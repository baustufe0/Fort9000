# Vanilla-3/-4/-5 – test history

Current state: [maps/vanilla.md](../maps/vanilla.md). Vanilla-4 (cannons) was removed on 28.10.2026 (plan, its
VanillaLong conversion and the generator variant `kanone`; recover them from git history before commit "Remove Vanilla-4").
Test matches 24.10.2026: the first cannon was built and fired both times; the second, one column back (x -3300..-3200) a storey higher (floor -95, as in ToGWM2) or lower (floor 105), was refused with `CS_UNSTABLE` both times (strut stress <= 0.27). That column is the seam where the back part of the tower (built up from the back block, which tips into the reactor gap) meets the front part (on the starting fort): the back part leaned 25-30 further forward, so the cells between x -3300 and -3200 were squeezed by about a quarter; the roof turbine on that column was refused in every test too. With the second heavy weapon directly above the first (x -3200..-3100, floor -95), it was refused too, and the `STRESS` line showed why there: the engine had turned its floor and the posts beside the first cannon into background bracing, although the plan built them solid. The game turns foreground struts a device overlaps into background bracing, on which nothing can be placed: at LinkT 0.75 the cannon's body (18 in front of its mount) crosses the post at x -3100, and its box (~90 high) reaches the floor 100 above once the nodes sag unevenly.

Test match 24.10.2026: the AI's own fort collapsed at 7.8 min without enemy fire: the starting fort's prow (it hangs over the cliff) carried the front, its armour chain reached 0.97 of its breaking limit (`STRESS` top) after the first cannon (120 mass, LinkT 0.75) was placed.

Test matches 24.10.2026: both heavy weapons were built and fired in Vanilla-4 (cannons) and Vanilla-3 (20mm, 54 shots), the fort stayed stable (prow stress 0.42-0.53 instead of 0.75-0.97).

Test match the same evening: the sniper was built at once, the machine gun in the low cell too; the plan finished at 445 s with every device except the roof turbine on the seam column (refused three times, the AI gave up after 120 s).

Test match 24.10.2026 (Vanilla-3): first turbine at 161 s instead of 58 s, but the plan was finished at 475 s instead of 445 s; both 20mm cannons and three turbines were built; the sniper on the top front cell (floor -270), placed easily on the lone front column before, was refused with `CS_UNSTABLE` (strain only up to 1.02) once the whole tower stood below it, and the AI gave up on it; the lower tower storeys leaned forward less (rough `SHAPE` averages, the snapshots are noisy).

A match with both mines first (`mine, mine, turbine`) had plenty of metal but ran short of energy (200-600 instead of 1200-2300 at 40-120 s), so the first turbine was no earlier (170 s); the later devices came 12-32 s earlier and the plan was finished at 400 s instead of 475 s (the wood struts in front of the reactor held; the top sniper was refused again). Test match with the current opening: workshop at 71 s (was 238 s), first turbine 174 s, machine gun 185 s, second mine 226 s; metal was short again (50-110 at 40-240 s) while energy piled up, and the plan was finished at 430 s (both 20mm cannons placed at 402-410 s; the top sniper refused again).

Test match 25.10.2026 (Vanilla-3, against a player, aborted at 680 s): workshop 5 s, munitions plant 65 s, first 20mm placed 155 s (built 225 s), cage turbines 268 and 359 s, both cage sandbags 314-316 s, upgrade centre 414 s with store, battery and a machine gun while it built, both turbines upgraded 454-455 s, second 20mm 478 s; 126 20mm shots; energy ended at ~10,500 (two upgraded turbines are enough there), metal was short until late.

