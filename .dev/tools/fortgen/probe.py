#!/usr/bin/env python3
"""FORT 9000 - read the PROBE lines of a CS_UNSTABLE probe run (.dev/docs/debugging.md).

With FortPlanConfig.Probe set in ai/fortplans.lua the AI tries every probe device at every LinkT on every strut
of its finished fort and writes (world coordinates, node ids are the engine's):
  [CAI] T<team> PROBE START t=<s> devices=<a,b> linkt=<t,t> struts=<n> steep=<n> attempts=<n> mirrored=<0|1>
  [CAI] T<team> PROBE NODE part=<k>/<n> <id>:<x>,<y>:<plan node id|-> ...
  [CAI] T<team> PROBE LINK part=<k>/<n> <a>-<b>:<material>:<stress>[:<device>@<LinkT>,...] ...
  [CAI] T<team> PROBE TRY <k> <device> <a>-<b> t=<LinkT> r=<OK|result> s=.. sn=.. len=.. ang=.. sag=a,b v=a,b
                  dv=<devices on the strut> dn=<devices on the other struts at its nodes> near=<their types|->
  [CAI] T<team> PROBE LOAD <k> <device> <a>-<b> s=.. sn=.. top=<stress>:<a>-<b> d=dxA,dyA,dxB,dyB
  [CAI] T<team> PROBE END tried=<n> placed=<n> unstable=<n> other=<n>
This tool prints per device how many attempts were placed or refused, how the refusals depend on each measured
value (strut stress s, largest stress at the strut's nodes sn, length, angle, sag, LinkT, devices on the strut
dv and on its neighbours dn) and how the results split by devices nearby, the single
threshold that best separates placed from CS_UNSTABLE, lists the refused struts, and optionally writes every
attempt as CSV (for fitting a model) and a map per device (green placed, red CS_UNSTABLE, orange mixed).

Usage:
  probe.py [log.txt] [--team 102] [--match -1] [--csv out.csv] [--png out.png] [--list 15]
Default log: the Forts log of the user next to this mod; default team: the one with PROBE lines; default match:
the last one with PROBE lines. --png writes one image per device (out-<device>.png).
"""
import argparse
import csv
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
from shape import default_log, matches   # noqa: E402
import train                             # noqa: E402

PROBE_RE = re.compile(r"\[CAI\] T(\d+) PROBE (\w+) ?(.*)")
TRY_RE = re.compile(r"(\d+) (\S+) (\d+)-(\d+) t=(\S+) r=(\S+)(.*)")
LOAD_RE = re.compile(r"(\d+) (\S+) (\d+)-(\d+) (.*)")
FEATURES = ("s", "abs_s", "sn", "len", "ang", "sag", "v", "t", "dv", "dn")


def kv(text):
    return dict(p.split("=", 1) for p in text.split() if "=" in p)


class Run:
    def __init__(self, team):
        self.team = team
        self.start = {}
        self.end = {}
        self.nodes = {}       # id -> (x, y, plan node id or None)
        self.links = []       # (a, b, material, stress, [device@LinkT, ...]) at the start
        self.tries = []       # dicts, one per attempt
        self.loads = {}       # attempt number -> dict


def read_runs(lines):
    """PROBE data per team of one match: {team: Run}."""
    runs = {}
    for line in lines:
        m = PROBE_RE.search(line)
        if not m:
            continue
        team, kind, rest = m.group(1), m.group(2), m.group(3)
        if kind == "START":          # a new probe of that team replaces an earlier one
            runs[team] = Run(team)
        run = runs.setdefault(team, Run(team))
        if kind == "START":
            run.start = kv(rest)
        elif kind == "END":
            run.end = kv(rest)
        elif kind == "NODE":
            for item in rest.split()[1:]:
                n, xy, orig = item.split(":")
                x, y = xy.split(",")
                run.nodes[int(n)] = (float(x), float(y), None if orig == "-" else int(orig))
        elif kind == "LINK":
            for item in rest.split()[1:]:
                ends, mat, s, *devs = item.split(":")
                a, b = ends.split("-")
                run.links.append((int(a), int(b), mat, float(s), devs[0].split(",") if devs else []))
        elif kind == "TRY":
            t = TRY_RE.match(rest)
            if not t:
                continue
            row = {"k": int(t.group(1)), "device": t.group(2), "a": int(t.group(3)), "b": int(t.group(4)),
                   "t": float(t.group(5)), "r": t.group(6)}
            v = kv(t.group(7))
            if "s" in v:
                sag = [int(x) for x in v["sag"].split(",")]
                speed = [int(x) for x in v["v"].split(",")]
                row.update(s=float(v["s"]), abs_s=abs(float(v["s"])), sn=float(v["sn"]), len=float(v["len"]),
                           ang=float(v["ang"]), v=max(speed))
                if max(sag) >= 0:      # -1: not a plan node
                    row["sag"] = max(sag)
                if "dv" in v:          # logged since the device columns were added
                    row.update(dv=int(v["dv"]), dn=int(v["dn"]), near=v["near"])
            run.tries.append(row)
        elif kind == "LOAD":
            t = LOAD_RE.match(rest)
            if t:
                v = kv(t.group(5))
                d = [int(x) for x in v.get("d", "0,0,0,0").split(",")] if v.get("d", "-") != "-" else [0, 0, 0, 0]
                run.loads[int(t.group(1))] = {"load_s": float(v["s"]), "load_sn": float(v["sn"]),
                                              "load_top": float(v["top"].split(":")[0]),
                                              "load_drop": max(d[1], d[3])}
    return runs


