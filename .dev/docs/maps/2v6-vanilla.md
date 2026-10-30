# 2v6 Vanilla (clean)

Workshop map 2927068191 (`workshop/content/410900/2927068191/2v6 Vanilla clean.*`). Evaluated 30.10.2026: can the
[Vanilla](vanilla.md) plans run here unchanged? Analysis from the map's `.spr` / `.fwe` (`spr.py`, `fwe.py`); not yet
tested in a match.

## Map

- `FortGroups`: TeamFort(1, 1-2), TeamFort(2, 1-6), `ai/forts/vanilla/mid`, `ai/forts/vanilla/long`.
  `FortOrder` team 2: 3, 4, 2, 5, 1, 6. `RequiresHighSeas = true`.
- Team 1 (left): 2 forts, anchors (-4100, -300) and (-5100, -1600). Team 2 (right): **6** forts on a staircase,
  anchors (3200, 1100), (4100, 100), (5000, -900), (5900, -1900), (6800, -3000), (7700, -4000): each step 900 back
  and 1000 higher. Anchor = the Vanilla plan frame's (-3200, 700) (left rear foundation node, team 1 orientation).
- Gravity 981 like Vanilla.

## Same as Vanilla

- All 8 starting forts are the Vanilla starting fort node for node (0.0 deviation, team 2 mirrored), with the same
  devices (reactor, store, battery, machine gun, 2 mines at the same places).
- The fort rock: 700 wide (plan frame dx -400..+300), foundation edge on top; the free mine sites dx -340, -212,
  +171 are on it.
- Plan swap: `GetMapFilename` gives no known map, so the AI falls back to the FortPos + action-count signature of the
  game's mid/long plan; both `Vanilla` and `VanillaLong` are registered, so either choice is swapped and shifted.

## Different

- **Behind the fort** (team 2): a rock wall from the back edge (dx -400..-500) up to dy -1000, the cliff of the next
  step. Vanilla has a low slope there (dy -26 at dx -619). The plans' back column at dx -400 (dy 0..-495) stays clear
  of it (~40-100); it is cover, not an obstacle.
- **In front**: rock slopes down from (300, 0) to (500, 100) instead of Vanilla's cliff; the prow nodes (dx 388-508,
  dy 0) hang 44-100 above rock instead of over a drop.
- **Above**: the next fort up stands at dx -900, dy -1000. Its prow reaches dx -392, dy -1000..-1098 in the lower
  fort's frame. Vanilla-2/-5/-6 stay below dy -885; Vanilla-3's top (dx -200, dy -1200) reaches into the upper fort's
  lowest firing storey.
- **Distance**: 7000-12500 horizontally to the enemy forts (Vanilla ~6000), 1400 lower to 3700 higher.
  The mortar (and heavy mortar, same `weapons/mortar.lua`: speed 1550-2750, angle 45-85°, ~7700 on the flat) depends
  on height: downhill it reaches far, uphill little (ballistics without drag, 30-57 target points per pair):
  - From team 1's front fort T1-A (a mortar at plan y 81, as Michael built it): all of T2-1, 2/3 of T2-2, nothing
    higher. Confirmed in the game: his mortar fired at the AI forts (30.10.2026; one shot logged, no hit recorded).
  - From T2-1..T2-4 a mortar high in the fort reaches T1-A's front: at plan y -185 (the cage roof) up to plan x -3100
    (T2-1) / -3250 (T2-2) / -3150 (T2-3) / -2950 (T2-4), i.e. the prow and the reactor (x -3040); at y 75 only the
    prow. T2-5, T2-6 reach nothing, no AI fort reaches T1-B.
  - The first evaluation said "no mortar reaches any fort": it checked only the AI firing at team 1 from y -300 above
    its rock (wrong).
  Direct-fire weapons (sniper 10000, 20mm/cannon 6000, flak 8000) and rockets are not range-limited this way.

- **Wind**: the cliff wall behind every fort blocks each turbine's left side completely (`rules.wind_rays` with the
  map's terrain: 0 %). Vanilla-5's gallery behind its front weapons keeps 9-36 % on the right: no wind at all here.

## Plans (`fortplans/Vanilla2v6/`, redesigned 30.10.2026 after three matches, not yet played in this form)

`gen_fort.py --map Vanilla2v6` (`VANILLA2V6_VARIANTS`): the Vanilla base plan and starting fort, the map's terrain of all
eight spots laid over each other in the plan frame (`fwe_dir`, `fwe_frame.anchors`, `rock_clear` 15), and a `ceiling`:
no node above y -400, no device box above -450. The next fort up stands on rock at y -300, all of it behind x -3592; its
lowest storey (its starting fort's, -300..-398 here) never holds a weapon, its starting machine gun fires at ~-535 (the
player, 30.10.2026; the first ceiling, -250 / -300, kept everything below that rock). Every plan starts with the hub
([vanilla.md](vanilla.md)). Three weapon storeys over the starting fort's roof (205..80, 80..-45, -45..-175), each
front cell with one weapon alone in its row (a minigun needs a line of fire to the enemy fort), and the **wind
storey** on top (-175..-305): the turbines on its floor (x -3465/-3365/-3265/-3165, three of them), background bracing
all round (hidden: the wind passes, the player cannot see them), two stacked sandbags in its front cell. Wind (with
the terrain): right 54-72 %, left 0 % (the cliff). Turbines in a weapon storey behind the front weapon's door got 18-36 %
on the right (no wind), on the open roof 81-100 % but unprotected (third match).

