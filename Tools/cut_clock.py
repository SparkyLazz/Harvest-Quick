"""Cuts the clock out of the UI pack's weather sheets into one atlas.

The pack's Weather_UI sheet packs its pieces close enough that a plain rectangle
around the big frame also catches a corner of the dial below it, so every piece
here is lifted by its own pixel mask (the connected blob of opaque pixels at its
seed point), not by its bounding box.

The five arrows are drawn at different sizes, each with its tail somewhere
else. They are baked into same-sized cells with every tail on the cell's PIVOT,
so the game swaps frames without moving anything.

The thermometer fills are bottom-aligned in their cells, as the pack draws them,
so each sits on the bulb wherever it is placed.

The frame's thermometer is drawn hollow, a little wider than the liquid that
goes in it, so on its own the ground shows round the liquid and above it. The
pack's own finished thermometers are solid, and this makes ours match them:
the frame keeps holes only where liquid can be -- four pixels up the tube, and
the round of the bulb -- and the rest of the hollow is painted the cream of the
tube's inner ring. An empty tube in the pack's tan goes behind the liquid, so
whatever the fill doesn't reach still reads as glass, not as a hole. The rungs
stay on the frame and so cross over the liquid, as they do in the pack.

Everything drawn behind the frame is BLED: cut with a pixel of spare art all
round, copied outward from its own edge, so it reaches under the frame's rim.
At a window size that scales the clock by a whole number this changes nothing
on screen -- the rim covers the spare pixel. At any other size the rim and the
piece behind it round to screen pixels separately, and where their edges met
exactly a one-pixel seam opened onto whatever was behind the clock: a dark line
down the left of the tube, specks round the picture window and the dial. The
spare pixel is what the rounding lands on instead. The frame's holes are worked
out before anything is bled, so the holes themselves do not grow.

    python Tools/cut_clock.py "<UI pack>/emojis/emoji style ui/weather" Assets/UI/Clock.png

Layout of the atlas (all sizes in pixels):
    frame    (0, 0)     98x99   frame, thermometer and date plate, as one piece
    dial     (100, 0)   24x36   day above, night below; bled
    tube     (124, 0)   10x30   the empty tube and the bulb, drawn behind a fill; bled
    arrows   (100, 40)  5 cells of 24x24 across, tail at PIVOT in each
    skies    (100, 66)  3 cells of 36x36 across: day, dusk, night; bled
    fills    (0, 104)   9 cells of 8x28 across, hottest first; liquid bled sideways
"""
import sys

from PIL import Image

ATLAS_SIZE = (220, 132)
# A pixel on the frame's left edge; the frame, thermometer and plate are one blob.
FRAME = (10, 37)
DIAL = (67, 103, 22, 34)
# (x, y, w, h, tail) in Weather_UI, steepest up first. The tail is the middle of
# the arrow's blunt end, in the sprite's own pixels.
ARROWS = [
    (338, 1, 13, 13, (3, 11)),
    (337, 18, 15, 12, (3, 9)),
    (336, 34, 16, 12, (2, 6)),
    (337, 50, 15, 12, (3, 3)),
    (338, 66, 13, 13, (3, 2)),
]
ARROW_CELL = 24
PIVOT = (4, 12)
# (x, y, w, h) in Thermometer_UI_Seperated, hottest first.
FILLS = [
    (12, 57, 8, 28), (44, 57, 8, 28), (76, 57, 8, 28), (108, 62, 8, 23), (140, 68, 8, 17),
    (12, 119, 8, 14), (44, 121, 8, 12), (76, 125, 8, 8), (108, 125, 8, 8),
]
FILL_CELL = (8, 28)
FILLS_AT = (0, 104)
# Where a fill cell sits on the frame, and so where its liquid lands.
FILL_AT = (7, 61)
# The liquid's columns in a fill cell, and the rows of the tube above the bulb.
LIQUID_X = range(2, 6)
LIQUID_ROWS = range(1, 21)
# The tube's inner ring, painted into the hollow; and the empty glass.
RING = (232, 207, 166, 255)
EMPTY = (220, 185, 138, 255)
# The thermometer's corner of the frame: the hollow is the see-through pixels
# in here that the outside can't reach.
THERMOMETER = (0, 56, 22, 43)

# The spare art round everything drawn behind the frame, in pixels.
BLEED = 1
DIAL_CELL = (100, 0)
TUBE_CELL = (124, 0)
# The bare skies on Weather_Icons_Big (48px cells, the 34px picture inset 7 in
# each): its columns for day (green), dusk (orange) and night (blue), in the
# order they are laid into the atlas.
SKY_ROW = 6
SKY_COLUMNS = [0, 4, 7]
ICON_CELL, ICON_INSET, WINDOW_SIZE = 48, 7, 34
SKIES_AT = (100, 66)


def blob(im: Image.Image, seed: tuple[int, int]) -> Image.Image:
    """The connected opaque piece at `seed`, alone, cropped to its bounds."""
    px = im.load()
    w, h = im.size
    stack, seen = [seed], {seed}
    while stack:
        x, y = stack.pop()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and px[nx, ny][3]:
                seen.add((nx, ny))
                stack.append((nx, ny))
    out = Image.new("RGBA", im.size)
    for p in seen:
        out.putpixel(p, px[p])
    return out.crop(out.getbbox())


def rect(im: Image.Image, r: tuple[int, int, int, int]) -> Image.Image:
    x, y, w, h = r
    return im.crop((x, y, x + w, y + h))