Second rush test: the 20mm was built at 220 s and reported ready; every `TryFireGun` was declined although energy (up to 9000) and metal were there; the 20mm's `alone` grouping affinity is 1, so the likely reason is no target: `FindTarget` drops targets whose ray is blocked, and in the 20mm's cell on floor 105 the background diagonal runs from (-3200,-20) down to (-3100,105), right in front of its barrel (in the old cannon cells it ran the other way, behind it). The `CREC` struts of that match showed the actual cause: the post in front of the 20mm's lane (x -2945, floor 105 to -20) was placed as wood bracing at 212 s (before the cannon was finished) and only became the planned door at 422 s, when the AI had finished the plan and its final pass corrected the material; the 20mm fired 11 s later (in the first rush test: door 332 s, first shot 343 s). A material change on a strut that is still under construction does not take effect, and the AI works through its actions faster than struts are built (5 s and more), so a door or armour planned a few actions after its strut stayed wood (in that match only 2 armour struts and no door were built before the plan was finished). `gen_fort.py` therefore gives the action that places a strut its final material when the plan changes it within `SWAP_WINDOW` (20) actions, instead of adding a second action that swaps it (8-9 actions fewer per Vanilla plan; the rush 20mm now comes after 58 struts). Test match with it (24.10.2026): munitions plant 155 s, 20mm placed 158 s, built 228 s and fired at once (first shots by 230 s, against 445-480 s with the earlier plans). Added after the 20mm rush test (24.10.2026), where the finished 20mm waited ~2 minutes before its first shot although energy and its line of fire were free.

## Notes moved from the current-state docs (condensed 25.10.2026)

- **Stepped tower and node chains** (Vanilla-4, since reverted): almost every node of the tower was built through one
  chain of 14-17 nodes up a 100-wide column at the back (x -3500, built first for the first turbine); the tower top
  was ~200 forward of its plan position after 4.6 minutes, almost without enemy fire. A build-only test with `SHAPE`
  lines: the lean grew only while the tower was being built (minutes 1-3: rows above y=205 shifted +17 per storey,
  every node of a row by the same amount) and then stayed constant; nodes at row 205 were placed ~23 forward of the
  nodes below them because they were built sideways from the leaning column; the cannon cells' back edge (61-79
  forward) and front edge (+5) squeezed the 155-wide cells to 85-100, floor beams locked in at 42-55 % of their length,
  and neither cannon could be placed. Three test matches in all: with long chains the fort collapsed at 8.5 min; with
  short chains the cannon cells kept their shape (sag 14-24), but both cannons and a sniper in the top cell were still
  refused at strut stress 0.001-0.05. Short node chains then brought Vanilla from max 16-17 / avg 6.4-7.9 to max 10 /
  avg 3.6-3.8.
- **Heavy weapon on another weapon cell** (Vanilla-3): the 20mm in the top storey sagged 24-38 (most stretched link the
  background diagonal of the 20mm cell below); one storey lower it was placed and fired 63 shots; in a second match the
  20mm one storey lower, again directly on the other 20mm's cell, failed the same way under fire (sag 38-49, moving).
- **First 20mm rush test** (24.10.2026): workshop 65 s, munitions plant placed at once and built at 155 s, the 20mm
  placed 158 s and built 228 s, as modelled, but first shot only at ~343 s: from 235 s the fire control found it not
  available or not ready although energy and the line of fire were free (the wood post in front of it, see above).
- Vanilla-3 then had three roof turbines on the plain tower roof (`turbine_avoid` on the seam column), enough for the
  munitions plant and both heavy weapons; the cage (25.10.2026) has two, upgraded.

## Vanilla-5, first test (25.10.2026)

Against a player (difficulty 1; the player had 6 mines after 79 s, about 10 turbines, an armoury, an upgrade centre, a
factory at 163 s, lasers at 374 and 438 s, firebeams at 427 and 545 s): **the player won at 629 s**. The AI's build ran
as planned: workshop 3 s, battery 18 s, factory 80 s, store 118 s, mine 141 s, laser placed 219 s (built 339 s),
machine gun 341 s, cage turbines 369 and 427 s, sandbags 410-414 s, sniper 459 s. Metal averaged 402 (below 150 in 44 %
of the snapshots; player 511), energy 5,820.

