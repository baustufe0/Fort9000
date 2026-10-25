"""FORT 9000 - rule checks for Forts AI build plans (lessons from test matches, see docs/building-rules.md).

check_plan(actions, enemy_dir=+1, terrain=None) -> (errors, warnings)
  actions: parsed plan actions (fortplan.parse_plan) in plan coordinates, team 1 (enemy to the right).

Usage on plan files:  python rules.py <plan.lua> [...]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fortplan import parse_plan   # noqa: E402

# Sizes from the game files (SelectionWidth / SelectionHeight); weapon_pack is always installed.
SIZE = {
    "machinegun": (40, 40), "minigun": (40, 40), "sniper": (70, 45), "sniper2": (70, 45),
    "mortar": (40, 30), "mortar2": (40, 30), "cannon": (95, 60), "cannon20mm": (90, 55), "laser": (50, 50),
    "flak": (40, 59), "shotgun": (40, 59), "rocket": (40, 56), "rocketemp": (40, 56), "firebeam": (50, 50),
    "battery": (40, 40), "store": (40, 40), "turbine": (40, 63), "turbine2": (40, 63), "sandbags": (40, 25),
    "workshop": (90, 45), "factory": (90, 45), "upgrade": (90, 45), "munitions": (45, 85), "armoury": (45, 85),
    # dlc_smokebomb is packed (not readable): size estimated like a mortar launcher
    "smokebomb": (40, 40),
}
# Height of a device's box above its strut: the game centres the box SelectionHeight above the strut
# (SelectionOffset y = -SelectionHeight - 0.5) with half-height SelectionHeight, so it reaches 2x SelectionHeight up.
BOX_TOP = {"machinegun": 81, "minigun": 81, "sniper": 91, "sniper2": 91, "mortar": 61, "mortar2": 61,
           "cannon": 121, "cannon20mm": 111, "laser": 101, "firebeam": 101, "flak": 118, "shotgun": 118,
           "rocket": 112, "rocketemp": 112, "turbine": 127, "turbine2": 127, "battery": 81, "store": 81,
           "workshop": 91, "factory": 91, "upgrade": 91, "munitions": 170, "armoury": 170, "sandbags": 51,
           # dlc_smokebomb is packed: assumed like a turbine
           "smokebomb": 127}
# tall launchers: a solid strut through their box is an error (the other devices only get a warning; the
# munitions plant, 170 high, was built in 100-high storeys in test matches)
TALL = {"rocket", "rocketemp", "flak", "shotgun", "smokebomb"}
# weapons that fire (roughly) straight ahead and need a clear line of fire (MinFireClearance 500-1000)
DIRECT = {"machinegun", "minigun", "sniper", "sniper2", "cannon", "cannon20mm", "laser", "flak", "shotgun",
          "rocket", "rocketemp", "firebeam"}
LOBBED = {"mortar", "mortar2", "smokebomb"}
TURBINES = {"turbine", "turbine2"}
UPGRADE_OF = {"minigun": "machinegun", "sniper2": "sniper", "mortar2": "mortar", "mine2": "mine", "turbine2": "turbine",
              "shotgun": "flak", "rocket": "rocketemp"}
FOREGROUND = {"bracing", "armour", "door"}     # materials that stop shots (and wind); background bracing does not
MIN_LENGTH = 37.5          # StandardMinLength
MIN_DOOR_LENGTH = 49
FIRE_RANGE = 600           # checked length of the line of fire (beyond that it is outside the fort)
# When a weapon is placed, the game recesses foreground struts that already stand in its way within its
# RecessionBox (bracing -> background bracing, armour -> door). Struts built later, or outside the box, block it.
# The box (weapon files: Size {w, h}, Offset {x, y}, centred on the offset, x negative = forward) does not start
# at the weapon: (first, last) distance ahead it covers. A strut closer than the box is only cleared when the
# weapon's body overlaps it (the game turns struts a device overlaps into background bracing): Vanilla-5's laser
# (body 50 ahead, box from 130) never fired through the post 50 in front of it (test match 25.10.2026), while the
# 20mm (body 108 ahead) in the same cell fired 126 shots.
RECESSION = {"machinegun": (42.5, 62.5), "minigun": (130, 330), "sniper": (200, 400), "sniper2": (200, 400),
             "cannon": (200, 400), "cannon20mm": (200, 400), "laser": (130, 330), "firebeam": (130, 330),
             "flak": (60, 140), "shotgun": (70, 170), "rocket": (70, 170), "rocketemp": (70, 170)}
# A weapon's body (the box the game turns overlapped struts into background bracing with): SelectionWidth (a
# half-width in the game files) to both sides of a centre moved forward by SelectionOffset (sniper 40, cannons 18;
# the laser and machine guns are centred), 2 x SelectionHeight high (BOX_TOP). The Vanilla-2 sniper's body cleared the
# post 44 ahead of it (124 shots); the laser's (front edge 50 ahead) did not clear the post 50.4 ahead, so a strut
# must reach BODY_MARGIN into the body. Diagonals sloping back over a weapon cross its body above the barrel.
BODY_SHIFT = {"sniper": 40, "sniper2": 40, "cannon": 18, "cannon20mm": 18}
BODY_MARGIN = 5
# the earlier model: a strut built before a weapon counted as recessed up to 200 ahead (machine gun 20). Still used
# for lobbed weapons (along their arc) and by the generator's cautious mode (fire_blockers)
OLD_RECESSION = 200
OLD_RECESSION_MG = 20


def body_overlaps(name, p, a, b, enemy_dir=1):
    """True if the strut a-b reaches into the weapon's body box (shrunk by BODY_MARGIN)."""
    w = SIZE.get(name, (40, 40))[0] - BODY_MARGIN
    cx = p[0] + enemy_dir * BODY_SHIFT.get(name, 0)
    top = p[1] - BOX_TOP.get(name, 81)
    n = max(2, int(math.dist(a, b) / 2))
    for k in range(n + 1):
        x, y = a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n
        if abs(x - cx) < w and top < y < p[1] - BODY_MARGIN:
            return True
    return False


