#!/usr/bin/env python3
"""FORT 9000 - read the starting forts of a Forts map from its .spr file (data/maps/<map>/<map>.spr).

The .spr holds the structure every side starts with (.dev/docs/map-files.md): nodes with their positions and foundation
flag, devices (on struts, or on the ground with a position), the material table and, per node, its struts with
material, rest length and the device standing on them. Decoded on 27.10.2026 against the CS_UNSTABLE probe dumps of
Abyss and Vanilla (node positions, every strut and material, device positions on their struts all equal). Little
endian; strings are i32 length + bytes.

  header   i32 version (17-22), f32 0.4, i32 -1, then flag bytes; i32 node count at offset 22 (version <= 18) or 23
  node     54 bytes: i32 id, i32 team, f32 x, f32 y, 9 x f32 (unknown), u8 foundation, u8 (1)
  (u8)     then i32 device count
  device   str name, i32 team, i32 (1), f32 health (1.0), [4 x f32 ground position x, y, 0, angle: ground devices
           only], [i32 id: version >= 22]
  materials  i32 count, str names (bracing, backbracing, camo, armour, door, solar, shield, rope, fuse)
  struts   for every node in order: i32 count, then per strut:
           u8 (unknown), i32 other node (index), i32 material (index), i32 n, n x i32 node indices (probably the third
           corners of the background panels on the strut), i32 device (index, -1 = none), [device only: u8 flag,
           f32 LinkT if flag == 0], 6 x f32 (version <= 20) or 9 x f32: rest length first, u8 (unknown)
A strut is stored once, under one of its nodes. A device whose LinkT is not stored (flag 1, the mirrored side) has it
as 1 - the second float. Versions 18-22 parse to the last byte for every multiplayer map of the game; version 17 and
the mission "ghost" files do not.

Usage: spr.py <map name or .spr file> [--team 1]   (prints the starting fort of that team)
"""
import argparse
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(HERE)))))
NODE_SIZE = 54


class SprError(ValueError):
    pass


def spr_path(map_name):
    return os.path.join(DATA, "maps", map_name, map_name + ".spr")


def read(path):
    """{version, nodes: [{id, team, x, y, foundation}], devices: [{name, team, ground (x, y, angle) or None}],
    materials, struts: [{a, b (node ids), material, rest, device (index or None), t (LinkT from a)}]}"""
    d = open(path, "rb").read()

    def i32(p):
        return struct.unpack_from("<i", d, p)[0]

    def text(p):
        n = i32(p)
        if not 0 <= n < 64:
            raise SprError("no string at %d" % p)
        return d[p + 4:p + 4 + n].decode("ascii"), p + 4 + n

    def name_at(p):
        n = i32(p) if p + 4 <= len(d) else -1
        return 0 < n < 48 and p + 4 + n <= len(d) and all(32 <= c < 127 for c in d[p + 4:p + 4 + n])

    ver = i32(0)
    if not 18 <= ver <= 22:
        raise SprError("version %d not supported" % ver)
    o = 22 if ver <= 18 else 23
    count = i32(o)
    o += 4
    nodes = []
    for _ in range(count):
        nid, team, x, y = struct.unpack_from("<iiff", d, o)
        nodes.append({"id": nid, "team": team, "x": x, "y": y, "foundation": bool(d[o + 52])})
        o += NODE_SIZE
    o += 1
    count = i32(o)
    o += 4
    devices = []
    for k in range(count):
        name, o = text(o)
        team = i32(o)
        o += 12
        # a ground device has its position here; otherwise the next device (or the material table) follows
        q = o + 4 if ver >= 22 else o
        ground = None
        if not (name_at(q) or (0 < i32(q) < 64 and name_at(q + 4))):
            x, y, _, ang = struct.unpack_from("<4f", d, o)
            ground = (x, y, ang)
            o += 16
        if ver >= 22:
            o += 4
        devices.append({"name": name, "team": team, "ground": ground})
    count = i32(o)
    o += 4
    materials = []
    for _ in range(count):
        m, o = text(o)
        materials.append(m)
    nfloat = 9 if ver >= 21 else 6
    struts = []
    for a in range(len(nodes)):
        count = i32(o)
        o += 4
        for _ in range(count):
            b, mat, n = i32(o + 1), i32(o + 5), i32(o + 9)
            if not (0 <= b < len(nodes) and 0 <= mat < len(materials) and 0 <= n < 32):
                raise SprError("bad strut record at %d" % o)
            o += 13 + 4 * n
            dev = i32(o)
            o += 4
            t = None
            if dev != -1:
                if d[o] == 0:
                    t = struct.unpack_from("<f", d, o + 1)[0]
                    o += 4
                o += 1
            fl = struct.unpack_from("<%df" % nfloat, d, o)
            o += 4 * nfloat + 1
            if dev != -1 and t is None:
                t = 1.0 - fl[1]
            struts.append({"a": nodes[a]["id"], "b": nodes[b]["id"], "material": materials[mat], "rest": fl[0],
                           "device": dev if dev != -1 else None, "t": t})
    if o != len(d):
        raise SprError("parsed %d of %d bytes" % (o, len(d)))
    return {"version": ver, "nodes": nodes, "devices": devices, "materials": materials, "struts": struts}


def starting_fort(path, team=1):
    """The starting fort of one team: (nodes {id: (x, y)}, foundations {id}, struts [(a, b, material, rest)],
    devices [(name, a, b, t)], ground devices [(name, x, y)])."""
    s = read(path)
    nodes = {n["id"]: (n["x"], n["y"]) for n in s["nodes"] if n["team"] == team}
    found = {n["id"] for n in s["nodes"] if n["team"] == team and n["foundation"]}
    struts, devices = [], []
    for st in s["struts"]:
        if st["a"] not in nodes:
            continue
        struts.append((st["a"], st["b"], st["material"], st["rest"]))
        if st["device"] is not None:
            devices.append((s["devices"][st["device"]]["name"], st["a"], st["b"], st["t"]))
    ground = [(dv["name"],) + dv["ground"][:2] for dv in s["devices"] if dv["team"] == team and dv["ground"]]
    return nodes, found, struts, devices, ground


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("map", help="map name (data/maps/<map>/<map>.spr) or path of a .spr file")
    ap.add_argument("--team", type=int, default=1)
    args = ap.parse_args()
    path = args.map if args.map.endswith(".spr") else spr_path(args.map)
    s = read(path)
    teams = sorted({n["team"] for n in s["nodes"]})
    print("%s: version %d, %d nodes, %d struts, %d devices, teams %s" % (
        os.path.basename(path), s["version"], len(s["nodes"]), len(s["struts"]), len(s["devices"]), teams))
    nodes, found, struts, devices, ground = starting_fort(path, args.team)
    print("team %d: %d nodes (%d foundations), %d struts, devices %s, on the ground %s" % (
        args.team, len(nodes), len(found), len(struts), ["%s %d-%d@%.2f" % d for d in devices],
        ["%s (%.0f, %.0f)" % g for g in ground]))
    for a, b, mat, rest in struts:
        print("  %d-%d %s rest %.1f (now %.1f)" % (a, b, mat, rest, math.dist(nodes[a], nodes[b])))


if __name__ == "__main__":
    sys.exit(main())
