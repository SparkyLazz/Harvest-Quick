"""Gives the house tiles their collision and interaction data.

Collision is taken from each tile's own opaque bounds rather than the whole
cell, because several wall pieces are only a few pixels of art inside a 16px
cell -- a full-cell box there blocks empty floor.

  python Tools/setup_interior_tiles.py
"""
import re
from PIL import Image

TRES = "Tilemaps/Terrains.tres"

# source 20 is the wall sheet: every cell is structure except the brick one,
# which the house uses as its floor.
WALLS_WALKABLE = {(1, 1)}

# source 22 is the furniture sheet. Anything you walk over or that hangs on a
# wall stays clear; the rest blocks.
FURN_CLEAR = {(0, 0), (1, 0), (2, 0),            # framed pictures
              (4, 0),                             # upper leaves of a tall plant
              (6, 3), (7, 3)}                     # wall clocks
FURN_CLEAR |= {(x, 5) for x in range(9)}          # rugs

BED = {(x, y) for x in (0, 1, 2) for y in (1, 2, 3, 4)}
WARDROBE = {(3, 2)}


def opaque_box(img, tx, ty):
    """The tile's art, as a polygon in Godot's cell-centre coordinates."""
    a = img.getchannel("A").load()
    pts = [(i, j) for i in range(16) for j in range(16) if a[tx * 16 + i, ty * 16 + j] > 0]
    if not pts:
        return None
    x0 = min(p[0] for p in pts) - 8
    x1 = max(p[0] for p in pts) + 1 - 8
    y0 = min(p[1] for p in pts) - 8
    y1 = max(p[1] for p in pts) + 1 - 8
    return f"PackedVector2Array({x0}, {y0}, {x1}, {y0}, {x1}, {y1}, {x0}, {y1})"


def cells_of(body):
    seen = []
    for line in body.split("\n"):
        m = re.match(r'^(\d+):(\d+)/0 = 0$', line.strip())
        if m:
            seen.append((int(m.group(1)), int(m.group(2))))
    return seen


def rebuild(body, img, solid_of, interact_of):
    out = []
    for c in cells_of(body):
        out.append(f"{c[0]}:{c[1]}/0 = 0")
        if solid_of(c):
            poly = opaque_box(img, *c)
            if poly:
                out.append(f"{c[0]}:{c[1]}/0/physics_layer_0/polygon_0/points = {poly}")
        tag = interact_of(c)
        if tag:
            out.append(f'{c[0]}:{c[1]}/0/custom_data_0 = "{tag}"')
    return "\n".join(out)


def replace_source(text, sub_id, new_body):
    pat = (rf'(\[sub_resource type="TileSetAtlasSource" id="{sub_id}"\]\n'
           rf'texture = ExtResource\("[^"]+"\)\n)(.*?)(?=\n\[sub_resource|\n\[resource\])')
    m = re.search(pat, text, re.S)
    assert m, f"source {sub_id} not found"
    return text[:m.start(2)] + new_body + text[m.end(2):]


def main():
    t = open(TRES, encoding="utf-8").read()

    # One string per tile saying what walking into it does. Empty means nothing.
    if "custom_data_layer_0/name" not in t:
        t = t.replace("\n[resource]\n", "\n[resource]\n", 1)
        t = re.sub(r'(\[resource\]\n)', r'\1custom_data_layer_0/name = "interact"\ncustom_data_layer_0/type = 4\n', t, count=1)

    walls_img = Image.open("Assets/Buildings/Wooden_House_Walls_Tilset.png").convert("RGBA")
    furn_img = Image.open("Assets/Buildings/Basic_Furniture.png").convert("RGBA")

    m = re.search(r'id="TileSetAtlasSource_walls"\]\ntexture = ExtResource\("[^"]+"\)\n(.*?)(?=\n\[sub_resource)', t, re.S)
    t = replace_source(t, "TileSetAtlasSource_walls",
                       rebuild(m.group(1), walls_img,
                               lambda c: c not in WALLS_WALKABLE, lambda c: ""))

    m = re.search(r'id="TileSetAtlasSource_furn"\]\ntexture = ExtResource\("[^"]+"\)\n(.*?)(?=\n\[sub_resource|\n\[resource\])', t, re.S)
    t = replace_source(t, "TileSetAtlasSource_furn",
                       rebuild(m.group(1), furn_img,
                               lambda c: c not in FURN_CLEAR,
                               lambda c: "bed" if c in BED else ("wardrobe" if c in WARDROBE else "")))

    open(TRES, "w", encoding="utf-8", newline="\n").write(t)
    print("wall cells solid except", sorted(WALLS_WALKABLE))
    print("furniture cells left clear:", len(FURN_CLEAR))
    print("bed cells tagged:", len(BED), " wardrobe cells tagged:", len(WARDROBE))


main()
