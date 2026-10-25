# FORT 9000 – Specification

FORT 9000 is a mod for the game **Forts** (Steam). It extends the built-in AI, records matches, and automatically retrains the AI parameters from those recordings.

In-game name: *FORT 9000 (AI + Recorder)* · Folder: `data/mods/fort-9000`

---

## 1. Goals

- A stronger, more adaptive computer opponent than the built-in Forts AI.
- The AI should improve from real matches (training), not only through manual tuning.
- Custom build variants per map, so the AI does not always build the same fort.
- Everything deterministic: replays and multiplayer must not desync.

## 2. Features

### 2.1 Adaptive target selection
The priority lists of the built-in AI (`HeavyArmsPriorities`, `SmallArmsPriorities`) are re-sorted every `ThinkInterval` seconds.
Score per device type = base value (`Strategy.TargetValue`) + threat bonus.
Threat rises when an enemy weapon fires (`ThreatPerShot`), hits us (`ThreatPerHit`) or hits the reactor (`ThreatPerReactorHit`), and decays continuously (`ThreatDecay`). The bonus saturates: `ThreatWeight · T / (T + ThreatHalf)`. When an enemy weapon is destroyed, its threat drops to 70 %.

### 2.2 Aggression by game phase and economy
- Phases: Early (< `EarlySeconds`), Mid, Late (from `LateSeconds`), each with its own factor.
- Plenty of metal (`RichMetal`) → factor × `RichBoost`; low metal/energy (`PoorMetal`, `PoorEnergy`) → factor × `PoorFactor`.
- Applied to `OffensiveFireProbability` (machine guns are excluded via `AggressionExclude`).

### 2.3 Anti-air by incoming fire pressure
Counts enemy shots from mortars and missiles (`IndirectThreatTypes`). The more there are, the more `AntiAirFireProbability` is raised (up to `AntiAirBoostMax`).