| Plan | Row 205 | Row 80 | Row -45 | Wind storey / roof | Tech | physics.py max stress |
|---|---|---|---|---|---|---|
| Vanilla2v6-1 | sniper -> AP sniper | machine gun -> minigun | sniper -> AP sniper (LinkT 0.28) | 3 turbines, sandbags; two mortars -> heavy mortars in a storey -305..-370 on its roof (door roof, door in front) | workshop, upgrade | 0.47 |
| Vanilla2v6-2 | cannon (x -3200..-3100, lane in front) | cannon (same) | sniper -> AP sniper (LinkT 0.28) | 3 turbines, sandbags; machine gun -> minigun on the roof (open) | workshop, munitions, upgrade | 0.52 |
| Vanilla2v6-3 | EMP rocket -> rocket | EMP rocket -> rocket | EMP rocket -> rocket (full door) | 3 turbines, sandbags; machine gun -> minigun on the roof (open) | armoury, upgrade (right after the first two rockets) | 0.52 |
| Vanilla2v6-4 | laser (x -3200..-3100, lane in front); last a firebeam in front, row 602 (see below) | machine gun -> minigun | sniper -> AP sniper (LinkT 0.28) | 3 turbines, sandbags | workshop first, factory, store and battery before the laser, upgrade | 0.66 (0.50 without the firebeam) |

