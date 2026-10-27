# Abyss-2 – test matches

The mortar battery (rebuilt 27.10.2026, [maps/abyss.md](../maps/abyss.md)). Matches of the old Abyss-2 (mortars on the
open roofs of a wide tower, 0/3) are not listed here.

## Test 1 (27.10.2026, `log_20261026-225726_8815c524b622.txt`): lost after 8.8 min

AI on team 2 (`PLAN ... choice=forced`), difficulty 1.0. The player built a mine, turbines and four machine guns,
then weapon_pack's armoury (144 s), EMP rockets (216, 280, 465 s), flak (219, 310 s), a sniper (391 s) and upgraded
two EMP rockets to rockets (446, 448 s).

| | AI | Player |
|---|---|---|
| Shots | mortar 70, heavy mortar 22, minigun 156, machine gun 14 | machine gun 644, flak 112 (984 shrapnel), rocket 12, EMP rocket 7, sniper 10 |
| Metal avg (below 150) | 343 (28 %) | 414 (14 %) |
| Energy avg | 1462 | 3507 |
| Mines avg / max | 4.7 / 6 | 3.6 / 4 |
| Kills | flak 1, machine gun 3, turbine 2, sandbags 1 | reactor, two heavy mortars, minigun, machine gun, battery |

- **Build:** the whole plan was built, nothing given up; only first-attempt `CS_OCCUPIED` / `CS_OBSTRUCTION` (all
  placed later). Workshop 3 s, sandbags 44-46 s, **mortars 66 and 75 s** (the rush works), ledge mines 169, 201, 254 s,
  first turbines 273 and 290 s, third mortar 319 s, upgrade centre 352 s, heavy mortars 415-420 s, miniguns 421-423 s,
  plan done ~512 s.
- **Structure:** stood without sagging problems. At 295 s a hit took the nest's roof node (-1800, -125) (six background
  struts). Nothing else fell until 498 s.
- **What decided it:** the starting fort's lower front face, below the nest and directly in front of the reactor (the
  armour (-1695, 228)-(-1753, 319) and (-1695, 228)-(-1746, 112)), fell at 498-518 s after the player's rockets
  (446 s on) and the reactor's block collapsed at 525 s. The plan had no woodspam there (only in front of the nest).
- **Energy was short:** the turbines need the tower, and came after all three ledge mines (273 s); energy was at
  1061 (185 s), 318 (305 s) and 561 (365 s), each mortar shot costs 200. The player's flak (from 219 s) shot down many
  shells (984 shrapnel).

## Test 2 (27.10.2026, `log_20261026-231846_4225d23d38c1.txt`): won after 9.0 min

After the changes from test 1 (early sniper with `FortRetire = { sniper = 90 }`, upgrade centre enclosed, wood curtain
in front of the reactor wall, a turbine after each ledge mine). Same setting (difficulty 1.0, `choice=forced`,
`RETIRE-CONFIG sniper:90` logged). The player built the armoury at 31 s, nine machine guns, EMP rockets (203, 301 s)
upgraded to rockets (402, 405 s), a minigun and sandbags late.

| | AI | Player |
|---|---|---|
| Shots | minigun 299, sniper 146, mortar 59, heavy mortar 37, machine gun 14 | machine gun 273, rocket 16, EMP rocket 6, minigun 13 |
| Metal avg (below 150) | 402 (24 %) | 293 (22 %) |
| Energy avg | 1714 | 3517 |
| Mines avg / max | 4.8 / 6 | 3.4 / 4 |
| Kills | reactor, machine gun 9, turbine 5, minigun, battery, sandbags | sniper (530 s, rebuilt at 536 s) |

- **Build:** everything built, nothing given up; first-attempt `CS_OCCUPIED` / `CS_OBSTRUCTION` only. Sniper 34 s,
  mortars 67-68 s, ledge mines 152 / 231 / 260 s with turbines at 193 / 236 s (test 1: first turbine 273 s), upgrade
  centre 311 s, heavy mortars and miniguns 371-376 s, plan done ~480 s.
- **Early sniper:** 146 shots, it always found a target, so it was never retired (no `RETIRE` line; correct). The
  sell rule is still untested in a match.
- **Wood curtain:** the only struts the AI lost (14) were the curtain's, to the player's rockets at 442-527 s; it was
  rebuilt, the starting fort's front face and the reactor were not hit through it.
- **Energy** still dipped (537 at 185 s, 325 at 425 s) but averaged 1714 (test 1: 1462).

## Test 3 (27.10.2026, `log_20261027-084316_e71c178c640c.txt`): lost after 14.6 min

