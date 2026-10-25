"""Reading and drawing Forts AI build plans (fort-*.lua)."""
import re

NUM = r"-?\d+(?:\.\d+)?"
TYPES = {"CREATE_NODE": 1, "DESTROY_NODE": 2, "CREATE_LINK": 3, "DESTROY_LINK": 4, "CREATE_DEVICE": 5, "DESTROY_DEVICE": 6}

def parse_vec(s, key):
    m = re.search(key + r"\s*=\s*\{\s*x\s*=\s*(" + NUM + r")\s*,\s*y\s*=\s*(" + NUM + r")\s*\}", s)
    return (float(m.group(1)), float(m.group(2))) if m else None

MODULES_MARK = "\nFortModules ="


def parse_plan(path):
    """Header and the actions of the Fort table (reactive build modules after it are left out, see parse_modules)."""
    text = open(path, encoding="latin-1").read().split(MODULES_MARK)[0]
    header = {}
    m = re.search(r"FortTeam = (\d+); FortId = (\d+); FortPos = \{ x = (" + NUM + "), y = (" + NUM + ")", text)
    if m:
        header = {"team": int(m.group(1)), "fort": int(m.group(2)), "pos": (float(m.group(3)), float(m.group(4)))}
    return header, parse_lines(text.splitlines())


def parse_modules(path):
    """The plan's reactive build modules (FortModules, written by gen_fort.py): a list of dicts with name, types,
    count, time, after (None if not set), requires and actions (parsed like the plan's)."""
    parts = open(path, encoding="latin-1").read().split(MODULES_MARK)
    if len(parts) < 2:
        return []
    mods = []
    for line in parts[1].splitlines():
        m = re.match(r'\s*\{ Name = "(\w+)", Trigger = \{ (.*) \}, Requires = (\d+), Actions = \{', line)
        if m:
            tr = m.group(2)
            types = re.search(r"Types = \{ ([^}]*) \}", tr)
            count, time, after = (re.search(k + r' = "?(\w+)"?', tr) for k in ("Count", "Time", "After"))
            mods.append({"name": m.group(1), "types": re.findall(r'"(\w+)"', types.group(1)) if types else [],
                         "count": int(count.group(1)) if count else 1, "time": int(time.group(1)) if time else None,
                         "after": after.group(1) if after else None, "requires": int(m.group(3)), "lines": []})
        elif mods and line.strip().startswith("{ Type"):
            mods[-1]["lines"].append(line.strip())
    for m in mods:
        m["actions"] = parse_lines(m["lines"])
    return mods


def format_modules(mods):
    """FortModules table for the plan file, after the Fort table (mods: name, types, count, time, after, requires,
    lines; time and after may be None)."""
    if not mods:
        return ""
    out = ["FortModules =", "{"]
    for m in mods:
        tr = []
        if m.get("types"):
            tr.append("Types = { %s }, Count = %d" % (", ".join('"%s"' % t for t in m["types"]), m.get("count", 1)))
        if m.get("time") is not None:
            tr.append("Time = %d" % m["time"])
        if m.get("after"):
            tr.append('After = "%s"' % m["after"])
        out.append('{ Name = "%s", Trigger = { %s }, Requires = %d, Actions = {' % (m["name"], ", ".join(tr), m["requires"]))
        out.extend(m["lines"])
        out.append("} },")
    out.append("}")
    return "\n".join(out) + "\n"


def module_requires(plan_actions, module_actions):
    """The last plan action (1-based) whose node or strut the module uses without building it itself: the module
    may only go in once the AI has passed it. Nodes of the starting fort need no plan action."""
    made = {a["OriginalNodeBId"] for a in module_actions if a["Type"] == "CREATE_NODE"}
    own = {frozenset((a["OriginalNodeAId"], a["OriginalNodeBId"])) for a in module_actions
           if a["Type"] in ("CREATE_NODE", "CREATE_LINK")}
    nodes, struts = set(), set()
    for a in module_actions:
        ids = [a[k] for k in ("OriginalNodeAId", "OriginalNodeBId") if k in a]
        nodes.update(x for x in ids if x not in made)
        if a["Type"] == "CREATE_DEVICE" and len(ids) == 2 and frozenset(ids) not in own:
            struts.add(frozenset(ids))
    first = {}
    for k, a in enumerate(plan_actions, 1):
        if a["Type"] == "CREATE_NODE":
            first.setdefault(("n", a["OriginalNodeBId"]), k)
        if a["Type"] in ("CREATE_NODE", "CREATE_LINK"):
            first.setdefault(("s", frozenset((a["OriginalNodeAId"], a["OriginalNodeBId"]))), k)
    req = [first.get(("n", x), 0) for x in nodes] + [first.get(("s", s), 0) for s in struts]
    return max(req or [0])


