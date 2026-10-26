# Vanilla-6 test matches

The modular fort (current state: [maps/vanilla.md](../maps/vanilla.md#vanilla-6--modular-fort)).

## First test (26.10.2026): lost at 896 s, the AI's longest Vanilla match

Difficulty 1, forced plan (`Force`), against a player with mines, turbines, sandbags, three mortars (170-172 s),
machine guns from 192 s (up to ~12 over the match), a missile (250 s), an upgrade centre (371 s), heavy mortars
(451-454 s), an EMP missile (457 s) and a sniper (339 s, 800 s): **the player won at 896 s** (14.9 min). Log archived
as `log_20261026-101216_f3d77b96929a.txt`.

| | AI | player |
|---|---|---|
| Shots | 738: minigun 416, machine gun 212, heavy mortar 73, mortar 37 | 541: machine gun 388, mortar 104, missile 38, sniper 11 |
| Destroyed | 33: machine gun 14, sandbags 13, heavy mortar 3, mortar 1, sniper 1, turbine 1 | 27 devices, then the reactor |
| Metal avg (below 150) | 779 (13 %) | 620 (7 %) |
| Mines avg | 4.7 | 3.9 |

- Every module came at its time; none was pulled forward (the player's mortars came at 170 s, after the artillery
  module at 150 s; the missile at 250 s, after anti-air at 240 s): sniper 45 s, mortars 150/160 s, machine gun
  240 s, heavy mortars 346 s, second machine gun 433 s, AP sniper 450 s, miniguns 570 s. No `GAVE_UP`, no `SKIPPED`.
- The plan was finished at ~485 s (build index 356/355). From then on the AI sat at its storage caps (1200 metal,
  9000 energy) for six minutes and only rebuilt: heavy mortars lost six times, mortars twice, machine guns seven
  times (one capped: `REBUILD_CAP action 116 machinegun losses=4`, the starting fort's own machine gun).
- Upgrades of rebuilt weapons failed with `CS_PREQUISITENOTMET` (heavy mortar 6x, minigun 2x) while the base weapon
  was not yet rebuilt; they went through later.
- The end: from 8 min on the player's machine guns and mortars wore down the woodspam on the starting fort's lower
  front (x -2800..-2900, y 500..700) and the hidden nest (x -3100, y 0); the reactor fell at 896 s.
- Change after the test: late modules `artillery2` (two more mortars on the gallery roof, 480 s), `heavyartillery2`
  (560 s) and `frontlayer` (a third woodspam layer in front of the lower front, 600 s or when the player has six
  machine guns).
