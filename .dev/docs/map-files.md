# FORT 9000 – Forts map files (.spr, .fwe)

A map folder `data/maps/<map>/` holds `<map>.lua` (settings), `<map>.fwe` (terrain, views, props), `<map>.spr`
(the starting forts) and the game's own AI plans. Both binary formats were decoded on 27.10.2026; the readers are
`.dev/tools/fortgen/spr.py` and `.dev/tools/fortgen/fwe.py` (pure Python, each prints a summary when run on a map name).
Little endian throughout; a string is an i32 length followed by that many bytes.

## .spr – starting forts

Every side's starting structure: nodes, devices, struts. Both teams are stored (team 2 mirrored).

| Part | Layout |
|---|---|
| header | i32 version (17-22), f32 0.4, i32 −1, flag bytes; i32 node count at offset 22 (version ≤ 18) or 23 |
| node (54 bytes) | i32 id, i32 team, f32 x, f32 y, 9 × f32 (unknown), u8 **foundation**, u8 (1) |
| | u8, then i32 device count |
| device | str name, i32 team, i32 (1), f32 health (1.0), [4 × f32 ground position x, y, 0, angle: ground devices such as mines only], [i32 id: version ≥ 22] |
| materials | i32 count, names: bracing, backbracing, camo, armour, door, solar, shield, rope, fuse |
| struts | per node in file order: i32 count, then per strut: u8 (unknown), i32 other node (index), i32 material (index), i32 n + n × i32 node indices (probably the third corners of the background panels on the strut), i32 device (index, −1 none), [device only: u8 flag, f32 LinkT if flag = 0], 6 × f32 (version ≤ 20) or 9 × f32 with the **rest length** first, u8 (unknown) |

- A strut is stored once, under one of its nodes. When the LinkT of a device is not stored (flag 1: the mirrored
  side), it is 1 − the second float.
- Which entry has a ground position is not flagged: a ground device is the one not followed by the next name (or the
  material table).
- The positions are the settled fort: it is in equilibrium with the stored rest lengths (the physics solver does not
  move it). Rest lengths differ from the node distances by up to ±2.4 (the map maker's fort settled under load).
- Versions 18, 19, 21 and 22 parse to the last byte for all 102 map files of the game and its mods except the two
  version-17 mission files and two mission `ghost.spr` files (none has a fort for the AI).

**Verification:** Abyss against the probe dump 5 s into a match (`log_20261026-215802`, runtime node ids are the file
ids): all 69 struts of the AI's side and their materials equal; reactor at LinkT 0.523 and machine gun at 0.349 on the
same struts (probe: 0.52, 0.35); the foundation flag equals "on the rock" for all 62 nodes. Vanilla: node positions
and devices equal the probe's (file ids = plan ids − 1). The engine's stress of the bare Abyss starting fort matches
the physics model with the file's rest lengths at correlation 0.99 ([physics.md](physics.md)).

## .fwe – terrain

| Part | Layout |
|---|---|
| header | i32 version (20), i32 0, f32 gravity (981), f32 0, f32 x0, x1, y0, y1 (map bounds), str environment (`environment/canyon`) |
| blocks | i32 count, per block (a terrain polygon): str name (mostly empty; `barrier`, `nosplash_t1_top`, `ns_t1`, ...), i32 vertex count, 4 × f32 colour, str texture, str default edge decoration, 5 × f32 (0.375, 0, 0, 0, 0), i32 **id**, 7 × u8 flags, vertices |
| vertex | f32 x, f32 y, f32 z (0), i32 (unknown), str decoration of the edge to the next vertex (`foundations`: foundations may be built on it; `rocks01`, empty, ...) |
| views | i32 count, per view i32 index, f32 zoom, f32 x0, x1, y0, y1 (team 1's side, team 2's side, whole map) |
| named views | i32 count, per view str name, 5 × f32 (as above; tutorials: `ore`, `reactor`, ...) |
| props | i32 count, per prop str name, i32 n + n × str texture, f32 x, y, z, width, height, angle, scale x, scale y, i32 flip |

- Block id: 1 / 2 solid rock belonging to team 1 / 2, −1 neutral solid rock, −2 background (no collision).
- The fort editor's `ai/forts/*/clipboard_terrain.fwe` end after the blocks.
- All 109 `.fwe` files of the game and its mods parse to the last byte. For Abyss and Vanilla the polygons are the
  same as the earlier heuristic reader found (contiguous vertex records), so generated plans did not change; on 74
  other maps the heuristic had missed or merged polygons.

## Open

- The 9 unknown floats of a node record, the u8 fields of a strut record and the floats after the rest length (two
  of them are the strut's angle).
- Version 17 `.spr` files and the mission `ghost.spr` files.
