#!/usr/bin/env python3
"""FORT 9000 - plans for the hanging forts of Stalactites (1v1 and 2v2), on top of gen_fort.py.

The forts of Stalactites hang from the underside of a stalactite (the game's shared starting fort and plans
ai/forts/hanging/long, TemplateHang-1 recorded on Stalactites 1v1; .dev/docs/maps/stalactites.md). This module adds
the map and its variants to gen_fort (MAPS["Stalactites"], STALACTITES_VARIANTS) and runs gen_fort's own main(), so the
generator file stays the same for the other maps. Hanging changes little for the grid generator: cells are built top
down from the starting fort (no require_support: that rule knows support from below only), every new node is created
from a built neighbour, and foundations on the underside are snapped like ground foundations.

    py gen_hang.py --out <dir>                      # writes fort-t1f1-Stalactites-1..4.lua
    py gen_hang.py physics <plans...>               # physics.py check with the map registered

Plan frame (team 1, enemy to the right, y down): the stalactite x -3150..-2500, its underside at y -1350 (the
starting fort's foundations x -3000..-2500); the mine pocket above it, floor y -1500, open to the front; the reactor
centred on its strut at (-2799, -998), box x -2844..-2754, y -1083..-913. Fort 2 of the 2v2 map is the same starting
fort 1600 back and 1200 lower (FortPos (-4100, -150)): both spots' terrain is laid over the plan frame (fwe_frame).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_fort  # noqa: E402
import rules  # noqa: E402
from gen_fort import _box, _union  # noqa: E402

# Rows: the pocket mouth (-1500), the underside (-1350), the starting fort's storeys (-1198, -1098, -997, -897; -1200
# on the grid: the back posts up to the underside foundations are then 150, StandardMaxLength), two
# 130-high weapon storeys below it and the turbine gallery at the bottom (-637..-507, 130 high: a turbine's box is 127,
# two stacked sandbags 2 x 51). Columns: from row -997 up the starting fort's posts (-2803, -2703, -2603: its rows
# -1198 and -997); below, its bottom nodes (-2753, -2653, -2503) and a 75-wide pair behind the reactor's bottom left
# corner (x -2844 at y -913, 16 above the row -897). The front column is 135 wide (a 150-high cell's diagonal
# within MAX_LINK): in a 100-wide one a sniper's body (70 to each side of a centre 40 ahead of its LinkT point) filled
# the cell and its door could not be cut short and doubled (split_doors found no brace clear of it); its top right
# corner is the starting fort's node 132 (-2401, -1348). The last two columns (-2268, -2168) are outside the shape: the
# generator looks one cell past the front.
_S_ROWS = [-1500, -1350, -1200, -1098, -997, -897, -767, -637, -507]
_S_COLS_UPPER = [-3100, -3000, -2900, -2803, -2703, -2603, -2503, -2368, -2268, -2168]
_S_COLS = [-3100, -3000, -2925, -2850, -2753, -2653, -2503, -2368, -2268, -2168]

# the shape: the back block (tech and eco, against the stalactite's back half), the front column (weapons, in front
# of the starting fort's front post, x -2503), and the bottom (two weapon storeys and the turbine gallery)
_S_BACK = _box(-3100, -2900, -1350, -637)
_S_FRONT = _box(-2503, -2368, -1350, -507)
_S_BOTTOM = _box(-3100, -2368, -897, -507)
_S_SHAPE = _union(_S_BACK, _S_FRONT, _S_BOTTOM)

# The turbine gallery: turbines on its floor (-507) at LinkT 0.5, background bracing all round (the wind passes, the
# player sees nothing), its front cell split at half height for two stacked sandbags. Below it there is nothing (the
# abyss), to its left open air for ~800 (the back wall reaches x -3891 at y -552), to its right the enemy.
_S_GALLERY = dict(turbine_floor_y=-507, turbine_floor_t=0.5, turbine_roof_max_y=-10000, turbine_min_w=95,
                  turbine_row_open=True, hidden_box=[(-3100, -2368, -637, -507)],
                  split_cell=[(-2503, -637)], sandbag_slots=[(0, "floor", 0.5), (0, "mid", 0.5)])

# The hub (like Vanilla's, before the first plan step): a node inside the starting fort's two front storeys, background
# spokes up to the underside foundations 131 and 142 and to the front post's nodes around it. The front column hangs on
# the starting fort's front post 131-140-158-161-162; its weakest piece 140-158 was the peak of every plan (physics.py
# 0.46-0.71), with the hub the load goes up to the rock directly (rockets 0.71 -> 0.60, miniguns 0.46 -> 0.33).
# Background bracing: the starting machine gun fires through the lane below.
_S_HUB_NODE = (-2545, -1175)
_S_HUB = [((-2501.92, -1198.62), _S_HUB_NODE, "backbracing")] + [
    (_S_HUB_NODE, q, "backbracing") for q in ((-2500.0, -1350.0), (-2600.0, -1350.0), (-2602.0, -1198.5),
                                              (-2503.24, -1096.45), (-2502.82, -996.69), (-2602.7, -996.8),
                                              (-2652.3, -1097.6))]

# The shield of the storey under the mines (the anchor row: a player cuts the fort off the rock there) and of the mine
# pocket, early in every plan (after the first mine). Nothing fires in these rows (the top front cell is armour, the
# first weapon row is -1098), so the wood can be solid:
# - the pocket mouth (x -2500, y -1650..-1500, the only opening to the mines) armour: the starting fort's post 134-135
#   and a new foundation on the pocket's roof edge (-2500, -1650);
# - the starting fort's front post 133-132 (x -2400, below the pocket floor) armour;
# - two wood layers in front (x -2320, -2280) from y -1590 (in front of the pocket mouth) down to y -1200,
#   triangulated; the first is braced back to the pocket wall's foundation (-2500, -1650). The rock lip over the mouth
#   takes no foundations (its edges are "rocks01", only "foundations" edges do): the lip foundation (-2320, -1686) of
#   the first version was refused with CS_OBSTRUCTION (Stalactites-3 match, 01.11.2026).
_S_SHIELD = ("struts", [
    ((-2500.0, -1500.0), (-2499.33, -1599.47), "armour"),
    ((-2499.33, -1599.47), (-2500, -1650), "armour"),
    ((-2400.17, -1498.31), (-2400.8, -1348.2), "armour"),
    ((-2400.17, -1498.31), (-2320, -1500), "bracing"),
    ((-2400.8, -1348.2), (-2320, -1350), "bracing"),
    ((-2320, -1500), (-2320, -1350), "bracing"),
    ((-2320, -1500), (-2320, -1590), "bracing"),
    ((-2320, -1590), (-2500, -1650), "bracing"),
    ((-2320, -1590), (-2400.17, -1498.31), "bracing"),
    ((-2320, -1500), (-2400.8, -1348.2), "bracing"),
    ((-2368, -1200), (-2320, -1200), "bracing"),
    ((-2320, -1350), (-2320, -1200), "bracing"),
    ((-2400.8, -1348.2), (-2320, -1200), "bracing"),
    ((-2320, -1500), (-2280, -1500), "bracing"),
    ((-2320, -1350), (-2280, -1350), "bracing"),
    ((-2320, -1200), (-2280, -1200), "bracing"),
    ((-2280, -1500), (-2280, -1350), "bracing"),
    ((-2280, -1350), (-2280, -1200), "bracing"),
    ((-2320, -1500), (-2280, -1350), "bracing"),
    ((-2320, -1350), (-2280, -1200), "bracing"),
])


def _shielded(plan):
    """The plan with _S_SHIELD right after its first step that builds a mine (the top front cell first: the lowest
    layer struts start at its front node (-2368, -1200))."""
    k = next(i for i, (step, items) in enumerate(plan) if step == "eco" and "mine" in items)
    return plan[:k + 1] + [("build", [(-2503, -1200)]), _S_SHIELD] + plan[k + 1:]


# The deep fort (plans with four heavy or tall front weapons: 20mm cannons, cannons and rockets need a storey of 125+,
# their boxes are 111-121 high): below the starting fort four 135-high storeys and the gallery (-357..-222). 135, not
# 130: a cannon's door cut to its shot (92.5) left an armour piece of exactly 37.5 (StandardMinLength) in a 130-high
# storey, and the ties between stacked outer doors were as short; both were refused in physics.py once the fort sagged.
# The munitions plant and the armoury (170 high) stand on a back-block floor and reach through the storey above
# (clear_boxes: the struts they cross become background bracing).
_S_DEEP_ROWS = _S_ROWS[:6] + [-762, -627, -492, -357, -222]
_S_DEEP_SHAPE = _union(_box(-3100, -2900, -1350, -492), _box(-2503, -2368, -1350, -222), _box(-3100, -2368, -897, -222))
_S_DEEP = dict(rows=_S_DEEP_ROWS, turbine_floor_y=-222, hidden_box=[(-3100, -2368, -357, -222)],
               split_cell=[(-2503, -357)],
               crossbrace_keep=[(-2503, -2368, -1350, -357), (-3100, -2368, -897, -357)],
               large_t=0.2)
# The gallery's narrow cells behind the reactor (75 wide, no turbine fits) right after the first turbine: left to the
# final pass, the bottom had sheared by then and their 75-long struts were 25-33 long (physics.py, refused)
_S_GALLERY_NARROW = ("build", [(-3000, -222), (-2925, -222)])
# Heavy weapons and rockets stand in the cell behind the front column (x -2653..-2503, 150 wide) and fire through the
# front cell, their lane (door in front, background diagonals): in the front cell itself a cannon's body (95 to each
# side of a centre 18 ahead of its LinkT point) filled the 135-wide cell, and split_doors found no brace clear of it,
# so the door stayed one full door (the AP sniper shoots through one)
# The smoke launcher (lobbed, assumed 127 high) needs open air above it: in a hanging fort only in front of the front
# column. A perch hung from the front column's nodes at x -2368 in the storey -897..-762 (130 high): wooden floor, a
# door roof and a door in front, a background diagonal, and a background hanger up to (-2368, -997) (the starting machine
# gun fires through it at ~-937). The front cell behind it holds no weapon (the perch stands in its line of fire). Its
# front x -2260 is off the grid (the grid's spare column -2268 would be a node the struts step does not create).
_S_PERCH = ("struts", [((-2368, -897), (-2260, -897), "door"), ((-2368, -762), (-2260, -762), "bracing"),
                       ((-2260, -897), (-2260, -762), "door"), ((-2368, -897), (-2260, -762), "backbracing"),
                       ((-2368, -997), (-2260, -897), "backbracing")])
# The weapons below the perch get their second door from it: the perch's front door continued down as an outer door wall
# x -2260 (108 in front of the front post) to the cannon's floor, tied back to the front post at every floor, braced
# with background bracing like the generator's layers (its own outer layer at x -2318 would start on the perch's floor
# and on these ties). door_layer_skip keeps the generator from hanging a third layer on it.
def _s_door_wall(top, floors):
    out = []
    for y in floors:
        out += [((-2260, top), (-2260, y), "door"), ((-2368, y), (-2260, y), "armour"),
                ((-2368, top), (-2260, y), "backbracing")]
        top = y
    return ("struts", out)

MAP = {
    "plan_dir": "ai/forts/hanging/long",
    "base_plan": "fort-t1f1-TemplateHang-1.lua",
    "fwe": "Stalactites.fwe",
    "solid_minus1": True,          # the cave ceiling and the back walls are block -1
    # both 2v2 spots in the plan frame (fort 1 is also the 1v1 fort): x' = -2500 + (x - anchor x), y' = -1350 + ...
    "fwe_frame": {"plan_anchor": (-2500, -1350), "anchors": [((-2500, -1350), False), ((-4100, -150), False)]},
    "cols": _S_COLS,
    "upper_y": -997,
    "cols_upper": _S_COLS_UPPER,
    "rows": _S_ROWS,
    "reactor": (-2799, -998),
    # the starting fort's body (the reactor and the struts around it): no cells; its front post x -2503 is the back
    # wall of the front column
    "keepout": [(-2900, -2510, -1350, -897),
                # in front of the pocket mouth (the starting fort's nodes 133/132 would make it a connecting cell)
                (-2400, -2200, -1500, -1350)],
    "snap": 45,
    "ground_snap": 25,
    "rock_clear": 15,
    # the underside foundations are created from the node below them (straight up, at most 150), never along the rock
    "found_from_below": True,
    # cells hang from the cells above them (filter_supported_hanging), built after them
    "require_support": True,
    "hanging": True,
    # the plans' devices stand where the generator puts them (no proven slots of the game's plan fit this shape: its
    # workshop and factory stand around the reactor)
    "tech_slots": {
        # the back block's floors, the device at the right end of the back cell (its box x -3095..-2915 over the
        # post x -3000, which turns to background bracing; tech_spill)
        "workshop": [((-3100, -1200), (-3000, -1200), 0.95)],
        "upgrade": [((-3100, -997), (-3000, -997), 0.95)],
        "factory": [((-3100, -767), (-3000, -767), 0.95)],
    },
    "tech_spill": True,
    "prereq": {"cannon": "munitions", "cannon20mm": "munitions", "munitions": "workshop"},
    # batteries and stores high in the back block first, so its column is built down from the underside: on the lowest
    # free floors (the generator's default) the back column was built up from the gallery, and the struts closing it
    # to the underside were 240-277 long when the fort had sagged (physics.py, refused)
    "use_eco_slots": True,
    "eco_slots": [((-3100, -1098), (-3000, -1098), 0.5), ((-3000, -1098), (-2900, -1098), 0.5),
                  ((-3100, -897), (-3000, -897), 0.5), ((-3000, -897), (-2925, -897), 0.5)],
    "eco_orig": False,
    # the mine pocket's floor (TemplateHang-1's three sites; TemplateHang-2 puts a fourth at -2695.75, between the
    # starting fort's pocket posts, last in every plan)
    "mines": [
        {"ground": (-2823.35, -1500.0)},
        {"ground": (-2950.95, -1500.0)},
        {"ground": (-3078.55, -1500.0)},
        {"ground": (-2695.75, -1500.0)},
    ],
    "rebrace_after_mine": [],
    # the starting fort's machine gun stands on its bottom strut 162-157 (y -897) and fires through its door 161-162 at
    # x -2503: the front cell ahead of it is a fire lane (door in front, background diagonals)
    "lane_cells": [(-2503, -897)],
    "clear_fire_lines": True,
    "split_doors": True,
    # the front post sags against the weapon behind it: the doors reach door_sag higher than the shot needs
    "door_sag": 25,
    # both diagonals of every cell background bracing (background_skeleton), not through the reactor or the starting
    # machine gun's cell (strut 162-157, y -897, firing through door 161-162 at x -2503)
    "skeleton": True,
    "skeleton_keepout": [(-2844, -2754, -1083, -913), (-2610, -2503, -997, -897)],
    # the starting fort's storeys (the neck every hanging load passes) and the storey above the deep fort
    "skeleton_levels": {-1275: 8, -1150: 8, -1047: 8, -947: 8},
    "door_layers": 2,
    "light_roof": True,
    "weapon_min_w": 95,
    "weapon_pick_best": True,
    "single_diagonal": True,
    # the front column and the two weapon storeys crossbraced (what the enemy shoots at, heavy weapons)
    "crossbrace_keep": [(-2503, -2368, -1350, -637), (-3100, -2368, -897, -637)],
    "aa_y": -1050,
    "spr_map": "Stalactites",
    "header": "FortTeam = 1; FortId = 1; FortPos = { x = -2500.000000, y = -1350.000000 }; ",
    "variants": "STALACTITES_VARIANTS",
    "footing": _S_HUB,
}
MAP.update(_S_GALLERY)

# Front cells (left x -2503) by floor: -1200 (150 high, its front from the starting fort's node 132 slanted: no short
# door fits) stays armour and shields the anchor row on the underside; -1098 and -997 (100 high: a weapon there keeps a
# full door, split_doors finds no brace clear of a sniper's box) take machine guns, or the first sniper; -897 is the
# starting fort's machine gun's fire lane; -767 and -637 (130 high) take the snipers and the laser behind two short
# doors in a row (door_layers) against the AP sniper.
STALACTITES_VARIANTS = {
    # 1, cannons: an early sniper, then the workshop and the munitions plant (on the back block's floor -627, through
    # the storey above), two 20mm cannons (-627, -357) and two cannons (-762, -492) one above the other behind the deep
    # fort's four 135-high front cells, each its own row, firing through its lane and short doors
    "cannons": {
        "title": "Early sniper, then two 20mm cannons and two cannons in the front column, deep fort (Stalactites)",
        "shape": _S_DEEP_SHAPE,
        "tech_slots": {"munitions": [((-3100, -627), (-3000, -627), 0.5)]},
        # the second door layer on every other row (cannons): on all four the outer doors hanging off the front post
        # x -2368 took its armour to 0.78 in physics.py, on two 0.64
        "cfg": dict(_S_DEEP, clear_boxes=["munitions"],
                    large_cells=[(-2503, -627, 0.2), (-2503, -762, 0.2), (-2503, -357, 0.2), (-2503, -492, 0.2)],
                    weapon_cells=[(-2503, -997, "sniper", 0.2), (-2503, -1098, "machinegun", 0.5)]),
        "plan": [
            ("weapons", ["sniper"]),
            ("tech", ["workshop"]),
            ("eco", ["mine"]),
            ("tech", ["munitions"]),
            # a 20mm costs 600 metal / 4000 energy, a cannon more: a store and a battery before the first
            ("eco", ["mine", "store", "battery"]),
            ("weapons", ["cannon20mm"]),
            ("eco", ["turbine"]),
            _S_GALLERY_NARROW,
            ("weapons", ["cannon"]),
            ("defence", ["sandbags", "sandbags"]),
            ("aa", ["machinegun"]),
            ("eco", ["turbine", "mine"]),
            ("weapons", ["cannon20mm"]),
            ("tech", ["upgrade"]),
            ("eco", ["battery"]),
            ("upgrades", ["sniper2"]),
            ("eco", ["turbine"]),
            ("weapons", ["cannon"]),
            ("upgrades", ["turbine2", "turbine2"]),
            ("upgrades", ["minigun"]),
            ("eco", ["mine", "turbine"]),
            ("upgrades", ["mine2", "mine2"]),
        ],
    },
    # 2, laser: workshop -> factory -> laser behind the 130-high front cell below the starting fort, a sniper below it
    "laser": {
        "title": "Laser below the starting fort, a sniper below it and a minigun above, turbines in the bottom gallery (Stalactites)",
        "shape": _S_SHAPE,
        # laser and sniper behind the front column (x -2653..-2503), firing through its empty cells (lanes): in the front
        # column below the starting fort plan 4's snipers were refused with CS_UNSTABLE (see miniguns)
        "cfg": {"large_cells": [(-2503, -767, 0.2)],
                "weapon_cells": [(-2503, -637, "sniper", 0.2), (-2503, -1098, "machinegun", 0.5)]},
        "plan": [
            ("tech", ["workshop"]),
            ("eco", ["mine"]),
            ("tech", ["factory"]),
            ("weapons", ["sniper"]),
            ("eco", ["turbine", "mine", "store", "battery"]),
            ("weapons", ["laser"]),
            ("eco", ["turbine"]),
            ("defence", ["sandbags", "sandbags"]),
            ("aa", ["machinegun"]),
            ("eco", ["mine", "turbine"]),
            ("tech", ["upgrade"]),
            ("eco", ["battery"]),
            ("upgrades", ["sniper2"]),
            ("upgrades", ["turbine2", "turbine2"]),
            ("upgrades", ["minigun"]),
            ("eco", ["turbine", "mine"]),
            ("upgrades", ["mine2"]),
        ],
    },
    # 3, rockets: the armoury first, two EMP rockets (-> rockets) behind the front cells -627 and -492, the smoke launcher on
    # the perch in front of the empty cell -762, two machine guns (-> miniguns) in the 100-high cells; late the
    # munitions plant (the armoury opens it, PrerequisiteAlt) and a cannon behind the lowest front cell (-357)
    "rockets": {
        "title": "Rocket rush with smoke: two EMP rockets -> rockets, smoke launcher perch, two miniguns, late cannon, deep fort (Stalactites)",
        "shape": _S_DEEP_SHAPE,
        "tech_slots": {"armoury": [((-3100, -627), (-3000, -627), 0.5)],
                       "munitions": [((-3000, -492), (-2925, -492), 0.6)]},
        # the second door layer for the first rocket and the cannon (every other row, see cannons)
        "cfg": dict(_S_DEEP, clear_boxes=["armoury", "munitions"],
                    door_layer_skip=[(-2260, -627), (-2260, -492), (-2260, -357)],
                    prereq={"cannon": "munitions", "cannon20mm": "munitions", "munitions": "armoury"},
                    large_cells=[(-2503, -357, 0.2)],
                    weapon_cells=[(-2503, -627, "rocketemp", 0.2), (-2503, -492, "rocketemp", 0.2),
                                  (-2503, -1098, "machinegun", 0.5), (-2503, -997, "machinegun", 0.5)],
                    lane_cells=[(-2503, -897)],
                    weapon_struts=[((-2368, -762), (-2260, -762), 0.5, "smokebomb")]),
        "plan": [
            ("tech", ["armoury"]),
            ("eco", ["mine"]),
            ("aa", ["machinegun"]),
            # the perch hangs on the front cell -897..-762 (built first, with the lane cell above it); its door continued
            # down is the upper rocket's second door, so it comes before the rocket
            ("build", [(-2503, -762), (-2503, -627)]),
            _S_PERCH,
            _s_door_wall(-762, [-627]),
            ("weapons", ["rocketemp"]),
            ("eco", ["turbine", "mine"]),
            _S_GALLERY_NARROW,
            ("build", [(-2503, -492)]),
            _s_door_wall(-627, [-492]),
            ("weapons", ["rocketemp"]),
            ("weapons", ["smokebomb"]),
            ("tech", ["upgrade"]),
            ("eco", ["turbine", "battery"]),
            ("upgrades", ["rocket", "rocket"]),
            ("defence", ["sandbags", "sandbags"]),
            ("aa", ["machinegun"]),
            ("upgrades", ["minigun", "minigun"]),
            ("eco", ["mine", "store", "turbine"]),
            ("tech", ["munitions"]),
            ("build", [(-2503, -357)]),
            _s_door_wall(-492, [-357]),
            ("weapons", ["cannon"]),
            ("upgrades", ["turbine2", "turbine2"]),
            ("eco", ["battery", "mine"]),
            ("upgrades", ["mine2", "mine2"]),
        ],
    },
    # 4, miniguns: two machine guns early (one front cell each), the upgrade centre, both become miniguns, two snipers
    # (-> AP snipers) below them, behind the front column
    "miniguns": {
        "title": "Two miniguns and two AP snipers in the front column, turbines in the bottom gallery (Stalactites)",
        "shape": _S_SHAPE,
        # the snipers behind the front column, firing through its empty cells: in the front column itself (x -2503..-2368,
        # hanging ~600 below the rock) both were refused with CS_UNSTABLE in both Stalactites-4 forts of the 2v2 match
        # (01.11.2026, the game saw the nodes moving: v=2-3) and given up; the cells behind hang on the starting fort's
        # posts like plan 3's rockets, which were placed
        "cfg": {"weapon_cells": [(-2503, -1098, "machinegun", 0.5), (-2503, -997, "machinegun", 0.5),
                                 (-2503, -767, "sniper", 0.2), (-2503, -637, "sniper", 0.2)]},
        "plan": [
            ("aa", ["machinegun"]),
            ("eco", ["mine"]),
            ("weapons", ["sniper"]),
            ("eco", ["turbine", "mine"]),
            ("tech", ["upgrade"]),
            ("aa", ["machinegun"]),
            ("eco", ["turbine", "battery"]),
            ("upgrades", ["minigun"]),
            ("defence", ["sandbags", "sandbags"]),
            ("eco", ["mine", "store"]),
            ("upgrades", ["minigun"]),
            ("upgrades", ["sniper2"]),
            ("eco", ["turbine"]),
            ("weapons", ["sniper"]),
            ("upgrades", ["turbine2", "turbine2"]),
            ("eco", ["battery", "mine"]),
            ("upgrades", ["sniper2", "mine2"]),
        ],
    },
}


_filter_supported = gen_fort.Plan.filter_supported


def filter_supported_hanging(self):
    """require_support for a hanging fort (cfg "hanging"): the mirror of gen_fort's rule. A node is held if it is an
    original node, a foundation, or a bottom corner of a supported cell; a cell is supported if both its top corners
    are held, or if it lies in a horizontal run of at most max_bridge cells whose outer top corners are held. Each cell
    records the cells it hangs from (self.deps), which build_cell builds first: a gallery cell built sideways before
    the storeys above it hung off its neighbour alone (physics.py: sag 200, later struts 240-319 long, refused)."""
    if not self.cfg.get("hanging"):
        return _filter_supported(self)
    held = {ij: None for ij, n in self.nodes.items() if n[2] in ("orig", "found")}
    sup = set(self.orig_cells)
    for i, j in sup:
        held.setdefault((i, j + 1), None)
        held.setdefault((i + 1, j + 1), None)
    via = {}

    def hold_bottom(c):
        held.setdefault((c[0], c[1] + 1), c)
        held.setdefault((c[0] + 1, c[1] + 1), c)

    max_bridge = self.cfg.get("max_bridge", 3)
    changed = True
    while changed:
        changed = False
        for c in sorted(self.cells - sup, key=lambda c: c[1]):
            i, j = c
            if (i, j) in held and (i + 1, j) in held:
                sup.add(c)
                via[c] = [(i, j), (i + 1, j)]
                hold_bottom(c)
                changed = True
        for c in sorted(self.cells - sup):
            i, j = c
            if (i, j) not in held or (i - 1, j) in self.cells - sup:
                continue
            run = [c]
            while len(run) <= max_bridge and (run[-1][0] + 1, j) in self.cells - sup:
                run.append((run[-1][0] + 1, j))
            for k in range(len(run)):
                if k < max_bridge and (run[k][0] + 1, j) in held:
                    ends = [(i, j), (run[k][0] + 1, j)]
                    for x in run[:k + 1]:
                        sup.add(x)
                        via[x] = ends
                        hold_bottom(x)
                    changed = True
                    break
    # each corner a cell hangs from is held by the shallowest supported cell above it (or the starting fort)
    depth, best = {}, {}
    for c in sorted(via, key=lambda c: c[1]):
        for n in via[c]:
            if n not in best:
                hs = [h for h in ((n[0] - 1, n[1] - 1), (n[0], n[1] - 1)) if h in depth]
                best[n] = None if held.get(n, 0) is None or not hs else min(hs, key=lambda h: depth[h])
        depth[c] = 1 + max([depth[best[n]] if best[n] else 0 for n in via[c]])
    self.deps = {c: {best[n] for n in via[c]} - {None} for c in via}
    self.depth = depth
    dropped = self.cells - sup
    if dropped:
        self.cells -= dropped
        self.problems.append("%d unsupported cells omitted: %s" % (len(dropped), sorted(dropped)))


for _v in STALACTITES_VARIANTS.values():
    _v["plan"] = _shielded(_v["plan"])


_ensure_node = gen_fort.Plan.ensure_node


def ensure_node_hanging(self, ij, via_material="bracing"):
    """ensure_node for a hanging fort (cfg "hanging"): a foundation on the underside is created only straight up from
    the node below it, which is built first (from its neighbours if need be). gen_fort's found_from_below falls back to
    a built neighbour beside the foundation; the first Stalactites-3 match (01.11.2026) refused that node, created along
    the rock from the starting fort's foundation (-3000, -1350) to (-3100, -1350), with CS_OBSTRUCTION, and the back
    block hanging on it never came (the AI stuck at plan action 12)."""
    n = self.nodes.get(ij)
    if not self.cfg.get("hanging") or n is None or n[2] != "found" or not (len(ij) == 2 and isinstance(ij[0], int)):
        return _ensure_node(self, ij, via_material)
    nid = self.node(ij)[0]
    if nid in self.built_nodes:
        return nid
    i, j = ij
    below = (i, j + 1)
    if below not in self.nodes or gen_fort.math.dist(self.nodes[below][1], self.nodes[ij][1]) > gen_fort.MAX_NEW_NODE:
        return None
    if self.ensure_node(below) is None:
        for k in (i - 1, i + 1):
            if (k, j + 1) in self.nodes:
                self.ensure_node((k, j + 1))
        if self.ensure_node(below) is None:
            return None
    src = self.nodes[below]
    p = self.nodes[ij][1]
    self.actions.append('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "%s" },'
                        % (src[0], self._fmt(src[1]), nid, self._fmt(p), via_material))
    self.built_nodes.add(nid)
    self.note_node(src[0], nid, "found")
    self.links[frozenset((src[0], nid))] = via_material
    return nid


_door_span = gen_fort.Plan.door_span


def door_span_hanging(self, y_top, y_floor, y_hi, y_lo):
    """door_span, the door reaching cfg door_sag higher (hanging forts): the front column hangs further from the rock
    than the cell behind it and sags more. In the second Stalactites-3 match (01.11.2026) the cannon (-2653, -357)
    behind its lane never fired: its shot hit the armour above its door, cut to the shot +- 22.5 (rules.py and
    physics.py see the unloaded plan)."""
    span = _door_span(self, y_top, y_floor, y_hi - self.cfg.get("door_sag", 0), y_lo)
    if span is None:
        return None
    # an armour piece left above or below the door shorter than 45 is squeezed under the game's 37.5 once the fort
    # sags (Stalactites-1's 20mm doors, 97.5 of 135: 35 and 34 long in physics.py, refused): the door takes it
    top, bot = span
    if 0 < top - y_top < 45:
        top = y_top
    if 0 < y_floor - bot < 45:
        bot = y_floor
    return None if (top, bot) == (y_top, y_floor) else (top, bot)


_generate = gen_fort.Plan.generate


def generate_hanging(self, variant):
    """generate, then for a hanging fort (cfg "hanging") clear_recent_blockers."""
    _generate(self, variant)
    if self.cfg.get("skeleton"):
        background_skeleton(self)
    if self.cfg.get("hanging"):
        keep_outer_doors(self)
        clear_recent_blockers(self)
    return self


def _seg_box(p, q, box):
    """True if the segment p-q passes through the inside of box (x0, x1, y0, y1)."""
    x0, x1, y0, y1 = box
    t0, t1 = 0.0, 1.0
    dx, dy = q[0] - p[0], q[1] - p[1]
    for pk, qk in ((-dx, p[0] - x0), (dx, x1 - p[0]), (-dy, p[1] - y0), (dy, y1 - p[1])):
        if pk == 0:
            if qk < 0:
                return False
            continue
        r = qk / pk
        if pk < 0:
            t0 = max(t0, r)
        else:
            t1 = min(t1, r)
        if t0 > t1:
            return False
    return t1 - t0 > 1e-6


def _device_boxes(d, cx, y0):
    """A device's box (centre x cx on a strut at height y0), and for a direct-fire weapon its line of fire: barrel
    height +- 15, 420 ahead (the line clear_recent_blockers keeps free)."""
    w, h = rules.SIZE.get(d, (40, 40))
    out = [(cx - w / 2, cx + w / 2, y0 - rules.BOX_TOP.get(d, h), y0)]
    if d in gen_fort.DIRECT_WEAPONS:
        yb = y0 - gen_fort.BARREL_H.get(d, 40)
        out.append((cx, cx + 420, yb - 15, yb + 15))
    return out


def background_skeleton(self):
    """cfg skeleton: every cell (two nearly vertical posts side by side between the same two floors) gets both
    diagonals as background bracing: a foreground diagonal becomes background bracing, the free one is added right
    after the cell's last strut. Background bracing cannot be shot, so a cut through every foreground strut of a storey
    leaves the fort below hanging on the diagonals (fourth Stalactites-3 match, 01.11.2026: the starting fort's bottom
    storey was cut and everything below fell; `gen_hang.py cut` checks it). Left out: diagonals through a device's
    box (rules.BOX_TOP / SIZE, also devices built later), a direct-fire weapon's line of fire (_device_boxes) or a cfg
    skeleton_keepout box, and longer than MAX_LINK."""
    import re
    acts = self.actions
    link_re = re.compile(r"OriginalNodeAId = (\d+),.*OriginalNodeBId = (\d+),")
    pos = dict(self.orig)
    made = {n: -1 for n in self.orig}            # node -> action creating it (-1: starting fort)
    links = {}                                    # pair -> (action index, material)
    boxes = [tuple(b) for b in self.cfg.get("skeleton_keepout", [])]
    for k, line in enumerate(acts):
        m = link_re.search(line)
        pts = [(float(x), float(y)) for x, y in re.findall(r"x = (-?[\d.]+), y = (-?[\d.]+)", line)]
        if "CREATE_DEVICE" in line and "LinkT" in line and len(pts) >= 2:
            d = re.search(r'DeviceSaveName = "(\w+)"', line).group(1)
            a, b = pts[:2]
            lt = float(re.search(r"LinkT = (-?[\d.]+)", line).group(1))
            cx, y0 = a[0] + lt * (b[0] - a[0]), a[1] + lt * (b[1] - a[1])
            boxes += _device_boxes(d, cx, y0)
            continue
        if not m or len(pts) < 2:
            continue
        a, b = int(m.group(1)), int(m.group(2))
        pos.setdefault(a, pts[0])
        if "CREATE_NODE" in line:
            pos[b] = pts[1]
            made.setdefault(b, k)
        else:
            pos.setdefault(b, pts[1])
        mat = re.search(r'MaterialSaveName = "(\w+)"', line).group(1)
        links[frozenset((a, b))] = (k, mat)
    # the starting fort's struts and devices (map .spr; nodes no plan names, id 90000+, cannot be used)
    import physics
    start = physics.load_startfort(self.cfg["spr_map"], None, self.orig)
    for a, b, mat, rest in (start.links.values() if start else ()):
        if a in self.orig and b in self.orig:
            links.setdefault(frozenset((a, b)), (-1, mat))
    for d, a, b, lt in (start.devices if start else ()):
        if a in start.pos and b in start.pos:
            pa, pb = start.pos[a], start.pos[b]
            cx, y0 = pa[0] + lt * (pb[0] - pa[0]), pa[1] + lt * (pb[1] - pa[1])
            boxes += _device_boxes(d, cx, y0)
    posts = []
    for pair, (k, mat) in links.items():
        a, b = tuple(pair)
        if a in pos and b in pos and abs(pos[a][0] - pos[b][0]) < 15 and abs(pos[a][1] - pos[b][1]) > 60:
            top, bot = (a, b) if pos[a][1] < pos[b][1] else (b, a)
            posts.append((top, bot, k))
    edits, added = {}, []
    for t1, b1, k1 in posts:
        for t2, b2, k2 in posts:
            x1, x2 = pos[t1][0], pos[t2][0]
            if not (x1 < x2 and abs(pos[t1][1] - pos[t2][1]) < 15 and abs(pos[b1][1] - pos[b2][1]) < 15):
                continue
            if any(x1 + 5 < pos[t][0] < x2 - 5 and abs(pos[t][1] - pos[t1][1]) < 15 and abs(pos[b][1] - pos[b1][1]) < 15
                   for t, b, _ in posts):
                continue                          # another post between: not one cell
            for p_, q_ in ((t1, b2), (t2, b1)):
                pair = frozenset((p_, q_))
                if any(_seg_box(pos[p_], pos[q_], bx) for bx in boxes):
                    continue
                if pair in links:
                    k, mat = links[pair]
                    if mat == "bracing" and k >= 0:
                        edits[k] = acts[k].replace('"bracing"', '"backbracing"')
                    continue
                if math.dist(pos[p_], pos[q_]) > gen_fort.MAX_LINK:
                    continue
                after = max(k1, k2, made.get(p_, -1), made.get(q_, -1))
                pa, pb = pos[p_], pos[q_]
                added.append((after, '{ Type = CREATE_LINK, OriginalNodeAId = %d, PosA = {x = %.2f, y = %.2f }, '
                              'OriginalNodeBId = %d, PosB = { x = %.2f, y = %.2f }, MaterialSaveName = "backbracing" },'
                              % (p_, pa[0], pa[1], q_, pb[0], pb[1])))
                links[pair] = (after, "backbracing")
    # skeleton_levels {y: n}: up to n background hangers across height y between any two nodes the plan can name (the
    # starting fort is a zigzag truss without posts: no cells), near-vertical first, spread over the width
    hangers = 0
    for y, want in sorted(self.cfg.get("skeleton_levels", {}).items()):
        have = [pair for pair, (k, mat) in links.items() if mat == "backbracing"
                and all(n in pos for n in pair) and (pos[min(pair)][1] - y) * (pos[max(pair)][1] - y) < 0]
        xs = [sum(pos[n][0] for n in pair) / 2 for pair in have]
        use = {}
        cands = []
        for a in pos:
            for b in pos:
                if not (pos[a][1] < y < pos[b][1]) or frozenset((a, b)) in links:
                    continue
                L = math.dist(pos[a], pos[b])
                if not (60 < L <= gen_fort.MAX_LINK) or abs(pos[a][0] - pos[b][0]) > 0.8 * (pos[b][1] - pos[a][1]):
                    continue
                if any(_seg_box(pos[a], pos[b], bx) for bx in boxes):
                    continue
                cands.append((abs(pos[a][0] - pos[b][0]) - (pos[b][1] - pos[a][1]) / 4, a, b))
        n = 0
        for _, a, b in sorted(cands):
            if n >= want:
                break
            xm = (pos[a][0] + pos[b][0]) / 2
            if any(abs(xm - x) < 45 for x in xs) or use.get(a, 0) >= 2 or use.get(b, 0) >= 2:
                continue
            after = max(made.get(a, -1), made.get(b, -1))
            pa, pb = pos[a], pos[b]
            added.append((after, '{ Type = CREATE_LINK, OriginalNodeAId = %d, PosA = {x = %.2f, y = %.2f }, '
                          'OriginalNodeBId = %d, PosB = { x = %.2f, y = %.2f }, MaterialSaveName = "backbracing" },'
                          % (a, pa[0], pa[1], b, pb[0], pb[1])))
            links[frozenset((a, b))] = (after, "backbracing")
            xs.append(xm)
            use[a] = use.get(a, 0) + 1
            use[b] = use.get(b, 0) + 1
            n += 1
            hangers += 1
    for k, line in edits.items():
        acts[k] = line
    # struts between starting-fort nodes come after the footing (the hub, node 10000): it stays the plan's first step
    hub = [k for k, line in enumerate(acts[:20]) if re.search(r"OriginalNode[AB]Id = 10000,", line)]
    floor = max(hub) if hub else -1
    added = [(max(after, floor), line) for after, line in added]
    for after, line in sorted(added, key=lambda x: -x[0]):
        acts.insert(after + 1, line)
    if edits or added:
        self.problems.append("skeleton: %d diagonals made background, %d background diagonals added"
                             % (len(edits), len(added)))


def keep_outer_doors(self):
    """The generator ties the outer door layers of weapons one above the other with armour (door_layers); with full
    doors in stacked rows (door_sag) the tie is the next row's outer door itself, and the CREATE_LINK swaps it to armour
    (Stalactites-1: the lower cannon's second door). A later armour copy of a door is dropped. Vertical armour in the
    outer door column (x -2318) in front of a lane cell becomes a door (the starting machine gun fires through it)."""
    import re
    acts = self.actions
    pair_re = re.compile(r"OriginalNodeAId = (\d+),.*OriginalNodeBId = (\d+),")
    doors, drop = set(), []
    for k, line in enumerate(acts):
        m = pair_re.search(line)
        if not m or not ("CREATE_LINK" in line or "CREATE_NODE" in line):
            continue
        pair = frozenset((int(m.group(1)), int(m.group(2))))
        if '"door"' in line:
            doors.add(pair)
        elif '"armour"' in line and "CREATE_LINK" in line and pair in doors:
            drop.append(k)
    lanes = [y for x, y in self.cfg.get("lane_cells", [])]
    for k, line in enumerate(acts):
        pts = [(float(x), float(y)) for x, y in re.findall(r"x = (-?[\d.]+), y = (-?[\d.]+)", line)]
        if '"armour"' in line and len(pts) >= 2 and all(abs(p[0] + 2318) < 3 for p in pts[:2])                 and any(abs(max(pts[0][1], pts[1][1]) - y) < 3 for y in lanes):
            acts[k] = line.replace('"armour"', '"door"')
    for k in reversed(drop):
        del acts[k]
    if drop:
        self.problems.append("%d armour copies of outer doors dropped" % len(drop))


def clear_recent_blockers(self):
    """Solid struts in a direct-fire weapon's line of fire that the plan builds shortly before the weapon (within
    SWAP_WINDOW actions) become background bracing (armour: a door). rules.py takes them as recessed by the game when
    the weapon is placed, but a strut still under construction is not recessed: in the first Stalactites-3 match
    (01.11.2026) the post x -2503 between each EMP rocket and its lane, built 3 actions before the rocket, stayed solid
    and neither rocket fired once in 9 minutes (42 smoke shells fired as their cover). Struts built after the weapon
    are never recessed and are cleared too (door_sag's full doors tie the outer door layers of stacked rows with
    armour, in front of a row whose layer is skipped)."""
    import re
    acts = self.actions
    pos = dict(self.orig)
    for line in acts:
        ids = [int(x) for x in re.findall(r"OriginalNode[AB]Id = (\d+)", line)]
        pts = [(float(x), float(y)) for x, y in re.findall(r"x = (-?[\d.]+), y = (-?[\d.]+)", line)]
        for i, q in zip(ids, pts):
            pos.setdefault(i, q)
    hit = set()
    for k, line in enumerate(acts):
        m = re.search(r'DeviceSaveName = "(\w+)"', line)
        if not (m and "CREATE_DEVICE" in line and m.group(1) in gen_fort.DIRECT_WEAPONS and "LinkT" in line):
            continue
        a, b = [(float(x), float(y)) for x, y in re.findall(r"x = (-?[\d.]+), y = (-?[\d.]+)", line)][:2]
        t_ = float(re.search(r"LinkT = (-?[\d.]+)", line).group(1))
        px, py = a[0] + t_ * (b[0] - a[0]), a[1] + t_ * (b[1] - a[1])
        for j in range(max(0, k - self.SWAP_WINDOW), len(acts)):
            sj = acts[j]
            if not ("CREATE_LINK" in sj or "CREATE_NODE" in sj) or not re.search(r'"(bracing|armour)"', sj):
                continue
            ids = [int(x) for x in re.findall(r"OriginalNode[AB]Id = (\d+)", sj)]
            if len(ids) != 2 or ids[0] not in pos or ids[1] not in pos:
                continue
            (x1, y1), (x2, y2) = pos[ids[0]], pos[ids[1]]
            bh = gen_fort.BARREL_H.get(m.group(1), 40)  # the weapon's barrel height above its strut (machine guns 40)
            for h in (bh - 10, bh, bh + 10):
                y = py - h
                if y1 != y2 and (y1 - y) * (y2 - y) <= 0:
                    x = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
                    if px < x < px + 420:
                        hit.add(j)
    for j in hit:
        acts[j] = acts[j].replace('"bracing"', '"backbracing"').replace('"armour"', '"door"')
    if hit:
        self.problems.append("%d struts built shortly before or after a weapon in its line of fire made background bracing"
                             % len(hit))


def register():
    """Adds the map and its variants to gen_fort (and so to physics.py, which reads gen_fort.MAPS), and the hanging
    support rule and foundation building to gen_fort.Plan (only maps with cfg "hanging" use them)."""
    gen_fort.MAPS["Stalactites"] = MAP
    gen_fort.STALACTITES_VARIANTS = STALACTITES_VARIANTS
    gen_fort.Plan.filter_supported = filter_supported_hanging
    gen_fort.Plan.ensure_node = ensure_node_hanging
    gen_fort.Plan.generate = generate_hanging
    gen_fort.Plan.door_span = door_span_hanging


CUT_YS = [-1275, -1150, -1047, -947, -830, -695, -560, -425, -290]   # mid-storey heights of the deep and shallow forts


def cut_test(paths, ys=CUT_YS):
    """A player cuts a hanging fort off the rock (fourth Stalactites-3 match, 01.11.2026: the starting fort's bottom
    storey -997..-897 failed from the front post to the back block in 1.6 s, everything below fell). For each height y:
    the plan is built (physics.py replay), every foreground strut crossing y is removed (background bracing cannot be
    shot), and the rest is settled. HOLDS: nothing detached and no strut breaks; else the devices that fall."""
    import physics
    from fortplan import parse_plan
    terrain = physics.load_terrain("Stalactites")
    falls = 0
    for path in paths:
        header, actions = parse_plan(path)
        fort = physics.load_startfort("Stalactites", terrain,
                                      {n: p for n, p in physics.node_positions(actions).items() if n < 10000})
        rp = physics.Replay(fort, terrain).run(actions)
        print(os.path.basename(path))
        for y in ys:
            f = rp.f.copy()
            cut = [k for k, (a, b, mat, rest) in f.links.items() if mat != "backbracing"
                   and (f.pos[a][1] - y) * (f.pos[b][1] - y) < 0]
            for k in cut:
                f.links.pop(k)
            r, broken = physics.settle(f, max_breaks=60)
            adj = {n: set() for n in f.pos}
            for a, b, _, _ in f.links.values():
                adj[a].add(b)
                adj[b].add(a)
            held, todo = set(f.fixed), list(f.fixed)
            while todo:
                for m in adj[todo.pop()]:
                    if m not in held:
                        held.add(m)
                        todo.append(m)
            fall = sorted(d[0] for d in f.devices if d[1] not in held or d[2] not in held)
            ok = not fall and not broken and r.converged
            falls += not ok
            print("  cut y %5d: %2d struts cut, %s%s" % (y, len(cut), "HOLDS" if ok else "FALLS",
                  "" if ok else " (%d broken, %d devices fall: %s)" % (len(broken), len(fall), ",".join(fall))))
    print("cut test: %d falls" % falls)


def main():
    register()
    here = os.path.dirname(os.path.abspath(__file__))
    data = os.path.normpath(os.path.join(here, "..", "..", "..", "..", ".."))
    if len(sys.argv) > 1 and sys.argv[1] == "physics":
        import physics
        sys.argv = [sys.argv[0], "check"] + sys.argv[2:]
        return physics.main()
    if len(sys.argv) > 1 and sys.argv[1] == "cut":
        return cut_test(sys.argv[2:])
    sys.argv = [sys.argv[0], "--maps", os.path.join(data, "maps"), "--map", "Stalactites", "--start-number", "1"] + sys.argv[1:]
    gen_fort.main()


if __name__ == "__main__":
    main()
