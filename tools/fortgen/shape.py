#!/usr/bin/env python3
"""FORT 9000 - read the SHAPE lines of a match (how far each plan node has moved from its planned position).

The mod writes, on the first CS_UNSTABLE of a device and place and once per game minute:
  [CAI] T<team> SHAPE t=<s> why=<minute|unstable:<device>> mirrored=<0|1> part=<k>/<n> <plan node id>:<dx>,<dy> ...
dx/dy are already in the plan's own frame. This tool lays them over the plan file and prints, per snapshot,
how far each storey row has moved (forward = towards the enemy, down = sag), and the nodes that moved most.
It also prints the STRESS lines (the engine's own strut stress on CS_UNSTABLE) with plan positions.

Usage:
  shape.py [log.txt] [--team 102] [--match -1] [--plan fortplans/Vanilla/fort-t1f1-Vanilla-3.lua]
           [--min 5] [--png out.png] [--snap -1] [--scale 1]
Default log: the Forts log of the user next to this mod (<Forts>/users/<id>/log.txt); default match: the last
one in the log; default plan: the file named in the match's PLAN line (fortplans/<map>/<file>).
"""
import argparse
import glob
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
from fortplan import parse_plan, node_positions   # noqa: E402
import train                                       # noqa: E402

STRESS_RE = re.compile(r"\[CAI\] T(\d+) STRESS (\S+) (\S+) links=(\d+) at=(.*) top=(.*)")
SHAPE_RE = re.compile(r"\[CAI\] T(\d+) SHAPE t=(\S+) why=(\S+) mirrored=(\d) part=(\d+)/(\d+)(.*)")
PLAN_RE = re.compile(r"\[CAI\] T(\d+) PLAN map=(\S+) file=(\S+)")


def default_log():
    logs = glob.glob(os.path.join(MOD, "..", "..", "..", "users", "*", "log.txt"))
    return max(logs, key=os.path.getmtime) if logs else None


def matches(lines):
    """Split the log into matches: lists of lines from the end of the previous match's START (so the PLAN
    line, written just before START, belongs to its match) to the next START."""
    starts = [i for i, line in enumerate(lines) if "[CREC] f=0 START" in line]
    bounds = [0] + starts[1:] + [len(lines)]
    out = []
    for k, s in enumerate(starts):
        lo = starts[k - 1] + 1 if k else 0
        out.append(lines[lo:bounds[k + 1]])
    return out


def read_match(lines, team):
    """PLAN line (map, file), snapshots [(t, why, {node: (dx, dy)})] and STRESS lines [(device, nodes, links,
    at, top)] of one team in one match."""
    plan, snaps, cur, stress = None, [], None, []
    for line in lines:
        m = STRESS_RE.search(line)
        if m and m.group(1) == team:
            stress.append((m.group(2), m.group(3), int(m.group(4)), m.group(5).split(), m.group(6).split()))
            continue
        m = PLAN_RE.search(line)
        if m and m.group(1) == team:
            plan = (m.group(2), m.group(3))
        m = SHAPE_RE.search(line)
        if not m or m.group(1) != team:
            continue
        t, why, k = m.group(2), m.group(3), int(m.group(5))
        if k == 1 or cur is None or cur[0] != t or cur[1] != why:
            cur = (t, why, {})
            snaps.append(cur)
        for item in m.group(7).split():
            node, d = item.split(":")
            dx, dy = d.split(",")
            cur[2][int(node)] = (int(dx), int(dy))
    return plan, snaps, stress


def link_text(item, pos):
    """'P10052-N731:bracing:0.412' -> '  0.412 bracing     (-3100,-95)-N731' (plan nodes as plan positions)."""
    ends, mat, val = item.rsplit(":", 2)
    names = []
    for e in ends.split("-"):
        n = int(e[1:]) if e[1:].isdigit() else None
        names.append("(%d,%d)" % pos[n] if e.startswith("P") and n in pos else e)
    return "%7s %-11s %s" % (val, mat, "-".join(names))


def report_stress(stress, pos):
    for dev, nodes, links, at, top in stress:
        print("\n== STRESS %s on %s (%d struts in the fort)" % (dev, nodes, links))
        print("   at the device's nodes:")
        for item in at:
            print("     " + link_text(item, pos))
        print("   most stressed in the fort:")
        for item in top:
            print("     " + link_text(item, pos))


