# Forts scripting API

Official reference: <https://www.earthworkgames.com/content/docs/FortsAPI.html>

Local copy: [references/FortsAPI.html](references/FortsAPI.html) (downloaded 28.10.2026). It is about 375 KB,
so don't read the whole file. Grep it for a function name instead.

## Looking up a function

The page has an index by category (`<h3>Artificial Intelligence</h3>`, `<h3>Audio</h3>`, ...) followed by one
entry per function. Each entry starts with `<h3><a name="<Function>">` and contains a description, a "See also"
line, the C prototype and an example Lua call:

```bash
grep -n -A 16 'name="GetRandomInteger"' docs/references/FortsAPI.html
```

List the functions of one category (example: AI):

```bash
grep -n -A 6 '<h3>Artificial Intelligence</h3>' docs/references/FortsAPI.html
```

## Notes for this mod

- Randomness only through `GetRandomInteger` (deterministic, synchronised). `GetRandomIntegerLocal` is not
  synchronised, so it must not affect game state (see the determinism rule in `CLAUDE.md`).
- The page documents the game's C functions exposed to Lua. The built-in AI's Lua functions (`data/ai/ai.lua`),
  which `ai/ai.lua` wraps, are not in it; read the game's source files for those.
- When the game behaves differently from the reference, record it here.

## Updating the copy

```bash
curl -sSL -o docs/references/FortsAPI.html https://www.earthworkgames.com/content/docs/FortsAPI.html
```

Update the download date above when you do.