### 2.4 Fire control
The built-in AI only fires during build pauses and at most one weapon per cycle. FORT 9000 sets `HardThreshold = 0` (always ready to attack), raises the fire probability while building (`RebuildFireFactor`), and fires on its own timer (`Fire.Interval`), cycling through up to `WeaponsPerTick` ready weapons. Weapon types in `Fire.NoOffence` (default: the plain machine gun; the upgraded minigun is a separate type and keeps firing at the fort) never fire at the enemy fort (offensive and rebuild fire probability 0; they do little damage there and stay anti-air); the fire timer skips them without using up a turn, so snipers and other weapons fire instead.
**Smoke before rockets** (`Fire.SmokeCover`): rockets and EMP rockets are projectiles the enemy anti-air shoots down. While the team has a smoke launcher (`smokebomb`, `smokebomb2`), a rocket only fires from `MinDelay` (2 s) to `Window` (10 s) after one of the team's own smoke shells was fired (`OnWeaponFired`, timed in game seconds by the fire timer). When a rocket is ready without smoke, the fire timer fires a ready smoke launcher first; under smoke the ready rockets fire before the other weapons. `TryFireGun` is wrapped, so the built-in AI's own rocket shots are held the same way (a group that is already firing is not interrupted). Held rockets do not use up turns. After `MaxHold` (30 s) without smoke (launcher destroyed, reloading, no target or no energy) the rockets fire anyway (`SMOKE_TIMEOUT` in the log). Without a smoke launcher nothing changes. The timings are first guesses (the smoke bomb is a packed DLC weapon, its shell's flight time and cloud duration are not readable).
**Fire diagnostics:** the fire timer logs why an offence weapon did not fire, at most one line per weapon every `CAI_FIREWAIT_EVERY` (30) seconds and at once when the reason changes: `FIREWAIT <type> <id> avail=<0|1> ready=<0|1> code=<FIREFAIL name|-> queue=<0|1> m= e=` when it is skipped (not available, not ready to fire with the engine's reason, or an action such as opening doors pending), `FIRETRY <type> <id> fired=<0|1> code= [ray=<hit>:<side>:<material>@<x>,<y>] m= e=` after `TryFireGun` (fired = no longer ready, i.e. reloading; `fired=0`: the built-in AI declined - no target, chance or cost; `ray` = what the targeting ray towards the enemy reactor hits first, cast with the flags of the built-in `TargetObstructed`, in which the team's own background bracing blocks the ray). Second rush test: the 20mm was built at 220 s and reported ready; every `TryFireGun` was declined although energy (up to 9000) and metal were there; the 20mm's `alone` grouping affinity is 1, so the likely reason is no target: `FindTarget` drops targets whose ray is blocked, and in the 20mm's cell on floor 105 the background diagonal runs from (-3200,-20) down to (-3100,105), right in front of its barrel (in the old cannon cells it ran the other way, behind it). The `CREC` struts of that match showed the actual cause: the post in front of the 20mm's lane (x -2945, floor 105 to -20) was placed as wood bracing at 212 s (before the cannon was finished) and only became the planned door at 422 s, when the AI had finished the plan and its final pass corrected the material; the 20mm fired 11 s later (in the first rush test: door 332 s, first shot 343 s). A material change on a strut that is still under construction does not take effect, and the AI works through its actions faster than struts are built (5 s and more), so a door or armour planned a few actions after its strut stayed wood (in that match only 2 armour struts and no door were built before the plan was finished). `gen_fort.py` therefore gives the action that places a strut its final material when the plan changes it within `SWAP_WINDOW` (20) actions, instead of adding a second action that swaps it (8-9 actions fewer per Vanilla plan; the rush 20mm now comes after 58 struts). Test match with it (24.10.2026): munitions plant 155 s, 20mm placed 158 s, built 228 s and fired at once (first shots by 230 s, against 445-480 s with the earlier plans). Added after the 20mm rush test (24.10.2026), where the finished 20mm waited ~2 minutes before its first shot although energy and its line of fire were free.

### 2.5 Build tempo by difficulty
Update period (`UpdatePeriod`) and repair period (`RepairPeriod`) are interpolated linearly between Easy / Normal / Hard. Construction and pause durations are configurable.

### 2.6 Build safety valves
- **Give up rebuilds:** if a queued rebuild action is stuck for longer than `RebuildGiveUpSeconds`, it is discarded. If the AI is merely waiting for metal, the clock does not run. "Insufficient resources" only counts as waiting while metal is still rising; if metal stays flat above `BuildSkipMinMetal` for `StarvedFlatTicks` think ticks (e.g. at the storage cap, when an action costs more than can be stored), the clocks run again.
- **Skip actions:** if normal construction is stuck on one action for longer than `BuildSkipSeconds` despite enough metal (`BuildSkipMinMetal`), the action is skipped.

### 2.7 Custom build plan variants per map
- Plans live in `fortplans/<Map>/` (Forts removes foreign files from `data/maps`).
- The map is identified by file name or by the signature of the game's plan (position + action count, optionally reactor count).
  Plans of other mods can be listed as originals by full path; Vanilla knows the `weapon_pack` mid plans (ToGAF1, ToGWM2).
- One plan is chosen deterministically per match (game random or `teamId`) and shifted into the coordinates of the game's plan; the game then mirrors/offsets it as usual.
- `"original"` in the plan list keeps the game's own plan.
- Abyss variants: the game's own plan, Abyss-2 mortars, Abyss-3 snipers, Abyss-4 two cannons, Abyss-5 rockets with smoke
  (armoury, two EMP rockets upgraded to rockets, two smoke bombs, two flak upgraded to shotguns; see 2.12).
- Supported maps: **Abyss**, **Vanilla** (mid fort, also applies to Penguin, Caverns, …), **VanillaLong** (2v2, upper platform).
- Per-map strategy overrides (`Maps[<Map>].Strategy`), e.g. a slower start on wide maps.

### 2.8 Debugging
Build functions (`CreateLink`, `CreateNode`, `CreateDeviceWithFlags`, `CreateGroundDevice`, `UpgradeDevice`, `DestroyDevice`) are hooked; a sale (`DestroyDevice`) that finds nothing on the strut is tried with the nodes the other way round (a device is found only in the node order it was built with, `GetDeviceIdOnPlatform`; the built-in `DestroyAttachedDevices` does the same), if both orders find nothing (test matches 25.10.2026: the planned sale of the starting machine gun found nothing in either order - it stood on another strut, see below), the own device whose platform (`GetDevicePlatformA/B`) is that strut is sold by its id (`DestroyDeviceById`), else the own device standing closest to the strut within 40 (`GetDevicePosition`; in the eleventh test no device's platform matched either: `scan=6 match=none`); a failed sale is logged as `BUILD_ERROR destroy scan=<devices> match=<id|none>` with its `DD_*` code and, if nothing matched, every own device as `type@platform:position`; failed attempts are written to the log with the error code as `BUILD_ERROR` (once per case, max. 200).
A device that fails with `CS_UNSTABLE` additionally writes `UNSTABLE <device> <nodeA>-<nodeB> N<id> sag=<distance from planned position> v=<speed> ... links=<n> strain=<min>..<max> stretched=<link> compressed=<link> action=<k>` (up to 3 samples per device and place): strain is current/planned length of all links at the two nodes (bracing breaks below 0.90 or above 1.10, background bracing below 0.92 or above 1.08); `<link>` = `N<id>(x,y)-N<id>(x,y) <planned material>` for the most stretched / most compressed link (current world positions; `start-fort` if the plan does not build it). Background bracing cannot carry devices (`SupportsDevices = false`).
Shape snapshots: `SHAPE t=<s> why=<minute|unstable:<device>> mirrored=<0|1> part=<k>/<n> <plan node id>:<dx>,<dy> ...` lists how far every plan node (starting fort and new) has moved from its planned position, on the first `CS_UNSTABLE` of a device and place and once per game minute (at most `CAI_SHAPE_MAX` = 40 snapshots, 25 nodes per line). dx/dy are in the plan's own frame (x mirrored back when the game mirrored the plan; `MirrorFort` sets `CAI_FortMirrored`), so they can be laid over the plan file: `python tools/fortgen/shape.py [log] [--team 102] [--match -1] [--png out.png]` prints per snapshot the average forward/down movement of each storey row and the nodes that moved most, and draws the offsets as arrows.
Real stress: on the same first `CS_UNSTABLE` of a device and place (at most `CAI_STRESS_MAX` = 20 times) the mod also enumerates the fort's struts with the engine's own stress (`EnumerateLinks`, callback `CAI_EnumStress`) and writes `STRESS <device> <a>-<b> links=<n> at=<link> ... top=<link> ...`: `at` = every strut at the device's two nodes, `top` = the `CAI_STRESS_TOP` = 8 most stressed struts of the fort (by |stress|); `<link>` = `<node>-<node>:<material>:<stress>` with `P<plan node id>` for plan nodes, else `N<actual id>`. The strain in the `UNSTABLE` line only compares with plan lengths, which is meaningless for struts built between nodes that had already moved; `shape.py` prints the `STRESS` lines with plan positions.
CS_UNSTABLE probe (testing only): with `Probe` set in `fortplans.lua` (see 4), the AI stops (`data.Disable`) once its plan is finished (or after `Probe.At` seconds) and tries every device of `Probe.Devices` at every LinkT of `Probe.LinkT` on every strut of its fort made of `Probe.Materials` (default bracing and armour) and at most `MaxAngle` (default 20) degrees steep (optional `Box` in world coordinates, `Max` attempts), one attempt every `Interval` seconds (default 0.2), one device over the whole fort before the next. It calls the engine's `CreateDeviceWithFlags` directly (no `BUILD_ERROR`/`UNSTABLE` diagnostics) and removes a placed device again at once (refunded), or after `Hold` seconds to measure its load. Lines: `PROBE START`, `PROBE NODE` (every node with world position and plan node id), `PROBE LINK` (every strut with the engine's stress before the probe and the devices standing on it, `<device>@<LinkT>`), one `PROBE TRY <k> <device> <a>-<b> t=<LinkT> r=<OK|result> s=<strut stress> sn=<largest |stress| of the other struts at its nodes> len= ang= sag= v= dv=<devices on the strut> dn=<devices on the other struts at its nodes> near=<their types>` per attempt (measured just before it), `PROBE LOAD` (stress and node movement after `Hold`), `PROBE WAIT` (short of resources: the attempt is repeated, at most 30 times), `PROBE END`; exact format in the header of the probe section of `ai/ai.lua`. `python tools/fortgen/probe.py [log] [--csv out.csv] [--png out.png]` prints per device how many attempts were placed or refused, the quartiles of every measured value for placed vs. `CS_UNSTABLE` and the single threshold that separates them best, lists the refused struts, writes every attempt as CSV (for fitting a model of the check) and draws a map per device. A match with `PROBE` lines is not used for training. First game run (24.10.2026, Vanilla-3, 20mm cannon, 60 attempts): removal works (no `CS_OCCUPIED` after it); a device under construction hardly loads the structure (after 3 s `Hold` the strut stress rose 0.026 to 0.029, its nodes dropped 1), so `Hold` tells little; every strut of 30 degrees or more was `CS_INVALIDNODES` (hence `MaxAngle`); on the level struts 2 placed, 13 `CS_UNSTABLE` at strut stress 0.000-0.186 and 12 `CS_NODESTOOCLOSE` (78-164 long, cause unknown); neither strut stress, the stress at its nodes, length nor sag separated placed from refused. Full run the same day (54 level struts, 20mm cannon and sniper at LinkT 0.2/0.5/0.8, 324 attempts): 110 placed, 118 `CS_UNSTABLE`, 96 `CS_NODESTOOCLOSE`; the sniper (mass 40) and the 20mm cannon (100) got the same result on 51 of 54 struts, so the check is not about the device's weight; no measured value separated the results better than 64-71 %. Placed: nearly every level strut of the back block (between fully solid X-braced cells); refused: the starting fort, the front of the tower and the weapon cells, where devices already stand. The probe therefore also logs the existing devices (`dv`, `dn`, `near`); `probe.py` splits the results by them and marks them on the map. Third run with them (same fort, identical totals, so the check is deterministic): every `CS_NODESTOOCLOSE` (96 of 96) was a strut that already carries a device, i.e. the strut is taken; `CS_UNSTABLE` came in 80 of 84 attempts on a strut whose node is shared with a strut carrying a device (placed only 4), against 38 of 144 on struts with no device at either node. Those remaining refusals were 8 struts: four in the sagging, tilted top of the weapon tower (8-13 degrees, sag 56-91), two at its top left (sag 164) and two unexplained (2885,417 and 3499,508); without nearby devices the best single split was sag > 40 (85 %). This holds for adding a device to the finished, loaded fort, but it is not a rule for plans: the game's own plans (Template-1/2, Abyss-1) build turbines and mortars side by side on struts sharing a node, and in the probed match two turbines stood on struts sharing one node (both built while the fort was still small). The refusal near existing devices therefore probably depends on the load at the shared node when the device is added (a device built late, next to loaded devices, fails); not yet a `rules.py` check.

### 2.9 Assist-AI mode
If a player takes over the AI as an anti-air assistant, FORT 9000 deactivates itself and restores all changed values.

### 2.10 Recorder
`script.lua` runs in every match and in replays, changes nothing in the game, and writes lines prefixed `[CREC]` to the Forts log:

| Line | Content |
|---|---|
| `START v=3` | Start |
| `SNAP s=… m=… e=… dev=… shots=…` | every 125 frames: metal, energy, devices and shots per side |
| `BUILT` / `LOST s=… i=<device id> d=…` | device completed / destroyed |
| `NODE` / `LINK` / `DEV` / `GDEV` | node, strut, device on a strut (nodes, LinkT, `u=` upgraded device), ground device built (both sides; positions, team `t=`) |
| `UNNODE` / `UNLINK` / `DEL` | node, strut destroyed; device scrapped |
| `RESULT w=…` | winner |

The build events (see the header of `script.lua` for the exact format) let `tools/fortgen/rec_fort.py` turn a fort built by a player into an AI build plan: struts to new nodes become `CREATE_NODE` from the end that already exists, other struts `CREATE_LINK`, devices `CREATE_DEVICE` (ground devices with `GroundPosition`), in the player's order. Parts built and removed again are left out; removing a part of the starting fort becomes `DESTROY_LINK`/`DESTROY_DEVICE`; an upgrade keeps the old device and adds the new one. Starting-fort nodes are matched by position (within 20) to the base plan of the map (`gen_fort.MAPS`), new nodes get ids from 10000. A fort built on side 2 is mirrored into the team-1 frame like the game mirrors plans (device nodes swapped, LinkT -> 1 - LinkT). The tool then checks the plan (build order, lengths, rock, `rules.py`). Record without combat (sandbox, or `--until <frame>` before the first shot), otherwise damage and repairs end up in the plan. Not yet tried in the game: the order in which the engine reports a new node and its strut (both orders are handled), and whether ground devices also fire `OnDeviceCreated` (handled: the ground event wins).

### 2.11 Training
`tools/train.py` collects the logs, learns from them and rewrites `ai/strategy.lua` (previous version: `strategy_previous.lua`).
Learning always starts from the default values, so running it repeatedly shifts nothing; only new matches change the result.
It learns `TargetValue` (Heavy/Small) and `Aggression` (Early/Mid/Late). `--strength` (0..1) limits how far values may deviate from the defaults.

### 2.12 Fort generator
`tools/fortgen/` generates build plan variants (`gen_fort.py`), checks plans against the fort building rules (`rules.py`, see 2.13), converts plans between coordinate systems (`mid_to_long.py`: the VanillaLong plans are the Vanilla plans converted, `mid_to_long.py fortplans/Vanilla/fort-t1f1-Vanilla-N.lua <Forts>/data/ai/forts/vanilla/long/fort-t2f1-Template-1.lua fortplans/VanillaLong/fort-t2f3-VanillaLong-N.lua`; convert them again whenever the Vanilla plans change) renders them as images for review (`render_all.py`, `view.py`) and shows from a match log how the fort deformed (`shape.py`, see 2.8).
weapon_pack's armoury line is supported: flak and EMP rockets need the armoury (on Abyss on the munitions slot), shotgun and rocket are their upgrades (upgrade centre); the smoke bomb (DLC `dlc_smokebomb`, active in all matches so far) follows the armoury as in the game's own plans (Crevice-Howie, Mountain King 3v3), is treated as lobbed and assumed as tall as a turbine. **Tall devices** (`TALL`: rockets, flak, shotgun, smoke bomb; boxes 112-127 high, see 2.13) only go into storeys at least `TALL_MIN_H` (125) high. Variant options: `roof_weapons` places these devices on an open roof like a turbine (nothing above them limits their height; the highest roof first, `roof_weapon_max_y`, never on a strut that already carries a device), never in the line of fire of a weapon behind it on the same level, and keeps direct weapons from firing across such roofs; `reserve_tall` reserves the tall storeys for the tall front weapons first, the lowest first, and builds them right away (on Abyss the storey above the reactor is the way up the starting fort; left for later, the top roof and the mines were not reachable). A node that cannot be built within 150 of a built neighbour is no longer built from farther away: the cell waits until a neighbouring cell is built.
Abyss map rules for the cliff ledge left of the tower (y=-750), following the game's Abyss-1: `found_from_below` builds a foundation from the storey below first, else diagonally from above, never straight down (the front ledge node (-2199,-746) is 154 from the node below, beyond the 150 limit, so it comes diagonally from the roof node (-2100,-846), as Abyss-1 builds its other ledge foundations); `no_build_from_found` builds nodes above the ground from other nodes rather than from foundations, so the roof nodes go along the roof; `rock_clear` (30) keeps every other new node at least that far from the rock (closer grid points become foundations or are dropped; `validate()` reports violations). Abyss-2..5 were regenerated with these rules (devices unchanged).
Abyss-5 (rockets): the Abyss-4 shape; the EMP rockets/rockets in the two tall front storeys (x -1800..-1700 floor -250, 142 high; x -2000..-1900 floor -95, 155 high), one smoke bomb and one flak/shotgun on the top roof next to the three turbines, the other two on the roof at y=-502. The Abyss rows are fixed by the starting fort (storeys 100-155 high), so only these two front storeys are tall enough. Not yet tested in a match.
Optional per-map rules (used for Vanilla, following the Steam guide "How to be a PRO at Vanilla Forts"):
- `require_support`: cells that would hang in the air (beyond a cliff edge) are dropped; a cell needs both bottom corners held (original node, foundation or top of a supported cell) or must be a short bridge (`max_bridge`, default 3 cells) between held nodes.
- `crossbrace_y`: cells at or below this height get both diagonals (|X|). With `crossbrace_late_y`, only cells at or below that height get the second diagonal right away; the others get it in a final pass after all devices, so weapons are not delayed by extra wood. Cells from `crossbrace_now_x` forward (the front weapon column) are always crossbraced right away.
- `bottom_up`: remaining cells are built from the bottom up.
- `light_roof`: no armour roof; doors only over mortars.
- `use_eco_slots`: batteries/stores go on the proven slots of the original plan (`eco_slots`) first; `eco_no_ground`: never on the ground row.
- `cols_upper` / `upper_y`: from node row `upper_y` upwards the grid uses other column positions (cells take the columns of their bottom row). Vanilla follows the starting fort's roof posts (-3093, -2945) like the game's Template-1, so the weapon column is one 155-wide cell and no node stands mid-span on the roof beam; heavy weapons stand near the back post (`large_t` 0.2).
- `support_struts`: extra solid struts built as soon as both end nodes exist (currently unused). `validate()` also rejects new nodes more than 150 from their source (StandardMaxLength).
- `large_cells`: explicit cells for the large weapons in plan order, `(left x, floor y, LinkT)`; the cells between such a weapon and the front of its storey become its fire lane (`mark_large`).
- `crossbrace_large`: the cells of a large weapon and the cells below it (down to the turbine row) are crossbraced right away; the sandbag strut in the split cell is solid bracing.
- `roof_turbine_t`: LinkT positions of turbines on one roof cell (default one at 0.5). Two side by side on a 100-wide cell failed in a test match (CS_OCCUPIED), so Vanilla uses one per cell. `turbine_roof_max_y`: turbines only on roofs this high or higher (Vanilla: the tower roof, y=-295, see the wind rule in 2.13). `reserve_mortar`: mortars take their top cells before the turbines take the roofs.
- `clear_fire_lines`: final pass, struts that would block a weapon's line of fire become background bracing (armour becomes a door); `mortar_open_arc`: mortars only where no other cell is in their arc (`rules.MORTAR_ARC`, 300 forward and 520 up, so a mortar on a low roof behind the tower is rejected).
- `turbine_min_w`: no turbines on narrower cells or above large weapons.
- `woodspam`: cheap, dense wooden layers, two layers 40 apart. Material per storey: background bracing in front of direct-fire weapons (they shoot through it, `MinFireClearance`; solid woodspam blocked our own cannon and snipers in a test match; the weapon itself is protected by a metal door, which the AI opens to fire) and in turbine rows (wind); foreground bracing (`material`) only where it protects something that does not fire through it (e.g. a mortar storey). `finalise_woodspam` sets each strut's final material and builds it once (the minimum strut length is 37.5) with posts and X-diagonals in front of the weapon column's door wall, over the rock; build step `defence` / `woodspam`, once after the main weapons and again late (idempotent, completes new storeys).
- `turbine_floor_y`: turbines stand on the floor of the storey at this height (turbine gallery) before roofs are used. `turbine_row_open`: that storey contains only background bracing (posts, diagonals, outer edges), so the wind can blow through; no weapons or eco devices there. `split_cell`/`sandbag_slots`: the front cell of the turbine row is split at half height by a background-bracing strut (no full-height posts), with two sandbags side by side on that strut (build step `defence`, last in the plan: if the strut cannot carry them, nothing else is blocked).
- With `require_support`, each cell also records the cells it rests on (the shallowest support); they are always built first, so nothing hangs in the air while the fort is under construction (`validate()` checks the build order). `turbine_cheap_first`: turbines go on the roof that needs the fewest unbuilt cells.

Vanilla-3/-4/-5 (25.10.2026): the roof turbines stand in a hidden cage, a 130-high storey of background bracing on the tower roof (rows ending at -500 for Vanilla-3/-4, -425 for Vanilla-5), whose front cell (x -3100..-2945) holds two stacked sandbags in front of the turbines, placed right after the first turbine; that cell held a turbine, so Vanilla-3/-4 have two turbines (the seam column refuses them, `turbine_avoid` now also for floor turbines) and Vanilla-5 three, all upgraded late (Vanilla-3/-4 now build an upgrade centre for it, with storage and anti-air in between). The first turbine comes as early as before (after 152-162 struts, the cage is left out of `tower_connect`); the sandbags' cell costs ~23 struts. Test match 25.10.2026 (Vanilla-3, against a player, aborted at 680 s): workshop 5 s, munitions plant 65 s, first 20mm placed 155 s (built 225 s), cage turbines 268 and 359 s, both cage sandbags 314-316 s, upgrade centre 414 s with store, battery and a machine gun while it built, both turbines upgraded 454-455 s, second 20mm 478 s; 126 20mm shots; energy ended at ~10,500 (two upgraded turbines are enough there), metal was short until late. Vanilla-5's laser had needed four plain turbines (three upgraded ones yield 202 instead of 180): not yet tested. The Vanilla variants share one shape: a back block on the ground (x -3600..-3100, back to the rock edge) up to the starting fort's roof height (y=205), and a solid, fully X-braced weapon tower (x -3400..-2945, five storeys up to y=-295) on the back block and the starting fort's roof posts; weapon column at the front, the prow beyond the cliff edge carries two light storeys. Vanilla-2 differs (sniper and mortar rush, 24.10.2026): no tall tower; two storeys over the starting fort's roof and the back block (x -3500..-2845; the first one solid, the second one hidden behind background bracing), with a two-storey deck on the starting fort's roof (the front column x -3100..-2945 on its roof posts, and the prow). Its second storey (y 105..-25, 130 high: the variant's rows are 205, 105, -25; 135 would make the 155-wide nest cell's diagonal longer than `MAX_LINK`) is a hidden mortar nest: its floor over the front column is built in two halves through a node at x -3022 (`split_edges`, braced down to the starting fort's roof posts with background bracing), one mortar on each half (`mortar_slots`, at their outer ends, LinkT 0.25 and 0.75: 116 apart); the prow's nest cell is split at half height (`split_cell`) and carries two stacked sandbags (`sandbag_slots`, at y 105 and 40, LinkT 0.7) in front of both mortars against sniper fire; everything else in the nest above its floor (posts, diagonals, roof) background bracing (`hidden_box`), through which the enemy cannot see and the mortar shells pass (the built-in AI checks only the terrain for lobbed weapons, `TargetObstructed`, so the nest does not stop it firing). The nest's sandbags (0 metal / 300 energy) come before the mortars, while the workshop builds (placed after them, both mortars were destroyed 3-5 s later by the player's machine-gun fire through the nest). The sniper stands in the front column on the starting fort's roof beam (-3093,205)-(-2945,206), like Template-2's sniper, and fires through the prow storey (it holds the starting fort's machine gun, door in front; the post between them is recessed by the game when the sniper is placed); `weapon_cells` (`cfg`: `(left x, floor y, device)`) gives it that cell, which is not at the front. The mortars in the tower's top cells had waited for the whole storey-by-storey tower (sniper after 165 struts, mortars after 175-183); now the sniper comes after 14 struts, both mortars after 19 and the sandbags after 33. Behind the nest, on the same hidden storey (`hidden_box` x -3500..-2845), the turbine gallery: three turbines on the floor (`turbine_floor_y` 105, x -3500..-3200), its front cell (x -3200..-3100, next to the nest) split for two more stacked sandbags directly in front of the turbines (`split_cell` takes a list, `sandbag_slots` entries `(split cell index, slot, LinkT)`). Order: the armour sale (`rebrace`) and the workshop at once (the prow storey the sniper fires through stays a fire lane with a door and background diagonals, `lane_cells`), the sniper and the deck while the workshop builds (60 s), the mortars as soon as it is finished, the nest's sandbags, the first turbine, the gallery's sandbags, a machine gun on the gallery roof (anti-air, as soon as that roof stands), two more turbines, then the upgrade centre and, while it builds (60 s; every upgrade waits for it, and the AI waits on a planned upgrade without moving on: in a test match the heavy mortars came 52 s after the upgrade centre was placed, with only a battery in between), a mine, a battery, a store and the second machine gun on the gallery roof. Late game, in this order: both mortars upgraded to heavy mortars, the sniper upgraded to the AP sniper, then miniguns (both machine guns on the gallery roof, `roof_weapons` with `roof_weapon_cells` x -3200 and -3400 at y -25, both upgraded), then woodspam (two layers, x -2805 and -2765, in front of the starting fort's prow below the deck, y 205..310, in front of the reactor; foreground bracing, `outside` since no grid cell stands behind that band), then the turbine and mine upgrades. Woodspam stays out of the hidden storey: there it stood 460-600 in front of the two front gallery turbines at their hub height and blocked their front-side wind completely. The AI upgrades whatever device stands on the planned strut (`GetDeviceIdOnPlatform`), so a plan can also upgrade a starting-fort device, and it can sell one (`DESTROY_DEVICE`, as the game's Abyss-1 does) to free its strut. No third mortar: the low fort has no free top cell with an open arc. Without the late block the plan had ended at ~390 s and the AI would only have repaired. The roof turbines of the five-storey tower had waited for the whole back block (first turbine after 163 struts, ~9,700 energy in struts: storeys above the second wait for the first two over the full width, `tower_connect`); in the gallery the first turbine comes after 92 struts (~5,500 energy). With the gallery's front cell holding the sandbags, the turbines need the back block below them; a turbine in that cell itself (hanging on the starting fort's back posts, `support_cheapest`) would come after 63 struts, with only the nest's sandbags in front of it. Wind (`rules.wind_rays`): the back side is open (100%), the front side 36-73% clear (the downward rays meet the solid storey below and the deck), so the middle turbine gets a one-sided warning; how much a turbine with one-sided wind yields is not known. Economy model: sniper at ~12 s, mortars at ~63 s and ~70 s, sandbags ~99 s (metal-limited; mortar cells under door roofs would have cost ~700 metal more for doors and armour). First test match (25.10.2026, difficulty 1, the version with the sniper in the first prow storey): workshop placed at 5 s, the mortars at 65 and 71 s (built 90 and 96 s, firing before 110 s, faster than the model); the sniper was refused (`CS_UNSTABLE` at 5 s, `CS_OCCUPIED` later) on the prow's roof strut (first blamed on the starting fort's machine gun, which in fact stands on the lower front). The refused sniper cost no time, the AI moved on and waited for the workshop. Second test (same day, the sniper in a second prow storey with a mortar on its roof): mortars placed at 65 and 66 s, the sniper refused again (`CS_OCCUPIED`, then `CS_UNSTABLE` on the second storey's floor). Both refusals were on the prow, which hangs over the cliff, as was the early sniper on the starting fort's front post in Vanilla-3/-4; the sniper now stands behind the prow, on the roof beam over the reactor. Third test (same day, sniper on the roof beam, mortars on the open deck roof): sniper placed at 9 s (built 29 s), mortars at 65 and 66 s (built 90 and 91 s), both fired; no build errors. Energy then dropped to 130-300 (each mortar shot 200 energy, the first turbine needs the whole tower). The sniper rarely fired: its ray mostly ended on the armour of the enemy's front (`FIRETRY ... RAY_HIT_STRUCTURE`), so the built-in AI held fire. The open-roof mortars could be seen and sniped by the player, hence the hidden, sandbagged nest. Fourth test (same day, sandbags planned on the mortars' own struts at LinkT 0.8, mortars at 0.3): the sandbags were placed at 15-16 s and took both struts, no mortar was placed (the game allows one device per strut); now each device has its own strut. Fifth test (same day, 100-high nest, sandbags before the mortars): the lower sandbags were placed at 22 s, the upper ones (strut at y 55) refused with `CS_OBSTRUCTION`, then `CS_UNSTABLE` (a sandbag's box is 51 high, each half of the cell 50); the first mortar was placed at 71 s, the second (its strut sharing a node with the sandbags' and the first mortar's) refused with `CS_UNSTABLE`, while the prow's nest leaned ~25 forward. Now the nest is 125 high and the mortars come before the sandbags. Sixth test (same day): both sandbags placed (87 and 89 s, the upper one after one `CS_OBSTRUCTION`), the first mortar at 65 s (fired regularly through the nest), the second again refused (`CS_UNSTABLE`, later `CS_OCCUPIED`). The two mortars stood 77 apart (LinkT 0.5 on each half); the game's own plans space mortars 91-122 apart, and 127 apart both were placed in the third test. Now 116 apart. Seventh test (same day): sniper at 11 s, both mortars at 65 and 66 s (built 90 and 91 s), both sandbags at 76 and 77 s, no build errors; both mortars fired regularly through the nest (the AI's ray sometimes ended on the own sandbags or the other mortar, the next try fired). Energy then ran down to 2-20 between shots (each 200 energy, one roof turbine by 210 s): energy is now the limit, hence the turbine gallery. Eighth test (same day, difficulty 1, against the player): the AI won at 390 s without losing a device (it destroyed 7 machine guns, the reactor, a turbine, a battery, a store, a repair station and sandbags). Sniper 11 s, mortars 65-66 s, nest sandbags 76-77 s, first gallery turbine 141 s, the other two 199-202 s; energy stayed at 1500-7500 from 100 s on and the mortars fired 41 times without waiting for energy (metal became the limit, 17-100 late in the match). The gallery's lower sandbags, 70 from the first mortar at the same height, were refused (`CS_OBSTRUCTION`, then `CS_UNSTABLE`); the upper ones (y 40) were placed. Now at x -3170 (90 from the mortar), the gallery turbines at LinkT 0.35 (`turbine_floor_t`; x -3465, -3365, -3265). The `UNSTABLE` line's `sag` and `strain` values are not usable for these team-2 matches: every node, also untouched starting-fort nodes, showed 80-120 off its plan position. Variant options for this: `roof_weapons = {"mortar"}` with `roof_weapon_low_first` (the lowest roof with an open arc first; `mortar_open_arc` applies to roof mortars too), `small_low_first` (the sniper in the lowest front cell) and `weapon_pick_best` (no random pick among the best two cells). The tower roof carries the turbines (one per cell, nothing resting on them) and, in Vanilla-2, the mortars: it is the only height where the wind reaches a turbine from both sides (on the back block's roof the tower blocked the wind on the right of every turbine). (An open turbine storey under the weapons was the breaking point in a test match: one hit dropped the whole upper block.) They open as in design rule 4 of 2.13 (Vanilla-2: the sniper and mortar rush; Vanilla-3: the 20mm rush; the others: mine, workshop, roof turbine, machine gun, mine), end with a late-game block (more anti-air, weapons, upgrades, storage) so the AI does not sit idle at the storage cap, and assume `weapon_pack` is installed (all players use it): cannons and 20mm cannons need the munitions plant (`prereq` override, munitions slot taken from weapon_pack's own plan ToGWM2). Each variant has its own main weapon, so the player meets a different challenge: Vanilla-2 mortars, Vanilla-3 two 20mm cannons, Vanilla-4 two cannons (both with the munitions plant), Vanilla-5 a laser (factory; all four turbines, an extra store and batteries before the laser, then turbine upgrades from an upgrade centre on the munitions slot, since the factory takes the usual upgrade slot). Large weapons are reserved first (`reserve_large`) and placed in the two storeys below the top one (`large_top_min`/`large_top_max`: cell tops y=-195 and -95); the top storey gets a sniper and its roof a turbine. The two-heavy-weapon variants (Vanilla-3, -4) place them like weapon_pack's own ToGWM2 (`large_cells`): the first on the 100-wide cell x -3200..-3100 (floor 5), the second a column back (x -3300..-3200), both at LinkT 0.75, behind the 155-wide front cells; those cells are their fire lanes (`mark_large`: no device, background diagonals, door in the front wall). Test matches 24.10.2026: the first cannon was built and fired both times; the second, one column back (x -3300..-3200) a storey higher (floor -95, as in ToGWM2) or lower (floor 105), was refused with `CS_UNSTABLE` both times (strut stress <= 0.27). That column is the seam where the back part of the tower (built up from the back block, which tips into the reactor gap) meets the front part (on the starting fort): the back part leaned 25-30 further forward, so the cells between x -3300 and -3200 were squeezed by about a quarter; the roof turbine on that column was refused in every test too. With the second heavy weapon directly above the first (x -3200..-3100, floor -95), it was refused too, and the `STRESS` line showed why there: the engine had turned its floor and the posts beside the first cannon into background bracing, although the plan built them solid. The game turns foreground struts a device overlaps into background bracing, on which nothing can be placed: at LinkT 0.75 the cannon's body (18 in front of its mount) crosses the post at x -3100, and its box (~90 high) reaches the floor 100 above once the nodes sag unevenly. The cannon storeys of Vanilla-3/-4 are therefore 125 high (`cfg` overrides `rows`, shape, woodspam rows and `turbine_roof_max_y`); the sniper storey below them (front column, floor 105) too, after a sniper there was refused with `CS_UNSTABLE` in both tests with 100-high storeys: rows 205, 105, -20, -145, -270, -370 (tower roof), the cannons at floors -20 and -145, the 155x125 cells with 199-long diagonals (`MAX_LINK` 205; the game allows `StandardMaxLinkLength` 218). Test match 24.10.2026: the AI's own fort collapsed at 7.8 min without enemy fire: the starting fort's prow (it hangs over the cliff) carried the front, its armour chain reached 0.97 of its breaking limit (`STRESS` top) after the first cannon (120 mass, LinkT 0.75) was placed. Vanilla-3/-4 therefore have no prow storeys and no woodspam base on the prow, and the cannons stand at LinkT 0.5. Test matches 24.10.2026: both heavy weapons were built and fired in Vanilla-4 (cannons) and Vanilla-3 (20mm, 54 shots), the fort stayed stable (prow stress 0.42-0.53 instead of 0.75-0.97). Still refused with `CS_UNSTABLE`: a sniper in the front column early in the build, and the turbine on the roof cell x -3300..-3200. The sniper (front cell x -3100..-2945 on the starting fort's front post, floor 105) was refused in all three test matches of 24.10.2026 too, and the AI gave up on it after 120 s; `weapon_avoid` (`cfg`: cells `(left x, floor y, devices)` that these weapons skip) now keeps snipers out of that cell in Vanilla-3/-4 (and VanillaLong-3/-4), so the sniper swaps places with the machine gun on the tower's top front cell (floor -270), and the machine gun takes the low cell late in the build. Test match the same evening: the sniper was built at once, the machine gun in the low cell too; the plan finished at 445 s with every device except the roof turbine on the seam column (refused three times, the AI gave up after 120 s). `turbine_avoid` (`cfg`: roofs `(left x, roof y)` that turbines skip) now leaves that roof without a turbine: Vanilla-3/-4 (and VanillaLong-3/-4) have three roof turbines, which the test match showed is enough for the munitions plant and both heavy weapons. Build order of the tower (all Vanilla variants, `tower_connect` in the map config): the tower stands on two foundations, the back block and the starting fort. Built column by column, its front part went up to the roof alone (for the first turbine), the back part followed and the seam column between them came last, so the two parts leaned apart. Now the cells above y=205 are built storey by storey: a cell in storey k (1 = lowest) waits for every tower cell in storeys 1..max(2, k-2) (`connect_tower`, added to the cell dependencies), so both parts are joined over two storeys before anything higher is built and never rise more than two storeys above the joined part. Cost: the back block comes first, so the first turbine and the first weapon follow about 155-170 struts instead of about 31. Test match 24.10.2026 (Vanilla-3): first turbine at 161 s instead of 58 s, but the plan was finished at 475 s instead of 445 s; both 20mm cannons and three turbines were built; the sniper on the top front cell (floor -270), placed easily on the lone front column before, was refused with `CS_UNSTABLE` (strain only up to 1.02) once the whole tower stood below it, and the AI gave up on it; the lower tower storeys leaned forward less (rough `SHAPE` averages, the snapshots are noisy). To start faster, every Vanilla variant now opens with the mine under the starting fort (x -3029), the workshop (on the starting fort, no tower needed), the first roof turbine, the anti-air machine gun and then the second mine (x -3412; the third, x -3539, stays later). A match with both mines first (`mine, mine, turbine`) had plenty of metal but ran short of energy (200-600 instead of 1200-2300 at 40-120 s), so the first turbine was no earlier (170 s); the later devices came 12-32 s earlier and the plan was finished at 400 s instead of 475 s (the wood struts in front of the reactor held; the top sniper was refused again). Test match with the current opening: workshop at 71 s (was 238 s), first turbine 174 s, machine gun 185 s, second mine 226 s; metal was short again (50-110 at 40-240 s) while energy piled up, and the plan was finished at 430 s (both 20mm cannons placed at 402-410 s; the top sniper refused again). Vanilla-3 is now a 20mm rush. Economy (game files and the `SNAP` lines): start 601 metal / 3004 energy, reactor and the two starting mines +13 metal/s and about +100 energy/s, storage 600 + 300 per store metal and 3000 + 2000 per battery energy (900 / 5000 at the start); workshop 400 m / 2000 e / 60 s, munitions plant 800 / 5000 / 90 s (needs the workshop), 20mm 600 / 4000 / 70 s (needs the munitions plant), a burst 40 m / 2000 e; wood bracing 0.1 m and 0.5 e per unit length, armour 1.8 m / 1.5 e with 0.9 m back when sold. The tech chain (60 + 90 + 70 s) sets the pace and the starting economy pays for it on time if nothing else comes first (an economy model of the plan order: first shot ~220 s instead of 445-480 s in the test matches; a mine at the start costs ~20 s, since its 2000 energy delays the workshop). Order: the inner armour layer rebuilt as wood at once (plan step `rebrace`), the workshop, the munitions plant (28 struts: its proven slot x -3400..-3300 at y 602; on the bottom floor of the column right behind the starting fort, next to the workshop, it was refused with `CS_UNSTABLE` in the first rush test without any stress or sag - its body beside the workshop, its 170-high box over the workshop's strut - and the AI gave up on it, so the 20mm failed with `CS_PREQUISITENOTMET`), a mine and a battery while it builds, the first 20mm (60 struts in all, model ~226 s; test match 24.10.2026: workshop 65 s, munitions plant placed at once and built at 155 s, the 20mm placed at 158 s and built at 228 s, as modelled, but its first shot came only at ~343 s - from 235 s on the fire control found it not available or not ready although energy and the line of fire were free, cause not yet logged: on floor 105 of the same column, a 125-high storey; its cell is closed above and nothing stands in front of it yet), then the economy, the tower and the second 20mm on floor -20 above it. That column hangs on the starting fort's back posts (about 3 struts per cell); `support_cheapest` (Vanilla-3 `cfg`) makes the generator rest each node on the support with the fewest cells below it instead of the shallowest one, which had led from column to column through the whole back block (100 struts before the cannon instead of 42). Right after the first mine rebuilds the inner metal layer in front of the reactor as wood bracing (`rebrace_after_mine`: starting-fort nodes 50-53 and 53-55, the diagonal (-2892,411)-(-2943,312) and the post (-2943,312)-(-2945,206); a `CREATE_LINK` with another material makes the game swap it, the refunded metal goes into the tower; the outer armour shell at x -2845 stays). A variant can override map settings with `cfg`. A large weapon's LinkT keeps its body inside its cell (`large_t` 0.2 in the 155-wide cell, `large_t_narrow` 0.32 in a 100-wide cell), so the cell behind it keeps solid diagonals and a solid post (`large_rear_solid`).

