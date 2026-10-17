"""Finds the texture_origin that seats the chest in the cell it is painted in."""
import re, subprocess
from PIL import Image, ImageChops

GODOT = r"D:\Applications\Godot 4.7.2\Godot_v4.7.2-stable_mono_win64_console.exe"
TRES = "Tilemaps/Terrains.tres"
ZOOM = 4          # the probe camera's zoom
CELL = 16

def set_origin(v):
    t = open(TRES, encoding="utf-8").read()
    t = re.sub(r'(\d+:\d+/0/texture_origin = Vector2i\(0, )-?\d+(\))',
               lambda m: m.group(1) + str(v) + m.group(2), t)
    open(TRES, "w", encoding="utf-8", newline="\n").write(t)

def chest_box(v):
    set_origin(v)
    run = subprocess.run([GODOT, "--path", r"D:\Code\HarvestQuick", "--resolution", "480x360",
                    "--script", "Tools/shoot5.gd"], capture_output=True, timeout=180, text=True)
    box = re.search(r"CELLBOX ([\d.-]+) ([\d.-]+) ([\d.-]+) ([\d.-]+)", run.stdout)
    a = Image.open("Tools/without.png").convert("RGB")
    b = Image.open("Tools/with.png").convert("RGB")
    diff = ImageChops.difference(a, b).convert("L").point(lambda p: 255 if p > 18 else 0)
    bbox = diff.getbbox()
    if bbox is None or box is None:
        return None
    top, bot = float(box.group(2)), float(box.group(4))
    return bbox, top, bot

for v in [16, 12, 8, 4, 0, -8]:
    out = chest_box(v)
    if out is None:
        print(f"origin {v:>4}: nothing drew"); continue
    (x0, y0, x1, y1), top, bot = out
    print(f"origin {v:>4}: chest y {y0}..{y1}   painted cell y {top:.0f}..{bot:.0f}   "
          f"base off by {(y1 - bot):+.0f} screen px  "
          f"({'SEATED' if abs(y1 - bot) <= 2 else 'off'})")
