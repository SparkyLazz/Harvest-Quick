"""Adds the farm's shipping bin and seed-shop sign: copies their art in from the
asset packs, gives them tiles in the TileSet, and paints them onto the farm.

A text edit of Terrains.tres on purpose: a headless ResourceSaver save strips
every uid:// from the file (TECH_NOTES, traps). It only ever adds or replaces
its own pieces. (Tools/setup_interior_tiles.py, by contrast, rewrites the whole
custom-data layer list and would drop "breakable" and "drop": do not re-run
that one as it stands.)

    python -I Tools/setup_farm_props.py ["<Downloads folder>"]

then re-import, so the copied PNGs get their .import files. Safe to run twice:
it replaces what it added before rather than adding a second copy.

Both props are ordinary painted tiles, like the house's furniture: each carries
its verb in the "interact" custom data ("ship", "shop"), so the player, the
cursor and the lid animator all treat them as they treat a chest.
"""
import base64
import os
import re
import shutil
import struct
import sys

from PIL import Image

DOWNLOADS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.expanduser("~"), "Downloads")
# Each piece of art: where it is in the packs, and where it goes in the project.
ART = {
    "bin": ("Sprout Sorry pack/Sprout Sorry pack/Early Access/Plant update 2/Furniture/Oak_Chest.png",
            "Assets/Buildings/Shipping_Bin.png"),
    "signs": ("Sprout Lands - Sprites - premium pack/Sprout Lands - Sprites - premium pack/Objects/signs.png",
              "Assets/Objects/Signs.png"),
    "coins": ("Sprout Lands - UI Pack - Premium pack/Sprout Lands - UI Pack - Premium pack/"
              "UI Sprites/Icons/special icons/coins.png", "Assets/UI/Coins.png"),
}
TRES = "Tilemaps/Terrains.tres"
FARM = "Scenes/Dev.tscn"
FARM_TILESET_ID = "1_lbjce"

BIN_SOURCE, SIGN_SOURCE = 28, 29
BIN_TEXTURE_ID, SIGN_TEXTURE_ID = "31_bin", "32_signs"
# The bin's five lid frames are 32px cells side by side, the box 16px wide in
# the middle of each. So a frame is a 2x2 tile, frames two columns apart, and
# it is drawn on its cell exactly as the house chest is: lifted 8 by its
# texture origin (measured for the chest), sorted on the floor under it, and
# owning its whole cell.
BIN_FRAMES = 5
BIN_STEP = 2
# The signs sheet is 6 x 4 single-tile signs; the one with the carrot on it is
# the seed shop. The rest are there to paint as decoration.
SIGN_GRID = (6, 4)
SHOP_SIGN = (2, 0)
# Where they stand on the farm: the bin beside the house's front, as in
# Stardew, and the sign two cells along, both in sight from where you wake.
BIN_AT = (12, 6)
SIGN_AT = (14, 6)


def copy_art() -> None:
    for name, (src, dst) in ART.items():
        shutil.copyfile(os.path.join(DOWNLOADS, src), dst)
        print(f"art: {name} -> {dst}")


def opaque_box(img: Image.Image, tx: int, ty: int) -> str:
    """A tile's art as a collision box, in Godot's cell-centre coordinates."""
    box = img.crop((tx * 16, ty * 16, tx * 16 + 16, ty * 16 + 16)).getbbox()
    x0, y0, x1, y1 = (box[0] - 8, box[1] - 8, box[2] - 8, box[3] - 8)
    return f"PackedVector2Array({x0}, {y0}, {x1}, {y0}, {x1}, {y1}, {x0}, {y1})"


def bin_source() -> str:
    lines = ['[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_bin"]',
             f'texture = ExtResource("{BIN_TEXTURE_ID}")']
    for i in range(BIN_FRAMES):
        at = f"{i * BIN_STEP}:0"
        lines += [f"{at}/size_in_atlas = Vector2i(2, 2)",
                  f"{at}/0 = 0",
                  f"{at}/0/texture_origin = Vector2i(0, 8)",
                  f"{at}/0/y_sort_origin = 8",
                  f"{at}/0/physics_layer_0/polygon_0/points = PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)",
                  # Every frame carries the verb and its own index, as the
                  # chest's do: an open bin shows its last frame, and the
                  # first must be findable from any of them.
                  f'{at}/0/custom_data_0 = "ship"',
                  f"{at}/0/custom_data_1 = {BIN_FRAMES}",
                  f"{at}/0/custom_data_2 = {BIN_STEP}",
                  f"{at}/0/custom_data_3 = {i}"]
    return "\n".join(lines) + "\n"