def report(snap, pos, forward, min_d):
    t, why, nodes = snap
    print("\n== t=%ss %s: %d nodes" % (t, why, len(nodes)))
    rows = {}
    for n, (dx, dy) in nodes.items():
        if n in pos:
            rows.setdefault(round(pos[n][1]), []).append((n, forward * dx, dy))
    print("   %6s %5s %9s %8s %9s   %s" % ("row y", "nodes", "fwd avg", "down avg", "max |d|", "node with max"))
    for y in sorted(rows):
        r = rows[y]
        fx = sum(v[1] for v in r) / len(r)
        dy = sum(v[2] for v in r) / len(r)
        n, f, d = max(r, key=lambda v: math.hypot(v[1], v[2]))
        print("   %6d %5d %9.0f %8.0f %9.0f   N%d (%d,%d)" % (y, len(r), fx, dy, math.hypot(f, d), n, pos[n][0], pos[n][1]))
    moved = sorted(((math.hypot(dx, dy), n, dx, dy) for n, (dx, dy) in nodes.items() if n in pos), reverse=True)
    top = [m for m in moved if m[0] >= min_d][:8]
    if top:
        print("   moved most: " + ", ".join("N%d (%d,%d) fwd %d down %d" % (n, pos[n][0], pos[n][1], forward * dx, dy)
                                          for _, n, dx, dy in top))


def draw(snap, acts, pos, out, scale):
    from PIL import Image, ImageDraw
    nodes = snap[2]
    pts = [pos[n] for n in nodes if n in pos]
    x0, x1 = min(p[0] for p in pts) - 150, max(p[0] for p in pts) + 150
    y0, y1 = min(p[1] for p in pts) - 150, max(p[1] for p in pts) + 150
    k = 0.6
    img = Image.new("RGB", (int((x1 - x0) * k), int((y1 - y0) * k)), (245, 235, 205))
    g = ImageDraw.Draw(img)
    P = lambda p: ((p[0] - x0) * k, (p[1] - y0) * k)
    for a in acts:
        ia, ib = a.get("OriginalNodeAId"), a.get("OriginalNodeBId")
        if a["Type"] in ("CREATE_NODE", "CREATE_LINK") and ia in pos and ib in pos:
            g.line([P(pos[ia]), P(pos[ib])], fill=(190, 170, 140), width=1)
    for n, (dx, dy) in nodes.items():
        if n not in pos:
            continue
        p = pos[n]
        q = (p[0] + dx * scale, p[1] + dy * scale)
        d = math.hypot(dx, dy)
        col = (40, 160, 40) if d < 20 else (230, 150, 0) if d < 60 else (220, 30, 30)
        g.line([P(p), P(q)], fill=col, width=2)
        g.ellipse([P(q)[0] - 2, P(q)[1] - 2, P(q)[0] + 2, P(q)[1] + 2], fill=col)
    g.text((5, 5), "t=%ss %s (arrows x%g; green <20, orange <60, red >=60)" % (snap[0], snap[1], scale), fill=(0, 0, 0))
    img.save(out)
    print("\nwritten:", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log", nargs="?", default=None)
    ap.add_argument("--team", default="102")
    ap.add_argument("--match", type=int, default=-1, help="index of the match in the log (default: last)")
    ap.add_argument("--plan", help="plan file (default: from the PLAN line)")
    ap.add_argument("--min", type=float, default=5, help="list nodes that moved at least this far")
    ap.add_argument("--png", help="draw one snapshot as arrows")
    ap.add_argument("--snap", type=int, default=-1, help="snapshot for --png (default: last)")
    ap.add_argument("--scale", type=float, default=1, help="arrow scale for --png")
    args = ap.parse_args()
    path = args.log or default_log()
    lines = train.read_log(path)
    ms = matches(lines)
    if not ms:
        sys.exit("no match in " + str(path))
    plan, snaps, stress = read_match(ms[args.match], args.team)
    if not snaps and not stress:
        sys.exit("no SHAPE or STRESS lines for team %s in that match" % args.team)
    plan_path = args.plan or (plan and os.path.join(MOD, "fortplans", plan[0], plan[1]))
    if not plan_path or not os.path.exists(plan_path):
        sys.exit("plan file not found (%s); pass --plan" % plan_path)
    head, acts = parse_plan(plan_path)
    pos = node_positions(acts)
    forward = -1 if head.get("team") == 2 else 1         # team 1 plans face the enemy on the right
    print("log %s, team %s, plan %s, %d snapshots" % (path, args.team, os.path.basename(plan_path), len(snaps)))
    for s in snaps:
        report(s, pos, forward, args.min)
    report_stress(stress, pos)
    if args.png and snaps:
        draw(snaps[args.snap], acts, pos, args.png, args.scale)


if __name__ == "__main__":
    main()
