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
