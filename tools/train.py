#!/usr/bin/env python3
"""FORT 9000 for Forts - training from matches and replays.

Flow:
  1. collect: copies the current Forts log (users/<id>/log.txt) into the archive tools/logs/
     if it contains recorder data ([CREC]). Forts overwrites log.txt on every start,
     so collect after every play session!
  2. train: reads ALL archived logs, learns from them and rewrites ai/strategy.lua.
     It always learns from the default values again - running it repeatedly
     therefore shifts nothing, only new matches change the result.

Usage:
  python train.py              -> collect + train
  python train.py collect      -> only archive the log
  python train.py train        -> only train
  python train.py report       -> only show the evaluation, write nothing
Options:
  --strength 0.5   how far the learned values may deviate from the defaults (0..1)
  --log PATH       collect one specific log instead of users/*/log.txt
"""
import argparse
import glob
import hashlib
import json
import math
import os
import re
import shutil
import sys
import time
from collections import defaultdict

TOOLS = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(TOOLS)
FORTS = os.path.normpath(os.path.join(MOD, "..", "..", ".."))
ARCHIVE = os.path.join(TOOLS, "logs")
STRATEGY = os.path.join(MOD, "ai", "strategy.lua")
REPORT_JSON = os.path.join(TOOLS, "last_training.json")

FPS = 25                 # assumption: game frames per second (for the phases)
WINDOW_FRAMES = 375      # time window before/after a loss (3 snapshots)
MIN_CONF_EVENTS = 5      # from this many observations a type counts half

# firepower weight per weapon type (for "how much does a loss weaken the opponent")
WEAPON_WEIGHT = {
    "machinegun": 0.3, "minigun": 0.6, "sniper": 0.8, "sniper2": 1.0,
    "mortar": 1.5, "mortar2": 2.0, "missile": 2.0, "missileinv": 2.0,
    "missile2": 3.0, "missile2inv": 3.0, "cannon": 3.0, "laser": 3.0,
    # DLC weapons
    "rocket": 2.0, "rocketemp": 1.5, "buzzsaw": 2.0, "flak": 0.5, "shotgun": 1.0, "shrapnel": 1.5,
    "firebeam": 2.5, "magnabeam": 2.0, "smokelauncher": 0.2, "howitzer": 3.0,
}
DEFAULT_WEAPON_WEIGHT = 1.0

# default values - identical to the shipped strategy.lua
DEFAULTS = {
    "Version": 1,
    "TrainedGames": 0,
    "LogDecisions": True,
    "ThinkInterval": 5,
    "ThreatWeight": 30,
    "ThreatHalf": 10,
    "ThreatDecay": 0.85,
    "ThreatPerShot": 1,
    "ThreatPerHit": 3,
    "ThreatPerReactorHit": 6,
    "EarlySeconds": 120,
    "LateSeconds": 480,
    "Aggression": {"Early": 0.85, "Mid": 1.0, "Late": 1.2},
    "AggressionExclude": {"machinegun": True},
    "RichMetal": 1500, "RichBoost": 1.15,
    "PoorMetal": 150, "PoorEnergy": 300, "PoorFactor": 0.75,
    "IndirectThreatTypes": {k: True for k in ["mortar", "mortar2", "missile", "missileinv", "missile2", "missile2inv"]},
    "AntiAirThreatShots": 6,
    "AntiAirBoostMax": 1.4,
    "RebuildGiveUpSeconds": 120,
    "BuildSkipSeconds": 90,
    "BuildSkipMinMetal": 300,
    "Fire": {"Enabled": True, "Interval": 1.0, "WeaponsPerTick": 3, "AlwaysOffensive": True, "RebuildFireFactor": 2.5},
    "Tempo": {"UpdatePeriod": 2.0, "UpdatePeriodEasy": 4.0, "UpdatePeriodNormal": 2.0, "UpdatePeriodHard": 1.0, "UpdateAfterRebuildDelay": 0.625, "ConstructionMean": 20, "ConstructionMin": 12,
              "NonConstructionMean": 6, "NonConstructionMin": 3, "RepairPeriod": 6,
              "RepairPeriodEasy": 12, "RepairPeriodNormal": 6, "RepairPeriodHard": 3},
    "TargetValue": {
        "Heavy": dict(zip(
            ["cannon", "laser", "barreltemp", "reactor", "turbine2", "mine2", "turbine", "mine", "factory",
             "workshop", "upgrade", "machinegun", "mortar2", "battery", "missile2", "missile2inv", "missile",
             "missileinv", "store", "sniper2", "sniper", "minigun"],
            range(100, 0, -4))),
        "Small": dict(zip(
            ["sniper2", "barreltemp", "sniper", "minigun", "mortar2", "mortar", "machinegun", "cannon", "laser",
             "reactor", "mine2", "turbine2", "mine", "turbine", "battery", "missile2", "missile2inv", "missile",
             "missileinv", "store"],
            range(100, 0, -4))),
    },
}

