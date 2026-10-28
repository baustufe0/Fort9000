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
**Smoke before rockets** (`Fire.SmokeCover`): rockets and EMP rockets are projectiles the enemy anti-air shoots down. While the team has a smoke launcher (`smokebomb`, `smokebomb2`), a rocket only fires from `MinDelay` (2 s) to `Window` (10 s) after one of the team's own smoke shells was fired (`OnWeaponFired`, timed in game seconds by the fire timer). When a rocket is ready without smoke, the fire timer fires a ready smoke launcher first; under smoke the ready rockets fire before the other weapons. `TryFireGun` is wrapped, so the built-in AI's own rocket shots are held the same way (a group that is already firing is not interrupted). Held rockets do not use up turns. After `MaxHold` (30 s) without smoke (launcher destroyed, reloading, no target or no energy) the rockets fire anyway (`SMOKE_TIMEOUT` in the log). A smoke launcher fires only as this cover, never on its own (the fire timer skips it, and the wrapped `TryFireGun` holds the built-in AI's own smoke shots): only when at least one rocket is ready and the team can pay for the smoke shell and every ready rocket together (`GetWeaponFireCost`, `CanAfford`, as the built-in AI checks a weapon group); otherwise it waits (`SMOKE_WAIT energy rockets=<n>` once, `SMOKE_WAIT off` when it fires again).
**Volleys** (`Fire.Volley`, default `Types = { firebeam }`, `MaxHold` 20 s): weapons of these types fire together, as
one group, at the same spot. The built-in AI fires a group (`TryFireGun(leader, group)`) at the leader's target;
weapon_pack gives firebeams no grouping affinity to each other, so without this they fire one by one at different
spots. A ready weapon of a volley type waits until every fully built one (`IsDeviceFullyBuilt`) is ready and the team
can pay for all their shots (`GetWeaponFireCost`, `CanAfford`); then the fire timer (or the built-in AI's own call,
via the wrapped `TryFireGun`) fires them as one group. After `MaxHold` seconds of waiting (partner reloading, under
repair or no energy) a weapon fires alone; with only one built, nothing changes. The fire timer starts or holds at
most one volley per tick, and the round robin skips the volley types without using up a turn. A volley skips the
built-in AI's random fire chance, as its group members do. Log: `VOLLEY <n> leader=<id> ids=<id,...> fired=<k>` (k: members no longer ready after the call; 0 when the leader found no target or the built-in AI opens doors and retries the group), `VOLLEY_HOLD
ready=<n>/<m> energy=<0|1>` (once when the wait starts or its reason changes), `VOLLEY_TIMEOUT <type> <id>
after=<s>s`. Used by Abyss-3 (27.10.2026). In its first match every volley failed with `ERROR volley: attempt to
index a number value` (the cost sum started at the number 0; the game's fire costs are resource vectors, so it now
starts from the first cost) and the firebeams fired one by one; no volley seen in a match yet.
**Anti-air first** (`Fire.AntiAirFirst`): flak and its upgrade, the shotgun, fire at the enemy fort only while the enemy has none of the `Threats` they should shoot down (mortars, heavy mortars, missiles, rockets, EMP rockets; counted every think step). With one of them they fire anti-air only, like `NoOffence` (offensive and rebuild fire probability 0); when the threats are gone their probabilities come back. Log on each change: `FLAK_HOLD on threats=<type:n,...>`, `FLAK_HOLD off`. Without a smoke launcher nothing changes. The timings are first guesses (the smoke bomb is a packed DLC weapon, its shell's flight time and cloud duration are not readable).
**Fire diagnostics:** the fire timer logs why an offence weapon did not fire, at most one line per weapon every `CAI_FIREWAIT_EVERY` (30) seconds and at once when the reason changes: `FIREWAIT <type> <id> avail=<0|1> ready=<0|1> code=<FIREFAIL name|-> queue=<0|1> m= e=` when it is skipped (not available, not ready to fire with the engine's reason, or an action such as opening doors pending), `FIRETRY <type> <id> fired=<0|1> code= [ray=<hit>:<side>:<material>@<x>,<y>] m= e=` after `TryFireGun` (fired = no longer ready, i.e. reloading; `fired=0`: the built-in AI declined - no target, chance or cost; `ray` = what the targeting ray towards the enemy reactor hits first, cast with the flags of the built-in `TargetObstructed`, in which the team's own background bracing blocks the ray).

**Retire idle weapons:** a plan may list weapon types to sell once they have nothing left to hit: `FortRetire = {
sniper = 90 }` after the `Fort` table (written by `gen_fort.py` from a variant's `retire`; `CAI_LoadPlanFile` reads
it, the plan swap logs e.g. `RETIRE-CONFIG sniper2:90,sniper:90`). The fire control counts, per weapon of such a type, the seconds in
which `TryFireGun` left it ready (the built-in AI declined: no target in reach) while the team had at least
`CAI_RETIRE_MIN_ENERGY` (1000) energy (it also declines when it cannot pay a shot); a shot resets the count, also one the built-in AI fires through its own `TryFireGun` call (`CAI_RetireShot` in the wrapper; before 28.10.2026 only the mod's round robin counted, and Abyss-3 test 2 sold a sniper that had fired 17 times). At the
limit the weapon is sold with `DestroyDeviceById` and its plan entry dropped (`RETIRE <type> <id> idle=<s> shots=<n>
result=<r>`). The built-in AI does not rebuild it: it only rebuilds a deleted device it marked itself
(`DeviceDeleteToRebuild`). Used by Abyss-2's early sniper (27.10.2026; the player's idea: snipe the enemy's first
weapons, sell the sniper once none is reachable). First seen in Abyss-2 test 7: `RETIRE sniper2 ... result=-8`, the AP
sniper gone from the next snapshot on, so -8 is the game's result for a sale it carries out (not `DD_SUCCESS`).

## Build tempo by difficulty

Update period (`UpdatePeriod`) and repair period (`RepairPeriod`) are interpolated linearly between Easy / Normal / Hard. Construction and pause durations are configurable.

## Build safety valves

- **Give up rebuilds:** if a queued rebuild action is stuck for longer than `RebuildGiveUpSeconds`, it is discarded. If the AI is merely waiting for metal, the clock does not run. "Insufficient resources" only counts as waiting while metal is still rising; if metal stays flat above `BuildSkipMinMetal` for `StarvedFlatTicks` think ticks (e.g. at the storage cap, when an action costs more than can be stored), the clocks run again.
- **Skip actions:** if normal construction is stuck on one action for longer than `BuildSkipSeconds` despite enough metal (`BuildSkipMinMetal`), the action is skipped.
- **Rebuild cap:** the built-in AI queues every lost device for rebuilding (`CheckDeviceForRebuild` schedules `QueueDeviceRebuild`, which the mod wraps). Losses are counted per plan action; a loss within `RebuildCap.Window` (180 s, game time) of the one before continues the streak, a longer survival starts a new one. Once a streak passes `RebuildCap.Max[type]` (machine gun, minigun and smoke launcher: 3 rebuilds), the device stays lost for the rest of the match and its metal goes into the plan (`REBUILD_CAP action <k> <type> losses=<n> window=<s>s`). Types without an entry (turbines, mines, weapons other than these) are always rebuilt. Reason: on Vanilla-5 (25.10.2026) one machine gun on the prow was lost and rebuilt ten times in four minutes under mortar fire, while the AI was below 150 metal most of the match. On Abyss (`Maps.Abyss.Strategy` in `ai/fortplans.lua`, 27.10.2026) snipers are capped at 2 rebuilds and mortars at 3 (Abyss-2 test 6: a sniper lost four times, the mortars five times, metal below 150 for 56 % of the match).

## Reactive build modules

A plan is a fixed fort, and a player who sees it picks its gap: Vanilla-5 lost to a sniped laser, to laser plus
firebeam, to rockets and to mortars (`.dev/docs/history/vanilla-3-5.md`). Modules let the AI answer the weapons the enemy
actually builds without giving up the fixed opening: the plan still sets the opening and the economy, and a module is
a small, pre-generated and rule-checked build snippet that is put in front of the rest of the plan when scouting sees
its trigger.

**How the built-in AI makes this possible** (`data/ai/ai.lua`):
- It builds `Fort[data.fortIndex]` and moves on; failed actions go to `data.Rebuild[index]`. It already inserts
  actions into the running plan itself: `DiscoverLinks/Nodes/Devices` do `table.insert(Fort, data.fortIndex, action)`
  and advance `data.fortIndex`. Inserting at `data.fortIndex` without advancing puts actions *ahead* of the rest of
  the plan, which is what a module needs.
- Actions refer to nodes by original id, mapped through `data.OriginalToActual`. `CREATE_NODE` snaps to an existing
  node within 20 units (`SnapToNode`) and maps its id instead of building a second node, so a module may build
  nodes the plan also builds later (and the other way round).
- `OffsetFort`/`MirrorFort` (called before `Load`) renumber the AI's new nodes (`MakeAINodesInSequence`, from
  `AI_NODE_START` = 10000) and move all positions. Module actions must go through this transform, so they have to be
  in `Fort` when it runs.
- Index-keyed state: `data.Rebuild[index]`, `data.Frustration[index]` (keys), `data.Devices[deviceId] = index`
  (values), and the mod's `st.rebuildSince[index]`, `st.buildIndex`.

**How it works:**
1. **Plan file.** After the `Fort` table a plan may define `FortModules = { { Name = "counterbattery", Trigger =
   { Types = { "mortar", "mortar2" }, Count = 2 }, Requires = <plan action>, Actions = { ... } }, ... }` (a list, so the
   order is deterministic; `Count` defaults to 1). The `Fort` table and its header are unchanged, so the
   line-sensitive part stays as it is. `CAI_LoadPlanFile` also reads `FortModules`.
2. **Load.** On the swap (`CAI_TrySwapPlan`) every plan action is tagged with its number (`CAI_K`), and the module
   actions are appended to `Fort`, tagged `CAI_Module = <list index>` and shifted like the plan's own actions. The
   game's transform then renumbers and moves them with the rest. Right after the base `Load`
   (`CAI_ExtractModules`) the tagged actions are cut out of `Fort` into `data.CAIModules`, so the built-in AI never
   reaches them on its own, and `CAI_PlanPos` is rebuilt on next use so SHAPE diagnostics know the module nodes. Log:
   `MODULES <name>:<actions>,...`. The `PLAN ... actions=` count leaves the modules out.
3. **Scouting.** Each think step counts the enemy's devices by type (`GetDeviceCountSide(enemyTeamId)`,
   `GetDeviceIdSide`, `GetDeviceType`; already used for targeting). This is game state, so it is deterministic and
   replay-safe.
4. **Trigger.** A module fires once per match when the enemy has at least `Count` devices of its `Types` together
   (counted every think step, `CAI_UpdateModules`, not during a probe), or when the game time (seconds since the AI
   started) reaches `Time`: a module that is part of the plan's goal comes even against a player who builds nothing,
   and the enemy's devices only pull it forward. `After = <name>`: only once that module has gone in (e.g. heavy
   mortars after the mortars). If the AI has not yet passed plan action `Requires` (progress = the `CAI_K` of the
   last plan action before `data.fortIndex`), it waits. Several modules ready in the same step go in the order listed
   in the plan. The log names the reason: `trigger=mortar:2` or `trigger=time:150`.
5. **Insertion.** The module's `n` actions are inserted at `data.fortIndex` (copies, so a rebuild works on them like
   any plan action). All index-keyed state at or after that index moves up by `n`: keys of `data.Rebuild`,
   `data.Frustration` and `st.rebuildSince`, values of `data.Devices`; `st.buildIndex` is reset so the skip valve
   starts a new clock. Log: `[CAI] T<team> MODULE <name> trigger=<type:n,...> at=<index> actions=<n>`, and once
   when it starts waiting `MODULE_WAIT <name> trigger=<type:n,...> requires=<k> now=<plan action>`.
   The built-in AI keeps no other state by action index (`data.Rebuild` and `data.Frustration` are the only tables
   indexed that way in `data/ai/ai.lua`).
6. **Rebuild cap:** see [Build safety valves](#build-safety-valves); index-keyed like the rest (`st.rebuilds` moves
   with an insert).

**Generator:** a variant lists `modules` ([generator.md](generator.md#reactive-build-modules)): each is generated
with the plan's step syntax on the plan as it stands after a given step, and `rules.py` checks it inside the plan,
right after its `Requires`.

**First modules** (from the lost matches; the counters themselves are first guesses):

| Trigger (enemy builds) | Module | Lost to it |
|---|---|---|
| mortars | counter-battery mortars (Vanilla-6: `artillery`; the laser Vanilla-5's tower-top `counterbattery` went with that plan) | Vanilla-5, 25.10.2026 |
| rockets, EMP rockets | a second anti-air position (machine gun or flak) | Vanilla-5 |
| snipers, lasers, firebeams | a door or armour in front of the exposed weapons, an own sniper | Vanilla-5 (twice) |

**Rejected:** switching to a whole different plan mid-match (every combination of tails would have to be generated
and kept consistent with what is already built); building counters by searching free places at runtime (no rule
checks in the game, and the fort-building rules are what most failures came from).

**Open questions, to test in a match with the first module:** what `CREATE_LINK` returns for a link
that already exists (module and plan sharing a strut); what a module costs against a starved economy; whether a
restart (key frame restore) keeps `Fort` and `data.CAIModules` consistent.

Test: `.dev/tools/tests/t_modules.lua` (hand-written module on Vanilla-2, team 102, mirrored).

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
├── preview.jpg, LICENSE    Workshop preview image, licence
├── .claude/                CLAUDE.md, project skills
├── .github/                README.md
└── .dev/                   Development only (dot folders are not uploaded to the Workshop)
    ├── SPEC.md, docs/      Specification (index, topics, maps/, history/)
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
2. Enable the mod *FORT 9000 (AI)* in the game.
3. Play matches or watch replays.
4. Run `.dev/tools/train.bat` (requires Python 3) – updates `ai/strategy.lua`.
5. Tests: `.dev/tools/tests/run_tests.sh` (Lua, via `LuaPlusC.exe`).