### 2.13 Fort building rules (lessons learned)

Everything below was learned from the game files and from test matches against the AI (Vanilla, weapon_pack,
difficulty 0.5–1, October 2026). The generator follows these rules; `tools/fortgen/rules.py` checks them
(see "Validation"). When a rule changes, update this section, the generator and `rules.py` together.

#### Game mechanics (facts)

**Materials** (`data/materials/building_materials.lua`)

| Material | Stiffness | Mass/length | Breaks below / above | Hit points | Notes |
|---|---|---|---|---|---|
| `bracing` (foreground wood) | 200000 | 0.25 | 0.90 / 1.10 | 150 | stops most shots and the wind; a device built on it turns it into background bracing |
| `backbracing` (background wood) | 200000 | 0.25 | 0.92 / 1.08 | 100 | **cannot carry devices** (`SupportsDevices = false`); most projectiles pass through it (not laser, buzzsaw, howitzer); burns |
| `armour` / `door` | 250000 | 0.5 | 0.90 / 1.10 | 400 | armour in a weapon's way is turned into a door when the weapon is placed |

- Minimum strut length 37.5 (doors 49). A new node may be at most 150 from the node it is built from
  (`StandardMaxLength`); struts between existing nodes may be up to 218 (`StandardMaxLinkLength`; the
  generator uses up to 205).
