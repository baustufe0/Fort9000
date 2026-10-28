# Publishing to the Steam Workshop

## Two mod folders

| Folder | In game | Content |
|---|---|---|
| `data/mods/fort9000dev` | FORT 9000 AI DEV | git repo, the mod as developed, everything for development in dot folders |
| `data/mods/fort9000` | FORT 9000 AI | generated copy for the Workshop upload; never edit it by hand |

Enable only one of the two in the game: both at once would load `ai/ai.lua` twice and wrap the built-in AI twice.

The AI loads its own files by fixed paths (`mods/fort9000dev/ai/strategy.lua`, `.../ai/fortplans.lua`,
`.../fortplans/<map>/`), so each copy needs its own folder name in those paths.

## publish.py

`py .dev/tools/publish.py` (`--dry-run` only checks and lists) copies every root entry of the dev folder that does
not start with `.` into `fort9000`, after emptying it, and:
- rewrites `mods/fort9000dev/` to `mods/fort9000/` in the `.lua` files (plan files are copied byte for byte;
  the rewrite changes no line numbers);
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

## Open question

How a subscriber's copy is installed is untested: Workshop mods may load from a folder named by their numeric id
(the game executable contains `/mods/%llu/`), where the fixed `mods/fort9000/...` paths would not find the plans or
the strategy. `ai/ai.lua` already tries the global `path` first for `strategy.lua`.
