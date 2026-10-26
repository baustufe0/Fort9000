#!/usr/bin/env python3
"""FORT 9000 - static physics check of Forts build plans: does the fort stand, sag or fall?

Forts simulates a fort as point masses (nodes) joined by springs (struts); foundations on the rock are fixed. A strut
breaks when it is squeezed below MaxCompression or stretched above MaxExpansion of its rest length
(building_materials.lua). Nodes are hinges: a cell without a diagonal folds. This tool solves the same model for
static equilibrium under gravity (Newton-Raphson on the nonlinear truss, banded LDL^T factorisation, pure Python):
  * stress of every strut as the game shows it: strain / break limit (1.0 = breaks);
  * sag of every node; unbraced mechanisms (a zero pivot of the stiffness matrix);
  * the cascade when a strut breaks (it is removed and the fort solved again);
  * the build order: the plan is replayed action by action the way the AI builds it (GetAdjustedNodePosition: a new
    node goes to the CURRENT position of its source node plus the planned offset; a strut between existing nodes
    takes their current distance as its rest length, so deformation is locked in; a node within 20 of an existing
    one snaps to it; a strut longer than MaxLinkLength 218 or shorter than 37.5 at build time is refused).

Game constants (db/constants.lua Physics): Gravity 981, MinimumMass 15 per node. Masses: strut Mass per length,
devices Mass / WeaponMass from their files. The spring law and the scale of the game's stress are not documented;
SPRING_LAW and STRESS_SCALE below come from `calibrate` (engine stress of every strut in a CS_UNSTABLE probe log,
docs/physics.md).

The plan alone does not contain the starting fort; startforts/<map>.json holds it (nodes, struts, devices),
extracted from a probe log with `startfort`.

Usage:
  physics.py check <plan.lua> ... [--map Vanilla] [--no-modules] [--png out.png] [--trace]
  physics.py calibrate --log <probe log> --plan <plan built in that match> [--map Vanilla]
  physics.py startfort --log <probe log> --plan <plan built in that match> [--map Vanilla] [--out startforts/<map>.json]
"""
import argparse
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(os.path.dirname(HERE))
DATA = os.path.dirname(os.path.dirname(MOD))
sys.path.insert(0, HERE)
from fortplan import parse_plan, parse_modules, node_positions   # noqa: E402

GRAVITY = 981.0
MIN_NODE_MASS = 15.0
MAX_LINK_LENGTH = 218.0       # StandardMaxLinkLength (a strut between existing nodes)
MIN_LINK_LENGTH = 37.5
SNAP = 20.0                   # SnapToNode
COLLAPSE_BREAKS = 8           # struts broken in all: the fort has fallen, the replay stops
UNBRACED_MAX = 8              # actions a node may hang unbraced before it is reported
GROUND_TOL = 5.0

# building_materials.lua: Stiffness, Mass per length, MaxCompression, MaxExpansion
MATERIALS = {
    "bracing": (200000.0, 0.25, 0.90, 1.10),
    "backbracing": (200000.0, 0.25, 0.92, 1.08),
    "armour": (250000.0, 0.5, 0.90, 1.10),
    "door": (250000.0, 0.5, 0.90, 1.10),
    "shield": (200000.0, 0.05, 0.90, 1.10),
    "rope": (50000.0, 0.001, 0.60, 1.50),
    "solar": (200000.0, 0.4, 0.90, 1.10),
}
DEFAULT_DEVICE_MASS = 60.0    # devices whose file is packed (smoke bomb)

# Spring law: force = Stiffness * (L - L0) ("abs", Stiffness per unit of length change) or
# Stiffness * (L - L0) / L0 * 100 ("strain", per unit strain on a 100-long strut). Chosen by `calibrate`.
SPRING_LAW = "abs"
STRESS_SCALE = 1.0            # game stress = STRESS_SCALE * strain / limit (from `calibrate`)


# ---------------------------------------------------------------------------------------------------------------
# game data

_masses = None


def device_masses():
    """SaveName -> mass, from the device and weapon lists of the game and weapon_pack (Mass / WeaponMass)."""
    global _masses
    if _masses is not None:
        return _masses
    _masses = {}
    lists = [("devices/device_list.lua", DATA), ("weapons/weapon_list.lua", DATA),
             ("mods/weapon_pack/devices/device_list.lua", os.path.join(DATA, "mods", "weapon_pack")),
             ("mods/weapon_pack/weapons/weapon_list.lua", os.path.join(DATA, "mods", "weapon_pack"))]
    for rel, base in lists:
        path = os.path.join(DATA, rel)
        if not os.path.exists(path):
            continue
        text = open(path, encoding="latin-1").read()
        for m in re.finditer(r'SaveName\s*=\s*"(\w+)",\s*FileName\s*=\s*(?:path\s*\.\.\s*)?"/?([\w/.\-]+)"', text):
            name, fn = m.group(1), m.group(2)
            f = os.path.join(base if "path" in m.group(0) else DATA, fn)
            if not os.path.exists(f):
                continue
            mm = re.search(r"^\s*(?:Weapon)?Mass\s*=\s*([\d.]+)", open(f, encoding="latin-1").read(), re.M)
            if mm:
                _masses[name] = float(mm.group(1))
    return _masses