- Woodspam struts therefore cannot be closer than about 40.

**Devices** (selection box from the game files, weight). The game files give `SelectionWidth`/`SelectionHeight`
as half-extents around a centre `SelectionOffset` = (0, -SelectionHeight - 0.5): a device's box reaches
**2 × SelectionHeight above its strut** (`rules.BOX_TOP`): machine gun 81, sniper 91, mortar 61, laser 101,
20mm cannon 111, rocket/EMP rocket 112, flak/shotgun 118, cannon 121, turbine 127, munitions plant/armoury 170
(smoke bomb: packed, assumed 127). The overlap checks below still use the values as full widths.

| Device | Width × height (game values) | Mass |
|---|---|---|
| machine gun, minigun | 40 × 40 | 40 |
| sniper, AP sniper | 70 × 45 | 40 |
| mortar, heavy mortar | 40 × 30 | 60 |
| cannon | 95 × 60 | 120 |
| 20mm cannon (weapon_pack) | 90 × 55 | 100 |
| laser | 50 × 50 | 100 |
| turbine | 40 × 63 (but needs ~100 spacing) | 70 |
| battery / store | 40 × 40 | 40 / 60 |
| workshop / factory / upgrade centre | 90 × 45 | 100 |
| munitions plant / armoury (weapon_pack) | 45 × 85 | 120 |
| sandbags | 40 × 25 | 45 |
| flak, shotgun (weapon_pack) | 40 × 58.75 | |
| EMP rocket, rocket (weapon_pack) | 40 × 55.75 | |