def parse_lines(lines):
    """Parse plan action lines ('{ Type = ... },') into dicts."""
    actions = []
    for line in lines:
        line = line.strip()
        if not line.startswith("{ Type"):
            continue
        a = {"Type": re.search(r"Type = (\w+)", line).group(1)}
        for k in ("OriginalNodeAId", "OriginalNodeBId"):
            mm = re.search(k + r" = (\d+)", line)
            if mm: a[k] = int(mm.group(1))
        for k in ("PosA", "PosB", "NewNodePos", "GroundPosition", "Pos"):
            v = parse_vec(line, k)
            if v: a[k] = v
        for k in ("MaterialSaveName", "DeviceSaveName"):
            mm = re.search(k + r' = "(\w+)"', line)
            if mm: a[k] = mm.group(1)
        mm = re.search(r"LinkT = (" + NUM + ")", line)
        if mm: a["LinkT"] = float(mm.group(1))
        mm = re.search(r"Facing = (\w+)", line)
        if mm: a["Facing"] = mm.group(1)
        a["raw"] = line
        actions.append(a)
    return actions

def node_positions(actions):
    pos = {}
    for a in actions:
        if "OriginalNodeAId" in a and "PosA" in a: pos.setdefault(a["OriginalNodeAId"], a["PosA"])
        if a["Type"] == "CREATE_NODE": pos[a["OriginalNodeBId"]] = a["NewNodePos"]
        elif "OriginalNodeBId" in a and "PosB" in a: pos.setdefault(a["OriginalNodeBId"], a["PosB"])
    return pos

COLORS = {"bracing": (200, 150, 90), "backbracing": (120, 90, 60), "armour": (170, 170, 190), "door": (90, 160, 255),
          "shield": (80, 255, 200), "rope": (230, 230, 230), "portal": (255, 0, 255)}
DEVCOL = {"weapon": (255, 60, 60), "eco": (255, 220, 0), "tech": (60, 255, 60), "other": (255, 255, 255)}
WEAPONS = {"machinegun", "minigun", "sniper", "sniper2", "mortar", "mortar2", "cannon", "laser", "missile", "missile2", "missileinv", "missile2inv"}
ECO = {"mine", "mine2", "turbine", "turbine2", "battery", "store", "derrick"}
TECH = {"workshop", "factory", "upgrade"}

def render(actions, out, background=None, bounds=(-4000, 4000, -2450, 2450), crop=None, scale=1.0, title=None):
    from PIL import Image, ImageDraw
    x0, x1, y0, y1 = bounds
    if background:
        img = Image.open(background).convert("RGB")
    else:
        img = Image.new("RGB", (1024, 576), (30, 30, 30))
    W, H = img.size
    def P(p):
        return ((p[0] - x0) / (x1 - x0) * W, (p[1] - y0) / (y1 - y0) * H)
    d = ImageDraw.Draw(img)
    pos = node_positions(actions)
    for a in actions:
        if a["Type"] in ("CREATE_NODE", "CREATE_LINK"):
            A = pos.get(a.get("OriginalNodeAId")); B = pos.get(a.get("OriginalNodeBId"))
            if A and B:
                w = 3 if a.get("MaterialSaveName") in ("armour", "door") else 1
                d.line([P(A), P(B)], fill=COLORS.get(a.get("MaterialSaveName"), (255, 0, 255)), width=w)
    for nid, p in pos.items():
        if nid < 10000:
            q = P(p); d.ellipse([q[0]-2, q[1]-2, q[0]+2, q[1]+2], outline=(0, 255, 255))
    for a in actions:
        if a["Type"] != "CREATE_DEVICE": continue
        n = a.get("DeviceSaveName", "?")
        cat = "weapon" if n in WEAPONS else "eco" if n in ECO else "tech" if n in TECH else "other"
        if "GroundPosition" in a: p = a["GroundPosition"]
        else:
            A = pos.get(a.get("OriginalNodeAId")); B = pos.get(a.get("OriginalNodeBId"))
            if not (A and B): continue
            t = a.get("LinkT", 0.5); p = (A[0] + (B[0]-A[0])*t, A[1] + (B[1]-A[1])*t)
        q = P(p); d.rectangle([q[0]-3, q[1]-3, q[0]+3, q[1]+3], fill=DEVCOL[cat])
    if crop:
        cx0, cy0 = P((crop[0], crop[2])); cx1, cy1 = P((crop[1], crop[3]))
        img = img.crop((int(cx0), int(cy0), int(cx1), int(cy1)))
        if scale != 1.0:
            img = img.resize((int(img.width*scale), int(img.height*scale)), Image.NEAREST)
    if title:
        ImageDraw.Draw(img).text((5, 5), title, fill=(255, 255, 255))
    img.save(out)
    return img