def recessed(name, dist, p, a, b, enemy_dir=1):
    """True if a strut built before the weapon, dist ahead of it in its line of fire, stops blocking it once the
    weapon is placed (inside its recession box, or overlapped by its body)."""
    first, last = RECESSION.get(name, (0, 0))
    return first <= dist <= last or body_overlaps(name, p, a, b, enemy_dir)
# mortar arc checked from the muzzle: steeply up and forward (dx, up); long enough to reach over a tower
# standing 150 in front of a lower mortar
MORTAR_ARC = (300, 520)
TURBINE_SPACING = 90       # two turbines 46-54 apart failed with CS_OCCUPIED; the game's plan uses ~100
# mortars 77 apart on the two halves of a split strut: the second refused (CS_UNSTABLE, later CS_OCCUPIED) in two
# test matches (25.10.2026); the game's own plans space them 91-122 apart (Abyss-1: 91-96), 127 apart both were placed
MORTAR_SPACING = 90
LOBBED = {"mortar", "mortar2", "smokebomb"}
# Wind test of the game (devices/windturbine.lua): rays to both sides from MinTestDistance 25 to MaxTestDistance
# 600, between MinWindAngle -10 and MaxWindAngle 10 degrees. Everything except background bracing, shields,
# rope and fuse collides with the wind (CollidesWithWind = false in building_materials.lua).
WIND_MIN, WIND_MAX, WIND_ANGLE, WIND_STEP = 25, 600, 10, 2
WIND_OPEN = 0.5            # a side counts as open when at least this share of its rays is clear


def _cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def segments_cross(p1, p2, q1, q2):
    """Proper intersection of two segments (touching endpoints does not count)."""
    d1, d2 = _cross(q1, q2, p1), _cross(q1, q2, p2)
    d3, d4 = _cross(p1, p2, q1), _cross(p1, p2, q2)
    return ((d1 > 1e-6 and d2 < -1e-6) or (d1 < -1e-6 and d2 > 1e-6)) and \
           ((d3 > 1e-6 and d4 < -1e-6) or (d3 < -1e-6 and d4 > 1e-6))


