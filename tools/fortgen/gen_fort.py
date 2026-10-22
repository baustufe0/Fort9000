#!/usr/bin/env python3
"""FORT 9000 - Generator fuer neue Forts-KI-Bauplaene (fort-t1f1-<Karte>-<Nr>.lua).

Idee:
  * Gelaende aus der .fwe-Karte lesen (Polygone).
  * Die Startfestung (Original-Knoten) aus einem vorhandenen Plan der Karte uebernehmen.
  * Ein Raster aus Zellen (ca. 100 x 110) ueber den Bauraum legen. Rasterpunkte nahe
    Original-Knoten werden auf diese gesetzt, Punkte im Fels werden zu Fundamenten auf
    der Felsoberflaeche oder fallen weg.
  * Eine Variante (Archetyp) waehlt, welche Zellen gebaut werden (Form), welche Waffen,
    Wirtschaft und Technik wohin kommen und in welcher Reihenfolge.
  * Front (zum Gegner) wird gepanzert, vor direkt feuernden Waffen kommen Tueren,
    ueber Moersern Tuer-Daecher. Diagonalen in Geraete-Zellen sind Hintergrundstreben.
  * Pruefungen: Knoten nicht im Fels, Streben nicht durch Fels und nicht zu lang,
    Bau-Reihenfolge (jeder Knoten wird von einem schon gebauten Knoten aus erzeugt),
    Technik-Voraussetzungen (Werkstatt vor Moerser usw.).

Die KI fuehrt Plaene robust aus: was nicht klappt, ueberspringt sie nach einigen
Versuchen ("Frustration"). Ein leicht fehlerhafter Plan bricht also nicht das Spiel.
"""
import argparse
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fwe import read_blocks            # noqa: E402
from terrain import Terrain              # noqa: E402
from fortplan import parse_plan, node_positions  # noqa: E402

MAX_LINK = 195
MIN_LINK = 45
DIRECT_WEAPONS = {"machinegun", "minigun", "sniper", "sniper2", "cannon", "laser"}
LOBBED_WEAPONS = {"mortar", "mortar2"}
LARGE = {"cannon", "laser"}
PREREQ = {"mortar": "workshop", "factory": "workshop", "cannon": "factory", "laser": "factory",
          "minigun": "upgrade", "sniper2": "upgrade", "mortar2": "upgrade", "mine2": "upgrade", "turbine2": "upgrade"}
UPGRADE_OF = {"minigun": "machinegun", "sniper2": "sniper", "mortar2": "mortar", "mine2": "mine", "turbine2": "turbine"}

# ----------------------------------------------------------------------------- Kartenkonfiguration

MAPS = {
    "Abyss": {
        "base_plan": "fort-t1f1-Abyss-1.lua",
        "fwe": "Abyss.fwe",
        "cols": [-2500, -2400, -2300, -2200, -2100, -2000, -1900, -1800, -1700],
        "rows": [-846, -746, -628, -502, -392, -250, -95, 5, 106, 206, 305, 405, 500, 600],
        "reactor": (-1995, 60),
        "snap": 45,
        "ground_snap": 25,
        # erprobte Plaetze aus dem Originalplan: (Knoten A, Knoten B, LinkT); Knoten als Position
        "tech_slots": {
            "workshop": [((-2001, 305), (-1901, 309), 0.05)],
            "upgrade": [((-2097, 3), (-1997, 5), 0.94)],
            "factory": [((-2002, 405), (-1901, 405), 0.94)],
        },
        "eco_slots": [((-2100, 200), (-1998, 206), 0.51), ((-2100, 400), (-2002, 405), 0.46),
                      ((-1998, 206), (-1898, 210), 0.52), ((-2100, 500), (-2002, 500), 0.55),
                      ((-2002, 500), (-1902, 500), 0.47)],
        # Bodenminen: Position + Kette von Knoten, die vorher stehen muessen (Positionen)
        "mines": [
            {"ground": (-2223.44, 650.0), "chain": [(-2100, 500), (-2100, 600), (-2150, 650)]},
            {"ground": (-2271.2, -750.0), "needs": [(-2200, -750)]},
            {"ground": (-2398.8, -750.0), "needs": [(-2300, -750)]},
            {"ground": (-2526.4, -750.0), "needs": [(-2400, -750)]},
        ],
        "header": "FortTeam = 1; FortId = 1; FortPos = { x = -1995.335815, y = 106.206329 }; ",
    },
    "Vanilla": {
        # Vorlagen-Karte: Startfestung kommt aus ai/forts/vanilla/mid (geteilt mit Penguin, Caverns, ...)
        "plan_dir": "ai/forts/vanilla/mid",
        "base_plan": "fort-t1f1-Template-1.lua",
        "fwe": "Vanilla.fwe",
        "solid_minus1": True,          # Bloecke mit Kennung -1 sind hier Fels
        "cols": [-3300, -3200, -3100, -3000, -2920, -2845, -2745],
        "rows": [-395, -295, -195, -95, 5, 105, 205, 308, 405, 503, 602, 700],
        "reactor": (-3040, 305),
        "keepout": [(-3140, -2900, 205, 405)],   # Reaktor + Rahmen: keine Zellen
        "eco_orig": False,             # Batterie/Speicher nicht in Zellen der Startfestung
        "weapon_min_w": 95,            # keine Waffen in schmalen Zellen (<95 breit)
        "mortar_avoid_roof": True,
        "turbine_narrow_first": True,
        "tech_spill": True,
        "aa_y": 250, "large_y": 100,
        "snap": 45,
        "ground_snap": 25,
        # erprobte Plaetze aus Template-1/-2: (Knoten A, Knoten B, LinkT)
        "tech_slots": {
            "workshop": [((-3096, 503), (-2996, 504), 0.05), ((-3200, 503), (-3096, 503), 0.96)],
            "upgrade": [((-3200, 600), (-3098, 602), 0.02)],
            "factory": [((-3200, 600), (-3098, 602), 0.04)],
        },
        "eco_slots": [((-3200, 403), (-3094, 407), 0.48), ((-3300, 510), (-3199, 509), 0.46)],
        "mines": [
            {"ground": (-3029.41, 700.0)},
            {"ground": (-3412.21, 700.0)},
            {"ground": (-3539.81, 700.0)},
        ],
        "header": "FortTeam = 1; FortId = 1; FortPos = { x = -2900.000000, y = 700.000000 }; ",
        "variants": "VANILLA_VARIANTS",
    },
}

