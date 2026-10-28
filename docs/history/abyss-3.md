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