def build_state(actions):
    """Final state of the plan: node positions, links {pair: (material, a, b, action index)},
    devices [(name, a, b, t, pair, action index)], ground devices [(name, pos)]."""
    pos, links, devices, ground = {}, {}, [], []
    for k, a in enumerate(actions):
        ida, idb = a.get("OriginalNodeAId"), a.get("OriginalNodeBId")
        if ida is not None and "PosA" in a:
            pos.setdefault(ida, a["PosA"])
        if a["Type"] == "CREATE_NODE":
            pos[idb] = a["NewNodePos"]
            links[frozenset((ida, idb))] = (a.get("MaterialSaveName"), ida, idb, k)
        elif idb is not None and "PosB" in a:
            pos.setdefault(idb, a["PosB"])
        if a["Type"] == "CREATE_LINK":
            links[frozenset((ida, idb))] = (a.get("MaterialSaveName"), ida, idb, k)
        elif a["Type"] == "CREATE_DEVICE":
            name = a.get("DeviceSaveName")
            if "GroundPosition" in a:
                ground.append((name, a["GroundPosition"]))
                continue
            pair = frozenset((ida, idb))
            # an upgrade replaces the device at the same place
            base = UPGRADE_OF.get(name)
            if base:
                devices = [d for d in devices if not (d[0] == base and d[4] == pair and abs(d[3] - a["LinkT"]) < 0.02)]
            devices.append((name, ida, idb, a["LinkT"], pair, k))
        elif a["Type"] == "DESTROY_DEVICE":
            # the game's own plans sell a device to free its strut (Abyss-1: sandbags, then a laser there)
            pair = frozenset((ida, idb))
            devices = [d for d in devices if not (d[0] == a.get("DeviceSaveName") and d[4] == pair)]
    return pos, links, devices, ground


def node_chains(actions, terrain=None, ground_tol=3):
    """Chain depth of every node the plan creates: how many node creations lie between it and an anchor (a node
    of the starting fort, or a node on the ground, which the game places at its absolute position). The game
    places every other new node relative to the CURRENT position of its source node (GetAdjustedNodePosition),
    so a lean of any node in the chain is copied into it: short chains keep the fort in shape."""
    depth = {}
    for a in actions:
        if a["Type"] != "CREATE_NODE":
            continue
        p = a["NewNodePos"]
        on_ground = terrain is not None and (terrain.inside(p) or terrain.nearest_surface(p)[1] <= ground_tol)
        depth[a["OriginalNodeBId"]] = 0 if on_ground else depth.get(a["OriginalNodeAId"], 0) + 1
    return depth


def _point(pos, ida, idb, t):
    a, b = pos[ida], pos[idb]
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def _blocking(links, pos, p, q, skip=()):
    """Foreground links crossing the segment p-q (except those in skip): [(material, a, b, action, pair)]."""
    out = []
    for pair, (mat, ia, ib, k) in links.items():
        if mat not in FOREGROUND or pair in skip or ia not in pos or ib not in pos:
            continue
        if segments_cross(p, q, pos[ia], pos[ib]):
            out.append((mat, pos[ia], pos[ib], k, pair))
    return out


def _cross_dist(p, q, a, b):
    """Distance from p along p-q to the crossing with a-b."""
    d = (q[0] - p[0], q[1] - p[1])
    e = (b[0] - a[0], b[1] - a[1])
    den = d[0] * e[1] - d[1] * e[0]
    if abs(den) < 1e-9:
        return 0
    s = ((a[0] - p[0]) * e[1] - (a[1] - p[1]) * e[0]) / den
    return s * math.hypot(*d)


def wind_rays(links, pos, hub, terrain=None):
    """Share of clear wind rays on the left and right of a turbine hub: (left, right), 0..1."""
    out = []
    for side in (-1, 1):
        n = clear = 0
        for deg in range(-WIND_ANGLE, WIND_ANGLE + 1, WIND_STEP):
            r = math.radians(deg)
            d = (side * math.cos(r), math.sin(r))
            p = (hub[0] + WIND_MIN * d[0], hub[1] + WIND_MIN * d[1])
            q = (hub[0] + WIND_MAX * d[0], hub[1] + WIND_MAX * d[1])
            n += 1
            if not _blocking(links, pos, p, q) and (terrain is None or terrain.segment_clear(p, q, end_margin=0)):
                clear += 1
        out.append(clear / n)
    return tuple(out)


