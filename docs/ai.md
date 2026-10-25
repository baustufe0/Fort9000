# FORT 9000 – AI

## Adaptive target selection

The priority lists of the built-in AI (`HeavyArmsPriorities`, `SmallArmsPriorities`) are re-sorted every `ThinkInterval` seconds.
Score per device type = base value (`Strategy.TargetValue`) + threat bonus.
Threat rises when an enemy weapon fires (`ThreatPerShot`), hits us (`ThreatPerHit`) or hits the reactor (`ThreatPerReactorHit`), and decays continuously (`ThreatDecay`). The bonus saturates: `ThreatWeight · T / (T + ThreatHalf)`. When an enemy weapon is destroyed, its threat drops to 70 %.

## Aggression by game phase and economy

- Phases: Early (< `EarlySeconds`), Mid, Late (from `LateSeconds`), each with its own factor.
- Plenty of metal (`RichMetal`) → factor × `RichBoost`; low metal/energy (`PoorMetal`, `PoorEnergy`) → factor × `PoorFactor`.
- Applied to `OffensiveFireProbability` (machine guns are excluded via `AggressionExclude`).

## Anti-air by incoming fire pressure

Counts enemy shots from mortars and missiles (`IndirectThreatTypes`). The more there are, the more `AntiAirFireProbability` is raised (up to `AntiAirBoostMax`).

## Fire control

