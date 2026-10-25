# FORT 9000 – Recorder and training

## Recorder

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

## Training

`tools/train.py` collects the logs, learns from them and rewrites `ai/strategy.lua` (previous version: `strategy_previous.lua`).
Learning always starts from the default values, so running it repeatedly shifts nothing; only new matches change the result.
It learns `TargetValue` (Heavy/Small) and `Aggression` (Early/Mid/Late). `--strength` (0..1) limits how far values may deviate from the defaults.

- Usage: `python tools/train.py` (collect + train), `collect` (archive `log.txt` into `tools/logs/`; `--log <file>` for
  another log such as `log1.txt`), `train`, `report` (show the evaluation, write nothing). The output lists the AI's
  wins per plan, the learned target values and the aggression per phase.
- Learning is global, not per map (the map is in the log as `Loading map maps/<Map>/...`). The build tempo is not
  learned; it comes from the defaults (`DEFAULTS["Tempo"]` in `train.py`) and per-map `Strategy` overrides.

## Training loop

```
Play match ──► users/<id>/log.txt ([CREC] + [CAI])
     ▲                      │ train.py collect (archive in tools/logs/)
     │                      ▼
strategy.lua  ◄── train.py train (reads all logs, learns from defaults)
```

Forts overwrites `log.txt` on every start, so run `train.bat` after each play session.