LINE_RE = re.compile(r"\[CREC\] f=(-?\d+) (\w+)(.*)")
CAI_RE = re.compile(r"\[CAI\] T(\d+) (\w+)(.*)")
# from the game itself: which teams are AI (team members 0) and which build plan they get
PLAN_RE = re.compile(r"\[CAI\] T(\d+) PLAN map=\S+ file=(\S+)")
ACT_RE = re.compile(r"ActivateAI team (\d+) team members (\d+) fort (.*)")


# ---------------------------------------------------------------- Reading logs

def read_log(path):
    raw = open(path, "rb").read()
    if raw[:2] == b"\xff\xfe" or (len(raw) > 1 and raw[1:2] == b"\x00"):
        text = raw.decode("utf-16-le", errors="replace")
    else:
        text = raw.decode("utf-8", errors="replace")
    return text.replace("﻿", "").replace("\r", "").split("\n")


def parse_kv(rest):
    out = {}
    for token in rest.split():
        if "=" in token:
            k, v = token.split("=", 1)
            out[k] = v
    return out


def parse_counts(s):
    out = {}
    if not s:
        return out
    for part in s.split(","):
        if ":" in part:
            k, v = part.rsplit(":", 1)
            try:
                out[k] = float(v)
            except ValueError:
                pass
    return out


class Game:
    def __init__(self, source):
        self.source = source
        self.snaps = {1: [], 2: []}   # side -> [(frame, metal, energy, dev, shots)]
        self.lost = []                # (frame, side, type)
        self.built = []
        self.winner = None
        self.ai_teams = set()         # sides on which the FORT 9000 AI ran
        self.ai_end = []
        self.ai_sides = {}            # side -> build plan of the AI (according to the game log)

    @property
    def frames(self):
        f = [s[0] for side in self.snaps.values() for s in side]
        return max(f) if f else 0


