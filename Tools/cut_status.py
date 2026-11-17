"""Cuts the hanging hearts-and-purse sign out of the UI pack into one atlas.

The pack draws it ready-made, but only on its all-in-one sheet (UI Sprites/ALL
UI ASSETS on one sheet.png, the "hanging" pairs at x 821): a wide plate of
hearts with a smaller plate hung under it on two posts, a coin on the small
one. No separate file has it. It is cut here into parts so the game can build
the sign for any number of hearts and any amount of money:

  - the two plates, as nine-slice sources. Both have the same border: a 1px
    outline and a 2px light rim round the top and sides, then along the bottom
    the rim, a 2px shadow lip and the outline -- margins 3, 3, 3, 5 -- around a
    flat face. Taken from the sheet's empty pair, so no hearts or coin are
    baked into them;
  - one post (3x3);
  - the three big hearts, from Hearts.png -- full (151, 168), half (183, 168)
    and empty (215, 104). Checked pixel for pixel: they are exactly the hearts
    the sheet's own sign shows. The coin is UISkin.COIN, which already matches.

    python -I Tools/cut_status.py "<UI pack folder>" Assets/UI/Status.png

Layout of the atlas (pixels):
    top plate   (0, 0)    71x31   hearts plate, nine-slice 3/3/3/5
    low plate   (0, 32)   41x20   purse plate, nine-slice 3/3/3/5
    post        (44, 32)  3x3
    hearts      (0, 53)   full, half, empty: 19x17 cells at x 0, 20, 40
"""
import sys

from PIL import Image

SHEET = "UI Sprites/ALL UI ASSETS on one sheet.png"
HEARTS = "UI Sprites/Icons/special icons/Hearts.png"
# The sheet's empty hanging pair, and its parts within it.
PAIR = (821, 453)
TOP_PLATE = (0, 0, 71, 31)
LOW_PLATE = (0, 34, 41, 20)
POST = (6, 31, 3, 3)
HEART_CELLS = {"full": (151, 168), "half": (183, 168), "empty": (215, 104)}
HEART_SIZE = (19, 17)


def part(im: Image.Image, origin: tuple[int, int], r: tuple[int, int, int, int]) -> Image.Image:
    x, y, w, h = r
    return im.crop((origin[0] + x, origin[1] + y, origin[0] + x + w, origin[1] + y + h))


def cut(pack: str, dst: str) -> None:
    sheet = Image.open(f"{pack}/{SHEET}").convert("RGBA")
    hearts = Image.open(f"{pack}/{HEARTS}").convert("RGBA")
    atlas = Image.new("RGBA", (72, 70))
    atlas.alpha_composite(part(sheet, PAIR, TOP_PLATE), (0, 0))
    atlas.alpha_composite(part(sheet, PAIR, LOW_PLATE), (0, 32))
    atlas.alpha_composite(part(sheet, PAIR, POST), (44, 32))
    for i, (x, y) in enumerate(HEART_CELLS.values()):
        atlas.alpha_composite(hearts.crop((x, y, x + HEART_SIZE[0], y + HEART_SIZE[1])), (i * 20, 53))
    atlas.save(dst)


if __name__ == "__main__":
    cut(sys.argv[1], sys.argv[2])
