# Vanilla-7 history

Vanilla-7 is a player's fort: first recorded (tests 1-2), then generated from its ideas
(variant `frame` of `gen_fort.py`). **Removed on 28.10.2026** (plan, its VanillaLong conversion and the generator
variant; recover them from git history before commit "Remove Vanilla-7").

## Source match (26.10.2026): the player against Vanilla-5

The player (side 1) against Vanilla-5 (forced), won by the player at 1283 s (frame 32080). The player fired almost
nothing until ~870 s and built for most of the match; Vanilla-5's rockets destroyed five turbines and three sandbags
(`END ... kills=sandbags:3,turbine:5`) and lost its reactor.

- **Build:** a mine at once; a background-bracing frame on the starting fort; six mines by ~75 s; armoury 142 s, upgrade
  centre 178 s, munitions plant 236 s, mines upgraded from 230 s; cannons built at 378, 441, 595, 644, 1067, 1099,
  1250 s (eight at the end); howitzer 728 s, sniper 744 s, factory 878 s, AP sniper 937 s, flak 949 s, firebeams 965,
  1006, 1018 s, laser 1127 s, workshop 1233 s; at the end 13 batteries and 36,800 energy.
- **Shots (whole match):** cannon ~12, firebeam ~10, flak 16 with ~120 shrapnel, AP sniper 4-5, howitzer 2, laser 2.
  The cannon stack barely fired: `rules.py` finds a foreground post or X-brace of the column in front of the tower in
  every cannon's line of fire (Vanilla-7 has them as background bracing).
- **The fort sagged** while it grew: starting-fort roof nodes moved ~65 back, the top of the cannon tower ~150, so later
  `LINK` positions are up to ~150 off the positions the parts were built at (`rec_fort.py` now places each new node by
  its offset at build time).
- **Devices on background bracing:** the player placed ~40 devices on background-bracing struts; the game accepted
  them and logged no material swap. The game's own plans do the same 937 times.
- **Foundations** were built 181-212 away from their source node (more than the 150 for a node in the air).
- Recorded with `py .dev/tools/fortgen/rec_fort.py --map Vanilla --side 1 --clear-fire --out fortplans/Vanilla/fort-t1f1-Vanilla-7.lua`
  from this match's log, archived as `.dev/tools/logs/log_20261026-195816_6da5a70e7e8c.txt` (`--log`).

## Test 1 (26.10.2026): first version (816 actions)

The player gave up at 306 s: the AI had built no weapon. It placed the starting-fort actions and ~60 plan actions in
150 s (energy 188-337 until ~150 s: six mines and no turbine), then hung on one action for 90 s until the safety
valve skipped it (`SKIPPED action 180 type=1 backbracing after 90s`); metal and energy sat at their caps (900/5000)
from ~200 s. `BUILD_ERROR`: two mine sites and the armoury and upgrade centre `CS_OCCUPIED` once (all built later).

Causes, both in `rec_fort.py`: (1) nodes the player removed (`UNNODE` without `UNLINK` for their struts) stayed in the
plan, three nodes within 15 of each other (actions 56/57/59), so the AI snapped them together and the next strut
could not be built; (2) the opening turbines, which Vanilla-5's rockets destroyed and the player rebuilt several
times, came at their last rebuild (~action 220), so the opening starved of energy. Fixed (removed nodes take their
struts along; enemy losses stay in the plan; a device rebuilt in place is built once; see
[recorder-training.md](../recorder-training.md)); the plan now has 781 actions, turbines at actions 7-8, no `ERROR`.

## Test 2 (26.10.2026): fixed recording (781 actions)

Lost at 479 s to its own fort: the player built nothing and fired no shot. The opening worked (two turbines at ~20 s,
six mines, armoury, upgrade centre, munitions plant; no long stall), but:
- ~15 struts refused with `CS_NODESTOOFAR` (from ~120 s on: plan actions 60, 66, 160, 181, ...): all were 210-217 long
  when the player built them, the limit is 218, and the AI's fort deforms a little differently (other timing and
  loads); each missing diagonal let the frame bend further. `SHAPE` at 420 s: nodes up to ~210 off their planned
  positions (the player's fort: ~65-150).
- The first cannon (plan action 129) `CS_UNSTABLE` (strain 0.80..1.28) and given up; one cannon built (~390 s), never
  fired (`FIREFAIL_BUILDING`). Turbines `CS_OBSTRUCTION`/`CS_OCCUPIED` on the bent frame; at ~275 s 17 struts broke
  (`rebuild=63`).
- ~460-470 s: 84 struts lost, turbines, stores, batteries and the reactor destroyed (collapse).

Lesson: a recorded fort built at the limits of the game (16 struts of 210-217 of 218) cannot be replayed: it needs
margin; see [maps/vanilla.md](../maps/vanilla.md#open-problems).

## Generated version (26.10.2026)

After test 2 the plan is generated with `gen_fort.py` (variant `frame`, 291 actions, struts at most 199) from the
player's ideas: armoury instead of workshop, a turbine column of background bracing at the back, three cannons stacked
behind clear lanes, two firebeams low at the front, flak. Not yet tested.