# ----------------------------------------------------------------------------- Varianten (Archetypen)
# shape(x0, y0, x1, y1) -> True, wenn die Zelle mit diesen Ecken gebaut werden soll

VARIANTS = {
    "artillerie": {
        "title": "Artillerie-Turm: breiter Turm, viele Moerser oben, Werkstatt frueh",
        "shape": lambda x0, y0, x1, y1: (
            (y0 >= -628 and y1 <= -250 and x0 >= -2100 and x1 <= -1800) or
            (y0 >= -846 and y1 <= -628 and x0 >= -2400 and x1 <= -1900)),
        "plan": [
            ("aa", ["machinegun", "machinegun"]),
            ("eco", ["mine", "mine", "turbine", "turbine", "battery"]),
            ("tech", ["workshop"]),
            ("weapons", ["mortar", "mortar", "sniper", "mortar"]),
            ("eco", ["mine", "turbine", "store", "battery", "mine"]),
            ("tech", ["upgrade"]),
            ("weapons", ["mortar", "sniper", "machinegun"]),
            ("upgrades", ["mortar2", "mortar2", "minigun"]),
            ("eco", ["turbine", "battery"]),
        ],
        "armour_roof": True,
    },
    "scharfschuetzen": {
        "title": "Scharfschuetzen-Festung: schmaler hoher Turm mit vorgezogener Front, viele Sniper und Luftabwehr",
        "shape": lambda x0, y0, x1, y1: (
            (y0 >= -846 and y1 <= -250 and x0 >= -2100 and x1 <= -1900) or
            (y0 >= -628 and y1 <= -250 and x0 >= -1900 and x1 <= -1700) or
            (y0 >= -846 and y1 <= -746 and x0 >= -2400 and x1 <= -2100)),
        "plan": [
            ("aa", ["machinegun", "machinegun"]),
            ("eco", ["mine", "turbine", "mine", "battery"]),
            ("weapons", ["sniper", "sniper"]),
            ("tech", ["upgrade"]),
            ("weapons", ["sniper", "machinegun"]),
            ("eco", ["mine", "turbine", "store", "mine"]),
            ("upgrades", ["sniper2", "sniper2", "minigun"]),
            ("weapons", ["sniper", "machinegun"]),
            ("upgrades", ["sniper2", "minigun"]),
            ("eco", ["turbine", "battery"]),
        ],
        "armour_roof": True,
    },
    "schwer": {
        "title": "Schwere Front: breiter, stark gepanzerter Block, Fabrik frueh, Kanonen und Laser",
        "shape": lambda x0, y0, x1, y1: (
            (y0 >= -502 and y1 <= -250 and x0 >= -2100 and x1 <= -1700) or
            (y0 >= -846 and y1 <= -502 and x0 >= -2400 and x1 <= -1900) or
            (y0 >= 405 and y1 <= 600 and x0 >= -2100 and x1 <= -1900)),
        "plan": [
            ("aa", ["machinegun", "machinegun"]),
            ("eco", ["mine", "mine", "turbine", "battery", "turbine"]),
            ("tech", ["workshop"]),
            ("eco", ["mine", "store", "battery", "mine"]),
            ("tech", ["factory"]),
            ("weapons", ["cannon", "machinegun"]),
            ("eco", ["turbine", "battery"]),
            ("weapons", ["laser", "cannon"]),
            ("tech", ["upgrade"]),
            ("upgrades", ["minigun"]),
            ("weapons", ["sniper"]),
        ],
        "armour_roof": True,
    },
}