def label(run, n):
    p = run.nodes.get(n)
    if p is None:
        return "N%d" % n
    return "(%d,%d)%s" % (p[0], p[1], "P%d" % p[2] if p[2] is not None else "")


def best_split(rows, f):
    """Threshold on feature f that best separates OK from CS_UNSTABLE: (accuracy, threshold, unstable side)."""
    pts = sorted((r[f], r["r"] == "CS_UNSTABLE") for r in rows if f in r)
    if not pts:
        return None
    n_bad = sum(1 for _, bad in pts if bad)
    best = (max(n_bad, len(pts) - n_bad) / len(pts), None, "-")
    bad_below = 0
    for i in range(len(pts) - 1):
        bad_below += pts[i][1]
        if pts[i][0] == pts[i + 1][0]:
            continue
        thr = (pts[i][0] + pts[i + 1][0]) / 2
        ok_below = i + 1 - bad_below
        bad_above = n_bad - bad_below
        ok_above = len(pts) - (i + 1) - bad_above
        for acc, side in (((bad_above + ok_below) / len(pts), ">"), ((bad_below + ok_above) / len(pts), "<")):
            if acc > best[0]:
                best = (acc, thr, side)
    return best


def quartiles(rows, f):
    vals = sorted(r[f] for r in rows if f in r)
    if not vals:
        return "-"
    q = lambda p: vals[min(len(vals) - 1, int(p * (len(vals) - 1) + 0.5))]
    return "%8.3f %8.3f %8.3f" % (q(0.25), q(0.5), q(0.75))


