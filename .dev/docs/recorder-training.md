# FORT 9000 – Recorder and training

## Recorder

`script.lua` runs in every match and in replays, changes nothing in the game, and writes lines prefixed `[CREC]` to the Forts log:

| Line | Content |
|---|---|
| `START v=3` | Start; `restart=1` when the player restarts the match (the game rewinds to frame 2 without reloading the script, the frame jumps back) |
| `SNAP s=… m=… e=… dev=… shots=…` | every 125 frames: metal, energy, devices and shots per side |
| `BUILT` / `LOST s=… i=<device id> d=…` | device completed / destroyed |
| `NODE` / `LINK` / `DEV` / `GDEV` | node, strut, device on a strut (nodes, LinkT, `u=` upgraded device), ground device built (both sides; positions, team `t=`) |
| `UNNODE` / `UNLINK` / `DEL` | node, strut destroyed; device scrapped |
| `RESULT w=…` | winner |

The build events (see the header of `script.lua` for the exact format) let `.dev/tools/fortgen/rec_fort.py` turn a fort built by a player into an AI build plan: struts to new nodes become `CREATE_NODE` from the end that already exists, other struts `CREATE_LINK`, devices `CREATE_DEVICE` (ground devices with `GroundPosition`), in the player's order. Parts built and removed again are left out; removing a part of the starting fort becomes `DESTROY_LINK`/`DESTROY_DEVICE`; an upgrade keeps the old device and adds the new one. Starting-fort nodes are matched by position (within 20) to the base plan of the map (`gen_fort.MAPS`); one whose first logged position is too late (the fort had sagged) is matched by the runtime-id offset of the others; new nodes get ids from 10000. A node the recorder never saw created that is not in the base plan (foundations are not always reported) becomes a new node. A new node is placed at the offset its strut had from the source node when it was built (the game's AI places nodes by that offset, `GetAdjustedNodePosition`), which also takes out the sag of a long build; foundations keep their absolute position and may be up to 218 away. Strut lengths are checked at the length they had when built. A strut that created a node still in use is kept even if it was removed later (the log does not say whether the player removed it or it was shot away), unless its other node was destroyed (the player may have built another node in its place); a destroyed node takes its struts along even when the game reported no `UNLINK` (a node cancelled while building). Devices: one destroyed by the enemy (`LOST`) stays in the plan, and if the player rebuilt it on the same strut (same family, e.g. turbine/turbine2) it is built once, at the first time; one the player scrapped (`DEL`) within 60 s is left out, later it is built and then destroyed there (`DESTROY_DEVICE`); scrapping an upgraded device also drops the devices it was upgraded from; a reverted upgrade (turbine2 back to turbine) is left out. The check reports a new node within 20 of another (the AI snaps to it: an error for a starting-fort node, a warning between new nodes, whose plan positions have the sag taken out). `--clear-fire` turns struts that block a weapon into background bracing (armour: door), like the generator's `clear_fire_lines`. A fort built on side 2 is mirrored into the team-1 frame like the game mirrors plans (device nodes swapped, LinkT -> 1 - LinkT). The tool then checks the plan (build order, lengths, rock, `rules.py`). Record without combat (sandbox, or `--until <frame>` before the first shot), otherwise damage and repairs end up in the plan (the first Vanilla-7 was recorded from a whole match: struts and devices that were shot away and not rebuilt are missing, rebuilt ones come at their rebuild time). The log is UTF-16; `train.read_log` reads it. Not yet tried in the game: the order in which the engine reports a new node and its strut (both orders are handled), and whether ground devices also fire `OnDeviceCreated` (handled: the ground event wins).

## Training

`.dev/tools/train.py` collects the logs, learns from them and rewrites `ai/strategy.lua` (previous version: `strategy_previous.lua`).
Learning always starts from the default values, so running it repeatedly shifts nothing; only new matches change the result.
It learns `TargetValue` (Heavy/Small) and `Aggression` (Early/Mid/Late). `--strength` (0..1) limits how far values may deviate from the defaults.

- Usage: `python .dev/tools/train.py` (collect + train), `collect` (archive `log.txt` into `.dev/tools/logs/`; `--log <file>` for
  another log such as `log1.txt`), `train`, `report` (show the evaluation, write nothing). The output lists the AI's
  wins per plan, the learned target values and the aggression per phase.
- Matches: a new one starts at `START` or at the game's `RevertMap` line (a restart, also in logs from before the
  recorder wrote `restart=1`; it keeps the AI plan of the restarted match). Lines after `Starting instant replay` are
  ignored until the next map is loaded. Matches that must not be learned from (e.g. the player's own fort collapsed)
  go into `EXCLUDED` in `train.py` by their `game_key`; `report` prints how many were excluded.
- Learning is global, not per map (the map is in the log as `Loading map maps/<Map>/...`). The build tempo is not
  learned; it comes from the defaults (`DEFAULTS["Tempo"]` in `train.py`) and per-map `Strategy` overrides.

## Training loop

```
Play match ──► users/<id>/log.txt ([CREC] + [CAI])
     ▲                      │ train.py collect (archive in .dev/tools/logs/)
     │                      ▼
strategy.lua  ◄── train.py train (reads all logs, learns from defaults)
```

Forts overwrites `log.txt` on every start, so run `train.bat` after each play session.