def _box(x0, x1, y0, y1):
    return lambda a, b, c, d: a >= x0 and c <= x1 and b >= y0 and d <= y1


def _union(*fs):
    return lambda a, b, c, d: any(f(a, b, c, d) for f in fs)


# Vanilla: Spalten -3300 .. -2745, Zeilen -395 .. 700. Reaktor bei (-3040, 305) (Sperrzone).
_V_LEFT = _box(-3300, -3100, 205, 700)       # linke Saeule bis zum Boden
_V_RIGHT = _box(-2920, -2745, 205, 700)      # rechte Saeule (Front, Luftabwehr)

VANILLA_VARIANTS = {
    "artillerie": {
        "title": "Artillerie-Turm: breite Plattform ueber dem Reaktor, Moerser oben unter Tuer-Dach, Werkstatt frueh",
        "shape": _union(_box(-3300, -2745, -195, 205), _V_LEFT, _V_RIGHT),
        "tech_slots": {"upgrade": [((-3200, 600), (-3098, 602), 0.02)]},
        "plan": [
            ("aa", ["machinegun"]),
            ("eco", ["mine", "mine", "turbine", "turbine", "battery"]),
            ("tech", ["workshop"]),
            ("weapons", ["mortar", "mortar", "sniper", "mortar"]),
            ("eco", ["mine", "turbine", "store", "battery"]),
            ("tech", ["upgrade"]),
            ("weapons", ["mortar", "sniper", "machinegun"]),
            ("upgrades", ["mortar2", "mortar2", "minigun"]),
            ("eco", ["turbine", "battery"]),
        ],
        "armour_roof": True,
    },
    "scharfschuetzen": {
        "title": "Scharfschuetzen-Festung: hoher schmaler Turm links, vorgezogene Front oben, Sniper + Luftabwehr",
        "shape": _union(_box(-3300, -3100, -395, 205), _box(-3100, -2745, -395, -195),
                        _box(-3100, -2745, 105, 205), _V_LEFT, _V_RIGHT),
        "tech_slots": {"upgrade": [((-3200, 600), (-3098, 602), 0.02)]},
        "plan": [
            ("aa", ["machinegun"]),
            ("eco", ["mine", "turbine", "mine", "battery"]),
            ("weapons", ["sniper", "sniper"]),
            ("tech", ["upgrade"]),
            ("weapons", ["sniper", "machinegun"]),
            ("eco", ["mine", "turbine", "store"]),
            ("upgrades", ["sniper2", "sniper2", "minigun"]),
            ("weapons", ["sniper", "machinegun"]),
            ("upgrades", ["sniper2", "minigun"]),
            ("eco", ["turbine", "battery"]),
        ],
        "armour_roof": True,
    },
    "schwer": {
        "title": "Schwere Front: niedriger, breiter, stark gepanzerter Block, Fabrik frueh, Kanone und Laser",
        "shape": _union(_box(-3300, -2745, 5, 205), _V_LEFT, _V_RIGHT),
        "plan": [
            ("aa", ["machinegun"]),
            ("eco", ["mine", "mine", "turbine", "battery", "turbine"]),
            ("tech", ["workshop"]),
            ("eco", ["mine", "store", "battery"]),
            ("tech", ["factory"]),
            ("weapons", ["cannon", "machinegun"]),
            ("eco", ["turbine", "battery"]),
            ("weapons", ["laser", "cannon"]),
            ("weapons", ["sniper", "machinegun"]),
        ],
        "armour_roof": True,
    },
    "wirtschaft": {
        "title": "Wirtschaftsfestung: erst alle Minen und Turbinen, dann gemischt Sniper/Moerser, wenig MGs",
        "shape": _union(_box(-3300, -2745, 5, 205), _box(-3300, -3000, -95, 5), _V_LEFT, _V_RIGHT),
        "tech_slots": {"upgrade": [((-3200, 600), (-3098, 602), 0.02)]},
        "plan": [
            ("eco", ["mine", "mine", "mine", "turbine", "turbine"]),
            ("aa", ["machinegun"]),
            ("eco", ["turbine", "turbine", "battery", "store"]),
            ("tech", ["workshop"]),
            ("weapons", ["sniper", "mortar", "mortar"]),
            ("tech", ["upgrade"]),
            ("upgrades", ["mine2", "mine2", "mine2", "turbine2", "turbine2"]),
            ("weapons", ["sniper", "mortar"]),
            ("eco", ["battery", "turbine"]),
            ("upgrades", ["mortar2", "sniper2"]),
        ],
        "armour_roof": True,
    },
}


# ----------------------------------------------------------------------------- Generator