- `weapon_pack` is always installed: cannon and 20mm cannon need the **munitions plant** (needs workshop or
  armoury; costs 800 metal and **5000 energy**); laser and firebeam need the factory. The laser also needs an
  extra store and battery and a lot of energy per shot.
- **One device per strut**: the game (and the player) cannot place a second device on a strut that carries one,
  however short the devices are (test match 25.10.2026: sandbags at LinkT 0.8 beside a mortar planned at 0.3 took
  the strut, the mortar was never placed). The game's own Abyss-1 sells its sandbags (`DESTROY_DEVICE`) before it
  puts a laser on their strut. `split_edges` builds a strut in two halves for two devices.
- **Mortar spacing**: two mortars 77 apart (on the two halves of a split strut) - the second was refused in two
  test matches (`CS_UNSTABLE`, later `CS_OCCUPIED`); the game's own plans space them 91-122 apart. Sandbags 70 from
  a mortar at the same height were refused too (`CS_OBSTRUCTION`), 89 away they were placed: devices at the same
  height need about 90 between them.
- The starting fort already has 2 mines, a battery, a store and a machine gun; their spots are occupied. The
  machine gun stands on the strut (-2996,504)-(-2895,505) of the starting fort's lower front, beside the workshop
  slot (`orig_devices`; a failed sale listed the own devices at match start: `machinegun@64-65:2949,503` for the
  mirrored team 2). Until 25.10.2026 it was assumed on the prow's roof strut (-2945,206)-(-2846,204), from a probe
  log whose machine gun there had been built by the Vanilla-3 plan; that wrong assumption moved devices off the
  prow storey and led to a needless sale in Vanilla-2 (both reverted).

**Economy** (`devices/device_list.lua`, weapon_pack, the `SNAP` lines of test matches 24.10.2026)
- Start: 601 metal, 3004 energy. Reactor and the two starting mines: +13 metal/s (reactor 5, mine 4 each) and
  about +100 energy/s; every further mine +4 metal/s and -5 energy/s; a roof turbine up to +45 energy/s.
- Storage: 600 metal + 300 per store, 3000 energy + 2000 per battery (900 / 5000 at the start).
- Costs (metal / energy / build time): mine 300 / 2000 / 30 s, turbine 200 / 800 / 20 s, battery 150 / 625 / 16 s,
  store 200 / 500 / 16 s, workshop 400 / 2000 / 60 s, munitions plant 800 / 5000 / 90 s, 20mm 600 / 4000 / 70 s,
  one 20mm burst 40 / 2000 (reload 28.8 s). Struts per unit length: wood 0.1 metal / 0.5 energy, armour
  1.8 / 1.5, door 2 / 2; selling refunds wood 0.025, armour 0.9, door 1.0 metal per length.
- Costs are paid when a device is placed, and the build times hold exactly (munitions plant placed at 65 s,
  built at 155 s; 20mm placed at 158 s, built at 228 s). The AI moves on to its next action once a device is
  placed, not when it is finished.
- The tech chain workshop -> munitions plant -> 20mm takes 60 + 90 + 70 s; the starting economy pays for it on
  time if nothing else comes first (the munitions plant needs the whole 5000 energy cap). A mine at the start
  delays the workshop (its 2000 energy); with both near mines first, metal was plentiful but energy stayed at
  200-600, so the tower (and the first roof turbine) came no earlier.

**Lines of fire**
- Every direct-fire weapon needs a clear line straight ahead (`MinFireClearance` 500–1000). Foreground struts
  in that line stop the AI from firing (test match: woodspam built after the cannon → 0 cannon shots, sniper
  shots dropped to 0 once the woodspam stood).
- When a weapon is placed, the game **recesses** foreground struts that already stand in its way within its
  `RecessionBox` (a band 200 long and only 25 high at barrel height, ahead of the weapon; machine gun only 20): bracing becomes background bracing, armour becomes a
  door. Struts built **after** the weapon, or further away, are not recessed and block it.
- Doors never block: the AI opens all doors in the way before firing (`OpenWeaponDoors`) and closes them
  afterwards. Every direct-fire weapon gets a metal door in front of it.
- **Small doors**: a door opens and closes at `DoorSpeed` 50 per second (`building_materials.lua`), so a 100-long door
  stands open ~2 s per shot, long enough for the player to snipe through it; `MinLength` 49. Only the part the shot
  passes needs to be a door: the game wants a clear corridor around the shot, ~20 to each side at the muzzle widening
  to 40 at 1000 (`FireClearanceOffsetInner/Outer`); the sniper's barrel is ~50 above its strut and 100 long, and its
  `RecessionBox` (200 x 25) starts 200 ahead, so a door closer than that must be planned. Vanilla-2 (first try):
  the sniper's door post is split (`split_edges` with `materials`): door from the strut up to y 142.5 (61.5 long,
  ~1.2 s), armour above it (37.5); the sniper moved forward on its strut (LinkT 0.7, `weapon_cells` takes a LinkT) so
  its muzzle is ~44 instead of ~74 behind the door. Test match 25.10.2026: the sniper was placed at its new
  position without errors and fired 124 shots, no clearance failures (`FIREWAIT`/`FIRETRY`): the armour above the
  door did not get in the way. Vanilla-3/-4/-5 (`split_doors`, a final pass over the plan): the front post of a
  sniper, cannon, 20mm cannon or laser is rebuilt in up to three pieces (armour, door, armour) through new nodes,
  braced with background bracing to the cell's back corners; the door is the shortest that covers the shot. Where the
  barrel is, is not certain: the door covers both the weapon file's `RecessionBox` height (machine gun 40, sniper 50,
  20mm cannon and laser 60, cannon 70 above the strut) and `rules.py`'s muzzle (0.6 of the device's height), +-12.5
  (the Vanilla-2 margin) plus ~5 degrees of aim per unit of distance beyond a muzzle 44 behind the door. Result:
  Vanilla-3 20mm doors 78 instead of 125, its sniper's door 62.5 instead of 125; the cannons (Vanilla-4) and the laser
  (Vanilla-5) keep their full doors, no split is shorter for both estimates. A new node needs a brace that does not
  pass through the box of a device in that cell (test match 25.10.2026, Vanilla-3: a brace through the sniper's spot,
  the sniper was refused, `CS_OCCUPIED` then `CS_UNSTABLE`, until the AI gave up); without one the door is not split
  (a lone node would be a hinge in a post that carries the storeys above). So Vanilla-3's sniper stands at LinkT 0.28
  (`sniper_t`), where the brace to the cell's top corner clears it; in the 100-high storeys of Vanilla-4/-5 no brace
  clears the sniper and its door stays full. Test match 25.10.2026 (Vanilla-3, aborted at 680 s): the 20mm cannons
  fired 126 shots through their 78-long doors. Machine guns
  keep full doors: they only fire anti-air here, at steep angles. Not yet tested in a match.
- The built-in AI only fires at a target whose ray from the weapon reaches an enemy device or structure
  (`FindTarget` -> `TargetObstructed`, flag `RAY_ALLIED_BG_BLOCKS`); otherwise `TryFireGun` declines without an
  error (`FIRETRY ... fired=0`, 2.4). A door that is still a wood post blocks: in two rush tests the finished 20mm
  did not fire for 2-3 minutes and fired 11 s after the post in front of it became a door. The 20mm may fire
  alone (grouping affinity `alone` = 1).
- Mortars fire steeply up and forward: the roof above them must be a door (or open) and no other part of the
  fort may stand in that arc (test match: a mortar beside the weapon tower).

**Wind:** the game tests the wind with rays from each turbine to both sides, from 25 to 600 away and within ±10°
(`devices/windturbine.lua`: `MinTestDistance`, `MaxTestDistance`, `MinWindAngle`/`MaxWindAngle`). Every material
except background bracing, shields, rope and fuse collides with the wind (`CollidesWithWind = false`); with wind
from one side only the turbine falls back to a lower minimum efficiency (`MinWindNoCrossFlow` 0.3 vs.
`MinWindCrossFlow` 0.35; the exact formula is not known). Consequence: a turbine needs open air 600 to both sides
at its own height, so a turbine beside a taller solid tower gets no wind from that side, however far back it
stands (test match: turbines inside a storey with solid posts produced almost nothing, energy stayed at
170–300; the player noticed little energy from the turbines on the back block's roof beside the tower).
Two turbines 46–54 apart on one strut failed with `CS_OCCUPIED`; the game's own plan spaces them ~100 apart.

**`CS_UNSTABLE`** (the game refuses a device; there is no flag to skip the check)
- Light devices (machine gun, turbine) usually succeed on a later try; heavy ones (laser, cannon, 20mm cannon,
  store) failed persistently. The `UNSTABLE` log line (2.8) showed: struts at the device stretched 4–7 %
  (still below their breaking limit) with the structure sagging 13–27, or the structure moving (speed 5–18)
  while under fire. The game seems to refuse heavy devices where the support is weak, well before anything
  breaks.
- Weak support that caused it: a wall standing mid-span on a straight beam (the starting fort's roof beam over
  the reactor); storeys resting on an open storey of background posts; the long floor beam of a high, narrow
  top storey.
- What worked: weapon column on the starting fort's own posts (like the game's Template-1, one 155-wide cell,
  no node mid-span), solid X-braced storeys below heavy weapons, heavy weapons near the back post
  (`LinkT` ~0.2, Template-1 uses 0.16). The cannon was then placed and fired; the 20mm cannon in the high top
  storey still failed.
- A heavy weapon on top of another weapon cell fails: a weapon cell's diagonals are background bracing (lines of
  fire), so the floor above it sags (test match, Vanilla-3: 20mm cannon in the top storey sagged 24–38, most
  stretched link the background diagonal of the 20mm cell below; the 20mm one storey lower was placed and
  fired 63 shots). Heavy weapons therefore stay out of the top storey. In a second match the 20mm one storey
  lower, again directly on the other 20mm's cell, failed the same way under fire (sag 38–49, moving).
