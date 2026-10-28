# Publishing to the Steam Workshop

## Two mod folders

| Folder | In game | Content |
|---|---|---|
| `data/mods/fort9000dev` | FORT 9000 AI DEV | git repo, the mod as developed, everything for development in dot folders |
| `data/mods/fort9000` | FORT 9000 AI | generated copy for the Workshop upload; never edit it by hand |

Enable only one of the two in the game: both at once would load `ai/ai.lua` twice and wrap the built-in AI twice.

The AI loads its own files (`ai/strategy.lua`, `ai/fortplans.lua`, `fortplans/<map>/`) from the first folder in
`CAI_ModDirs` (top of `ai/ai.lua`) that holds `ai/strategy.lua`: the global `path` if the game sets it, then
`mods/<PublishedFileId>/` (published copy only), then the copy's own folder (`mods/fort9000dev/` or `mods/fort9000/`).

A Workshop subscriber has the mod only as `mods/<PublishedFileId>/` (here `mods/3829000413/`), the author also as
`mods/fort9000/`. All players of a match must load the same files: on 28.10.2026 (Vanilla 2v2) the host loaded the
plans from `mods/fort9000/`, the subscriber found none, skipped the `CAI plan` random draw and desynced at frame 2.
So the published copy looks in the Workshop folder first, also on the author's machine: there, a change in
`fort9000` takes effect only after the upload.

## publish.py

`py .dev/tools/publish.py` (`--dry-run` only checks and lists) copies every root entry of the dev folder that does
not start with `.` into `fort9000`, after emptying it, and:
- rewrites `mods/fort9000dev/` to `mods/fort9000/` in the `.lua` files (plan files are copied byte for byte;
  the rewrite changes no line numbers);
- replaces the `--[[WORKSHOP]] ` marker in `ai/ai.lua` with `"mods/<PublishedFileId>/", ` (warns and drops it
  while there is no id yet; subscribers then miss the plans and the strategy);
- removes ` DEV` from the names in `displayname.lua` (UTF-16 LE with BOM, as the game writes it);
- keeps `fort9000/publishedfileid.lua`, the Workshop item id the game writes after the first upload, and stores a
  copy in `.dev/publishedfileid.lua` (tracked in git); if `fort9000` has none, it restores it from there.

It refuses to publish when the dev folder contains a `.bat`, `.cmd` or `.exe` file (anywhere, dot folders included),
when `Probe` is switched on or `Force` is not empty in `ai/fortplans.lua`, or when the target folder name is not
alphanumeric ASCII. The skill `forts-publish` runs the tests and the script.

## Known upload errors (game log, German client)

| Log line | Cause | Fix |
|---|---|---|
| `Uploaded Workshop-Ordnernamen müssen nur grundlegende alphanumerische ASCII-Zeichen enthalten (<name>)` | the item name typed in the upload dialog has spaces or other characters | type letters and digits only (`FORT9000AI`); rename the item on its Workshop page afterwards |
| `Fehlerhafter Dateipfad oder Dateitypen nicht gefunden.` | a `.bat` file in the mod folder (`.dev/tools/train.bat`, removed 28.10.2026); the validation refuses `.bat`, `.cmd`, `.exe` even in dot folders | no such files anywhere in the mod folder |

## Workshop page

The game's upload dialog takes only the item name and a change note; the thumbnail is `preview.jpg` (16:9, under
1 MB). Title and description are edited on the item's Steam Workshop page.

## Subscriber's copy

Confirmed by the desync reports of 28.10.2026: a Workshop mod loads from `mods/<PublishedFileId>/` (the world dump
lists `mods/3829000413/script.lua`). `run_tests.sh` publishes into a temporary folder, links it as
`mods/<PublishedFileId>/` only and checks that the AI finds its plans there. Whether the game sets `path` for AI
scripts is still unknown.