def sign_source(img: Image.Image) -> str:
    lines = ['[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_signs"]',
             f'texture = ExtResource("{SIGN_TEXTURE_ID}")']
    for ty in range(SIGN_GRID[1]):
        for tx in range(SIGN_GRID[0]):
            at = f"{tx}:{ty}"
            lines += [f"{at}/0 = 0",
                      f"{at}/0/physics_layer_0/polygon_0/points = {opaque_box(img, tx, ty)}"]
            if (tx, ty) == SHOP_SIGN:
                lines.append(f'{at}/0/custom_data_0 = "shop"')
    return "\n".join(lines) + "\n"


def put_sub_resource(text: str, sub_id: str, block: str) -> str:
    """Replaces the sub-resource `sub_id`, or adds it before [resource].
    Either way the blank line Godot puts between sections is kept."""
    pat = (rf'\[sub_resource type="TileSetAtlasSource" id="{sub_id}"\]\n'
           rf'.*?\n\n*(?=\[sub_resource|\[resource\])')
    if re.search(pat, text, re.S):
        # The match runs through any blank lines after the block, so it comes
        # back with exactly one, however many there were.
        return re.sub(pat, lambda _m: block + "\n", text, count=1, flags=re.S)
    spot = text.index("\n[resource]\n")
    return text[:spot] + "\n" + block + text[spot:]


def setup_tileset() -> None:
    t = open(TRES, encoding="utf-8").read()
    anchor = re.search(r'\[ext_resource [^\n]*id="30_pine"\]', t).group(0)
    for path, ext_id in (("res://Assets/Buildings/Shipping_Bin.png", BIN_TEXTURE_ID),
                         ("res://Assets/Objects/Signs.png", SIGN_TEXTURE_ID)):
        if f'id="{ext_id}"' not in t:
            line = f'[ext_resource type="Texture2D" path="{path}" id="{ext_id}"]'
            t = t.replace(anchor, anchor + "\n" + line, 1)
            anchor = line
    t = put_sub_resource(t, "TileSetAtlasSource_bin", bin_source())
    t = put_sub_resource(t, "TileSetAtlasSource_signs", sign_source(Image.open(ART["signs"][1]).convert("RGBA")))
    last = 'sources/27 = SubResource("TileSetScenesCollectionSource_trees")'
    assert last in t, "trees source line not found"
    for line in (f'sources/{BIN_SOURCE} = SubResource("TileSetAtlasSource_bin")',
                 f'sources/{SIGN_SOURCE} = SubResource("TileSetAtlasSource_signs")'):
        if line not in t:
            t = t.replace(last, last + "\n" + line, 1)
            last = line
    open(TRES, "w", encoding="utf-8", newline="\n").write(t)
    print(f"tileset: source {BIN_SOURCE} bin ({BIN_FRAMES} frames), source {SIGN_SOURCE} signs "
          f"({SIGN_GRID[0] * SIGN_GRID[1]}, shop at {SHOP_SIGN})")


def paint_farm() -> None:
    cells = [(*BIN_AT, BIN_SOURCE, 0, 0, 0), (*SIGN_AT, SIGN_SOURCE, *SHOP_SIGN, 0)]
    data = struct.pack("<H", 0) + b"".join(struct.pack("<hhHHHH", *c) for c in cells)
    encoded = base64.b64encode(data).decode("ascii")
    t = open(FARM, encoding="utf-8").read()
    node = re.search(r'\[node name="Props" type="TileMapLayer"[^\n]*\]\n(?:[^\[\n][^\n]*\n)*', t)
    block = ('[node name="Props" type="TileMapLayer" parent="."]\n'
             "y_sort_enabled = true\n"
             f'tile_map_data = PackedByteArray("{encoded}")\n'
             f'tile_set = ExtResource("{FARM_TILESET_ID}")\n')
    if node:
        t = t[:node.start()] + block + t[node.end():]
    else:
        # Among the map layers, after the trees: the player collects every map
        # layer above the grass as ground cover, so nothing is hoed under it.
        spot = t.index('[node name="Farm"')
        t = t[:spot] + block + "\n" + t[spot:]
    open(FARM, "w", encoding="utf-8", newline="\n").write(t)
    print(f"farm: bin at {BIN_AT}, shop sign at {SIGN_AT}")


if __name__ == "__main__":
    copy_art()
    setup_tileset()
    paint_farm()
