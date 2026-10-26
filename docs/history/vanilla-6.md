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

## Second test (26.10.2026): rockets and flak, lost at 615 s, probably a collapse

Difficulty 1, the first match with the late modules. The player built an armoury (27 s), two EMP rocket launchers
(129/143 s), flak (205 s, later shrapnel), machine guns, an upgrade centre (302 s), a smoke launcher (346 s), two
rocket launchers (366/367 s) and a third EMP rocket launcher (394 s): **the player won at 615 s** (10.3 min). Log
archived as `log_20261026-103639_7e8a08ff8382.txt`.

| | AI | player |
|---|---|---|
| Shots | 295: machine gun 112, minigun 84, mortar 59, heavy mortar 40 | flak/shrapnel 660, rocket 26, EMP rocket 13, smoke 36 |
| Destroyed | 7: machine gun 3, sandbags 2, rocket launcher 1, smoke launcher 1 | heavy mortar 2, machine gun 4, AP sniper, then the collapse |
| Metal avg (below 150) | 696 (12 %) | 307 (33 %) |
| Mines avg | 4.6 | 3.8 |

- The modules reacted to the rockets: the first EMP rocket launcher (129 s) triggered `antiair` at once
  (`MODULE_WAIT antiair trigger=rocketemp:1 requires=145 now=63`), but its machine gun came only at 220 s, when the
  gallery roof stood (the ~90 actions of support from the back block). The two rocket launchers pulled `antiair2`
  forward from 420 s to ~395 s. All other modules came at their times, the late ones too (mortars 480 s, heavy
  mortars 560 s, `frontlayer` 600 s); the AI did not sit at its storage caps for long.
- The end: from minute 8 the starting fort's lower front lost struts (x -2800..-2900, y 500..600). `frontlayer` built
  its third woodspam layer in front of it at 600-608 s. At 614 s the first strut to fail was one of that new layer,
  then the starting fort's armour beside it; within about a second 105 struts failed and the store, battery,
  upgrade centre, workshop and reactor were lost. In those 5 s the player fired only flak and 2 rockets: most
  likely a collapse of the damaged lower front under the extra hanging layer (not proven from the log alone). The
  module is kept for now.
- No build errors worth fixing, no `GAVE_UP`, no `SKIPPED`; `REBUILD_CAP` stopped the starting fort's machine gun
  again (action 116, 4 losses).