def turbine_hub(p):
    return (p[0], p[1] - 0.55 * SIZE["turbine"][1])


def fire_lines(name, p, enemy_dir=1):
    """Segments a weapon at base point p needs free: direct fire straight ahead, mortars steep forward."""
    w, h = SIZE.get(name, (40, 40))
    muzzle = (p[0], p[1] - 0.6 * h)
    if name in DIRECT:
        return [(muzzle, (p[0] + enemy_dir * FIRE_RANGE, muzzle[1]))]
    if name in LOBBED:
        return [(muzzle, (p[0] + enemy_dir * MORTAR_ARC[0], muzzle[1] - MORTAR_ARC[1]))]
    return []


def fire_blockers(links, pos, name, p, k_dev, enemy_dir=1, cautious=False):
    """Foreground struts that block a weapon: built after it anywhere in its line of fire, or (built before)
    outside its recession box and its body (recessed()); doors in front of it are its own (opened to fire).
    cautious (the generator's clear_fire_lines): also every strut the earlier model called blocking (beyond
    OLD_RECESSION, machine gun OLD_RECESSION_MG), so plans that fired in test matches keep every strut they cleared."""
    out = []
    for p0, p1 in fire_lines(name, p, enemy_dir):
        for m, a, b, k, pair in _blocking(links, pos, p0, p1):
            dist = _cross_dist(p0, p1, a, b)
            if m == "door":
                continue                    # the AI opens all doors in the way before firing (OpenWeaponDoors)
            if k < k_dev:                   # built before the weapon: recessed by the game when it is placed?
                if name not in DIRECT:
                    if dist <= OLD_RECESSION:
                        continue
                elif recessed(name, dist, p, a, b, enemy_dir) and not (
                        cautious and dist > (OLD_RECESSION_MG if name == "machinegun" else OLD_RECESSION)):
                    continue
            out.append((m, a, b, k, pair, dist))
    return out


def _fmt(p):
    return "(%d,%d)" % (round(p[0]), round(p[1]))