def parse_games(lines, source):
    games = []
    g = None
    pending_ai = {}
    pending_plan = {}
    for line in lines:
        a = ACT_RE.search(line)
        if a:
            team, members, fort = int(a.group(1)), int(a.group(2)), a.group(3).strip()
            if members == 0:
                pending_ai[team % 100] = os.path.basename(fort) or "?"
            continue
        pl = PLAN_RE.search(line)
        if pl:
            pending_plan[int(pl.group(1)) % 100] = pl.group(2)
            continue
        m = LINE_RE.search(line)
        if m:
            frame, kind, rest = int(m.group(1)), m.group(2), m.group(3)
            kv = parse_kv(rest)
            if kind == "START" or g is None:
                g = Game(source)
                # the FORT 9000 AI's own plan takes precedence over the one chosen by the game
                for side, plan in pending_plan.items():
                    if side in pending_ai and plan != "original":
                        pending_ai[side] = plan
                g.ai_sides = pending_ai
                pending_ai = {}
                pending_plan = {}
                games.append(g)
                if kind == "START":
                    continue
            side = int(kv.get("s", -1)) if kv.get("s", "-1").lstrip("-").isdigit() else -1
            if kind == "SNAP" and side in (1, 2):
                g.snaps[side].append((frame, float(kv.get("m", -1)), float(kv.get("e", -1)),
                                      parse_counts(kv.get("dev")), parse_counts(kv.get("shots"))))
            elif kind == "LOST" and side in (1, 2):
                g.lost.append((frame, side, kv.get("d", "?")))
            elif kind == "BUILT" and side in (1, 2):
                g.built.append((frame, side, kv.get("d", "?")))
            elif kind == "RESULT":
                w = int(kv.get("w", -1))
                g.winner = w if w in (1, 2) else None
            continue
        m = CAI_RE.search(line)
        if m and g is not None:
            team, kind, rest = int(m.group(1)), m.group(2), m.group(3)
            g.ai_teams.add(team % 100)
            if kind == "END":
                kv = parse_kv(rest)
                try:
                    g.ai_end.append((team % 100, int(kv.get("winner", -1)) % 100))
                except ValueError:
                    pass
    return [x for x in games if x.snaps[1] or x.snaps[2]]


# ---------------------------------------------------------------- Learning

def firepower(shots):
    return sum(n * WEAPON_WEIGHT.get(t, DEFAULT_WEAPON_WEIGHT) for t, n in shots.items())


def window_sum(snaps, lo, hi, fn):
    return sum(fn(s) for s in snaps if lo < s[0] <= hi)


def metal_at(snaps, frame):
    best = None
    for s in snaps:
        if s[0] <= frame:
            best = s
    return best[1] if best else None


def learn(games, strength):
    impact = defaultdict(list)   # type -> list of effects of a loss on the loser
    lift_games = defaultdict(list)
    phase_share = {"Early": [], "Mid": [], "Late": []}
    early_f = DEFAULTS["EarlySeconds"] * FPS
    late_f = DEFAULTS["LateSeconds"] * FPS

    for g in games:
        for frame, side, typ in g.lost:
            snaps = g.snaps[side]
            if not snaps:
                continue
            before = window_sum(snaps, frame - WINDOW_FRAMES, frame, lambda s: firepower(s[4]))
            after = window_sum(snaps, frame, frame + WINDOW_FRAMES, lambda s: firepower(s[4]))
            # end of the match: no full window afterwards -> skip
            if not any(s[0] > frame + WINDOW_FRAMES * 0.6 for s in snaps):
                continue
            fire_drop = (before - after) / max(before, 1.0)
            m0, mb, ma = metal_at(snaps, frame), metal_at(snaps, frame - WINDOW_FRAMES), metal_at(snaps, frame + WINDOW_FRAMES)
            econ_drop = 0.0
            if None not in (m0, mb, ma) and min(m0, mb, ma) >= 0:
                inc_before, inc_after = m0 - mb, ma - m0
                econ_drop = (inc_before - inc_after) / max(abs(inc_before), 50.0)
            impact[typ].append(max(-1.0, min(1.0, fire_drop + 0.3 * econ_drop)))

        if g.winner:
            loser = 3 - g.winner
            kills_by_winner = defaultdict(int)
            kills_by_loser = defaultdict(int)
            for _, side, typ in g.lost:
                if side == loser:
                    kills_by_winner[typ] += 1
                else:
                    kills_by_loser[typ] += 1
            for typ in set(kills_by_winner) | set(kills_by_loser):
                kw, kl = kills_by_winner[typ], kills_by_loser[typ]
                lift_games[typ].append((kw - kl) / (kw + kl + 1.0))

            for phase, lo, hi in (("Early", -1, early_f), ("Mid", early_f, late_f), ("Late", late_f, 10 ** 12)):
                wf = window_sum(g.snaps[g.winner], lo, hi, lambda s: firepower(s[4]))
                lf = window_sum(g.snaps[loser], lo, hi, lambda s: firepower(s[4]))
                if wf + lf > 0:
                    phase_share[phase].append(wf / (wf + lf))

    strategy = json.loads(json.dumps(DEFAULTS))
    learned_types = {}
    for typ in sorted(set(impact) | set(lift_games)):
        imp = sum(impact[typ]) / len(impact[typ]) if impact[typ] else 0.0
        lift = sum(lift_games[typ]) / len(lift_games[typ]) if lift_games[typ] else 0.0
        n = len(impact[typ]) + len(lift_games[typ])
        conf = n / (n + MIN_CONF_EVENTS)
        learned = 50 + 35 * imp + 15 * lift
        shift = strength * conf * (learned - 50)
        learned_types[typ] = {"n": n, "impact": round(imp, 3), "winLift": round(lift, 3),
                              "conf": round(conf, 2), "shift": round(shift, 1)}
        for cls in ("Heavy", "Small"):
            table = strategy["TargetValue"][cls]
            if typ in table:
                table[typ] = round(max(0.0, min(150.0, table[typ] + shift)), 1)
            elif cls == "Heavy":
                # add new device types (e.g. from mods/DLC) with a neutral value
                table[typ] = round(max(0.0, min(150.0, 30 + shift)), 1)

    aggression = {}
    n_games = sum(1 for g in games if g.winner)
    conf_g = n_games / (n_games + 3.0)
    for phase, shares in phase_share.items():
        share = sum(shares) / len(shares) if shares else 0.5
        factor = 1 + strength * conf_g * (share - 0.5) * 2
        val = round(max(0.4, min(1.8, DEFAULTS["Aggression"][phase] * factor)), 3)
        strategy["Aggression"][phase] = val
        aggression[phase] = {"winnerFireShare": round(share, 3), "games": len(shares), "value": val}

    strategy["TrainedGames"] = n_games
    return strategy, learned_types, aggression


