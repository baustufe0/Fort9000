#!/usr/bin/env python3
"""FORT 9000 - turn a fort built by a player into an AI build plan (fort-t1f1-<map>-<no>.lua).

The recorder (script.lua) logs every node, strut and device a side builds ([CREC] NODE/LINK/DEV/GDEV and the
removals UNNODE/UNLINK/DEL/LOST). This tool replays those events for one side of one match and writes them
as plan actions, in the order the player built them:
  * a strut to a new node becomes CREATE_NODE from the end that already exists, every other strut CREATE_LINK;
  * devices on struts become CREATE_DEVICE (nodes + LinkT), ground devices CREATE_DEVICE with GroundPosition;
  * whatever the player built and removed again is left out (mistakes, scaffolding); removing a part of the
    starting fort becomes DESTROY_LINK / DESTROY_DEVICE;
  * an upgrade (machinegun -> minigun) keeps the old device and adds the new one, as the game's plans do;
  * nodes of the starting fort are matched by position to the node ids of the map's base plan
    (gen_fort.MAPS[map]["base_plan"]), new nodes get ids from 10000 on;
  * a fort built on side 2 is mirrored into the team-1 frame (x -> 2*pivot - x) the way the game mirrors
    plans for team 2 (device nodes swapped, LinkT -> 1 - LinkT).
Then it checks the plan like gen_fort.py does (build order, strut and new-node lengths, rock, rules.py).

Record best without combat (sandbox, or a match before the first shot; --until <frame> cuts the log there):
damage and repairs would otherwise turn into removals and rebuilds.

Usage:
  rec_fort.py --out fortplans/Vanilla/fort-t1f1-Vanilla-6.lua [--map Vanilla] [--log log.txt] [--match -1]
              [--side 1|2] [--team 101] [--until <frame>] [--pivot 0] [--title "..."]
Default log: the newest <Forts>/users/<id>/log.txt; default match: the last one; default side: the side
without an AI (ActivateAI ... team members 0).
"""
import argparse
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(os.path.dirname(HERE))
DATA = os.path.dirname(os.path.dirname(MOD))
sys.path.insert(0, HERE)
from fortplan import parse_plan, parse_lines, node_positions   # noqa: E402
from fwe import read_blocks                                    # noqa: E402
from terrain import Terrain                                    # noqa: E402
import gen_fort                                                 # noqa: E402
import rules                                                    # noqa: E402
from shape import default_log, matches                          # noqa: E402

CREC_RE = re.compile(r"\[CREC\] f=(-?\d+) (\w+)(.*)")
ACT_RE = re.compile(r"ActivateAI team (\d+) team members (\d+)")
SIDES = 100
BUILD_EVENTS = {"NODE", "LINK", "DEV", "GDEV"}
MATCH_TOL = 20.0          # max distance of a starting-fort node from its base plan node
GROUND_LINKT = 1.57       # ground devices in recorded plans


def kv(rest):
    out = {}
    for token in rest.split():
        if "=" in token:
            k, v = token.split("=", 1)
            out[k] = v
    return out


def pos(s):
    if not s or s == "-":
        return None
    x, y = s.split(",")
    return (float(x), float(y))


def read_events(lines, until=None):
    """[(frame, kind, {key: value})] of all [CREC] lines of one match."""
    out = []
    for line in lines:
        m = CREC_RE.search(line)
        if not m:
            continue
        f = int(m.group(1))
        if until is not None and f > until:
            break
        out.append((f, m.group(2), kv(m.group(3))))
    return out


def ai_sides(lines):
    sides = set()
    for line in lines:
        m = ACT_RE.search(line)
        if m and m.group(2) == "0":
            sides.add(int(m.group(1)) % SIDES)
    return sides


def pick_side(events, lines):
    built = {int(e["s"]) for _, k, e in events if k in BUILD_EVENTS and "s" in e}
    human = sorted(built - ai_sides(lines))
    if len(human) == 1:
        return human[0]
    if len(built) == 1:
        return built.pop()
    raise SystemExit("cannot tell which side the player built (sides with build events: %s); use --side"
                     % (sorted(built) or "none"))