def check_plan(actions, enemy_dir=1, terrain=None):
    errors, warnings = [], []
    pos, links, devices, ground = build_state(actions)

    # strut lengths
    for pair, (mat, ia, ib, k) in links.items():
        if ia in pos and ib in pos:
            L = math.dist(pos[ia], pos[ib])
            need = MIN_DOOR_LENGTH if mat == "door" else MIN_LENGTH
            if L < need - 0.5:
                errors.append("strut %s-%s %s too short (%.0f < %.1f)" % (_fmt(pos[ia]), _fmt(pos[ib]), mat, L, need))

    for name, ia, ib, t, pair, kd in devices:
        if ia not in pos or ib not in pos:
            continue
        p = _point(pos, ia, ib, t)
        w, h = SIZE.get(name, (40, 40))
        mat = links.get(pair, (None,))[0]
        where = "%s at %s" % (name, _fmt(p))
        # background bracing cannot carry devices (SupportsDevices = false); the game's own Template-1
        # nevertheless records a sniper on one (recorded plans may show the recessed material)
        if mat == "backbracing":
            warnings.append("%s stands on background bracing (SupportsDevices = false)" % where)
        # line of fire / mortar arc
        for m, a, b, k, pr, dist in fire_blockers(links, pos, name, p, kd, enemy_dir)[:1]:
            errors.append("%s: %s blocked by %s %s-%s, %.0f ahead%s" % (
                where, "line of fire" if name in DIRECT else "mortar arc", m, _fmt(a), _fmt(b), dist,
                " (built after the weapon, not recessed)" if k > kd else " (outside the recession box and the body)"))
        # nothing solid inside the device's box above its strut
        top = BOX_TOP.get(name)
        if top and name not in TURBINES:
            hits = set()
            for dx in (-w / 2, 0, w / 2):
                q0, q1 = (p[0] + dx, p[1] - 3), (p[0] + dx, p[1] - top)
                for m, a, b, k, pr in _blocking(links, pos, q0, q1, skip={pair}):
                    if ia in pr or ib in pr:
                        continue            # the posts at the ends of its own strut
                    hits.add((m, _fmt(a), _fmt(b)))
            for m, a, b in sorted(hits)[:1]:
                (errors if name in TALL else warnings).append(
                    "%s: %s %s-%s inside its box (%d high)" % (where, m, a, b, top))
        # turbines need wind from both sides (the game's ray test, see wind_rays)
        if name in TURBINES:
            shares = wind_rays(links, pos, turbine_hub(p), terrain)
            blocked = [side for side, sh in zip(("left", "right"), shares) if sh < WIND_OPEN]
            info = "%d%% / %d%% of the rays clear" % (100 * shares[0], 100 * shares[1])
            if len(blocked) == 2:
                errors.append("%s: no wind (%s)" % (where, info))
            elif blocked:
                warnings.append("%s: wind blocked on the %s side (%s)" % (where, blocked[0], info))

    # one device per strut; devices on neighbouring struts must not overlap; turbines and mortars need ~100 between them
    for k, (n1, a1, b1, t1, pr1, _) in enumerate(devices):
        for n2, a2, b2, t2, pr2, _ in devices[k + 1:]:
            if a1 not in pos or b1 not in pos or a2 not in pos or b2 not in pos:
                continue
            p1, p2 = _point(pos, a1, b1, t1), _point(pos, a2, b2, t2)
            need = (SIZE.get(n1, (40,))[0] + SIZE.get(n2, (40,))[0]) / 2
            if pr1 == pr2:
                # the game allows one device per strut (test match 25.10.2026: sandbags beside a mortar took it)
                errors.append("%s at %s and %s at %s share one strut (one device per strut)" % (n1, _fmt(p1), n2, _fmt(p2)))
            elif abs(p1[1] - p2[1]) < 10 and abs(p1[0] - p2[0]) < need - 1:
                # side by side on neighbouring struts at the same height (a device wider than the rest of its
                # strut reaches over the shared node)
                errors.append("%s at %s and %s at %s overlap (neighbouring struts)" % (n1, _fmt(p1), n2, _fmt(p2)))
            if n1 in TURBINES and n2 in TURBINES and abs(p1[1] - p2[1]) < 20 and math.dist(p1, p2) < TURBINE_SPACING:
                errors.append("turbines at %s and %s only %.0f apart (need %d)" % (_fmt(p1), _fmt(p2), math.dist(p1, p2), TURBINE_SPACING))
            if n1 in LOBBED and n2 in LOBBED and abs(p1[1] - p2[1]) < 20 and math.dist(p1, p2) < MORTAR_SPACING:
                errors.append("%s at %s and %s at %s only %.0f apart (need %d)" % (n1, _fmt(p1), n2, _fmt(p2), math.dist(p1, p2), MORTAR_SPACING))

    # nothing lying on the rock across a mine site (the mine would be blocked)
    for name, g in ground:
        if name not in ("mine", "mine2"):
            continue
        for pair, (mat, ia, ib, k) in links.items():
            if ia in pos and ib in pos:
                a, b = pos[ia], pos[ib]
                if abs(a[1] - g[1]) < 6 and abs(b[1] - g[1]) < 6 and min(a[0], b[0]) - 40 < g[0] < max(a[0], b[0]) + 40:
                    errors.append("%s strut %s-%s lies on the mine site at %s" % (mat, _fmt(a), _fmt(b), _fmt(g)))
    return errors, warnings


def main():
    for path in sys.argv[1:]:
        head, acts = parse_plan(path)
        # team 1 plans face the enemy on the right, team 2 plans (e.g. VanillaLong) on the left
        errors, warnings = check_plan(acts, enemy_dir=-1 if head.get("team") == 2 else 1)
        print("%s: %d errors, %d warnings" % (os.path.basename(path), len(errors), len(warnings)))
        for e in errors:
            print("   RULE ERROR:", e)
        for w in warnings:
            print("   RULE WARN: ", w)


if __name__ == "__main__":
    main()
