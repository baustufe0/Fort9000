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
The built-in AI only fires during build pauses and at most one weapon per cycle. FORT 9000 sets `HardThreshold = 0` (always ready to attack), raises the fire probability while building (`RebuildFireFactor`), and fires on its own timer (`Fire.Interval`), cycling through up to `WeaponsPerTick` ready weapons.

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
- Supported maps: **Abyss**, **Vanilla** (mid fort, also applies to Penguin, Caverns, …), **VanillaLong** (2v2, upper platform).
- Per-map strategy overrides (`Maps[<Map>].Strategy`), e.g. a slower start on wide maps.

### 2.8 Debugging
Build functions (`CreateLink`, `CreateNode`, `CreateDeviceWithFlags`, `CreateGroundDevice`, `UpgradeDevice`) are hooked; failed attempts are written to the log with the error code as `BUILD_ERROR` (once per case, max. 200).
A device that fails with `CS_UNSTABLE` additionally writes `UNSTABLE <device> <nodeA>-<nodeB> N<id> sag=<distance from planned position> v=<speed> ... links=<n> strain=<min>..<max> stretched=<link> compressed=<link> action=<k>` (up to 3 samples per device and place): strain is current/planned length of all links at the two nodes (bracing breaks below 0.90 or above 1.10, background bracing below 0.92 or above 1.08); `<link>` = `N<id>(x,y)-N<id>(x,y) <planned material>` for the most stretched / most compressed link (current world positions; `start-fort` if the plan does not build it). Background bracing cannot carry devices (`SupportsDevices = false`).

### 2.9 Assist-AI mode
If a player takes over the AI as an anti-air assistant, FORT 9000 deactivates itself and restores all changed values.

### 2.10 Recorder
`script.lua` runs in every match and in replays, changes nothing in the game, and writes lines prefixed `[CREC]` to the Forts log:

| Line | Content |
|---|---|
| `START v=2` | Start |
| `SNAP s=… m=… e=… dev=… shots=…` | every 125 frames: metal, energy, devices and shots per side |
| `BUILT` / `LOST` | device completed / destroyed |
| `RESULT w=…` | winner |

### 2.11 Training
`tools/train.py` collects the logs, learns from them and rewrites `ai/strategy.lua` (previous version: `strategy_previous.lua`).
Learning always starts from the default values, so running it repeatedly shifts nothing; only new matches change the result.
It learns `TargetValue` (Heavy/Small) and `Aggression` (Early/Mid/Late). `--strength` (0..1) limits how far values may deviate from the defaults.