class Recording:
    """Replays the build events of one side. Nodes are keyed ('new', serial) if built in the recording,
    ('pre', runtime id) if they belong to the starting fort."""

    def __init__(self, events, side, team=None):
        self.ops = []            # [kind, payload, alive] in log order
        self.node_pos = {}       # key -> first known position
        self.ground = set()      # new nodes on the ground (foundations)
        alive_node = {}          # runtime id -> key of the node currently using it
        alive_link = {}          # frozenset(keys) -> [op]
        alive_dev = {}           # device id -> op
        upgraded = set()         # device ids replaced by an upgrade (their removal is not a removal)
        pre_dead = set()         # runtime ids of starting-fort nodes that were destroyed (their id may come back)
        serial = 0

        def key(rid):
            return alive_node.get(rid, ("pre", rid))

        def learn(k, p):
            if p is not None:
                self.node_pos.setdefault(k, p)

        def adopt(old, new):
            """The game may report the strut to a new node before the node itself: the strut took the node
            for a starting-fort node, so hand its references over to the new node."""
            for op in self.ops:
                for f in ("a", "b"):
                    if op[1].get(f) == old:
                        op[1][f] = new
            for pair in [p for p in alive_link if old in p]:
                alive_link[frozenset(new if k == old else k for k in pair)] = alive_link.pop(pair)
            self.node_pos.pop(old, None)

        for _, kind, e in events:
            mine = "s" in e and int(e["s"]) == side and (team is None or e.get("t") == str(team))
            if kind == "UNNODE":
                k = alive_node.pop(int(e["n"]), None)
                if k is None:
                    pre_dead.add(int(e["n"]))
                    continue
                for op in self.ops:
                    if op[0] == "node" and op[1]["key"] == k:
                        op[2] = False
                continue
            if not mine:
                continue
            if kind == "NODE":
                serial += 1
                k = ("new", serial)
                rid = int(e["n"])
                if rid not in pre_dead:
                    adopt(("pre", rid), k)
                pre_dead.discard(rid)
                alive_node[rid] = k
                learn(k, pos(e.get("p")))
                if e.get("g") == "1":
                    self.ground.add(k)
                self.ops.append(["node", {"key": k}, True])
            elif kind == "LINK":
                ka, kb = key(int(e["a"])), key(int(e["b"]))
                learn(ka, pos(e.get("pa")))
                learn(kb, pos(e.get("pb")))
                op = ["link", {"a": ka, "b": kb, "m": e["m"]}, True]
                self.ops.append(op)
                alive_link.setdefault(frozenset((ka, kb)), []).append(op)
            elif kind == "UNLINK":
                ka, kb = key(int(e["a"])), key(int(e["b"]))
                stack = alive_link.get(frozenset((ka, kb)))
                if stack:
                    stack.pop()[2] = False
                elif ka[0] == "pre" and kb[0] == "pre":
                    self.ops.append(["unlink", {"a": ka, "b": kb}, True])
            elif kind == "DEV":
                i = int(e["i"])
                if i in alive_dev:          # also reported as a ground device
                    continue
                ka, kb = key(int(e["a"])), key(int(e["b"]))
                learn(ka, pos(e.get("pa")))
                learn(kb, pos(e.get("pb")))
                lt = float(e["lt"]) if e.get("lt", "-") != "-" else 0.5
                op = ["dev", {"a": ka, "b": kb, "t": lt, "d": e["d"]}, True]
                self.ops.append(op)
                alive_dev[i] = op
                if int(e.get("u", "-1")) > 0:
                    upgraded.add(int(e["u"]))
            elif kind == "GDEV":
                i = int(e["i"])
                op = ["gdev", {"p": pos(e["p"]), "d": e["d"]}, True]
                if i in alive_dev:          # DEV came first: the ground position wins, at the same place
                    self.ops[next(k for k, o in enumerate(self.ops) if o is alive_dev[i])] = op
                else:
                    self.ops.append(op)
                alive_dev[i] = op
            elif kind in ("DEL", "LOST"):
                i = int(e["i"]) if "i" in e else None
                if i is None or i in upgraded:
                    continue
                op = alive_dev.pop(i, None)
                if op is not None:
                    op[2] = False
                elif kind == "DEL" and "a" in e:
                    ka, kb = key(int(e["a"])), key(int(e["b"]))
                    if ka[0] == "pre" and kb[0] == "pre":
                        learn(ka, pos(e.get("pa")))
                        learn(kb, pos(e.get("pb")))
                        self.ops.append(["undev", {"a": ka, "b": kb, "d": e["d"]}, True])
        # a node nobody links to any more is left out with its links
        linked = set()
        for kind, p, alive in self.ops:
            if kind == "link" and alive:
                linked.update((p["a"], p["b"]))
        for op in self.ops:
            if op[0] == "node" and op[1]["key"] not in linked:
                op[2] = False


