"""Lays the frames from shoot_plate_options.gd out on one numbered sheet.

Each cell is the whole clock, scaled up, with its number and name under it. The
ink on the plate is measured as it goes, and an option whose text spills past
the plate's face, or sits more than a pixel off centre, is flagged on the sheet
and in the printout, so nothing is picked that only looks right by luck.

    python Tools/plate_options.py "Small, one line, split" "Small, one line, centred" ...
"""
import glob
import sys

from PIL import Image, ImageDraw, ImageFont

FACE = (24, 58, 47, 18)          # in the clock's own pixels
CLOCK_W, CLOCK_H, SCALE, MARGIN = 98, 99, 2, 10
TEXT = [(0x5A, 0x3D, 0x3D), (0x90, 0x62, 0x5D)]
ZOOM = 2
COLUMNS = 4
CAPTION = 44


def measure(im: Image.Image) -> tuple[int, int, int, int] | None:
    """Gaps (left, right, top, bottom) from the face's edges to the ink.

    Only the face itself is searched: the plate's outline is the same brown as
    the soft text, so looking past the face would count the outline as ink.
    Text that runs off the face therefore shows up as a gap of 0."""
    px = im.load()
    ox = MARGIN               # the clock hangs in the top-left corner
    xs, ys = [], []
    fx, fy, fw, fh = FACE
    for ly in range(fy, fy + fh):
        for lx in range(fx, fx + fw):
            if px[ox + lx * SCALE, MARGIN + ly * SCALE][:3] in TEXT:
                xs.append(lx)
                ys.append(ly)
    if not xs:
        return None
    return (min(xs) - fx, fx + fw - 1 - max(xs), min(ys) - fy, fy + fh - 1 - max(ys))


def build(names: list[str], dst: str) -> None:
    frames = sorted(glob.glob("Tools/_plate_option_*.png"))
    cell_w = (CLOCK_W * SCALE + 20) * ZOOM
    cell_h = (CLOCK_H * SCALE + 20) * ZOOM
    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGB", (cell_w * COLUMNS, (cell_h + CAPTION) * rows), (40, 36, 44))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=24)
    for i, path in enumerate(frames):
        im = Image.open(path).convert("RGB")
        gaps = measure(im)
        # Left-set options are meant to be uneven side to side.
        centred = "left" not in names[i].lower()
        bad = gaps is None or min(gaps) < 1 or abs(gaps[2] - gaps[3]) > 1             or (centred and abs(gaps[0] - gaps[1]) > 1)
        crop = im.crop((0, 0, CLOCK_W * SCALE + 20, CLOCK_H * SCALE + 20))
        x, y = (i % COLUMNS) * cell_w, (i // COLUMNS) * (cell_h + CAPTION)
        sheet.paste(crop.resize((cell_w, cell_h), Image.NEAREST), (x, y))
        note = "" if not bad else "  (!) doesn't fit / off centre"
        draw.text((x + 12, y + cell_h + 8), f"{i + 1}. {names[i]}{note}",
                  fill=(255, 120, 120) if bad else (240, 230, 210), font=font)
        print(f"{i + 1:2}. {names[i]:32} gaps L/R/T/B {gaps}{'  BAD' if bad else ''}")
    sheet.save(dst)


if __name__ == "__main__":
    build(sys.argv[1:], "Tools/plate_options.png")