The late-block version (sniper at LinkT 0.4 behind a short door, munitions plant on the ledge roof beside the tower,
one 20mm in the tower behind a fire lane). The player built a sniper at 25 s, sandbags, eight machine guns, a
repair station, a buzzsaw, then armoury, EMP rockets upgraded to rockets, two flak, a mortar; their fort had a large
cross-braced block under the starting fort along the wall (workshop, upgrade centre, batteries, a minigun and rockets
in it) and an upper part anchored to the cliff at every storey (foundations at (-2163, -386), (-2178, -527),
(-2181, -673)).

| | AI | Player |
|---|---|---|
| Shots | mortar 91, heavy mortar 74, minigun 21 | machine gun 1712, rocket 96, flak 32 (384 shrapnel), minigun 39, sniper 16, buzzsaw 9 |
| Metal avg (below 150) | 301 (50 %) | 559 (4 %) |
| Energy avg | 3735 (at its 7000 cap from ~545 s) | 3754 |
| Mines avg / max | 5.1 / 6 | 4.1 / 5 |
| Kills | machine gun 6, buzzsaw, sandbags | reactor, all mortars (six losses), minigun, batteries, store, sandbags |

- **Sniper never placed:** `CS_UNSTABLE` at once, given up after 120 s (test 2, LinkT 0.7 with a full door: placed
  at 34 s). The short door's top node was braced to the cell's back corner through the sniper's spot; the generator
  checked that brace against half the sniper's width (35 instead of the half-width 70), the failure the Vanilla-3
  sniper had (a brace through its spot, refused).
- **The spine tower leaned:** its top was 40-70 off toward the abyss by ~340 s and further later (the UNSTABLE lines:
  struts at the ledge roof strained to 1.9); a machine gun, the tower-top mortar's rebuild and the munitions plant
  were refused there with `CS_UNSTABLE` (the plant at 601 s after several tries); the 20mm never came (its tech was
  not placed in time). `physics.py` had said STANDS with sag 57: the Abyss model is not validated for such towers.
- **Mortars died:** the player's machine guns (1712 shots) and rockets killed the mortars six times (586-865 s);
  metal was below 150 half the match while energy sat at its cap, so the rebuilds starved.

## Test 4 (27.10.2026, `log_20261027-091418_4e6b74f1e6f1.txt`): won after 13.7 min

The lower-block version (sniper in the block's top storey, munitions plant at the wall, 20mm in the bottom storey,
both firing through two lane cells and short doors at x -1700; the tower tied to the cliff). The player built a
sniper on the starting fort's roof (55 s), machine guns, armoury, munitions plant, a 20mm (494 s) and a cannon (596 s)
on a strut rising 3.9 degrees to the front, at LinkT 0.92 (the front end).

| | AI | Player |
|---|---|---|
| Shots | minigun 594, heavy mortar 99, mortar 71, sniper 61, AP sniper 21, 20mm 0 | machine gun 1557, sniper 11 |
| Metal avg (below 150) | 477 (32 %) | 450 (17 %) |
| Energy avg | 2322 | 5062 |
| Mines avg / max | 5.0 / 6 | 3.8 / 5 |
| Kills | reactor, 20mm, cannon, sniper, machine gun 10, turbine 3, batteries, store, upgrade centre | sniper (six times) |

- **Build:** sniper 73 s, mortars 81 / 90 s, the tower's wall anchors and the whole plan built (no `UNSTABLE`, no
  given-up weapon); munitions plant 564 s, 20mm 630 s.
- **The doors were cut too low:** the targeting ray toward the enemy rises 4-7 degrees (the player's reactor), but the
  doors were cut for a level shot from a weapon 230-330 behind them. The sniper declined 77 times with its ray on its
  own armour just above the door (y 460-466 at x -1700, the door from 457); the 20mm declined every try (ray on the
  armour above its door at y 633) and never fired.
- The player's machine guns and sniper killed the sniper six times; the mortars and miniguns won the match.

## Test 5 (27.10.2026, `log_20261027-111732_5dfa6b61f8b4.txt`): lost after 6.9 min, the AI stalled

The version with the sniper and the lower 20mm on struts rising to their door posts (lower block storeys 405..550,
550..600, 600..750) and the second 20mm at the tower's top. Plan action 29 built the lower block's wall node
(-2100, 550) straight down from the starting fort's node (-2100, 400): the 150-long strut ran through the starting
fort's wall node (-2100, 500) and was refused with `CS_OBSTRUCTION` (with row 530 that grid point had snapped onto the
node). The AI stood at that action from ~65 s to ~285 s, gave it up (`GAVE_UP action 240`), skipped the next strut,
and only then placed the sniper and the mortars (285-287 s). With three mines and no tower it lost at 6.9 min to the
player's EMP rockets and rockets.

