"""Gelaende + Plan in Weltkoordinaten zeichnen."""
from PIL import Image, ImageDraw
from fortplan import node_positions, COLORS, DEVCOL, WEAPONS, ECO, TECH

def draw(polys, actions, out, view=(-2800, -1000, -1300, 1000), px_per_unit=0.35, title=None, extra=None, background=()):
    x0, x1, y0, y1 = view
    W, H = int((x1-x0)*px_per_unit), int((y1-y0)*px_per_unit)
    img = Image.new("RGB", (W, H), (235, 215, 160))
    d = ImageDraw.Draw(img)
    P = lambda p: ((p[0]-x0)*px_per_unit, (p[1]-y0)*px_per_unit)
    for poly in background:
        d.polygon([P(p) for p in poly], fill=(205, 185, 135))
    for poly in polys:
        d.polygon([P(p) for p in poly], fill=(90, 65, 45), outline=(40, 30, 20))
    pos = node_positions(actions)
    for a in actions:
        if a["Type"] in ("CREATE_NODE", "CREATE_LINK"):
            A, B = pos.get(a.get("OriginalNodeAId")), pos.get(a.get("OriginalNodeBId"))
            if A and B:
                m = a.get("MaterialSaveName")
                col = {"bracing": (150, 95, 40), "backbracing": (190, 160, 120), "armour": (90, 90, 110),
                       "door": (40, 110, 230), "shield": (0, 200, 160)}.get(m, (255, 0, 255))
                d.line([P(A), P(B)], fill=col, width=4 if m in ("armour", "door") else 2)
    for nid, p in pos.items():
        q = P(p)
        r = 3 if nid < 10000 else 1.5
        d.ellipse([q[0]-r, q[1]-r, q[0]+r, q[1]+r], fill=(0, 200, 255) if nid < 10000 else (60, 40, 20))
    for a in actions:
        if a["Type"] != "CREATE_DEVICE": continue
        n = a.get("DeviceSaveName", "?")
        if "GroundPosition" in a: p = a["GroundPosition"]
        else:
            A, B = pos.get(a.get("OriginalNodeAId")), pos.get(a.get("OriginalNodeBId"))
            if not (A and B): continue
            t = a.get("LinkT", 0.5); p = (A[0]+(B[0]-A[0])*t, A[1]+(B[1]-A[1])*t)
        cat = "weapon" if n in WEAPONS else "eco" if n in ECO else "tech" if n in TECH else "other"
        q = P(p)
        d.rectangle([q[0]-6, q[1]-10, q[0]+6, q[1]], fill={"weapon": (220, 30, 30), "eco": (240, 200, 0), "tech": (30, 170, 30), "other": (250, 250, 250)}[cat], outline=(0, 0, 0))
        d.text((q[0]+7, q[1]-11), n[:6], fill=(0, 0, 0))
    if extra: extra(d, P)
    if title: d.text((6, 6), title, fill=(0, 0, 0))
    img.save(out)