### 2.12 Fort generator
`tools/fortgen/` generates build plan variants (`gen_fort.py`), checks plans against the fort building rules (`rules.py`, see 2.13), converts plans between coordinate systems (`mid_to_long.py`: the VanillaLong plans are the Vanilla plans converted, `mid_to_long.py fortplans/Vanilla/fort-t1f1-Vanilla-N.lua <Forts>/data/ai/forts/vanilla/long/fort-t2f1-Template-1.lua fortplans/VanillaLong/fort-t2f3-VanillaLong-N.lua`; convert them again whenever the Vanilla plans change) and renders them as images for review (`render_all.py`, `view.py`).
Optional per-map rules (used for Vanilla, following the Steam guide "How to be a PRO at Vanilla Forts"):
- `require_support`: cells that would hang in the air (beyond a cliff edge) are dropped; a cell needs both bottom corners held (original node, foundation or top of a supported cell) or must be a short bridge (`max_bridge`, default 3 cells) between held nodes.
- `crossbrace_y`: cells at or below this height get both diagonals (|X|). With `crossbrace_late_y`, only cells at or below that height get the second diagonal right away; the others get it in a final pass after all devices, so weapons are not delayed by extra wood. Cells from `crossbrace_now_x` forward (the front weapon column) are always crossbraced right away.
- `bottom_up`: remaining cells are built from the bottom up.
- `light_roof`: no armour roof; doors only over mortars.
- `use_eco_slots`: batteries/stores go on the proven slots of the original plan (`eco_slots`) first; `eco_no_ground`: never on the ground row.
- `cols_upper` / `upper_y`: from node row `upper_y` upwards the grid uses other column positions (cells take the columns of their bottom row). Vanilla follows the starting fort's roof posts (-3093, -2945) like the game's Template-1, so the weapon column is one 155-wide cell and no node stands mid-span on the roof beam; heavy weapons stand near the back post (`large_t` 0.2).
- `support_struts`: extra solid struts built as soon as both end nodes exist (currently unused). `validate()` also rejects new nodes more than 150 from their source (StandardMaxLength).
- `crossbrace_large`: the cells of a large weapon and the cells below it (down to the turbine row) are crossbraced right away; the sandbag strut in the split cell is solid bracing.
- `roof_turbine_t`: LinkT positions of turbines on one roof cell (default one at 0.5). Two side by side on a 100-wide cell failed in a test match (CS_OCCUPIED), so Vanilla uses one per cell. `turbine_roof_max_y`: turbines only on roofs this high or higher (Vanilla: the tower roof, y=-295, see the wind rule in 2.13). `reserve_mortar`: mortars take their top cells before the turbines take the roofs.
- `clear_fire_lines`: final pass, struts that would block a weapon's line of fire become background bracing (armour becomes a door); `mortar_open_arc`: mortars only where no other cell is in their arc (`rules.MORTAR_ARC`, 300 forward and 520 up, so a mortar on a low roof behind the tower is rejected).
- `turbine_min_w`: no turbines on narrower cells or above large weapons.
- `woodspam`: cheap, dense wooden layers, two layers 40 apart. Material per storey: background bracing in front of direct-fire weapons (they shoot through it, `MinFireClearance`; solid woodspam blocked our own cannon and snipers in a test match; the weapon itself is protected by a metal door, which the AI opens to fire) and in turbine rows (wind); foreground bracing (`material`) only where it protects something that does not fire through it (e.g. a mortar storey). `finalise_woodspam` sets each strut's final material and builds it once (the minimum strut length is 37.5) with posts and X-diagonals in front of the weapon column's door wall, over the rock; build step `defence` / `woodspam`, once after the main weapons and again late (idempotent, completes new storeys).
- `turbine_floor_y`: turbines stand on the floor of the storey at this height (turbine gallery) before roofs are used. `turbine_row_open`: that storey contains only background bracing (posts, diagonals, outer edges), so the wind can blow through; no weapons or eco devices there. `split_cell`/`sandbag_slots`: the front cell of the turbine row is split at half height by a background-bracing strut (no full-height posts), with two sandbags side by side on that strut (build step `defence`, last in the plan: if the strut cannot carry them, nothing else is blocked).
- With `require_support`, each cell also records the cells it rests on (the shallowest support); they are always built first, so nothing hangs in the air while the fort is under construction (`validate()` checks the build order). `turbine_cheap_first`: turbines go on the roof that needs the fewest unbuilt cells.