def device_mass(name):
    return device_masses().get(name, DEFAULT_DEVICE_MASS)


def load_terrain(map_name):
    import gen_fort
    from fwe import read_blocks
    from terrain import Terrain
    cfg = gen_fort.MAPS.get(map_name)
    if cfg is None:
        return None
    _, blocks = read_blocks(os.path.join(DATA, "maps", map_name, cfg["fwe"]))
    return Terrain([pts for flag, pts in blocks if flag >= 0 or (cfg.get("solid_minus1") and flag == -1)])


def on_ground(terrain, p):
    return terrain is not None and (terrain.inside(p) or terrain.nearest_surface(p)[1] <= GROUND_TOL)


# ---------------------------------------------------------------------------------------------------------------
# the fort

class Fort:
    """Nodes (id -> [x, y]), fixed nodes, struts {pair: [a, b, material, rest length]}, devices on struts."""

    def __init__(self):
        self.pos = {}
        self.fixed = set()
        self.links = {}
        self.devices = []          # [name, a, b, t]
        self.warning = None        # caveat of the starting fort (startforts/<map>.json "warning")

    def add_link(self, a, b, mat, rest=None):
        self.links[frozenset((a, b))] = [a, b, mat, rest if rest is not None else self.dist(a, b)]

    def dist(self, a, b):
        pa, pb = self.pos[a], self.pos[b]
        return math.hypot(pb[0] - pa[0], pb[1] - pa[1])

    def masses(self):
        m = {n: 0.0 for n in self.pos}
        for a, b, mat, rest in self.links.values():
            half = MATERIALS.get(mat, MATERIALS["bracing"])[1] * rest / 2
            m[a] += half
            m[b] += half
        for name, a, b, t in self.devices:
            if a in m and b in m:
                w = device_mass(name)
                m[a] += w * (1 - t)
                m[b] += w * t
        return {n: max(MIN_NODE_MASS, v) for n, v in m.items()}

    def copy(self):
        f = Fort()
        f.pos = {n: list(p) for n, p in self.pos.items()}
        f.fixed = set(self.fixed)
        f.links = {k: list(v) for k, v in self.links.items()}
        f.devices = [list(d) for d in self.devices]
        f.warning = self.warning
        return f


def stiffness(mat, rest):
    s = MATERIALS.get(mat, MATERIALS["bracing"])[0]
    return s if SPRING_LAW == "abs" else s * 100.0 / max(rest, 1.0)


def ratio(mat, length, rest):
    """Stress as the game shows it (signed: + stretched, - squeezed); |ratio| >= 1 breaks the strut."""
    _, _, cmin, emax = MATERIALS.get(mat, MATERIALS["bracing"])
    strain = length / rest - 1.0
    return STRESS_SCALE * (strain / (emax - 1.0) if strain >= 0 else strain / (1.0 - cmin))


# ---------------------------------------------------------------------------------------------------------------
# linear algebra: symmetric banded LDL^T

def _rcm(nodes, adj):
    """Reverse Cuthill-McKee order of the free nodes (small bandwidth)."""
    order, seen = [], set(adj) - set(nodes)
    for start in sorted(nodes, key=lambda n: len(adj[n])):
        if start in seen:
            continue
        seen.add(start)
        queue = [start]
        while queue:
            n = queue.pop(0)
            order.append(n)
            for m in sorted(adj[n] - seen, key=lambda x: len(adj[x])):
                seen.add(m)
                queue.append(m)
    return order[::-1]


