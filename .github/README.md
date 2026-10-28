# FORT 9000

AI mod for **Forts**: extends the built-in AI (adaptive target selection, aggression, anti-air, fire control, custom build plan variants), records matches and retrains the AI parameters from them.

Features and architecture: [.dev/SPEC.md](../.dev/SPEC.md) (index of the files in `.dev/docs/`)

## Installation
Only the root files are part of the mod; folders starting with "." (`.dev/`, `.claude/`, `.github/`) hold development files and are not uploaded to the Workshop.
Place this folder as `fort9000` in `<Steam>/steamapps/common/Forts/data/mods/` and enable *FORT 9000 AI* in the game.

## Training
After each play session, run `py .dev/tools/train.py` from the mod folder (requires Python 3).