The built-in AI only fires during build pauses and at most one weapon per cycle. FORT 9000 sets `HardThreshold = 0` (always ready to attack), raises the fire probability while building (`RebuildFireFactor`), and fires on its own timer (`Fire.Interval`), cycling through up to `WeaponsPerTick` ready weapons. Weapon types in `Fire.NoOffence` (default: the plain machine gun; the upgraded minigun is a separate type and keeps firing at the fort) never fire at the enemy fort (offensive and rebuild fire probability 0; they do little damage there and stay anti-air); the fire timer skips them without using up a turn, so snipers and other weapons fire instead.
**Smoke before rockets** (`Fire.SmokeCover`): rockets and EMP rockets are projectiles the enemy anti-air shoots down. While the team has a smoke launcher (`smokebomb`, `smokebomb2`), a rocket only fires from `MinDelay` (2 s) to `Window` (10 s) after one of the team's own smoke shells was fired (`OnWeaponFired`, timed in game seconds by the fire timer). When a rocket is ready without smoke, the fire timer fires a ready smoke launcher first; under smoke the ready rockets fire before the other weapons. `TryFireGun` is wrapped, so the built-in AI's own rocket shots are held the same way (a group that is already firing is not interrupted). Held rockets do not use up turns. After `MaxHold` (30 s) without smoke (launcher destroyed, reloading, no target or no energy) the rockets fire anyway (`SMOKE_TIMEOUT` in the log). Without a smoke launcher nothing changes. The timings are first guesses (the smoke bomb is a packed DLC weapon, its shell's flight time and cloud duration are not readable).
**Fire diagnostics:** the fire timer logs why an offence weapon did not fire, at most one line per weapon every `CAI_FIREWAIT_EVERY` (30) seconds and at once when the reason changes: `FIREWAIT <type> <id> avail=<0|1> ready=<0|1> code=<FIREFAIL name|-> queue=<0|1> m= e=` when it is skipped (not available, not ready to fire with the engine's reason, or an action such as opening doors pending), `FIRETRY <type> <id> fired=<0|1> code= [ray=<hit>:<side>:<material>@<x>,<y>] m= e=` after `TryFireGun` (fired = no longer ready, i.e. reloading; `fired=0`: the built-in AI declined - no target, chance or cost; `ray` = what the targeting ray towards the enemy reactor hits first, cast with the flags of the built-in `TargetObstructed`, in which the team's own background bracing blocks the ray).

## Build tempo by difficulty

Update period (`UpdatePeriod`) and repair period (`RepairPeriod`) are interpolated linearly between Easy / Normal / Hard. Construction and pause durations are configurable.

## Build safety valves

- **Give up rebuilds:** if a queued rebuild action is stuck for longer than `RebuildGiveUpSeconds`, it is discarded. If the AI is merely waiting for metal, the clock does not run. "Insufficient resources" only counts as waiting while metal is still rising; if metal stays flat above `BuildSkipMinMetal` for `StarvedFlatTicks` think ticks (e.g. at the storage cap, when an action costs more than can be stored), the clocks run again.
- **Skip actions:** if normal construction is stuck on one action for longer than `BuildSkipSeconds` despite enough metal (`BuildSkipMinMetal`), the action is skipped.

## Custom build plan variants per map

- Plans live in `fortplans/<Map>/` (Forts removes foreign files from `data/maps`).
- The map is identified by file name or by the signature of the game's plan (position + action count, optionally reactor count).
  Plans of other mods can be listed as originals by full path; Vanilla knows the `weapon_pack` mid plans (ToGAF1, ToGWM2).
- One plan is chosen deterministically per match (game random or `teamId`) and shifted into the coordinates of the game's plan; the game then mirrors/offsets it as usual.
- `"original"` in the plan list keeps the game's own plan.
- Supported maps: **Abyss**, **Vanilla** (mid fort, also applies to Penguin, Caverns, …), **VanillaLong** (2v2, upper platform).
- Per-map strategy overrides (`Maps[<Map>].Strategy`), e.g. a slower start on wide maps.

- How the swap works: at initialisation (the only time `dofile` is allowed) `ai/ai.lua` preloads all custom plans and
  all `Originals`. The game then calls `OffsetFort`/`MirrorFort` (adapting its plan to the real fort, using the
  FortPos of *its* plan) and `Load`; on the first call the mod identifies the map from the game's plan (FortPos +
  action count, optionally `ReactorsPerSide`), chooses a plan (`GetRandomInteger` or `Force`), shifts it by
  (FortPos of the game's plan - FortPos of the custom plan) and inserts it; the game then transforms it as usual.
  Custom plans must therefore be in the coordinate frame of the game's plan (same header).
- Template maps without their own `fort-*.lua` (Vanilla, Vanilla 2v2) use the shared folders
  `data/ai/forts/<type>/<mid|long>/` (also Penguin, Caverns, MP 1v3 2, Rhino Vs Tiger, Up & Down, ...): `OriginalsDir`
  points there and the signature applies to every map using those plans (no `ReactorsPerSide` then).
- The assist AI (team 1 with a player) has no game plan and never gets a custom plan; forts with an unknown signature
  keep their original plan.

## Assist-AI mode

If a player takes over the AI as an anti-air assistant, FORT 9000 deactivates itself and restores all changed values.

## Forts Lua environment

A Lua 5.1 sandbox: no `io`, `os`, `require`, `package`, `loadstring`, `loadfile`, `rawget`, `rawset` (avoid
metatables); `dofile` only during initialisation. Never use the identifier `L` (LuaPlus reads `L"..."` as a wide
string: syntax error). When the mod's `ai/ai.lua` runs, `teamId` and the engine functions (`CreateLink`, ...) do not
exist yet: everything engine-related happens in `Load()`. `GetMapFilename` does not exist in the AI environment.
`ScheduleCall` comes from `scripts/core.lua` (available to the AI, not to the mod's `script.lua`, which uses
`Update(frame)`); scheduled functions must be global. The built-in AI (`data/ai/ai.lua`) does one build step per
`UpdateAI`, puts failed actions into `data.Rebuild` and builds nothing new while a rebuild fails (hence the safety
valves); it attacks only in build pauses unless `difficulty >= data.HardThreshold` (0.75; the mod sets 0);
`EnableHumanAssist()` is called after `Load`.

## Architecture

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
├── SPEC.md, docs/          Specification (index, topics, maps/, history/)
└── tools/
    ├── train.py / train.bat    Collect + train
    ├── fortgen/                Plan generator, rule checks (rules.py) and utilities
    ├── tests/                  Lua tests (run_tests.sh)
    ├── logs/                   Archived match logs (not in repo)
    └── _alt/                   Backups (not in repo)
```

## Load order and extension principle

Forts executes the mod's `ai/ai.lua` **after** the built-in AI. The mod does not overwrite files but **wraps** functions of the built-in AI (`Load`, `OffsetFort`, `MirrorFort`, `OnWeaponFired`, `OnDeviceHit`, `OnDeviceDestroyed`, `OnGameResult`, `EnableHumanAssist`): the original function is saved, called, and extended with custom logic.

## AI flow

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

## Configuration reference

**`strategy.lua`** (excerpt): `ThinkInterval`, `ThreatWeight/Half/Decay/PerShot/PerHit/PerReactorHit`, `EarlySeconds`, `LateSeconds`, `Aggression{Early,Mid,Late}`, `AggressionExclude`, `RichMetal/RichBoost`, `PoorMetal/PoorEnergy/PoorFactor`, `IndirectThreatTypes`, `AntiAirThreatShots`, `AntiAirBoostMax`, `RebuildGiveUpSeconds`, `BuildSkipSeconds`, `BuildSkipMinMetal`, `Fire{…}`, `Tempo{…}`, `TargetValue{Heavy,Small}`.

**`fortplans.lua`:** per map `Originals` (file names relative to `OriginalsDir`, or full paths), `OriginalsDir`, `ReactorsPerSide`, `Plans`, `Strategy`; global `Force` (force a plan, for testing) and `Probe` (CS_UNSTABLE probe, [debugging.md](debugging.md): `At`, `Devices`, `LinkT`, `Materials`, `MaxAngle`, `Interval`, `Hold`, `Max`, `Box`; for testing, never commit it switched on).

## Installation and usage

1. Copy the `fort-9000` folder to `<Steam>/steamapps/common/Forts/data/mods/`.
2. Enable the mod *FORT 9000 (AI + Recorder)* in the game.
3. Play matches or watch replays.
4. Run `tools/train.bat` (requires Python 3) – updates `ai/strategy.lua`.
5. Tests: `tools/tests/run_tests.sh` (Lua, via `LuaPlusC.exe`).
