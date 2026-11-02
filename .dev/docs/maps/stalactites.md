# Stalactites (1v1 and 2v2): hanging forts

## Map

- `maps/Stalactites 1v1` (one fort per side) and `maps/Stalactites` (2v2, two per side; display name "Stalactites
  2v2"). No fort files of their own: `FortGroups` points to the game's shared **hanging** plans
  `ai/forts/hanging/long/fort-t1f1-TemplateHang-1/-2/-3.lua`. TemplateHang-1 was recorded on Stalactites 1v1 (FortPos
  (-2500, -1350)); -2 and -3 come from other maps, the game moves any of them onto any hanging fort.
- The same plans are used by Caverns (top forts), Up & Down (and 3v3), Rhino Vs Tiger, MP 1v3 2, Ziggurat 4v4,
  Dueling Vipers 4v4, Hellmouth 3v3 and the high forts of Stalactites 4v4: `fortplans.lua` tells Stalactites apart by
  `FortPositions` (fort 1 at (-2500, -1350), the 2v2 fort 2 at (-4100, -150), team 2 mirrored at +2500 / +4100).
- Plan frame (team 1, enemy to the right, y down). The fort **hangs** from a stalactite, x -3150..-2500:
  - underside at y -1350, the starting fort's six foundations x -3000..-2500;
  - mine pocket inside the rock above it: floor y -1500, roof up to -1750, open to the front. TemplateHang-1 uses the
    sites x -2823 / -2951 / -3079, TemplateHang-2 a fourth at -2696 between the starting fort's pocket posts;
  - reactor centred on its strut (153-90154, (-2799, -998)), box x -2844..-2754, y -1083..-913;
  - the starting machine gun on strut 162-157 (y -897) fires through the door 161-162 (x -2503, y -997..-897);
  - nothing below the fort (the abyss to the map's edge), the back wall slopes away from (-3150, -1350) to
    (-3500, -780) and (-4100, -450), the cave ceiling between the forts is at y -2000..-2600 (mortar arcs hit it).
  - 5000 between the fronts. The 2v2 fort 2 is the same starting fort 1600 back and 1200 lower: in the plan frame the
    back wall of fort 1 lies in front of it above y -1650 (`fwe_frame` lays both spots over the plan frame).

## Plans (`.dev/tools/fortgen/gen_hang.py`)

`gen_hang.py` adds the map and its variants to `gen_fort` and runs `gen_fort.main()`, so `gen_fort.py` itself is
unchanged: `py gen_hang.py --out <dir>`; `py gen_hang.py physics <plans> --map Stalactites` for `physics.py check`.
What a hanging fort needs from the generator:
- **Support from above** (`hanging`, with `require_support`): a cell needs both *top* corners held and is built
  after the cells it hangs from (`filter_supported_hanging`, patched onto `gen_fort.Plan`). With the standing rule
  every cell was dropped; without any rule the economy plan's gallery grew sideways off one cell (sag 200, struts
  240-319 long refused in `physics.py`).
- Foundations on the underside are created **only straight up from the node below them**, which is built first
  (`ensure_node_hanging`, patched onto `gen_fort.Plan`); the second row is -1200 (not the starting fort's -1198) so
  those posts are 150 (StandardMaxLength). gen_fort's `found_from_below` alone fell back to the neighbour beside: the
  first Stalactites-3 match (01.11.2026) refused the back foundation (-3100, -1350), created along the rock from the
  starting fort's (-3000, -1350), with CS_OBSTRUCTION, and the AI stuck at plan action 12 (the back block hangs on
  it). `run_tests.sh` checks every Stalactites plan for this ("Stalactites foundations built from below").
- Batteries and stores take slots high in the back block first (`eco_slots`): on the lowest free floors the back
  column was built up from the gallery and could not be closed to the underside.

Shape: a back block (x -3100..-2900, tech and eco), a front column (x -2503..-2368, weapons) in front of the
starting fort's front post, two 130-high storeys below the starting fort and a turbine gallery at the bottom
(-637..-507, background bracing, two stacked sandbags in its front cell). The front column is 135 wide: in a 100-wide
one a sniper's body fills the cell and `split_doors` cannot cut its door short. Front cells by floor: -1200 armour
(its front is slanted from node 132, no short door fits; it shields the anchor row), -1098 / -997 machine guns (100
high: full doors), -897 the starting machine gun's lane, -767 / -637 snipers or the laser behind two short doors.

**Deep fort** (plans 1 and 3, `_S_DEEP`): four heavy or tall front weapons need four storeys of 125+, so below the
starting fort come four 135-high storeys (-897..-762..-627..-492..-357) and the gallery (-357..-222). 135, not 130: a
cannon's door cut to its shot (92.5) left an armour piece of exactly 37.5 (StandardMinLength), refused in `physics.py`
once the fort sagged. Cannons, 20mm cannons and rockets stand in the cell *behind* the front column (x -2653..-2503,
150 wide, LinkT 0.2 / 0.4) and fire through the front cell, their lane: in the 135-wide front cell a cannon's body
filled the cell and its door could not be split. The second door layer only on every other row: on all four rows the
outer doors hanging off the front post x -2368 took its armour to 0.78-0.89 (and the ties between stacked outer doors
were 36-37 long, refused); on two rows 0.62-0.64. The munitions plant / armoury (170 high) stand on a back-block floor
through the storey above (`clear_boxes`). The gallery's two 75-wide cells are built right after the first turbine
(`_S_GALLERY_NARROW`): left to the final pass, their struts were squeezed to 25-33 by then.

**Smoke launcher perch** (plan 3, `_S_PERCH`): a lobbed weapon needs open air above it, which a hanging fort has only
in front of its front column: a 108-wide cell hung from the front column's nodes at x -2368 in the storey -897..-762
(wooden floor, door roof, door in front, background diagonal and a background hanger up to (-2368, -997), which the
starting machine gun fires through). The front cell behind it stays empty (the perch is in its line of fire); its front
x -2260 is off the grid (a grid node at -2268 would not be created by the `struts` step). The front cell -762 is built
first (`build` step); without it the perch failed and the launcher fell back to a cell under the starting fort, whose
arc turned the starting fort's front post 140-158 into background bracing.

**Hub** (every plan, `_S_HUB` as `footing`, the player's Vanilla idea): a node (-2545, -1175) inside the starting
fort's two front storeys with background spokes up to the underside foundations 131 (-2500, -1350) and 142
(-2600, -1350) and to the front post's nodes 140, 158, 161, 141, 151, 155 around it. The front column hangs on the
starting fort's front post 131-140-158-161-162; its piece 140-158 was the peak of every plan (0.46-0.71). With the hub
the load goes up to the rock directly: rockets 0.71 -> 0.60, miniguns 0.46 -> 0.33 (cannons stay at 0.72: their peak is
the deep front post's door armour). A further brace from the hub to the front column's top node (-2368, -1200)
changed nothing.

**Shield of the anchor storey and the mines** (every plan, `_S_SHIELD`, right after the first mine step, with the top
front cell built first): a player cuts a hanging fort off the rock, and the mines in the pocket were open to the front.
- The pocket mouth (x -2500, y -1650..-1500, the mines' only opening) armour: the starting fort's post 134-135 and a
  new foundation on the pocket roof's edge (-2500, -1650).
- The starting fort's front post 133-132 (x -2400, the storey under the pocket floor) armour.
- Two solid wood layers in front (x -2320, -2280, triangulated) from y -1590 (in front of the pocket mouth) down to
  y -1200; the first is braced back to the pocket wall's foundation (-2500, -1650). Only rock edges decorated
  `foundations` in the `.fwe` take foundations (`fwe.read`, vertex decoration): the stalactite's underside, pocket
  floor and pocket roof do, the rock lip over the mouth (`rocks01`) does not; the first version's lip foundation
  (-2320, -1686) was refused with CS_OBSTRUCTION in the match below.
- Nothing fires in these rows (the top front cell is armour, the first weapon row is -1098). Below y -1200 every front
  row holds a weapon, a fire lane or door layers, so solid woodspam there would block a shot: none (the only empty
  front row, Stalactites-2's -997, was left as it is).

| Plan | Idea |
|---|---|
| Stalactites-1 cannons | early sniper (-997), workshop, munitions plant; 20mm cannons (-627, -357) and cannons (-762, -492, two door layers) behind the front column, a machine gun -> minigun; deep fort |
| Stalactites-2 laser | workshop, factory, laser and sniper (-> AP sniper) behind the front column below the starting fort, minigun |
| Stalactites-3 rockets | armoury, two EMP rockets -> rockets (-627, -492), smoke launcher on the perch, two machine guns -> miniguns; late the munitions plant (opened by the armoury) and a cannon (-357); deep fort |
| Stalactites-4 swarm | a swarm rush (since 02.11.2026: one mine, workshop, spotter sniper, the launchers' background cover, the first launcher hidden, then the portals (the surprise, the user); the economy after it): two inverted swarm launchers (`missileinv` -> warheads `missile2inv`) on the mine pocket's roof over the two right mine sites, firing down into a portal that sends them out of a second portal in front of the shield; two plain snipers as spotters (no AP upgrade: an AP sniper cannot spot), two machine guns (one -> minigun), five mines (replaced plan 4 "miniguns" on 02.11.2026: the user: only AP snipers and miniguns win no match) |

Checked 01.11.2026: `validate()` and `rules.py` 0 errors (expected warnings: a diagonal in the upgrade centre's box,
and in plan 1 the diagonal of the cell behind each cannon inside its box), tech hidden when placed, turbine wind clear
with the terrain of both 2v2 spots. `physics.py` (with hub and shield): Stalactites-1 STANDS (0.72, sag 57), -2 STANDS
(0.47, sag 46), -3 WEAK by its sag only (0.60, sag 61), -4 STANDS (0.33, sag 33), nothing refused. The posts hanging straight down from the starting fort's bottom are reported
UNBRACED for a few actions, harmless when hanging. Not yet tested in a match.

**Lines of fire built late** (`clear_recent_blockers`, final pass for hanging plans): a solid strut in a direct-fire
weapon's line of fire (its barrel height ±10, up to 420 ahead) that the plan builds within `SWAP_WINDOW` actions before
the weapon becomes background bracing (armour: a door). `rules.py` takes such a strut as recessed by the game when the
weapon is placed, but a strut still under construction is not: in Stalactites-3 the post x -2503 between each EMP
rocket and its lane was built 3 actions before the rocket, stayed solid, and neither rocket fired once.

**Doors for sag** (`door_sag` 25, `door_span` patched for hanging plans): the doors reach 25 higher than the shot
needs. The front column hangs further from the rock than the cell behind it and sags more: in the second
Stalactites-3 match the cannon (-2653, -357) behind its lane never fired, its shot hit the armour above its door (cut
to the shot +- 22.5). In the 135-high rows of the deep plans this gives full doors; the outer door layers of stacked
rows are then tied by armour, which `clear_recent_blockers` also clears where a row's layer is skipped (struts built
after a weapon in its line of fire are never recessed). Peak stress after the change: Stalactites-1 0.47, -3 0.48
(sag 61, WEAK by sag only).

**Metal out of the weapons' bodies, starting machine gun sold** (02.11.2026): every front-column weapon was refused with `CS_UNSTABLE` because the door post x -2368 reached into its body (placing a weapon recesses only wood bracing; probe and player, [building-rules.md](../building-rules.md)). `fit_weapon_bodies` now moves them back on their struts: cannons LinkT 0.20 -> 0.08, 20mm cannons -> 0.12, snipers / AP snipers -> 0.10-0.11 (the body still ends at the door). Every plan sells the starting machine gun first (`sell:machinegun`, `orig_devices` strut 157-162): the front column in front of it took its line of fire (the grid rebuilds its door 161-162 as wood). physics.py all STANDS (0.33-0.55, sag 32-49), rules 0 errors.

**Plan 3: economy before the munitions plant** (02.11.2026): the turbine2 upgrades, battery, mine and mine2 upgrades now come before the munitions plant (800 metal) and the cannon; same 282 actions, physics STANDS (0.55, sag 49).

**Background skeleton** (`skeleton`, `background_skeleton`, every plan): in the fourth match the player cut the
starting fort's bottom storey (y -997..-897) from the front post to the back block within 1.6 s and everything below
fell. Background bracing cannot be shot, so the fort must hang on it alone once every foreground strut of a storey is
cut. Every cell (two posts side by side between the same floors) gets both diagonals as background bracing (a
foreground diagonal is made background, the free one added right after the cell's last strut); the starting fort is a
zigzag truss without posts, so across its storeys (`skeleton_levels` -1275 / -1150 / -1047 / -947) up to 8 background
hangers between nodes the plan can name are added, near-vertical first and spread over the width (struts between
starting-fort nodes after the hub, which stays the first step). Left out: device boxes (also the starting fort's,
from the .spr), every direct-fire weapon's line of fire (barrel height +- 15, 420 ahead) and `skeleton_keepout` (the
reactor, the starting machine gun's cell). 25-37 diagonals added and 13-22 made background per plan.

`py gen_hang.py cut <plans>` (in `run_tests.sh`): the plan is built in physics.py, every foreground strut through a
height is removed (9 heights, -1275 .. -290) and the rest settled. Before the skeleton Stalactites-3 fell at
-1275 / -1150 / -1047 (the reactor with it) and at -947 (17 devices: the match's loss exactly); now all four plans
hold at every height. It also stiffened the forts: Stalactites-1 STANDS 0.43 (sag 36), -2 0.35 (32), -3 0.44 (43, was
WEAK by sag), -4 0.56 (35).

**Swarm missiles through a portal** (plan 4, 02.11.2026, the player's layout of the 2v2 match that day): swarm
launchers need a workshop (warheads the upgrade centre), stand on the ground only, and fire only at a target a plain
sniper paints (`RequiresSpotterToFire`; sniper SpotterFactor 1, AP sniper 0). The inverted ones hang from a roof and
fire straight down. The pocket's roof (y -1650) is flat from x -3100 to the mouth at -2500, foundations only on
x -2700..-2500. The launchers stand at x -2696.12 / -2568.52 (the player's spots, over mine sites 4 and 5; both mines
stay below). Entry portal: strut (-2705, -1578)->(-2555, -1578), held only by background bracing (the missiles pass it)
from the mouth post 134-135, a node (-2632, -1600) and the roof foundation (-2632, -1650) straight above it. Exit
portal: upright (-2210, -1500)->(-2210, -1630) in front of the shield's outer wood layer, nothing in front of it.
`CONNECT` (the base AI's ConnectPortals, rebuilt with its struts) links entry A-B to exit A-B. Assumed: a portal maps
its A->B onto the destination's A->B keeping the crossing side, so a missile falling through west->east leaves
lower->upper to the right: **confirmed** in the fifth test match (02.11.2026, the player saw the missiles fly to the
enemy). Risk: enemy shots entering the exit portal come out under the launchers.
The portal material is packed (`dlc1_portal.pack`): physics.py assumes armour values. Generator steps `("ground",
[(device, (x, y))])` and `("connect", [(A, B, dest A, dest B)])` (gen_fort). Rules 0 errors, physics STANDS (0.31,
sag 35), all tests pass.

**Swarm extension, mine guard, plan 4's cannon** (02.11.2026, the user): plans 1-3 end with the swarm launchers
(`_S_SWARM_LATE`): a plain spotter sniper in the starting machine gun's old fire lane (front cell -997..-897, pinned by
`weapon_cells` + a build step; left to the generator it took the slanted top front cell with armour in its body), the
cover, the hidden launcher, a battery, the portals, the mine guard, the second launcher, both warheads (plan 3 gets
the workshop for it). The mine guard (`_S_MINE_GUARD`, plan 4 after its first warhead): two sandbags on the floor in
front of the pocket mouth (struts 134-133 and 133-(-2320, -1500)) and the shield's inner post over the mouth armour.
Plan 4 then grows down: munitions plant on the back block's floor -637, a storey under the gallery's front
(-507..-372, rows + -372) and a cannon in its front cell behind two doors (a node (-2260, -507) for the outer door
layer). All four: rules 0 errors, physics STANDS (0.35-0.54, sag 33-50), every CONNECT points at the other portal
after the renumbering, tests pass.

## Matches

| Date | Plan (game plan) | Result | Notes |
|---|---|---|---|
| 01.11.2026 | ToGHngA1 kept (weapon_pack's plans were not in `Originals`) | AI won, 10.2 min | the player fired little; weapon_pack's three hanging plans added to `Originals` |
| 01.11.2026 | Stalactites-3 forced (ToGW1) | aborted | stuck at plan action 12: the back foundation (-3100, -1350) was created along the rock, CS_OBSTRUCTION (`ensure_node_hanging`) |
| 01.11.2026 | Stalactites-3 forced (ToGA1) | player won, 9.1 min | the rockets never fired (post in their line of fire, `clear_recent_blockers`), 42 smoke shells wasted; the lip foundation refused; the player's two flak and two cannons (4 shots) took the reactor; AI metal < 150 for 61 % of the match |
| 01.11.2026 | Stalactites-3 forced (ToGA1), difficulty 1 | player won, 19.4 min | EMP rockets 22 shots, but the upgraded rockets (from 6.6 min) and the late cannon 0: the cannon's shot hit the armour above its door (`door_sag`), why the rockets did not fire is not in the log (smoke-cover shots now logged: `SMOKETRY`, `FIRETRY`, `FIREHOLD`); 741 minigun shots, 9 MG kills; at 12.0 min the player (flak, laser, firebeams) cut the lower fort off: rockets, cannon, smoke launcher, armoury, upgrade centre, turbines, battery and store fell within 5 frames (`LOST s=0`), 88-126 struts to rebuild after it; the AI never recovered |

| 01.11.2026 | 2v2, difficulty 1: ally T201 Stalactites-4, enemy T102 Stalactites-4, T202 Stalactites-3 (lower spot) | player's side won, 12.1 min | in both Stalactites-4 forts the snipers in the front column below the starting fort (-767, -637) and their AP upgrades were refused with `CS_UNSTABLE` (the game saw the nodes moving, `v=2-3`, strain ~1.0) and given up, and the fourth mine (-2696) too; plans 2 and 4 got their snipers behind the front column at first; moved forward again the same day for the angle on both enemy forts (see Weapons forward) (this time the upgraded rockets fired 22 times under smoke). Side 2 fell when both reactors went (T202's at 11.4 min) |
| 01.11.2026 | 2v2, difficulty 1: ally T201 Stalactites-1 (lower spot), enemy T102 Stalactites-2, T202 Stalactites-1 (lower spot) | player's side won, 13.6 min | every front-column sniper / cannon / 20mm of all three forts `CS_UNSTABLE` and given up (T201 sniper -997 and 20mm; T202 sniper and cannon; T102 sniper, AP sniper, a mine); side 2 ended with 1 laser + 1 20mm and sat on 1200 metal. The mirrored forts' `sag=115-157`, strain 0.27-1.46 were a logging error (MirrorFort swaps a device's node ids but not PosA/PosB; fixed in `CAI_BuildPlanIndex`): SHAPE shows both sides alike (dy median 10, max ~21), so the refusals are real but not from sag. T102 fell at 12.6 min when the player cut the struts round its reactor |
| 02.11.2026 | 2v2, difficulty 1: ally T201 Stalactites-2, enemy T102 Stalactites-4, T202 Stalactites-3 (lower spot) | player's side won, 17.6 min | first match after "metal out of the bodies": no weapon refused (no `CS_UNSTABLE` on weapons), the starting machine guns sold in the first minute, T102 and T201 built their plans to the end; T202 waited 8 minutes (t 525-1020) on the munitions plant (800 metal; its metal never passed ~540 while it rebuilt 16 miniguns), with two mines, turbine2 and a battery behind it -> plan 3's economy moved before the munitions plant. Side 2 1559 shots (1117 minigun) vs 642, metal 590 vs 1467 (11 turbine2 on side 1) |
| 02.11.2026 | 1v1, Stalactites-4 (swarm) forced | aborted at ~6.5 min | both portals and `CONNECT` built; the first launcher was refused before the portals (`CS_INVALIDNODES`) and placed once the struts stood (now after them); both launchers ready from 5.3 / 5.8 min, no missile left in ~1 min: the built-in `LaunchMissile` fires with `FIREFLAG_TERRAINBLOCKS` (rock between the pocket and the target), now replaced in ai.lua (no terrain test, logs `PAINT` / `MISSILE`) |
| 02.11.2026 | 1v1, Stalactites-4 (swarm) forced, again | aborted | the sniper painted (`PAINT painted=1`) but the launch was `FIRE_BLOCKED`; only the entry portal glowed, the exit portal stayed dark (the player: connected portals both glow) -> a second `CONNECT` back from the exit to the entry, and `CONNECT` lines in the log (result, both portals' destinations) |
| 02.11.2026 | 1v1, Stalactites-4 (swarm) forced, third | aborted at ~7.7 min | launchers ready only at 7.0 / 7.2 min, no `PAINT` before the end; no `CONNECT` line at all although the build passed both CONNECT actions (the wrapper's pcall may have swallowed an error). Assumed cause of the dark exit portal: CONNECT runs while the exit strut is still being built -> ai.lua now checks every 5 s that each CONNECT's portal leads to its destination and connects again (`PORTAL` lines), and logs `CONNECT` before anything else |
| 02.11.2026 | 1v1, Stalactites-4 (swarm) forced, fourth | (running) | `PORTAL`/`CONNECT` lines showed the cause: the entry portal 308-304 was connected to 307-308, the back CONNECT failed (dest=0-0). MirrorFort/OffsetFort renumber the plan's nodes (`MakeAINodesInSequence`) but not a CONNECT's destination ids -> replaced in ai.lua (destinations mapped too); checked on plan 4 in Lua (both CONNECTs point at the other portal) |
| 02.11.2026 | 1v1, Stalactites-4 (swarm) forced, fifth (with the renumbering fix) | (running at ~5 min) | **the launchers fired** (`MISSILE ... result=FIRE_SUCCESS`, 36 swarm missiles in the SNAPs by ~5 min). The first CONNECT failed while the exit strut was still being built (`cp=-1`), the portal check connected the back direction (`CP_SUCCESS`), then both plan CONNECTs succeeded (dest = the other portal both ways); the missiles leave the exit portal towards the enemy (the player) |
| 02.11.2026 | (same match, until ~5.5 min) | - | workshop only at 3.9 min (machine gun, sniper, two turbines, four mines before it), first launcher placed 4.3 / built 5.3 min, the second placed 4.9 min, still building; metal mostly under 300 -> plan 4 reordered as a rush (the user): mine, workshop, sniper, portals, first launcher (action 102 instead of 131), then mines, machine gun, turbine, second launcher |
| 02.11.2026 | 1v1, Stalactites-4 swarm rush with hidden launchers, forced | player won, 15.1 min | first launcher placed 3.4 / ready 4.4 min (5.3 before), portals 3.6 / 4.0 min, second launcher ready 7.3 min, warheads 11.5 min; 3 launches `FIRE_SUCCESS`, 1 `FIRE_ENERGY`: energy 80-900 from 5 min on (a swarm volley 1000 energy, a warhead 4000, the portals drain all the time) while metal sat at its cap of 900 from 5.3 to 8.6 min with one turbine; the player's 135 20mm and 288 shrapnel shots took 7 snipers and the reactor -> plan 4: two turbines right after the first launcher (before the portals), four turbines (the gallery's slots) all upgraded to turbine2 before the warheads |
| 02.11.2026 | 1v1, Stalactites-4 (turbines, mine guard, late cannon), forced | player won, 18.2 min | launcher 1 ready 4.0 min, portals 3.9 / 4.0, launcher 2 6.8, upgrade centre 8.4, warheads 10.9 / 11.6, munitions 12.3, cannon 14.8; launches: swarm 9 `FIRE_SUCCESS` (126 missiles), warheads 10 (all shot down: `damagedmissile2`, the player's 108 flak shots), 4 `FIRE_ENERGY`, 1 `FIRE_METAL`, 3 `FIRE_BLOCKED` (before the portals connected); kills flak 6, cannon, turbine, 2 sandbags. The spotter is the weak point: `PAINT` painted=0 in 58 of 87 requests (9 with no sniper at all), snipers lost 9 times to 1236 shrapnel shots |
| 02.11.2026 | 2v2, random: ally T201 Stalactites-4 (lower spot), enemy T102 Stalactites-2, T202 Stalactites-3 (lower spot) | player's side won, 15.6 min | the missile extension of plans 1-3 came too late to matter: T102 (plan 2) reached action 374 of 422 (the extension starts ~390; rebuild queue 47-312 at the end), T202 (plan 3) reached its first launcher at ~13.3 min (action 458, `CS_OCCUPIED`, then waiting) and stayed there to the end. The ally T201 (plan 4) fired 10 swarm volleys and 8 warheads (`FIRE_SUCCESS`), painted in 38 of 91 requests; T202's munitions plant again `UNSTABLE` |

**Weapons forward, two doors each** (user, 01.11.2026): behind a 135-wide lane the muzzle was ~125 behind the door and
the opening covered too narrow a cone for both enemy forts on 2v2, and a lane had one door only (AP sniper). Every weapon
now stands in the front column (x -2503..-2368, LinkT 0.2, its barrel at the front post's door) with two doors:
- plans 1, 2, 4: the generator's outer layer at x -2318. With full doors in stacked rows (`door_sag`) the generator's
  tie of the outer doors re-created the next row's outer door as armour; `keep_outer_doors` drops such armour copies
  and makes outer-column armour in front of a lane (the starting machine gun's row) a door. `door_span` in hanging forts
  also leaves no armour piece under 45 above or below a door (Stalactites-1's 20mm: 37.5 pieces squeezed to 34-35).
- plan 3: the perch's front door continued down as an outer door wall at x -2260 to the cannon's floor
  (`_s_door_wall`, tied to the front post at each floor, background diagonals; built with each weapon's cell), since
  the generator's layer at x -2318 would start on the perch floor.
- Risk: in the 2v2 match the snipers in this column (plan 4, rows -767 / -637) were refused with `CS_UNSTABLE` (the game
  saw the nodes moving, `v=2-3`). Not explained; if it happens again, run the `Probe` (debugging.md) on the front column.

Checked: rules 0 errors, physics all STANDS (0.33-0.55, sag 32-49), cut test 0 falls, no new background bracing in a
line of fire.

## Open

- No mortars: the ceiling caps their arcs (untested); the game's own hanging plans have none either. Whether the smoke
  launcher's shells clear the ceiling is untested as well.
- The deep plans hang ~1130 below the underside: watch the front post x -2368 and the starting fort's front post 140-158
  under fire.
- The fourth mine site (-2696) stands between the starting fort's pocket posts: built in Stalactites-3's 1v1 match,
  given up in both Stalactites-4 forts of the 2v2 match (no build error logged). Watch it; drop it from `mines` if it
  keeps failing.
- The cut test assumes the player cuts the foreground struts of one storey only, and treats background bracing as
  unbreakable by fire (true for shots; splash and fire damage are not modelled). Watch the next match's `UNLINK`
  records for background bracing lost before the foreground struts around it.
- The AI targets devices only. Cutting the enemy fort's anchor struts under the stalactite would drop the whole fort;
  a map-specific target for struts is not built.
