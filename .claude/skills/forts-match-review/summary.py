#!/usr/bin/env python3
"""FORT 9000 - summarise the matches in a Forts log (read-only).

Usage: py summary.py [log.txt] [--match N] [--team 102]
Without a path it reads <Forts>/users/<id>/log.txt (the first users folder with a log). The log may be UTF-16
(as Forts writes it) or UTF-8. Without --match it lists the matches; with --match N (1-based, -1 = last) it prints
the details of that match: plan, result, economy, shots, devices built and lost, build errors, gave-ups.
"""
import argparse
import glob
import os
import re
from collections import Counter

FORTS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "..", ".."))
FPS = 25


def read_log(path):
    raw = open(path, "rb").read()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        text = raw.decode("utf-16")
    else:
        text = raw.decode("utf-8", errors="replace")
    return text.replace("\r", "").split("\n")


def split_matches(lines):
    """Matches in a log, each as a list of lines. A match starts at "[CREC] f=0 START" or at a restart ("RevertMap":
    the game rewinds to frame 2 and logs no new plan, so the previous match's map/plan lines are kept) and ends at
    its last RESULT before the next match or an instant replay ("Starting instant replay"; its lines are left out).
    The recorder's own "START restart=1" right after a restart belongs to that restart."""
    starts, restart_at = [], None
    for i, l in enumerate(lines):
        if l.startswith("RevertMap "):
            starts.append((i, True))
            restart_at = i
        elif re.match(r"\[CREC\] f=\d+ START", l):
            if restart_at is not None and "restart=1" in l and i - restart_at < 60:
                continue
            starts.append((i, False))
            restart_at = None
    matches, header = [], []
    for k, (s, restart) in enumerate(starts):
        nxt = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
        body_start = s if restart else max(starts[k - 1][0] + 1 if k else 0, s - 40)
        replay = next((j for j in range(s, nxt) if "Starting instant replay" in lines[j]), nxt)
        results = [j for j in range(s, replay) if re.match(r"\[CREC\] f=\d+ RESULT", lines[j])]
        end = results[-1] + 3 if results else replay
        body = lines[body_start:min(end, nxt)]
        if not restart:
            header = [l for l in body if re.search(r"Loading map |ConfigureAI |\[CAI\] T\d+ PLAN ", l)]
        matches.append((header if restart else []) + body)
    return matches


def info(m, team):
    t = "\n".join(m)
    plan = re.search(r"\[CAI\] T%d PLAN (?:map=(\S+) )?file=(\S+)" % team, t)
    res = (re.findall(r"\[CREC\] f=(\d+) RESULT w=(-?\d+)", t) or [None])[-1]
    diff = re.search(r"ConfigureAI Team 2: Fort , Difficulty ([\d.]+)", t)
    mp = re.search(r"Loading map maps/([^/]+)/", t)
    return {
        "map": mp.group(1) if mp else (plan.group(1) if plan and plan.group(1) else "?"),
        "plan": plan.group(2) if plan else "?",
        "winner": res[1] if res else "-",
        "minutes": int(res[0]) / FPS / 60 if res else 0,
        "difficulty": diff.group(1) if diff else "?",
        "text": t,
    }


def details(m, team):
    d = info(m, team)
    t = d["text"]
    print("map %s, plan %s, AI difficulty %s, winner side %s (2 = AI), %.1f min"
          % (d["map"], d["plan"], d["difficulty"], d["winner"], d["minutes"]))
    end = re.search(r"\[CAI\] T%d END (.*)" % team, t)
    if end:
        print("END", end.group(1))
    for side, name in ((2, "AI"), (1, "player")):
        shots = Counter()
        for s in re.findall(r"SNAP s=%d \S+ m=\d+ e=\d+ dev=\S* shots=(\S*)" % side, t):
            for p in filter(None, s.split(",")):
                k, v = p.rsplit(":", 1)
                shots[k] += float(v)
        metal = [int(x) for x in re.findall(r"SNAP s=%d t=\d+ m=(\d+)" % side, t)] or [0]
        energy = [int(x) for x in re.findall(r"SNAP s=%d t=\d+ m=\d+ e=(\d+)" % side, t)] or [0]
        mines = [sum(int(x) for x in re.findall(r"mine2?:(\d+)", dv))
                 for dv in re.findall(r"SNAP s=%d \S+ m=\d+ e=\d+ dev=(\S*)" % side, t)] or [0]
        print("%-6s shots %s" % (name, dict((k, int(v)) for k, v in shots.most_common())))
        print("       metal avg %d (below 150: %d%%), energy avg %d, mines avg %.1f max %d"
              % (sum(metal) / len(metal), 100 * sum(x < 150 for x in metal) / len(metal),
                 sum(energy) / len(energy), sum(mines) / len(mines), max(mines)))
        print("       lost %s" % dict(Counter(re.findall(r"LOST s=%d \S+ d=(\w+)" % side, t)).most_common()))
    print("AI devices placed (s):", ", ".join("%s %d" % (dv, int(f) // FPS) for f, dv in
          re.findall(r"\[CREC\] f=(\d+) G?DEV s=2 \S+ \S+ d=(\w+)", t)))
    print("player devices placed (s):", ", ".join("%s %d" % (dv, int(f) // FPS) for f, dv in
          re.findall(r"\[CREC\] f=(\d+) G?DEV s=1 \S+ \S+ d=(\w+)", t)))
    errs = Counter(re.sub(r" action=\d+| \S+-\S*", "", e) for e in re.findall(r"\[CAI\] T%d BUILD_ERROR (.*)" % team, t))
    print("build errors:", dict(errs.most_common(15)) or "none")
    for kind in ("GAVE_UP", "SKIPPED", "ERROR"):
        hits = re.findall(r"\[CAI\] T%d %s (.*)" % (team, kind), t)
        print("%s: %d %s" % (kind, len(hits), hits[:5] if hits else ""))
    think = re.findall(r"\[CAI\] T%d THINK t=(\d+) build=(\d+/\d+).*? econ=(\w+) m=(\d+)\S* e=(\d+)" % team, t)
    print("THINK (t, build, econ, m, e) every ~60 s:", [x for i, x in enumerate(think) if i % 12 == 0])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log", nargs="?")
    ap.add_argument("--match", type=int)
    ap.add_argument("--team", type=int, default=102)
    a = ap.parse_args()
    path = a.log or next(iter(sorted(glob.glob(os.path.join(FORTS, "users", "*", "log.txt")))), None)
    if not path:
        raise SystemExit("no log found under %s/users" % FORTS)
    matches = split_matches(read_log(path))
    if a.match is None:
        print("%s: %d match(es)" % (path, len(matches)))
        for k, m in enumerate(matches, 1):
            d = info(m, a.team)
            print("%d: %s %s, difficulty %s, winner %s, %.1f min" % (k, d["map"], d["plan"], d["difficulty"], d["winner"], d["minutes"]))
    else:
        details(matches[a.match - 1 if a.match > 0 else a.match], a.team)


if __name__ == "__main__":
    main()