- **The laser never fired.** Ten tries from 340 s on, all `FIRETRY laser ... fired=0 ray=RAY_HIT_STRUCTURE:2:bracing@3086,79`:
  the ray hit our own post 111-114 (x -3100, floor 105 to -20, foreground bracing since 157 s), 50.4 ahead of the
  laser's centre. The laser file's `RecessionBox` (`Size {200, 25}`, `Offset {-230, -60}`) covers 130-330 ahead and
  its body (`SelectionWidth` 50, centred) reaches 50, so the post was never recessed. `rules.py` had assumed the box
  ran from the weapon to 200 and passed the plan. Vanilla-3's 20mm in the same cell fired because its body (90 + 18
  forward) overlapped that post.
- **The upgrade centre was refused** on the munitions slot (action 354: `CS_OCCUPIED`, then `CS_UNSTABLE`; the
  `UNSTABLE` sag values are unusable in team-2 matches). The AI then waited on the turbine upgrades; from ~545 s it
  sat at 1500 metal / 11,000 energy.
- **The end:** the player fired the laser and the firebeam once each, together, at ~626 s: the starting fort's lower
  front strut 69-71 first, then woodspam region 1 and the door 64-68; 62 struts, the workshop, factory, batteries,
  store and the reactor within 4 s. The AI destroyed nothing; its sniper fired 28 times.
- Why the upgrade centre was refused: not the mine at x -3412 below the slot (in three Vanilla-3 matches the munitions
  plant was placed on the same slot after that mine), but the factory on the neighbouring strut: both are 90 to each
  side, 155 apart. `rules.py` had treated the widths as full widths. The upgrade centre now stands one strut further
  back (x -3500..-3400), and the generator keeps batteries and stores clear of it.
- Fix: the laser's front post is now background bracing (`rules.py` models the recession boxes and bodies from the
  weapon files; the generator clears such struts).

## Vanilla-5, second and third test (25.10.2026): both fixes confirmed

Two matches in one log: in the first the player's own fort collapsed at 2.2 min (`RESULT w=2`, no AI weapon placed
yet; does not count). The player restarted: the game logs `RevertMap Vanilla` and `Restoring
replay key frame at physics frame 2`, rewinds the game (the AI's own state included, its `END` counts only the second
match) but keeps the recorder's state, so the recorder wrote no new `START` and, having seen `RESULT`, no more snapshots
(only the final one). `summary.py` and `train.py` saw one match; they now split at `RevertMap`, the recorder writes
`START restart=1`, and the collapsed match is in `EXCLUDED` (train.py). In the second match the AI won at 10.6 min;
the player built mines, turbines, sandbags, a store and repair stations and fired no shot.

- **Laser:** placed 210 s, then every `FIRETRY` ray reached the enemy (`RAY_HIT_STRUCTURE:1:...`) instead of our own
  post; 7 laser shots, limited by energy (a beam 5000; energy down to 145-550 between shots).
- **Upgrade centre** at x -3500..-3400: one first-try `CS_OCCUPIED`, placed at 470 s; then both upgraded turbines
  (531 s), both miniguns (533-538 s), the AP sniper (543 s) and both upgraded mines (581-603 s) - the late game ran
  through (build index 384/422 at 600 s instead of stalling at 359).
- Other shots: minigun 182, sniper 17, AP sniper 9; no AI device lost.

## Vanilla-5, fourth test (25.10.2026): the laser stood unprotected

Against a player with a sniper (from 132 s), missiles, a buzzsaw and a mortar; the player's own fort collapsed at
5.2 min (`RESULT w=2`; excluded from training). The laser was placed at 219 s in its cell (x -3200..-3100, floor 105)
with nothing in front of it: its fire lane, the cell ahead with the door in the front wall (x -2945), came only at plan
action 166, 100 actions after the laser. The player's sniper shot into the open cell (7 sniper shots), the laser cell's
struts broke at 283 s and the laser was destroyed at 292 s, before it was finished (339 s); it never fired.

