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
  struts the plan also builds. With a *different* material the AI calls `CreateLink` on the existing strut, and the
  game **replaces the material at once** (engine probe, Vanilla match 03.11.2026: `CreateLink(team, "armour", a, b)` on a
  starting bracing strut answered `CS_SUCCESS` (-15), the strut was armour right after and one think step later, and
  the metal fell by 199 in the same frame). So a module can upgrade plan struts in place, at a price.
- `DestroyDeviceById(deviceId)` "starts the salvage process", the same as a player's reclaim; the built-in AI uses it
  for `DESTROY_DEVICE` actions with a ground position, `DestroyDevice(team, a, b)` for one on a strut, both answer
  `DD_SUCCESS` (-8). `DeviceCanBeDestroyedById` says whether a device can be reclaimed (not the reactor). Engine probe
  (03.11.2026, a machine gun at full health, cost 75 metal): `OnDeviceDeleted` came 124 frames (about 5 s) after the
  call, and the metal rose by 37.5 beyond the income, **half the cost**. The device is out of action during the salvage.
- The game cuts long log lines (an `EPROBE` line of about 200 numbers ended in the middle of a number): keep log lines short.
- `OnLinkHit(nodeIdA, nodeIdB, objectId, objectTeamId, objectSaveName, damage, pos, reflectedByEnemy)`: called when a
  projectile hits a strut, **not for beams or splash damage**. Lasers, firebeams and explosions only show up through
  `OnLinkDestroyed(teamId, saveName, nodeA, nodeB, breakType)` (`LINKBREAK_PROJECTILE`, `LINKBREAK_DELETE`, ...) or by
  reading `GetLinkHealth`. The built-in AI does not define `OnLinkHit`; it does define `OnLinkDestroyed` (wrap it).
  The game **does call `OnLinkHit` in the AI's script environment** (engine probe, 03.11.2026), also for the AI's
  **own** projectiles: the only hit in that match was the AI's own EMP rocket on its own door (team 102, damage 100,
  Vanilla-5). A hit map has to keep only `objectTeamId` of the enemy side. The enemy side was not tested: the player fired
  no shot in that match.

## Updating the copy

```bash
curl -sSL -o .dev/docs/references/FortsAPI.html https://www.earthworkgames.com/content/docs/FortsAPI.html
```

Update the download date above when you do.
