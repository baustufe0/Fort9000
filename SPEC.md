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
`tools/fortgen/` generates build plan variants (`gen_fort.py`), converts plans between coordinate systems (`mid_to_long.py`) and renders them as images for review (`render_all.py`, `view.py`).
Optional per-map rules (used for Vanilla, following the Steam guide "How to be a PRO at Vanilla Forts"):
- `require_support`: cells that would hang in the air (beyond a cliff edge) are dropped; a cell needs both bottom corners held (original node, foundation or top of a supported cell) or must be a short bridge (`max_bridge`, default 3 cells) between held nodes.
- `crossbrace_y`: cells at or below this height get both diagonals (|X|). With `crossbrace_late_y`, only cells at or below that height get the second diagonal right away; the others get it in a final pass after all devices, so weapons are not delayed by extra wood. Cells from `crossbrace_now_x` forward (the front weapon column) are always crossbraced right away.
- `bottom_up`: remaining cells are built from the bottom up.
- `light_roof`: no armour roof; doors only over mortars.
- `use_eco_slots`: batteries/stores go on the proven slots of the original plan (`eco_slots`) first; `eco_no_ground`: never on the ground row.
- `turbine_min_w`: no turbines on narrower cells or above large weapons.
- `turbine_floor_y`: turbines stand on the floor of the storey at this height (turbine gallery) before roofs are used. `turbine_row_open`: that storey contains only background bracing (posts, diagonals, outer edges), so the wind can blow through; no weapons or eco devices there. `split_cell`/`sandbag_slots`: the front cell of the turbine row is split at half height by a background-bracing strut (no full-height posts), with two sandbags side by side on that strut (build step `defence`; the floor below is the starting fort's top beam, which was blocked in a test match). The laser goes two storeys above the open turbine row (`large_y`), on solid storeys.
- With `require_support`, each cell also records the cells it rests on (the shallowest support); they are always built first, so nothing hangs in the air while the fort is under construction (`validate()` checks the build order). `turbine_cheap_first`: turbines go on the roof that needs the fewest unbuilt cells.

The Vanilla variants share one shape modelled on large player-built vanilla forts: a tall rectangle (back block on the ground at x -3500..-3100, six storeys over the starting fort up to y=-395), a weapon column at the front (x -3100..-3000, over the core frame; the prow beyond the cliff edge only carries two light storeys), a turbine gallery on the storey just above the starting fort and mortars on top; every cell is crossbraced (above the lower layers in a final pass). The build lists put a machine gun and a sniper right after the first mine/turbine/mine and only then the turbines that need the back block. The laser plan builds four turbines before the factory and laser (a laser shot needs a lot of energy). They start with economy (mines and turbines first), end with a late-game block (more anti-air, weapons, upgrades, storage) so the AI does not sit idle at the storage cap, and use no cannon (its prerequisite differs between the base game and `weapon_pack`); the heavy variant uses a plasma laser.

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
    ├── fortgen/                Plan generator and utilities
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