# ---------------------------------------------------------------- Writing Lua

def lua_value(v, indent):
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(v, 4)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, dict):
        lines = ["{"]
        for k in sorted(v):
            key = k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else '["%s"]' % k
            lines.append("%s\t%s = %s," % (pad, key, lua_value(v[k], indent + 1)))
        lines.append(pad + "}")
        return "\n".join(lines)
    raise TypeError(type(v))


def write_strategy(strategy, n_logs):
    if os.path.exists(STRATEGY):
        shutil.copyfile(STRATEGY, os.path.join(MOD, "ai", "strategy_previous.lua"))
    header = (
        "-- FORT 9000 - strategy file (generated automatically by tools/train.py)\n"
        "-- Trained on %s from %d matches with a result in %d logs.\n"
        "-- Loaded once at the start of a match. Previous version: strategy_previous.lua\n\n"
        % (time.strftime("%Y-%m-%d %H:%M"), strategy["TrainedGames"], n_logs))
    with open(STRATEGY, "w", encoding="ascii", newline="\n") as f:
        f.write(header + "Strategy =\n" + lua_value(strategy, 0) + "\n")


# ---------------------------------------------------------------- Commands

def find_logs(explicit):
    if explicit:
        return [explicit]
    return sorted(glob.glob(os.path.join(FORTS, "users", "*", "log.txt")))


def collect(explicit=None):
    os.makedirs(ARCHIVE, exist_ok=True)
    known = {f.split("_")[-1].split(".")[0] for f in os.listdir(ARCHIVE)}
    added = 0
    for path in find_logs(explicit):
        lines = read_log(path)
        if not any("[CREC]" in l for l in lines):
            print("  %s: no recorder data, skipped" % path)
            continue
        digest = hashlib.sha1("\n".join(lines).encode("utf-8")).hexdigest()[:12]
        if digest in known:
            print("  %s: already archived" % path)
            continue
        stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(os.path.getmtime(path)))
        dest = os.path.join(ARCHIVE, "log_%s_%s.txt" % (stamp, digest))
        with open(dest, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines))
        known.add(digest)
        added += 1
        print("  archived: %s" % os.path.basename(dest))
    return added


