# Abyss-3 – test matches

The firebeam rush (rebuilt 27.10.2026, [maps/abyss.md](../maps/abyss.md)): two firebeams firing together, below the
reactor in the lower block and above it on a cliff perch, an early sniper, the laser on the upper perch as the end game.

## Test 1 (27.10.2026, `log_20261027-214403_b2d9af068ad6.txt`): won after 9.7 min

The version built on Abyss-2 after its seventh test (economy first, the sniper's storey after the factory, perches
not hidden). AI difficulty 1.0. The player built a sniper at 19 s, sandbags, the armoury (124 s), the factory (233 s),
a firebeam (329 s), three lasers (376, 439, 508 s) and a repair station.

| | AI | Player |
|---|---|---|
| Shots | minigun 195, flaming minigun 29, sniper 10, firebeam 9 | sniper 9, firebeam 3, laser 3 |
| Metal avg (below 150) | 276 (36 %) | 549 (10 %) |
| Energy avg | 2652 (at its 5000 cap from ~245 to ~425 s) | 5303 |
| Mines avg / max | 5.1 / 6 | 5.1 / 6 |
| Kills | reactor, laser, factory, armoury, repair station, sniper, batteries 2, stores 2 | sniper (three times) |

- **Late first shot:** no weapon before the sniper at 286 s; the AI's first shot came at ~300 s. Build: workshop 3 s,
  bottom mine 18 s, the tower with its anchors, ledge mines 138 / 177 / 201 s (turbines 161 / 186 / 210 s), battery and
  store 213 / 221 s, factory 259 s (energy-bound: placed as energy reached the 5000 cap), sniper 286 s (rebuilt 356,
  401 s), firebeams 366 / 384 s (75 s to build; first firebeam shot ~475 s), upgrade centre 426 s, miniguns ~510 s.
  The match ended before the laser (plan action 222).
- **No volley:** every volley attempt failed with `ERROR volley: attempt to index a number value` (88 times): the
  cost sum started at the number 0, and the game's fire costs are resource vectors. The error was caught and the
  firebeams fired one by one (9 shots). Fixed in `ai/ai.lua` (the sum starts from the first cost); the test now uses
  vector costs.
- Many of the sniper's and the firebeams' tries ended with the ray on the player's wood wall in front of their reactor
  (`RAY_HIT_STRUCTURE:1:bracing@-1640,249`): the built-in AI declined those shots.
- **The cliff weapons were visible:** the player saw both perch weapons placed (the perch's quadrilateral had no
  diagonal, so no closed panel hid it).
- Changed after it: the sniper's storey and the sniper right after the bottom mine (action 35), before the tower; each
  perch closed into four triangles of background bracing around a node in its back part.

## Test 2 (28.10.2026, `log_20261028-130702_5288e603a252.txt`): won after 10.0 min

The version after test 1 (sniper first, perches hidden, volley fixed). AI difficulty 1.0. The player built machine
guns (24, 40 s, three more at ~438 s), sandbags, the armoury (52 s), EMP rockets (187, 200, 348 s), smoke bombs, three
rockets (427-429 s) and three miniguns (~468 s).

| | AI | Player |
|---|---|---|
| Shots | machine gun 132, minigun 52, sniper 17, flaming minigun 8, firebeam 6 | minigun 156, rocket 38, EMP rocket 10, smoke 31 |
| Metal avg (below 150) | 219 (53 %) | 483 (9 %) |
| Energy avg | 2858 | 3690 |
| Mines avg / max | 4.9 / 6 | 3.8 / 4 |
| Kills | reactor, armoury, store, batteries 2, machine guns 3 | miniguns 2, turbine, firebeam 1 (at 593 s) |

- **Early first shot:** the sniper was placed at 65 s and built at 85 s; its first shot came at ~90 s (test 1:
  ~300 s). It fired 17 times up to 175 s and killed a machine gun at 114 s.
- **The sniper was sold while it was firing:** `RETIRE sniper 17 idle=91 shots=0` at 182 s. Every sniper shot came
  from the built-in AI's own `TryFireGun` calls; the mod's round robin only saw its own tries, which all declined
  (ray on the player's armour at (-1698, 223)), so the retire clock never reset. Fixed in `ai/ai.lua`
  (`CAI_RetireShot`: a shot of a retire-type weapon resets its idle time, whoever fired it); `t_retire.lua` has a
  sniper that only the built-in AI fires.
- Build: ledge mines at 189 / 228 / 251 s, each followed by a turbine; battery and store at 267 / 275 s; factory at 304 s
  (test 1: 259 s; metal below 150 for most of the early game); firebeams placed at 405 / 411 s and built at 486 / 490 s
  (75 s to build plus waits for metal); upgrade centre at 451 s; turbines upgraded at 511-528 s, which drained energy
  to 70-306; miniguns at ~530 s. The match ended before the laser.
- **Volleys:** 16 `VOLLEY 2` lines from 505 s, but only 5 firebeam shots after that (one beam fired alone at 486 s,
  before the second was built). Several volleys came in the same second (510, 550, 560 s): the built-in group fire
  returns without firing when the leader finds no target, and retries later when doors are in the way. Two holds
  were for energy (`VOLLEY_HOLD ready=2/2 energy=0` at 530 and 549 s, after the turbine upgrades), and one
  `VOLLEY_TIMEOUT` at 581 s. The `VOLLEY` line now also logs `fired=<k>`.
- Not visible in the log: whether the perch weapons stayed hidden while they were placed.