def report(run, n_list):
    st = run.start
    print("team %s: probe started at t=%ss, devices %s, LinkT %s, %s struts (%s too steep, left out), %s attempts; "
          "%d nodes, %d struts in the fort"
          % (run.team, st.get("t", "?"), st.get("devices", "?"), st.get("linkt", "?"), st.get("struts", "?"),
             st.get("steep", "?"), st.get("attempts", "?"), len(run.nodes), len(run.links)))
    if run.end:
        print("finished: " + " ".join("%s=%s" % kv_ for kv_ in sorted(run.end.items())))
    else:
        print("not finished (no PROBE END line): %d attempts logged" % len(run.tries))
    for dev in sorted({r["device"] for r in run.tries}):
        rows = [r for r in run.tries if r["device"] == dev]
        counts = {}
        for r in rows:
            counts[r["r"]] = counts.get(r["r"], 0) + 1
        print("\n== %s: %d attempts, %s" % (dev, len(rows), ", ".join("%s %d" % c for c in sorted(counts.items()))))
        decided = [r for r in rows if r["r"] in ("OK", "CS_UNSTABLE") and "s" in r]
        ok = [r for r in decided if r["r"] == "OK"]
        bad = [r for r in decided if r["r"] == "CS_UNSTABLE"]
        if ok and bad:
            print("   %-6s  %-26s  %-26s  %s" % ("value", "placed: q25 / median / q75", "CS_UNSTABLE: q25 / med / q75",
                                                 "best single split (accuracy)"))
            for f in FEATURES:
                b = best_split(decided, f)
                split = "unstable if %s %s %.3f (%.0f %%)" % (f, b[2], b[1], 100 * b[0]) if b and b[1] is not None else "-"
                print("   %-6s  %-26s  %-26s  %s" % (f, quartiles(ok, f), quartiles(bad, f), split))
        if any("dv" in r for r in decided):
            groups = {}
            for r in decided:
                key = "device on the strut" if r["dv"] else "devices at its nodes" if r["dn"] else "no device near"
                groups.setdefault(key, [0, 0])[r["r"] == "CS_UNSTABLE"] += 1
            print("   by devices already standing there (placed / CS_UNSTABLE):")
            for key in ("no device near", "devices at its nodes", "device on the strut"):
                if key in groups:
                    print("     %-22s %4d / %d" % (key, groups[key][0], groups[key][1]))
        loads = [dict(r, **run.loads[r["k"]]) for r in ok if r["k"] in run.loads]
        if loads:
            print("   under load (Hold): strut stress median %.3f, max at the nodes median %.3f, node drop median %d"
                  % (sorted(x["load_s"] for x in loads)[len(loads) // 2],
                     sorted(x["load_sn"] for x in loads)[len(loads) // 2],
                     sorted(x["load_drop"] for x in loads)[len(loads) // 2]))
        refused = {}
        for r in bad:
            refused.setdefault((r["a"], r["b"]), []).append(r)
        if refused:
            print("   refused struts (CS_UNSTABLE at LinkT ...; sn = largest stress at its nodes):")
            for (a, b), rs in sorted(refused.items(), key=lambda kv_: -kv_[1][0]["sn"])[:n_list]:
                r0 = rs[0]
                print("     %s-%s  t=%s  s=%.3f sn=%.3f len=%.0f ang=%.0f sag=%d%s" % (
                    label(run, a), label(run, b), ",".join("%.2f" % r["t"] for r in rs), r0["s"], r0["sn"], r0["len"],
                    r0["ang"], r0.get("sag", -1),
                    "  dv=%d near=%s" % (r0["dv"], r0["near"]) if "dv" in r0 else ""))
            if len(refused) > n_list:
                print("     ... %d more" % (len(refused) - n_list))


def write_csv(run, path):
    cols = ["k", "device", "a", "b", "t", "r", "s", "sn", "len", "ang", "sag", "v", "dv", "dn", "near",
            "xa", "ya", "xb", "yb", "plan_a", "plan_b", "load_s", "load_sn", "load_top", "load_drop"]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in run.tries:
            row = dict(r)
            row.pop("abs_s", None)
            for end in ("a", "b"):
                p = run.nodes.get(r[end])
                if p:
                    row["x" + end], row["y" + end], row["plan_" + end] = p[0], p[1], p[2] if p[2] is not None else ""
            row.update(run.loads.get(r["k"], {}))
            w.writerow(row)
    print("\nwritten:", path)


def draw(run, out):
    from PIL import Image, ImageDraw
    if not run.nodes:
        return
    xs = [p[0] for p in run.nodes.values()]
    ys = [p[1] for p in run.nodes.values()]
    x0, x1, y0, y1 = min(xs) - 60, max(xs) + 60, min(ys) - 60, max(ys) + 60
    k = min(1.0, 1400 / max(1, x1 - x0))
    root, ext = os.path.splitext(out)
    for dev in sorted({r["device"] for r in run.tries}):
        img = Image.new("RGB", (int((x1 - x0) * k), int((y1 - y0) * k) + 20), (245, 235, 205))
        g = ImageDraw.Draw(img)
        P = lambda n: ((run.nodes[n][0] - x0) * k, (run.nodes[n][1] - y0) * k + 20)
        for a, b, _, _, _ in run.links:
            if a in run.nodes and b in run.nodes:
                g.line([P(a), P(b)], fill=(190, 175, 150), width=1)
        res = {}
        for r in run.tries:
            if r["device"] == dev:
                res.setdefault((r["a"], r["b"]), []).append(r["r"])
        for (a, b), rs in res.items():
            if a not in run.nodes or b not in run.nodes:
                continue
            n_ok, n_bad = rs.count("OK"), rs.count("CS_UNSTABLE")
            col = ((40, 160, 40) if n_ok and not n_bad else (220, 30, 30) if n_bad and not n_ok
                   else (235, 140, 0) if n_ok and n_bad else (120, 120, 120))
            g.line([P(a), P(b)], fill=col, width=3)
        for a, b, _, _, devs in run.links:      # devices already standing in the fort
            if a in run.nodes and b in run.nodes:
                for d in devs:
                    t = float(d.split("@")[1]) if "@" in d else 0.5
                    pa, pb = P(a), P(b)
                    x, y = pa[0] + t * (pb[0] - pa[0]), pa[1] + t * (pb[1] - pa[1])
                    g.rectangle([x - 4, y - 8, x + 4, y], fill=(40, 70, 200))
        g.text((5, 3), "%s: green placed, red CS_UNSTABLE, orange depends on LinkT, grey other error, blue existing device"
               % dev, fill=(0, 0, 0))
        path = "%s-%s%s" % (root, dev, ext or ".png")
        img.save(path)
        print("written:", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log", nargs="?", default=None)
    ap.add_argument("--team", help="team with the probe (default: the one with PROBE lines)")
    ap.add_argument("--match", type=int, help="index of the match in the log (default: last one with a probe)")
    ap.add_argument("--csv", help="write every attempt as CSV")
    ap.add_argument("--png", help="draw a map per device (out-<device>.png)")
    ap.add_argument("--list", type=int, default=15, help="refused struts to list per device")
    args = ap.parse_args()
    path = args.log or default_log()
    if not path:
        sys.exit("no log found; pass the log file")
    ms = matches(train.read_log(path))
    if not ms:
        ms = [train.read_log(path)]      # a log without recorder lines (e.g. the recorder mod was off)
    if args.match is not None:
        ms = [ms[args.match]]
    for lines in reversed(ms):
        runs = read_runs(lines)
        if args.team:
            runs = {t: r for t, r in runs.items() if t == args.team}
        if runs:
            break
    else:
        sys.exit("no PROBE lines in %s" % path)
    print("log %s" % path)
    for team in sorted(runs):
        run = runs[team]
        report(run, args.list)
        if args.csv:
            write_csv(run, args.csv if len(runs) == 1 else args.csv.replace(".csv", "-%s.csv" % team))
        if args.png:
            draw(run, args.png if len(runs) == 1 else args.png.replace(".png", "-%s.png" % team))


if __name__ == "__main__":
    main()
