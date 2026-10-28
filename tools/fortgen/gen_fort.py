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
import copy
import math
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fwe import read_blocks            # noqa: E402
from terrain import Terrain              # noqa: E402
from fortplan import parse_plan, parse_lines, node_positions, format_modules, module_requires  # noqa: E402
import rules  # noqa: E402

MAX_LINK = 205          # struts between existing nodes (the game allows StandardMaxLinkLength = 218)
GAME_MAX_LINK = 218     # StandardMaxLinkLength: only for struts listed in long_struts
MAX_NEW_NODE = 150     # StandardMaxLength: a new node can be at most this far from the node it is built from
MIN_LINK = 45
MIN_STRUT = 37.5        # StandardMinLength: the shortest strut the game allows
DOOR_MIN = 49           # the shortest door (MinLength of door in building_materials.lua)
# direct-fire weapons whose door is cut to the shot (split_doors): barrel height above the strut (the RecessionBox
# offset of the weapon file) and barrel length
DOOR_WEAPONS = {"sniper", "sniper2", "cannon", "cannon20mm", "laser", "rocketemp", "rocket", "firebeam"}
# rockets: weapon_pack's rocket.lua / rocketemp.lua (RecessionBox Offset y -65, BarrelLength 60); firebeam:
# weapon_pack's firebeam.lua (Offset y -60, BarrelLength 58, like the laser)
BARREL_H = {"sniper": 50, "sniper2": 50, "cannon": 70, "cannon20mm": 60, "laser": 60, "rocketemp": 65, "rocket": 65,
            "firebeam": 60}
BARREL_LEN = {"sniper": 100, "sniper2": 100, "cannon": 100, "cannon20mm": 100, "laser": 58, "rocketemp": 60, "rocket": 60,
              "firebeam": 58}
DIRECT_WEAPONS = {"machinegun", "minigun", "sniper", "sniper2", "cannon", "cannon20mm", "laser",
                  "flak", "shotgun", "rocketemp", "rocket", "firebeam"}
# the smoke bomb launcher (dlc_smokebomb) stands on top like a mortar: the game's own plans (Mountain King 3v3)
# put it on the highest storey
LOBBED_WEAPONS = {"mortar", "mortar2", "smokebomb"}
LARGE = {"cannon", "cannon20mm", "laser"}
# weapon_pack: flak and EMP rockets need the armoury, shotgun (flak) and rocket (EMP rocket) are their upgrades;
# the smoke bomb follows the armoury in the game's own plans (Crevice-Howie: armoury is its only tech)
PREREQ = {"mortar": "workshop", "factory": "workshop", "cannon": "factory", "laser": "factory",
          "minigun": "upgrade", "sniper2": "upgrade", "mortar2": "upgrade", "mine2": "upgrade", "turbine2": "upgrade",
          "flak": "armoury", "rocketemp": "armoury", "smokebomb": "armoury", "shotgun": "upgrade", "rocket": "upgrade"}
UPGRADE_OF = {"minigun": "machinegun", "sniper2": "sniper", "mortar2": "mortar", "mine2": "mine", "turbine2": "turbine",
              "shotgun": "flak", "rocket": "rocketemp"}
# tall devices: their box reaches 112 (rockets) to 118 (flak, shotgun) above the strut (rules.BOX_TOP; the smoke
# bomb is assumed like a turbine, 127); on a floor they need a storey at least this high, like a turbine
TALL = {"rocketemp", "rocket", "flak", "shotgun", "smokebomb"}
TALL_MIN_H = 125