- Background bracing is exactly as stiff and heavy as foreground bracing (it inherits `Bracing`); it only breaks
  sooner (0.92 / 1.08 instead of 0.90 / 1.10), so in a sagging weapon cell its diagonal is the first link near
  its limit (1.06 in the first match). Inside a weapon cell no solid strut is possible: the weapons aim over a
  wide range (cannon -20..30 degrees, 20mm -40..40). Putting the upper heavy weapon on solid cells one column
  back (stepped tower) did not help: there even a sniper and a correctly shaped cannon cell got `CS_UNSTABLE`
  (see "Approaches that failed").
- Probe runs (2.8, three runs on the finished Vanilla-3 fort, identical results): the check is deterministic and
  does not depend on the device's weight (sniper and 20mm cannon got the same result on 51 of 54 struts).
  Adding a device to the finished, loaded fort: refused on 80 of 84 attempts on a strut sharing a node with a
  strut that carries a device, against 38 of 144 without; the rest on sagging or tilted struts (best single
  split: sag > 40, 85 %). This is not a rule for plans: built together in plan order, devices on struts sharing
  a node are fine (the game's own plans; two turbines on one node in that match).
- Late devices in a finished tower fail where early ones on a light structure worked: the sniper on the tower's
  top front cell was placed at once on the lone front column, but refused (strain only up to 1.02) once the
  whole tower stood below it (storey-by-storey order); the roof turbine on the seam column x -3300..-3200 was
  refused in every test; the munitions plant on the bottom floor right behind the starting fort, beside the
  workshop, was refused with no stress and no sag.
- A heavy weapon's body sits 18 in front of its LinkT point (`SelectionOffset` -18 in the weapon's own frame,
  which faces left, mirrored for team 1); the laser is centred. At the generator's LinkT values the body stays
  inside its own cell, so the cell behind it needs no background bracing.

**Other build errors:** `CS_OCCUPIED` (spot taken: starting fort devices, debris, devices too close; on the first
attempt of a device it is common and harmless, the next attempt places it), `CS_OBSTRUCTION` (something in the
way; a roof turbine got it once and was placed shortly after), `CS_NODESTOOFAR` / `CS_NODESTOOCLOSE` (length
limits; for a device, `CS_NODESTOOCLOSE` meant in every probe attempt that the strut already carries a device),
`CS_INVALIDNODES` (a device on a strut of 30 degrees or more), `CS_PREQUISITENOTMET` (tech missing, e.g. cannon
without munitions plant).

**Changing a strut's material:** a `CREATE_LINK` with another material on an existing strut swaps it (selling the
old one: armour -> wood brings back 0.9 metal per length), but only once the strut is finished. On a strut still
under construction (5 s and more) it has no effect and the AI moves on without an error; its rebuild pass
corrects the material only after the plan is finished. In a Vanilla-3 test, no door and only 2 armour struts
planned right after their posts were built before the plan was done (422 s); the swaps of the old
starting-fort armour at the start worked within 5 s.

**Vanilla starting fort** (plan coordinates of the game's `ai/forts/vanilla/mid` plans, team 1, enemy to the
right; weapon_pack's ToGAF1/ToGWM2 use the same fort, shifted by -3950/-3300)
- The rock under the fort reaches from x -3600 to -2900 (top at y=700). The starting fort's prow
  (x -2945..-2845) already overhangs the cliff; anything heavier built out there tears the fort apart.
- Reactor at about (-3040, 305); roof beam from (-3093, 205) to (-2945, 206) with posts at both ends; front
  posts (-2945, 206), (-2943, 312), (-2892, 411) … down to (-2900, 700).
- Proven slots from the game's own plans: battery/store, workshop, upgrade, factory (Template-1/-2),
  munitions plant and a third workshop slot (ToGWM2); mines at x -3029, -3412, -3539 on y=700.
- The starting fort leans forward: build backwards (behind it) and upwards, not out over the cliff.
- The AI does not place a new node at its plan position but at the **current position of its source node plus
  the planned offset** (`GetAdjustedNodePosition` in `data/ai/ai.lua`; on land without rotation). A lean or
  sag of a node while building is therefore copied into every node built from it, and a strut later built
  between nodes from different paths takes their current distance as its rest length (locked-in
  deformation; the `UNSTABLE` strain values far outside 0.90..1.10 come from this). A node that lands more
  than 20 from an existing one becomes a separate node (`SnapToNode(dest, 20)`). Keep the chains of new
  nodes short and anchored in rigid structure; in the stepped Vanilla-4 (since reverted) almost every node of the tower was
  built through one chain of 14-17 nodes up a 100-wide column at the back (x -3500, built first for the first
  turbine), and the tower top was ~200 forward of its plan position after 4.6 minutes, almost without enemy
  fire. A build-only test with `SHAPE` lines confirmed it: the lean grew only while the tower was being
  built (minutes 1-3: rows above y=205 shifted +17 per storey, every node of a row by the same amount) and then
  stayed constant; nodes at row 205 were placed ~23 forward of the nodes directly below them because they
  were built sideways from the leaning column; the cannon cells' back edge (from the chain, 61-79 forward)
  and front edge (from the starting fort, +5) squeezed the 155-wide cells to 85-100, floor beams locked in
  at 42-55 % of their length, so neither cannon could be placed.

**Defence: hiding, sandbags, doors, spacing** (test matches 25.10.2026 against a player, Vanilla-2 rush; game files)
- **Background bracing hides**: the player cannot see devices behind or inside it, and projectiles, mortar shells and
  the wind pass through it; it cannot carry a device. The built-in AI checks only the terrain before firing a lobbed
  weapon (`TargetObstructed`), so mortars fire from inside a nest of background bracing (41 shots in one match).
  Direct-fire weapons fire through their own background diagonals too (sniper: 124 shots).
- **Sandbags** (0 metal / 300 energy, 30 s, box 51 high) shield what cannot shoot back (mortars, turbines) from
  sniper fire. Two stacked ones need a cell split at half height (`split_cell`) with at least 51 per half: in a
  100-high cell the upper ones were refused (`CS_OBSTRUCTION`, then `CS_UNSTABLE`), in 125-130-high cells both were
  placed. A 155-wide cell can be at most 130 high (its diagonal must stay within `MAX_LINK` 205; at 135 the cell
  was dropped).
- **One device per strut**, and **~90 between devices at the same height**: a mortar 77 from another mortar and
  sandbags 70 from a mortar were refused (`CS_UNSTABLE`/`CS_OBSTRUCTION`, later `CS_OCCUPIED`); 89-127 apart they were
  placed (the game's own plans: mortars 91-122 apart). `rules.py` checks both (mortars and turbines). Two devices
  on one 155-wide cell floor need a split floor (`split_edges`, braced to the cell below).
- **A device's body turns the solid struts it overlaps into background bracing**: the sniper's body over the post in
  front of it made that post background, so it fired through it.
- **Doors**: open and close at `DoorSpeed` 50 per second (a 125-long door ~2.5 s), the player snipes in meanwhile;
  `MinLength` 49. Barrel heights above the strut (`RecessionBox` offset of the weapon files): machine gun/minigun 40,
  sniper 50, 20mm cannon and laser 60, cannon 70; barrel length 60 (machine gun), 100 (sniper, cannons), 58
  (laser). The game wants a clear corridor around the shot (`FireClearanceOffsetInner` 20 at the muzzle to
  `FireClearanceOffsetOuter` 40 at 1000); the `RecessionBox` (200 x 25) starts 200 ahead (sniper, cannons), so a
  door closer than that must be planned. A door cut to the shot works: the Vanilla-2 sniper's 61.5-long door (instead
  of 99, muzzle 44 behind it) fired 124 shots without clearance failures (`split_doors`, 2.12).
- **Energy**: a strut costs 0.5 energy per unit length, so building the tower uses ~60 energy per second; a mortar
  shot costs 200 (reload 9 s: two mortars up to ~44 per second); a mine costs 2000. A turbine yields up to 45, an
  upgraded one 67.5 (upgrade 200 metal / 1000 energy). The roof turbines of a five-storey storey-by-storey tower
  came after ~160 struts (the storeys above the second wait for the first two over the full width, which pulls in
  the whole back block) and energy ran down to 2-20 between mortar shots; turbines on the floor of the second storey
  (Vanilla-2's gallery) came after ~92 struts and energy then stayed at 1500-7500.
- **Upgrades** need the upgrade centre *finished*; the AI waits on a planned upgrade (a test match: 52 s with only a
  battery in between). It upgrades whatever device stands on the planned strut (`GetDeviceIdOnPlatform`), also one of
  the starting fort.
- **Selling** (`DESTROY_DEVICE`, as the game's Abyss-1 sells sandbags before putting a laser on their strut; plan
  step `sell:<device>` for `orig_devices`): the mod's `DestroyDevice` wrapper tries both node orders, then the own
  device on that platform, then the one closest to the strut (2.8). The starting fort's machine gun stands on its
  lower front (-2996,504)-(-2895,505), not on the prow (a planned sale from the wrong position failed three times).
- **Woodspam is foreground wood**: within a turbine's wind rays (+-10 degrees, 600) it blocks them (in front of the
  Vanilla-2 gallery: 0% of the front-side rays clear), so it stays out of the turbines' height band.
- **Background bracing does not stop projectiles**: hidden devices are still hit by fire that passes through it
  (two mortars destroyed by machine-gun fire before their sandbags stood); sandbags (or solid struts) must stand
  before the device they shield.
- **A laser beam cuts through an unprotected wall in seconds**: the starting fort's lower front (x -2900, y
  411..700) is the AI's weak spot (lost at 451-453 s to one beam); layers of woodspam in front of it buy time.

#### Design rules (enforced by the generator for Vanilla)

1. **No overhang:** every cell needs support (both bottom corners on the starting fort, a foundation or a
   supported cell, or a short bridge). Nothing beyond the cliff except the starting fort's prow.
2. **Supports first:** a cell's supports are built before the cell (a battery cell hung sideways off the
   starting fort before its column existed and the fort collapsed after 2 minutes).
3. **Bottom up, X-braced:** cells are built from the bottom up and crossbraced; the lower storeys and the weapon
   column at once, the rest in a final pass so weapons are not delayed. The tower rises **storey by storey**
   (`tower_connect`): its back part (on the back block) and front part (on the starting fort) are joined over two
   storeys before anything higher is built, and neither rises more than two storeys above the joined part.
4. **Opening by the economy numbers** (above): Vanilla-3 rushes the 20mm (armour layer in front of the reactor
   sold, workshop, munitions plant, a mine and a battery while it builds, the 20mm; first shot ~230 s instead of
   445-480 s); Vanilla-2 rushes the sniper and two mortars (armour sold, workshop, the sniper and a low deck while
   it builds, the mortars on the deck's open roof). The other Vanilla variants open with the mine under the starting fort, the workshop (on the
   starting fort), the first roof turbine, the anti-air machine gun, then the second mine (both mines first left
   energy short). Roof turbines need the tower below them, so they cannot come first; no mine before a rush's
   workshop. Turbines before power-hungry tech in the other variants (laser).
   **Tech early, then something else:** the AI waits on a device until its tech is *finished* (workshop,
   upgrade centre, factory 60 s; munitions plant ~90 s), without an error. Build the tech early and put devices
   that do not need it (store, battery, machine gun, sniper, woodspam) between the tech and the devices that
   do (test matches 24.10.2026: with the cannon right after the munitions plant the AI waited ~1.5 min, part
   of it with metal and energy at the storage cap; Vanilla-4 now has 26 plan actions in between). The rush in Vanilla-3 is the exception: there the munitions plant follows the workshop directly, since the starting economy affords nothing else before it, and the cannon's cell, a mine and a battery fill its 90 s.
