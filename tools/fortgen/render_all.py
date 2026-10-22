"""Preview: render_all.py <map-fwe> <out.png> <view x0,x1,y0,y1> <px_per_unit> <plans...>"""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fwe import read_blocks; from fortplan import parse_plan; from view import draw
from PIL import Image
fwe, out, view, ppu = sys.argv[1], sys.argv[2], tuple(float(v) for v in sys.argv[3].split(",")), float(sys.argv[4])
files = sys.argv[5:]
_, bl = read_blocks(fwe)
solid = [p for f, p in bl if f >= 0]; bg = [p for f, p in bl if f < 0]
imgs = []
for f in files:
    h, acts = parse_plan(f)
    name = os.path.basename(f)
    png = os.path.join(os.path.dirname(os.path.abspath(out)), "_" + name + ".png")
    draw(solid, acts, png, title=name, background=bg, view=view, px_per_unit=ppu)
    imgs.append(Image.open(png))
W = sum(i.width for i in imgs) + 10 * (len(imgs) - 1); H = max(i.height for i in imgs)
sheet = Image.new("RGB", (W, H), (255, 255, 255)); x = 0
for i in imgs: sheet.paste(i, (x, 0)); x += i.width + 10
sheet.save(out)
