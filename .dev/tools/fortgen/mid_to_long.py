#!/usr/bin/env python3
"""FORT 9000 - convert plans of the mid fort (team 1, Vanilla, FortPos -2900/700) into the coordinate
system of the long plan (team 2, FortId 3, FortPos 3700/-1950): x' = 800 - x, y' = y - 2650.
Devices on links: A/B swapped, LinkT -> 1 - LinkT (like MirrorFort in the game).
Everything after the Fort table goes along: modules with their triggers as written, FortRetire and the Bastion tables
FortSockets, FortStrip and FortZones (their positions converted, the AI reads them in the plan's own frame).
Usage: mid_to_long.py <mid-plan> <long-plan-original> <output>"""
import math, re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fortplan import MODULES_MARK, parse_plan, parse_lines, parse_modules, node_positions

DX, DY = 800.0, -2650.0
M = lambda p: (DX - p[0], p[1] + DY)

def f(p): return "x = %.2f, y = %.2f" % p

def convert_tables(text):
    """The tables between the Fort table and the modules, positions converted."""
    def cell(m):
        x, y = M((int(m.group(1)), int(m.group(2))))
        return "Cell = { x = %d, y = %d }" % (x, y)
    def box(m):
        x0, x1, y0, y1 = (int(g) for g in m.groups())
        return "Box = { x0 = %d, x1 = %d, y0 = %d, y1 = %d }" % (DX - x1, DX - x0, y0 + DY, y1 + DY)
    def strut(m):
        a = [float(g) for g in m.groups()]
        return "{ %.2f, %.2f, %.2f, %.2f }" % (M(a[:2]) + M(a[2:]))
    def strip(m):
        return re.sub(r"\{ (-?[\d.]+), (-?[\d.]+), (-?[\d.]+), (-?[\d.]+) \}", strut, m.group(0))
    text = re.sub(r"Cell = \{ x = (-?\d+), y = (-?\d+) \}", cell, text)
    text = re.sub(r"Box = \{ x0 = (-?\d+), x1 = (-?\d+), y0 = (-?\d+), y1 = (-?\d+) \}", box, text)
    return re.sub(r"^FortStrip = .*$", strip, text, flags=re.M)

def convert(src, long_orig, dst):
    h, acts = parse_plan(src)
    mods = parse_modules(src)
    # the modules' starting-fort nodes too (a module may use one the plan never touches, e.g. Vanilla-5's laser front)
    mid_pos = node_positions(acts + [a for m in mods for a in m["actions"]])
    _, lacts = parse_plan(long_orig)
    lpos = {k: v for k, v in node_positions(lacts).items() if k < 10000}
    idmap = {}
    for k, v in mid_pos.items():
        if k >= 10000:
            continue
        m = M(v)
        best = min(lpos.items(), key=lambda kv: math.dist(kv[1], m))
        assert math.dist(best[1], m) < 3, (k, v, best)
        idmap[k] = best[0]
    assert len(set(idmap.values())) == len(idmap)
    nid = lambda i: idmap.get(i, i)
    npos = lambda i, p: lpos[idmap[i]] if i in idmap else M(p)
    def conv(a):
        line = conv_action(a)
        socket = re.search(r'Socket = "[^"]*"', a["raw"])    # the socket a device stands in (Bastion)
        return line[:-3] + ", " + socket.group(0) + " }," if socket else line
    def conv_action(a):
        t = a["Type"]
        if t == "CREATE_NODE":
            A, B = a["OriginalNodeAId"], a["OriginalNodeBId"]
            return ('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, NewNodePos = { %s }, MaterialSaveName = "%s" },'
                    % (nid(A), f(npos(A, a["PosA"])), nid(B), f(M(a["NewNodePos"])), a["MaterialSaveName"]))
        elif t == "CREATE_LINK":
            A, B = a["OriginalNodeAId"], a["OriginalNodeBId"]
            return ('{ Type = CREATE_LINK, OriginalNodeAId = %d, PosA = {%s }, OriginalNodeBId = %d, PosB = { %s }, MaterialSaveName = "%s" },'
                    % (nid(A), f(npos(A, a["PosA"])), nid(B), f(npos(B, a["PosB"])), a["MaterialSaveName"]))
        elif t == "CREATE_DEVICE" and "GroundPosition" in a:
            return ('{ Type = CREATE_DEVICE, GroundPosition = { %s }, LinkT = %s, DeviceSaveName = "%s" },'
                    % (f(M(a["GroundPosition"])), re.search(r"LinkT = ([\d.]+)", a["raw"]).group(1), a["DeviceSaveName"]))
        elif t == "CREATE_DEVICE":
            A, B = a["OriginalNodeAId"], a["OriginalNodeBId"]
            pa, pb = npos(A, a["PosA"]), npos(B, a["PosB"])
            return ('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                    % (nid(B), f(pb), nid(A), f(pa), 1.0 - a["LinkT"], a["DeviceSaveName"]))
        elif t == "DESTROY_DEVICE":         # selling a device (e.g. of the starting fort): A/B swapped like devices
            A, B = a["OriginalNodeAId"], a["OriginalNodeBId"]
            return ('{ Type = DESTROY_DEVICE, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, DeviceSaveName = "%s" },'
                    % (nid(B), f(npos(B, a["PosB"])), nid(A), f(npos(A, a["PosA"])), a["DeviceSaveName"]))
        elif t == "DESTROY_LINK":           # removing a strut (recorded plans: the starting fort's prow)
            A, B = a["OriginalNodeAId"], a["OriginalNodeBId"]
            return ('{ Type = DESTROY_LINK, OriginalNodeAId = %d, PosA = { %s }, OriginalNodeBId = %d, PosB = { %s }, },'
                    % (nid(A), f(npos(A, a["PosA"])), nid(B), f(npos(B, a["PosB"]))))
        raise ValueError(a["raw"])
    out = [conv(a) for a in acts]
    source = open(src, encoding="latin-1", newline="").read().replace("\r\n", "\n")
    before, _, modules = source.partition(MODULES_MARK)
    tables = "".join(ln + "\n" for ln in before[before.index("\n}\n", before.index("\nFort =")) + 3:].splitlines() if not ln.startswith("-- Generated by"))
    # reactive build modules: every line as written but the actions (their own node ids, 20000 and up, keep their numbers)
    mod_text = ""
    if modules:
        mod_text = "FortModules =" + "\n".join(
            conv(parse_lines([ln])[0]) if ln.strip().startswith("{ Type") else ln for ln in modules.split("\n"))
    head = ("-- Fort recorded for AI replay\n"
            "CREATE_NODE = 1\nDESTROY_NODE = 2\nCREATE_LINK = 3\nDESTROY_LINK = 4\nCREATE_DEVICE = 5\nDESTROY_DEVICE = 6\n")
    lh, _ = parse_plan(long_orig)
    header = "FortTeam = %d; FortId = %d; FortPos = { x = %.6f, y = %.6f }; " % (lh["team"], lh["fort"], lh["pos"][0], lh["pos"][1])
    tail = "-- Generated by Claude AI (.dev/tools/fortgen/mid_to_long.py) from %s\n" % os.path.basename(src)
    with open(dst, "w", encoding="ascii", newline="\r\n") as fh:
        fh.write(head + header + "\n\nFort =\n{\n" + "\n".join(out) + "\n}\n" + tail + convert_tables(tables) + mod_text)
    return len(out)

if __name__ == "__main__":
    print(convert(*sys.argv[1:4]))