class Converter:
    def __init__(self, rec, base_pos, mirror_pivot=None):
        self.rec = rec
        self.pivot = mirror_pivot
        self.ids = {}             # node key -> plan id
        self.pos = {}             # plan id -> position (plan frame)
        self.next_id = 10000
        self.warnings = []
        self.actions = []
        self.base = base_pos

    def p(self, q):
        if q is None or self.pivot is None:
            return q
        return (2 * self.pivot - q[0], q[1])

    def pre_id(self, k):
        if k in self.ids:
            return self.ids[k]
        q = self.p(self.rec.node_pos.get(k))
        best, bestd = None, MATCH_TOL
        if q is not None:
            for nid, b in self.base.items():
                d = math.dist(q, b)
                if nid < 10000 and d <= bestd:
                    best, bestd = nid, d
        if best is None:
            self.warnings.append("starting-fort node %d at %s has no node in the base plan; kept as is"
                                 % (k[1], fmt(q) if q else "?"))
            best = k[1]
        self.ids[k] = best
        self.pos[best] = self.base.get(best, q)
        return best

    def built(self, k):
        return k[0] == "pre" or k in self.ids

    def nid(self, k):
        return self.pre_id(k) if k[0] == "pre" else self.ids[k]

    def try_emit(self, kind, p):
        """Plan line for one op, or None if its nodes do not exist yet."""
        if kind == "link":
            a, b = p["a"], p["b"]
            if self.built(a) and self.built(b):
                ia, ib = self.nid(a), self.nid(b)
                return ('{ Type = CREATE_LINK, OriginalNodeAId = %d, PosA = {x = %s }, OriginalNodeBId = %d, PosB = { x = %s }, '
                        'MaterialSaveName = "%s" },' % (ia, xy(self.pos[ia]), ib, xy(self.pos[ib]), p["m"]))
            if self.built(a) != self.built(b):
                src, new = (a, b) if self.built(a) else (b, a)
                q = self.p(self.rec.node_pos.get(new))
                if q is None:
                    return None
                isrc = self.nid(src)
                inew = self.next_id
                self.next_id += 1
                self.ids[new] = inew
                self.pos[inew] = q
                return ('{ Type = CREATE_NODE, OriginalNodeAId = %d, PosA = { x = %s }, OriginalNodeBId = %d, NewNodePos = { x = %s }, '
                        'MaterialSaveName = "%s" },' % (isrc, xy(self.pos[isrc]), inew, xy(q), p["m"]))
            return None
        if kind in ("dev", "undev"):
            a, b = p["a"], p["b"]
            if not (self.built(a) and self.built(b)):
                return None
            ia, ib = self.nid(a), self.nid(b)
            if kind == "undev":
                return ('{ Type = DESTROY_DEVICE, OriginalNodeAId = %d, PosA = { x = %s }, OriginalNodeBId = %d, PosB = { x = %s }, '
                        'DeviceSaveName = "%s" },' % (ia, xy(self.pos[ia]), ib, xy(self.pos[ib]), p["d"]))
            t = p["t"]
            if self.pivot is not None:      # the game mirrors team-1 plans the same way (ai.lua MirrorFort)
                ia, ib, t = ib, ia, 1 - t
            return ('{ Type = CREATE_DEVICE, OriginalNodeAId = %d, PosA = { x = %s }, OriginalNodeBId = %d, PosB = { x = %s }, '
                    'LinkT = %.2f, DeviceSaveName = "%s" },' % (ia, xy(self.pos[ia]), ib, xy(self.pos[ib]), t, p["d"]))
        if kind == "gdev":
            return ('{ Type = CREATE_DEVICE, GroundPosition = { x = %s }, LinkT = %.2f, DeviceSaveName = "%s" },'
                    % (xy(self.p(p["p"])), GROUND_LINKT, p["d"]))
        if kind == "unlink":
            ia, ib = self.nid(p["a"]), self.nid(p["b"])
            return ('{ Type = DESTROY_LINK, OriginalNodeAId = %d, PosA = { x = %s }, OriginalNodeBId = %d, PosB = { x = %s }, },'
                    % (ia, xy(self.pos[ia]), ib, xy(self.pos[ib])))
        return None

    def run(self):
        pending = []
        for kind, p, alive in self.rec.ops:
            if not alive or kind == "node":
                continue
            pending.append((kind, p))
            progress = True
            while progress:          # an op that waited for a node may be possible now
                progress = False
                for item in list(pending):
                    line = self.try_emit(*item)
                    if line:
                        self.actions.append(line)
                        pending.remove(item)
                        progress = True
                        break
        for kind, p in pending:
            self.warnings.append("left out %s %s: its nodes are never built" % (kind, p.get("d") or p.get("m")))
        return self.actions


def fmt(p):
    return "(%.0f,%.0f)" % p


def xy(p):
    return "%.2f, y = %.2f" % p