The player stacked three EMP rockets (upgraded to rockets) up the cliff above the ledge mines, at y ~-1000, -1125 and
-1270 against the upper cliff face (x ~-2160 from y -1025 up), each on a strut falling 12-13 degrees toward the front
from a wall anchor, a short slanted door at its front end.

Fix: the grid point (-2100, 550) snaps onto the starting fort's node (`snap` 50), and the connecting cell under the
starting fort's lower front face is kept out (its floor would have run through the node (-1751, 310)). A check of the
plan for struts that pass through an existing node now finds none.

## Test 6 (27.10.2026): lost after 7.9 min

The cliff-cannon version (two cannons on the upper cliff face, the tower-top 20mm and third mortar removed; the stall of
test 5 fixed). No stall, nothing given up, but the AI reached only plan action ~163 of 256 by 425 s; the cannons, the
munitions plant and the lower 20mm never came. The player built mines, machine guns, sandbags, the armoury at 50 s,
EMP rockets (137, 223, 241 s) upgraded to rockets, two flak, a repair station.

| | AI | Player |
|---|---|---|
| Shots | machine gun 81, mortar 57, sniper 42 | machine gun 392, flak 80 (960 shrapnel), rocket 36, EMP rocket 7 |
| Metal avg (below 150) | 163 (56 %) | 391 (12 %) |
| Energy avg | 1708 (35 at 305 s) | 1604 |
| Mines avg / max | 4.1 / 6 | 3.8 / 4 |
| Kills | flak, machine gun 4, turbine | reactor, mortars (5 losses), sniper (4 losses), upgrade centre, battery |

- **Slow economy:** sniper 90 s, mortars 99 / 108 s (test 2: 67 / 68 s), ledge mines 230 / 291 / 346 s (test 2: 152 /
  231 / 260 s), first turbine 257 s: the sniper storey and the tower's cliff anchors put ~40 actions before the
  ledge mines; five mortar and four sniper rebuilds took the metal.
- **Where it fell:** the player's rockets hit the lower block's top front corner under the starting fort's lower front
  face (struts around (-1800..-1700, 318..551), from 296 s; the sniper there was killed four times) and the wood
  curtain's lower end (y ~230-325); the reactor fell at 473 s. The connecting cell under that face had been left out
  (its floor ran through a starting-fort node), so that corner was open.

## Test 7 (27.10.2026): won after 15.9 min

The version after test 6 (economy first: mortars, the tower with its cliff anchors, the ledge mines with a turbine
after each, then the sniper's storey; the corner under the reactor closed; sniper and mortar rebuilds capped on
Abyss). The player built mines, machine guns, the armoury (149 s), EMP rockets upgraded to rockets (seven in all),
flak, a repair station and many sandbags and machine guns late.

| | AI | Player |
|---|---|---|
| Shots | minigun 914, heavy mortar 88, mortar 64, 20mm 54, machine gun 35, sniper 23, AP sniper 5, cannon 2 | machine gun 1449, rocket 122, EMP rocket 14, flak 12 (144 shrapnel) |
| Metal avg (below 150) | 353 (30 %) | 452 (6 %) |
| Energy avg | 2917 | 2854 |
| Mines avg / max | 5.3 / 6 | 5.0 / 6 |
| Kills | reactor, machine gun 18, sandbags 14, turbine 4, rocket 3, battery 3, flak, repair station, armoury | minigun 3, sniper, heavy mortar, machine gun |

- **The whole plan was built**, nothing given up: mortars 65 / 74 s, ledge mines 169 / 231 / 261 s with turbines at
  198 / 240 s, sniper 295 s, upgrade centre 352 s, heavy mortars and miniguns 412-416 s, AP sniper 481 s, munitions
  plant 536 s, 20mm 665 s, cannons 787 / 872 s (each refused once with `CS_OCCUPIED` first).
- **The corner under the reactor held:** the AI lost only four weapons all match; no `REBUILD_CAP` was needed.
- **The 20mm fired 54 times** from its strut rising to the door (three tries had their ray on own armour near the
  door, y ~635). The cannons came too late to matter (2 shots).
- **First `RETIRE`:** the AP sniper was sold at 686 s after 91 s without a shot (its ray kept hitting the armour
  in front of the player's reactor), `result=-8`; the snapshots show it gone from 695 s, so -8 is the game's code for a
  sale it carries out.
