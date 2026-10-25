# FORT 9000 – Testing a plan

- Force a plan in `ai/fortplans.lua` (`Force = { Vanilla = "fort-t1f1-Vanilla-4.lua" }`), never commit that line.
- Letting the AI build for 7–8 minutes without attacking is enough for build/stability questions (attacks mix
  damage into the diagnosis); a quit match does not count for training.
- The Forts log (`log.txt`) is UTF-16; for grep and other line tools convert a copy first
  (`iconv -f UTF-16 -t UTF-8 log.txt | tr -d '\r'`). Frames are 25 per second (`f=2500` = 100 s).
- Read the log before restarting Forts (it is overwritten on start; `train.py collect` archives it). Look at
  `PLAN`, `BUILT`/`LOST`, `BUILD_ERROR`, `UNSTABLE`, `GAVE_UP`/`SKIPPED`, the `THINK` lines (build index,
  metal, energy) and the `shots=` of the `SNAP` lines.
- Several matches without restarting Forts land in one log: count only from the latest `PLAN` line (its
  `actions=` shows which version of the plan the game loaded; a plan file is read at match start).
- `tools/fortgen/shape.py` shows from the `SHAPE` lines where and when the fort deformed ([debugging.md](debugging.md)). Pass
  `--plan` with the plan file the match actually used; with a later version of the plan the node ids no longer
  match and nodes seem to jump by about 100.
- The `CREC` `LINK` lines show when each strut was built and with which material (e.g. whether a door in front
  of a weapon stands yet); `DEV`/`GDEV` show when a device was placed, `BUILT` when it was finished.
- What decided a match: the `RESULT w=` and `END winner=... kills=... lost=... enemyShots=...` lines; `LOST s=1`/`s=2`
  (devices lost per side, with time); `UNLINK s=2` lines show which struts fell in which order (in the lost Vanilla-2
  matches: the breach came through the starting fort's front to the reactor); the `shots=` of all `SNAP s=2` lines
  summed give the shots per weapon type; `SNAP s=1` shows what the player built. `BUILD_ERROR destroy ... devices=`
  lists the own devices with platform and position ([debugging.md](debugging.md)).
- `FIREWAIT`/`FIRETRY` ([ai.md](ai.md#fire-control)) show why a weapon does not fire: `ready=0` with the engine's reason (e.g.
  `FIREFAIL_BUILDING`), `queue=1` for a pending door action, `fired=0` with the ray result when the built-in AI
  declined (no target, chance or cost).
- To map where a plan's fort refuses devices, let it build in a sandbox with `Probe` set ([debugging.md](debugging.md)) and read the run
  with `tools/fortgen/probe.py`.
- Render plans with `render_all.py` and compare with the game's Template-1.

## Reading the log of a match

- The log is `<Forts>/users/<steam-id>/log.txt` (UTF-16LE with BOM). It holds every match since the last game start
  and is written live; copies such as `log1.txt` may overlap (`train.py` skips duplicate matches). If its modification
  time has not changed since the last analysis, there is no new match (Forts still open, match not finished, log renamed).
- Side 1 is the player, side 2 the AI (team 102); `RESULT w=2` means the AI won. In 2v2 with two AIs each AI team has
  its own `[CAI] T<team>` lines.
- Game lines: `Loading map maps/<Map>/<Map>.fwe`, `ConfigureAI Team <n>: Fort , Difficulty <0..1>`,
  `ActivateAI team 102 team members 0 fort <plan>` (members 0 = a real AI; `team 1 team members 1` = the player's
  assist AI), `AllocateFortsToAI Side 2 ...`.
- `[CAI] T<team>` lines:
  - `PLAN-PRELOAD <Map>:<custom>/<original> ...`; `PLAN map= file= actions= instead= choice=<forced|random> detected=signature at=<MirrorFort|OffsetFort|Load> shift=`
    (plan swapped) or `PLAN file=original reason=<random|no-game-plan>`; `TRANSFORM MirrorFort/OffsetFort`;
    `MAP-STRATEGY <Map>: <keys>`; `INIT strategy=v1 trained=<n> difficulty=`; `ASSIST FORT 9000 AI inactive`;
    `TEMPO`, `FIRE`, `DEBUG-HOOKS` (settings at start).
  - `THINK t= build=<fort index>/<#actions> rebuild=<n> heavy=.. small=.. phase= econ= m= e= aggr= aa= fire=<ready weapons>`.
  - `GAVE_UP action k type=<1 node|3 strut|5 device> ...` (a rebuild stuck for 120 s or more despite metal),
    `SKIPPED action k` (building stuck for 90 s or more with at least 300 metal),
    `BUILD_ERROR <link|node|device|ground_device|upgrade|destroy> ... <CS_CODE> action=k`
    (`CS_INSUFFICIENTRESOURCES` is not logged).
  - `END winner= kills=<what the AI destroyed> lost=<AI losses> enemyShots=<player's shots>` (often written twice).
- Plausibility before training: a match without `RESULT` or shorter than 1 minute was aborted (does not count); a
  player with fewer than ~40 shots probably did not defend (ask before training on it); the same action given up in
  several matches with one plan is a plan bug.
- After `RESULT`, an instant replay may repeat `[CAI]`/`[CREC]` lines (`Starting instant replay`); count up to `RESULT`.
- A restart (`RevertMap <map>`, then `START ... restart=1`) is a new match with the same plan; `summary.py` and
  `train.py` split there. A match that should not count (own fort collapsed, nobody fought) goes into `EXCLUDED` in
  `train.py`.
