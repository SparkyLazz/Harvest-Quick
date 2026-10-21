"""Makes the inventory version of an outlined item sheet.

The pack draws its dropped-item icons with a one-pixel cream halo so they read
against the ground. In a slot that halo just looks like a smudge, so this writes
a copy with the halo cleared: every halo-coloured pixel reachable from the
transparent background, so cream highlights inside an icon are left alone.

    python Tools/strip_halo.py Assets/Items/Wood_Items.png Assets/Items/Wood_Items_Plain.png
"""
import sys

from PIL import Image

HALO = (243, 244, 231)


def strip(src: str, dst: str) -> int:
    im = Image.open(src).convert("RGBA")
    px = im.load()
    w, h = im.size
    stack = [(x, y) for y in range(h) for x in range(w) if px[x, y][3] == 0]
    seen = set(stack)
    cleared = 0
    while stack:
        x, y = stack.pop()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if not (0 <= nx < w and 0 <= ny < h) or (nx, ny) in seen:
                continue
            r, g, b, a = px[nx, ny]
            if a and (r, g, b) == HALO:
                px[nx, ny] = (0, 0, 0, 0)
                cleared += 1
                seen.add((nx, ny))
                stack.append((nx, ny))
    im.save(dst)
    return cleared


if __name__ == "__main__":
    print("cleared %d halo pixels" % strip(sys.argv[1], sys.argv[2]))
