# FORT 9000

AI mod for **Forts**: extends the built-in AI (adaptive target selection, aggression, anti-air, fire control, custom build plan variants), records matches and retrains the AI parameters from them.

Features and architecture: [.dev/SPEC.md](../.dev/SPEC.md) (index of the files in `.dev/docs/`)

## Installation
Only the root files are part of the mod; folders starting with "." (`.dev/`, `.claude/`, `.github/`) hold development files and are not uploaded to the Workshop.
For development, clone this repo as `fort9000dev` into `<Steam>/steamapps/common/Forts/data/mods/` and enable *FORT 9000 AI DEV* in the game. `py .dev/tools/publish.py` copies the mod into `mods/fort9000` (*FORT 9000 AI*) for the Steam Workshop upload.

## Training
After each play session, run `py .dev/tools/train.py` from the mod folder (requires Python 3).
