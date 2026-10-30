---
name: forts-publish
description: Copy the FORT 9000 mod from the dev folder (data/mods/fort9000dev) into the folder that is uploaded to the Steam Workshop (data/mods/fort9000), and keep the Workshop description (.dev/steam-description.txt) up to date. Use when the user wants to publish, upload or release the mod, update the Workshop item or its description.
---

# Publish FORT 9000

The repo and the development mod live in `data/mods/fort9000dev` ("FORT 9000 AI DEV" in game). The Workshop is fed from
`data/mods/fort9000` ("FORT 9000 AI"), which holds only a generated copy: never edit it by hand. Background:
[.dev/docs/publishing.md](../../../.dev/docs/publishing.md).

## Steps

1. **State of the repo:** `git status --short`. Uncommitted changes would be published too: tell the user and ask
   whether to commit first or publish anyway.
2. **Tests** (must pass before publishing):
   ```bash
   bash .dev/tools/tests/run_tests.sh /c/Tools/Lua/lua5.1.exe "/d/Steam/steamapps/common/Forts/data"
   ```
3. **Check, then copy:**
   ```bash
   py .dev/tools/publish.py --dry-run
   py .dev/tools/publish.py
   ```
   The script refuses on `.bat`/`.cmd`/`.exe` files anywhere in the dev folder, a switched-on `Probe` or a non-empty
   `Force` in `ai/fortplans.lua`. Fix the cause (ask the user before removing a testing `Force`), never bypass it.
   `WARNING could not remove ...` usually means Forts or another program has a file open in `fort9000`: ask the user
   to close it and run the script again.
4. **Report** to the user: number of files, the Workshop id line, and the next steps in the game:
   - enable **FORT 9000 AI** and disable **FORT 9000 AI DEV** (both at once would run the AI twice);
   - upload `fort9000` from the game's Workshop screen; the item name must be ASCII letters and digits only
     (e.g. `FORT9000AI`); title and description are edited on the Workshop page afterwards.
5. **Workshop description:** `.dev/steam-description.txt` is the item's description in Steam's BBCode (`[h1]`, `[h2]`,
   `[b]`, `[list][*]...[/list]`, `[noparse]` around text in square brackets such as `[CAI]`). Check it against what is
   published: the maps and the number of layouts per map (`Maps` and `Plans` in `ai/fortplans.lua`, the files in
   `fortplans/<map>/`), the features, the requirements (devices the plans use: Weapon Pack, DLC weapons). If anything
   changed, update the file, commit it with the publish, and give the user the whole text to paste into the Workshop
   page's description (the game's upload dialog does not set it). If nothing changed, say so.
6. **After the first upload** the game writes `fort9000/publishedfileid.lua`. Run `py .dev/tools/publish.py` once more:
   it copies the id to `.dev/publishedfileid.lua`. Commit that file, so later uploads update the same item.
7. **After the user has uploaded:** tag the published commit `workshop-v<N>` and write the changelog entry and the
   change note ([.dev/docs/publishing.md](../../../.dev/docs/publishing.md), "Versions and changelog").
8. If the upload fails, read the end of `<Forts>/users/<id>/log.txt` (UTF-16) for the `Fehler:`/`Error:` line and see
   the known upload errors in [.dev/docs/publishing.md](../../../.dev/docs/publishing.md).