5. **Turbines on an open roof or in a hidden cage** with nothing resting on them and ~100 apart, at least as high as every solid part
   of the fort within 600 to both sides (Vanilla: the tower roof; the cage of rule 13 is background bracing, which the wind passes); never inside a storey with solid posts, and never as the floor that carries the weapons (an open turbine storey under the weapon tower was
   the breaking point: one hit dropped the whole upper block).
6. **Weapons:** direct-fire weapons at the front behind a door; struts in their line of fire are background
   bracing (or built before the weapon within its recession box); heavy weapons in solid, X-braced storeys on
   strong posts, never in the top storey of the tower; mortars on top with a door roof and an open arc (Vanilla-2:
   in a low nest of background bracing with sandbags in front of each mortar, hidden from the enemy, for its rush).
   Two heavy weapons: behind open front cells (fire lanes, as in weapon_pack's ToGWM2), one above the other in
   x -3200..-3100 at LinkT 0.5, in 125-high storeys so the lower one does not reach the floor above (the game
   turns struts a device overlaps into background bracing, which cannot carry a device); built and fired in
   both test matches (Vanilla-3, -4; Vanilla-3's rush puts them on floors 105 and -20, Vanilla-4's on -20 and
   -145). Stacked in the weapon column with 100-high storeys, the upper one failed. Cells where a device type
   failed in every test are left to other devices (`weapon_avoid`, `turbine_avoid`).
7. **Woodspam:** cheap wooden layers in front of the weapons; background bracing where it is in a line of fire
   or next to turbines, foreground bracing only where it just protects (e.g. in front of a mortar storey); never
   within a turbine's wind rays (Vanilla-2: below the deck, in front of the reactor).
8. **Devices only on solid bracing** (never on background bracing); batteries and stores on proven slots, not
   on the ground row; no strut lying on a mine site.
9. **No metal roof** (heavy); armour only where something must be protected.
10. **Keep the AI busy:** the plan ends with a late-game block (more anti-air, weapons, upgrades, storage), so
    the AI does not sit idle at the storage cap.
11. **Short node chains:** every new node is built from the built neighbour with the shortest chain to an
    anchor (a starting fort node or a foundation on the ground), then from the node directly below (a vertical
    post), then the nearest one, within 150 (`ensure_node`, `chain`). This keeps the AI's relative node
    placement from copying a lean sideways through the fort. Vanilla chains went from max 16-17 / avg 6.4-7.9
    to max 10 / avg 3.6-3.8 (10 = a column from the ground to the tower roof), Abyss from max 10 / avg 3.9-4.8
    to max 5-6 / avg 2.4-2.9; in the (failed) stepped tower the cannon cells then hung 2-3 creations from the
    starting fort's roof post instead of 15-17 from the back column, and kept their shape. `gen_fort.py` prints the chain lengths of every plan
    (`rules.node_chains`). With `support_cheapest` (Vanilla-3) a cell rests on the support with the fewest cells
    below it, so a column right behind the starting fort hangs on its back posts instead of pulling in the
    whole back block.
12. **Final material at once:** a strut is placed with its final material (door, armour, background bracing)
    when the plan would change it within `SWAP_WINDOW` (20) actions; a swap on a strut under construction has
    no effect (see "Changing a strut's material").
13. **Hide and shield what cannot shoot back** (facts above): mortars and turbines stand in a storey of background
    bracing (`hidden_box`; Vanilla-2: the mortar nest and the turbine gallery on the deck; Vanilla-3/-4/-5: a turbine
    cage on the tower roof), 130 high, each row with two stacked sandbags in its front cell (`split_cell`,
    `sandbag_slots`), right after its first device; every device on its own strut, ~90 from its neighbours at the same
    height; the cage storey is left out of `tower_connect` (`skip_floors`), so the first turbine is not delayed.
    Weapon doors only as long as the shot needs (`split_doors`; machine guns keep full doors, they fire anti-air at
    steep angles). Upgrades after the upgrade centre with devices that need no tech in between.

#### Validation (`tools/fortgen/rules.py`)

`python tools/fortgen/rules.py <plan.lua> ...` checks any plan file; `gen_fort.py` runs the same checks on every
plan it writes (`RULE ERROR` / `RULE WARN`) in addition to `validate()` (rock, lengths, build order, supports,
prerequisites). Checked:
- strut length (37.5, doors 49);
- device on background bracing (warning: the game's Template-1 records one);
- line of fire of direct-fire weapons and the arc of mortars: no foreground strut that is built after the
  weapon or lies beyond its recession box (doors are fine);
- turbine wind with the game's ray test (`wind_rays`: a side is open when at least half of its rays are clear;
  error if both sides are blocked, warning if one is) and turbine spacing (≥ 90);
- two devices on one strut (one device per strut; a `DESTROY_DEVICE` frees the strut), or devices side by side on
  neighbouring struts at the same height that overlap (a wide device near a strut end reaches over the shared node;
  widths from the table above);
- mortars at the same height closer than 90 (`MORTAR_SPACING`);
- struts lying on a mine site;
- a solid strut inside a device's box above its strut (`BOX_TOP`, the posts at the ends of its own strut excluded):
  error for tall devices (rockets, flak, shotgun, smoke bomb), warning for the others (the munitions plant, 170
  high, stood in 100-high storeys in test matches). Warnings on the current plans: the tech slots of the game's
  own plans (upgrade, factory, munitions), Vanilla-5's laser (101 in a 100-high storey) and Abyss-4's top cannon
  (121 high in the 100-high top storey, the armour roof at y=-846 crosses its box).

The generator fixes lines of fire itself (`clear_fire_lines`: blocking struts become background bracing,
armour becomes a door) and only places mortars where the arc is open (`mortar_open_arc`). All current Abyss,
Vanilla and VanillaLong plans pass without errors (warnings: only the box heights above). On the command line `rules.py` takes the enemy side
from the plan header (team 2 plans such as VanillaLong face the enemy on the left) and ignores the terrain;
`check_plan(..., terrain=...)` also lets rock block the wind rays. With terrain, every turbine on Abyss's top roof
(next to the cliff wall) gets no wind from the left; the game's own Abyss-1 puts its turbines on the same spots,
weapon_pack's ToGA1 puts some far out on the right instead (open on both sides).

#### Approaches that failed (do not repeat)

| Approach | What happened |
|---|---|
| Front column out over the cliff (no foundation) | the fort tore itself apart after 3 min |
| Cells hanging sideways before their support existed | collapse after 2 min |
| Laser plan with 2–3 turbines | laser never placed or never fired (energy 170–1500) |
| Turbines in a storey with solid posts | almost no energy |
| Open turbine storey (background posts) carrying the weapon tower | heavy weapons `CS_UNSTABLE`; one hit dropped the whole upper block |
| Lighter upper block (fewer storeys, single diagonals) on that storey | heavy weapons still `CS_UNSTABLE` |
| Sandbags on a background-bracing strut | always refused (background bracing cannot carry devices) |
| Solid woodspam in front of weapons | the AI stopped firing them |
| Weapon wall mid-span on the starting fort's roof beam (+ support strut) | door post below the cannon stretched 6–7 %, `CS_UNSTABLE` |
| Dropping a grid column for the whole map | the starting fort's lower nodes no longer snapped, plans broke |
| Two turbines per 100-wide roof cell | the second one `CS_OCCUPIED` |
| Turbines on the back block's roof beside the taller weapon tower | wind on the right blocked for every turbine (0 % of the rays clear), little energy |
| Cannons with factory as prerequisite | `CS_PREQUISITENOTMET` with weapon_pack (Abyss-4 never placed its cannons; it now builds the munitions plant on weapon_pack's ToGA1 armoury slot) |
| Foundation on the Abyss cliff ledge built straight down from the roof node above, roof node built diagonally up from that foundation (all Abyss plans since the short-chain change, 23.10.2026) | test match 24.10.2026 (Abyss-5): both refused with `CS_OBSTRUCTION`, the AI stalled for 5 minutes with full resources and never reached the armoury. The tower had sagged 15-35 by then; a node is placed at its source's current position plus the offset, so the foundation (4 above the rock) landed in the rock. Now built like the game's Abyss-1 (`found_from_below`, `no_build_from_found`, `rock_clear`, see 2.12) |
| Heavy weapon directly on another weapon cell (top storey, and one storey lower under fire) | floor sagged 24–49, `CS_UNSTABLE`, given up |
| Stepped tower for two heavy weapons (front column up to y=-95 for the lower one, the upper one a column back on solid cells, firing over the front roof; rear part from x -3500, Vanilla-3/-4, October 2026) | 3 test matches. Built through long node chains it leaned ~100-200 forward and squeezed the cannon cells (both cannons `CS_UNSTABLE`, fort collapsed at 8.5 min). With short node chains the cannon cells kept their shape (sag 14-24, nodes still), but both cannons and even a sniper in the top cell were still refused with `CS_UNSTABLE`, at strut stress 0.001-0.05 (`STRESS`). Cause unknown; reverted to the straight tower. |
| Rule check "no device on a strut that shares a node with a strut carrying a device" (from the probe, 24.10.2026) | flagged the game's own plans (Template-1/-2, Abyss-1) and devices that were built in the test match; only true for devices added to the finished, loaded fort. Not in `rules.py` |
| Early sniper on the front cell on the starting fort's front post (x -3100..-2945, floor 105) | `CS_UNSTABLE` in every match, also with a 125-high storey (strain up to 1.79 at its front node), given up after 120 s; now `weapon_avoid` (a machine gun takes the cell) |
| Roof turbine on the seam column (x -3300..-3200) | `CS_UNSTABLE` in every test, given up; now `turbine_avoid` (three roof turbines) |
| Sniper on the prow's roof strut (Vanilla-2 rush, 25.10.2026) | `CS_UNSTABLE`, then `CS_OCCUPIED`; the cause is not the starting machine gun (it stands on the lower front); the sniper now stands on the roof beam behind the prow |
| Woodspam in front of the hidden storey with the turbines (Vanilla-2 late game, 25.10.2026, plan only) | at their hub height 460-600 ahead: the front-side wind of two turbines blocked completely (`rules.py`); now below the deck |
| A 135-high storey over a 155-wide cell (Vanilla-2 nest) | the cell's diagonal is longer than `MAX_LINK`, the generator dropped the cell (and the mortars with it); 130 is the limit |
| Planned sale of the starting machine gun from the prow's roof strut (Vanilla-2, 25.10.2026) | `DD_NOTFOUND` in three matches: it stands on the lower front; the sale is gone (it is not in the sniper's way) |
| Two mortars 77 apart on the halves of a split strut (Vanilla-2 nest, 25.10.2026) | the second refused in two matches (`CS_UNSTABLE`, later `CS_OCCUPIED`); now 116 apart, `rules.py` checks 90 |
| Two stacked sandbags in a 100-high cell split at half height (Vanilla-2 nest, 25.10.2026) | the upper ones `CS_OBSTRUCTION`, then `CS_UNSTABLE`: a sandbag's box is 51 high; now a 125-high nest (62.5 per half) |
| Sandbags and a mortar on the same strut (LinkT 0.8 and 0.3, Vanilla-2 rush, 25.10.2026) | the sandbags took the strut, no mortar was placed: one device per strut; now separate struts (`split_edges`, `split_cell`) |
| Sniper in a second prow storey, mortar on its roof (Vanilla-2 rush, 25.10.2026) | `CS_OCCUPIED`, then `CS_UNSTABLE`; the mortars were built. Now on the starting fort's roof beam behind the prow |
| Both near mines before the first turbine | metal 160-400 but energy 200-600; the first turbine was no earlier (170 s) |
| Munitions plant on the bottom floor right behind the starting fort, beside the workshop (first rush test) | `CS_UNSTABLE` without stress or sag, given up; the 20mm then failed with `CS_PREQUISITENOTMET`. It keeps its proven slot x -3400..-3300 |
| Door or armour planned a few actions after its strut (all plans until 24.10.2026) | the swap had no effect while the strut was under construction; the post in front of the rush 20mm stayed wood until the plan was finished and kept it from firing. Now `SWAP_WINDOW` |
| Support by the shallowest chain, ties to the left (generator default) | the rush 20mm right behind the starting fort pulled in the whole back block (100 struts before it instead of 42); now `support_cheapest` for Vanilla-3 |

#### Testing a plan

- Force a plan in `ai/fortplans.lua` (`Force = { Vanilla = "fort-t1f1-Vanilla-4.lua" }`), never commit that line.
- Letting the AI build for 7–8 minutes without attacking is enough for build/stability questions (attacks mix
  damage into the diagnosis); a quit match does not count for training.
- Read the log before restarting Forts (it is overwritten on start; `train.py collect` archives it). Look at
  `PLAN`, `BUILT`/`LOST`, `BUILD_ERROR`, `UNSTABLE`, `GAVE_UP`/`SKIPPED`, the `THINK` lines (build index,
  metal, energy) and the `shots=` of the `SNAP` lines.
- Several matches without restarting Forts land in one log: count only from the latest `PLAN` line (its
  `actions=` shows which version of the plan the game loaded; a plan file is read at match start).
- `tools/fortgen/shape.py` shows from the `SHAPE` lines where and when the fort deformed (2.8). Pass
  `--plan` with the plan file the match actually used; with a later version of the plan the node ids no longer
  match and nodes seem to jump by about 100.
- The `CREC` `LINK` lines show when each strut was built and with which material (e.g. whether a door in front
  of a weapon stands yet); `DEV`/`GDEV` show when a device was placed, `BUILT` when it was finished.
- `FIREWAIT`/`FIRETRY` (2.4) show why a weapon does not fire: `ready=0` with the engine's reason (e.g.
  `FIREFAIL_BUILDING`), `queue=1` for a pending door action, `fired=0` with the ray result when the built-in AI
  declined (no target, chance or cost).