def ldl_solve(n, bw, rows, rhs, eps=1e-9):
    """rows[i]: dict j -> K[i][j] for j <= i (lower band). Returns (x, weak DOFs): a pivot below eps * diagonal
    means the structure has no stiffness there (a mechanism); it is stiffened by a weak spring and reported."""
    L = [None] * n
    D = [0.0] * n
    weak = []
    for i in range(n):
        lo = max(0, i - bw)
        Li = [0.0] * (i - lo)
        r = rows[i]
        for j in range(lo, i):
            s = r.get(j, 0.0)
            Lj, loj = L[j], max(0, j - bw)
            for k in range(max(lo, loj), j):
                s -= Li[k - lo] * D[k] * Lj[k - loj]
            Li[j - lo] = s / D[j]
        d = r.get(i, 0.0)
        for k in range(lo, i):
            d -= Li[k - lo] * Li[k - lo] * D[k]
        diag = abs(r.get(i, 0.0)) or 1.0
        if d <= eps * diag:
            weak.append(i)
            d = max(abs(d), 1e-3 * diag)
        L[i], D[i] = Li, d
    y = list(rhs)
    for i in range(n):
        lo = max(0, i - bw)
        s = y[i]
        for k in range(lo, i):
            s -= L[i][k - lo] * y[k]
        y[i] = s
    for i in range(n):
        y[i] /= D[i]
    for i in range(n - 1, -1, -1):
        s = y[i]
        for j in range(i + 1, min(n, i + bw + 1)):
            lo = max(0, j - bw)
            s -= L[j][i - lo] * y[j]
        y[i] = s
    return y, weak


# ---------------------------------------------------------------------------------------------------------------
# static solver

class Result:
    def __init__(self):
        self.converged = False
        self.mechanism = []        # free nodes without stiffness
        self.iterations = 0
        self.residual = 0.0


def solve(fort, max_iter=200, tol=1.0, max_step=10.0, hold=False):
    """Moves fort.pos to static equilibrium under gravity (in place). tol: largest residual force per node.
    hold: nodes without stiffness where the fort stands (a node hanging on one strut, an unbraced cell) are held in
    place and the rest is solved (res.mechanism lists them); otherwise they are stiffened by a weak spring."""
    held = set()
    for _ in range(50):
        res = _solve(fort, held, max_iter, tol, max_step, hold)
        if not (hold and res.iterations == 0 and res.mechanism and not res.converged):
            break
        held.update(res.mechanism)
    if hold:
        res.mechanism = sorted(held | set(res.mechanism))
    return res


