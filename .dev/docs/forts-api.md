# Forts scripting API

Official reference: <https://www.earthworkgames.com/content/docs/FortsAPI.html>

Local copy: [references/FortsAPI.html](references/FortsAPI.html) (downloaded 28.10.2026). It is about 375 KB,
so don't read the whole file. Grep it for a function name instead.

## Looking up a function

The page has an index by category (`<h3>Artificial Intelligence</h3>`, `<h3>Audio</h3>`, ...) followed by one
entry per function. Each entry starts with `<h3><a name="<Function>">` and contains a description, a "See also"
line, the C prototype and an example Lua call:

```bash
grep -n -A 16 'name="GetRandomInteger"' .dev/docs/references/FortsAPI.html
```

List the functions of one category (example: AI):

```bash
grep -n -A 6 '<h3>Artificial Intelligence</h3>' .dev/docs/references/FortsAPI.html
```

## Notes for this mod

- Randomness only through `GetRandomInteger` (deterministic, synchronised). `GetRandomIntegerLocal` is not
  synchronised, so it must not affect game state (see the determinism rule in `CLAUDE.md`).
- The page documents the game's C functions exposed to Lua. The built-in AI's Lua functions (`data/ai/ai.lua`),
  which `ai/ai.lua` wraps, are not in it; read the game's source files for those.
- When the game behaves differently from the reference, record it here.
- `CREATE_LINK` on a strut that already exists (built-in AI, `data/ai/ai.lua`, the `CREATE_LINK` branch of the
  action executor): if `IsNodeLinkedTo(a, b)` and `GetLinkMaterialSaveName(a, b)` is the action's material, the action
  passes without calling `CreateLink` (no cost, `LogDetail "Link already exists, action passed"`). So a module may list
  struts the plan also builds. With a *different* material the AI calls `CreateLink` on the existing strut; what the
  game does then (replace the material, or an error code) is not verified yet (Bastion, step 0).
- `DestroyDeviceById(deviceId)` "starts the salvage process", the same as a player's reclaim; the built-in AI uses it
  for `DESTROY_DEVICE` actions with a ground position, `DestroyDevice(team, a, b)` for one on a strut, both answer
  `DD_SUCCESS`. `DeviceCanBeDestroyedById` says whether a device can be reclaimed (not the reactor). How much metal the
  salvage gives back is not verified yet.
- `OnLinkHit(nodeIdA, nodeIdB, objectId, objectTeamId, objectSaveName, damage, pos, reflectedByEnemy)`: called when a
  projectile hits a strut, **not for beams or splash damage**. Lasers, firebeams and explosions only show up through
  `OnLinkDestroyed(teamId, saveName, nodeA, nodeB, breakType)` (`LINKBREAK_PROJECTILE`, `LINKBREAK_DELETE`, ...) or by
  reading `GetLinkHealth`. The built-in AI does not define `OnLinkHit`; it does define `OnLinkDestroyed` (wrap it).
  Whether the game calls `OnLinkHit` in the AI's script environment is not verified yet.

## Updating the copy

```bash
curl -sSL -o .dev/docs/references/FortsAPI.html https://www.earthworkgames.com/content/docs/FortsAPI.html
```

Update the download date above when you do.