- **Firebeam (plan 4, the player's request, 30.10.2026):** a closed cell on the mine-row woodspam in front of the fort
  (x -2812..-2692, y ~497..602; the mine row in one 120-wide layer at x -2692 so its top strut carries the firebeam,
  50 to each side of its LinkT point 0.45), a door as its front post (with the second door layer), a wooden roof, a
  background diagonal. Its own row (602: the starting machine gun at 505, the laser at 205), nothing in front of it.
  It hangs over the slope, which takes no foundations: physics.py 0.50 -> 0.66 (the cell's diagonal), the front sags
  112 instead of 92. Built last (plan action 232 of 252), so a refusal on that strut (the AI gives up after 120 s)
  holds nothing up. Options not taken: behind a lane at x -3200..-3100, row 80 (the tested heavy-weapon column; the
  machine gun to the wind storey's roof), the prow floor (row 310; the prow overhangs the cliff).
- Plans 1 and 3: the low fort (x -3500..-2845 for the deck and nest with the prow lanes, the top storey to x -2945);
  plans 2 and 4: the block fort (x -3400..-2945, Vanilla-3's heavy-weapon column).
- No smoke launcher in plan 3: it needs a storey of its own row with a door roof (box assumed 127, the DLC file is
  packed); every such storey shares a rocket's row or reaches above the ceiling. The rockets fire without waiting.
- The roof machine guns of plans 2 and 3 stand in the open: a door shield in front of them would take the roof
  turbines' wind (a weapon cell on the roof as well).
- The mortars at y -170 (barrel ~-200) reach T1-A's reactor from T2-1..T2-4 (ballistics above).
- The first version (cage of turbines on top, mortar-free, machine guns side by side on the cage roof, a modular
  plan without fixed weapons) is replaced.
- The `Vanilla2v6Long` plans are the same four converted with `mid_to_long.py`, for a fort the game gives the long plan.
- Both entries in `ai/fortplans.lua` carry `FortPositions` (the eight forts' FortPos: team 2 (2900, 1100), (3800, 100),
  (4700, -900), (5600, -1900), (6500, -3000), (7400, -4000); team 1 (-3800, -300), (-4800, -1600)). The AI identifies
  the map by the game plan's signature (the same as Vanilla's) and then by where `OffsetFort`/`MirrorFort` put that plan's
  FortPos ([ai.md](../ai.md)); Vanilla's own fort (2900, 700) and Vanilla 2v2's upper one (3800, -250) keep their plans
  (`t_vanilla2v6.lua`).

## First match (30.10.2026, log_20261030-140328, ~146 s)

- Michael on T1-A against six AIs. All six forts identified by position: `PLAN map=Vanilla2v6 ... fort=` 2900,1100
  (plan 2), 3800,100 (1), 4700,-900 (2), 5600,-1900 (3), 6500,-3000 (4), 7400,-4000 (2); the game gave them the mid
  plans (weapon_pack's ToGAF1/ToGWM2, one from weapon_pack's long folder with the mid signature).
- His opening: workshop, then a front fortification before building up ([2v6-front-fortification.png](2v6-front-fortification.png)),
  then a turbine and a mortar nest at y ~80 behind sandbags. The part that matters (Michael): the **hub node** at
  (-2949, 532) in the starting fort's two lower front storeys, six background-bracing spokes to nodes 46, 47, 42, 40,
  51, 50 (17-26 s). `physics.py`, the hub added as the first actions: Vanilla2v6-1..4 0.64/0.59/0.83/0.74 ->
  0.48/0.47/0.59/0.61; Vanilla-2/-5/-6 0.65/0.69/0.68 -> 0.47/0.48/0.53, Vanilla-3 0.76 -> 0.75 (peak in its tower).
  Since 30.10.2026 the first 6 actions of every Vanilla-fort plan (Vanilla, VanillaLong, Vanilla2v6, Vanilla2v6Long;
  `_V_HUB` in `gen_fort.py`, part of `_V_FOOTING`).
- No AI device or strut was destroyed; the AIs had 4 snipers and 2 EMP rockets, 4 sniper shots and 1 rocket shot.

## Second match (30.10.2026, log_20261030-151042, ~640 s, the AI side won)

Plans: three rocket forts (T2-3, T2-4, T2-5), the laser fort (T2-2), two cannon forts (T2-1, T2-6). The player saw EMP
rockets but no rockets, and the heavy weapons late. Causes (fixed in the plans since):
- A sniper or rocket in the top storey's front cell (above the nest's weapon cell, one diagonal per cell, sniper at
  LinkT 0.7) was refused with `CS_UNSTABLE` in 3 of 4 forts and given up after 120 s; the laser fort's sniper in the
  front cell on the starting fort's front post too (the Vanilla notes: snipers refused there in every match). In the
  cannon forts the stuck sniper delayed the munitions plant to 145 s and the first cannon to ~300 s. Now: the front
  column X-braced, snipers at LinkT 0.28 in the top front cell (Vanilla-3's), a machine gun in the cell on the front
  post.
- The laser was never placed: it costs 6000 energy, the cap is 5000 until a battery stands, and the battery came after
  it (the fort sat at 1200 / 5000 from 185 s). Now the store and the battery come first.
- T2-4 stalled at plan action 173 for 8 minutes: a back node (-3600, 602) touched the rock step behind that spot only
  (`CS_OBSTRUCTION`, given up, the cells on it skipped one by one). Now the generator checks the terrain of all eight
  spots laid over each other (`fwe_frame.anchors`, `rock_clear` 15) and the back block starts at x -3500.
- The upgrade centre came at 270 / 392 s (after the third rocket, a turbine and two mines): rockets at 330 s in one
  fort, one at 535 s in another (its second upgrade refused with `CS_OCCUPIED`, then `CS_OBSTRUCTION`, cause unknown).
  Now right after the first two EMP rockets (plan action 62 instead of 111, the rockets at 91/92).
- A roof turbine on the hidden top storey (background bracing) was refused with `CS_UNSTABLE`: the top storey is solid.

## Third match (30.10.2026, log_20261030-152731, ~450 s, the AI side won)

Plans: four laser forts, two cannon forts (the version with turbines on the open roof). No plan action given up, only
first-try `CS_OCCUPIED`: the fixes of the second match held (snipers, cannons and lasers placed). Lasers at ~320 s: the
plan put the sniper first, which needs two storeys under it, so the workshop came at 75 s (now the workshop first);
cannons at ~300 s, the munitions plant at ~153 s (energy cap). The AI lost one machine gun. The player: the turbines on
the open roof are unprotected; fortify them in a storey (done: the wind storey).

## Fourth match (30.10.2026, log_20261030-155504, ~546 s, the AI side won without a device lost)

Plans: three cannon forts, one each of rockets, snipers/mortars and laser (the wind-storey version). No plan action
given up or skipped; the turbines in their storey lost nothing. AI shots: 251 sniper, 41 mortar (from T2-1, uphill to
T1-A), 21 rockets, 10 cannon. The player lost 8 machine guns, 8 flak, 3 turbines and 2 reactors.
- Rockets work: upgrade centre at 161 s, rockets at 238/247 s, the third EMP rocket at 322 s and its rocket at 352 s
  (two upgrades refused once with `CS_OBSTRUCTION`, built on the retry).
- The cannon and laser forts placed the sniper (third storey, two storeys below it) before their tech: sniper ~177-189
  s, munitions plant ~257 s / factory ~268 s, cannons ~350 s, laser ~371 s; the firebeam (plan action 232) was not
  reached by 546 s. Since then (the player): tech, then the sniper while it builds, then the main weapon (plan #2:
  munitions plant at action 36 instead of 124, sniper 128, cannon 131; plan #4: factory 23 instead of 122, sniper 122,
  laser 131, firebeam 231).
- `shots=` in a `SNAP` line counts the shots since the previous snapshot, not a total.

## Open

- Played once (short). To check in the log: `PLAN map=Vanilla2v6 file=... fort=x,y` for every AI fort (or `map=Vanilla` if a
  position is off), refused devices in the low storeys, the cage turbines' energy with one-sided wind.
- Whether the game gives 2v6 forts the mid or the long plan (both are covered).
- Whether a smoke launcher of an allied AI fort holds this fort's rockets (`Fire.SmokeCover` looks at the team).