def _segment_hits_box(p, q, box):
    """True if the segment p-q passes through the box (x0, x1, y_top, y_bottom), sampled every ~2 units."""
    x0, x1, yt, yb = box
    n = max(2, int(math.dist(p, q) / 2))
    for k in range(n + 1):
        x, y = p[0] + (q[0] - p[0]) * k / n, p[1] + (q[1] - p[1]) * k / n
        if x0 < x < x1 and yt < y < yb:
            return True
    return False


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
        # cliff ledge at y=-750 left of the tower (test match 24.10.2026: the foundation (-2199,-746) built straight
        # down from the roof node above and the roof node (-2300,-846) built up from that foundation were refused
        # with CS_OBSTRUCTION, the AI stalled for 5 minutes; the AI places a node at its source's current position
        # plus the offset, so a source that sagged puts a foundation into the rock). Build like the game's Abyss-1:
        # foundations from the storey below, else diagonally from above, never straight down; nodes above the
        # ground not from foundations (roof nodes along the roof); other new nodes at least rock_clear from the rock
        "found_from_below": True,
        "no_build_from_found": True,
        "rock_clear": 30,
        # proven slots from the original plan: (node A, node B, LinkT); nodes given as positions
        "tech_slots": {
            "workshop": [((-2001, 305), (-1901, 309), 0.05)],
            "upgrade": [((-2097, 3), (-1997, 5), 0.94)],
            "factory": [((-2002, 405), (-1901, 405), 0.94)],
            # weapon_pack's ToGA1 armoury slot (shifted by -500; the munitions plant has the same size), moved
            # to 0.3: the workshop at 0.05 on the strut to the right reaches over the shared node
            "munitions": [((-2100, 300), (-2001, 305), 0.3)],
            # the same slot for the armoury (same size; no plan builds both)
            "armoury": [((-2100, 300), (-2001, 305), 0.3)],
        },
        # weapon_pack is always installed: cannons and 20mm cannons need the munitions plant
        "prereq": {"cannon": "munitions", "cannon20mm": "munitions", "munitions": "workshop"},
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
        # the tower stands on two foundations that move apart (the back block and the starting fort): built
        # column by column, its front part went up to the roof alone and the back part after it, and the seam
        # between them came last (test matches: the two parts leaned apart, the seam cells were squeezed).
        # Cells above base_y (the tower) are built storey by storey: none above the first `storeys` storeys
        # before those are complete over the whole width, and later none more than `storeys` storeys above
        # the highest complete one (connect_tower)
        "tower_connect": {"base_y": 205, "storeys": 2},
        # after the first mine, the inner metal layer in front of the reactor (diagonal (-2892,411)-(-2943,312)
        # and post (-2943,312)-(-2945,206); the outer armour shell at x -2845 stays) is rebuilt as wood bracing:
        # the refunded metal speeds up the start (starting-fort node ids of fort-t1f1-Template-1.lua)
        "rebrace_after_mine": [(50, 53), (53, 55)],
        "solid_minus1": True,          # blocks with id -1 are rock here
        # front column at -2945/-2845 = the prow of the starting fort (rock ends at x=-2900, nothing beyond -2845)
        # back columns -3600..-3400: room for turbines and eco behind the fort (the rock ends at -3600)
        # front column at -2945/-2845 = the prow of the starting fort (rock ends at x=-2900, nothing beyond -2845)
        "cols": [-3600, -3500, -3400, -3300, -3200, -3100, -3000, -2945, -2845],
        # from the starting fort's roof (y=205) upwards the columns follow its posts at -3093 and -2945, like
        # the game's own Template-1: the weapon column is one 155-wide cell, no node mid-span on the roof beam
        # (test matches: a wall at -3000 on that beam sagged, cannons failed with CS_UNSTABLE)
        "upper_y": 205,
        "cols_upper": [-3600, -3500, -3400, -3300, -3200, -3100, -2945, -2845, -2745],
        "rows": [-395, -295, -195, -95, 5, 105, 205, 308, 405, 503, 602, 700],
        "reactor": (-3040, 305),
        "keepout": [(-3140, -2900, 205, 405),    # reactor + frame: no cells
                    (-2945, -2745, 205, 310)],   # prow of the starting fort (the grid changes columns at y=205)
        # the rock ends at x=-2900: no cells hanging beyond the cliff without foundations
        "require_support": True,
        # rules from the guide "How to be a PRO at Vanilla Forts": crossbraced lower layers,
        # build from the bottom up, no heavy metal roof
        # every cell crossbraced (|X|): the weapon tower stands on solid storeys (test match: an open
        # turbine storey under the weapons was the breaking point, one hit dropped the whole upper block)
        "crossbrace_y": -1000,
        "crossbrace_late_y": 405,      # ... but above the lower layers only in a final pass (weapons first)
        "crossbrace_now_x": -3100,     # ... except the front weapon column and the prow
        "bottom_up": True,
        "light_roof": True,
        # after the first test match: the ground row of the back column is taken by the starting
        # store/battery (CS_OCCUPIED), turbines on the 55-wide cell block their neighbours and the laser
        "use_eco_slots": True,
        "eco_no_ground": True,
        "turbine_min_w": 90,
        # turbines stand on the tower roof (y=-295), nothing rests on them: the game tests the wind with rays
        # up to 600 to both sides (+-10 degrees), so any lower turbine has the solid tower in its wind on the
        # right (rules.wind_rays: 0% clear on the back block's roof at y=205); the turbine gallery / split
        # sandbag cell options (turbine_floor_y, split_cell) are not used here
        "turbine_roof_max_y": -295,
        # mortars take their top cells before the turbines take the roofs (both want the tower top)
        "reserve_mortar": True,
        # woodspam in front of the weapon column (door wall x=-2945), two layers 40 apart
        "woodspam": {"wall_x": -2945, "layers": [-2905, -2865], "rows": [-295, -195, -95],
                     "base": [(-2845, 5), (-2845, 5)]},
        "turbine_cheap_first": True,
        # lines of fire (rules.py): struts in front of weapons become background bracing in the plan,
        # mortars only where their arc is open (test matches: blocked cannon/snipers, mortar beside the tower)
        "clear_fire_lines": True,
        "mortar_open_arc": True,
        # one turbine per roof cell (test match: two side by side, 46-54 apart, failed with CS_OCCUPIED)
        "eco_orig": False,             # no battery/storage in cells of the starting fort
        # the starting fort's machine gun stands on the strut (-2996,504)-(-2895,505) of its lower front, beside the
        # workshop slot (test match 25.10.2026: the own devices listed by a failed sale, machinegun@64-65 at
        # 2949,503 for the mirrored team 2); not on the prow's roof strut, as assumed before
        "orig_devices": [((-2996.23, 503.57), (-2895.38, 505.41), "machinegun")],
        "weapon_min_w": 95,            # no weapons in narrow cells (<95 wide)
        "mortar_avoid_roof": True,
        "turbine_narrow_first": True,
        "tech_spill": True,
        # large weapons in the weapon column, in the two storeys below the top one: the floor of the top
        # storey rests on the weapon cell below, whose diagonals are background bracing (lines of fire),
        # and sagged 24-38 (test match: 20mm cannon there CS_UNSTABLE, the one a storey lower was placed)
        "aa_y": 250, "large_y": -195, "large_top_min": -195, "large_top_max": -95, "reserve_large": True, "crossbrace_large": True, "large_t": 0.2,
        # a heavy weapon's body sits 18 forward of its LinkT point (SelectionOffset, mirrored for team 1):
        # at 0.2 in the 155-wide cell and 0.32 in a 100-wide cell it stays inside its own cell, so the cell
        # behind it (marked "<weapon>+") keeps solid diagonals and a solid post (large_rear_solid)
        "large_t_narrow": (150, 0.32), "large_rear_solid": True,
        "snap": 45,
        "ground_snap": 25,
        # proven slots from Template-1/-2: (node A, node B, LinkT)
        "tech_slots": {
            "workshop": [((-3096, 503), (-2996, 504), 0.05), ((-3200, 503), (-3096, 503), 0.96),
                         ((-3300, 601), (-3199, 601), 0.99)],   # last one from weapon_pack's ToGWM2
            "upgrade": [((-3200, 600), (-3098, 602), 0.02)],
            "factory": [((-3200, 600), (-3098, 602), 0.04)],
            # from weapon_pack's own plan ToGWM2 (shifted into this frame by +3950/+3300)
            "munitions": [((-3400, 602), (-3299, 604), 0.49)],
        },
        # weapon_pack is always installed: cannons and 20mm cannons need the munitions plant
        "prereq": {"cannon": "munitions", "cannon20mm": "munitions", "munitions": "workshop"},
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
    # Abyss-2, mortar battery (rebuilt 27.10.2026; the old Abyss-2, mortars on the open roofs of a wide tower, lost all
    # three test matches). The game's own Abyss-1 puts its three mortars on a storey over the starting fort's front
    # roof (y 5..-95, x -2000..-1700); here that storey is a hidden nest like Vanilla-2's (background bracing: the
    # player cannot see in, the shells pass out), 130 high, two mortars on its floor (the starting fort's roof struts,
    # 95 apart) behind a split front cell with two stacked sandbags and two layers of solid woodspam (the mortars lob
    # over them). Everything else hangs on the cliff: a one-cell spine tower against the wall (x -2100..-2000, from
    # the starting fort's top node at -250 up to the ledge) carries the ledge roof with the three ledge mines under it
    # and the turbines on it (the rock blocks their wind from the left, as for the game's Abyss-1); the third mortar
    # on the tower's top roof (nothing above it). Every cell X-braced (a cell with a device has background diagonals,
    # as stiff as solid ones); the machine guns (anti-air, later miniguns) in the tower's front cells behind doors,
    # the starting fort's own machine gun upgraded too.
    # After test 1 (27.10.2026, lost at 8.8 min, docs/history/abyss-2.md): an early sniper in the tower's first cell,
    # sold by the AI once it finds nothing to hit (FortRetire); the upgrade centre's cell under the starting fort
    # enclosed and shielded (it hung on a bare strut, open to snipers); two layers of wood in front of the starting
    # fort's lower front face, the reactor's wall (the player's rockets broke it and the reactor fell); a turbine
    # after each ledge mine (energy fell to ~300 with the turbines after all three mines).
    # Late game (after test 2, 27.10.2026: won, but the plan was done at ~480 s and the AI then sat at its storage
    # caps, 900 metal / 7000 energy): the sniper upgraded to an AP sniper, then the munitions plant and one 20mm
    # cannon (direct fire the player's flak cannot stop; lighter and lower than a cannon). Every direct-fire weapon
    # behind a short door cut to its shot, built with its cell before the weapon (split_doors).
    # After test 3 (27.10.2026, lost at 14.6 min): the sniper (tower foot, short door braced through its spot) was
    # refused with CS_UNSTABLE, and the spine tower leaned 40-170 toward the abyss, so the munitions plant on the
    # ledge roof, a machine gun and a mortar were refused up there. Following the player's fort of that match: a
    # lower block under the starting fort along the wall (x -2100..-1700, y 405..730, anchored to the wall's
    # foundations) carries the sniper (top storey, firing through two lane cells), the munitions plant (wall column,
    # its box kept clear, clear_boxes) and the 20mm (bottom storey at the wall, three lane cells); the tower is tied to
    # the cliff at every storey (the player's anchor points on the rock).
    "artillerie": {
        "title": "Mortar battery: hidden mortar nest over the starting fort behind sandbags, spine tower on the cliff, miniguns",
        "shape": lambda x0, y0, x1, y1: (
            (y0 >= -125 and y1 <= 5 and x0 >= -2000 and x1 <= -1700) or       # mortar nest
            (y0 >= -846 and y1 <= -250 and x0 >= -2100 and x1 <= -2000) or     # spine tower on the cliff wall
            (y0 >= -846 and y1 <= -746 and x0 >= -2500 and x1 <= -2100) or     # ledge roof (mines, turbines)
            (y0 >= 305 and y1 <= 405 and x0 >= -2000 and x1 <= -1900) or       # upgrade centre's cell
            (y0 >= 405 and y1 <= 750 and x0 >= -2100 and x1 <= -1700)),        # lower block under the starting fort
        # the early sniper is sold after 90 s in which it declined to fire with energy to spare (ai.lua, RETIRE)
        "retire": {"sniper": 90, "sniper2": 90},
        # the upgrade centre on Abyss-1's factory slot (its own slot at y 5 is the nest floor, beside the first mortar)
        "tech_slots": {"upgrade": [((-2002, 405), (-1901, 405), 0.94)],
                       # the munitions plant (box 170 high) in the lower block's wall column, on the floor at y 600, as
                       # close to the wall as it fits; its box (x -2095..-2005, y 430..600) kept clear (clear_boxes).
                       # Its own slot at y 305 lies under the workshop's body; on the ledge roof (test 3) the leaning
                       # tower made it CS_UNSTABLE and it stood in the open
                       "munitions": [((-2100, 600), (-2000, 600), 0.5)]},
        "cfg": {
            # one more column, so the nest's front cell (x -1800..-1700) has a neighbour on the grid
            "cols": [-2500, -2400, -2300, -2200, -2100, -2000, -1900, -1800, -1700, -1600],
            # the nest 130 high (y 5..-125: two stacked sandbags need 2 x 51); its back post is the starting fort's
            # node at (-1997, -96), onto which the grid point (-2000, -125) snaps; the lower block: storeys 405..550
            # (the sniper's: with its strut higher its box would reach the upgrade centre's body above), 550..600 and
            # 600..750 (the 20mm's; 150 is the longest post a new node may be built along); row 600 is the bottom
            # mine's chain node
            "rows": [-846, -746, -628, -502, -392, -250, -125, 5, 106, 206, 305, 405, 550, 600, 750],
            # the grid point (-2100, 550) snaps onto the starting fort's wall node (-2100, 500), 50 above it (test 5:
            # built as its own node straight down from (-2100, 400), its strut ran through that node, CS_OBSTRUCTION,
            # and the AI stood there for over three minutes)
            "snap": 50,
            "weapon_pick_best": True,
            "bottom_up": True,
            "crossbrace_y": -1000,
            # weapons aiming upward right behind short doors on the upper side (test 4: the doors were cut for a level
            # shot from weapons 230-330 behind them; the targeting ray rose 4-7 degrees and hit the armour above the
            # door, the 20mm never fired). Like the player's 20mm (a strut rising 3.9 degrees, the weapon at its front
            # end) and shotgun: each weapon on its own strut rising 5 degrees from the post at x -1900 (45 above the
            # floor: at 37.5, the shortest strut, physics.py had the sagged piece refused) to the front post at x -1700,
            # where it ends at the bottom of the
            # door. The front post: door from the top down to that node, armour below; both ends of the weapon's
            # strut braced down-back below it (nothing through the weapon's box). The weapons at LinkT 0.425, their
            # muzzles ~15 behind the door (BARREL_LEN 100); the two cells (x -1900..-1700) are lanes
            "split_edges": [
                {"a": (-1900, 405), "b": (-1900, 550), "mid": (-1900, 505), "braces": [((-2000, 550), "bracing")]},
                {"a": (-1700, 405), "b": (-1700, 550), "mid": (-1700, 487.5), "materials": {"a": "door", "b": "armour"},
                 "braces": [((-1800, 550), "bracing")]},
                {"a": (-1900, 600), "b": (-1900, 750), "mid": (-1900, 705), "braces": [((-2000, 750), "bracing")]},
                {"a": (-1700, 600), "b": (-1700, 750), "mid": (-1700, 687.5), "materials": {"a": "door", "b": "armour"},
                 "braces": [((-1800, 750), "bracing")]}],
            # the two cannons on the cliff (the plan's cliff steps): each on its own strut falling 10 degrees (the
            # player's rockets there: 12-13) from a node off the rock, tied to two anchors on it, to a front node; the
            # cannon's body (half-width 95, 18 forward) ends 7 behind its door, LinkT = (strut length - 120) / length
            "weapon_struts": [((-1900, 505), (-1700, 487.5), 0.425, "sniper"),
                              ((-1900, 705), (-1700, 687.5), 0.425, "cannon20mm"),
                              ((-2140, -1040), (-1940, -1004.7), 0.41, "cannon"),
                              ((-2112, -1167), (-1917.4, -1132.72), 0.39, "cannon")],
            "lane_cells": [(-1900, 550), (-1800, 550), (-1900, 750), (-1800, 750)],
            # the boxes of the munitions plant and the weapons kept free of solid struts (devices stand in front of
            # background bracing): the posts at x -1800 they stand over, the storey tops their boxes reach into
            "clear_boxes": ["munitions", "sniper", "sniper2", "cannon20mm", "cannon"], "clear_boxes_tilted": True,
            "hidden_box": (-2000, -1700, -125, 5),
            # one device per strut: each mortar on its own roof strut of the starting fort, 95 apart (Abyss-1: 91-96)
            "mortar_slots": [((-2000, 5), (-1900, 5), 0.5), ((-1900, 5), (-1800, 5), 0.45)],
            "split_cell": [(-1800, -125)],
            "sandbag_slots": [(0, "floor", 0.5), (0, "mid", 0.5)],
            # machine guns in the tower's front cells, from the middle storey (their doors look out over the nest)
            "aa_y": -502,
            # the starting fort's machine gun (LinkT from the map's .spr), upgraded to a minigun like the planned ones
            "orig_devices": [((-1895, 110), (-1795, 114), "machinegun", 0.35)],
            # batteries and stores inside the starting fort (Abyss-1's slots), behind its armour; not the two slots at
            # y 500 (the munitions plant's box, the sniper's strut)
            "use_eco_slots": True,
            "eco_slots": [((-2100, 200), (-1998, 206), 0.51), ((-2100, 400), (-2002, 405), 0.46),
                          ((-1998, 206), (-1898, 210), 0.52)],
            "mortar_open_arc": True,
            "clear_fire_lines": True,
            # two solid layers in front of the nest's front post (x -1700): they shield the mortars and sandbags
            # from flat fire; the mortars lob over them
            # each layer braced down to the starting fort's front node (-1747, 110), like the nest's front node
            # (no woodspam in front of the upgrade centre's cell: the device is 180 wide on a 100-wide cell, its box
            # reaches 90 beyond the cell's front post, and a layer there would be built through it, rules.py warns)
            "woodspam": {"wall_x": -1700, "layers": [-1660, -1620], "rows": [-125, 5],
                         "base": [(-1747.27, 110.37), (-1747.27, 110.37)]},
            # nothing on the nest's roof: the grid would add a connecting cell there (x -2000..-1900, y -250..-125,
            # it touches the starting fort's node (-1997, -96)), in the first mortar's arc and resting on the
            # background bracing of the nest
            # ... and no connecting cell under the starting fort's lower front face (x -1800..-1700, y 305..405): its
            # floor would run from the starting fort's node (-1802, 318) through its node (-1751, 310)
            "keepout": [(-2000, -1900, -250, -125), (-1800, -1700, 305, 405)],
        },
        "plan": [
            # mortar rush: the workshop (on the starting fort, no structure, 60 s) sets the pace; meanwhile the bottom
            # mine (three struts), the nest with its sandbags (0 metal) and the sniper; the mortars as soon as the
            # workshop is finished, after their sandbags (placed first, Vanilla-2's mortars were destroyed 3-5 s later)
            ("tech", ["workshop"]),
            ("eco", ["mine"]),
            # the tower's first cell, its foot (-2000, -250) braced at once to the starting fort's nodes below it
            # (-2049, -197) and (-1997, -96); otherwise it hangs on the wall node (-2120, -250) alone
            ("build", [(-2100, -250)]),
            ("struts", [((-2000, -250), (-2049.41, -196.45), "bracing"), ((-2000, -250), (-1997.10, -95.84), "bracing")]),
            # the nest from the back to the front, then the front cell's floor node (beyond the starting fort's roof)
            # braced down to the starting fort's front node (-1747, 110), a triangle with the roof's front node
            # (-1797, 9), before its sandbags: built first, the front cell hung on that one roof node and swung down
            # (physics.py, sag ~320)
            ("build", [(-2000, 5), (-1900, 5), (-1800, 5)]),
            ("struts", [((-1700, 5), (-1747.27, 110.37), "bracing")]),
            ("defence", ["sandbags", "sandbags"]),
            ("weapons", ["mortar", "mortar"]),
            # the tower tied to the cliff storey by storey (the player's anchor points of test 3, on the rock): each
            # back node to a foundation on the wall, and each foundation to the node of the next storey (triangles);
            # alone, the one-cell tower leaned 40-170 toward the abyss in test 3. With the tower, before its mines: built
            # after the tower stood, the anchors took its sag as their rest length and physics.py put the starting
            # fort's back diagonal 307-311 at 0.82 instead of 0.76; they cost ~7 actions (test 6's late ledge mines
            # came from the sniper's storey, now after them)
            ("struts", [((-2100, -392), (-2162.70, -386.08), "bracing"), ((-2120.45, -250), (-2162.70, -386.08), "bracing")]),
            ("build", [(-2100, -392)]),
            ("struts", [((-2100, -502), (-2178.13, -527.18), "bracing"), ((-2162.70, -386.08), (-2100, -502), "bracing")]),
            ("build", [(-2100, -502)]),
            ("struts", [((-2100, -628), (-2180.78, -672.55), "bracing"), ((-2178.13, -527.18), (-2100, -628), "bracing")]),
            ("build", [(-2100, -628)]),
            ("struts", [((-2180.78, -672.55), (-2100, -746), "bracing")]),
            # then metal (the AI averaged 100-260 metal on Abyss against the player's ~510) and energy (a mortar shot
            # costs 200): the tower up to the ledge, a turbine on the ledge roof after each of its mines
            ("eco", ["mine"]),
            ("eco", ["turbine"]),
            ("eco", ["mine"]),
            ("eco", ["turbine"]),
            ("eco", ["mine"]),
            # the lower block's top storey with the sniper's cell and its two lanes (short door at x -1700), then the
            # sniper (no tech), after the economy (test 6)
            ("build", [(-2100, 550), (-2000, 550), (-1900, 550), (-1800, 550)]),
            ("struts", [((-1900, 505), (-1700, 487.5), "bracing")]),
            ("weapons", ["sniper"]),
            # the corner under the starting fort's lower front face closed (test 6: the player's rockets broke in there,
            # under the reactor; the grid's cell there would have run through the starting fort's node (-1751, 310)):
            # from that node up to the lower block's top front nodes, and the starting fort's front node (-1695, 223)
            # down to (-1700, 405) as the front post (armour, it runs 54 clear of that node)
            ("struts", [((-1751.69, 314.55), (-1700, 405), "bracing"), ((-1751.69, 314.55), (-1800, 405), "bracing"),
                        ((-1694.52, 223.44), (-1700, 405), "armour")]),
            ("defence", ["woodspam"]),
            # two layers of wood in front of the starting fort's lower front face (nodes (-1746, 112), (-1695, 223),
            # (-1752, 315)), the reactor's wall: layer A at x ~-1655, layer B 40 further out, X-braced, hung from the
            # nest's woodspam above (those two posts background bracing: the starting fort's machine gun fires flat
            # through that band)
            ("struts", [((-1746.18, 112.27), (-1655, 112), "bracing"), ((-1694.52, 223.44), (-1650, 223), "bracing"),
                        ((-1751.69, 314.55), (-1655, 315), "bracing"),
                        ((-1655, 112), (-1650, 223), "bracing"), ((-1650, 223), (-1655, 315), "bracing"),
                        ((-1746.18, 112.27), (-1650, 223), "bracing"), ((-1694.52, 223.44), (-1655, 112), "bracing"),
                        ((-1694.52, 223.44), (-1655, 315), "bracing"), ((-1751.69, 314.55), (-1650, 223), "bracing"),
                        ((-1660, 5), (-1655, 112), "backbracing"),
                        ((-1655, 112), (-1615, 112), "bracing"), ((-1650, 223), (-1610, 223), "bracing"),
                        ((-1655, 315), (-1615, 315), "bracing"),
                        ((-1615, 112), (-1610, 223), "bracing"), ((-1610, 223), (-1615, 315), "bracing"),
                        ((-1655, 112), (-1610, 223), "bracing"), ((-1650, 223), (-1615, 112), "bracing"),
                        ((-1650, 223), (-1615, 315), "bracing"), ((-1610, 223), (-1655, 315), "bracing"),
                        ((-1620, 5), (-1615, 112), "backbracing")]),
            # ... and on down in front of the closed corner (y 315..405), to the lower block's top front node. Not further: in
            # front of the sniper's door it would have to be background bracing, which stops no shots (physics.py: the
            # extra weight at the front raised the starting fort's back diagonal 307-311 to 0.86)
            ("struts", [((-1655, 315), (-1655, 405), "bracing"), ((-1615, 315), (-1615, 405), "bracing"),
                        ((-1700, 405), (-1655, 405), "bracing"), ((-1655, 405), (-1615, 405), "bracing"),
                        ((-1700, 405), (-1655, 315), "bracing"), ((-1655, 315), (-1615, 405), "bracing"),
                        ((-1615, 315), (-1655, 405), "bracing")]),
            ("aa", ["machinegun"]),
            # the upgrade centre, then what needs no tech while it builds (60 s)
            # the upgrade centre on Abyss-1's factory slot, enclosed under the starting fort: its cell and the cell in
            # front of it (x -1900..-1800, where its 180-wide body reaches), with the armour front post at x -1800,
            # built right after it (background diagonals behind the device; in test 1 it hung on a bare strut, open
            # to snipers)
            ("tech", ["upgrade"]),
            ("build", [(-1900, 405)]),
            ("eco", ["battery", "store"]),
            ("aa", ["machinegun"]),
            ("upgrades", ["mortar2", "mortar2"]),
            ("upgrades", ["minigun", "minigun", "minigun"]),
            ("eco", ["turbine", "turbine"]),
            ("upgrades", ["turbine2", "turbine2", "turbine2", "turbine2"]),
            ("eco", ["battery"]),
            ("upgrades", ["mine2", "mine2"]),
            # late game: the AP sniper, the lower block's lower storeys (the munitions plant's floor at y 600), the
            # munitions plant (800 m / 5000 e, 90 s), a store while it builds, the 20mm with its lanes
            ("upgrades", ["sniper2"]),
            ("build", [(-2100, 600), (-2000, 600), (-1900, 600), (-1800, 600)]),
            # the bottom storey (the wall cell last: its foundation (-2104, 750) is 150.4 below the node above it, so it
            # is built sideways from the cell beside it), the 20mm's strut
            ("build", [(-1800, 750), (-1900, 750), (-2000, 750), (-2100, 750)]),
            ("struts", [((-1900, 705), (-1700, 687.5), "bracing")]),
            ("tech", ["munitions"]),
            ("eco", ["store"]),
            ("weapons", ["cannon20mm"]),
            # two cannons on the cliff above the ledge mines, like the player's three rockets there (test 5): no
            # storeys, only what holds them. From the tower's top one cell of background bracing (y -846..-950: the
            # turbines' only wind passes there), then per cannon a strut falling 10 degrees from a node off the rock
            # (each tied to two anchors on the upper cliff face, x ~-2146..-2183) to a front node; the door in front of
            # each cannon square to its strut (130 long, like the player's slanted doors: an upright post crossed the
            # front top corner of the tilted box), the next cannon's strut on top of it (the box is 121 high). The
            # third mortar on the tower's top went: these struts stood in its arc
            ("struts", [((-2100, -846), (-2100, -950), "backbracing"), ((-2000, -846), (-2000, -950), "backbracing"),
                        ((-2100, -950), (-2000, -950), "backbracing"), ((-2100, -846), (-2000, -950), "backbracing"),
                        ((-2000, -846), (-2100, -950), "backbracing"),
                        ((-2100, -950), (-2182.73, -1050.25), "backbracing"), ((-2100, -950), (-2140, -1040), "bracing"),
                        ((-2182.73, -1050.25), (-2140, -1040), "bracing"), ((-2140, -1040), (-2162.18, -1110.06), "bracing"),
                        ((-2000, -950), (-1940, -1004.7), "backbracing"), ((-2100, -950), (-1940, -1004.7), "backbracing"),
                        ((-2140, -1040), (-1940, -1004.7), "bracing")]),
            ("struts", [((-1940, -1004.7), (-1917.4, -1132.72), "door"), ((-2140, -1040), (-2112, -1167), "bracing"),
                        ((-2162.18, -1110.06), (-2112, -1167), "bracing"), ((-2112, -1167), (-2148.94, -1210.1), "bracing"),
                        ((-2112, -1167), (-1917.4, -1132.72), "bracing")]),
            ("struts", [((-1917.4, -1132.72), (-1894.81, -1260.74), "door"), ((-2112, -1167), (-2095, -1297), "bracing"),
                        ((-2095, -1297), (-2146.48, -1249.93), "bracing"), ((-2095, -1297), (-2158.66, -1329.9), "bracing"),
                        ((-2095, -1297), (-1894.81, -1260.74), "bracing")]),
            ("weapons", ["cannon", "cannon"]),
        ],
    },
    # Abyss-3, firebeam rush (27.10.2026; replaces the sniper fortress, won 1/1 against a player who barely fired).
    # The factory line instead of Abyss-2's mortars: two firebeams as soon as the factory is finished, fired together at
    # one spot (ai.lua, Fire.Volley: two beams cut what one only burns), the laser late as the end game. Built on
    # Abyss-2 as it stands after its seventh test (docs/maps/abyss.md, docs/history/abyss-2.md):
    # - economy first (test 6: the sniper's storey before the ledge mines made them late): the workshop, the tower with
    #   its cliff anchors storey by storey (alone it leaned 40-170 in test 3), the three ledge mines with a turbine
    #   after each, then the factory and, while it builds, the sniper's storey and the sniper;
    # - the corner under the reactor's face closed (test 6: the player's rockets broke in there), the wood curtain in
    #   front of the face down to y 405;
    # - weapons on their own struts sloping toward the enemy right behind a door on their upper side (test 4: doors cut
    #   for a level shot left the targeting ray on the armour above them): below the reactor the sniper and firebeam 1
    #   in the lower block under the starting fort (Abyss-2's sniper and 20mm, which fired 54 times in test 7); above
    #   the reactor firebeam 2 and the laser on Abyss-2's two cliff perches over the ledge mines (struts falling 10
    #   degrees behind slanted doors; Abyss-2's cannons were placed there in test 7; the tower-top column went);
    # - snap 50 and no cell under the starting fort's lower front face (test 5: a strut through the wall node
    #   (-2100, 500) stalled the AI for three minutes).
    # No mortar nest. Factory on Abyss-1's slot (y 405, enclosed, like Abyss-2's upgrade centre); the upgrade centre on
    # its own slot inside the starting fort's top storey. Energy is what a beam costs (firebeam 1500, laser 5000; the
    # factory 5000, the laser 6000 to place): a battery before the factory, three before the laser.
    "firebeam": {
        "title": "Firebeam rush: two firebeams firing together below and above the reactor, early sniper, laser as the end game",
        "shape": lambda x0, y0, x1, y1: (
            (y0 >= -846 and y1 <= -250 and x0 >= -2100 and x1 <= -2000) or     # spine tower on the cliff wall
            (y0 >= -846 and y1 <= -746 and x0 >= -2500 and x1 <= -2100) or     # ledge roof (mines, turbines)
            (y0 >= 305 and y1 <= 405 and x0 >= -2000 and x1 <= -1900) or       # factory's cell
            (y0 >= 405 and y1 <= 750 and x0 >= -2100 and x1 <= -1700)),        # lower block under the starting fort
        # the early sniper is sold after 90 s in which it declined to fire with energy to spare (ai.lua, RETIRE)
        "retire": {"sniper": 90},
        "cfg": {
            "cols": [-2500, -2400, -2300, -2200, -2100, -2000, -1900, -1800, -1700, -1600],
            # Abyss-2's rows: the lower block's storeys 405..550 (the sniper's), 550..600 and 600..750 (firebeam 1's)
            "rows": [-846, -746, -628, -502, -392, -250, -125, 5, 106, 206, 305, 405, 550, 600, 750],
            # the grid point (-2100, 550) snaps onto the starting fort's wall node (-2100, 500) (Abyss-2, test 5)
            "snap": 50,
            "weapon_pick_best": True,
            "bottom_up": True,
            "crossbrace_y": -1000,
            # the lower weapons' doors as on Abyss-2: each front post split where the weapon's strut ends, door above
            # (from the storey top down to that node), armour below; both ends of the strut braced down-back below it
            "split_edges": [
                {"a": (-1900, 405), "b": (-1900, 550), "mid": (-1900, 505), "braces": [((-2000, 550), "bracing")]},
                {"a": (-1700, 405), "b": (-1700, 550), "mid": (-1700, 487.5), "materials": {"a": "door", "b": "armour"},
                 "braces": [((-1800, 550), "bracing")]},
                {"a": (-1900, 600), "b": (-1900, 750), "mid": (-1900, 705), "braces": [((-2000, 750), "bracing")]},
                {"a": (-1700, 600), "b": (-1700, 750), "mid": (-1700, 687.5), "materials": {"a": "door", "b": "armour"},
                 "braces": [((-1800, 750), "bracing")]}],
            # the sniper at Abyss-2's LinkT (0.425, muzzle ~16 behind its door). Firebeam and laser have a 58-long barrel
            # (the 20mm's and the sniper's 100) and a centred body (half-width 50): the muzzle ~16 behind the door at
            # LinkT = (strut length - 74) / length, 0.63 on the lower block's strut and the upper perch, 0.64 on the lower
            # perch; their bodies end 24 behind the door (Abyss-2's cannons there: 7)
            "weapon_struts": [((-1900, 505), (-1700, 487.5), 0.425, "sniper"),
                              ((-1900, 705), (-1700, 687.5), 0.63, "firebeam"),
                              ((-2140, -1040), (-1940, -1004.7), 0.64, "firebeam"),
                              ((-2112, -1167), (-1917.4, -1132.72), 0.63, "laser")],
            "lane_cells": [(-1900, 550), (-1800, 550), (-1900, 750), (-1800, 750)],
            # the weapons' boxes kept free of solid struts (the posts at x -1800 they stand over, the storey tops),
            # on the perches tilted with their struts
            "clear_boxes": ["sniper", "firebeam", "laser"], "clear_boxes_tilted": True,
            # machine guns (anti-air, later miniguns) in the tower's front cells; the starting fort's machine gun is
            # upgraded too
            "aa_y": -502,
            "orig_devices": [((-1895, 110), (-1795, 114), "machinegun", 0.35)],
            # batteries and stores inside the starting fort (Abyss-2's slots: not the two at y 500, the sniper's strut),
            # then the lower block's bottom wall cell and the ledge cell beside the tower's top (behind the tower). Chosen
            # freely, a battery stood beside firebeam 1 with the brace under its strut through its box; the wall cell
            # of the sniper's storey has a sloping floor (the grid point (-2100, 550) snaps onto (-2100, 500))
            "use_eco_slots": True,
            "eco_slots": [((-2100, 200), (-1998, 206), 0.51), ((-2100, 400), (-2002, 405), 0.46),
                          ((-1998, 206), (-1898, 210), 0.52),
                          ((-2104.43, 750.32), (-2000, 750), 0.5), ((-2200, -746), (-2100, -746), 0.5)],
            "clear_fire_lines": True,
            # no connecting cell under the starting fort's lower front face (its floor would run through the starting
            # fort's node (-1751, 310)); the corner is closed by explicit struts instead
            "keepout": [(-1800, -1700, 305, 405)],
        },
        "plan": [
            # the workshop (on the starting fort, no structure, 60 s) opens the factory; meanwhile the bottom mine, then
            # the lower block's top storey and the early sniper (no tech) before the tower, as Abyss-2 puts its mortars
            # first (test 1, 27.10.2026: the sniper after the factory, the AI's first shot came at ~300 s)
            ("tech", ["workshop"]),
            ("eco", ["mine"]),
            ("build", [(-2100, 550), (-2000, 550), (-1900, 550), (-1800, 550)]),
            ("struts", [((-1900, 505), (-1700, 487.5), "bracing")]),
            ("weapons", ["sniper"]),
            # the tower's first cell, its foot braced to the starting fort, then the tower tied to the cliff storey by
            # storey with its growth (Abyss-2's anchors; built after the tower stood, they took its sag as rest length)
            ("build", [(-2100, -250)]),
            ("struts", [((-2000, -250), (-2049.41, -196.45), "bracing"), ((-2000, -250), (-1997.10, -95.84), "bracing")]),
            ("struts", [((-2100, -392), (-2162.70, -386.08), "bracing"), ((-2120.45, -250), (-2162.70, -386.08), "bracing")]),
            ("build", [(-2100, -392)]),
            ("struts", [((-2100, -502), (-2178.13, -527.18), "bracing"), ((-2162.70, -386.08), (-2100, -502), "bracing")]),
            ("build", [(-2100, -502)]),
            ("struts", [((-2100, -628), (-2180.78, -672.55), "bracing"), ((-2178.13, -527.18), (-2100, -628), "bracing")]),
            ("build", [(-2100, -628)]),
            ("struts", [((-2180.78, -672.55), (-2100, -746), "bracing")]),
            # metal and energy first (test 6): the three ledge mines, a turbine after each
            ("eco", ["mine"]),
            ("eco", ["turbine"]),
            ("eco", ["mine"]),
            ("eco", ["turbine"]),
            ("eco", ["mine"]),
            ("eco", ["turbine"]),
            # the factory costs 800 metal and 5000 energy: a store (900 metal) and a battery (5000 energy) first
            ("eco", ["battery", "store"]),
            ("tech", ["factory"]),
            # the factory enclosed under the starting fort (its cell and the cell in front, where its 180-wide body
            # reaches; Abyss-2's upgrade centre on this slot hung on a bare strut and was sniped)
            ("build", [(-1900, 405)]),
            # while the factory builds (90 s): the corner under the starting fort's lower front face closed (Abyss-2's
            # struts: from its node (-1751, 315) up to the lower block's top front nodes, the armour front post from its
            # node (-1695, 223) down to (-1700, 405))
            ("struts", [((-1751.69, 314.55), (-1700, 405), "bracing"), ((-1751.69, 314.55), (-1800, 405), "bracing"),
                        ((-1694.52, 223.44), (-1700, 405), "armour")]),
            # firebeam 1's storeys at the bottom of the lower block (the wall cell last: its foundation (-2104, 750) is
            # 150.4 below the node above it, so it is built sideways), its strut
            ("build", [(-2100, 600), (-2000, 600), (-1900, 600), (-1800, 600)]),
            ("build", [(-1800, 750), (-1900, 750), (-2000, 750), (-2100, 750)]),
            ("struts", [((-1900, 705), (-1700, 687.5), "bracing")]),
            # firebeam 2's perch on the cliff above the ledge mines (Abyss-2's lower cannon perch): from the tower's top
            # one cell of background bracing (y -846..-950, the turbines' only wind passes there), the strut falling 10
            # degrees from a node off the rock, tied to two anchors on the upper cliff face, to a front node; its door
            # square to the strut, the laser's perch strut on top of it
            ("struts", [((-2100, -846), (-2100, -950), "backbracing"), ((-2000, -846), (-2000, -950), "backbracing"),
                        ((-2100, -950), (-2000, -950), "backbracing"), ((-2100, -846), (-2000, -950), "backbracing"),
                        ((-2000, -846), (-2100, -950), "backbracing"),
                        ((-2100, -950), (-2182.73, -1050.25), "backbracing"), ((-2100, -950), (-2140, -1040), "bracing"),
                        ((-2182.73, -1050.25), (-2140, -1040), "bracing"), ((-2140, -1040), (-2162.18, -1110.06), "bracing"),
                        ((-2000, -950), (-1940, -1004.7), "backbracing"), ((-2100, -950), (-1940, -1004.7), "backbracing"),
                        ((-2140, -1040), (-1940, -1004.7), "bracing")]),
            ("struts", [((-1940, -1004.7), (-1917.4, -1132.72), "door"), ((-2140, -1040), (-2112, -1167), "bracing"),
                        ((-2162.18, -1110.06), (-2112, -1167), "bracing"), ((-2112, -1167), (-2148.94, -1210.1), "bracing"),
                        ((-2112, -1167), (-1917.4, -1132.72), "bracing")]),
            # the perch hidden (test 1: the player saw both cliff weapons placed): its quadrilateral (weapon strut, door,
            # the strut above, the back edge) closed into four triangles of background bracing around a node in its back
            # part, clear of the firebeam's box (a diagonal across it would be 236-241 long, the game allows 218)
            ("struts", [((-2140, -1040), (-2090, -1100), "backbracing"), ((-2090, -1100), (-2112, -1167), "backbracing"),
                        ((-2090, -1100), (-1940, -1004.7), "backbracing"), ((-2090, -1100), (-1917.4, -1132.72), "backbracing")]),
            ("weapons", ["firebeam", "firebeam"]),
            # two layers of wood in front of the starting fort's lower front face (Abyss-2's reactor wall), braced to its
            # nodes (-1746, 112), (-1695, 223), (-1752, 315), and on down in front of the closed corner to y 405 (not
            # further: in front of the sniper's door it would have to be background bracing)
            ("struts", [((-1746.18, 112.27), (-1655, 112), "bracing"), ((-1694.52, 223.44), (-1650, 223), "bracing"),
                        ((-1751.69, 314.55), (-1655, 315), "bracing"),
                        ((-1655, 112), (-1650, 223), "bracing"), ((-1650, 223), (-1655, 315), "bracing"),
                        ((-1746.18, 112.27), (-1650, 223), "bracing"), ((-1694.52, 223.44), (-1655, 112), "bracing"),
                        ((-1694.52, 223.44), (-1655, 315), "bracing"), ((-1751.69, 314.55), (-1650, 223), "bracing"),
                        ((-1655, 112), (-1615, 112), "bracing"), ((-1650, 223), (-1610, 223), "bracing"),
                        ((-1655, 315), (-1615, 315), "bracing"),
                        ((-1615, 112), (-1610, 223), "bracing"), ((-1610, 223), (-1615, 315), "bracing"),
                        ((-1655, 112), (-1610, 223), "bracing"), ((-1650, 223), (-1615, 112), "bracing"),
                        ((-1650, 223), (-1615, 315), "bracing"), ((-1610, 223), (-1655, 315), "bracing")]),
            ("struts", [((-1655, 315), (-1655, 405), "bracing"), ((-1615, 315), (-1615, 405), "bracing"),
                        ((-1700, 405), (-1655, 405), "bracing"), ((-1655, 405), (-1615, 405), "bracing"),
                        ((-1700, 405), (-1655, 315), "bracing"), ((-1655, 315), (-1615, 405), "bracing"),
                        ((-1615, 315), (-1655, 405), "bracing")]),
            ("aa", ["machinegun"]),
            # the upgrade centre, then what needs no tech while it builds (60 s)
            ("tech", ["upgrade"]),
            ("eco", ["battery"]),
            ("aa", ["machinegun"]),
            ("eco", ["turbine"]),
            ("upgrades", ["turbine2", "turbine2", "turbine2", "turbine2"]),
            ("upgrades", ["minigun", "minigun", "minigun"]),
            # end game: the laser (1000 metal, 6000 energy to place: a third battery) on Abyss-2's upper cannon perch,
            # its door square to the strut and the roof strut over it
            ("eco", ["battery"]),
            ("struts", [((-1917.4, -1132.72), (-1894.81, -1260.74), "door"), ((-2112, -1167), (-2095, -1297), "bracing"),
                        ((-2095, -1297), (-2146.48, -1249.93), "bracing"), ((-2095, -1297), (-2158.66, -1329.9), "bracing"),
                        ((-2095, -1297), (-1894.81, -1260.74), "bracing")]),
            # hidden like the firebeam's perch: four triangles of background bracing around a node in the back part
            ("struts", [((-2112, -1167), (-2070, -1225), "backbracing"), ((-2070, -1225), (-2095, -1297), "backbracing"),
                        ((-2070, -1225), (-1917.4, -1132.72), "backbracing"), ((-2070, -1225), (-1894.81, -1260.74), "backbracing")]),
            ("weapons", ["laser"]),
            ("upgrades", ["mine2", "mine2"]),
        ],
    },
    "schwer": {
        "title": "Heavy front: wide, heavily armoured block, munitions plant early, two cannons",
        "shape": lambda x0, y0, x1, y1: (
            (y0 >= -502 and y1 <= -250 and x0 >= -2100 and x1 <= -1700) or
            (y0 >= -846 and y1 <= -502 and x0 >= -2400 and x1 <= -1900) or
            (y0 >= 405 and y1 <= 600 and x0 >= -2100 and x1 <= -1900)),
        "plan": [
            ("aa", ["machinegun", "machinegun"]),
            ("eco", ["mine", "mine", "turbine", "battery", "turbine"]),
            ("tech", ["workshop"]),
            ("eco", ["mine", "store", "battery", "mine"]),
            # the munitions plant costs 800 metal and 5000 energy: all turbines first; no laser (only three
            # turbine slots, and their wind is blocked on the cliff side: a laser plan with 2-3 turbines never fired)
            ("eco", ["turbine", "battery"]),
            ("tech", ["munitions"]),
            ("weapons", ["cannon", "machinegun"]),
            ("weapons", ["sniper", "cannon"]),
            ("tech", ["upgrade"]),
            ("upgrades", ["minigun"]),
            ("weapons", ["sniper"]),
        ],
        "armour_roof": True,
    },
    # Abyss-5, rocket rush with smoke (rebuilt 28.10.2026; the old Abyss-5 on Abyss-4's shape, rockets in the two tall
    # front storeys and smoke launchers on open roofs in front of the shotguns, lost its only match 0/1: it stalled on the
    # ledge foundations before the armoury). Built on Abyss-2/-3 as they stand (docs/maps/abyss.md) and on Vanilla-5's
    # rocket tests (docs/maps/vanilla.md):
    # - one early weapon, then the economy (Abyss-2 test 6, Abyss-3 test 1): the armoury (400 m / 2000 e, 60 s, opens EMP
    #   rockets, smoke and flak; no workshop), the bottom mine, EMP rocket 1 at once, then the tower with its cliff
    #   anchors storey by storey and the three ledge mines with a turbine after each;
    # - the rockets on Abyss-2's sloping struts below the reactor (rising 5 degrees to the bottom of a door on their
    #   upper side; test 4: doors cut for a level shot left the ray on the armour above them): EMP rocket 1 in the lower
    #   block's top storey (Abyss-2's sniper spot), EMP rocket 2 in its bottom storey (Abyss-2's 20mm, 54 shots in test
    #   7); each in its own row with its lanes (a weapon blocks every weapon behind it in its row);
    # - the smoke launcher in a closed cell over the starting fort's front roof (the front cell of Abyss-2's nest) with a
    #   door roof and a door in front (Vanilla-5: on an open roof it was destroyed five times); no sandbags or woodspam in
    #   its row ahead of it: they block the line of fire (the player, 28.10.2026);
    # - the flak in the tower's lowest front cell (142 high, the flak's box is 118) behind a full door it opens (Vanilla-5:
    #   above a low shield it was sniped), out of every other weapon's row; one machine gun above it;
    # - the corner under the reactor closed and the wood curtain in front of the reactor's face (Abyss-2 test 6), snap
    #   50 and no cell under the starting fort's lower front face (test 5's stall);
    # - late game (Abyss-2 test 2: done at ~480 s, then idle at the caps): EMP rocket 3 on Abyss-2's lower cliff perch,
    #   hidden like Abyss-3's perches, upgraded to a rocket.
    "raketen": {
        "title": "Rocket rush: armoury, EMP rockets below the reactor on sloping struts behind short doors, smoke in the hidden nest, flak in the tower, a third rocket on the cliff",
        "shape": lambda x0, y0, x1, y1: (
            (y0 >= -125 and y1 <= 5 and x0 >= -1800 and x1 <= -1700) or       # smoke cell (front of Abyss-2's nest)
            (y0 >= -846 and y1 <= -250 and x0 >= -2100 and x1 <= -2000) or     # spine tower on the cliff wall
            (y0 >= -846 and y1 <= -746 and x0 >= -2500 and x1 <= -2100) or     # ledge roof (mines, turbines)
            (y0 >= 405 and y1 <= 750 and x0 >= -2100 and x1 <= -1700)),        # lower block under the starting fort
        "cfg": {
            "cols": [-2500, -2400, -2300, -2200, -2100, -2000, -1900, -1800, -1700, -1600],
            # Abyss-2's rows: the nest 130 high (y 5..-125), the lower block's storeys 405..550 (rocket 1's), 550..600
            # and 600..750 (rocket 2's)
            "rows": [-846, -746, -628, -502, -392, -250, -125, 5, 106, 206, 305, 405, 550, 600, 750],
            # the grid point (-2100, 550) snaps onto the starting fort's wall node (-2100, 500) (Abyss-2, test 5)
            "snap": 50,
            "weapon_pick_best": True,
            "bottom_up": True,
            "crossbrace_y": -1000,
            # the rockets' doors as on Abyss-2: each front post split where the weapon's strut ends, door above (from the
            # storey top down to that node, covering the barrel 65 above the strut), armour below; both ends of the
            # strut braced down-back below it
            "split_edges": [
                {"a": (-1900, 405), "b": (-1900, 550), "mid": (-1900, 505), "braces": [((-2000, 550), "bracing")]},
                {"a": (-1700, 405), "b": (-1700, 550), "mid": (-1700, 487.5), "materials": {"a": "door", "b": "armour"},
                 "braces": [((-1800, 550), "bracing")]},
                {"a": (-1900, 600), "b": (-1900, 750), "mid": (-1900, 705), "braces": [((-2000, 750), "bracing")]},
                {"a": (-1700, 600), "b": (-1700, 750), "mid": (-1700, 687.5), "materials": {"a": "door", "b": "armour"},
                 "braces": [((-1800, 750), "bracing")]}],
            # a rocket's body is centred (half-width 40), its barrel 60 long: LinkT = (strut length - 76) / length puts
            # the muzzle ~16 behind the door, as for Abyss-2's weapons (0.62 on the lower block's struts, 0.63 on the
            # perch). The flak on the tower's lowest floor (the starting fort's wall node to the tower's foot)
            "weapon_struts": [((-1900, 505), (-1700, 487.5), 0.62, "rocketemp"),
                              ((-1900, 705), (-1700, 687.5), 0.62, "rocketemp"),
                              ((-2140, -1040), (-1940, -1004.7), 0.63, "rocketemp"),
                              ((-2120.45, -250), (-2000, -250), 0.5, "flak")],
            "lane_cells": [(-1900, 550), (-1800, 550), (-1900, 750), (-1800, 750)],
            # the rockets' boxes (112 high) reach over the posts at x -1800 and a little into the storey tops: those
            # struts become background bracing (devices stand in front of it); on the perch tilted with the strut. The
            # smoke launcher's cell diagonals likewise
            "clear_boxes": ["rocketemp", "rocket", "flak", "shotgun", "smokebomb"], "clear_boxes_tilted": True,
            # the smoke launcher in a closed cell over the starting fort's front roof (the front cell of Abyss-2's nest,
            # x -1800..-1700, y -125..5, 130 high; the launcher's box is ~127): a door roof (it lobs upward) and a door
            # front post, the AI opens both to fire; nothing solid ahead of it in its row (the player, 28.10.2026:
            # sandbags block the line of fire, a weapon in the open is found by its first shot). The only spot with open
            # sky above it: the tower's cells have more tower above, its top lies under the cliff perch
            "mortar_slots": [((-1800, 5), (-1700, 5), 0.5)],
            "mortar_open_arc": True,
            # the machine gun (anti-air, later a minigun) in the tower's front cell above the flak; the starting fort's
            # machine gun is upgraded too
            "aa_y": -502,
            "orig_devices": [((-1895, 110), (-1795, 114), "machinegun", 0.35)],
            # batteries and stores inside the starting fort (not the slot at y 200, under the armoury's box, nor those
            # at y 500, rocket 1's strut), the lower block's bottom wall cell and the ledge cell beside the tower's top
            "use_eco_slots": True,
            "eco_slots": [((-2100, 400), (-2002, 405), 0.46), ((-1998, 206), (-1898, 210), 0.52),
                          ((-2104.43, 750.32), (-2000, 750), 0.5), ((-2200, -746), (-2100, -746), 0.5)],
            "clear_fire_lines": True,
            # nothing on the nest's roof (a connecting cell there would stand in the smoke's arc), no cell under the
            # starting fort's lower front face (its floor would run through the starting fort's node (-1751, 310))
            "keepout": [(-2000, -1900, -250, -125), (-1800, -1700, 305, 405)],
        },
        "plan": [
            # the armoury (on weapon_pack's ToGA1 slot inside the starting fort, no structure) sets the pace; meanwhile
            # the bottom mine, rocket 1's storey and lanes, then EMP rocket 1 (the AI waits on it until the armoury is
            # finished): one early weapon before the tower (Abyss-3 test 1: no weapon before ~300 s)
            ("tech", ["armoury"]),
            ("eco", ["mine"]),
            ("build", [(-2100, 550), (-2000, 550), (-1900, 550), (-1800, 550)]),
            ("struts", [((-1900, 505), (-1700, 487.5), "bracing")]),
            ("weapons", ["rocketemp"]),
            # the tower's first cell, its foot braced to the starting fort, then the tower tied to the cliff storey by
            # storey with its growth (Abyss-2's anchors; alone it leaned 40-170 in test 3)
            ("build", [(-2100, -250)]),
            ("struts", [((-2000, -250), (-2049.41, -196.45), "bracing"), ((-2000, -250), (-1997.10, -95.84), "bracing")]),
            ("struts", [((-2100, -392), (-2162.70, -386.08), "bracing"), ((-2120.45, -250), (-2162.70, -386.08), "bracing")]),
            ("build", [(-2100, -392)]),
            ("struts", [((-2100, -502), (-2178.13, -527.18), "bracing"), ((-2162.70, -386.08), (-2100, -502), "bracing")]),
            ("build", [(-2100, -502)]),
            ("struts", [((-2100, -628), (-2180.78, -672.55), "bracing"), ((-2178.13, -527.18), (-2100, -628), "bracing")]),
            ("build", [(-2100, -628)]),
            ("struts", [((-2180.78, -672.55), (-2100, -746), "bracing")]),
            # metal and energy (the AI averaged 100-260 metal on Abyss; Vanilla-5's rockets starved of energy with the
            # first turbine late): the three ledge mines, a turbine after each, a battery
            ("eco", ["mine"]),
            ("eco", ["turbine"]),
            ("eco", ["mine"]),
            ("eco", ["turbine"]),
            ("eco", ["mine"]),
            ("eco", ["turbine"]),
            ("eco", ["battery"]),
            # the smoke cell, its floor node braced down to the starting fort's front node (Abyss-2: built without it,
            # the nest's front cell swung down, physics.py sag ~320), the door roof and door front post, then the smoke
            # launcher inside
            ("build", [(-1800, 5)]),
            ("struts", [((-1700, 5), (-1747.27, 110.37), "bracing"),
                        ((-1800, -125), (-1700, -125), "door"), ((-1700, -125), (-1700, 5), "door")]),
            ("weapons", ["smokebomb"]),
            # the corner under the starting fort's lower front face closed (Abyss-2 test 6: the player's rockets broke in
            # there): from its node (-1751, 315) up to the lower block's top front nodes, the armour front post from its
            # node (-1695, 223) down to (-1700, 405)
            ("struts", [((-1751.69, 314.55), (-1700, 405), "bracing"), ((-1751.69, 314.55), (-1800, 405), "bracing"),
                        ((-1694.52, 223.44), (-1700, 405), "armour")]),
            # rocket 2's storeys at the bottom of the lower block (the wall cell last: its foundation (-2104, 750) is
            # 150.4 below the node above it, so it is built sideways), its strut, EMP rocket 2
            ("build", [(-2100, 600), (-2000, 600), (-1900, 600), (-1800, 600)]),
            ("build", [(-1800, 750), (-1900, 750), (-2000, 750), (-2100, 750)]),
            ("struts", [((-1900, 705), (-1700, 687.5), "bracing")]),
            ("weapons", ["rocketemp"]),
            # the flak behind a full door in the tower's front post (Vanilla-5: the door it opens; above a 65-high
            # shield it was sniped)
            ("struts", [((-2000, -392), (-2000, -250), "door")]),
            ("aa", ["flak"]),
            # two layers of wood in front of the starting fort's lower front face (Abyss-2's reactor wall), braced to its
            # nodes (-1746, 112), (-1695, 223), (-1752, 315) (as on Abyss-3: no nest woodspam to hang it from), and on
            # down in front of the closed corner to y 405
            ("struts", [((-1746.18, 112.27), (-1655, 112), "bracing"), ((-1694.52, 223.44), (-1650, 223), "bracing"),
                        ((-1751.69, 314.55), (-1655, 315), "bracing"),
                        ((-1655, 112), (-1650, 223), "bracing"), ((-1650, 223), (-1655, 315), "bracing"),
                        ((-1746.18, 112.27), (-1650, 223), "bracing"), ((-1694.52, 223.44), (-1655, 112), "bracing"),
                        ((-1694.52, 223.44), (-1655, 315), "bracing"), ((-1751.69, 314.55), (-1650, 223), "bracing"),
                        ((-1655, 112), (-1615, 112), "bracing"), ((-1650, 223), (-1610, 223), "bracing"),
                        ((-1655, 315), (-1615, 315), "bracing"),
                        ((-1615, 112), (-1610, 223), "bracing"), ((-1610, 223), (-1615, 315), "bracing"),
                        ((-1655, 112), (-1610, 223), "bracing"), ((-1650, 223), (-1615, 112), "bracing"),
                        ((-1650, 223), (-1615, 315), "bracing"), ((-1610, 223), (-1655, 315), "bracing")]),
            ("struts", [((-1655, 315), (-1655, 405), "bracing"), ((-1615, 315), (-1615, 405), "bracing"),
                        ((-1700, 405), (-1655, 405), "bracing"), ((-1655, 405), (-1615, 405), "bracing"),
                        ((-1700, 405), (-1655, 315), "bracing"), ((-1655, 315), (-1615, 405), "bracing"),
                        ((-1615, 315), (-1655, 405), "bracing")]),
            ("aa", ["machinegun"]),
            # the upgrade centre (its own slot in the starting fort's top storey, under the nest), then what needs no
            # tech while it builds (60 s), then the rockets
            ("tech", ["upgrade"]),
            ("eco", ["store", "battery"]),
            ("upgrades", ["rocket", "rocket"]),
            ("eco", ["turbine"]),
            ("upgrades", ["turbine2", "turbine2", "turbine2", "turbine2"]),
            ("upgrades", ["shotgun", "minigun", "minigun"]),
            # late game: EMP rocket 3 on Abyss-2's lower cliff perch above the ledge mines (its cannon was placed there in
            # test 7): from the tower's top one cell of background bracing (the turbines' only wind passes there), the
            # strut falling 10 degrees from a node off the rock, tied to two anchors on the upper cliff face, to a front
            # node; the door square to the strut, the roof strut over it; the perch closed into four triangles of
            # background bracing around a node in its back part, so the player does not see the rocket placed (Abyss-3
            # test 1)
            ("struts", [((-2100, -846), (-2100, -950), "backbracing"), ((-2000, -846), (-2000, -950), "backbracing"),
                        ((-2100, -950), (-2000, -950), "backbracing"), ((-2100, -846), (-2000, -950), "backbracing"),
                        ((-2000, -846), (-2100, -950), "backbracing"),
                        ((-2100, -950), (-2182.73, -1050.25), "backbracing"), ((-2100, -950), (-2140, -1040), "bracing"),
                        ((-2182.73, -1050.25), (-2140, -1040), "bracing"), ((-2140, -1040), (-2162.18, -1110.06), "bracing"),
                        ((-2000, -950), (-1940, -1004.7), "backbracing"), ((-2100, -950), (-1940, -1004.7), "backbracing"),
                        ((-2140, -1040), (-1940, -1004.7), "bracing")]),
            ("struts", [((-1940, -1004.7), (-1917.4, -1132.72), "door"), ((-2140, -1040), (-2112, -1167), "bracing"),
                        ((-2162.18, -1110.06), (-2112, -1167), "bracing"), ((-2112, -1167), (-2148.94, -1210.1), "bracing"),
                        ((-2112, -1167), (-1917.4, -1132.72), "bracing")]),
            ("struts", [((-2140, -1040), (-2090, -1100), "backbracing"), ((-2090, -1100), (-2112, -1167), "backbracing"),
                        ((-2090, -1100), (-1940, -1004.7), "backbracing"), ((-2090, -1100), (-1917.4, -1132.72), "backbracing")]),
            ("weapons", ["rocketemp"]),
            ("eco", ["battery"]),
            ("upgrades", ["rocket"]),
            ("upgrades", ["mine2", "mine2"]),
        ],
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
_V_BACK = _box(-3600, -3100, 205, 700)       # back block down to the ground (counterweight, eco, tech)


def _v_terrace(*steps):
    """Storeys over the starting fort roof (y=205), each given as (top y, front x): the storeys step
    back, so every storey has its own front cell for a weapon and roof space behind it."""
    fs, y1 = [], 205
    for y0, x1 in steps:
        fs.append(_box(-3500, x1, y0, y1))
        y1 = y0
    return _union(*fs)


_V_STEPS = _v_terrace((5, -2845), (-95, -2845), (-195, -3100))
# weapon tower (x -3400..-2945, five storeys up to y=-295): solid and X-braced, standing on the back
# block and the starting fort's roof posts (-3093, -2945); weapon column at the front, mortars and the
# turbines on its roof (the only height where the wind reaches a turbine from both sides).
# The back block (x -3600..-3100) ends at the starting fort's roof. The prow (-2945..-2845, beyond the
# cliff edge at -2900) carries two light storeys.
_V_TALL = _union(_box(-3400, -2945, -295, 205), _box(-2945, -2845, 5, 205))
# sniper and mortar rush (Vanilla-2): the mortars cannot wait for a five-storey tower (~165 struts before its roof).
# Two storeys over the starting fort's roof and one column back (x -3500..-2845; rows of the variant: 205, 105, -25):
# the first one solid (the sniper on the starting fort's roof beam, like the game's Template-2, firing through the
# prow storey with the starting fort's machine gun; on the prow it was refused with CS_UNSTABLE in both test matches,
# 25.10.2026), the second one hidden behind background bracing: the mortar nest over the deck and the turbine gallery
# behind it, each behind two stacked sandbags (details in VANILLA_VARIANTS).
_V_RUSH_DECK = _union(_box(-3500, -2845, -25, 205), _V_BACK)
# heavy weapons placed like weapon_pack's own ToGWM2 (shifted into this frame: 20mm on a 100-wide cell at
# x -3303..-3203, LinkT 0.75; cannon a column back, LinkT 0.74): (left x, floor y, LinkT). They stand behind
# the 155-wide front cells and fire through them (fire lanes, mark_large). The second one stands directly
# above the first, in the front part of the tower: one column back (x -3300..-3200), a storey higher or lower,
# it was refused with CS_UNSTABLE while the first was built and fired (test matches 24.10.2026). That column is
# the seam where the back part of the tower (leaning 25-30 more) meets the front part: its cells are squeezed.
_V_LARGE_TOGWM2 = [(-3200, -20, 0.5), (-3200, -145, 0.5)]
# The cannon storeys (floors 5 and -120) are 125 high instead of 100: the cannon's box reaches ~90 above its
# floor, and the game turns struts a device overlaps into background bracing, on which nothing can be placed
# (test match 24.10.2026: the floor of the second cannon, 100 above the first, had become background bracing).
# The sniper storey below them (floor 105, front column) is 125 high too: a sniper there was refused with
# CS_UNSTABLE in both tests with 100-high storeys. Rows above the starting fort: 205, 105, -20, -145, -270,
# -370 (tower roof); the 155x125 cells get 199-long diagonals (MAX_LINK 205).
# Less load on the starting fort's prow (it hangs over the cliff; test match 24.10.2026: its armour chain reached
# 0.97 of its breaking limit after the first cannon was placed and the fort collapsed at 7.8 min, without enemy
# fire): no prow storeys, no woodspam base on the prow, cannons at LinkT 0.5 instead of 0.75 (ToGWM2).
_V_HIGH_ROWS = [-500, -370, -270, -145, -20, 105, 205, 308, 405, 503, 602, 700]
# Defence (as in Vanilla-2): the roof turbines stand in a hidden cage, a storey of background bracing on the tower
# roof (130 high: a turbine is 127, two stacked sandbags 2 x 51), through which the wind blows and the player cannot
# see; its front cell (x -3100..-2945) is split for two stacked sandbags in front of the turbines (128 from the
# nearest one; devices at one height need ~90). That cell held a turbine: two turbines remain (the seam column
# x -3300..-3200 refuses them), upgraded late (67.5 each instead of 45).
_V_TALL_HIGH = _union(_box(-3400, -2945, -370, 205), _box(-3400, -2945, -500, -370))
_V_CAGE_HIGH = {"turbine_floor_y": -370, "hidden_box": (-3400, -2945, -500, -370),
                "split_cell": [(-3100, -500)], "sandbag_slots": [(0, "floor", 0.6), (0, "mid", 0.6)],
                "tower_connect": {"base_y": 205, "storeys": 2, "skip_floors": (-370,)}}
# The front cell on the starting fort's front post (x -3100..-2945, floor 105) refused the early sniper with
# CS_UNSTABLE in every test match, also with a 125-high storey (24.10.2026: the AI gave up after 120 s; the links
# at its front node were strained to 1.79 of their planned length); snipers stay out of it (a machine gun takes it).
# split_doors: the doors of the sniper and the heavy weapons only as long as the shot needs (Vanilla-2's sniper door,
# 61.5 instead of 99, fired 124 shots in a test match)
_V_HIGH_CFG = dict(_V_CAGE_HIGH, **{"rows": _V_HIGH_ROWS, "large_cells": _V_LARGE_TOGWM2, "turbine_roof_max_y": -370, "split_doors": True,
               "weapon_avoid": [(-3100, 105, {"sniper"})],
               # the roof turbine on the seam column (x -3300..-3200, where the back and front parts of the tower
               # meet) was refused with CS_UNSTABLE in every test match (24.10.2026: three tries, the AI gave up
               # after 120 s); the cage has two turbines without it and the sandbags' cell
               "turbine_avoid": [(-3300, -370)],
               "large_top_min": -270, "large_top_max": -145,
               "woodspam": {"wall_x": -2945, "layers": [-2905, -2865], "rows": [-370, -270, -145],
                            "base": []}})

VANILLA_VARIANTS = {
    # Every variant ends with a late-game block (more anti-air, more weapons, upgrades), so the AI
    # does not run out of things to build while metal piles up (test match 22.10.2026: plan done
    # after 5.4 min, then minutes at the storage cap). The raised back towers give extra front
    # cells that look out over the deck.
    "artillerie": {
        "title": "Sniper and mortar rush: hidden mortar nest and turbine gallery behind sandbags, sniper on the starting fort",
        "shape": _V_RUSH_DECK,
        "tech_slots": {"upgrade": [((-3200, 600), (-3098, 602), 0.02)]},
        # the sniper takes the front column on the starting fort's roof beam (weapon_cells). The game allows one
        # device per strut (test match 25.10.2026: sandbags planned beside the mortars on their struts took both,
        # no mortar was placed): the nest floor over the front column is built in two halves (split_edges, braced
        # down to the starting fort's roof posts), one mortar on each (mortar_slots); the prow's nest cell is split
        # at half height (split_cell) and carries two stacked sandbags in front of both mortars (sandbag_slots).
        # Behind the nest, on the same floor (y 105), the turbine gallery: turbines on the floor of an open storey of
        # background bracing (wind passes through it, nothing rests on it), its front cell (x -3200..-3100) split for
        # two stacked sandbags against sniper fire. Nest and gallery are one hidden storey (hidden_box), 130 high
        # (rows): each sandbag half 65 (box 51; a 100-high split cell refused the upper sandbags, test match
        # 25.10.2026), a turbine 127; 135 would make the 155-wide nest cell's diagonal longer than MAX_LINK. Two storeys only: the roof turbines of the five-storey tower waited for the
        # whole back block (~165 struts; storeys above the second wait for the first two over the full width,
        # tower_connect), the gallery needs ~30
        # the prow storey (on the starting fort's roof) stays a fire lane for the sniper behind it (lane_cells).
        # The machine guns (anti-air) stand on the gallery roof, the only free place of the low fort (not on the nest
        # roof: the mortar shells pass through it): the first one as soon as that roof stands, the second late; both
        # become miniguns. The starting fort's machine gun (lower front, not in the sniper's way) stays
        "roof_weapons": {"machinegun"},
        "cfg": {"small_low_first": True, "weapon_pick_best": True,
                "rows": [-425, -325, -225, -125, -25, 105, 205, 308, 405, 503, 602, 700],
                "roof_weapon_cells": [(-3200, -25), (-3400, -25)],
                # the sniper at LinkT 0.7 (was 0.5): its muzzle ~44 behind the door instead of ~74, where the game's
                # clear corridor around the shot is narrowest (FireClearanceOffsetInner 20 at the muzzle, 40 at 1000);
                # its body still overlaps the post at x -2945, which the game then turns into background bracing
                "weapon_cells": [(-3100, 205, "sniper", 0.7)],
                "lane_cells": [(-2945, 205)],
                "rebrace_after_mine": [],
                "hidden_box": (-3500, -2845, -25, 105),
                "split_edges": [{"a": (-3100, 105), "b": (-2945, 105), "mid": (-3022, 105),
                                 "braces": [((-3093.19, 205.21), "backbracing"), ((-2945.11, 206.49), "backbracing")]},
                                # the sniper's door: the prow storey's front post only as a door where the shot passes
                                # (barrel ~50 above its strut, y ~155): door 61.5 long (y 204..142.5, ~1.2 s to open
                                # at DoorSpeed 50 instead of ~2 s for the whole 99), armour above it (37.5, the
                                # minimum strut length); the mid node braced to the storey's back corners
                                {"a": (-2846.18, 203.99), "b": (-2845, 105), "mid": (-2845, 142.5),
                                 "materials": {"a": "door", "b": "armour"},
                                 "braces": [((-2945.11, 206.49), "backbracing"), ((-2945, 105), "backbracing")]}],
                # at the outer ends of the halves: 116 apart like the game's own plans; 77 apart (LinkT 0.5 each) the
                # second was refused with CS_UNSTABLE, later CS_OCCUPIED (two test matches, 25.10.2026)
                "mortar_slots": [((-3100, 105), (-3022, 105), 0.25), ((-3022, 105), (-2945, 105), 0.75)],
                "split_cell": [(-2945, -25), (-3200, -25)],
                # devices at the same height need ~90 between them: the gallery's lower sandbags 70 from the first
                # mortar were refused (CS_OBSTRUCTION, then CS_UNSTABLE; test match 25.10.2026), the nest's 89 from
                # the second mortar were placed. Lower gallery sandbags at x -3170 (90 from the mortar), the turbines
                # at -3465, -3365, -3265 (100 apart, 95 from the sandbags)
                "sandbag_slots": [(0, "floor", 0.7), (0, "mid", 0.7), (1, "floor", 0.3), (1, "mid", 0.5)],
                "turbine_floor_y": 105, "turbine_floor_t": 0.35,
                # woodspam, never in the turbines' wind (in the hidden storey it stood at their hub height, 460-600
                # in front of them), both regions early, right after the gallery's sandbags (the reactor's front was
                # where the player broke through in both lost test matches): 0 = two layers in front of the starting
                # fort's prow below the deck (y 205..310, in front of the reactor); 1 = two layers hanging in front of
                # the starting fort's lower front (y
                # 411..700, the face at x -2892..-2900, so the layers at -2852/-2812 keep every strut at least 40; the rock
                # ends there), early: in a test match one laser beam
                # cut through that unprotected face at ~451 s and the starting fort with the reactor collapsed
                # within 2 s. The band 411..505 stays background bracing: the starting fort's machine gun (strut at
                # y 505) fires through it
                "woodspam": [{"wall_x": -2845, "layers": [-2805, -2765], "rows": [205, 310], "base": [],
                              "outside": "bracing"},
                             {"wall_x": -2896, "layers": [-2852, -2812], "rows": [411, 505, 602, 700], "base": [],
                              "outside": {411: "backbracing", 505: "bracing", 602: "bracing"}}]},
        "plan": [
            # sniper and mortar rush: the workshop (60 s) sets the pace for the mortars. The workshop at once (the
            # inner armour in front of the reactor is kept: rebrace_after_mine off; sold for the rush, it fell first
            # when the player's rockets broke through to the reactor, test match 25.10.2026); the sniper (100 m / 300 e, no tech), the deck and the nest's sandbags (0 m / 300 e)
            # while the workshop builds; the mortars (200 m / 1000 e each) as soon as it is finished. Placed before
            # their sandbags, both mortars were destroyed 3-5 s later by the player's machine guns, whose fire passes
            # the background bracing of the nest (test match 25.10.2026); the second mortar once refused beside the
            # sandbags stood 77 from the first, now 116 (89-90 from the sandbags worked)
            ("tech", ["workshop"]),
            ("weapons", ["sniper"]),
            ("defence", ["sandbags", "sandbags"]),
            ("weapons", ["mortar", "mortar"]),
            # then metal: all three free mine sites (300 m each, +4 metal/s) before the turbines and the gallery.
            # With the mines after the upgrade centre the first one came at 347 s, metal stayed below 150 for 62% of
            # the match and the plan stalled for 4 minutes, while energy stood at 2400-5000 and at its cap from 260 s
            # (15th test match, 25.10.2026; the player had six mines after 55 s)
            ("eco", ["mine", "mine", "mine"]),
            # then energy: each mortar shot costs 200 energy and every strut 0.5 per unit length (with the roof
            # turbines waiting for the tower, energy once ran down to 2-20); the first turbine, the gallery's
            # sandbags, then more turbines
            ("eco", ["turbine"]),
            ("defence", ["sandbags", "sandbags"]),
            ("defence", ["woodspam"]),
            ("aa", ["machinegun"]),
            ("eco", ["turbine", "turbine"]),
            # the upgrade centre, then what needs no tech while it builds (60 s): every upgrade waits until it is
            # finished, and the AI waits on a planned upgrade without moving on (test match 25.10.2026: upgrade
            # centre placed at 254 s, the heavy mortars only at 306 s, with just a battery in between)
            ("tech", ["upgrade"]),
            ("eco", ["battery", "store"]),
            ("aa", ["machinegun"]),
            # late game: first the mortars (heavy mortars) and the sniper (AP sniper), then the miniguns (both
            # machine guns on the gallery roof upgraded), then the woodspam
            ("upgrades", ["mortar2", "mortar2"]),
            ("upgrades", ["sniper2"]),
            ("upgrades", ["minigun", "minigun"]),
            ("defence", ["woodspam"]),
            ("upgrades", ["turbine2", "turbine2", "turbine2"]),
            ("eco", ["battery"]),
            ("upgrades", ["mine2", "mine2"]),
            ("defence", ["woodspam"]),
        ],
    },
    "kanone20mm": {
        "title": "20mm rush (weapon_pack): workshop, munitions plant and the first 20mm cannon before anything else",
        "shape": _union(_V_TALL_HIGH, _V_BACK),
        # the first 20mm stands low, on floor 105 of the column right behind the starting fort (x -3200..-3100,
        # a 125-high storey), the second one storey higher (that column hangs on the starting fort's back posts:
        # ~3 struts per cell). The munitions plant keeps its proven slot two columns back: on the bottom floor of
        # the column right behind the starting fort, next to the workshop, it was refused with CS_UNSTABLE
        # (test match 24.10.2026: no stress, no sag; its body beside the workshop, its 170-high box over the
        # workshop's strut) and the AI gave up on it
        # the machine gun stays out of the sniper's cell (front column, floor -145): the sniper was built there,
        # while one on the top front cell (floor -270) was refused once the tower stood below it
        # the sniper at LinkT 0.28 (was 0.5): the brace of its split door (from the door's top node back to the cell's
        # top corner) then clears its box; its muzzle is still ~12 behind the door
        "cfg": dict(_V_HIGH_CFG, large_cells=[(-3200, 105, 0.5), (-3200, -20, 0.5)], support_cheapest=True, sniper_t=0.28,
                    weapon_avoid=_V_HIGH_CFG["weapon_avoid"] + [(-3100, -145, {"machinegun"})]),
        "plan": [
            # 20mm rush: the tech chain (workshop 60 s, munitions plant 90 s, 20mm 70 s) sets the pace, the starting
            # economy (601 m / 3004 e, +13 m/s, +100 e/s, caps 900 / 5000) pays for it on time if nothing else
            # comes first (economy model: first shot ~225 s instead of ~450 s). The armour sale and the workshop
            # at once; the struts for the munitions slot while the workshop builds; the munitions plant needs the
            # whole 5000 energy cap; a mine and a battery and the cannon's cell from the surplus while it builds
            ("eco", ["rebrace"]),
            ("tech", ["workshop"]),
            ("tech", ["munitions"]),
            ("eco", ["mine", "battery"]),
            ("weapons", ["cannon20mm"]),
            # then the economy and the tower; the first turbine in the hidden cage on the tower roof, then the two
            # stacked sandbags in front of it
            ("eco", ["turbine"]),
            ("defence", ["sandbags", "sandbags"]),
            ("aa", ["machinegun"]),
            ("eco", ["mine"]),
            ("weapons", ["sniper"]),
            ("eco", ["turbine"]),
            ("eco", ["mine"]),
            # two turbines fit in the cage: upgraded ones instead of more (67.5 energy instead of 45); the upgrade
            # centre first, then what needs no tech while it builds (60 s)
            ("tech", ["upgrade"]),
            ("eco", ["store", "battery"]),
            ("aa", ["machinegun"]),
            ("weapons", ["sniper"]),
            ("upgrades", ["turbine2", "turbine2"]),
            ("defence", ["woodspam"]),
            ("weapons", ["cannon20mm"]),
            # late game: more anti-air, the woodspam completed
            ("aa", ["machinegun"]),
            ("defence", ["woodspam"]),
        ],
    },
    # Vanilla-4 (cannon deck) removed on 28.10.2026; the placeholder keeps Vanilla-5 and -6 at their numbers
    "kanone": None,
    # Vanilla-5, rockets (replaces the laser rush: a laser took ~5 minutes on Vanilla and lost four test matches, 25.10.2026):
    # EMP rockets as early as possible, a smoke launcher and anti-air, later upgraded to rockets. The smoke goes up
    # first, so the enemy's anti-air cannot see the rockets (ai.lua, Fire.SmokeCover); the EMP rockets fire already
    # while the upgrade centre is built. Vanilla-2's low fort (the most tested layout), without its sniper and mortars;
    # the armoury on the starting fort's proven workshop slot (no workshop needed), so it costs no structure.
    # A rocket needs a free lane ahead, like a 20mm, cannon or laser (no other rocket or smoke launcher in its row), and
    # a short door in front of it like a sniper (split_doors). Two storeys over the starting fort like Vanilla-2, both
    # 130 high (rows 205, 75, -55; a rocket's box is 112): EMP rocket 1 on the starting fort's roof beam, where
    # Vanilla-2's sniper stood (124 shots through its split door), firing through the prow's deck cell; EMP rocket 2 in
    # the nest above it, firing through the prow's nest cell, its door cut into that post (door_posts) with background
    # bracing around it (the hidden storey: the gallery turbines need the wind); the smoke launcher on the nest roof
    # (y -55), in neither rocket's row; flak and the machine gun on the gallery roof (they fire at the sky).
    # The first rocket layout (26.10.2026) put a third storey on the prow for rocket 2: the armoury was refused on the
    # starting fort's workshop slot (CS_UNSTABLE, the strut behind it strained to its limit), so no weapon was built,
    # and the 360-high front stack swayed 30-40 (Vanilla-6: 20-33); the player's 8 rockets brought it down at 394 s.
    "rockets": {
        "title": "Rocket rush: armoury, two EMP rockets behind short doors one above the other, smoke on the nest roof, flak behind",
        # plus one small storey on the gallery's back corner for the smoke launcher (its own row, see below)
        "shape": _union(_box(-3500, -2845, -55, 205), _V_BACK, _box(-3500, -3400, -155, -55)),
        # the armoury on the munitions slot (same size; the munitions plant was built there in Vanilla-3/-4)
        "tech_slots": {"armoury": [((-3400, 602), (-3299, 604), 0.49)],
                       "upgrade": [((-3200, 600), (-3098, 602), 0.02)]},
        "roof_weapons": {"machinegun"},
        # Vanilla-2's config with these changes (merged below the table)
        "cfg": {
            "mortar_slots": [], "split_edges": [],
            # no top cell reserved for the smoke launcher (lobbed): the reservation took a rocket's cell
            "reserve_mortar": False,
            # doors only as long as the rockets' shots need, like the snipers' (split_doors)
            "split_doors": True,
            "rows": [-445, -345, -245, -155, -55, 75, 205, 308, 405, 503, 602, 700],
            # LinkT 0.7 like Vanilla-2's sniper: the barrel (60) ends ~85 behind the door
            "weapon_cells": [(-3100, 205, "rocketemp", 0.7), (-3100, 75, "rocketemp", 0.7)],
            "lane_cells": [(-2945, 205), (-2945, 75)],
            "hidden_box": (-3500, -2845, -55, 75),
            # rocket 2's door in the nest prow's front post (background bracing in the hidden storey), background
            # bracing around it: a full door there blocked the gallery turbines' wind on the right side
            "door_posts": [(-2845, -55, 75)],
            "door_rest": [((-2845, -55, 75), "backbracing")],
            # the gallery's split cell only (the nest's prow cell is rocket 2's lane)
            "split_cell": [(-3200, -55)], "sandbag_slots": [(0, "floor", 0.3), (0, "mid", 0.5)],
            "turbine_floor_y": 75,
            # flak early on the nest roof, behind the armour shield (third test: ~15 heavy mortar shells brought the
            # front stack down; anti-air shoots the shells, an armour roof does not stop them). A weapon blocks the
            # line of fire of every weapon behind it in its row: on the gallery roof behind the flak the smoke launcher
            # could not fire toward the enemy fort, so it stands on one more storey on the gallery's back corner
            # (x -3500..-3400, roof y -155), over the back block's solid column; the machine gun (anti-air only) may
            # stand behind the flak
            "weapon_slots": [((-3100, -55), (-2945, -55), 0.5, "flak"),
                             ((-3500, -155), (-3400, -155), 0.5, "smokebomb")],
            "roof_weapon_cells": [(-3300, -55), (-3200, -55)],
            # the smoke launcher's storey rests on the gallery only (like the tower cage on Vanilla-3)
            "tower_connect": {"base_y": 205, "storeys": 2, "skip_floors": (-55,)},
            # the player's brace across the starting fort's two lower storeys (217-218 long in the game, which allows 218)
            "long_struts": [((-2996, 504), (-2900, 700))]},
        "plan": [
            # the armoury, a mine while it builds, the long brace, the EMP rockets (deck, nest) with their lanes and
            # doors, then the flak behind its shield (the shield first: placing the flak turns the armour in front of
            # it into a door it opens), then energy: the rockets cost energy per shot (second test: with the first
            # turbine at 293 s energy stayed below 900 from 90 to 330 s while metal sat at its cap)
            ("tech", ["armoury"]),
            ("eco", ["mine"]),
            # a long background brace through the starting fort's front column, from its node at y 504 down to the
            # front ground node: the player builds it early in every match (16-74 s); the starting fort has nothing
            # across those two storeys, and its lower front gave way in two lost matches (Vanilla-6, Vanilla-5)
            ("struts", [((-2996, 504), (-2900, 700), "backbracing")]),
            ("weapons", ["rocketemp", "rocketemp"]),
            # their lanes with the doors at once (left to the final pass, the doors came only at the end of the plan)
            ("build", [(-2945, 205), (-2945, 75)]),
            # the flak's shield: a full-height door (130, the flak stands ~118 tall) the AI opens to fire, like the
            # machine guns' full doors; the 65-high shield before let the player snipe the flak above it (fourth test)
            ("struts", [((-2945, -55), (-2945, -185), "door"), ((-2945, -185), (-2845, -55), "backbracing")]),
            ("aa", ["flak"]),
            ("eco", ["turbine"]),
            ("eco", ["mine", "mine"]),
            ("tech", ["upgrade"]),
            ("upgrades", ["rocket", "rocket"]),
            # the gallery with its sandbags, anti-air on its roof behind the rockets (flak first, then the machine gun;
            # the gallery roof needs ~90 actions of support from the back block, so until then the starting fort's
            # machine gun covers the sky), woodspam in front of the reactor and the lower front
            ("defence", ["sandbags", "sandbags"]),
            # the smoke launcher on its storey on the gallery's back corner (its arc passes over everything ahead)
            ("weapons", ["smokebomb"]),
            ("defence", ["woodspam"]),
            ("aa", ["machinegun"]),
            ("eco", ["turbine", "turbine"]),
            ("eco", ["battery", "store"]),
            ("upgrades", ["turbine2", "turbine2", "turbine2"]),
            ("eco", ["battery"]),
            ("upgrades", ["minigun"]),
            ("upgrades", ["mine2", "mine2"]),
            ("defence", ["woodspam"]),
        ],
    },
}


VANILLA_VARIANTS["rockets"]["cfg"] = dict(VANILLA_VARIANTS["artillerie"]["cfg"], **VANILLA_VARIANTS["rockets"]["cfg"])

# Vanilla-6, the modular fort: Vanilla-2's low fort (the most tested layout: the hidden mortar nest and turbine gallery
# two storeys over the starting fort, nothing in the mortars' arc), but its weapons are reactive build modules
# (docs/ai.md). The fixed core builds the economy, the tech, the defence and the empty slots the weapons need (the
# sniper's cell, the nest cell with the mortar struts, the gallery roof). Each module goes in when the player builds
# what it answers, and at the latest at its time, so the AI reaches its goal also against a player who builds
# nothing: an artillery fort (sniper, two mortars, anti-air, then heavy mortars, an AP sniper, more anti-air and
# miniguns). The times set the order without threats; the player's devices pull a module forward. A fixed plan loses
# to whatever the player picks against it (Vanilla-5: four lost matches against four different weapons).
_V6_MISSILES = ("missile", "missile2", "missileinv", "missile2inv", "rocket", "rocketemp")
VANILLA_VARIANTS["modular"] = {
    "title": "Modular fort: Vanilla-2's low fort as a core, its weapons as reactive modules",
    "shape": VANILLA_VARIANTS["artillerie"]["shape"],
    "tech_slots": VANILLA_VARIANTS["artillerie"]["tech_slots"],
    "roof_weapons": {"machinegun"},
    "cfg": dict(VANILLA_VARIANTS["artillerie"]["cfg"]),
    "plan": [
        # core: the workshop (mortars need it, 60 s), the nest's sandbags (0 metal) and the two weapon cells over the
        # starting fort (the sniper's cell on its roof beam, the nest cell with the split mortar struts above it)
        ("tech", ["workshop"]),                                     # 1
        ("build", [(-3100, 205, "sniper"), (-3100, 105)]),          # 2 (before anything builds the sniper's cell)
        ("defence", ["sandbags", "sandbags"]),                      # 3
        # metal first (15th Vanilla-2 test: with the mines late the AI starved), then energy and the gallery
        ("eco", ["mine", "mine", "mine"]),                          # 4
        ("eco", ["turbine"]),                                       # 5
        ("defence", ["sandbags", "sandbags"]),                      # 6
        ("defence", ["woodspam"]),                                  # 7
        ("eco", ["turbine", "turbine"]),                            # 8
        ("tech", ["upgrade"]),                                      # 9
        ("eco", ["battery", "store"]),                              # 10
        ("upgrades", ["turbine2", "turbine2", "turbine2"]),         # 11
        ("eco", ["battery"]),                                       # 12
        ("upgrades", ["mine2", "mine2"]),                           # 13
        ("defence", ["woodspam"]),                                  # 14
    ],
    # "after": generated on the core as it stands after that many steps (its cells built, nothing duplicated)
    "modules": [
        # the sniper answers snipers and heavy direct weapons (it outranges them and hits a laser while it is built)
        {"name": "sniper", "after": 3,
         "trigger": {"types": ("sniper", "sniper2", "laser", "firebeam", "cannon", "cannon20mm"), "count": 1, "time": 45},
         "plan": [("weapons", ["sniper"])]},
        # two mortars on the nest's split struts: counter-battery and the fort's offence
        {"name": "artillery", "after": 3, "trigger": {"types": ("mortar", "mortar2"), "count": 1, "time": 150},
         "plan": [("weapons", ["mortar", "mortar"])]},
        # anti-air on the gallery roof against missiles and rockets (the gallery's front cell needs ~90 actions of
        # support from the back block, so it comes with the gallery's sandbags; until then the starting fort's
        # machine gun)
        {"name": "antiair", "after": 6, "trigger": {"types": _V6_MISSILES, "count": 1, "time": 240},
         "plan": [("aa", ["machinegun"])]},
        {"name": "heavyartillery", "after": 9, "trigger": {"time": 330, "after": "artillery"},
         "plan": [("upgrades", ["mortar2", "mortar2"])]},
        {"name": "antiair2", "after": 8, "trigger": {"types": _V6_MISSILES, "count": 3, "time": 420, "after": "antiair"},
         "plan": [("aa", ["machinegun"])]},
        {"name": "sniper2", "after": 9, "trigger": {"types": ("sniper2", "laser", "firebeam"), "count": 2, "time": 450,
                                                    "after": "sniper"},
         "plan": [("upgrades", ["sniper2"])]},
        {"name": "miniguns", "after": 9, "trigger": {"time": 540, "after": "antiair2"},
         "plan": [("upgrades", ["minigun", "minigun"])]},
        # late game: in the first test match (26.10.2026) the plan was finished at ~485 s and the AI sat at its storage
        # caps (1200 / 9000) for six minutes while the player's machine guns and mortars wore down the starting fort's
        # lower front. Two more mortars on the free gallery-roof cells (100 from each machine gun; nothing above
        # them), their upgrade, and one more woodspam layer in front of the lower front (earlier when the player
        # has six machine guns: their fire wore it down)
        {"name": "artillery2", "after": 14, "trigger": {"time": 480, "after": "heavyartillery"},
         "variant": {"roof_weapons": {"machinegun", "mortar"}},
         "cfg": {"roof_weapon_cells": [(-3300, -25), (-3500, -25)]},
         "plan": [("weapons", ["mortar", "mortar"])]},
        {"name": "heavyartillery2", "after": 14, "trigger": {"time": 560, "after": "artillery2"},
         "plan": [("upgrades", ["mortar2", "mortar2"])]},
        {"name": "frontlayer", "after": 14, "trigger": {"types": ("machinegun", "minigun"), "count": 6, "time": 600},
         "cfg": {"woodspam": VANILLA_VARIANTS["artillerie"]["cfg"]["woodspam"] + [
             {"wall_x": -2812, "layers": [-2772], "rows": [411, 505, 602, 700], "base": [], "outside": "bracing"}]},
         "plan": [("defence", ["woodspam:2"])]},
    ],
}


# ----------------------------------------------------------------------------- Generator


def clear_fire_lines(actions, extra=(), cautious=True):
    """Plan lines with every strut that would block a weapon (rules.fire_blockers: built after the weapon, or
    outside the game's recession box and the weapon's body) turned into background bracing; armour becomes a door.
    extra: lines appended for the check only (module weapons)."""
    for _ in range(5):
        acts = parse_lines(list(actions) + list(extra))
        pos, links, devices, _g = rules.build_state(acts)
        fix = {}
        for name, ia, ib, t, pair, kd in devices:
            if ia in pos and ib in pos:
                p = rules._point(pos, ia, ib, t)
                for m, a, b, k, pr, dist in rules.fire_blockers(links, pos, name, p, kd, cautious=cautious):
                    fix[pr] = "door" if m == "armour" else "backbracing"
        if not fix:
            break
        out = []
        for line in actions:
            ids = re.findall(r"OriginalNode[AB]Id = (\d+)", line)
            if ("CREATE_LINK" in line or "CREATE_NODE" in line) and len(ids) == 2:
                m = fix.get(frozenset(int(x) for x in ids))
                if m:
                    line = re.sub(r'MaterialSaveName = "\w+"', 'MaterialSaveName = "%s"' % m, line)
            out.append(line)
        actions = out
    return actions

class Plan:
    def __init__(self, cfg, terrain, base_pos, seed):
        self.cfg = cfg
        self.t = terrain
        self.rng = random.Random(seed)
        self.orig = {k: v for k, v in base_pos.items() if k < 10000}
        self.nodes = {}        # (i,j) -> (id, pos, kind) kind: orig/new/found
        self.next_id = 10000
        self.built_nodes = set(self.orig)
        self.depth = {}        # node id -> chain depth (node creations since an anchor; see chain())
        self.links = {}        # frozenset(idA,idB) -> material (last set)
        self.actions = []
        self.pos = dict(self.orig)
        self.devices = {}      # cell -> device
        self.placed = []       # (device, a, b, t)
        self.problems = []
        self.tech_done = set()
        self.slot_cells = {}   # cell -> device it was built for, by a "build" step (a module places it)

    # --- Grid
    def colx(self, i, j):
        """x of grid column i in node row j: maps can use other column positions from upper_y upwards
        (cols_upper), e.g. to match the posts of the starting fort's roof."""
        up = self.cfg.get("cols_upper")
        if up and self.cfg["rows"][j] <= self.cfg["upper_y"]:
            return up[i]
        return self.cfg["cols"][i]

    def cell_x(self, c):
        """x range of cell c (columns of its bottom row)."""
        return self.colx(c[0], c[1] + 1), self.colx(c[0] + 1, c[1] + 1)

    def build_lattice(self):
        cols, rows = self.cfg["cols"], self.cfg["rows"]
        for i in range(len(cols)):
            for j, y in enumerate(rows):
                x = self.colx(i, j)
                p = (x, y)
                best = min(self.orig.items(), key=lambda kv: math.dist(kv[1], p))
                if math.dist(best[1], p) <= self.cfg["snap"]:
                    self.nodes[(i, j)] = (best[0], best[1], "orig")
                    continue
                surf, d = self.t.nearest_surface(p)
                if self.t.inside(p) or d < self.cfg.get("rock_clear", 12):
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
                x0, x1 = self.cell_x((i, j))
                cx, cy = (x0 + x1) / 2, (rows[j] + rows[j + 1]) / 2
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
                (x0, x1), y0, y1 = self.cell_x((i, j)), rows[j], rows[j + 1]
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
        # support_cheapest: by the fewest cells that must be built first (the whole chain below), not the
        # shallowest chain; on Vanilla the column right behind the starting fort hangs on its back posts, while
        # the shallowest choice led from column to column through the whole back block
        cheapest = self.cfg.get("support_cheapest")
        depth, best, closure = {}, {}, {}
        for c in sorted(via, key=lambda c: -c[1]):
            for n in via[c]:
                if n not in best:
                    hs = [h for h in ((n[0] - 1, n[1]), n) if h in depth]
                    key = (lambda h: len(closure[h])) if cheapest else (lambda h: depth[h])
                    best[n] = None if held.get(n, 0) is None or not hs else min(hs, key=key)
            depth[c] = 1 + max([depth[best[n]] if best[n] else 0 for n in via[c]])
            closure[c] = {c}.union(*[closure[best[n]] for n in via[c] if best[n]])
        self.deps = {c: {best[n] for n in via[c]} - {None} for c in via}
        self.depth = depth
        dropped = self.cells - sup
        if dropped:
            self.cells -= dropped
            self.problems.append("%d unsupported cells omitted: %s" % (len(dropped), sorted(dropped)))

    def connect_tower(self):
        """tower_connect: a tower cell (floor at or above base_y) in storey k (1 = lowest) also depends on every
        tower cell in storeys 1..max(n, k - n), so both parts of the tower are joined over n storeys before
        anything higher is built, and never rise more than n storeys above the joined part."""
        tc = self.cfg.get("tower_connect")
        if not tc:
            return
        rows, n = self.cfg["rows"], tc["storeys"]
        # skip_floors: storeys left out (e.g. the hidden turbine cage on the tower roof: it rests on the top storey
        # only, which is joined already, and would otherwise wait for one more storey over the full width)
        tower = [c for c in self.cells if rows[c[1] + 1] <= tc["base_y"] and rows[c[1] + 1] not in tc.get("skip_floors", ())]
        floors = sorted({rows[c[1] + 1] for c in tower}, reverse=True)       # lowest storey first
        storey = {c: floors.index(rows[c[1] + 1]) + 1 for c in tower}
        for c in tower:
            k = storey[c]
            if k > n:
                below = {d for d in tower if storey[d] <= max(n, k - n)}
                self.deps[c] = self.deps.get(c, set()) | below

    # --- Cell properties
    def is_front(self, c):
        n = (c[0] + 1, c[1])
        return n not in self.all_cells and n not in self.keep_cells

    def cell_w(self, c):
        return abs(self.nodes[(c[0] + 1, c[1] + 1)][1][0] - self.nodes[(c[0], c[1] + 1)][1][0])

    def cell_h(self, c):
        return self.cfg["rows"][c[1] + 1] - self.cfg["rows"][c[1]]

    def is_top(self, c):
        return (c[0], c[1] - 1) not in self.all_cells

    def near_reactor(self, c):
        rows = self.cfg["rows"]
        x0, x1 = self.cell_x(c)
        cx = (x0 + x1) / 2
        cy = (rows[c[1]] + rows[c[1] + 1]) / 2
        return math.dist((cx, cy), self.cfg["reactor"]) < 120

    # --- Actions
    def _fmt(self, p):
        return "x = %.2f, y = %.2f" % (p[0], p[1])

    def chain(self, nid):
        """Chain depth of a built node: node creations since an anchor (a starting fort node, or a foundation on
        the ground, which the game places at its absolute position). The game places every other new node at
        the CURRENT position of its source node plus the planned offset (GetAdjustedNodePosition), so a lean
        anywhere in the chain is copied into the new node (test match: a stepped tower, built sideways from
        a leaning back column through chains of up to 17 nodes, ended ~100 forward and squeezed its cannon
        cells to 55-65 % of their width)."""
        return self.depth.get(nid, 0)

    def note_node(self, src_id, nid, kind):
        self.depth[nid] = 0 if kind == "found" else self.chain(src_id) + 1

    def ensure_node(self, ij, via_material="bracing"):
        """Build node ij (if necessary) from an already built neighbour: the one with the shortest chain to an
        anchor, then the node directly below (a vertical post), then the nearest."""
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
                    cand.append((d, (i + di, j + dj), (di, dj)))
        if not cand:
            return None
        if kind == "found":
            # build the foundation from above/diagonally, not sideways along the ground
            if self.cfg.get("found_from_below"):
                # from the storey below first, then diagonally from above, straight down last
                cand = [c for c in cand if c[0] <= MAX_NEW_NODE]
                if not cand:
                    return None
                cand.sort(key=lambda dc: (dc[2][1] != 1, dc[2] == (0, -1), dc[1][1] == j, dc[0]))
            else:
                cand.sort(key=lambda dc: (dc[1][1] == j, dc[0]))
        else:
            if self.cfg.get("no_build_from_found"):
                cand = [c for c in cand if self.nodes[c[1]][2] != "found"] or cand
            near = [c for c in cand if c[0] <= MAX_NEW_NODE]    # a new node at most 150 from its source
            if not near:
                return None             # the caller builds a neighbouring cell first
            cand = sorted(near, key=lambda dc: (self.chain(self.nodes[dc[1]][0]), dc[2] != (0, 1), dc[0]))
        src = self.nodes[cand[0][1]]
        e = self.split_of(cand[0][1], ij) if self.cfg.get("split_edges") else None
        if e is not None:
            # built along a split edge: through its mid node, each half in its own material
            key = self.split_mid(e)
            mats = e.get("materials", {})
            from_a = self.node_at(e["a"]) == cand[0][1]
            m_src = mats.get("a" if from_a else "b", via_material)
            m_new = mats.get("b" if from_a else "a", via_material)
            mid = self.nodes[key]
            if mid[0] not in self.built_nodes:
                self.actions.append('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "%s" },'
                                    % (src[0], self._fmt(src[1]), mid[0], self._fmt(mid[1]), m_src))
                self.built_nodes.add(mid[0])
                self.note_node(src[0], mid[0], "new")
                self.links[frozenset((src[0], mid[0]))] = m_src
            src, via_material = mid, m_new
        self.actions.append('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "%s" },'
                            % (src[0], self._fmt(src[1]), nid, self._fmt(p), via_material))
        self.built_nodes.add(nid)
        self.note_node(src[0], nid, kind)
        self.links[frozenset((src[0], nid))] = via_material
        return nid

    # a strut placed this few actions ago is probably still under construction in the game; changing its material
    # then has no effect (test match 24.10.2026: doors in front of a 20mm, planned right after their post, came only
    # with the AI's final pass 200 s later, and blocked the cannon's line of fire until then), so the action that
    # places the strut gets the final material instead of a second action that swaps it
    SWAP_WINDOW = 20

    def split_edge(self, a_ij, b_ij, material):
        """split_edges: [{"a", "b", "mid", "braces", "materials"}] (positions): the strut a-b is built in two halves
        through a node at mid, braced by struts from mid to the given (point, material) pairs, since a node held
        only by two struts in line would hinge; one device fits on each half (the game allows one device per strut).
        "materials" {"a": ..., "b": ...} gives the halves a-mid and mid-b their own material (e.g. a short door
        only where a weapon fires through, armour on the rest). Returns True if a_ij-b_ij is such an edge."""
        e = self.split_of(a_ij, b_ij)
        if e is None:
            return False
        key = self.split_mid(e)
        mats = e.get("materials", {})
        ma, mb = mats.get("a", material), mats.get("b", material)
        ka, kb = self.node_at(e["a"]), self.node_at(e["b"])
        nid = self.nodes[key][0]
        if nid not in self.built_nodes:
            src, m = (ka, ma) if self.nodes[ka][0] in self.built_nodes else (kb, mb)
            self.actions.append('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "%s" },'
                                % (self.nodes[src][0], self._fmt(self.nodes[src][1]), nid, self._fmt(self.nodes[key][1]), m))
            self.built_nodes.add(nid)
            self.note_node(self.nodes[src][0], nid, "new")
            self.links[frozenset((self.nodes[src][0], nid))] = m
        if self.nodes[ka][0] in self.built_nodes:
            self.link(ka, key, ma)
        if self.nodes[kb][0] in self.built_nodes:
            self.link(key, kb, mb)
        for q, m in e.get("braces", []):
            if self.node_at(q) and self.nodes[self.node_at(q)][0] in self.built_nodes:
                self.link(key, self.node_at(q), m)
        return True

    def split_of(self, a_ij, b_ij):
        """The split_edges entry for the edge a_ij-b_ij, or None."""
        for e in self.cfg.get("split_edges", []):
            if {self.node_at(e["a"]), self.node_at(e["b"])} == {a_ij, b_ij}:
                return e
        return None

    def split_mid(self, e):
        key = ("split",) + tuple(e["mid"])
        if key not in self.nodes:
            self.nodes[key] = (None, tuple(e["mid"]), "new")
        self.node(key)
        return key

    def link(self, a_ij, b_ij, material):
        if self.cfg.get("split_edges") and self.split_edge(a_ij, b_ij, material):
            return
        a, b = self.nodes[a_ij], self.nodes[b_ij]
        key = frozenset((a[0], b[0]))
        if self.links.get(key) == material:
            return
        if key in self.links:
            ids = re.compile(r"OriginalNodeAId = (\d+),.*OriginalNodeBId = (\d+),")
            # a module never rewrites the plan's actions (action_floor: the first action of the module)
            for k in range(len(self.actions) - 1, max(getattr(self, "action_floor", 0) - 1, len(self.actions) - 1 - self.SWAP_WINDOW), -1):
                act = self.actions[k]
                m = ids.search(act)
                if m and ("CREATE_NODE" in act or "CREATE_LINK" in act) and {int(m.group(1)), int(m.group(2))} == set(key):
                    self.actions[k] = re.sub(r'MaterialSaveName = "\w+"', 'MaterialSaveName = "%s"' % material, act)
                    self.links[key] = material
                    return
        self.actions.append('{ Type = CREATE_LINK, OriginalNodeAId = %d, PosA = {%s }, OriginalNodeBId = %d, PosB = { %s }, MaterialSaveName = "%s" },'
                            % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), material))
        self.links[key] = material

    def spans_right(self, c):
        """True if a large device extends over the right edge of c into the neighbouring cell."""
        a, b = self.devices.get(c) or "", self.devices.get((c[0] + 1, c[1])) or ""
        if self.cfg.get("large_rear_solid") and (a in LARGE or b in LARGE):
            return False            # the weapon's body stays inside its own cell (large_t)
        return bool(a and b) and (a + "+" == b or b + "+" == a)

    def prereq(self, dev):
        """Tech a device needs; maps can override PREREQ (e.g. weapon_pack: cannon <- munitions)."""
        p = self.cfg.get("prereq", {})
        return p[dev] if dev in p else PREREQ.get(dev)

    def in_turbine_row(self, c):
        """Cell in the turbine gallery storey: only background bracing inside (open for the wind)."""
        return self.cfg.get("turbine_row_open") and self.cfg["rows"][c[1] + 1] in self.turbine_floors()

    def turbine_floors(self):
        """turbine_floor_y: one floor height or a list of them (stacked galleries, filled in that order)."""
        y = self.cfg.get("turbine_floor_y")
        return [] if y is None else list(y) if isinstance(y, (list, tuple)) else [y]

    def split_cells(self):
        """split_cell: one (left x, top y) or a list of them, in the order sandbag_slots refers to them."""
        sc = self.cfg.get("split_cell")
        return [] if not sc else ([sc] if isinstance(sc[0], (int, float)) else list(sc))

    def split_index(self, c):
        return next((k for k, (x0, top) in enumerate(self.split_cells())
                     if abs(self.cell_x(c)[0] - x0) < 2 and self.cfg["rows"][c[1]] == top), None)

    def is_split(self, c):
        """Cell split at half height for two stacked sandbags (in front of a turbine row or a mortar nest)."""
        return self.split_index(c) is not None

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
                self.note_node(src[0], nid, "new")
                self.links[frozenset((src[0], nid))] = "backbracing"
            self.link(key, bot, "backbracing")
            mids.append(key)
        self.link(bl, br, "bracing")
        self.link(mids[0], mids[1], "bracing")   # background bracing cannot carry devices (SupportsDevices = false)
        self.link(tl, tr, self.edge_material(c, "top"))
        self.link(tl, mids[1], "backbracing")
        self.link(mids[0], br, "backbracing")
        self.split_slots[c] = {"mid": (mids[0], mids[1]), "floor": (bl, br)}

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
            return "door" if dev in DIRECT_WEAPONS or dev == "lane" else "armour"
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
            diag = "backbracing" if self.has_device(c) or self.devices.get((i - 1, j)) in LARGE or self.in_turbine_row(c) else "bracing"
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
                if y >= self.cfg.get("crossbrace_late_y", -1e9) or self.cell_x((i, j))[0] >= self.cfg.get("crossbrace_now_x", 1e9):
                    self.crossbrace(c, diag)
                else:
                    self.late_crossbrace.append(c)
        else:
            self.link(bl, br, "bracing")
            if self.is_front(c):
                self.link(tr, br, self.edge_material(c, "right"))
        self.built_cells.add(c)
        self.build_order.append(c)
        self.add_support_struts()
        return True

    def add_support_struts(self):
        """Extra solid struts from the map config, built as soon as both end nodes exist."""
        for pa, pb in self.cfg.get("support_struts", []):
            ia, ib = self.node_at(pa, tol=10), self.node_at(pb, tol=10)
            if ia and ib and self.nodes[ia][0] in self.built_nodes and self.nodes[ib][0] in self.built_nodes:
                self.link(ia, ib, "bracing")

    def crossbrace(self, c, diag=None):
        """Second diagonal of cell c."""
        i, j = c
        if diag is None:
            diag = "backbracing" if self.has_device(c) or self.devices.get((i - 1, j)) in LARGE or self.in_turbine_row(c) else "bracing"
        if (i + j) % 2 == 0:
            self.link((i + 1, j), (i, j + 1), diag)
        else:
            self.link((i, j), (i + 1, j + 1), diag)

    def large_t(self, c):
        """LinkT of a large weapon in cell c: from large_cells, else near the back post, its body inside the cell."""
        if c in self.large_t_at:
            return self.large_t_at[c]
        narrow = self.cfg.get("large_t_narrow")
        if narrow and self.cell_w(c) < narrow[0]:
            return narrow[1]
        return self.cfg.get("large_t", 0.4)

    def has_device(self, c):
        """A device in cell c that needs background diagonals (not the solid rear half of a large weapon)."""
        d = self.devices.get(c)
        if d is None:
            return False
        return not (self.cfg.get("large_rear_solid") and d.endswith("+") and d[:-1] in LARGE)

    def brace_below(self, c):
        """Crossbrace the cells of a large weapon (its own and the half to the left) and the cells
        below them down to the turbine row: less strain on the links it hangs on (CS_UNSTABLE)."""
        for i in (c[0], c[0] - 1):
            j = c[1]
            while (i, j) in self.built_cells and not self.in_turbine_row((i, j)) and (i, j) not in self.orig_cells:
                self.crossbrace((i, j))
                if (i, j) in self.late_crossbrace:
                    self.late_crossbrace.remove((i, j))
                j += 1

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

    def mortar_slots_cells(self):
        """mortar_slots: [(node A, node B, LinkT)] -> the cell above each slot (its strut lies on the cell's floor;
        on a split edge, a half of it)."""
        out = []
        for pa, pb, t in self.cfg.get("mortar_slots", []):
            # the grid end of the strut (the other end may be the node of a split edge)
            ia = next((k for k in (self.node_at(pa), self.node_at(pb)) if k and k[0] != "split"), None)
            out.append(next((c for c in sorted(self.all_cells) if ia in ((c[0], c[1] + 1), (c[0] + 1, c[1] + 1))
                             and self.cell_x(c)[0] <= min(pa[0], pb[0]) + 1 and self.cell_x(c)[1] >= max(pa[0], pb[0]) - 1), None))
        return out

    def weapon_strut(self, dev):
        """weapon_struts [(node A, node B, LinkT, device)]: a weapon on an explicit strut between two built nodes (grid,
        split-edge or "struts" nodes), e.g. one rising a few degrees from a post to the front post, where it ends at
        the bottom of the weapon's door (Abyss-2, like the player's 20mm and shotgun); taken in order, the upgrade
        goes on the same strut. False if dev has no such strut."""
        used = self.__dict__.setdefault("weapon_struts_used", set())
        for n, (pa, pb, t, d) in enumerate(self.cfg.get("weapon_struts", [])):
            if d != dev or n in used:
                continue
            ka, kb = self.node_at(pa, tol=5), self.node_at(pb, tol=5)
            if not ka or not kb or self.nodes[ka][0] not in self.built_nodes or self.nodes[kb][0] not in self.built_nodes:
                self.problems.append("weapon strut %d (%s): nodes not built" % (n, dev))
                return False
            a, b = self.nodes[ka], self.nodes[kb]
            self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                                % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t, dev))
            self.placed.append((dev, a[1], b[1], t, ("slot", ka, kb)))
            used.add(n)
            return True
        return False

    def weapon_slot(self, dev):
        """weapon_slots [(node A, node B, LinkT, device)]: explicit roof struts for these weapons (also a half of a
        split edge, so two devices share one cell's roof), taken in order. The cell below the strut is built first;
        its upgrade goes on the same strut. False if dev has no free slot."""
        used = self.__dict__.setdefault("weapon_slots_used", set())
        rows = self.cfg["rows"]
        for n, (pa, pb, t, d) in enumerate(self.cfg.get("weapon_slots", [])):
            if d != dev or n in used:
                continue
            x0, x1, y = min(pa[0], pb[0]), max(pa[0], pb[0]), (pa[1] + pb[1]) / 2
            # a strut of the starting fort (both ends its nodes, e.g. Abyss-3's laser on its machine-gun strut, whose
            # cell below is the reactor's), or one outside the grid: it stands already
            on_orig = all(any(math.dist(q, p) <= 5 for q in self.orig.values()) for p in (pa, pb))
            if on_orig or not any(abs(rows[c[1]] - y) < 2 and self.cell_x(c)[0] <= x0 + 1 and self.cell_x(c)[1] >= x1 - 1
                                  for c in self.all_cells):
                ka, kb = self.orig_node_at(pa), self.orig_node_at(pb)
                if ka and kb:
                    # a strut of the starting fort outside the grid (its lower front face): it stands already
                    a, b = self.nodes[ka], self.nodes[kb]
                    self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                                        % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t, dev))
                    self.placed.append((dev, a[1], b[1], t, ("slot", ka, kb)))
                    used.add(n)
                    return True
            x0, x1, y = min(pa[0], pb[0]), max(pa[0], pb[0]), (pa[1] + pb[1]) / 2
            c = next((c for c in sorted(self.all_cells) if abs(rows[c[1]] - y) < 2
                      and self.cell_x(c)[0] <= x0 + 1 and self.cell_x(c)[1] >= x1 - 1), None)
            if c is None or not self.build_cell_path(c):
                self.problems.append("weapon slot %d (%s) not reachable" % (n, dev))
                return False
            i, j = c
            self.link((i, j), (i + 1, j), "bracing")         # the roof (a split edge: both halves and the mid node)
            ka, kb = self.node_at(pa), self.node_at(pb)
            if not ka or not kb or self.nodes[ka][0] not in self.built_nodes or self.nodes[kb][0] not in self.built_nodes:
                self.problems.append("weapon slot %d (%s): strut not built" % (n, dev))
                return False
            a, b = self.nodes[ka], self.nodes[kb]
            self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                                % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t, dev))
            self.placed.append((dev, a[1], b[1], t, ("slot", ka, kb)))
            self.roof_count[c] = 99            # no turbine beside it on this roof
            self.roof_device[c] = dev
            used.add(n)
            return True
        return False

    def mortar_slot(self, dev):
        """The next free mortar_slots strut: its cell (with its floor, maybe split) is built, then the mortar."""
        n = self.mortar_slots_used = getattr(self, "mortar_slots_used", 0)
        slots = self.cfg.get("mortar_slots", [])
        if n >= len(slots):
            return False
        pa, pb, t = slots[n]
        c = self.mortar_slots_cells()[n]
        if c is None or not self.build_cell_path(c):
            self.problems.append("mortar slot %d not reachable" % n)
            return False
        ka, kb = self.node_at(pa), self.node_at(pb)
        a, b = self.nodes[ka], self.nodes[kb]
        self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                            % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t, dev))
        self.placed.append((dev, a[1], b[1], t, ("slot", ka, kb)))
        self.mortar_slots_used = n + 1
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

    def orig_node_at(self, p, tol=5):
        """A node of the starting fort outside the grid (e.g. its lower front face), registered as a built node
        under the key ("orig", id); None if there is none within tol."""
        for nid, q in self.orig.items():
            if math.dist(p, q) <= tol:
                key = ("orig", nid)
                if key not in self.nodes:
                    self.nodes[key] = (nid, q, "orig")
                    self.built_nodes.add(nid)
                return key
        return None

    # --- Choose slots
    def free_cells(self, pred):
        cells = [c for c in sorted(self.all_cells) if c not in self.devices and not self.near_reactor(c)
                 and not self.in_turbine_row(c) and pred(c)]
        return cells

    def explicit_large_cell(self):
        """large_cells: the next free cell of the list [(left x, floor y, LinkT), ...] (or None)."""
        rows = self.cfg["rows"]
        for x0, floor_y, t in self.cfg["large_cells"]:
            for c in sorted(self.cells):
                if abs(self.cell_x(c)[0] - x0) < 2 and rows[c[1] + 1] == floor_y and c not in self.devices:
                    self.large_t_at[c] = t
                    return c
        return None

    def mark_large(self, c, dev):
        """A large weapon in cell c: the half cell behind it is taken ("<dev>+"); with large_cells, the cells
        between it and the front of its storey are its fire lane ("lane": no device, background diagonals,
        door in the front wall), as in weapon_pack's ToGWM2 where the cannons stand behind open cells."""
        self.devices[(c[0] - 1, c[1])] = dev + "+"
        if self.cfg.get("large_cells"):
            i = c[0] + 1
            while (i, c[1]) in self.all_cells and (i, c[1]) not in self.devices:
                self.devices[(i, c[1])] = "lane"
                i += 1

    def choose_weapon_cell(self, dev):
        rows = self.cfg["rows"]
        if dev in LARGE and self.cfg.get("large_cells"):
            return self.explicit_large_cell()
        # weapon_cells: [(left x, floor y, device)], cells given for a weapon (also cells that are not at the front:
        # the weapon fires through the cells ahead of it, whose struts the game recesses when it is placed)
        for wc in self.cfg.get("weapon_cells", []):          # (left x, floor y, device[, LinkT])
            x0, floor_y, d = wc[:3]
            for c in sorted(self.cells):
                # a cell a build step kept for this device (slot_cells), unless its device stands there already
                if d == dev and abs(self.cell_x(c)[0] - x0) < 10 and rows[c[1] + 1] == floor_y and (
                        c not in self.devices or (self.slot_cells.get(c) == d and not any(p[4] == c for p in self.placed))):
                    if len(wc) > 3:
                        self.weapon_t_at[c] = wc[3]
                    return c
        mw = self.cfg.get("weapon_min_w", 0)
        if mw:
            wide = lambda c: self.cell_w(c) >= mw
        else:
            wide = lambda c: True
        avoid_roof = self.cfg.get("mortar_avoid_roof")
        if dev in LOBBED_WEAPONS:
            cands = self.free_cells(lambda c: self.is_top(c) and c in self.cells and wide(c) and not (avoid_roof and self.roof_device.get(c))
                                    and (not self.cfg.get("mortar_open_arc") or self.arc_open(c)))
            cands.sort(key=lambda c: (-c[0], c[1]))     # on top, as far forward as possible
        elif dev in LARGE:
            top = self.cfg.get("large_top_max", 1e9)    # large weapons only in cells whose top is this high or higher
            low = self.cfg.get("large_top_min", -1e9)   # ... and this low or lower (not in the top storey)
            cands = self.free_cells(lambda c: self.is_front(c) and c in self.cells and (c[0] - 1, c[1]) in self.all_cells
                                    and (c[0] - 1, c[1]) not in self.devices and wide(c) and low <= rows[c[1]] <= top)
            cands.sort(key=lambda c: abs(rows[c[1]] - self.cfg.get("large_y", -300)))
        else:
            high = lambda c: dev not in TALL or self.cell_h(c) >= TALL_MIN_H
            # no roof weapon in front of it on its own floor level, now or later (roof_weapons: high roofs ahead
            # stay free for them)
            top = self.variant.get("roof_weapon_max_y", 1e9)
            roofs = [r for r in self.cells if self.is_top(r) and self.cfg["rows"][r[1]] <= top]                 if self.variant.get("roof_weapons") else []
            clear = lambda c: not any(self.roof_in_line(r, c) for r in roofs)
            # weapon_avoid: cells [(left x, floor y, devices)] where these weapons were refused in test matches
            avoid = lambda c: any(abs(self.cell_x(c)[0] - x0) < 2 and rows[c[1] + 1] == fy and dev in devs
                                  for x0, fy, devs in self.cfg.get("weapon_avoid", []))
            cands = self.free_cells(lambda c: self.is_front(c) and c in self.cells and wide(c) and high(c) and clear(c)
                                    and not avoid(c))
            if dev == "machinegun":
                cands.sort(key=lambda c: (abs(rows[c[1]] - self.cfg.get("aa_y", -250)), -c[0]))   # near reactor height: anti-air
            else:
                if self.cfg.get("small_low_first"):
                    cands.sort(key=lambda c: (-rows[c[1]], -c[0]))          # keep the top storeys for large weapons
                else:
                    cands.sort(key=lambda c: (rows[c[1]], -c[0]))           # snipers preferably on top
        if not cands:
            return None
        # some randomness among the best three so that variants differ (weapon_pick_best: always the best one)
        if self.cfg.get("weapon_pick_best"):
            return cands[0]
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

    def arc_open(self, c, roof=False):
        """No other cell of the fort in the mortar arc of cell c (steeply up and forward); roof: for a mortar
        standing on c's roof instead of its floor."""
        x0, x1 = self.cell_x(c)
        y_floor = self.cfg["rows"][c[1] + (0 if roof else 1)]
        p0 = ((x0 + x1) / 2, y_floor - 20)
        dx, dy = rules.MORTAR_ARC
        for k in range(1, 27):
            q = (p0[0] + dx * k / 26, p0[1] - dy * k / 26)
            for d in self.all_cells:
                if d == c:
                    continue
                dx0, dx1 = self.cell_x(d)
                if dx0 < q[0] < dx1 and self.cfg["rows"][d[1]] < q[1] < self.cfg["rows"][d[1] + 1]:
                    return False
        return True

    def overlaps_placed(self, dev, p):
        """True if dev at point p would overlap a device already placed beside it at the same height (rules.py:
        half-widths, weapon bodies moved forward; Vanilla-5's upgrade centre beside the factory was refused)."""
        def centre(d, q):
            return q[0] + rules.BODY_SHIFT.get(d, 0)
        w = rules.SIZE.get(dev, (40, 40))[0]
        # tech the plan builds later keeps its first proven slot free (a battery took the spot beside Vanilla-5's
        # upgrade centre before it was built)
        later = {d for kind, devs in self.variant.get("plan", []) if kind == "tech" for d in devs} - self.tech_done
        reserved = [(d,) + tuple(self.tech_slots[d][0]) for d in sorted(later) if self.tech_slots.get(d)]
        for d, a, b, t, *_c in self.placed + reserved + getattr(self, "module_placed", []):
            if d in ("mine", "mine2"):
                continue
            q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            # boxes reach BOX_TOP up from their strut: a tall one (armoury, munitions plant: 170) also covers the row above
            above = lambda dd, y: y - rules.BOX_TOP.get(dd, 81)
            same_band = abs(q[1] - p[1]) < 10 or (above(dev, p[1]) < q[1] - 10 and above(d, q[1]) < p[1] - 10)
            if same_band and abs(centre(d, q) - centre(dev, p)) < w + rules.SIZE.get(d, (40, 40))[0] - 1:
                return True
        return False

    def choose_eco_cell(self, dev=None):
        ground = max(self.cfg["rows"])
        no_ground = self.cfg.get("eco_no_ground")

        def floor_mid(c):
            a, b = self.nodes[(c[0], c[1] + 1)][1], self.nodes[(c[0] + 1, c[1] + 1)][1]
            return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        cands = self.free_cells(lambda c: not self.is_front(c) and (c in self.cells or self.cfg.get("eco_orig", True))
                                and not (no_ground and self.cfg["rows"][c[1] + 1] >= ground)
                                and not (dev and self.overlaps_placed(dev, floor_mid(c))))
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
        """Free cell of the turbine gallery (floor at turbine_floor_y; a list: the first floor with room), cheapest
        to reach first."""
        min_w = self.cfg.get("turbine_min_w", 0)
        # turbine_floor_x (x0, x1): only cells within these columns (a turbine column at the back)
        fx0, fx1 = self.cfg.get("turbine_floor_x", (-1e9, 1e9))
        for y in self.turbine_floors():
            cands = [c for c in sorted(self.cells)
                     if self.cfg["rows"][c[1] + 1] == y and not self.is_front(c) and c not in self.devices
                     and self.cell_x(c)[0] >= fx0 - 1 and self.cell_x(c)[1] <= fx1 + 1
                     and self.cell_w(c) >= min_w
                     # turbine_avoid: (left x, y) where turbines were refused in test matches (the roof = the floor here)
                     and not any(abs(self.cell_x(c)[0] - x0) < 2 and ry == y for x0, ry in self.cfg.get("turbine_avoid", []))]
            cands.sort(key=lambda c: (self.unbuilt_support(c), -c[0]))
            if cands:
                return cands[0]
        return None

    def choose_turbine_roof(self):
        min_w = self.cfg.get("turbine_min_w", 0)
        top = self.cfg.get("turbine_roof_max_y", 1e9)    # only roofs this high or higher (wind)
        cands = [c for c in sorted(self.cells)
                 if self.is_top(c) and (not self.is_front(c) or top < 1e9)
                 and self.cfg["rows"][c[1]] <= top
                 and c not in self.mortar_cells
                 and self.roof_count.get(c, 0) < len(self.cfg.get("roof_turbine_t", [0.5]))
                 and self.devices.get(c) not in LOBBED_WEAPONS
                 and self.cell_w(c) >= min_w
                 # not over a large weapon (the turbine collides with it)
                 and not (min_w and (self.devices.get(c) or "").rstrip("+") in LARGE)
                 # turbine_avoid: roofs [(left x, roof y)] where turbines were refused in test matches
                 and not any(abs(self.cell_x(c)[0] - x0) < 2 and self.cfg["rows"][c[1]] == ry
                             for x0, ry in self.cfg.get("turbine_avoid", []))]
        if self.cfg.get("turbine_cheap_first"):
            # early economy: the roof that needs the fewest unbuilt cells first, then the highest
            cands.sort(key=lambda c: (self.unbuilt_support(c), self.cfg["rows"][c[1]], -c[0]))
        elif self.cfg.get("turbine_narrow_first"):
            cands.sort(key=lambda c: (self.cell_w(c) >= 95, self.cfg["rows"][c[1]], -c[0]))
        else:
            cands.sort(key=lambda c: (self.cfg["rows"][c[1]], c[0]))
        return cands[0] if cands else None

    def roof_in_line(self, r, c):
        """A device on the roof of cell r stands in the line of fire of a weapon in cell c: the roof is c's floor
        level and lies ahead of c (enemy to the right)."""
        return self.cfg["rows"][c[1] + 1] == self.cfg["rows"][r[1]] and self.cell_x(c)[1] <= self.cell_x(r)[0] + 1

    def choose_weapon_roof(self, dev=None):
        """Open roof for a roof weapon (variant roof_weapons: tall devices with nothing above them): a top cell
        without turbine, mortar or other roof device and not in the line of fire of a weapon behind it on the
        same level (mortars: with an open arc, mortar_open_arc); the highest roof first (roof_weapon_low_first:
        the lowest), there as far forward as possible."""
        weapons = [d for d, v in self.devices.items() if v in DIRECT_WEAPONS or v == "reserved"]
        top = self.variant.get("roof_weapon_max_y", 1e9)     # only roofs this high or higher
        taken = {(p[1], p[2]) for p in self.placed}           # struts that already carry a device
        cands = [c for c in sorted(self.cells)
                 if self.is_top(c) and c not in self.mortar_cells and not self.roof_count.get(c)
                 and self.cfg["rows"][c[1]] <= top
                 and (self.nodes[c][1], self.nodes[(c[0] + 1, c[1])][1]) not in taken
                 and self.devices.get(c) not in LOBBED_WEAPONS
                 and (self.devices.get(c) or "").rstrip("+") not in LARGE
                 and not any(self.roof_in_line(c, d) for d in weapons)
                 and not (dev in LOBBED_WEAPONS and self.cfg.get("mortar_open_arc") and not self.arc_open(c, roof=True))
                 # roof_weapon_cells: [(left x, roof y)], the only roofs for roof weapons (e.g. out of mortar arcs)
                 and (not self.cfg.get("roof_weapon_cells") or any(
                     abs(self.cell_x(c)[0] - x0) < 2 and self.cfg["rows"][c[1]] == ry for x0, ry in self.cfg["roof_weapon_cells"]))]
        low = -1 if self.variant.get("roof_weapon_low_first") else 1
        cands.sort(key=lambda c: (low * self.cfg["rows"][c[1]], -c[0]))
        return cands[0] if cands else None

    # --- Main flow
    def generate(self, variant):
        self.variant = variant
        self.cfg = dict(self.cfg, **variant.get("cfg", {}))     # per-variant overrides of the map config
        self.tech_slots = dict(self.cfg["tech_slots"])
        self.tech_slots.update(variant.get("tech_slots", {}))
        self.build_lattice()
        self.select_cells(variant["shape"])
        self.connect_tower()
        self.built_cells = set()
        self.build_order = []
        self.late_crossbrace = []
        self.roof_device = {}
        self.roof_count = {}           # turbines per roof cell (roof_turbine_t: their LinkT positions)
        self.split_slots = {}          # split cell -> its sandbag struts ("floor", "mid")
        self.weapon_t_at = {}          # cell -> LinkT of its weapon (weapon_cells)
        self.mines_done = 0
        self.mortar_cells = set()      # top cells reserved for mortars (no turbine on their door roof)
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
        # cells whose floor strut already carries a device of the starting fort stay free (orig_devices); the cell
        # counts as holding that device, so a weapon there gets its door and clear diagonals like a planned one
        for x0, floor_y in self.cfg.get("lane_cells", []):
            # lane_cells: [(left x, floor y)], cells a weapon behind fires through (door in front, background
            # diagonals, no device)
            for c in self.all_cells:
                if abs(self.cell_x(c)[0] - x0) < 2 and self.cfg["rows"][c[1] + 1] == floor_y:
                    self.devices[c] = "lane"
        for pa, pb, dev, *_ in self.cfg.get("orig_devices", []):
            ia, ib = self.node_at(pa), self.node_at(pb)
            if ia and ib:
                c = (min(ia[0], ib[0]), ia[1] - 1)
                if c in self.all_cells:
                    self.devices[c] = dev
        # mortar_slots and the split sandbag cell are taken before any cell is reserved
        for c in self.mortar_slots_cells():
            if c is not None:
                self.devices[c] = "mortar"
                self.mortar_cells.add(c)
        for c in self.all_cells:
            if self.is_split(c) and self.cfg.get("sandbag_slots"):
                self.devices[c] = "sandbags"
        # reserve the cells of large weapons first, so early small weapons do not take them
        self.reserved = {}
        self.large_t_at = {}           # cell -> LinkT of its large weapon (large_cells)
        if self.cfg.get("reserve_mortar"):
            skip = len(self.cfg.get("mortar_slots", []))     # the first mortars take their slots
            for step, items in variant["plan"]:
                for dev in items:
                    if dev in LOBBED_WEAPONS and step == "weapons" and skip:
                        skip -= 1
                        continue
                    if dev in LOBBED_WEAPONS and step == "weapons":
                        c = self.choose_weapon_cell(dev)
                        if c is not None:
                            self.reserved.setdefault(dev, []).append(c)
                            self.devices[c] = "reserved"
                            self.mortar_cells.add(c)
        if self.cfg.get("reserve_large"):
            for step, items in variant["plan"]:
                for dev in items:
                    if dev in LARGE and step == "weapons":
                        c = self.choose_weapon_cell(dev)
                        if c is not None:
                            self.reserved.setdefault(dev, []).append(c)
                            self.devices[c] = "reserved"
                            self.mark_large(c, dev)
        if variant.get("reserve_tall"):
            # tall front weapons (rockets) take the few storeys that are high enough before anything else, the
            # lowest first, so the high roofs stay out of their lines of fire (roof weapons)
            roof = variant.get("roof_weapons", ())
            low_first = self.cfg.get("small_low_first")
            self.cfg["small_low_first"] = True
            for step, items in variant["plan"]:
                for dev in items:
                    if dev in TALL and dev not in roof and step == "weapons":
                        c = self.choose_weapon_cell(dev)
                        if c is not None:
                            self.reserved.setdefault(dev, []).append(c)
                            self.devices[c] = "reserved"
            self.cfg["small_low_first"] = low_first
            # build their structure right away: on Abyss the lowest one (y -250..-95 above the reactor) is the way
            # up to the top of the starting fort; left for later, the turbines and mines were not reachable
            for c in sorted(c for cs in self.reserved.values() for c in cs):
                self.build_cell_path(c)
        self.modules = []
        self.module_placed = []        # devices of the modules (kept clear by the plan's eco devices)
        for si, (step, items) in enumerate(variant["plan"]):
            for dev in items:
                self.add(step, dev)
            for m in variant.get("modules", []):
                if m["after"] == si + 1:
                    self.gen_module(m)
        # finish building the remaining cells of the shape (structure + armour);
        # bottom_up: lower layers first, so the fort does not grow top-heavy
        sign = -1 if self.cfg.get("bottom_up") else 1
        for c in sorted(self.cells, key=lambda c: (sign * self.cfg["rows"][c[1]], c[0])):
            self.build_cell_path(c)
        # deferred crossbracing, bottom up
        for c in sorted(self.late_crossbrace, key=lambda c: (-self.cfg["rows"][c[1]], c[0])):
            self.crossbrace(c)
        self.finalise_woodspam()
        self.hide_box()
        self.clear_boxes()
        if self.cfg.get("clear_fire_lines"):
            self.clear_fire_lines()
        if self.cfg.get("split_doors"):
            self.split_doors()
        # in the variant's order: the order the AI goes by when several modules fire at once
        names = [m["name"] for m in variant.get("modules", [])]
        self.modules.sort(key=lambda m: names.index(m["name"]))
        self.module_requires()
        return self

    def gen_module(self, m):
        """A reactive build module (docs/ai.md): its steps are generated on the plan as it stands after m["after"]
        steps, then the plan state is restored and the plan goes on as if the module did not exist. Its devices'
        cells stay reserved, so the plan puts nothing there. Its new nodes get ids of their own (20000 + 1000 per
        module): module and plan never share an id, and the plan stays the same with or without modules (the AI may
        build the module before or after any later part of the plan; nodes at one place are snapped together by the
        game's AI). m["cfg"] / m["variant"]: overrides while the module is generated (e.g. weapon_cells, roof_weapons)."""
        keep = ("t", "cfg", "variant", "rng")
        saved = copy.deepcopy({k: v for k, v in self.__dict__.items() if k not in keep})
        saved_cfg, saved_variant = self.cfg, self.variant
        self.cfg = dict(self.cfg, **m.get("cfg", {}))
        self.variant = dict(self.variant, **m.get("variant", {}))
        self.next_id = 20000 + 1000 * len(self.modules)
        rng_state = self.rng.getstate()
        n0, p0 = len(self.actions), len(self.problems)
        self.action_floor = n0
        # the devices of earlier modules count as placed (a later module may upgrade them, trigger "after")
        self.placed = self.placed + self.module_placed
        for step, items in m["plan"]:
            for dev in items:
                self.add(step, dev)
        lines = self.actions[n0:]
        problems = ["module %s: %s" % (m["name"], pr) for pr in self.problems[p0:]]
        cells = [c for c, d in self.devices.items() if saved["devices"].get(c) != d]
        mortar_cells = self.mortar_cells - saved["mortar_cells"]
        placed = [p for p in self.placed if p not in saved["placed"] and p not in saved["module_placed"]]
        for k in [k for k in self.__dict__ if k not in keep and k not in saved]:
            delattr(self, k)
        self.__dict__.update(saved)
        self.cfg, self.variant = saved_cfg, saved_variant
        self.rng.setstate(rng_state)
        for c in cells:
            self.devices[c] = "module"
        self.mortar_cells |= mortar_cells
        self.module_placed += placed
        self.problems += problems
        tr = m["trigger"]
        self.modules.append({"name": m["name"], "types": list(tr.get("types", ())), "count": tr.get("count", 1),
                             "time": tr.get("time"), "after": tr.get("after"), "lines": lines})

    def module_requires(self):
        """Requires of each module: the last plan action it builds on (nodes, struts), and its devices' tech (a
        mortar only after the plan's workshop)."""
        plan = parse_lines(self.actions)
        for m in self.modules:
            mod = parse_lines(m["lines"])
            req = module_requires(plan, mod)
            for a in mod:
                need = self.prereq(a.get("DeviceSaveName", ""))
                if need:
                    k = next((k for k, b in enumerate(plan, 1) if b.get("DeviceSaveName") == need), None)
                    if k is None:
                        self.problems.append("module %s: %s needs %s, which the plan does not build" % (m["name"], a["DeviceSaveName"], need))
                    else:
                        req = max(req, k)
            # a plan strut in a module weapon's line of fire, built after the module, is not recessed by the game:
            # the module waits until it stands
            for _ in range(20):
                acts = plan[:req] + mod + plan[req:]
                pos, links, devices, _g = rules.build_state(acts)
                later = req
                for name, ia, ib, t, pair, kd in devices:
                    if req <= kd < req + len(mod) and ia in pos and ib in pos:
                        for b in rules.fire_blockers(links, pos, name, rules._point(pos, ia, ib, t), kd):
                            if b[3] >= req + len(mod):
                                later = max(later, b[3] - len(mod) + 1)
                if later == req:
                    break
                req = later
            m["requires"] = req
            # struts the plan builds too (only after the module's snapshot): the module then builds them without the
            # plan's later changes (hidden cage, woodspam, cleared fire lines); move its "after" past them
            plan_struts = {frozenset((tuple(a.get("PosA") or ()), tuple(a.get("NewNodePos") or a.get("PosB") or ())))
                           for a in plan if a["Type"] in ("CREATE_NODE", "CREATE_LINK")}
            dup = sum(1 for a in mod if a["Type"] in ("CREATE_NODE", "CREATE_LINK") and frozenset(
                (tuple(a.get("PosA") or ()), tuple(a.get("NewNodePos") or a.get("PosB") or ()))) in plan_struts)
            if dup:
                self.problems.append("module %s builds %d struts the plan also builds later" % (m["name"], dup))

    def with_module(self, m):
        """The plan's actions with the module inserted right after its Requires (the earliest the AI may build it)."""
        k = m["requires"]
        return self.actions[:k] + m["lines"] + self.actions[k:]

    def hide_box(self):
        """hidden_box (x0, x1, y_top, y_floor): every strut of these cells except their floor and struts carrying a
        device becomes background
        bracing, built only once. The enemy cannot see through it, and mortar shells pass through it (the built-in
        AI checks only the terrain for lobbed weapons, TargetObstructed), so mortars on the floor stay hidden."""
        boxes = self.cfg.get("hidden_box")
        if not boxes:
            return
        import re
        if not isinstance(boxes[0], (list, tuple)):
            boxes = [boxes]                # one box or a list of them
        y_floor_of = lambda a, b: next(bx[3] for bx in boxes if all(
            bx[0] - 1 <= p[0] <= bx[1] + 1 and bx[2] - 1 <= p[1] <= bx[3] + 3 for p in (a, b)))
        def inside2(a, b):
            return any(all(bx[0] - 1 <= p[0] <= bx[1] + 1 and bx[2] - 1 <= p[1] <= bx[3] + 3 for p in (a, b))
                       for bx in boxes)
        # struts that carry a device stay solid (background bracing cannot carry devices)
        # (also the platforms of the modules' devices: the plan builds them, the module only adds the device)
        carry = {frozenset((tuple(a), tuple(b))) for d, a, b, t, c in self.placed + self.module_placed if c is not None}
        seen, out = set(), []
        for line in self.actions:
            pts = [(float(x), float(y)) for x, y in re.findall(r"x = (-?[\d.]+), y = (-?[\d.]+)", line)]
            ids = re.findall(r"OriginalNode[AB]Id = (\d+)", line)
            if ("CREATE_LINK" in line or "CREATE_NODE" in line) and len(pts) >= 2:
                a, b = pts[-2], pts[-1]
                if inside2(a, b) and min(a[1], b[1]) < y_floor_of(a, b) - 3 and frozenset((a, b)) not in carry:
                    pair = frozenset(ids)
                    if pair in seen:
                        continue
                    seen.add(pair)
                    line = re.sub(r'MaterialSaveName = "\w+"', 'MaterialSaveName = "backbracing"', line)
            out.append(line)
        self.actions = out

    def clear_boxes(self):
        """clear_boxes [device, ...]: every foreground strut crossing the box of such a device (its half-width
        SIZE[0] to both sides of its strut point, BOX_TOP above it; the posts at its own strut's ends excluded) becomes
        background bracing, so a device can stand inside a block of storeys (Abyss-2's munitions plant, box 170 high,
        under the starting fort): devices stand in front of background bracing. clear_boxes_tilted: the box square to
        the device's strut and shifted by its BODY_SHIFT, as it stands on a sloping strut (Abyss-2's weapons)."""
        names = set(self.cfg.get("clear_boxes", ()))
        if not names:
            return
        import re
        pos, links, devices, _ = rules.build_state(parse_lines(self.actions))
        hit = set()
        for name, ia, ib, t, pair, kd in devices:
            if name not in names or ia not in pos or ib not in pos:
                continue
            p = rules._point(pos, ia, ib, t)
            w, top = rules.SIZE[name][0], rules.BOX_TOP[name]
            L = math.dist(pos[ia], pos[ib])
            u = ((pos[ib][0] - pos[ia][0]) / L, (pos[ib][1] - pos[ia][1]) / L)
            nrm = (u[1], -u[0])                              # square to the strut, upward (y grows downward)
            if not self.cfg.get("clear_boxes_tilted"):
                u, nrm = (1.0, 0.0), (0.0, -1.0)
            for k in range(-4, 5):
                s_ = (rules.BODY_SHIFT.get(name, 0) if self.cfg.get("clear_boxes_tilted") else 0) + (w - 2) * k / 4
                q = (p[0] + u[0] * s_, p[1] + u[1] * s_)
                rays = [((q[0] + nrm[0] * 3, q[1] + nrm[1] * 3), (q[0] + nrm[0] * top, q[1] + nrm[1] * top))]
                if self.cfg.get("clear_boxes_tilted") and k in (-4, 4):
                    # the box's top and bottom edges too: a strut clipping a corner of the tilted box crosses no ray
                    c0 = rules.BODY_SHIFT.get(name, 0) - (w - 2)
                    c1 = rules.BODY_SHIFT.get(name, 0) + (w - 2)
                    rays += [((p[0] + u[0] * c0 + nrm[0] * hh, p[1] + u[1] * c0 + nrm[1] * hh),
                              (p[0] + u[0] * c1 + nrm[0] * hh, p[1] + u[1] * c1 + nrm[1] * hh)) for hh in (3, top)]
                for m, a, b, kk, pr in [hit for r0, r1 in rays for hit in rules._blocking(links, pos, r0, r1, skip={pair})]:
                    if ia not in pr and ib not in pr:
                        hit.add(pr)
        node_re = re.compile(r"OriginalNodeAId = (\d+),.*OriginalNodeBId = (\d+),")
        out = []
        for line in self.actions:
            m = node_re.search(line)
            if m and ("CREATE_LINK" in line or "CREATE_NODE" in line) and \
                    frozenset((int(m.group(1)), int(m.group(2)))) in hit:
                line = re.sub(r'MaterialSaveName = "\w+"', 'MaterialSaveName = "backbracing"', line)
            out.append(line)
        self.actions = out

    def door_span(self, y_top, y_floor, y_hi, y_lo):
        """The shortest door on a front post from y_top down to y_floor that covers y_hi..y_lo (the shot): (door top,
        door bottom), at least DOOR_MIN long; the armour left above or below it is either none or at least
        MIN_STRUT. None if no split is shorter than the whole post."""
        best = None
        tops = [y_top] + [y_top + MIN_STRUT + 0.5 * k for k in range(int((y_hi - y_top - MIN_STRUT) / 0.5) + 1)]
        bots = [y_floor] + [y_floor - MIN_STRUT - 0.5 * k for k in range(int((y_floor - MIN_STRUT - y_lo) / 0.5) + 1)]
        for dt in tops:
            for db in bots:
                if dt <= y_hi and db >= y_lo and db - dt >= DOOR_MIN:
                    if best is None or db - dt < best[1] - best[0]:
                        best = (dt, db)
        if best is None or best == (y_top, y_floor):
            return None
        return best

    def split_doors(self):
        """split_doors: the door of a front post in front of a direct-fire weapon (DOOR_WEAPONS) is only as long
        as the shot needs: a door opens and closes at DoorSpeed 50 per second, and the player snipes into it
        while it is open. The post is rebuilt in up to three pieces (armour, door, armour) through new nodes, each
        braced with background bracing to the cell's back corners. Where the barrel is, is not certain: the
        door covers both estimates, the weapon file's RecessionBox height (BARREL_H) and rules.py's muzzle (0.6 of
        the device's height), +- 12.5 (the margin of the Vanilla-2 sniper door, its muzzle 44 behind it, which
        fired in a test match), plus ~5 degrees of aim per unit of distance beyond that. Machine guns keep their
        full doors: in this mod they only fire anti-air, at steep angles."""
        import re
        node_re = re.compile(r"OriginalNodeAId = (\d+),.*OriginalNodeBId = (\d+),")
        pts_re = re.compile(r"x = (-?[\d.]+), y = (-?[\d.]+)")
        pos, made = {}, {}                       # node id -> position, -> index of the action creating it
        for k, line in enumerate(self.actions):
            m = node_re.search(line)
            pts = [(float(a), float(b)) for a, b in pts_re.findall(line)]
            if not m or len(pts) < 2:
                continue
            a, b = int(m.group(1)), int(m.group(2))
            pos.setdefault(a, pts[0])
            if "CREATE_NODE" in line:
                pos[b] = pts[1]
                made.setdefault(b, k)
            elif "CREATE_LINK" in line:
                pos.setdefault(b, pts[1])
        # final material of every strut, and where it is first built
        first, final = {}, {}
        for k, line in enumerate(self.actions):
            m = node_re.search(line)
            if m and ("CREATE_NODE" in line or "CREATE_LINK" in line):
                pair = frozenset((int(m.group(1)), int(m.group(2))))
                first.setdefault(pair, k)
                final[pair] = re.search(r'MaterialSaveName = "(\w+)"', line).group(1)
        weapons = [(d, a, b, t) for d, a, b, t, c in self.placed if d in DOOR_WEAPONS]
        # door_posts [(x, y_top, y_floor)]: front posts split like doors although they are not doors (e.g. background
        # bracing in a hidden storey); door_rest [((x, y_top, y_floor), material)]: the material of a split post's
        # pieces above and below its door (default armour; background bracing where turbines need the wind)
        def listed(p, q, entries):
            for x0, yt, yf in entries:
                if abs(p[0] - x0) < 3 and abs(q[0] - x0) < 3 and {round(p[1]), round(q[1])} == {round(yt), round(yf)}:
                    return True
            return False
        edits = {}                                   # action index -> replacement lines; None drops it
        appended = []                                # (insert after index, line)
        for pair, mat in final.items():
            ia, ib = tuple(pair)
            pa, pb = pos[ia], pos[ib]
            if mat != "door" and not listed(pa, pb, self.cfg.get("door_posts", [])):
                continue
            if abs(pa[0] - pb[0]) > 8:
                continue                             # only (nearly) vertical front posts
            top_id, bot_id = (ia, ib) if pa[1] < pb[1] else (ib, ia)
            y_top, y_floor, x = pos[top_id][1], pos[bot_id][1], (pa[0] + pb[0]) / 2
            behind = [(d, a, b, t) for d, a, b, t in weapons if abs((a[1] + b[1]) / 2 - y_floor) < 8
                      and x - 320 < a[0] + (b[0] - a[0]) * t < x]
            if not behind:
                continue
            d, a, b, t = max(behind, key=lambda w: w[1][0] + (w[2][0] - w[1][0]) * w[3])
            muzzle = a[0] + (b[0] - a[0]) * t + BARREL_LEN[d]
            margin = 12.5 + 0.09 * max(0.0, x - muzzle - 44)
            y_strut = (a[1] + b[1]) / 2
            h_lo, h_hi = sorted((BARREL_H[d], 0.6 * rules.SIZE.get(d, (40, 40))[1]))
            span = self.door_span(y_top, y_floor, y_strut - h_hi - margin, y_strut - h_lo + margin)
            boxes = []
            for dv, da, db_, dtt, dc in self.placed:
                y0 = (da[1] + db_[1]) / 2
                dx = da[0] + (db_[0] - da[0]) * dtt
                if dv in rules.BOX_TOP and (abs(y0 - y_floor) < 8 or abs(y0 - y_top) < 8) and x - 220 < dx < x:
                    half = rules.SIZE.get(dv, (40, 40))[0] / 2
                    boxes.append((dx - half, dx + half, y0 - rules.BOX_TOP[dv], y0))
            if span is None:
                continue
            dt, db = span
            # the pieces from the top down, with their materials
            ys = [y_top] + ([dt] if dt > y_top else []) + ([db] if db < y_floor else []) + [y_floor]
            rest = next((m_ for post, m_ in self.cfg.get("door_rest", []) if listed(pa, pb, [post])), "armour")
            mats = []
            for y0, y1 in zip(ys, ys[1:]):
                mats.append("door" if y0 >= dt - 0.01 and y1 <= db + 0.01 else rest)
            ids = [top_id]
            for y in ys[1:-1]:
                ids.append(self.next_id)
                pos[self.next_id] = (x, y)
                self.next_id += 1
            ids.append(bot_id)
            k0 = first[pair]
            # build from the end that exists first: the source of a CREATE_NODE, or either end of a CREATE_LINK
            created = "CREATE_NODE" in self.actions[k0]
            src = int(node_re.search(self.actions[k0]).group(1)) if created else bot_id
            chain = list(zip(ids, ids[1:], mats))
            if src == bot_id:
                chain = [(q, p_, m_) for p_, q, m_ in reversed(chain)]
            lines = []
            for n, (p_, q, m_) in enumerate(chain):
                last = n == len(chain) - 1
                if last and not created:
                    lines.append('{ Type = CREATE_LINK, OriginalNodeAId = %d, PosA = {%s }, OriginalNodeBId = %d, PosB = { %s }, MaterialSaveName = "%s" },'
                                 % (p_, self._fmt(pos[p_]), q, self._fmt(pos[q]), m_))
                else:
                    lines.append('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "%s" },'
                                 % (p_, self._fmt(pos[p_]), q, self._fmt(pos[q]), m_))
            # braces from each new node to the cell's back corners (the nearest nodes behind at the post's ends), but
            # none through the box of a device standing in that cell: a brace through the sniper's spot made the game
            # refuse it (CS_OCCUPIED, then CS_UNSTABLE; Vanilla-3 test match 25.10.2026). A new node without any
            # brace would be a hinge in a post that carries the storeys above: then the door is not split
            braces = []
            for mid in ids[1:-1]:
                n_before = len(braces)
                for y_end in (y_top, y_floor):
                    back = [n for n, q in pos.items() if abs(q[1] - y_end) < 8 and x - 220 < q[0] < x - 60]
                    if not back:
                        continue
                    corner = max(back, key=lambda n: pos[n][0])
                    if any(_segment_hits_box(pos[mid], pos[corner], bx) for bx in boxes):
                        continue
                    braces.append((max(k0, made.get(corner, -1)), '{ Type = CREATE_LINK, OriginalNodeAId = %d, PosA = {%s }, OriginalNodeBId = %d, PosB = { %s }, MaterialSaveName = "backbracing" },'
                                   % (mid, self._fmt(pos[mid]), corner, self._fmt(pos[corner]))))
                if len(braces) == n_before:
                    braces = None
                    break
            if braces is None:
                self.problems.append("door of %s at x %.0f: not split (no brace clear of the devices)" % (d, x))
                continue
            appended.extend(braces)
            edits[k0] = lines
            for k, line in enumerate(self.actions):     # later material changes of the whole post: dropped
                m = node_re.search(line)
                if k != k0 and m and frozenset((int(m.group(1)), int(m.group(2)))) == pair and "CREATE_" in line:
                    edits[k] = None
            self.problems.append("door of %s at x %.0f: y %.1f..%.1f (%.1f of %.1f)" % (d, x, dt, db, db - dt, y_floor - y_top))
        out = []
        for k, line in enumerate(self.actions):
            if k in edits:
                out.extend(edits[k] or [])
            else:
                out.append(line)
            out.extend(l for after, l in appended if after == k)
        self.actions = out

    def clear_fire_lines(self):
        """Every strut the plan builds that would block a weapon becomes background bracing (clear_fire_lines);
        the modules' weapons count too (appended: every plan strut counts as built before them; struts built
        after one hold its module back instead, module_requires)."""
        self.actions = clear_fire_lines(self.actions, [ln for m in getattr(self, "modules", []) for ln in m["lines"]])

    def woodspams(self):
        """woodspam: one region {wall_x, layers, rows, base, material, outside} or a list of them (plan step
        "woodspam" builds all, "woodspam:<k>" region k)."""
        ws = self.cfg.get("woodspam")
        return [] if not ws else (ws if isinstance(ws, list) else [ws])

    def finalise_woodspam(self):
        for ws in self.woodspams():
            self.finalise_woodspam_region(ws)

    def finalise_woodspam_region(self, ws):
        """Give every woodspam strut the material of its storey in the finished fort (a storey may get
        its weapon after the first woodspam pass) and build each strut only once."""
        import re
        xs = {round(x) for x in ws["layers"]}
        rows = sorted(ws["rows"])
        band = {y: self.ws_band_mat(y, ws) for y in rows}
        def mat_for(ya, yb):
            lo, hi = min(ya, yb), max(ya, yb)
            if lo == hi:                                    # horizontal at a row: background if a neighbour is
                k = rows.index(round(lo)) if round(lo) in rows else -1
                mats = [band.get(round(lo))] + ([band[rows[k - 1]]] if k > 0 else [])
                return "backbracing" if "backbracing" in mats else mats[0]
            top = max([y for y in rows if y <= lo + 3] or rows[:1])     # starting-fort nodes sit a few units off
            return band[top]
        seen, out = set(), []
        for line in self.actions:
            pts = [(float(x), float(y)) for x, y in re.findall(r"x = (-?[\d.]+), y = (-?[\d.]+)", line)]
            ids = re.findall(r"OriginalNode[AB]Id = (\d+)", line)
            is_ws = ("CREATE_LINK" in line or "CREATE_NODE" in line) and len(pts) >= 2 and any(round(p[0]) in xs for p in pts[:2]) \
                and all(rows[0] - 3 <= p[1] <= rows[-1] + 3 for p in pts[:2])
            if is_ws:
                pair = frozenset(ids)
                if pair in seen:
                    continue                                # already built (maybe in the other material)
                seen.add(pair)
                line = re.sub(r'MaterialSaveName = "\w+"', 'MaterialSaveName = "%s"' % mat_for(pts[0][1], pts[1][1]), line)
            out.append(line)
        self.actions = out

    def add(self, step, dev):
        if step == "struts":
            # ("struts", [(point A, point B, material), ...]): one extra strut each (e.g. a shield in front of a roof
            # weapon, or a long brace across the starting fort); A must stand (a grid node or one of the starting
            # fort's), B is created from A if no node is there yet
            pa, pb, mat = dev
            ka = self.node_at(pa, tol=5) or self.orig_node_at(pa)
            if ka is None or self.nodes[ka][0] not in self.built_nodes:
                self.problems.append("strut from (%d,%d): node not built" % tuple(pa))
                return
            kb = self.node_at(pb, tol=5) or self.orig_node_at(pb)
            if kb is None:
                self.ws_node(("strut",) + tuple(pb), tuple(pb), ka, mat)
            elif self.nodes[kb][0] not in self.built_nodes:
                self.problems.append("strut to (%d,%d): node not built" % tuple(pb))
            else:
                self.link(ka, kb, mat)
            return
        if step == "build":
            # ("build", [(left x, floor y[, device]), ...]): a cell and the cells on its way, no device yet (a slot a
            # module fills); with a device the cell is built for it (its door, background diagonals) and the
            # device's module takes it (weapon_cells)
            rows = self.cfg["rows"]
            c = next((c for c in sorted(self.all_cells) if abs(self.cell_x(c)[0] - dev[0]) < 2 and rows[c[1] + 1] == dev[1]), None)
            if c is not None and len(dev) > 2:
                self.devices[c] = dev[2]
                self.slot_cells[c] = dev[2]
            if c is None or not self.build_cell_path(c):
                self.problems.append("cell at x %d, floor %d not built" % tuple(dev[:2]))
            return
        need = self.prereq(dev)
        if need and need not in self.tech_done and dev not in UPGRADE_OF:
            self.problems.append("%s without %s - moved forward" % (dev, need))
            self.add("tech", need)
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
                    elif c[0] == "slot":            # mortar_slots: the exact strut (maybe half a split edge)
                        na, nb = self.nodes[c[1]], self.nodes[c[2]]
                        self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                                            % (na[0], self._fmt(na[1]), nb[0], self._fmt(nb[1]), t, dev))
                        self.placed.append((dev, na[1], nb[1], t, c))
                    else:
                        self.devices[c] = dev
                        self.place_on_floor(c, dev, t)
                    return
            # a device of the starting fort (orig_devices), each upgraded once (the AI upgrades whatever stands on the strut)
            done = self.__dict__.setdefault("orig_upgraded", set())
            for k, (pa, pb, d, *lt) in enumerate(self.cfg.get("orig_devices", [])):
                ka, kb = self.node_at(pa) or self.orig_node_at(pa), self.node_at(pb) or self.orig_node_at(pb)
                if d == base and k not in done and ka and kb:
                    done.add(k)
                    na, nb = self.nodes[ka], self.nodes[kb]
                    t = lt[0] if lt else 0.5
                    self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                                        % (na[0], self._fmt(na[1]), nb[0], self._fmt(nb[1]), t, dev))
                    return
            self.problems.append("no %s to upgrade to %s" % (base, dev))
            return
        if dev.startswith("sell:"):
            return self.sell_orig(dev[5:])
        if dev == "mine":
            return self.add_mine()
        if dev == "rebrace":
            return self.rebrace()
        if dev == "turbine":
            c = self.choose_turbine_floor() if self.cfg.get("turbine_floor_y") is not None else None
            if c is not None and self.build_cell_path(c):
                # turbine gallery: a row of turbines on the floor of one open storey (like big vanilla
                # forts), so roofs stay free for mortars; turbine_floor_t: their LinkT (spacing to other devices)
                self.devices[c] = dev
                self.place_on_floor(c, dev, self.cfg.get("turbine_floor_t", 0.5))
                return
            c = self.choose_turbine_roof()
            if c is None or not self.build_cell_path(c):
                self.problems.append("no roof slot for turbine")
                return
            ts = self.cfg.get("roof_turbine_t", [0.5])
            n = self.roof_count.get(c, 0)
            self.roof_count[c] = n + 1
            self.roof_device[c] = dev
            i, j = c
            self.link((i, j), (i + 1, j), "bracing")
            self.place_on_roof(c, dev, ts[n])
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
            c = self.choose_eco_cell(dev)
            if c is None or not self.build_cell_path(c):
                self.problems.append("no room for %s" % dev)
                return
            self.devices[c] = dev
            self.place_on_floor(c, dev)
            return
        if dev == "woodspam":
            return self.add_woodspam()
        if dev.startswith("woodspam:"):
            return self.add_woodspam(int(dev[9:]))
        if dev == "sandbags":
            # sandbags at the front of the turbine row (shield the turbines, like big vanilla forts); sandbag_slots:
            # [(slot, LinkT)] in the (first) split cell, or [(split cell index, slot, LinkT)]
            slots = self.cfg.get("sandbag_slots", [])
            n = sum(1 for p in self.placed if p[0] == "sandbags")
            if n >= len(slots):
                self.problems.append("no room for sandbags")
                return
            k, slot, t = (0,) + tuple(slots[n]) if len(slots[n]) == 2 else slots[n]
            c = next((c for c in sorted(self.all_cells) if self.split_index(c) == k), None)
            if c is None or not self.build_cell_path(c):
                self.problems.append("no room for sandbags")
                return
            a, b = (self.nodes[q] for q in self.split_slots[c][slot])
            self.actions.append('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "sandbags" },'
                                % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), t))
            self.placed.append(("sandbags", a[1], b[1], t, c))
            return
        # Weapons: lobbed ones (not roof weapons) take their mortar_slots before a weapon slot (Abyss-2: the nest's
        # mortars before the tower-top slot)
        if dev in LOBBED_WEAPONS and dev not in self.variant.get("roof_weapons", ()) and self.mortar_slot(dev):
            return
        if self.weapon_strut(dev) or self.weapon_slot(dev):
            return
        roof = self.choose_weapon_roof(dev) if dev in self.variant.get("roof_weapons", ()) else None
        if roof is None and dev in LOBBED_WEAPONS and dev in self.variant.get("roof_weapons", ()):
            self.problems.append("no roof for %s" % dev)
            return
        if roof is not None:
            c = roof
            if not self.build_cell_path(c):
                self.problems.append("no roof for %s" % dev)
                return
            self.roof_count[c] = 99            # no turbine beside it on this roof
            self.roof_device[c] = dev
            i, j = c
            self.link((i, j), (i + 1, j), "bracing")
            self.place_on_roof(c, dev)
            return
        if dev in LOBBED_WEAPONS and self.mortar_slot(dev):
            return
        lst = self.reserved.get(dev)
        c = lst.pop(0) if lst else None
        if c is None:
            c = self.choose_weapon_cell(dev)
        if c is None:
            self.problems.append("no room for %s" % dev)
            return
        self.devices[c] = dev
        if dev in LARGE:
            self.mark_large(c, dev)
        if not self.build_cell_path(c):
            if self.variant.get("reserve_tall"):
                del self.devices[c]        # not reachable yet: leave the cell to a later device
            return
        # a large weapon's fire lane (the cells ahead of it, with the door in the front wall) before the weapon: built
        # later, the Vanilla-5 laser stood in an open cell for minutes and was sniped before it was finished
        # (test match 25.10.2026)
        if dev in LARGE and self.cfg.get("large_cells"):
            k = c[0] + 1
            while self.devices.get((k, c[1])) == "lane":
                self.build_cell_path((k, c[1]))
                k += 1
        # reset front/roof after the weapon choice (door instead of armour)
        i, j = c
        if self.is_front(c):
            self.link((i + 1, j), (i + 1, j + 1), self.edge_material(c, "right"))
        if dev in LOBBED_WEAPONS and self.is_top(c):
            self.link((i, j), (i + 1, j), "door")
        # sniper_t: LinkT of snipers (e.g. further back, so a split door's brace clears its box)
        t = self.weapon_t_at.get(c, self.cfg.get("sniper_t", 0.5) if dev in ("sniper", "sniper2") else 0.5)
        self.place_on_floor(c, dev, self.large_t(c) if dev in LARGE else t)
        if dev in LARGE and self.cfg.get("crossbrace_large"):
            self.brace_below(c)

    def ws_band_mat(self, y_top, ws):
        """Woodspam material in front of the wall cell whose top is y_top: background bracing in front of
        direct-fire weapons (they must shoot through it, MinFireClearance; they get a metal door instead)
        and in turbine rows (wind), foreground bracing elsewhere, where it only protects."""
        for c in self.all_cells:
            if abs(self.cell_x(c)[1] - ws["wall_x"]) < 1 and self.cfg["rows"][c[1]] == y_top:
                dev = self.devices.get(c)
                if dev in DIRECT_WEAPONS or dev in ("reserved", "lane") or self.in_turbine_row(c):
                    return "backbracing"
                return ws.get("material", "bracing")
        # no grid cell behind this band (e.g. the starting fort's prow, a keep-out zone): "outside" (default
        # background bracing), or {band top y: material}
        out = ws.get("outside", "backbracing")
        return out.get(y_top, "backbracing") if isinstance(out, dict) else out

    def ws_node(self, key, p, src_key, mat):
        """Woodspam node: created from src_key (already built) unless it exists. A node on the rock surface (within 1)
        is a foundation (Abyss-2's wall anchors from the "struts" step)."""
        if key not in self.nodes:
            self.nodes[key] = (None, p, "found" if self.t.nearest_surface(p)[1] < 1 else "new")
        nid, p, _ = self.node(key)
        if nid in self.built_nodes:
            return True
        src = self.nodes[src_key]
        if src[0] not in self.built_nodes:
            return False
        self.actions.append('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "%s" },'
                            % (src[0], self._fmt(src[1]), nid, self._fmt(p), mat))
        self.built_nodes.add(nid)
        self.note_node(src[0], nid, self.nodes[key][2])
        self.links[frozenset((src[0], nid))] = mat
        return True

    def add_woodspam(self, k=None):
        regions = self.woodspams()
        for ws in (regions if k is None else regions[k:k + 1]):
            self.add_woodspam_region(ws)

    def add_woodspam_region(self, ws):
        """Woodspam: cheap, dense wooden layers in front of the weapon column's door wall, which
        take the hits before the metal (cheap to build and repair). Layers ~40 apart (struts must be
        at least 37.5 long). Material per storey (ws_band_mat). Idempotent: a later call completes
        storeys built since and updates materials of storeys that got a weapon in the meantime."""
        wall = {y: self.node_at((ws["wall_x"], y), tol=5) or self.orig_node_at((ws["wall_x"], y), tol=5) for y in ws["rows"]}
        rows = [y for y in sorted(ws["rows"]) if wall[y] and self.nodes[wall[y]][0] in self.built_nodes]
        if not rows:
            self.problems.append("woodspam: door wall not built yet")
            return
        band = {y: self.ws_band_mat(y, ws) for y in rows}      # storey below row y (top = y)
        def row_mat(y):                                         # horizontal at row y: between two storeys
            k = rows.index(y)
            mats = [band[y]] + ([band[rows[k - 1]]] if k > 0 else [])
            return "backbracing" if "backbracing" in mats else mats[0]
        cols = [None] + list(ws["layers"])
        key = lambda x, y: wall[y] if x is None else ("ws", x, y)
        for y in rows:                       # nodes, each from its neighbour towards the wall
            for a, b in zip(cols, cols[1:]):
                if self.ws_node(key(b, y), (b, y), key(a, y), row_mat(y)):
                    self.link(key(a, y), key(b, y), row_mat(y))
        for y0, y1 in zip(rows, rows[1:]):   # posts and X-diagonals per storey
            m = band[y0]
            for a, b in zip(cols, cols[1:]):
                self.link(key(b, y0), key(b, y1), m)
                self.link(key(a, y0), key(b, y1), m)
                self.link(key(b, y0), key(a, y1), m)
        # down to the storey below (the prow's top nodes), crossed like the storeys above
        m = band[rows[-1]]
        for k, (x, base) in enumerate(zip(ws["layers"], ws.get("base", []))):
            ij = self.node_at(base, tol=5) or self.orig_node_at(base)
            if ij and self.nodes[ij][0] in self.built_nodes:
                self.link(key(x, rows[-1]), ij, m)
                self.link(key(cols[k], rows[-1]), ij, m)

    def sell_orig(self, dev):
        """Plan step "sell:<device>": sell a device of the starting fort (orig_devices) with DESTROY_DEVICE, as the
        game's Abyss-1 sells its sandbags; its cell becomes a fire lane ("lane": no device, door in front,
        background diagonals), e.g. for a weapon behind it."""
        for pa, pb, d, *_ in self.cfg.get("orig_devices", []):
            ia, ib = self.node_at(pa), self.node_at(pb)
            if d != dev or not ia or not ib:
                continue
            a, b = self.nodes[ia], self.nodes[ib]
            self.actions.append('{ Type = DESTROY_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, DeviceSaveName = "%s" },'
                                % (a[0], self._fmt(a[1]), b[0], self._fmt(b[1]), dev))
            if isinstance(ia[0], int) and isinstance(ib[0], int):      # a grid strut (not the fort's own face)
                c = (min(ia[0], ib[0]), ia[1] - 1)
                if c in self.all_cells:
                    self.devices[c] = "lane"
            return
        self.problems.append("no %s of the starting fort to sell" % dev)

    def rebrace(self):
        """rebrace_after_mine: starting-fort struts rebuilt as wood bracing (the game swaps the material and refunds
        the metal); after the first mine, or earlier as the plan step "rebrace"."""
        if getattr(self, "rebraced", False):
            return
        self.rebraced = True
        for ia, ib in self.cfg.get("rebrace_after_mine", []):
            pa, pb = self.orig[ia], self.orig[ib]
            self.actions.append('{ Type = CREATE_LINK, OriginalNodeAId = %d, PosA = {%s }, OriginalNodeBId = %d, PosB = { %s }, MaterialSaveName = "bracing" },'
                                % (ia, self._fmt(pa), ib, self._fmt(pb)))
            self.links[frozenset((ia, ib))] = "bracing"

    def add_mine(self):
        spots = self.cfg["mines"]
        while self.mines_done < len(spots):
            m = spots[self.mines_done]
            self.mines_done += 1
            ok = True
            if "chain" in m:
                prev = None
                for p in m["chain"]:
                    # a node of the starting fort off the grid counts too (Abyss-2: its wall node (-2100, 500) with the
                    # grid's row at 550)
                    ij = self.node_at(p) or self.orig_node_at(p)
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
                        self.note_node(src[0], nid, self.nodes[ij][2])
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
                if self.mines_done == 1:
                    self.rebrace()
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
                if len(pts) >= 2 and math.dist(pts[0], pts[1]) > MAX_NEW_NODE + 1:
                    errors.append("action %d: new node too far from its source (%.0f)" % (k, math.dist(pts[0], pts[1])))
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
                # long_struts [(A, B)]: struts the game allows up to its own limit (StandardMaxLinkLength 218), e.g. a
                # brace players build across two storeys of the starting fort: 218.7 between the plan's recorded node
                # positions, 217-218 in the game, where the player built it in three matches)
                long_ok = any({(round(pts[0][0]), round(pts[0][1])), (round(pts[1][0]), round(pts[1][1]))}
                              == {tuple(map(round, a)), tuple(map(round, b))} for a, b in self.cfg.get("long_struts", []))
                if L > (GAME_MAX_LINK + 1 if long_ok else MAX_LINK + 1):
                    errors.append("action %d: link too long (%.0f)" % (k, L))
                if not self.t.segment_clear(pts[0], pts[1]):
                    errors.append("action %d: link passes through rock" % k)
        for nid, p in pos.items():
            if nid >= 10000 and self.t.inside((p[0], p[1] - 3)) and self.t.inside((p[0] + 3, p[1])):
                errors.append("node %d lies in rock" % nid)
        clear = self.cfg.get("rock_clear")
        if clear:
            found = {v[0] for v in self.nodes.values() if v[2] == "found"}
            for nid, p in pos.items():
                if nid >= 10000 and nid not in found and self.t.nearest_surface(p)[1] < clear - 0.5:
                    errors.append("node %d at (%d,%d) only %.0f from the rock (rock_clear %d)"
                                  % (nid, p[0], p[1], self.t.nearest_surface(p)[1], clear))
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
                if self.prereq(d) and self.prereq(d) not in seen:
                    errors.append("%s built before %s" % (d, self.prereq(d)))
                seen.add(d)
        return errors

    def write(self, path, title):
        # header exactly like recorded plans (the AI relies on these line numbers)
        head = ("-- Fort recorded for AI replay\n"
                "CREATE_NODE = 1\nDESTROY_NODE = 2\nCREATE_LINK = 3\nDESTROY_LINK = 4\nCREATE_DEVICE = 5\nDESTROY_DEVICE = 6\n")
        tail = "-- Generated by Claude AI (tools/fortgen/gen_fort.py): %s\n" % title
        # retire: {device: seconds}, the AI sells such a weapon once it has declined to fire that long (ai.lua)
        retire = self.variant.get("retire")
        if retire:
            tail += "FortRetire = { %s }\n" % ", ".join("%s = %d" % kv for kv in sorted(retire.items()))
        with open(path, "w", encoding="ascii", newline="\r\n") as f:
            f.write(head + self.cfg["header"] + "\n\nFort =\n{\n" + "\n".join(self.actions) + "\n}\n" + tail
                    + format_modules(getattr(self, "modules", [])))


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
        if var is None:     # a removed variant: keeps the numbers (and seeds) of the ones after it
            continue
        p = Plan(cfg, terrain, base_pos, args.seed * 100 + n).generate(var)
        errors = p.validate()
        name = "fort-t1f1-%s-%d.lua" % (args.map, args.start_number + n)
        p.write(os.path.join(args.out, name), var["title"])
        rule_errors, rule_warnings = rules.check_plan(parse_lines(p.actions))
        devs = {}
        for line in p.actions:
            if "CREATE_DEVICE" in line:
                d = line.split('DeviceSaveName = "')[1].split('"')[0]
                devs[d] = devs.get(d, 0) + 1
        print("%s [%s] %d actions, devices: %s" % (name, key, len(p.actions), ", ".join("%s:%d" % kv for kv in sorted(devs.items()))))
        chains = rules.node_chains(parse_lines(p.actions), terrain)
        if chains:
            print("   node chains: max %d, avg %.1f (node creations since an anchor)" % (max(chains.values()), sum(chains.values()) / len(chains)))
        for e in errors:
            print("   ERROR:", e)
        for e in rule_errors:
            print("   RULE ERROR:", e)
        for w in rule_warnings:
            print("   RULE WARN:", w)
        for pr in p.problems:
            print("   Note:", pr)
        # each module checked inside the plan, right after its Requires (build order, nodes, the fort-building rules)
        for m in p.modules:
            plan_actions = p.actions
            p.actions = p.with_module(m)
            m_errors = p.validate()
            p.actions = plan_actions
            m_rule_errors, m_rule_warnings = rules.check_plan(parse_lines(p.with_module(m)))
            m_rule_errors = [e for e in m_rule_errors if e not in rule_errors]          # the plan's own are listed above
            m_rule_warnings = [w for w in m_rule_warnings if w not in rule_warnings]
            devs = [ln.split('DeviceSaveName = "')[1].split('"')[0] for ln in m["lines"] if "CREATE_DEVICE" in ln]
            trig = ["%s x%d" % ("/".join(m["types"]), m["count"])] if m["types"] else []
            trig += ["time %d s" % m["time"]] if m.get("time") is not None else []
            print("   module %s: %d actions (%s), trigger %s%s, requires plan action %d"
                  % (m["name"], len(m["lines"]), ", ".join(devs), " or ".join(trig),
                     " (once %s is in)" % m["after"] if m.get("after") else "", m["requires"]))
            for e in m_errors:
                print("      ERROR:", e)
            for e in m_rule_errors:
                print("      RULE ERROR:", e)
            for w in m_rule_warnings:
                print("      RULE WARN:", w)


if __name__ == "__main__":
    main()