def validate(actions, base_pos, terrain):
    """Build order, strut length, new-node distance and rock, like gen_fort.Plan.validate."""
    errors = []
    built = {nid for nid in base_pos if nid < 10000}
    for k, a in enumerate(actions):
        if a["Type"] == "CREATE_NODE":
            if a["OriginalNodeAId"] not in built:
                errors.append("action %d: node %d is created from unbuilt node %d" % (k, a["OriginalNodeBId"], a["OriginalNodeAId"]))
            if math.dist(a["PosA"], a["NewNodePos"]) > gen_fort.MAX_NEW_NODE + 1:
                errors.append("action %d: new node too far from its source (%.0f)" % (k, math.dist(a["PosA"], a["NewNodePos"])))
            built.add(a["OriginalNodeBId"])
            ends = (a["PosA"], a["NewNodePos"])
        elif a["Type"] in ("CREATE_LINK", "CREATE_DEVICE") and "OriginalNodeAId" in a:
            for x in (a["OriginalNodeAId"], a["OriginalNodeBId"]):
                if x not in built:
                    errors.append("action %d: node %d not built yet" % (k, x))
            ends = (a["PosA"], a["PosB"]) if a["Type"] == "CREATE_LINK" else None
        else:
            ends = None
        if ends:
            if math.dist(*ends) > gen_fort.MAX_LINK + 1:
                errors.append("action %d: link too long (%.0f)" % (k, math.dist(*ends)))
            if terrain and not terrain.segment_clear(*ends):
                errors.append("action %d: link passes through rock" % k)
    return errors


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", required=True, help="plan file to write")
    ap.add_argument("--map", default="Vanilla", help="map key in gen_fort.MAPS (base plan, header)")
    ap.add_argument("--log", help="Forts log (default: newest users/*/log.txt)")
    ap.add_argument("--match", type=int, default=-1, help="match index in the log (default: last)")
    ap.add_argument("--side", type=int, choices=(1, 2), help="side the player built on")
    ap.add_argument("--team", type=int, help="only this team (2v2: e.g. 101)")
    ap.add_argument("--until", type=int, help="ignore events after this frame (e.g. before combat)")
    ap.add_argument("--pivot", type=float, default=0.0, help="mirror axis for side 2 (default 0)")
    ap.add_argument("--data", default=DATA, help="Forts data folder")
    ap.add_argument("--title", default="recorded build")
    args = ap.parse_args()

    log = args.log or default_log()
    if not log:
        raise SystemExit("no Forts log found; use --log")
    import train
    lines = train.read_log(log)
    games = matches(lines)
    if not games:
        raise SystemExit("no match with recorder data in %s" % log)
    game = games[args.match]
    events = read_events(game, args.until)
    side = args.side or pick_side(events, game)

    cfg = gen_fort.MAPS[args.map]
    plan_dir = os.path.join(args.data, cfg["plan_dir"]) if cfg.get("plan_dir") else os.path.join(args.data, "maps", args.map)
    _, base = parse_plan(os.path.join(plan_dir, cfg["base_plan"]))
    base_pos = node_positions(base)
    terrain = None
    fwe = os.path.join(args.data, "maps", args.map, cfg["fwe"])
    if os.path.exists(fwe):
        _, blocks = read_blocks(fwe)
        terrain = Terrain([pts for flag, pts in blocks if flag >= 0 or (cfg.get("solid_minus1") and flag == -1)])

    rec = Recording(events, side, args.team)
    conv = Converter(rec, base_pos, args.pivot if side == 2 else None)
    actions = conv.run()
    if not actions:
        raise SystemExit("side %d built nothing in this match" % side)

    head = ("-- Fort recorded for AI replay\n"
            "CREATE_NODE = 1\nDESTROY_NODE = 2\nCREATE_LINK = 3\nDESTROY_LINK = 4\nCREATE_DEVICE = 5\nDESTROY_DEVICE = 6\n")
    tail = "-- Recorded from a player's build (tools/fortgen/rec_fort.py): %s\n" % args.title
    with open(args.out, "w", encoding="ascii", newline="\r\n") as f:
        f.write(head + cfg["header"] + "\n\nFort =\n{\n" + "\n".join(actions) + "\n}\n" + tail)

    parsed = parse_lines(actions)
    devs = {}
    for a in parsed:
        if a["Type"] == "CREATE_DEVICE":
            devs[a["DeviceSaveName"]] = devs.get(a["DeviceSaveName"], 0) + 1
    removed = sum(1 for kind, _, alive in rec.ops if not alive and kind != "node")
    print("%s: side %d%s, %d actions (%d built and removed again, left out), devices: %s"
          % (os.path.basename(args.out), side, " (mirrored)" if side == 2 else "", len(actions), removed,
             ", ".join("%s:%d" % kv for kv in sorted(devs.items())) or "none"))
    chains = rules.node_chains(parsed, terrain)
    if chains:
        print("   node chains: max %d, avg %.1f (node creations since an anchor)" % (max(chains.values()), sum(chains.values()) / len(chains)))
    for w in conv.warnings:
        print("   WARN:", w)
    for e in validate(parsed, base_pos, terrain):
        print("   ERROR:", e)
    rule_errors, rule_warnings = rules.check_plan(parsed, terrain=terrain)
    for e in rule_errors:
        print("   RULE ERROR:", e)
    for w in rule_warnings:
        print("   RULE WARN:", w)


if __name__ == "__main__":
    main()
