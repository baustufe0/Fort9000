#!/usr/bin/env python3
"""FORT 9000 - generator for new Forts AI build plans (fort-t1f1-<map>-<no>.lua).

Idea:
  * Read terrain from the .fwe map (polygons).
  * Take the starting fort (original nodes) from an existing plan of the map.
  * Lay a grid of cells (approx. 100 x 110) over the building area. Grid points near
    original nodes are snapped to them, points inside rock become foundations on
    the rock surface or are dropped.
  * A variant (archetype) chooses which cells are built (shape), which weapons,
    economy and tech go where, and in which order.
  * The front (facing the enemy) is armoured, doors go in front of direct-fire weapons,
    door roofs over mortars. Diagonals in device cells are background braces.
  * Checks: nodes not in rock, links not through rock and not too long,
    build order (every node is created from an already built node),
    tech prerequisites (workshop before mortar, etc.).

The AI executes plans robustly: what does not work, it skips after a few
attempts ("frustration"). A slightly faulty plan therefore does not break the game.
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

# ----------------------------------------------------------------------------- Map configuration

MAPS = {
    "Abyss": {
        "base_plan": "fort-t1f1-Abyss-1.lua",
        "fwe": "Abyss.fwe",
        "cols": [-2500, -2400, -2300, -2200, -2100, -2000, -1900, -1800, -1700],
        "rows": [-846, -746, -628, -502, -392, -250, -95, 5, 106, 206, 305, 405, 500, 600],
        "reactor": (-1995, 60),
        "snap": 45,
        "ground_snap": 25,
        # proven slots from the original plan: (node A, node B, LinkT); nodes given as positions
        "tech_slots": {
            "workshop": [((-2001, 305), (-1901, 309), 0.05)],
            "upgrade": [((-2097, 3), (-1997, 5), 0.94)],
            "factory": [((-2002, 405), (-1901, 405), 0.94)],
        },
        "eco_slots": [((-2100, 200), (-1998, 206), 0.51), ((-2100, 400), (-2002, 405), 0.46),
                      ((-1998, 206), (-1898, 210), 0.52), ((-2100, 500), (-2002, 500), 0.55),
                      ((-2002, 500), (-1902, 500), 0.47)],
        # ground mines: position + chain of nodes that must exist beforehand (positions)
        "mines": [
            {"ground": (-2223.44, 650.0), "chain": [(-2100, 500), (-2100, 600), (-2150, 650)]},
            {"ground": (-2271.2, -750.0), "needs": [(-2200, -750)]},
            {"ground": (-2398.8, -750.0), "needs": [(-2300, -750)]},
            {"ground": (-2526.4, -750.0), "needs": [(-2400, -750)]},
        ],
        "header": "FortTeam = 1; FortId = 1; FortPos = { x = -1995.335815, y = 106.206329 }; ",
    },
    "Vanilla": {
        # template map: starting fort comes from ai/forts/vanilla/mid (shared with Penguin, Caverns, ...)
        "plan_dir": "ai/forts/vanilla/mid",
        "base_plan": "fort-t1f1-Template-1.lua",
        "fwe": "Vanilla.fwe",
        "solid_minus1": True,          # blocks with id -1 are rock here
        # front column at -2945/-2845 = the prow of the starting fort (rock ends at x=-2900, nothing beyond -2845)
        # back columns -3500/-3400: room for turbines and eco behind the fort (rock reaches back to -3600)
        "cols": [-3500, -3400, -3300, -3200, -3100, -3000, -2945, -2845],
        "rows": [-395, -295, -195, -95, 5, 105, 205, 308, 405, 503, 602, 700],
        "reactor": (-3040, 305),
        "keepout": [(-3140, -2900, 205, 405)],   # reactor + frame: no cells
        # the rock ends at x=-2900: no cells hanging beyond the cliff without foundations
        "require_support": True,
        # rules from the guide "How to be a PRO at Vanilla Forts": crossbraced lower layers,
        # build from the bottom up, no heavy metal roof
        "crossbrace_y": -1000,         # every cell crossbraced (|X|), like big vanilla forts
        "crossbrace_late_y": 405,      # ... but above the lower layers only in a final pass (weapons first)
        "crossbrace_now_x": -3100,     # ... except the front weapon column and the prow
        "bottom_up": True,
        "light_roof": True,
        # after the first test match: the ground row of the back column is taken by the starting
        # store/battery (CS_OCCUPIED), turbines on the 55-wide cell block their neighbours and the laser
        "use_eco_slots": True,
        "eco_no_ground": True,
        "turbine_min_w": 90,
        # turbine gallery: turbines stand on the floor of the storey just above the starting fort (y=205)
        "turbine_floor_y": 205,
        "turbine_row_open": True,      # only background bracing in that storey, so the wind gets through
        # front cell of the turbine row split at half height: two stacked sandbags shield the turbines.
        # Both stand side by side on the half-height strut (test match: the floor spot on the
        # starting fort's top beam was blocked).
        "split_cell": (-2945, 105), "sandbag_slots": [("mid", 0.27), ("mid", 0.73)],
        "turbine_cheap_first": True,
        "eco_orig": False,             # no battery/storage in cells of the starting fort
        "weapon_min_w": 95,            # no weapons in narrow cells (<95 wide)
        "mortar_avoid_roof": True,
        "turbine_narrow_first": True,
        "tech_spill": True,
        "aa_y": 250, "large_y": -195,         # large weapons in the main column, two storeys above the open turbine row (test match: CS_UNSTABLE right above it)
        "snap": 45,
        "ground_snap": 25,
        # proven slots from Template-1/-2: (node A, node B, LinkT)
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

# ----------------------------------------------------------------------------- Variants (archetypes)
# shape(x0, y0, x1, y1) -> True if the cell with these corners should be built

VARIANTS = {
    "artillerie": {
        "title": "Artillery tower: wide tower, many mortars on top, workshop early",
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
        "title": "Sniper fortress: narrow tall tower with advanced front, many snipers and anti-air",
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
        "title": "Heavy front: wide, heavily armoured block, factory early, cannons and lasers",
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


# Vanilla: columns -3500 .. -2845, rows -395 .. 700. Reactor at (-3040, 305) (keep-out zone).
# The rock ends at x=-2900 and the starting fort leans forward, so the forts grow backwards
# (left column on new foundations) and upwards over the starting fort, never out over the cliff.
# Every variant starts with economy (3rd mine + turbines in the first seconds), as the guide advises.
_V_BACK = _box(-3500, -3100, 205, 700)       # back block down to the ground (counterweight, eco, tech)


def _v_terrace(*steps):
    """Storeys over the starting fort roof (y=205), each given as (top y, front x): the storeys step
    back, so every storey has its own front cell for a weapon and roof space behind it."""
    fs, y1 = [], 205
    for y0, x1 in steps:
        fs.append(_box(-3500, x1, y0, y1))
        y1 = y0
    return _union(*fs)


_V_STEPS = _v_terrace((5, -2845), (-95, -2845), (-195, -3100))
# tall rectangle like big vanilla forts: a weapon column at the front over 6 storeys, mortars on top,
# turbine gallery above the starting fort. The tall front stands at x=-3000 over the core frame;
# the prow (-3000..-2845, beyond the cliff edge at -2900) only carries two light storeys.
_V_TALL = _union(_box(-3500, -3000, -395, 205), _box(-3000, -2845, 5, 205))

VANILLA_VARIANTS = {
    # Every variant ends with a late-game block (more anti-air, more weapons, upgrades), so the AI
    # does not run out of things to build while metal piles up (test match 22.10.2026: plan done
    # after 5.4 min, then minutes at the storage cap). The raised back towers give extra front
    # cells that look out over the deck.
    "artillerie": {
        "title": "Artillery deck: two-storey deck over the starting fort, mortars on top under doors, workshop early",
        "shape": _union(_V_TALL, _V_BACK),
        "tech_slots": {"upgrade": [((-3200, 600), (-3098, 602), 0.02)]},
        "plan": [
            ("eco", ["mine", "turbine", "mine"]),
            ("aa", ["machinegun"]),
            ("weapons", ["sniper"]),
            ("eco", ["turbine"]),
            ("defence", ["sandbags", "sandbags"]),
            ("tech", ["workshop"]),
            ("weapons", ["mortar", "mortar"]),
            ("eco", ["mine", "battery"]),
            ("tech", ["upgrade"]),
            ("upgrades", ["mortar2", "mortar2"]),
            ("eco", ["turbine", "store"]),
            # late game
            ("aa", ["machinegun", "machinegun"]),
            ("weapons", ["mortar", "sniper"]),
            ("upgrades", ["mortar2", "sniper2"]),
            ("eco", ["turbine", "battery"]),
            ("upgrades", ["mine2", "mine2", "turbine2"]),
        ],
    },
    "scharfschuetzen": {
        "title": "Sniper tower: deck over the starting fort plus a tower at the back, snipers in front, upgrade early",
        "shape": _union(_V_TALL, _V_BACK),
        "tech_slots": {"upgrade": [((-3200, 600), (-3098, 602), 0.02)]},
        "plan": [
            ("eco", ["mine", "turbine", "mine"]),
            ("aa", ["machinegun"]),
            ("weapons", ["sniper", "sniper"]),
            ("eco", ["turbine"]),
            ("defence", ["sandbags", "sandbags"]),
            ("tech", ["upgrade"]),
            ("eco", ["mine", "battery"]),
            ("upgrades", ["sniper2", "minigun"]),
            ("weapons", ["sniper"]),
            ("eco", ["turbine", "store"]),
            ("upgrades", ["sniper2", "sniper2"]),
            # late game
            ("aa", ["machinegun", "machinegun"]),
            ("weapons", ["sniper"]),
            ("upgrades", ["sniper2", "mine2", "mine2"]),
            ("eco", ["turbine", "battery"]),
            ("upgrades", ["turbine2"]),
        ],
    },
    "schwer": {
        "title": "Laser deck: factory early, plasma laser in the prow, extra store/battery for it, no cannon",
        "shape": _union(_V_TALL, _V_BACK),
        "plan": [
            ("eco", ["mine", "turbine", "mine"]),
            ("aa", ["machinegun"]),
            ("weapons", ["sniper"]),
            ("eco", ["turbine"]),
            ("defence", ["sandbags", "sandbags"]),
            ("tech", ["workshop"]),
            ("eco", ["mine", "battery", "store"]),
            # a laser shot needs a lot of energy: turbines first (test match: laser stood, never fired)
            ("eco", ["turbine", "turbine"]),
            ("tech", ["factory"]),
            ("weapons", ["laser"]),
            ("eco", ["turbine"]),
            ("weapons", ["machinegun"]),
            # late game: more anti-air and snipers, a mortar, more storage for repairs
            ("aa", ["machinegun", "machinegun"]),
            ("weapons", ["sniper", "mortar"]),
            ("eco", ["battery", "turbine"]),
            ("weapons", ["sniper"]),
        ],
    },
    "wirtschaft": {
        "title": "Economy deck: all mines and turbines first, then snipers and mortars, mine/turbine upgrades",
        "shape": _union(_V_TALL, _V_BACK),
        "tech_slots": {"upgrade": [((-3200, 600), (-3098, 602), 0.02)]},
        "plan": [
            ("eco", ["mine", "turbine", "mine", "mine"]),
            ("aa", ["machinegun"]),
            ("weapons", ["sniper"]),
            ("eco", ["turbine", "turbine", "battery"]),
            ("defence", ["sandbags", "sandbags"]),
            ("tech", ["workshop"]),
            ("weapons", ["mortar", "sniper"]),
            ("tech", ["upgrade"]),
            ("upgrades", ["mine2", "mine2", "turbine2"]),
            ("weapons", ["mortar", "sniper"]),
            ("eco", ["store", "turbine"]),
            ("upgrades", ["mortar2", "sniper2"]),
            # late game
            ("aa", ["machinegun", "machinegun"]),
            ("weapons", ["sniper", "mortar"]),
            ("upgrades", ["mortar2", "sniper2", "mine2", "turbine2"]),
            ("eco", ["battery"]),
        ],
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
        self.links = {}        # frozenset(idA,idB) -> material (last set)
        self.actions = []
        self.pos = dict(self.orig)
        self.devices = {}      # cell -> device
        self.placed = []       # (device, a, b, t)
        self.problems = []
        self.tech_done = set()

    # --- Grid
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
        # connecting cells only if they border a shape cell
        def neigh(c):
            i, j = c
            return ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1))
        self.cells |= {c for c in self.connectors if any(n in self.cells for n in neigh(c))}
        if self.cfg.get("require_support"):
            self.filter_supported()
        # keep only cells connected to the starting fort via edges
        # start points: cells of the starting fort and all cells with an original node as a corner
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
            self.problems.append("%d cells without connection to the starting fort omitted" % len(dropped))
        self.all_cells = self.cells | self.orig_cells

    def filter_supported(self):
        """Drop cells that would hang in the air (e.g. beyond a cliff edge).
        A node is held if it is an original node, a foundation, or the top corner of a supported cell.
        A cell is supported if both bottom corners are held, or if it lies in a horizontal run of
        at most max_bridge cells whose outer bottom corners are held (a truss over a gap)."""
        # held node -> cell that holds it up (None: original node or foundation, always there);
        # self.deps[c] = cells that must be built before c, so that c never hangs in the air
        # while the fort is being built (build_cell builds them first)
        held = {ij: None for ij, n in self.nodes.items() if n[2] in ("orig", "found")}
        sup = set(self.orig_cells)
        for i, j in sup:
            held.setdefault((i, j), None)
            held.setdefault((i + 1, j), None)
        via = {}       # supported cell -> the held nodes it rests on

        def hold_top(c):
            held.setdefault((c[0], c[1]), c)
            held.setdefault((c[0] + 1, c[1]), c)

        max_bridge = self.cfg.get("max_bridge", 3)
        changed = True
        while changed:
            changed = False
            for c in sorted(self.cells - sup, key=lambda c: -c[1]):
                i, j = c
                if (i, j + 1) in held and (i + 1, j + 1) in held:
                    sup.add(c)
                    via[c] = [(i, j + 1), (i + 1, j + 1)]
                    hold_top(c)
                    changed = True
            # bridges: runs of unsupported cells in one row, held at both outer ends
            for c in sorted(self.cells - sup):
                i, j = c
                if (i, j + 1) not in held or (i - 1, j) in self.cells - sup:
                    continue
                run = [c]
                while len(run) <= max_bridge and (run[-1][0] + 1, j) in self.cells - sup:
                    run.append((run[-1][0] + 1, j))
                for k in range(len(run)):
                    if k < max_bridge and (run[k][0] + 1, j + 1) in held:
                        ends = [(i, j + 1), (run[k][0] + 1, j + 1)]
                        for x in run[:k + 1]:
                            sup.add(x)
                            via[x] = ends
                            hold_top(x)
                        changed = True
                        break
        # dependencies: each resting node is held by the shallowest supported cell below it
        # (fewest cells to build first), so devices up top do not wait for the whole back column
        depth, best = {}, {}
        for c in sorted(via, key=lambda c: -c[1]):
            for n in via[c]:
                if n not in best:
                    hs = [h for h in ((n[0] - 1, n[1]), n) if h in depth]
                    best[n] = None if held.get(n, 0) is None or not hs else min(hs, key=lambda h: depth[h])
            depth[c] = 1 + max([depth[best[n]] if best[n] else 0 for n in via[c]])
        self.deps = {c: {best[n] for n in via[c]} - {None} for c in via}
        self.depth = depth
        dropped = self.cells - sup
        if dropped:
            self.cells -= dropped
            self.problems.append("%d unsupported cells omitted: %s" % (len(dropped), sorted(dropped)))

    # --- Cell properties
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

    # --- Actions
    def _fmt(self, p):
        return "x = %.2f, y = %.2f" % (p[0], p[1])

    def ensure_node(self, ij, via_material="bracing"):
        """Build node ij (if necessary) - from an already built neighbour."""
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
            # build the foundation from above/diagonally, not sideways along the ground
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
        """True if a large device extends over the right edge of c into the neighbouring cell."""
        a, b = self.devices.get(c) or "", self.devices.get((c[0] + 1, c[1])) or ""
        return bool(a and b) and (a + "+" == b or b + "+" == a)

    def in_turbine_row(self, c):
        """Cell in the turbine gallery storey: only background bracing inside (open for the wind)."""
        y = self.cfg.get("turbine_floor_y")
        return y is not None and self.cfg.get("turbine_row_open") and self.cfg["rows"][c[1] + 1] == y

    def is_split(self, c):
        """Front cell of the turbine row, split at half height for two stacked sandbags."""
        sc = self.cfg.get("split_cell")
        return bool(sc) and self.cfg["cols"][c[0]] == sc[0] and self.cfg["rows"][c[1]] == sc[1]

    def build_split_cell(self, c):
        """Cell with a background-bracing strut at half height: both side edges in two halves,
        no full-height posts, so two sandbags fit into the height of one turbine (like big vanilla forts)."""
        i, j = c
        tl, tr, bl, br = (i, j), (i + 1, j), (i, j + 1), (i + 1, j + 1)
        mids = []
        for top, bot, key in ((tl, bl, ("mid", i, j)), (tr, br, ("mid", i + 1, j))):
            if key not in self.nodes:
                pt, pb = self.nodes[top][1], self.nodes[bot][1]
                self.nodes[key] = (None, (round((pt[0] + pb[0]) / 2, 2), round((pt[1] + pb[1]) / 2, 2)), "new")
            nid, p, _ = self.node(key)
            if nid not in self.built_nodes:
                src = self.nodes[top]
                self.actions.append('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "backbracing" },'
                                    % (src[0], self._fmt(src[1]), nid, self._fmt(p)))
                self.built_nodes.add(nid)
                self.links[frozenset((src[0], nid))] = "backbracing"
            self.link(key, bot, "backbracing")
            mids.append(key)
        self.link(bl, br, "bracing")
        self.link(mids[0], mids[1], "backbracing")
        self.link(tl, tr, self.edge_material(c, "top"))
        self.link(tl, mids[1], "backbracing")
        self.link(mids[0], br, "backbracing")
        self.split_slots = {"mid": (mids[0], mids[1]), "floor": (bl, br)}

    def edge_material(self, c, edge):
        """Material for a cell edge: front/roof armoured, doors in front of weapons."""
        dev = self.devices.get(c)
        if edge == "right" and self.in_turbine_row(c):
            return "backbracing"       # wind must blow through the whole turbine row
        if edge == "right" and self.spans_right(c):
            return "backbracing"
        if edge == "right" and dev == "sandbags":
            return "bracing"
        if edge == "right" and self.is_front(c):
            return "door" if dev in DIRECT_WEAPONS else "armour"
        if edge == "top" and self.is_top(c) and self.cfg.get("light_roof"):
            # no metal roof (heavy, guide "How to be a PRO at Vanilla Forts"): doors only over mortars
            return "door" if dev in LOBBED_WEAPONS else "bracing"
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
        # first the cells that hold this one up (require_support); "building" guards against a
        # path to a support that leads back through this cell
        building = self.__dict__.setdefault("building", set())
        if c in building:
            return False
        building.add(c)
        try:
            for d in sorted(getattr(self, "deps", {}).get(c, ()), key=lambda d: -d[1]):
                if d not in self.built_cells and not self.build_cell_path(d):
                    return False
        finally:
            building.discard(c)
        i, j = c
        tl, tr, bl, br = (i, j), (i + 1, j), (i, j + 1), (i + 1, j + 1)
        orig = c in self.orig_cells
        for ij in (tl, tr, bl, br):
            if self.nodes[ij][0] not in self.built_nodes and self.ensure_node(ij) is None:
                # build the neighbouring cell first
                return False
        mine_cell = self.devices.get(c) == "mine-platz"
        if not orig and self.is_split(c):
            self.build_split_cell(c)
            self.built_cells.add(c)
            self.build_order.append(c)
            return True
        if not orig:
            if not mine_cell:   # no link on the rock at mine sites (otherwise the mine is blocked)
                self.link(bl, br, "bracing")
            self.link(tl, bl, "backbracing" if self.spans_right((i - 1, j)) or self.in_turbine_row(c) else "bracing")
            if not self.is_split((i + 1, j)):   # the split cell builds that edge in two halves
                self.link(tr, br, self.edge_material(c, "right"))
            self.link(tl, tr, self.edge_material(c, "top"))
            diag = "backbracing" if c in self.devices or self.devices.get((i - 1, j)) in LARGE or self.in_turbine_row(c) else "bracing"
            if mine_cell:
                diag = "backbracing"
            if (i + j) % 2 == 0:
                self.link(tl, br, diag)
            else:
                self.link(tr, bl, diag)
            # crossbrace the lower layers (|X|) so the fort does not wobble or collapse; with
            # crossbrace_late_y, cells above that height get their second diagonal in a final pass
            # (after all devices), so the weapons are not delayed by a lot of extra wood
            y = self.nodes[tl][1][1]
            if y >= self.cfg.get("crossbrace_y", 1e9) and not mine_cell:
                # the front weapon column (x >= crossbrace_now_x) is crossbraced right away: it is
                # what the enemy shoots at (test match: one 20mm volley cut off the single-braced column)
                if y >= self.cfg.get("crossbrace_late_y", -1e9) or self.cfg["cols"][i] >= self.cfg.get("crossbrace_now_x", 1e9):
                    self.crossbrace(c, diag)
                else:
                    self.late_crossbrace.append(c)
        else:
            self.link(bl, br, "bracing")
            if self.is_front(c):
                self.link(tr, br, self.edge_material(c, "right"))
        self.built_cells.add(c)
        self.build_order.append(c)
        return True

    def crossbrace(self, c, diag=None):
        """Second diagonal of cell c."""
        i, j = c
        if diag is None:
            diag = "backbracing" if c in self.devices or self.devices.get((i - 1, j)) in LARGE or self.in_turbine_row(c) else "bracing"
        if (i + j) % 2 == 0:
            self.link((i + 1, j), (i, j + 1), diag)
        else:
            self.link((i, j), (i + 1, j + 1), diag)

    def build_cell_path(self, c):
        """Build a cell; if necessary first the cells on the way from the starting fort."""
        if self.build_cell(c):
            return True
        # breadth-first search from built cells to c
        start = [x for x in self.built_cells]
        prev = {x: None for x in start}
        q = list(start)
        while q:
            x = q.pop(0)
            if x == c:
                break
            for n in ((x[0] + 1, x[1]), (x[0] - 1, x[1]), (x[0], x[1] + 1), (x[0], x[1] - 1)):
                if n in self.all_cells and n not in prev and n not in self.__dict__.get("building", ()):
                    prev[n] = x
                    q.append(n)
        if c not in prev:
            self.problems.append("cell %s not reachable" % (c,))
            return False
        path = []
        x = c
        while x is not None:
            path.append(x)
            x = prev[x]
        for x in reversed(path):
            if not self.build_cell(x):
                self.problems.append("cell %s could not be built" % (x,))
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

    # --- Choose slots
    def free_cells(self, pred):
        cells = [c for c in sorted(self.all_cells) if c not in self.devices and not self.near_reactor(c)
                 and not self.in_turbine_row(c) and pred(c)]
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
            cands.sort(key=lambda c: (-c[0], c[1]))     # on top, as far forward as possible
        elif dev in LARGE:
            cands = self.free_cells(lambda c: self.is_front(c) and c in self.cells and (c[0] - 1, c[1]) in self.all_cells
                                    and (c[0] - 1, c[1]) not in self.devices and wide(c))
            cands.sort(key=lambda c: abs(rows[c[1]] - self.cfg.get("large_y", -300)))
        else:
            cands = self.free_cells(lambda c: self.is_front(c) and c in self.cells and wide(c))
            if dev == "machinegun":
                cands.sort(key=lambda c: (abs(rows[c[1]] - self.cfg.get("aa_y", -250)), -c[0]))   # near reactor height: anti-air
            else:
                cands.sort(key=lambda c: (rows[c[1]], -c[0]))               # snipers preferably on top
        if not cands:
            return None
        # some randomness among the best three so that variants differ
        return cands[self.rng.randrange(min(2, len(cands)))]

    def place_eco_slot(self, dev):
        """Battery/store on a proven slot of the original plan (node A, node B, LinkT)."""
        for (pa, pb, t) in self.cfg.get("eco_slots", []):
            ia, ib = self.node_at(pa), self.node_at(pb)
            if not ia or not ib:
                continue
            c = (ia[0], ia[1] - 1)
            if c in self.devices or c not in self.all_cells or not self.build_cell_path(c):
                continue
            self.devices[c] = dev
            a, b = self.nodes[ia], self.nodes[ib]
            self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                                % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t, dev))
            self.placed.append((dev, a[1], b[1], t, c))
            return True
        return False

    def choose_eco_cell(self):
        ground = max(self.cfg["rows"])
        no_ground = self.cfg.get("eco_no_ground")
        cands = self.free_cells(lambda c: not self.is_front(c) and (c in self.cells or self.cfg.get("eco_orig", True))
                                and not (no_ground and self.cfg["rows"][c[1] + 1] >= ground))
        cands.sort(key=lambda c: (-self.cfg["rows"][c[1]], c[0]))
        return cands[0] if cands else None

    def unbuilt_support(self, c, seen=None):
        """Number of unbuilt cells that must be built before c (c included)."""
        seen = set() if seen is None else seen
        if c in self.built_cells or c in seen:
            return 0
        seen.add(c)
        return 1 + sum(self.unbuilt_support(d, seen) for d in getattr(self, "deps", {}).get(c, ()))

    def choose_turbine_floor(self):
        """Free cell of the turbine gallery (floor at turbine_floor_y), cheapest to reach first."""
        y = self.cfg["turbine_floor_y"]
        min_w = self.cfg.get("turbine_min_w", 0)
        cands = [c for c in sorted(self.cells)
                 if self.cfg["rows"][c[1] + 1] == y and not self.is_front(c) and c not in self.devices
                 and self.cell_w(c) >= min_w]
        cands.sort(key=lambda c: (self.unbuilt_support(c), -c[0]))
        return cands[0] if cands else None

    def choose_turbine_roof(self):
        min_w = self.cfg.get("turbine_min_w", 0)
        cands = [c for c in sorted(self.cells)
                 if self.is_top(c) and not self.is_front(c) and not self.roof_device.get(c)
                 and self.devices.get(c) not in LOBBED_WEAPONS
                 and self.cell_w(c) >= min_w
                 # not over a large weapon (the turbine collides with it)
                 and not (min_w and (self.devices.get(c) or "").rstrip("+") in LARGE)]
        if self.cfg.get("turbine_cheap_first"):
            # early economy: the roof that needs the fewest unbuilt cells first, then the highest
            cands.sort(key=lambda c: (self.unbuilt_support(c), self.cfg["rows"][c[1]], -c[0]))
        elif self.cfg.get("turbine_narrow_first"):
            cands.sort(key=lambda c: (self.cell_w(c) >= 95, self.cfg["rows"][c[1]], -c[0]))
        else:
            cands.sort(key=lambda c: (self.cfg["rows"][c[1]], c[0]))
        return cands[0] if cands else None

    # --- Main flow
    def generate(self, variant):
        self.variant = variant
        self.tech_slots = dict(self.cfg["tech_slots"])
        self.tech_slots.update(variant.get("tech_slots", {}))
        self.build_lattice()
        self.select_cells(variant["shape"])
        self.built_cells = set()
        self.build_order = []
        self.late_crossbrace = []
        self.roof_device = {}
        self.mines_done = 0
        # the starting fort counts as built
        for c in self.orig_cells:
            self.built_cells.add(c)
        # cells whose floor lies on a mine site stay free (the mine sits on the rock below)
        for m in self.cfg["mines"]:
            gx, gy = m["ground"]
            for c in self.all_cells:
                a, b = self.nodes[(c[0], c[1] + 1)][1], self.nodes[(c[0] + 1, c[1] + 1)][1]
                if min(a[0], b[0]) - 40 <= gx <= max(a[0], b[0]) + 40 and abs((a[1] + b[1]) / 2 - gy) < 20:
                    self.devices[c] = "mine-platz"
        for step, items in variant["plan"]:
            for dev in items:
                self.add(step, dev)
        # finish building the remaining cells of the shape (structure + armour);
        # bottom_up: lower layers first, so the fort does not grow top-heavy
        sign = -1 if self.cfg.get("bottom_up") else 1
        for c in sorted(self.cells, key=lambda c: (sign * self.cfg["rows"][c[1]], c[0])):
            self.build_cell_path(c)
        # deferred crossbracing, bottom up
        for c in sorted(self.late_crossbrace, key=lambda c: (-self.cfg["rows"][c[1]], c[0])):
            self.crossbrace(c)
        return self

    def add(self, step, dev):
        if PREREQ.get(dev) and PREREQ[dev] not in self.tech_done and dev not in UPGRADE_OF:
            self.problems.append("%s without %s - moved forward" % (dev, PREREQ[dev]))
            self.add("tech", PREREQ[dev])
        if step == "upgrades":
            base = UPGRADE_OF[dev]
            if "upgrade" not in self.tech_done:
                self.add("tech", "upgrade")
            for (d, a, b, t, c) in self.placed:
                if d == base:
                    self.placed.remove((d, a, b, t, c))
                    if c is None:       # upgrade ground mine
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
            self.problems.append("no %s to upgrade to %s" % (base, dev))
            return
        if dev == "mine":
            return self.add_mine()
        if dev == "turbine":
            c = self.choose_turbine_floor() if self.cfg.get("turbine_floor_y") is not None else None
            if c is not None and self.build_cell_path(c):
                # turbine gallery: a row of turbines on the floor of one open storey (like big vanilla
                # forts), so roofs stay free for mortars
                self.devices[c] = dev
                self.place_on_floor(c, dev)
                return
            c = self.choose_turbine_roof()
            if c is None or not self.build_cell_path(c):
                self.problems.append("no roof slot for turbine")
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
                    self.devices[(c[0] + 1, c[1])] = dev + "+"   # second half of the cell occupied
                    if self.cfg.get("tech_spill") and t <= 0.1 and (c[0] - 1, c[1]) not in self.devices:
                        self.devices[(c[0] - 1, c[1])] = dev + "+"   # device at the left link end extends to the left
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
            self.problems.append("no room for %s" % dev)
            return
        if dev in ("battery", "store"):
            if self.cfg.get("use_eco_slots") and self.place_eco_slot(dev):
                return
            c = self.choose_eco_cell()
            if c is None or not self.build_cell_path(c):
                self.problems.append("no room for %s" % dev)
                return
            self.devices[c] = dev
            self.place_on_floor(c, dev)
            return
        if dev == "sandbags":
            # sandbags at the front of the turbine row (shield the turbines, like big vanilla forts)
            slots = self.cfg.get("sandbag_slots", [])
            c = next((c for c in self.all_cells if self.is_split(c)), None)
            n = sum(1 for p in self.placed if p[0] == "sandbags")
            if c is None or n >= len(slots) or not self.build_cell_path(c):
                self.problems.append("no room for sandbags")
                return
            slot, t = slots[n]
            a, b = (self.nodes[k] for k in self.split_slots[slot])
            self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "sandbags" },'
                                % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t))
            self.placed.append(("sandbags", a[1], b[1], t, c))
            return
        # Weapons
        c = self.choose_weapon_cell(dev)
        if c is None:
            self.problems.append("no room for %s" % dev)
            return
        self.devices[c] = dev
        if dev in LARGE:
            self.devices[(c[0] - 1, c[1])] = dev + "+"
        if not self.build_cell_path(c):
            return
        # reset front/roof after the weapon choice (door instead of armour)
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
                        # additional node outside the grid
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
                # build the cell above the foundation
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
        self.problems.append("no mine site left")

    # --- Validation and output
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
                    errors.append("action %d: node %d is created from unbuilt node %d" % (k, ids[1], ids[0]))
                built.add(ids[1])
                pos[ids[1]] = pts[1]
            elif m in ("CREATE_LINK", "CREATE_DEVICE") and ids:
                for x in ids:
                    if x not in built:
                        errors.append("action %d: node %d not built yet" % (k, x))
            if len(pts) >= 2 and m in ("CREATE_NODE", "CREATE_LINK"):
                L = math.dist(pts[0], pts[1])
                if L > MAX_LINK + 1:
                    errors.append("action %d: link too long (%.0f)" % (k, L))
                if not self.t.segment_clear(pts[0], pts[1]):
                    errors.append("action %d: link passes through rock" % k)
        for nid, p in pos.items():
            if nid >= 10000 and self.t.inside((p[0], p[1] - 3)) and self.t.inside((p[0] + 3, p[1])):
                errors.append("node %d lies in rock" % nid)
        # every cell is built only after the cells that hold it up
        done = set(self.orig_cells)
        for c in getattr(self, "build_order", []):
            missing = getattr(self, "deps", {}).get(c, set()) - done
            if missing:
                errors.append("cell %s built before its support %s" % (c, sorted(missing)))
            done.add(c)
        seen = set()
        for line in self.actions:
            m = re.search(r'DeviceSaveName = "(\w+)"', line)
            if m:
                d = m.group(1)
                if PREREQ.get(d) and PREREQ[d] not in seen:
                    errors.append("%s built before %s" % (d, PREREQ[d]))
                seen.add(d)
        return errors

    def write(self, path, title):
        # header exactly like recorded plans (the AI relies on these line numbers)
        head = ("-- Fort recorded for AI replay\n"
                "CREATE_NODE = 1\nDESTROY_NODE = 2\nCREATE_LINK = 3\nDESTROY_LINK = 4\nCREATE_DEVICE = 5\nDESTROY_DEVICE = 6\n")
        tail = "-- Generated by Claude AI (tools/fortgen/gen_fort.py): %s\n" % title
        with open(path, "w", encoding="ascii", newline="\r\n") as f:
            f.write(head + self.cfg["header"] + "\n\nFort =\n{\n" + "\n".join(self.actions) + "\n}\n" + tail)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--maps", required=True, help="data/maps folder")
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
        print("%s [%s] %d actions, devices: %s" % (name, key, len(p.actions), ", ".join("%s:%d" % kv for kv in sorted(devs.items()))))
        for e in errors:
            print("   ERROR:", e)
        for pr in p.problems:
            print("   Note:", pr)


if __name__ == "__main__":
    main()