Fix: the generator builds a large weapon's fire-lane cells (door and armour in the front wall, background diagonals)
right before the weapon. Vanilla-5's lane now comes at actions 63-68 and the laser at 70 (was 63); Vanilla-3's 20mm
cannons get their lanes first the same way (same struts and devices, only the order changed).

## Vanilla-5, fifth test (25.10.2026): rockets, the laser lost 3 s after it was finished

The first match with the lane built first. Against a player with an armoury (65 s), two EMP rockets (128/152 s,
upgraded to rockets at 295 s), two flak upgraded to shotguns and an upgrade centre: **the player won at 449 s**
(rockets 32, EMP rockets 8, shotgun 120, flak 20). The AI's build: workshop 3 s, battery 18 s, factory 77 s, store
114 s, mine 137 s, laser placed 231 s and finished 371 s; then only three machine guns (386-443 s). Metal averaged 186
(below 150 in 63 % of the snapshots), energy fell to 0 several times; the build index stood at 290 from 365 s on.

- The laser fired no shot: one try at 371 s (`fired=0`, the ray reached the player's fort), then at 374 s a rocket
  volley broke its own floor strut (130-132) and the struts around its front node, and the laser and the machine gun
  beside it were lost together. Rockets come in from above, so the lane's door does not protect against them.
- Anti-air: only the starting machine gun until 386 s, while EMP rockets fired from 210 s and rockets from 335 s.
- The end: 113 struts in all; the reactor, workshop, batteries and stores at 449 s.
- The AI destroyed nothing. Vanilla-5 has now been played four times against an active player and its laser has
  fired in none of them (the one match with 7 laser shots was the one where the player did not fight).

Rework after the fifth test: all three free mine sites and the anti-air machine gun (on the starting fort's prow roof
strut) now come before the laser; the laser moves from action 70 to 78. On the lane's roof, where the generator first
put that machine gun, it would have pulled ~70 tower struts in front of the laser.

## Vanilla-5, sixth test (25.10.2026): mortars

The first match with mines and anti-air before the laser (difficulty 1). The player built sandbags, three mortars
(157-160 s), an upgrade centre, missiles and three heavy mortars (294-299 s) and a sniper: **the player won at 480 s**
(mortar 18, heavy mortar 45, machine gun 7, sniper 4, missile 1 shots) and lost nothing. The AI's build ran as
planned: mines 141/164/183 s, anti-air machine gun 201 s, laser 294 s.

- The laser fired once. The machine gun was destroyed and rebuilt ten times (201-449 s); metal averaged 187 (below 150
  in 57 % of the snapshots), so the plan never got past the laser's surroundings (build index 249/423 at 425 s).
- The AI had no answer to mortars: no mortars of its own, no armour on top. The mortars stood 2½ minutes before they
  did the damage.
- Conclusion: a fixed plan loses to whichever weapon the player picks against it. Next step is reactive build
  modules (`.dev/docs/ai.md`) and a rebuild cap per device.

## Vanilla-5 replaced (26.10.2026)

The laser rush is gone: a laser took about five minutes on Vanilla and the plan lost all four matches against an
active player. `fort-t1f1-Vanilla-5.lua` is now a rocket rush (EMP rockets, smoke, flak on Vanilla-2's low fort;
[maps/vanilla.md](../maps/vanilla.md#vanilla-5--rocket-rush)). Its tests continue below.

## Vanilla-5 rockets, first test (26.10.2026): no weapon built, lost at 394 s

The layout with a third storey on the prow (EMP rocket 1 in the nest, rocket 2 in that storey, smoke on top) and the
armoury on the starting fort's workshop slot. Difficulty 1, against a player with machine guns (108-182 s), an armoury
(139 s), an upgrade centre (200 s), EMP rockets (235/282 s, upgraded to rockets 288/318 s) and flak (320 s):
**the player won at 394 s** after firing only 61 shots (rocket 8, flak/shrapnel 52, EMP rocket 1). Log archived as
`log_20261026-121537_ff55787d592a.txt`.

- The armoury was refused (action 118: `CS_UNSTABLE`, the strut behind the slot, N66-N70, strained to 1.002, then
  `CS_OCCUPIED`) and given up after 120 s. Without it every EMP rocket, the smoke launcher and the flak failed with
  `CS_PREQUISITENOTMET` and were given up; the AI fired 21 machine-gun shots in the whole match.
- The front stack (three storeys, 360 high, on the starting fort's front posts; the gallery behind it only from plan
  action ~100) swayed: its top nodes sank 30-40 (Vanilla-6's highest 20-33).
- The end: two volleys of 4 rockets (365 s, 390 s) broke the starting fort's ground level (x -2900..-3100, y 700) and
  the prow woodspam; at 394 s the fort fell with the reactor. No strut had fallen before.
- Changes: the armoury on the munitions slot in the back block; two 130-high storeys over the starting fort instead
  of three (rocket 1 on the starting fort's roof beam, rocket 2 in the nest, smoke on the nest roof).

## Vanilla-5 rockets, second test (26.10.2026): rockets fired, energy starved, lost at 486 s

The two-storey layout (rocket 1 on the starting fort's roof beam, rocket 2 in the nest, smoke on the nest roof, armoury
on the munitions slot). Difficulty 1, against a player with machine guns (97-202 s), a repair station (180 s), a sniper
(227 s), a missile (278 s), three mortars (299-301 s), an upgrade centre (341 s) and heavy mortars (414-416 s): **the
player won at 486 s** (8.1 min). Log archived as `log_20261026-123716_b43a1618425c.txt`.

| | AI | player |
|---|---|---|
| Shots | 76: smoke 43, EMP rocket 17, machine gun 16 | 359: machine gun 287, missile 28, mortar 36, sniper 8 |
| Destroyed | 1 machine gun | smoke launcher 5x, EMP rocket 2, machine gun 3, then the reactor |
| Metal avg (below 150) | 516 (18 %) | 523 (15 %) |
| Energy avg | 1251 | 3789 |

- The armoury stood at 20 s on the munitions slot, the EMP rockets at 80/84 s, the smoke launcher at 92 s. The rockets
  fired 17 times; twice `SMOKE_TIMEOUT` (fired without smoke after 30 s).
- Energy was the bottleneck: below 900 from 90 to 330 s (the first turbine only at 293 s), while metal sat at its cap
  (900) from 150 s. The build stood at index 157 for 60 s (a mine site `CS_OCCUPIED`, skipped after 90 s) and around
  200-209 from 245 to 425 s.
- The smoke launcher on the open nest roof was destroyed at 255, 318, 371, 400 and 448 s and rebuilt each time; the
  EMP rockets were lost at 374/382 s, after the player's mortars came up, and not rebuilt (`CS_OCCUPIED`,
  `CS_INVALIDNODES`: their structure was damaged).
- The rockets' lanes with their doors were only built in the plan's final pass, so the rockets stood without doors.
- Changes: the lanes and doors right after the rockets, the first turbine next, the smoke launcher behind an armour
  shield, `RebuildCap` for smoke launchers (3).

## Vanilla-5 rockets, third test (26.10.2026): the front stack fell to heavy mortars, lost at 373 s

The layout with the doors and the first turbine right after the rockets, the smoke shield and the long brace across the
starting fort. Difficulty 1, against a player with sandbags, an upgrade centre (148 s), machine guns (166-282 s), three
mortars (232-234 s, heavy mortars 265-267 s), a missile, a sniper (254 s) and an EMP missile (307 s): **the player won
at 373 s** (6.2 min) after only 30 shots (heavy mortar 18, machine gun 7, sniper 5). Log archived as
`log_20261026-163229_aa1093caae21.txt`.

- Built: armoury 20 s, EMP rockets 80/84 s, the long brace at 91 s (216.6 long; the first try at ~37 s was refused
  with `CS_NODESTOOFAR`, the retry stood), turbine 158 s (293 s in the second test), smoke 172 s, mines 198/218 s,
  upgrade centre 254 s, rockets 314/315 s. The AI fired 53 times: smoke 45, EMP rocket 6, rocket 2.
- Metal was now short (below 150 in 35 % of the snapshots, `econ=poor` from 105 to 225 s): the turbine's ~50 actions of
  support came before the second and third mines. Energy was fine (avg 2509).
- The end: at 336-354 s about 15 heavy mortar shots brought down the deck and nest over the starting fort (the
  rockets' cells, the prow lanes with their doors, the hidden nest); their nodes stood ~28 forward of the plan (x -2917
  instead of -2945, -2819 instead of -2845) and 10-12 lower. The reactor below was lost at 373 s. The rockets were
  lost at 335/344 s.

## Vanilla-5 rockets, fourth test (26.10.2026): flak early, lost at 587 s, nothing destroyed

The layout with the flak on the nest roof behind a 65-high shield, the smoke launcher on its own storey and the flak /
smoke fire rules. Difficulty 1, against a player with a workshop (58 s), an upgrade centre (97 s), machine guns (89-303 s,
later miniguns), a mortar (146 s, three more 259-269 s, heavy mortars 369-371 s), missiles (213/320 s), a sniper (279 s)
and a buzzsaw (325 s): **the player won at 587 s** (9.8 min, the rocket plan's longest match). Log archived as
`log_20261026-170302_e3ed91a30460.txt`.

| | AI | player |
|---|---|---|
| Shots | 264: machine gun 140, flak 84 (12 + 72 shrapnel), smoke 24, rocket 16 | 313: machine gun 145, minigun 78, heavy mortar 46, missile 20, mortar 10, sniper 8, buzzsaw 6 |
| Destroyed | nothing | flak 2x, smoke launcher, rockets 2x, machine guns 3, then the reactor |
| Metal avg (below 150) | 344 (39 %) | 603 (6 %) |

- Built: armoury 20 s, EMP rockets 80/84 s, flak 129 s, turbine 179 s, mines 208/224 s, upgrade centre 258 s, rockets
  318/319 s, smoke 360 s (its storey after the gallery), machine gun 394 s.
- `FLAK_HOLD on threats=mortar:1` when the player's first mortar came, later `on threats=missile:1`; `SMOKE_WAIT energy
  rockets=2` once. The rockets fired 16 times and destroyed nothing.
- The player sniped the flak above its 65-high shield (lost 382 s and 427 s). The deck and nest front fell from minute
  7 (x -2900..-3000, y 0..200), the starting fort's lower front in minute 9; the reactor at 587 s.
- Metal stayed short (39 % of the snapshots below 150).
- Change: the flak's shield is a full-height door (130 high).

## Vanilla-3 and -5 in a 2v2 (28.10.2026): the AP sniper, lost at 540 s

- Vanilla 2v2 against two players, difficulty 1: Vanilla-3 (team 102) and Vanilla-5 (team 202). The players won
  at 9.0 min.
- The players fired 15 AP-sniper shots; the AI lost 8 EMP rockets, 2 flak, 3 machine guns and a 20mm. The AP sniper
  goes through one door (`PenetrationDamage` 600 against 400 HP).
- AI metal below 150 in 56 % of the snapshots (average 213; players 607).
- Change: `door_layers` 2 for Vanilla-3 (both 20mm and the sniper; outer doors tied into a column, `physics.py` peak
  0.80, before 0.92) and Vanilla-5's lower rocket (peak 0.97, before 0.94); the nest rocket keeps one door (its layer
  toppled the fort in `physics.py`).
