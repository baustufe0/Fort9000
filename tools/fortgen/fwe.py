"""Read Forts map files (.fwe): terrain blocks, camera views and props (docs/map-files.md).

Little endian; strings are i32 length + bytes. Decoded on 27.10.2026; every map .fwe of the game and its mods (version
20) parses to the last byte.

  header   i32 version (20), i32 0, f32 gravity (981), f32 0, f32 x0, x1, y0, y1 (map bounds), str environment
  blocks   i32 count, then per block (a terrain polygon):
           str name (mostly empty; "barrier", "nosplash_t1_top", ...), i32 vertex count, 4 x f32 colour,
           str texture, str edge decoration (default), 5 x f32 (0.375, 0, 0, 0, 0), i32 id, 7 x u8 flags,
           vertices: f32 x, f32 y, f32 z (0), i32 (unknown), str edge decoration ("foundations": foundations may
           be built on this edge, "rocks01", "" ...)
           id: 1 / 2 solid rock of team 1 / 2, -1 solid neutral rock, -2 background (no collision)
  views    i32 count, per view i32 index, f32 zoom, f32 x0, x1, y0, y1 (team 1, team 2, whole map)
  named    i32 count, per view str name, 5 x f32 (as above)
  props    i32 count, per prop str name, i32 n, n x str texture, f32 x, y, z, width, height, angle, scale x, y, i32 flip
The fort editor's clipboard_terrain.fwe files end after the blocks.

Usage: fwe.py <map name or .fwe file>
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(HERE))))
SOLID_TEAMS = (1, 2)
NEUTRAL = -1
BACKGROUND = -2


class FweError(ValueError):
    pass


def read(path):
    """{version, gravity, bounds (x0, x1, y0, y1), environment, blocks: [{name, id, texture, decoration, colour,
    flags, vertices: [(x, y, decoration)]}], views, named, props}"""
    d = open(path, "rb").read()
    o = 0

    def i32():
        nonlocal o
        o += 4
        return struct.unpack_from("<i", d, o - 4)[0]

    def floats(n):
        nonlocal o
        o += 4 * n
        return struct.unpack_from("<%df" % n, d, o - 4 * n)

    def text():
        nonlocal o
        n = i32()
        if not 0 <= n <= 1024 or o + n > len(d):
            raise FweError("no string at %d" % (o - 4))
        o += n
        return d[o - n:o].decode("latin-1")

    out = {"version": i32()}
    i32()
    out["gravity"] = floats(2)[0]
    out["bounds"] = floats(4)
    out["environment"] = text()
    blocks = []
    for _ in range(i32()):
        name = text()
        nv = i32()
        colour = floats(4)
        texture, decoration = text(), text()
        floats(5)
        bid = i32()
        flags = d[o:o + 7]
        o += 7
        verts = []
        for _ in range(nv):
            x, y, _z = floats(3)
            i32()
            verts.append((x, y, text()))
        blocks.append({"name": name, "id": bid, "texture": texture, "decoration": decoration, "colour": colour,
                       "flags": flags, "vertices": verts})
    out["blocks"] = blocks
    out["views"], out["named"], out["props"] = [], [], []
    if o == len(d):         # clipboard_terrain.fwe
        return out
    for _ in range(i32()):
        index = i32()
        out["views"].append((index,) + floats(5))
    for _ in range(i32()):
        out["named"].append((text(),) + floats(5))
    for _ in range(i32()):
        name = text()
        textures = [text() for _ in range(i32())]
        x, y, z, w, h, ang, sx, sy = floats(8)
        out["props"].append({"name": name, "textures": textures, "pos": (x, y), "size": (w, h), "angle": ang,
                             "scale": (sx, sy), "flip": i32()})
    if o != len(d):
        raise FweError("parsed %d of %d bytes" % (o, len(d)))
    return out


def read_blocks(path, min_vertices=3):
    """Returns (bounds, [(id, points)]): every terrain polygon with its id (1/2 solid rock of a team, -1 neutral
    rock, -2 background)."""
    f = read(path)
    return f["bounds"], [(b["id"], [(x, y) for x, y, _ in b["vertices"]]) for b in f["blocks"]
                         if len(b["vertices"]) >= min_vertices]


def read_polygons(path, min_vertices=3, solid_only=True):
    bounds, blocks = read_blocks(path, min_vertices)
    return bounds, [pts for flag, pts in blocks if (flag >= 0 or not solid_only)]


if __name__ == "__main__":
    import sys
    arg = sys.argv[1]
    path = arg if arg.endswith(".fwe") else os.path.join(DATA, "maps", arg, arg + ".fwe")
    f = read(path)
    print("%s: version %d, gravity %.0f, bounds %s, %s, %d blocks, %d views, %d named, %d props" % (
        os.path.basename(path), f["version"], f["gravity"], f["bounds"], f["environment"], len(f["blocks"]),
        len(f["views"]), len(f["named"]), len(f["props"])))
    for b in f["blocks"]:
        found = sum(1 for _, _, dec in b["vertices"] if dec == "foundations")
        print("  id %2d %-20s %3d vertices, %d foundation edges, %s" % (
            b["id"], b["name"] or "-", len(b["vertices"]), found,
            [(round(x), round(y)) for x, y, _ in b["vertices"]][:6]))