def cut(sheets: str, dst: str) -> None:
    ui = Image.open(f"{sheets}/Weather_UI.png").convert("RGBA")
    therm = Image.open(f"{sheets}/Thermometer_UI_Seperated.png").convert("RGBA")
    icons = Image.open(f"{sheets}/Weather_Icons_Big.png").convert("RGBA")
    atlas = Image.new("RGBA", ATLAS_SIZE)
    atlas.alpha_composite(blob(ui, FRAME), (0, 0))
    atlas.alpha_composite(rect(ui, DIAL), (DIAL_CELL[0] + BLEED, DIAL_CELL[1] + BLEED))
    for i, (x, y, w, h, tail) in enumerate(ARROWS):
        cell = (100 + i * ARROW_CELL, 40)
        atlas.alpha_composite(rect(ui, (x, y, w, h)),
                              (cell[0] + PIVOT[0] - tail[0], cell[1] + PIVOT[1] - tail[1]))
    for i, (x, y, w, h) in enumerate(FILLS):
        cx, cy = FILLS_AT[0] + i * FILL_CELL[0], FILLS_AT[1]
        atlas.alpha_composite(rect(therm, (x, y, w, h)), (cx, cy + FILL_CELL[1] - h))
    for i, column in enumerate(SKY_COLUMNS):
        sky = rect(icons, (column * ICON_CELL + ICON_INSET, SKY_ROW * ICON_CELL + ICON_INSET,
                           WINDOW_SIZE, WINDOW_SIZE))
        atlas.alpha_composite(sky, (SKIES_AT[0] + i * (WINDOW_SIZE + 2 * BLEED) + BLEED,
                                    SKIES_AT[1] + BLEED))
    # The holes first, from the art as drawn; only then is anything bled.
    seal(atlas, liquid_mask(atlas))
    paint_tube(atlas)
    bleed(atlas, (*DIAL_CELL, DIAL[2] + 2 * BLEED, DIAL[3] + 2 * BLEED))
    bleed(atlas, (*TUBE_CELL, FILL_CELL[0] + 2 * BLEED, FILL_CELL[1] + 2 * BLEED))
    for i in range(len(SKY_COLUMNS)):
        # Twice: the skies have rounded corners, and the first pass only
        # squares them off.
        size = WINDOW_SIZE + 2 * BLEED
        bleed(atlas, (SKIES_AT[0] + i * size, SKIES_AT[1], size, size), passes=2)
    for i in range(len(FILLS)):
        # Sideways only: up or down would move the liquid's visible level.
        bleed(atlas, (FILLS_AT[0] + i * FILL_CELL[0], FILLS_AT[1], *FILL_CELL), sideways=True)
    atlas.save(dst)


def liquid_mask(atlas: Image.Image) -> set[tuple[int, int]]:
    """Frame pixels liquid can show through: the tube's four columns, and the
    bulb as the fills draw it (every fill shares the one bulb)."""
    fx, fy = FILL_AT
    mask = {(fx + x, fy + y) for x in LIQUID_X for y in LIQUID_ROWS}
    px = atlas.load()
    for x in range(FILL_CELL[0]):
        for y in range(LIQUID_ROWS.stop, FILL_CELL[1]):
            if px[FILLS_AT[0] + x, FILLS_AT[1] + y][3]:
                mask.add((fx + x, fy + y))
    return mask


def seal(atlas: Image.Image, keep: set[tuple[int, int]]) -> None:
    """Paints the thermometer's hollow the ring's cream, except where liquid
    shows. The hollow is found as see-through pixels the outside can't reach."""
    px = atlas.load()
    x0, y0, w, h = THERMOMETER
    inside = lambda x, y: x0 <= x < x0 + w and y0 <= y < y0 + h
    clear = {(x, y) for x in range(x0, x0 + w) for y in range(y0, y0 + h) if not px[x, y][3]}
    outside = {p for p in clear if p[0] in (x0, x0 + w - 1) or p[1] in (y0, y0 + h - 1)}
    stack = list(outside)
    while stack:
        x, y = stack.pop()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if inside(*n) and n in clear and n not in outside:
                outside.add(n)
                stack.append(n)
    for p in clear - outside - keep:
        px[p] = RING


def paint_tube(atlas: Image.Image) -> None:
    """The piece behind every fill: empty glass up the tube, and the bulb as the
    fills draw it. The bulb is always full, so it is only ever seen here at the
    edges -- which is the point: rounding there now lands on bulb, not on
    whatever is behind the clock."""
    px = atlas.load()
    tx, ty = TUBE_CELL[0] + BLEED, TUBE_CELL[1] + BLEED
    for x in LIQUID_X:
        for y in LIQUID_ROWS:
            px[tx + x, ty + y] = EMPTY
    for x in range(FILL_CELL[0]):
        for y in range(LIQUID_ROWS.stop, FILL_CELL[1]):
            p = px[FILLS_AT[0] + x, FILLS_AT[1] + y]
            if p[3]:
                px[tx + x, ty + y] = p


def bleed(atlas: Image.Image, box: tuple[int, int, int, int], passes: int = 1,
          sideways: bool = False) -> None:
    """Grows the art inside `box` outward by one pixel per pass, each new pixel
    copying an opaque neighbour -- straight neighbours before diagonal ones --
    so the spare edge is the art's own edge colour, carried on."""
    x0, y0, w, h = box
    steps = [(-1, 0), (1, 0)]
    if not sideways:
        steps += [(0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
    px = atlas.load()
    for _ in range(passes):
        was = {(x, y): px[x, y] for x in range(x0, x0 + w) for y in range(y0, y0 + h)}
        for (x, y), p in was.items():
            if p[3]:
                continue
            for dx, dy in steps:
                n = was.get((x + dx, y + dy))
                if n is not None and n[3] == 255:
                    px[x, y] = n
                    break


if __name__ == "__main__":
    cut(sys.argv[1], sys.argv[2])
