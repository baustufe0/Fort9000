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