def game_key(g):
    """Fingerprint of a match so that the same match from several logs counts only once."""
    parts = [str(g.winner), str(sorted(g.ai_sides.items()))]
    for side in (1, 2):
        parts += ["%d:%d:%s:%s" % (side, s[0], s[1], sorted(s[3].items())) for s in g.snaps[side]]
    parts += ["%d:%d:%s" % x for x in g.lost]
    return hashlib.sha1("|".join(parts).encode("utf-8")).hexdigest()


def load_archive():
    games, logs, seen, dupes = [], 0, set(), 0
    for path in sorted(glob.glob(os.path.join(ARCHIVE, "*.txt"))):
        logs += 1
        for g in parse_games(read_log(path), os.path.basename(path)):
            k = game_key(g)
            if k in seen:
                dupes += 1
                continue
            seen.add(k)
            games.append(g)
    if dupes:
        print("  %d duplicate match(es) from overlapping logs skipped" % dupes)
    return games, logs


def report(games, learned_types, aggression, strategy):
    print("\nMatches in archive: %d (with result: %d)" % (len(games), sum(1 for g in games if g.winner)))
    ai_games = [(side, plan, g.winner) for g in games if g.winner for side, plan in g.ai_sides.items()]
    if not ai_games:  # old logs without ActivateAI lines: side 2 was the AI
        ai_games = [(2, "?", g.winner) for g in games if g.winner]
    wins = sum(1 for side, plan, w in ai_games if side == w)
    print("AI result: %d wins in %d matches" % (wins, len(ai_games)))
    per_plan = defaultdict(lambda: [0, 0])
    for side, plan, w in ai_games:
        per_plan[plan][1] += 1
        per_plan[plan][0] += (side == w)
    for plan, (w, n) in sorted(per_plan.items()):
        print("  Build plan %-28s %d/%d wins" % (plan, w, n))
    if learned_types:
        print("\nLearned target values (impact = how much a loss weakens the opponent, -1..1):")
        print("  %-14s %5s %8s %8s %7s %8s %8s" % ("Type", "n", "Impact", "WinLift", "Conf", "Heavy", "Small"))
        rows = sorted(learned_types.items(), key=lambda kv: -kv[1]["shift"])
        for typ, d in rows:
            print("  %-14s %5d %8.2f %8.2f %7.2f %8s %8s" % (
                typ, d["n"], d["impact"], d["winLift"], d["conf"],
                strategy["TargetValue"]["Heavy"].get(typ, "-"), strategy["TargetValue"]["Small"].get(typ, "-")))
    print("\nAggression per phase:")
    for phase, d in aggression.items():
        print("  %-6s winners' firepower share %.2f in %d matches -> %.2f" % (
            phase, d["winnerFireShare"], d["games"], d["value"]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", nargs="?", default="all", choices=["all", "collect", "train", "report"])
    ap.add_argument("--strength", type=float, default=0.5)
    ap.add_argument("--log")
    args = ap.parse_args()

    if args.cmd in ("all", "collect"):
        print("Collecting logs ...")
        collect(args.log)
        if args.cmd == "collect":
            return
    games, logs = load_archive()
    if not games:
        print("No matches with recorder data in the archive. Play with the mod enabled or watch a replay first.")
        return
    strategy, learned_types, aggression = learn(games, max(0.0, min(1.0, args.strength)))
    report(games, learned_types, aggression, strategy)
    if args.cmd != "report":
        write_strategy(strategy, logs)
        with open(REPORT_JSON, "w", encoding="utf-8") as f:
            json.dump({"games": len(games), "types": learned_types, "aggression": aggression}, f, indent=1)
        print("\nNew strategy written: %s" % STRATEGY)


if __name__ == "__main__":
    main()