- To map where a plan's fort refuses devices, let it build in a sandbox with `Probe` set (2.8) and read the run
  with `tools/fortgen/probe.py`.
- Render plans with `render_all.py` and compare with the game's Template-1.
- Open problems:
  - What exactly makes the game refuse a device with `CS_UNSTABLE` is still not known. Known so far (facts
    above): deterministic, independent of the device's weight, more likely for a device added late next to
    loaded devices or on a sagging or tilted strut; neither shape, movement nor strut stress alone explains it.
  - The sniper on the top front cell of the storey-by-storey tower (floor -270) is refused in Vanilla-4/-5
    once the tower below it stands; in Vanilla-3 the sniper sits lower and was built (Vanilla-2 now has it on the
    prow, before the tower).
  - Vanilla-2 (sniper and mortar rush, hidden nest and gallery, 12 test matches 25.10.2026): the current plan builds
    the sniper at 11 s, the mortars at 65-66 s, the nest sandbags at 84-86 s, the first turbine at ~142 s, the
    upgrades in order after the upgrade centre, all four sandbags, and won every match it played to the end (against
    a player at difficulty 1 at 390 and 568 s without losing a device, against an idle player at 190 s). Not yet
    tested: whether the sandbags stop the player's snipers, and the late block's woodspam below the deck (its load
    on the prow). Thirteenth test (25.10.2026, against a player who built a sniper, machine guns (504 shots), an
    armoury, a factory and a laser at ~355 s): **the player won at 453 s**. The AI's sniper was destroyed at 50 s
    (rebuilt 63 s); both mortars were destroyed 3-5 s after they were placed (65-66 s), before their sandbags (78-80 s):
    the hidden nest does not stop machine-gun fire (background bracing lets projectiles through), only sandbags do,
    so the sandbags must come before the mortars (the spacing that once refused the second mortar is fixed, 89-90
    apart worked). Rebuilt at 82-83 s behind the sandbags they survived and fired 63 times, upgrades and miniguns as
    planned; kills: a machine gun, a turbine, sandbags. The end: one laser beam at ~451 s cut through the starting
    fort's lower front (first strut lost: the armour at x -2900, y 512..606 of the starting fort) and the whole
    starting fort with the reactor collapsed within 2 s; nothing protected the lower front. Now: the nest's sandbags
    before the mortars, and early (right after the gallery's sandbags, ~145 struts) a second woodspam region: two
    layers (x -2852/-2812) hanging in front of the starting fort's lower face (y 411..700; the rock ends at the face),
    foreground bracing except the band 411..505 in front of the starting machine gun (`woodspam` takes a list of
    regions, plan step `woodspam:<k>`; `outside` takes a material per band; wall nodes outside the grid are found
    among the starting fort's nodes). Not yet tested.
  - The `UNSTABLE` diagnostics (`sag`, `strain`) compare with wrong plan positions in team-2 matches with a
    shifted game plan (`shift=-3950,-3300`): all nodes appear 80-120 off.
  - Vanilla-3/-4/-5: the turbine cage, its sandbags and the 20mm doors worked in a Vanilla-3 match (energy plenty);
    Vanilla-3's sniper at LinkT 0.28 behind its split door, Vanilla-4's cannons and Vanilla-5's laser with three
    upgraded turbines are not yet tested. The cannons' and the laser's doors stay full until a test shows where their
    barrel is. In that match one armour piece of a 20mm door post (47 long, y 27..-20) was refused with
    `CS_NODESTOOCLOSE` (as a link between existing nodes) and given up; cause unknown, the other door's identical piece
    was built.
  - The AI is not yet able to beat a human who builds heavy weapons by ~6 minutes at difficulty 1; the 20mm rush
    (first shot ~230 s) has not yet been tested against a human.

---

## 3. Architecture

```
fort-9000/
├── mod.lua                 Mod manifest
├── displayname.lua         Display name (EN/DE)
├── script.lua              Recorder (mod script, always runs)
├── ai/
│   ├── ai.lua              AI extension (runs AFTER data/ai/ai.lua)
│   ├── strategy.lua        Trained parameters (generated by train.py)
│   ├── strategy_previous.lua   Previous version
│   └── fortplans.lua       Maps, plan lists, per-map strategies
├── fortplans/<Map>/        Custom build plan variants
└── tools/
    ├── train.py / train.bat    Collect + train
    ├── fortgen/                Plan generator, rule checks (rules.py) and utilities
    ├── tests/                  Lua tests (run_tests.sh)
    ├── logs/                   Archived match logs (not in repo)
    └── _alt/                   Backups (not in repo)
```

### 3.1 Load order and extension principle
Forts executes the mod's `ai/ai.lua` **after** the built-in AI. The mod does not overwrite files but **wraps** functions of the built-in AI (`Load`, `OffsetFort`, `MirrorFort`, `OnWeaponFired`, `OnDeviceHit`, `OnDeviceDestroyed`, `OnGameResult`, `EnableHumanAssist`): the original function is saved, called, and extended with custom logic.

### 3.2 AI flow

```
Initialisation (dofile allowed)
  ├─ load strategy.lua, fill missing values with defaults
  ├─ load fortplans.lua
  └─ preload all custom and original plans
Game start
  ├─ OffsetFort / MirrorFort / Load → CAI_TrySwapPlan (once):
  │     identify map → merge map strategy → choose plan → shift → insert
  ├─ Load → CAI_Init, tempo, fire control, build logging, start think loop
Ongoing
  ├─ CAI_Think (every ThinkInterval s): threat decay, safety valves, targets, aggression, anti-air
  ├─ CAI_FireTick (every Fire.Interval s): fire weapons round-robin
  ├─ CAI_ProbeTick (only with Probe set, after the plan): one device attempt per Probe.Interval s
  └─ Events: OnWeaponFired / OnDeviceHit / OnDeviceDestroyed → threat, statistics
Game end
  └─ OnGameResult → [CAI] END with kills / lost / enemyShots
```

### 3.3 Training loop

```
Play match ──► users/<id>/log.txt ([CREC] + [CAI])
     ▲                      │ train.py collect (archive in tools/logs/)
     │                      ▼
strategy.lua  ◄── train.py train (reads all logs, learns from defaults)
```

Forts overwrites `log.txt` on every start, so run `train.bat` after each play session.

### 3.4 Key design rules
- **Determinism:** no wall-clock time, no `math.random`. Randomness only via `GetRandomInteger`, with fallback to `teamId`.
- **Fault tolerance:** all custom logic runs inside `pcall`; an error must not abort the match, it is logged as `[CAI] ERROR …`.
- **Configuration over code:** behaviour is controlled by `strategy.lua` (learned) and `fortplans.lua` (manual); training never modifies `fortplans.lua`.
- **Logging:** decisions use `[CAI]`, recording uses `[CREC]`.
- **Language:** code, comments, log messages and documentation are written in English.

## 4. Configuration reference

**`strategy.lua`** (excerpt): `ThinkInterval`, `ThreatWeight/Half/Decay/PerShot/PerHit/PerReactorHit`, `EarlySeconds`, `LateSeconds`, `Aggression{Early,Mid,Late}`, `AggressionExclude`, `RichMetal/RichBoost`, `PoorMetal/PoorEnergy/PoorFactor`, `IndirectThreatTypes`, `AntiAirThreatShots`, `AntiAirBoostMax`, `RebuildGiveUpSeconds`, `BuildSkipSeconds`, `BuildSkipMinMetal`, `Fire{…}`, `Tempo{…}`, `TargetValue{Heavy,Small}`.

**`fortplans.lua`:** per map `Originals` (file names relative to `OriginalsDir`, or full paths), `OriginalsDir`, `ReactorsPerSide`, `Plans`, `Strategy`; global `Force` (force a plan, for testing) and `Probe` (CS_UNSTABLE probe, 2.8: `At`, `Devices`, `LinkT`, `Materials`, `MaxAngle`, `Interval`, `Hold`, `Max`, `Box`; for testing, never commit it switched on).

## 5. Installation and usage

1. Copy the `fort-9000` folder to `<Steam>/steamapps/common/Forts/data/mods/`.
2. Enable the mod *FORT 9000 (AI + Recorder)* in the game.
3. Play matches or watch replays.
4. Run `tools/train.bat` (requires Python 3) – updates `ai/strategy.lua`.
5. Tests: `tools/tests/run_tests.sh` (Lua, via `LuaPlusC.exe`).

## 6. Known limitations

- Plans only for Abyss, Vanilla and VanillaLong.
- Training learns from few matches (currently 11); `--strength` limits the deviation.
- Assumes 25 frames per second for the game phases in training.
