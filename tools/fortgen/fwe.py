"""Gelaende aus Forts-Kartendateien (.fwe) lesen: Polygone aus zusammenhaengenden Eckpunkt-Datensaetzen.
Datensatz: float x, float y, float z(=0), u32, u32 len, len Bytes Name."""
import struct

def _vertex(d, o):
    if o + 20 > len(d): return None
    x, y, z = struct.unpack_from("<fff", d, o)
    if not (x == x and y == y) or abs(x) > 6000 or abs(y) > 6000 or z != 0.0:
        return None
    n = struct.unpack_from("<I", d, o + 16)[0]
    if n > 64 or o + 20 + n > len(d): return None
    s = d[o + 20:o + 20 + n]
    if n and not all(32 <= c < 127 or c == 0 for c in s): return None
    return (x, y), o + 20 + n

def read_blocks(path, min_vertices=3):
    """Liefert (bounds, [(kennung, punkte)]). Kennung 1/2 = fester Fels (Seite), -2 = Hintergrund."""
    d = open(path, "rb").read()
    bounds = struct.unpack_from("<ffff", d, 16)
    blocks, o = [], 0
    while o < len(d):
        v = _vertex(d, o)
        if v is None:
            o += 1; continue
        start = o
        pts = []
        while v is not None:
            pts.append(v[0]); o = v[1]; v = _vertex(d, o)
        if len(pts) >= min_vertices and not all(abs(p[0]) < 1 and abs(p[1]) < 1 for p in pts):
            flag = struct.unpack_from("<i", d, start - 11)[0] if start >= 11 else 0
            blocks.append((flag, pts))
    return bounds, blocks


def read_polygons(path, min_vertices=3, solid_only=True):
    bounds, blocks = read_blocks(path, min_vertices)
    return bounds, [pts for flag, pts in blocks if (flag >= 0 or not solid_only)]

if __name__ == "__main__":
    import sys
    b, blocks = read_blocks(sys.argv[1])
    print("bounds", b, "polygons", len(blocks))
    for f, p in blocks: print(f, len(p), [(round(x), round(y)) for x, y in p][:8])
