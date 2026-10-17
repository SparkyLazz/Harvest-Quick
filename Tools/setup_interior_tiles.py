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

# The chest is its own sheet. Its five lid frames sit three columns apart, and
# an open lid reaches into the row above, so every frame is one cell wide and
# two tall, anchored on the upper cell. Two styles: front on, and side on.
CHEST_ROWS = {"front": 0, "side": 3}
CHEST_COLUMNS = [1, 4, 7, 10, 13]
CHEST_STEP = 3


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


def chest_source(ext_id):
    """Every chest frame as a paintable tile.

    Only the first frame is tagged. The others are where the script parks the
    cell mid-open, so tagging them too would let the cursor light up over a
    half-raised lid that nothing can act on.
    """
    lines = ['[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_chest"]',
             f'texture = ExtResource("{ext_id}")']
    for row in CHEST_ROWS.values():
        for i, col in enumerate(CHEST_COLUMNS):
            at = f"{col}:{row}"
            lines.append(f"{at}/size_in_atlas = Vector2i(1, 2)")
            lines.append(f"{at}/0 = 0")
            # The cell you paint is the chest's BODY, with the lid drawn in
            # the cell above. A tall tile is drawn from its cell downwards, so
            # without this the body lands below the cell that was painted.
            #
            # +8, measured rather than reasoned: a positive origin lifts the
            # art. Both -8 and -16 were tried on the assumption that it pushed
            # the other way, and each left the chest sitting a cell low, which
            # is what made every hitbox look like it was one cell too high.
            lines.append(f"{at}/0/texture_origin = Vector2i(0, 8)")
            # Sorts on the floor under it, so you can pass behind a raised lid.
            lines.append(f"{at}/0/y_sort_origin = 8")
            # The whole cell, not an inset box. At 14x12 the player could clip
            # a pixel into the chest from either side, which reads as walking
            # into it; furniture standing on the floor should own its square.
            lines.append(f"{at}/0/physics_layer_0/polygon_0/points = "
                         "PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)")
            # Every frame is tagged, not just the first. An open chest shows
            # its last frame, and an untagged one would be invisible to both
            # the cursor and the use key -- you could open it and never shut it.
            # Carrying its own index is also what lets the first frame be found
            # again from any of them, so nothing has to remember where it was.
            lines.append(f'{at}/0/custom_data_0 = "chest"')
            lines.append(f"{at}/0/custom_data_1 = {len(CHEST_COLUMNS)}")
            lines.append(f"{at}/0/custom_data_2 = {CHEST_STEP}")
            lines.append(f"{at}/0/custom_data_3 = {i}")
    return "\n".join(lines) + "\n"


def main():
    t = open(TRES, encoding="utf-8").read()

    # Per-tile data: what using it does and, for the ones that open, how many
    # frames there are, how far apart they sit on the sheet, and which one this
    # is. The last of those is what makes a frame self-describing: the first can
    # be found again from any of them, so nothing has to remember where it was.
    layers = ('custom_data_layer_0/name = "interact"\n'
              'custom_data_layer_0/type = 4\n'
              'custom_data_layer_1/name = "frames"\n'
              'custom_data_layer_1/type = 2\n'
              'custom_data_layer_2/name = "step"\n'
              'custom_data_layer_2/type = 2\n'
              'custom_data_layer_3/name = "frame"\n'
              'custom_data_layer_3/type = 2\n')
    t = re.sub(r'custom_data_layer_\d+/(name|type) = [^\n]*\n', "", t)
    at = t.index("[resource]\n") + len("[resource]\n")
    t = t[:at] + layers + t[at:]

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

    # The chest gets its own source, so painting one is just another tile.
    if "Chest.png" not in t:
        anchor = ('[ext_resource type="Texture2D" uid="uid://dyq0yqdn7gfrb"'
                  ' path="res://Assets/Buildings/Basic_Furniture.png" id="22_furn"]')
        assert anchor in t, "furniture texture line not found"
        t = t.replace(anchor, anchor + '\n[ext_resource type="Texture2D"'
                      ' path="res://Assets/Buildings/Chest.png" id="23_chest"]', 1)
    block = chest_source("23_chest")
    if 'id="TileSetAtlasSource_chest"' in t:
        t = re.sub(r'\[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_chest"\]\n'
                   r'texture = ExtResource\("[^"]+"\)\n.*?(?=\n\[sub_resource|\n\[resource\])',
                   block.rstrip("\n"), t, flags=re.S)
    else:
        spot = t.index("\n[resource]\n")
        t = t[:spot] + "\n" + block + t[spot:]
    if "sources/23" not in t:
        line = 'sources/22 = SubResource("TileSetAtlasSource_furn")'
        assert line in t, "furniture source line not found"
        t = t.replace(line, line + '\nsources/23 = SubResource("TileSetAtlasSource_chest")', 1)

    open(TRES, "w", encoding="utf-8", newline="\n").write(t)
    print("chest: %d frames x %d styles, first frame tagged"
          % (len(CHEST_COLUMNS), len(CHEST_ROWS)))
    print("wall cells solid except", sorted(WALLS_WALKABLE))
    print("furniture cells left clear:", len(FURN_CLEAR))
    print("bed cells tagged:", len(BED), " wardrobe cells tagged:", len(WARDROBE))


main()