def _solve(fort, held, max_iter, tol, max_step, hold):
    res = Result()
    free = [n for n in fort.pos if n not in fort.fixed and n not in held]
    if not free:
        res.converged = True
        return res
    adj = {n: set() for n in fort.pos}
    for a, b, _, _ in fort.links.values():
        adj[a].add(b)
        adj[b].add(a)
    order = _rcm(free, {n: v for n, v in adj.items() if n not in held} | {n: set() for n in held})
    idx = {n: i for i, n in enumerate(order)}
    nd = 2 * len(order)
    bw = 1
    for a, b, _, _ in fort.links.values():
        if a in idx and b in idx:
            bw = max(bw, 2 * abs(idx[a] - idx[b]) + 1)
    mass = fort.masses()
    links = list(fort.links.values())
    for it in range(max_iter):
        rows = [dict() for _ in range(nd)]
        rhs = [0.0] * nd
        for n, i in idx.items():
            rhs[2 * i + 1] += mass[n] * GRAVITY
        for a, b, mat, rest in links:
            pa, pb = fort.pos[a], fort.pos[b]
            dx, dy = pb[0] - pa[0], pb[1] - pa[1]
            length = math.hypot(dx, dy) or 1e-6
            cx, cy = dx / length, dy / length
            k = stiffness(mat, rest)
            force = k * (length - rest)                  # + tension
            g = force / length                           # geometric stiffness
            kxx = k * cx * cx + g * (1 - cx * cx)
            kyy = k * cy * cy + g * (1 - cy * cy)
            kxy = (k - g) * cx * cy
            fx, fy = force * cx, force * cy
            ia, ib = idx.get(a), idx.get(b)
            if ia is not None:
                rhs[2 * ia] += fx
                rhs[2 * ia + 1] += fy
            if ib is not None:
                rhs[2 * ib] -= fx
                rhs[2 * ib + 1] -= fy
            block = ((kxx, kxy), (kxy, kyy))
            for i1, s1 in ((ia, 1), (ib, -1)):
                if i1 is None:
                    continue
                for i2, s2 in ((ia, 1), (ib, -1)):
                    if i2 is None:
                        continue
                    for r in range(2):
                        for c in range(2):
                            gi, gj = 2 * i1 + r, 2 * i2 + c
                            if gj <= gi:
                                rows[gi][gj] = rows[gi].get(gj, 0.0) + s1 * s2 * block[r][c]
        worst = max(math.hypot(rhs[2 * i], rhs[2 * i + 1]) for i in range(len(order)))
        res.iterations, res.residual = it, worst
        if worst < tol:
            res.converged = True
            break
        du, weak = ldl_solve(nd, bw, rows, rhs)
        res.mechanism = sorted({order[w // 2] for w in weak})
        if weak and hold and it == 0:
            return res
        big = max(abs(v) for v in du)
        scale = min(1.0, max_step / big) if big > 0 else 1.0
        for n, i in idx.items():
            p = fort.pos[n]
            p[0] += scale * du[2 * i]
            p[1] += scale * du[2 * i + 1]
    return res


def stresses(fort):
    """{pair: signed stress ratio}"""
    out = {}
    for key, (a, b, mat, rest) in fort.links.items():
        out[key] = ratio(mat, fort.dist(a, b), rest)
    return out


def settle(fort, max_breaks=COLLAPSE_BREAKS, hold=False):
    """Solve; break every strut over its limit (worst first), solve again. Returns (result, broken struts)."""
    broken = []
    while True:
        r = solve(fort, hold=hold)
        st = stresses(fort)
        over = [(abs(v), k) for k, v in st.items() if abs(v) >= 1.0]
        if not over or len(broken) >= max_breaks or not r.converged:
            return r, broken
        _, key = max(over, key=lambda x: x[0])
        a, b, mat, _ = fort.links.pop(key)
        broken.append((a, b, mat, st[key]))


def prestress(fort):
    """Rest lengths for which the fort is in equilibrium where it stands (a starting fort as the map stores it):
    solve from the current positions, then shorten/lengthen every strut by its deformation."""
    plan = {n: list(p) for n, p in fort.pos.items()}
    solve(fort)
    for key, lk in fort.links.items():
        a, b, mat, rest = lk
        lk[3] = rest * math.hypot(plan[b][0] - plan[a][0], plan[b][1] - plan[a][1]) / fort.dist(a, b)
    fort.pos = plan


# ---------------------------------------------------------------------------------------------------------------
# starting fort and plan replay

def startfort_path(map_name):
    return os.path.join(HERE, "startforts", map_name + ".json")


def load_startfort(map_name, terrain):
    path = startfort_path(map_name)
    if not os.path.exists(path):
        return None
    d = json.load(open(path))
    f = Fort()
    for n, p in d["nodes"].items():
        f.pos[int(n)] = list(p)
        if on_ground(terrain, p):
            f.fixed.add(int(n))
    for a, b, mat in d["links"]:
        f.add_link(a, b, mat)
    f.devices = [list(x) for x in d["devices"]]
    if d.get("prestress", True):
        prestress(f)
    f.warning = d.get("warning")
    return f


class Replay:
    """Builds a plan action by action on the starting fort and solves after each step."""

    def __init__(self, fort, terrain, trace=False):
        self.f = fort
        self.terrain = terrain
        self.plan_pos = {n: tuple(p) for n, p in fort.pos.items()}
        self.alias = {}                 # plan node id -> node it snapped to
        self.refused = []               # (action, kind, detail)
        self.peak = {}                  # pair -> (|stress|, action)
        self.broken = []                # (action, a, b, material, stress)
        self.mechanism = []             # (action, nodes)
        self.unconverged = []
        self.collapsed = None           # action at which the fort fell (replay stopped)
        self.unbraced = []              # (first action, last action, nodes): a mechanism for UNBRACED_MAX actions
        self.trace = trace

    def node(self, n):
        return self.alias.get(n, n)

    def step(self, k, a):
        f, t = self.f, a["Type"]
        A = self.node(a.get("OriginalNodeAId"))
        B = self.node(a.get("OriginalNodeBId"))
        for nid, key in ((a.get("OriginalNodeAId"), "PosA"), (a.get("OriginalNodeBId"), "PosB")):
            if nid is not None and key in a:
                self.plan_pos.setdefault(nid, a[key])
        if t == "CREATE_NODE":
            if A not in f.pos:
                self.refused.append((k, "node", "source %s missing" % A))
                return False
            np_ = a["NewNodePos"]
            self.plan_pos[a["OriginalNodeBId"]] = np_
            if on_ground(self.terrain, np_):
                p = list(np_)
            else:
                src = self.plan_pos.get(a["OriginalNodeAId"], f.pos[A])
                p = [f.pos[A][0] + np_[0] - src[0], f.pos[A][1] + np_[1] - src[1]]
            near = min(((math.hypot(q[0] - p[0], q[1] - p[1]), n) for n, q in f.pos.items()), default=(1e9, None))
            if near[0] < SNAP and near[1] != A:
                self.alias[a["OriginalNodeBId"]] = near[1]
                B = near[1]
            else:
                B = a["OriginalNodeBId"]
                f.pos[B] = p
                if on_ground(self.terrain, p):
                    f.fixed.add(B)
            length = f.dist(A, B)
            if length > MAX_LINK_LENGTH or length < MIN_LINK_LENGTH:
                self.refused.append((k, "link", "%s-%s length %.0f" % (A, B, length)))
                if B not in {x for l in f.links.values() for x in l[:2]} and B not in self.alias.values():
                    f.pos.pop(B, None)
                    f.fixed.discard(B)
                return False
            f.add_link(A, B, a.get("MaterialSaveName", "bracing"))
            return True
        if t == "CREATE_LINK":
            if A not in f.pos or B not in f.pos:
                self.refused.append((k, "link", "%s-%s node missing" % (A, B)))
                return False
            key = frozenset((A, B))
            if key in f.links:
                f.links[key][2] = a.get("MaterialSaveName", "bracing")     # material swap, rest length kept
                return False
            length = f.dist(A, B)
            if length > MAX_LINK_LENGTH or length < MIN_LINK_LENGTH:
                self.refused.append((k, "link", "%s-%s length %.0f" % (A, B, length)))
                return False
            f.add_link(A, B, a.get("MaterialSaveName", "bracing"))
            return True
        if t == "CREATE_DEVICE":
            if "GroundPosition" in a:
                return False
            if frozenset((A, B)) not in f.links:
                self.refused.append((k, "device", "%s on missing strut %s-%s" % (a.get("DeviceSaveName"), A, B)))
                return False
            f.devices.append([a.get("DeviceSaveName"), A, B, a.get("LinkT", 0.5)])
            return True
        if t == "DESTROY_DEVICE":
            key = frozenset((A, B))
            f.devices = [d for d in f.devices if not (d[0] == a.get("DeviceSaveName") and frozenset(d[1:3]) == key)]
            return True
        if t == "DESTROY_LINK":
            return f.links.pop(frozenset((A, B)), None) is not None
        if t == "DESTROY_NODE":
            n = self.node(a.get("OriginalNodeAId"))
            f.pos.pop(n, None)
            f.fixed.discard(n)
            f.links = {key: v for key, v in f.links.items() if n not in key}
            return True
        return False

    def run(self, actions):
        r, broken = settle(self.f)
        self._record(0, r, broken)
        since = {}                      # unbraced node -> first action it hung
        for k, a in enumerate(actions, 1):
            if not self.step(k, a):
                continue
            # a new node hangs on one strut until the next strut braces it (a second or two in the game): while a
            # node is freshly unbraced the fort is left as it is (solved again once it is braced); a node unbraced
            # for more than UNBRACED_MAX actions is reported and held in place while the rest is solved
            before = self.f.copy()
            r, broken = settle(self.f, hold=True)
            loose = set(r.mechanism)
            for n in loose:
                since.setdefault(n, k)
                if k - since[n] == UNBRACED_MAX:
                    self.unbraced.append((since[n], k, n))
            since = {n: v for n, v in since.items() if n in loose}
            if not broken and any(k - v < UNBRACED_MAX for v in since.values()):
                self.f = before
                continue
            r.mechanism = []
            self._record(k, r, broken)
            if len(self.broken) >= COLLAPSE_BREAKS or not r.converged:
                self.collapsed = k          # the rest of the replay would describe a heap of struts
                return self
            if self.trace:
                st = stresses(self.f)
                key = max(st, key=lambda x: abs(st[x])) if st else None
                print("  %4d %-13s max %.2f %s sag %.1f" % (k, a["Type"], abs(st[key]) if key else 0,
                                                             "-".join(map(str, sorted(key))) if key else "",
                                                             self.max_sag()[0]))
        r, broken = settle(self.f, hold=bool(since))
        if since:
            r.mechanism = sorted(since)
        self._record(len(actions), r, broken)
        return self

    def _record(self, k, r, broken):
        if r.mechanism:
            self.mechanism.append((k, r.mechanism))
        if not r.converged:
            self.unconverged.append((k, r.residual))
        for a, b, mat, s in broken:
            self.broken.append((k, a, b, mat, s))
        for key, s in stresses(self.f).items():
            if abs(s) > self.peak.get(key, (0, 0))[0]:
                self.peak[key] = (abs(s), k)

    def sag(self, n):
        p, q = self.f.pos[n], self.plan_pos.get(n)
        return (p[0] - q[0], p[1] - q[1]) if q else (0.0, 0.0)

    def max_sag(self):
        best = (0.0, None)
        for n in self.f.pos:
            d = math.hypot(*self.sag(n))
            if d > best[0]:
                best = (d, n)
        return best


def check(path, map_name, terrain, modules=True, trace=False, verbose=True):
    header, actions = parse_plan(path)
    if modules:
        for m in parse_modules(path):
            actions = actions + m["actions"]
    fort = load_startfort(map_name, terrain)
    if fort is None:
        print("%s: no starting fort for %s (startforts/%s.json)" % (os.path.basename(path), map_name, map_name))
        return None
    if header.get("team") == 2:      # team-2 plans (VanillaLong) stand mirrored on the map
        print("%s: team-2 plan, starting fort is team 1; skipped" % os.path.basename(path))
        return None
    rp = Replay(fort, terrain, trace).run(actions)
    st = stresses(rp.f)
    final_max = max(((abs(v), k) for k, v in st.items()), default=(0, None), key=lambda x: x[0])
    sag, sag_node = rp.max_sag()
    falls = bool(rp.broken or rp.unconverged)
    weak = final_max[0] > 0.8 or sag > 60 or rp.mechanism or len(rp.refused) > 3
    verdict = "FALLS" if falls else ("WEAK" if weak else "STANDS")
    if verbose:
        print("%s: %s  (struts %d, nodes %d, max stress %.2f, max sag %.0f at node %s)" % (
            os.path.basename(path), verdict, len(rp.f.links), len(rp.f.pos), final_max[0], sag, sag_node))
        if fort.warning:
            print("  NOTE %s" % fort.warning)
        for k, kind, d in rp.refused:
            print("  REFUSED action %d %s: %s" % (k, kind, d))
        for k, a, b, mat, s in rp.broken:
            print("  BREAKS  action %d %s-%s %s stress %+.2f" % (k, a, b, mat, s))
        for k, nodes in rp.mechanism:
            print("  LOOSE at the end: nodes %s (no strut braces them; they hang or swing)" % nodes[:8])
        stretches = {}
        for k0, k1, n in rp.unbraced:
            stretches.setdefault(k0, []).append(n)
        for k0, nodes in sorted(stretches.items()):
            print("  UNBRACED from action %d for %d+ actions: nodes %s" % (k0, UNBRACED_MAX, sorted(nodes)[:8]))
        for k, res in rp.unconverged:
            print("  NO EQUILIBRIUM action %d (residual %.0f)" % (k, res))
        if rp.collapsed:
            print("  COLLAPSE at action %d of %d (replay stopped)" % (rp.collapsed, len(actions)))
        top = sorted(rp.peak.items(), key=lambda x: -x[1][0])[:5]
        for key, (s, k) in top:
            lk = rp.f.links.get(key)
            mat = lk[2] if lk else "broken"
            print("  peak %.2f %s %s at action %d (final %.2f)" % (s, "-".join(map(str, sorted(key))), mat, k,
                                                                     abs(st.get(key, 0))))
    return rp, verdict


# ---------------------------------------------------------------------------------------------------------------
# probe logs: engine positions and stress

PROBE_RE = re.compile(r"\[CAI\] T(\d+) PROBE (START|NODE|LINK)(.*)")


def read_probe(log, match=-1):
    """Snapshots of PROBE NODE / LINK lines (one per PROBE START): nodes {runtime: (x, y, plan id)},
    links [(a, b, material, stress, [(device, t)])], mirrored flag."""
    snaps = []
    for line in open(log, encoding="latin-1"):
        m = PROBE_RE.search(line)
        if not m:
            continue
        kind, rest = m.group(2), m.group(3)
        if kind == "START":
            snaps.append({"nodes": {}, "links": [], "mirrored": "mirrored=1" in rest})
            continue
        if not snaps:
            continue
        for tok in rest.split()[1:]:
            if kind == "NODE":
                rid, xy, pid = tok.split(":")
                x, y = xy.split(",")
                snaps[-1]["nodes"][int(rid)] = (float(x), float(y), int(pid))
            else:
                parts = tok.split(":")
                a, b = parts[0].split("-")
                devs = [(d.split("@")[0], float(d.split("@")[1])) for d in parts[3:] if "@" in d]
                snaps[-1]["links"].append((int(a), int(b), parts[1], float(parts[2]), devs))
    snaps = [s for s in snaps if s["links"]]
    return snaps[match] if snaps else None


def map_probe(snap, actions, map_name):
    """runtime id -> plan id and plan-frame position: new nodes by the logged plan id, starting-fort nodes by
    nearest plan position (x mirrored for a mirrored plan)."""
    sx = -1.0 if snap["mirrored"] else 1.0
    start = dict(base_positions(map_name))
    start.update({n: p for n, p in node_positions(actions).items() if n < 10000})
    ids, pos = {}, {}
    for rid, (x, y, pid) in snap["nodes"].items():
        p = (sx * x, y)
        if pid >= 10000:
            ids[rid] = pid
        else:
            d, n = min(((math.hypot(q[0] - p[0], q[1] - p[1]), n) for n, q in start.items()), default=(1e9, None))
            ids[rid] = n if d < 30 else 9000 + rid
        pos[ids[rid]] = p
    return ids, pos


def base_positions(map_name):
    """Starting-fort node positions of the map's base plan (the game's own plan, gen_fort.MAPS)."""
    import gen_fort
    cfg = gen_fort.MAPS[map_name]
    d = os.path.join(DATA, cfg["plan_dir"]) if cfg.get("plan_dir") else os.path.join(DATA, "maps", map_name)
    return {n: p for n, p in node_positions(parse_plan(os.path.join(d, cfg["base_plan"]))[1]).items() if n < 10000}


def cmd_startfort(args, terrain):
    _, actions = parse_plan(args.plan)
    snap = read_probe(args.log)
    ids, pos = map_probe(snap, actions, args.map)
    plan_pos = dict(base_positions(args.map))
    plan_pos.update(node_positions(actions))
    built = {frozenset((a["OriginalNodeAId"], a["OriginalNodeBId"])) for a in actions
             if a["Type"] == "CREATE_NODE"}
    plan_dev = {(a.get("DeviceSaveName"), frozenset((a["OriginalNodeAId"], a["OriginalNodeBId"]))) for a in actions
                if a["Type"] == "CREATE_DEVICE" and "OriginalNodeAId" in a}
    nodes, links, devices = {}, [], []
    for ra, rb, mat, _, devs in snap["links"]:
        a, b = ids[ra], ids[rb]
        if a >= 10000 or b >= 10000 or frozenset((a, b)) in built:
            continue
        for n in (a, b):
            nodes[n] = list(plan_pos.get(n, pos[n]))
        links.append([a, b, mat])
        for name, t in devs:
            if (name, frozenset((a, b))) not in plan_dev:
                devices.append([name, a, b, t])
    out = args.out or startfort_path(args.map)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as fh:
        json.dump({"map": args.map, "source": "%s (plan %s)" % (os.path.basename(args.log), os.path.basename(args.plan)),
                   "note": "struts between starting-fort nodes in the probe snapshot; materials as logged at the end of "
                           "the plan (a plan's swap of a starting-fort strut is not undone)",
                   "prestress": True, "nodes": {str(k): v for k, v in sorted(nodes.items())},
                   "links": links, "devices": devices}, fh, indent=1)
    print("starting fort: %d nodes, %d struts, %d devices -> %s" % (len(nodes), len(links), len(devices), out))


def _corr(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    return sxy / math.sqrt(sxx * syy) if sxx and syy else 0.0


def cmd_calibrate(args, terrain):
    global SPRING_LAW, STRESS_SCALE
    _, actions = parse_plan(args.plan)
    snap = read_probe(args.log)
    ids, pos = map_probe(snap, actions, args.map)
    eng = {frozenset((ids[a], ids[b])): (s, mat) for a, b, mat, s, _ in snap["links"]}
    for law in ("abs", "strain"):
        SPRING_LAW, STRESS_SCALE = law, 1.0
        rp = Replay(load_startfort(args.map, terrain), terrain).run(actions)
        st = stresses(rp.f)
        pairs = [(abs(st[k]), eng[k][0]) for k in st if k in eng]
        xs, ys = [p[0] for p in pairs], [p[1] for p in pairs]
        scale = sum(x * y for x, y in pairs) / (sum(x * x for x in xs) or 1)
        dpos = [math.hypot(rp.f.pos[n][0] - p[0], rp.f.pos[n][1] - p[1]) for n, p in pos.items() if n in rp.f.pos]
        print("law %-6s struts %d  corr %.3f  engine = %.2f x model  mean |model| %.3f mean engine %.3f  "
              "node offset to engine: mean %.1f max %.1f  broken %d refused %d" % (
                  law, len(pairs), _corr(xs, ys), scale, sum(xs) / len(xs), sum(ys) / len(ys),
                  sum(dpos) / len(dpos), max(dpos), len(rp.broken), len(rp.refused)))
        if args.verbose:
            for k in sorted(st, key=lambda k: -eng.get(k, (0,))[0])[:25]:
                if k in eng:
                    print("   %-12s %-11s engine %.3f model %.3f" % ("-".join(map(str, sorted(k))), eng[k][1],
                                                                   eng[k][0], abs(st[k])))


# ---------------------------------------------------------------------------------------------------------------

def render_png(rp, out, title=""):
    from PIL import Image, ImageDraw
    f = rp.f
    xs = [p[0] for p in f.pos.values()]
    ys = [p[1] for p in f.pos.values()]
    x0, x1, y0, y1 = min(xs) - 40, max(xs) + 40, min(ys) - 40, max(ys) + 40
    s = 3.0 if (x1 - x0) < 600 else 1.6
    img = Image.new("RGB", (int((x1 - x0) * s), int((y1 - y0) * s)), (25, 25, 25))
    d = ImageDraw.Draw(img)

    def P(p):
        return ((p[0] - x0) * s, (p[1] - y0) * s)
    for key, (a, b, mat, rest) in f.links.items():
        if a in rp.plan_pos and b in rp.plan_pos:
            d.line([P(rp.plan_pos[a]), P(rp.plan_pos[b])], fill=(60, 60, 60), width=1)
    for key, v in stresses(f).items():
        a, b, mat, _ = f.links[key]
        x = min(1.0, abs(v))
        col = (int(255 * x), int(255 * (1 - x)), 60) if v < 0 else (int(255 * x), int(200 * (1 - x)), int(255 * (1 - x)))
        d.line([P(f.pos[a]), P(f.pos[b])], fill=col, width=3 if mat in ("armour", "door") else 2)
    for name, a, b, t in f.devices:
        if a in f.pos and b in f.pos:
            p = (f.pos[a][0] + (f.pos[b][0] - f.pos[a][0]) * t, f.pos[a][1] + (f.pos[b][1] - f.pos[a][1]) * t)
            q = P(p)
            d.rectangle([q[0] - 4, q[1] - 8, q[0] + 4, q[1]], outline=(255, 255, 255))
    for n in f.fixed:
        q = P(f.pos[n])
        d.rectangle([q[0] - 3, q[1] - 3, q[0] + 3, q[1] + 3], fill=(120, 120, 255))
    d.text((5, 5), title + "  (grey: plan, colour: stress, green -> red squeezed, blue -> red stretched)",
           fill=(255, 255, 255))
    img.save(out)


def selftest():
    """Small forts with known answers (tools/tests/run_tests.sh)."""
    def cell(diagonal):
        f = Fort()
        f.pos = {1: [0.0, 0.0], 2: [100.0, 0.0], 3: [0.0, -100.0], 4: [100.0, -100.0]}
        f.fixed = {1, 2}
        for a, b in ((1, 3), (2, 4), (3, 4)):
            f.add_link(a, b, "bracing")
        if diagonal:
            f.add_link(1, 4, "bracing")
        return f
    def cantilever(n):
        """n cells of 100 x 100 sticking out from a wall, two cannons at the tip."""
        f = Fort()
        f.pos = {1: [0.0, 0.0], 2: [0.0, -100.0]}
        f.fixed = {1, 2}
        for i in range(1, n + 1):
            f.pos[2 * i + 1], f.pos[2 * i + 2] = [100.0 * i, 0.0], [100.0 * i, -100.0]
            for a, b in ((2 * i - 1, 2 * i + 1), (2 * i, 2 * i + 2), (2 * i + 1, 2 * i + 2), (2 * i, 2 * i + 1)):
                f.add_link(a, b, "bracing")
        f.devices = [["cannon", 2 * n + 1, 2 * n + 2, 0.5], ["cannon", 2 * n - 1, 2 * n + 1, 0.5]]
        return f
    f = cell(True)
    r, broken = settle(f)
    st = stresses(f)
    print("braced cell: converged=%s mechanism=%s broken=%d post %.3f" % (
        r.converged, r.mechanism, len(broken), st[frozenset((1, 3))]))
    f = cell(False)
    r = solve(f, hold=True)
    print("unbraced cell: mechanism=%s" % r.mechanism)
    for n in (2, 6):
        f = cantilever(n)
        r, broken = settle(f)
        print("two cannons on a %d-long overhang: converged=%s broken=%d tip sag %.0f" % (
            100 * n, r.converged, len(broken), f.pos[2 * n + 1][1]))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("selftest")
    c = sub.add_parser("check")
    c.add_argument("plans", nargs="+")
    c.add_argument("--map", default=None, help="map (default: from the plan's folder)")
    c.add_argument("--no-modules", action="store_true", help="leave out the plan's reactive build modules")
    c.add_argument("--png", help="draw the final fort (one plan) with stress colours")
    c.add_argument("--trace", action="store_true", help="print the worst strut after every action")
    for name in ("calibrate", "startfort"):
        p = sub.add_parser(name)
        p.add_argument("--log", required=True)
        p.add_argument("--plan", required=True)
        p.add_argument("--map", default="Vanilla")
        p.add_argument("--out")
        p.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()
    if args.cmd == "selftest":
        return selftest()
    if args.cmd == "check":
        bad = 0
        for path in args.plans:
            map_name = args.map or os.path.basename(os.path.dirname(os.path.abspath(path)))
            terrain = load_terrain(map_name)
            out = check(path, map_name, terrain, modules=not args.no_modules, trace=args.trace)
            if out and out[1] == "FALLS":
                bad += 1
            if out and args.png:
                render_png(out[0], args.png, os.path.basename(path))
        sys.exit(1 if bad else 0)
    terrain = load_terrain(args.map)
    (cmd_startfort if args.cmd == "startfort" else cmd_calibrate)(args, terrain)


if __name__ == "__main__":
    main()
