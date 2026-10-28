# FORT 9000 – Specification

FORT 9000 is a mod for the game **Forts** (Steam). It extends the built-in AI, records matches, and automatically retrains the AI parameters from those recordings.

In-game name: *FORT 9000 (AI)* · Folder: `data/mods/fort-9000`

---

## Goals

- A stronger, more adaptive computer opponent than the built-in Forts AI.
- The AI should improve from real matches (training), not only through manual tuning.
- Custom build variants per map, so the AI does not always build the same fort.
- Everything deterministic: replays and multiplayer must not desync.

## Where to find what

The specification is split into files so a session only loads what it needs.

| File | Content | Read when |
|---|---|---|
| [docs/ai.md](docs/ai.md) | AI features (targets, aggression, anti-air, fire control, tempo, safety valves, plan selection, assist mode), architecture, AI flow, configuration reference, installation | changing `ai/ai.lua`, `strategy.lua` or `fortplans.lua` |
| [docs/forts-api.md](docs/forts-api.md) | the game's Lua scripting API: link, local copy `docs/references/FortsAPI.html`, how to look up a function | calling a game function from mod Lua |
| [docs/recorder-training.md](docs/recorder-training.md) | recorder (`[CREC]` lines), `rec_fort.py`, training and the training loop | changing `script.lua` or `train.py` |
| [docs/debugging.md](docs/debugging.md) | build hooks, `BUILD_ERROR`, `UNSTABLE`, `SHAPE`, `STRESS`, the `CS_UNSTABLE` probe | diagnosing refused devices or a deforming fort |
| [docs/generator.md](docs/generator.md) | `tools/fortgen/` tools and all generator / variant options | changing `gen_fort.py` |
| [docs/physics.md](docs/physics.md) | `physics.py`: static physics check of a plan (sag, strut stress, refused struts, collapse in build order), its model, calibration against the engine and limits | checking whether a plan stands before a match, or a fort that sags or falls |
| [docs/map-files.md](docs/map-files.md) | the map file formats `.spr` (starting forts: nodes, struts with rest lengths, devices) and `.fwe` (terrain blocks, views, props); readers `spr.py`, `fwe.py` | reading a map's starting fort or terrain |
| [docs/building-rules.md](docs/building-rules.md) | game mechanics (materials, devices, economy, lines of fire, wind, `CS_UNSTABLE`), defence facts, design rules, `rules.py` validation, general failed approaches | before changing any plan or the generator |
| [docs/testing.md](docs/testing.md) | how to test a plan and read the log of a match | analysing a match |
| [docs/maps/vanilla.md](docs/maps/vanilla.md) | Vanilla: starting fort, shared shape, Vanilla-2 to -7 (current state), failed approaches, open problems | working on a Vanilla plan |
| [docs/maps/abyss.md](docs/maps/abyss.md) | Abyss: variants, cliff-ledge rules, failed approaches | working on an Abyss plan |
| [docs/maps/vanillalong.md](docs/maps/vanillalong.md) | VanillaLong: converted Vanilla plans | working on a VanillaLong plan |
| [docs/history/vanilla-2.md](docs/history/vanilla-2.md) | Vanilla-2 test matches in order | debugging a regression, "did we try X?" |
| [docs/history/vanilla-3-5.md](docs/history/vanilla-3-5.md) | Vanilla-3/-4/-5 test matches (tower, cannons (Vanilla-4, removed 28.10.2026), 20mm rush, the former laser Vanilla-5, the rocket Vanilla-5) | debugging a regression, "did we try X?" |
| [docs/history/vanilla-6.md](docs/history/vanilla-6.md) | Vanilla-6 (modular fort) test matches | debugging a regression, "did we try X?" |
| [docs/history/vanilla-7.md](docs/history/vanilla-7.md) | Vanilla-7 (a player's fort: the source match, the recorded version's tests, the generated version; removed 28.10.2026) | debugging a regression, "did we try X?" |
| [docs/history/abyss-2.md](docs/history/abyss-2.md) | Abyss-2 (mortar battery, rebuilt 27.10.2026) test matches | debugging a regression, "did we try X?" |
| [docs/history/abyss-3.md](docs/history/abyss-3.md) | Abyss-3 (firebeam rush, rebuilt 27.10.2026) test matches | debugging a regression, "did we try X?" |
| [docs/history/probe-runs.md](docs/history/probe-runs.md) | the `CS_UNSTABLE` probe runs and their numbers | working on `CS_UNSTABLE` |

A test result goes into the history file of its plan; what it changes in the current state goes into the map file (and the topic file, if it is a general rule).

## Key design rules

- **Determinism:** no wall-clock time, no `math.random`. Randomness only via `GetRandomInteger`, with fallback to `teamId`.
- **Fault tolerance:** all custom logic runs inside `pcall`; an error must not abort the match, it is logged as `[CAI] ERROR …`.
- **Configuration over code:** behaviour is controlled by `strategy.lua` (learned) and `fortplans.lua` (manual); training never modifies `fortplans.lua`.
- **Logging:** decisions use `[CAI]`, recording uses `[CREC]`.
- **Language:** code, comments, log messages and documentation are written in English.

## Known limitations

- Plans only for Abyss, Vanilla and VanillaLong.
- Training learns from few matches (35 with a result on 25.10.2026); `--strength` limits the deviation.
- Assumes 25 frames per second for the game phases in training.