The Vanilla variants share one shape: a back block on the ground (x -3600..-3100, back to the rock edge) up to the starting fort's roof height (y=205), and a solid, fully X-braced weapon tower (x -3400..-2945, five storeys up to y=-295; Vanilla-2 one column wider, from -3500) on the back block and the starting fort's roof posts; weapon column at the front, the prow beyond the cliff edge carries two light storeys. The tower roof carries the turbines (one per cell, nothing resting on them) and, in Vanilla-2, the mortars: it is the only height where the wind reaches a turbine from both sides (on the back block's roof the tower blocked the wind on the right of every turbine). (An open turbine storey under the weapons was the breaking point in a test match: one hit dropped the whole upper block.) They start with economy (mines and turbines first), end with a late-game block (more anti-air, weapons, upgrades, storage) so the AI does not sit idle at the storage cap, and assume `weapon_pack` is installed (all players use it): cannons and 20mm cannons need the munitions plant (`prereq` override, munitions slot taken from weapon_pack's own plan ToGWM2). Each variant has its own main weapon, so the player meets a different challenge: Vanilla-2 mortars, Vanilla-3 two 20mm cannons, Vanilla-4 two cannons (both with the munitions plant), Vanilla-5 a laser (factory; all four turbines, an extra store and batteries before the laser, then turbine upgrades from an upgrade centre on the munitions slot, since the factory takes the usual upgrade slot). Large weapons are reserved first (`reserve_large`) and placed in the two storeys below the top one (`large_top_min`/`large_top_max`: cell tops y=-195 and -95); the top storey gets a sniper and its roof a turbine. The two-heavy-weapon variants (Vanilla-3, -4) use a **stepped tower** (`_V_STEPPED`): the front column (x -3100..-2945, on the starting fort's roof posts) ends at y=-95 and carries the lower heavy weapon (floor 5, built first: `cfg` override `large_y` -95); the upper one stands one column back (x -3200..-3100, floor -95) on solid X-braced cells, behind its own door wall at x=-3100, and fires over the front column's roof; the rear part reaches back to x -3500, so its roof keeps four turbine slots, and the woodspam covers only the front column's storey. A variant can override map settings with `cfg`. A large weapon's LinkT keeps its body inside its cell (`large_t` 0.2 in the 155-wide cell, `large_t_narrow` 0.32 in a 100-wide cell), so the cell behind it keeps solid diagonals and a solid post (`large_rear_solid`).

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
  (`StandardMaxLength`); struts between existing nodes may be longer (the generator uses up to 195).
- Woodspam struts therefore cannot be closer than about 40.

**Devices** (selection box from the game files, weight)

| Device | Width × height | Mass |
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

- `weapon_pack` is always installed: cannon and 20mm cannon need the **munitions plant** (needs workshop or
  armoury; costs 800 metal and **5000 energy**); laser and firebeam need the factory. The laser also needs an
  extra store and battery and a lot of energy per shot.
- The starting fort already has 2 mines, a battery, a store and a machine gun; their spots are occupied.

**Lines of fire**
- Every direct-fire weapon needs a clear line straight ahead (`MinFireClearance` 500–1000). Foreground struts
  in that line stop the AI from firing (test match: woodspam built after the cannon → 0 cannon shots, sniper
  shots dropped to 0 once the woodspam stood).
- When a weapon is placed, the game **recesses** foreground struts that already stand in its way within its
  `RecessionBox` (a band 200 long and only 25 high at barrel height, ahead of the weapon; machine gun only 20): bracing becomes background bracing, armour becomes a
  door. Struts built **after** the weapon, or further away, are not recessed and block it.
- Doors never block: the AI opens all doors in the way before firing (`OpenWeaponDoors`) and closes them
  afterwards. Every direct-fire weapon gets a metal door in front of it.
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
  wide range (cannon -20..30 degrees, 20mm -40..40). What helps is not standing on such a cell: the stepped
  tower (2.12) puts the upper heavy weapon on solid X-braced cells.
- A heavy weapon's body sits 18 in front of its LinkT point (`SelectionOffset` -18 in the weapon's own frame,
  which faces left, mirrored for team 1); the laser is centred. At the generator's LinkT values the body stays
  inside its own cell, so the cell behind it needs no background bracing.

**Other build errors:** `CS_OCCUPIED` (spot taken: starting fort devices, debris, devices too close),
`CS_OBSTRUCTION` (something in the way), `CS_NODESTOOFAR` / `CS_NODESTOOCLOSE` (length limits),
`CS_PREQUISITENOTMET` (tech missing, e.g. cannon without munitions plant).

**Vanilla starting fort** (plan coordinates of the game's `ai/forts/vanilla/mid` plans, team 1, enemy to the
right; weapon_pack's ToGAF1/ToGWM2 use the same fort, shifted by -3950/-3300)
- The rock under the fort reaches from x -3600 to -2900 (top at y=700). The starting fort's prow
  (x -2945..-2845) already overhangs the cliff; anything heavier built out there tears the fort apart.
- Reactor at about (-3040, 305); roof beam from (-3093, 205) to (-2945, 206) with posts at both ends; front
  posts (-2945, 206), (-2943, 312), (-2892, 411) … down to (-2900, 700).
- Proven slots from the game's own plans: battery/store, workshop, upgrade, factory (Template-1/-2),
  munitions plant and a third workshop slot (ToGWM2); mines at x -3029, -3412, -3539 on y=700.
- The starting fort leans forward: build backwards (behind it) and upwards, not out over the cliff.

#### Design rules (enforced by the generator for Vanilla)

1. **No overhang:** every cell needs support (both bottom corners on the starting fort, a foundation or a
   supported cell, or a short bridge). Nothing beyond the cliff except the starting fort's prow.
2. **Supports first:** a cell's supports are built before the cell (a battery cell hung sideways off the
   starting fort before its column existed and the fort collapsed after 2 minutes).