class Plan:
    def __init__(self, cfg, terrain, base_pos, seed):
        self.cfg = cfg
        self.t = terrain
        self.rng = random.Random(seed)
        self.orig = {k: v for k, v in base_pos.items() if k < 10000}
        self.nodes = {}        # (i,j) -> (id, pos, kind) kind: orig/new/found
        self.next_id = 10000
        self.built_nodes = set(self.orig)
        self.links = {}        # frozenset(idA,idB) -> material (zuletzt gesetzt)
        self.actions = []
        self.pos = dict(self.orig)
        self.devices = {}      # cell -> device
        self.placed = []       # (device, a, b, t)
        self.problems = []
        self.tech_done = set()

    # --- Raster
    def build_lattice(self):
        cols, rows = self.cfg["cols"], self.cfg["rows"]
        for i, x in enumerate(cols):
            for j, y in enumerate(rows):
                p = (x, y)
                best = min(self.orig.items(), key=lambda kv: math.dist(kv[1], p))
                if math.dist(best[1], p) <= self.cfg["snap"]:
                    self.nodes[(i, j)] = (best[0], best[1], "orig")
                    continue
                surf, d = self.t.nearest_surface(p)
                if self.t.inside(p) or d < 12:
                    if d <= self.cfg["ground_snap"]:
                        q = (round(surf[0], 2), round(surf[1], 2))
                        self.nodes[(i, j)] = (None, q, "found")
                    continue
                self.nodes[(i, j)] = (None, p, "new")

    def node(self, ij):
        n = self.nodes.get(ij)
        if n is None:
            return None
        nid, p, kind = n
        if nid is None:
            nid = self.next_id
            self.next_id += 1
            self.nodes[ij] = (nid, p, kind)
            self.pos[nid] = p
        return self.nodes[ij]

    def cell_ok(self, i, j):
        corners = [(i, j), (i + 1, j), (i, j + 1), (i + 1, j + 1)]
        if any(c not in self.nodes for c in corners):
            return False
        ps = [self.nodes[c][1] for c in corners]
        edges = [(ps[0], ps[1]), (ps[2], ps[3]), (ps[0], ps[2]), (ps[1], ps[3]), (ps[0], ps[3])]
        for a, b in edges:
            L = math.dist(a, b)
            if L > MAX_LINK or L < MIN_LINK or not self.t.segment_clear(a, b):
                return False
        return True

    def select_cells(self, shape):
        cols, rows = self.cfg["cols"], self.cfg["rows"]
        self.cells = set()
        self.orig_cells = set()
        self.connectors = set()
        self.keep_cells = set()
        for i in range(len(cols) - 1):
            for j in range(len(rows) - 1):
                cx, cy = (cols[i] + cols[i + 1]) / 2, (rows[j] + rows[j + 1]) / 2
                if any(kx0 <= cx <= kx1 and ky0 <= cy <= ky1 for kx0, kx1, ky0, ky1 in self.cfg.get("keepout", [])):
                    self.keep_cells.add((i, j))
        for i in range(len(cols) - 1):
            for j in range(len(rows) - 1):
                if not self.cell_ok(i, j):
                    continue
                corners = [(i, j), (i + 1, j), (i, j + 1), (i + 1, j + 1)]
                if all(self.nodes[c][2] == "orig" for c in corners):
                    self.orig_cells.add((i, j))
                    continue
                if (i, j) in self.keep_cells:
                    continue
                x0, y0 = cols[i], rows[j]
                x1, y1 = cols[i + 1], rows[j + 1]
                if shape(x0, y0, x1, y1):
                    self.cells.add((i, j))
                elif sum(self.nodes[c][2] == "orig" for c in corners) >= 1:
                    self.connectors.add((i, j))
        # Verbindungszellen nur, wenn sie an eine Form-Zelle grenzen
        def neigh(c):
            i, j = c
            return ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1))
        self.cells |= {c for c in self.connectors if any(n in self.cells for n in neigh(c))}
        # nur Zellen behalten, die ueber Kanten mit der Startfestung verbunden sind
        # Startpunkte: Zellen der Startfestung und alle Zellen mit einem Original-Knoten als Ecke
        reach = set(self.orig_cells) | {c for c in self.cells
                                         if any(self.nodes[x][2] == "orig" for x in
                                                ((c[0], c[1]), (c[0] + 1, c[1]), (c[0], c[1] + 1), (c[0] + 1, c[1] + 1)))}
        frontier = list(reach)
        while frontier:
            c = frontier.pop()
            for n in neigh(c):
                if n in self.cells and n not in reach:
                    reach.add(n)
                    frontier.append(n)
        dropped = self.cells - reach
        self.cells &= reach
        if dropped:
            self.problems.append("%d Zellen ohne Verbindung zur Startfestung weggelassen" % len(dropped))
        self.all_cells = self.cells | self.orig_cells

    # --- Eigenschaften von Zellen
    def is_front(self, c):
        n = (c[0] + 1, c[1])
        return n not in self.all_cells and n not in self.keep_cells

    def cell_w(self, c):
        return abs(self.nodes[(c[0] + 1, c[1] + 1)][1][0] - self.nodes[(c[0], c[1] + 1)][1][0])

    def is_top(self, c):
        return (c[0], c[1] - 1) not in self.all_cells

    def near_reactor(self, c):
        cols, rows = self.cfg["cols"], self.cfg["rows"]
        cx = (cols[c[0]] + cols[c[0] + 1]) / 2
        cy = (rows[c[1]] + rows[c[1] + 1]) / 2
        return math.dist((cx, cy), self.cfg["reactor"]) < 120

    # --- Aktionen
    def _fmt(self, p):
        return "x = %.2f, y = %.2f" % (p[0], p[1])

    def ensure_node(self, ij, via_material="bracing"):
        """Knoten ij bauen (falls noetig) - von einem schon gebauten Nachbarn aus."""
        nid, p, kind = self.node(ij)
        if nid in self.built_nodes:
            return nid
        i, j = ij
        cand = []
        for di, dj in ((-1, 0), (1, 0), (0, 1), (0, -1), (-1, 1), (1, 1), (-1, -1), (1, -1)):
            n = self.nodes.get((i + di, j + dj))
            if n and n[0] in self.built_nodes:
                d = math.dist(n[1], p)
                if MIN_LINK <= d <= MAX_LINK and self.t.segment_clear(n[1], p):
                    cand.append((d, (i + di, j + dj)))
        if not cand:
            return None
        if kind == "found":
            # Fundament von oben/schraeg bauen, nicht seitlich entlang des Bodens
            cand.sort(key=lambda dc: (dc[1][1] == j, dc[0]))
        else:
            cand.sort()
        src = self.nodes[cand[0][1]]
        self.actions.append('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "%s" },'
                            % (src[0], self._fmt(src[1]), nid, self._fmt(p), via_material))
        self.built_nodes.add(nid)
        self.links[frozenset((src[0], nid))] = via_material
        return nid

    def link(self, a_ij, b_ij, material):
        a, b = self.nodes[a_ij], self.nodes[b_ij]
        key = frozenset((a[0], b[0]))
        if self.links.get(key) == material:
            return
        self.actions.append('{ Type = CREATE_LINK, OriginalNodeAId = %d, PosA = {%s }, OriginalNodeBId = %d, PosB = { %s }, MaterialSaveName = "%s" },'
                            % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), material))
        self.links[key] = material

    def spans_right(self, c):
        """True, wenn ein grosses Geraet ueber die rechte Kante von c in die Nachbarzelle reicht."""
        a, b = self.devices.get(c) or "", self.devices.get((c[0] + 1, c[1])) or ""
        return bool(a and b) and (a + "+" == b or b + "+" == a)

    def edge_material(self, c, edge):
        """Material fuer eine Zellkante: front/roof gepanzert, Tueren vor Waffen."""
        dev = self.devices.get(c)
        if edge == "right" and self.spans_right(c):
            return "backbracing"
        if edge == "right" and self.is_front(c):
            return "door" if dev in DIRECT_WEAPONS else "armour"
        if edge == "top" and self.is_top(c) and self.variant.get("armour_roof"):
            if dev in LOBBED_WEAPONS:
                return "door"
            if self.roof_device.get(c):
                return "bracing"
            return "armour"
        return "bracing"

    def build_cell(self, c):
        if c in self.built_cells:
            return True
        i, j = c
        tl, tr, bl, br = (i, j), (i + 1, j), (i, j + 1), (i + 1, j + 1)
        orig = c in self.orig_cells
        for ij in (tl, tr, bl, br):
            if self.nodes[ij][0] not in self.built_nodes and self.ensure_node(ij) is None:
                # Nachbarzelle zuerst bauen
                return False
        mine_cell = self.devices.get(c) == "mine-platz"
        if not orig:
            if not mine_cell:   # auf Minenplaetzen keine Strebe auf dem Fels (sonst ist die Mine blockiert)
                self.link(bl, br, "bracing")
            self.link(tl, bl, "backbracing" if self.spans_right((i - 1, j)) else "bracing")
            self.link(tr, br, self.edge_material(c, "right"))
            self.link(tl, tr, self.edge_material(c, "top"))
            diag = "backbracing" if c in self.devices or self.devices.get((i - 1, j)) in LARGE else "bracing"
            if mine_cell:
                diag = "backbracing"
            if (i + j) % 2 == 0:
                self.link(tl, br, diag)
            else:
                self.link(tr, bl, diag)
        else:
            self.link(bl, br, "bracing")
            if self.is_front(c):
                self.link(tr, br, self.edge_material(c, "right"))
        self.built_cells.add(c)
        return True

    def build_cell_path(self, c):
        """Zelle bauen; wenn noetig zuerst die Zellen auf dem Weg von der Startfestung."""
        if self.build_cell(c):
            return True
        # Breitensuche von gebauten Zellen zu c
        start = [x for x in self.built_cells]
        prev = {x: None for x in start}
        q = list(start)
        while q:
            x = q.pop(0)
            if x == c:
                break
            for n in ((x[0] + 1, x[1]), (x[0] - 1, x[1]), (x[0], x[1] + 1), (x[0], x[1] - 1)):
                if n in self.all_cells and n not in prev:
                    prev[n] = x
                    q.append(n)
        if c not in prev:
            self.problems.append("Zelle %s nicht erreichbar" % (c,))
            return False
        path = []
        x = c
        while x is not None:
            path.append(x)
            x = prev[x]
        for x in reversed(path):
            if not self.build_cell(x):
                self.problems.append("Zelle %s konnte nicht gebaut werden" % (x,))
                return False
        return True

    def place_on_floor(self, c, dev, t=0.5):
        i, j = c
        a, b = self.nodes[(i, j + 1)], self.nodes[(i + 1, j + 1)]
        self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                            % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t, dev))
        self.placed.append((dev, a[1], b[1], t, c))

    def place_on_roof(self, c, dev, t=0.5):
        i, j = c
        a, b = self.nodes[(i, j)], self.nodes[(i + 1, j)]
        self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                            % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t, dev))
        self.placed.append((dev, a[1], b[1], t, ("roof",) + c))

    def node_at(self, p, tol=30):
        for ij, (nid, q, kind) in self.nodes.items():
            if math.dist(p, q) <= tol:
                return ij
        return None

    # --- Plaetze waehlen
    def free_cells(self, pred):
        cells = [c for c in sorted(self.all_cells) if c not in self.devices and not self.near_reactor(c) and pred(c)]
        return cells

    def choose_weapon_cell(self, dev):
        rows = self.cfg["rows"]
        mw = self.cfg.get("weapon_min_w", 0)
        if mw:
            wide = lambda c: self.cell_w(c) >= mw
        else:
            wide = lambda c: True
        avoid_roof = self.cfg.get("mortar_avoid_roof")
        if dev in LOBBED_WEAPONS:
            cands = self.free_cells(lambda c: self.is_top(c) and c in self.cells and wide(c) and not (avoid_roof and self.roof_device.get(c)))
            cands.sort(key=lambda c: (-c[0], c[1]))     # oben, moeglichst weit vorn
        elif dev in LARGE:
            cands = self.free_cells(lambda c: self.is_front(c) and c in self.cells and (c[0] - 1, c[1]) in self.all_cells
                                    and (c[0] - 1, c[1]) not in self.devices and wide(c))
            cands.sort(key=lambda c: abs(rows[c[1]] - self.cfg.get("large_y", -300)))
        else:
            cands = self.free_cells(lambda c: self.is_front(c) and c in self.cells and wide(c))
            if dev == "machinegun":
                cands.sort(key=lambda c: (abs(rows[c[1]] - self.cfg.get("aa_y", -250)), -c[0]))   # nahe Reaktorhoehe: Luftabwehr
            else:
                cands.sort(key=lambda c: (rows[c[1]], -c[0]))               # Sniper eher oben
        if not cands:
            return None
        # etwas Zufall unter den besten drei, damit Varianten sich unterscheiden
        return cands[self.rng.randrange(min(2, len(cands)))]

    def choose_eco_cell(self):
        cands = self.free_cells(lambda c: not self.is_front(c) and (c in self.cells or self.cfg.get("eco_orig", True)))
        cands.sort(key=lambda c: (-self.cfg["rows"][c[1]], c[0]))
        return cands[0] if cands else None

    def choose_turbine_roof(self):
        cands = [c for c in sorted(self.cells)
                 if self.is_top(c) and not self.is_front(c) and not self.roof_device.get(c)
                 and self.devices.get(c) not in LOBBED_WEAPONS]
        if self.cfg.get("turbine_narrow_first"):
            cands.sort(key=lambda c: (self.cell_w(c) >= 95, self.cfg["rows"][c[1]], -c[0]))
        else:
            cands.sort(key=lambda c: (self.cfg["rows"][c[1]], c[0]))
        return cands[0] if cands else None

    # --- Hauptablauf
    def generate(self, variant):
        self.variant = variant
        self.tech_slots = dict(self.cfg["tech_slots"])
        self.tech_slots.update(variant.get("tech_slots", {}))
        self.build_lattice()
        self.select_cells(variant["shape"])
        self.built_cells = set()
        self.roof_device = {}
        self.mines_done = 0
        # Startfestung gilt als gebaut
        for c in self.orig_cells:
            self.built_cells.add(c)
        # Zellen, deren Boden auf einem Minenplatz liegt, bleiben frei (Mine steht auf dem Fels darunter)
        for m in self.cfg["mines"]:
            gx, gy = m["ground"]
            for c in self.all_cells:
                a, b = self.nodes[(c[0], c[1] + 1)][1], self.nodes[(c[0] + 1, c[1] + 1)][1]
                if min(a[0], b[0]) - 40 <= gx <= max(a[0], b[0]) + 40 and abs((a[1] + b[1]) / 2 - gy) < 20:
                    self.devices[c] = "mine-platz"
        for step, items in variant["plan"]:
            for dev in items:
                self.add(step, dev)
        # restliche Zellen der Form fertig bauen (Struktur + Panzerung)
        for c in sorted(self.cells, key=lambda c: (self.cfg["rows"][c[1]], c[0])):
            self.build_cell_path(c)
        return self

    def add(self, step, dev):
        if PREREQ.get(dev) and PREREQ[dev] not in self.tech_done and dev not in UPGRADE_OF:
            self.problems.append("%s ohne %s - vorgezogen" % (dev, PREREQ[dev]))
            self.add("tech", PREREQ[dev])
        if step == "upgrades":
            base = UPGRADE_OF[dev]
            if "upgrade" not in self.tech_done:
                self.add("tech", "upgrade")
            for (d, a, b, t, c) in self.placed:
                if d == base:
                    self.placed.remove((d, a, b, t, c))
                    if c is None:       # Bodenmine aufruesten
                        self.actions.append('{ Type = CREATE_DEVICE, GroundPosition = { %s }, LinkT = 1.57, DeviceSaveName = "%s" },'
                                            % (self._fmt(a), dev))
                        self.placed.append((dev, a, b, t, None))
                        return
                    if c[0] == "roof":
                        self.place_on_roof(c[1:], dev, t)
                    else:
                        self.devices[c] = dev
                        self.place_on_floor(c, dev, t)
                    return
            self.problems.append("kein %s zum Aufruesten auf %s" % (base, dev))
            return
        if dev == "mine":
            return self.add_mine()
        if dev == "turbine":
            c = self.choose_turbine_roof()
            if c is None or not self.build_cell_path(c):
                self.problems.append("kein Dachplatz fuer Turbine")
                return
            self.roof_device[c] = dev
            i, j = c
            self.link((i, j), (i + 1, j), "bracing")
            self.place_on_roof(c, dev)
            return
        if step == "tech":
            if dev in self.tech_done:
                return
            for (pa, pb, t) in self.tech_slots.get(dev, []):
                ia, ib = self.node_at(pa), self.node_at(pb)
                if ia and ib:
                    c = (ia[0], ia[1] - 1)
                    if c in self.devices:
                        continue
                    self.devices[c] = dev
                    self.devices[(c[0] + 1, c[1])] = dev + "+"   # zweite Zellhaelfte belegt
                    if self.cfg.get("tech_spill") and t <= 0.1 and (c[0] - 1, c[1]) not in self.devices:
                        self.devices[(c[0] - 1, c[1])] = dev + "+"   # Geraet am linken Linkende ragt nach links
                    if c in self.all_cells:
                        self.build_cell_path(c)
                    if self.ensure_node(ia) is None or self.ensure_node(ib) is None:
                        continue
                    self.link(ia, ib, "bracing")
                    a, b = self.nodes[ia], self.nodes[ib]
                    self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                                        % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t, dev))
                    self.placed.append((dev, a[1], b[1], t, c))
                    self.tech_done.add(dev)
                    return
            self.problems.append("kein Platz fuer %s" % dev)
            return
        if dev in ("battery", "store"):
            c = self.choose_eco_cell()
            if c is None or not self.build_cell_path(c):
                self.problems.append("kein Platz fuer %s" % dev)
                return
            self.devices[c] = dev
            self.place_on_floor(c, dev)
            return
        # Waffen
        c = self.choose_weapon_cell(dev)
        if c is None:
            self.problems.append("kein Platz fuer %s" % dev)
            return
        self.devices[c] = dev
        if dev in LARGE:
            self.devices[(c[0] - 1, c[1])] = dev + "+"
        if not self.build_cell_path(c):
            return
        # Front/Dach nach Waffenwahl neu setzen (Tuer statt Panzerung)
        i, j = c
        if self.is_front(c):
            self.link((i + 1, j), (i + 1, j + 1), self.edge_material(c, "right"))
        if dev in LOBBED_WEAPONS and self.is_top(c):
            self.link((i, j), (i + 1, j), "door")
        self.place_on_floor(c, dev, 0.4 if dev in LARGE else 0.5)

    def add_mine(self):
        spots = self.cfg["mines"]
        while self.mines_done < len(spots):
            m = spots[self.mines_done]
            self.mines_done += 1
            ok = True
            if "chain" in m:
                prev = None
                for p in m["chain"]:
                    ij = self.node_at(p)
                    if ij is None:
                        # zusaetzlicher Knoten ausserhalb des Rasters
                        ij = ("x",) + p
                        self.nodes[ij] = (None, p, "found")
                    nid = self.node(ij)[0]
                    if nid not in self.built_nodes:
                        if prev is None:
                            ok = False
                            break
                        src = self.nodes[prev]
                        self.actions.append('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "bracing" },'
                                            % (src[0], self._fmt(src[1]), nid, self._fmt(self.nodes[ij][1])))
                        self.built_nodes.add(nid)
                    prev = ij
            for p in m.get("needs", []):
                ij = self.node_at(p)
                if ij is None:
                    ok = False
                    break
                # Zelle ueber dem Fundament bauen
                cell = None
                for c in sorted(self.all_cells):
                    if ij in ((c[0], c[1] + 1), (c[0] + 1, c[1] + 1)):
                        cell = c
                        break
                if cell is None or not self.build_cell_path(cell):
                    ok = False
                    break
            if ok:
                g = m["ground"]
                self.actions.append('{ Type = CREATE_DEVICE, GroundPosition = { %s }, LinkT = 1.57, DeviceSaveName = "mine" },' % self._fmt(g))
                self.placed.append(("mine", g, g, 0, None))
                return
        self.problems.append("kein Minenplatz mehr")

    # --- Pruefung und Ausgabe
    def validate(self):
        errors = []
        built = set(self.orig)
        pos = dict(self.orig)
        import re
        for k, line in enumerate(self.actions):
            m = re.search(r"Type = (\w+)", line).group(1)
            ids = [int(x) for x in re.findall(r"OriginalNode[AB]Id = (\d+)", line)]
            pts = [(float(a), float(b)) for a, b in re.findall(r"x = (-?[\d.]+), y = (-?[\d.]+)", line)]
            if m == "CREATE_NODE":
                if ids[0] not in built:
                    errors.append("Aktion %d: Knoten %d wird von nicht gebautem %d erzeugt" % (k, ids[1], ids[0]))
                built.add(ids[1])
                pos[ids[1]] = pts[1]
            elif m in ("CREATE_LINK", "CREATE_DEVICE") and ids:
                for x in ids:
                    if x not in built:
                        errors.append("Aktion %d: Knoten %d noch nicht gebaut" % (k, x))
            if len(pts) >= 2 and m in ("CREATE_NODE", "CREATE_LINK"):
                L = math.dist(pts[0], pts[1])
                if L > MAX_LINK + 1:
                    errors.append("Aktion %d: Strebe zu lang (%.0f)" % (k, L))
                if not self.t.segment_clear(pts[0], pts[1]):
                    errors.append("Aktion %d: Strebe geht durch Fels" % k)
        for nid, p in pos.items():
            if nid >= 10000 and self.t.inside((p[0], p[1] - 3)) and self.t.inside((p[0] + 3, p[1])):
                errors.append("Knoten %d liegt im Fels" % nid)
        seen = set()
        for line in self.actions:
            m = re.search(r'DeviceSaveName = "(\w+)"', line)
            if m:
                d = m.group(1)
                if PREREQ.get(d) and PREREQ[d] not in seen:
                    errors.append("%s vor %s gebaut" % (d, PREREQ[d]))
                seen.add(d)
        return errors

    def write(self, path, title):
        # Kopf exakt wie bei aufgezeichneten Plaenen (die KI rechnet mit diesen Zeilennummern)
        head = ("-- Fort recorded for AI replay\n"
                "CREATE_NODE = 1\nDESTROY_NODE = 2\nCREATE_LINK = 3\nDESTROY_LINK = 4\nCREATE_DEVICE = 5\nDESTROY_DEVICE = 6\n")
        tail = "-- Erzeugt von Claude AI (tools/gen_fort.py): %s\n" % title
        with open(path, "w", encoding="ascii", newline="\r\n") as f:
            f.write(head + self.cfg["header"] + "\n\nFort =\n{\n" + "\n".join(self.actions) + "\n}\n" + tail)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--maps", required=True, help="Ordner data/maps")
    ap.add_argument("--map", default="Abyss")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--start-number", type=int, default=2)
    args = ap.parse_args()
    cfg = MAPS[args.map]
    mdir = os.path.join(args.maps, args.map)
    _, blocks = read_blocks(os.path.join(mdir, cfg["fwe"]))
    polys = [pts for flag, pts in blocks if flag >= 0 or (cfg.get("solid_minus1") and flag == -1)]
    terrain = Terrain(polys)
    plan_dir = os.path.join(os.path.dirname(os.path.abspath(args.maps)), cfg["plan_dir"]) if cfg.get("plan_dir") else mdir
    _, base = parse_plan(os.path.join(plan_dir, cfg["base_plan"]))
    base_pos = node_positions(base)
    os.makedirs(args.out, exist_ok=True)
    variants = globals()[cfg["variants"]] if cfg.get("variants") else VARIANTS
    for n, (key, var) in enumerate(variants.items()):
        p = Plan(cfg, terrain, base_pos, args.seed * 100 + n).generate(var)
        errors = p.validate()
        name = "fort-t1f1-%s-%d.lua" % (args.map, args.start_number + n)
        p.write(os.path.join(args.out, name), var["title"])
        devs = {}
        for line in p.actions:
            if "CREATE_DEVICE" in line:
                d = line.split('DeviceSaveName = "')[1].split('"')[0]
                devs[d] = devs.get(d, 0) + 1
        print("%s [%s] %d Aktionen, Geraete: %s" % (name, key, len(p.actions), ", ".join("%s:%d" % kv for kv in sorted(devs.items()))))
        for e in errors:
            print("   FEHLER:", e)
        for pr in p.problems:
            print("   Hinweis:", pr)


if __name__ == "__main__":
    main()