3. **Bottom up, X-braced:** cells are built from the bottom up and crossbraced; the lower storeys and the weapon
   column at once, the rest in a final pass so weapons are not delayed.
4. **Economy first:** mine, turbine, mine, then a machine gun and a sniper; tech and heavy weapons later;
   turbines before power-hungry tech (munitions plant, laser).
5. **Turbines on an open roof** with nothing resting on them and ~100 apart, at least as high as every solid part
   of the fort within 600 to both sides (Vanilla: the tower roof); never inside a storey with solid posts, and never as the floor that carries the weapons (an open turbine storey under the weapon tower was
   the breaking point: one hit dropped the whole upper block).
6. **Weapons:** direct-fire weapons at the front behind a door; struts in their line of fire are background
   bracing (or built before the weapon within its recession box); heavy weapons in solid, X-braced storeys on
   strong posts, near the back post, never in the top storey of the tower and never directly on another
   weapon cell (two heavy weapons: stepped tower, the upper one a column further back, firing over the
   lower one's roof); mortars on top with a door roof and an open arc.
7. **Woodspam:** cheap wooden layers in front of the weapons; background bracing where it is in a line of fire
   or next to turbines, foreground bracing only where it just protects (e.g. in front of a mortar storey).
8. **Devices only on solid bracing** (never on background bracing); batteries and stores on proven slots, not
   on the ground row; no strut lying on a mine site.
9. **No metal roof** (heavy); armour only where something must be protected.
10. **Keep the AI busy:** the plan ends with a late-game block (more anti-air, weapons, upgrades, storage), so
    the AI does not sit idle at the storage cap.

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
- devices overlapping on one strut, or side by side on neighbouring struts at the same height (a wide device
  near a strut end reaches over the shared node; widths from the table above);
- struts lying on a mine site.

The generator fixes lines of fire itself (`clear_fire_lines`: blocking struts become background bracing,
armour becomes a door) and only places mortars where the arc is open (`mortar_open_arc`). All current Abyss,
Vanilla and VanillaLong plans pass without errors or warnings. On the command line `rules.py` takes the enemy side
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
| Heavy weapon directly on another weapon cell (top storey, and one storey lower under fire) | floor sagged 24–49, `CS_UNSTABLE`, given up |

#### Testing a plan

- Force a plan in `ai/fortplans.lua` (`Force = { Vanilla = "fort-t1f1-Vanilla-4.lua" }`), never commit that line.
- Letting the AI build for 7–8 minutes without attacking is enough for build/stability questions (attacks mix
  damage into the diagnosis); a quit match does not count for training.
- Read the log before restarting Forts (it is overwritten on start; `train.py collect` archives it). Look at
  `PLAN`, `BUILT`/`LOST`, `BUILD_ERROR`, `UNSTABLE`, `GAVE_UP`/`SKIPPED`, the `THINK` lines (build index,
  metal, energy) and the `shots=` of the `SNAP` lines.
- Render plans with `render_all.py` and compare with the game's Template-1.
- Open problem: the stepped tower (Vanilla-3, -4) and the turbines on the tower roof (exposed to fire: 5 lost
  in one match) are not yet tested enough; the AI is not yet able to beat a human who builds heavy weapons by ~6 minutes at difficulty 1.

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

**`fortplans.lua`:** per map `Originals` (file names relative to `OriginalsDir`, or full paths), `OriginalsDir`, `ReactorsPerSide`, `Plans`, `Strategy`; global `Force` (force a plan, for testing).

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
