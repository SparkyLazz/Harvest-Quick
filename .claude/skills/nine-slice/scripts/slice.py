#!/usr/bin/env python3
"""Nine-slice panel tooling for the Sprout Lands UI pack.

Every step here exists because it was got wrong by hand first. The border
thickness of a plate is not guessable from looking at it, a crop that is one
pixel off puts a seam through every stretched panel, and the only way to know a
slice tiles cleanly is to look at the pixels it will tile from.

Subcommands:
    panels  <sheet.png>                     list the separate panels on a sheet
    cut     <sheet.png> <n|x,y,w,h> <out>   crop one panel out, exactly
    measure <panel.png>                     border thickness + safe slice margin
    tres    <panel.png> [--margin N] [--pad N] [--pad-y N] [--out F]
    shade   <panel.png> --down|--up <out>   recolour along the pack's shade ladder
    verify  <render.png> [--ratio R] [--size WxH]   measure a rendered panel

Run with no arguments for this text.
"""

import argparse
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow is needed: python -m pip install pillow")


# The pack's plates are all drawn from one ramp of six shades. Recolouring a
# plate means stepping each of its colours along this ladder, which is why the
# variants come out matching the pack's own boxes exactly rather than looking
# like a tinted copy.
LADDER = [
    (144, 98, 93),    # 90625d  darkest outline / bottom shadow
    (170, 121, 89),   # aa7959  outline
    (196, 154, 108),  # c49a6c  dark fill
    (220, 185, 138),  # dcb98a  fill
    (232, 207, 166),  # e8cfa6  bevel
    (243, 229, 194),  # f3e5c2  highlight
]


def _load(path):
    return Image.open(path).convert("RGBA")


def _runs(flags):
    """Start/end index pairs of each True run, for finding panels on a sheet."""
    out, start = [], None
    for i, on in enumerate(flags):
        if on and start is None:
            start = i
        elif not on and start is not None:
            out.append((start, i - 1))
            start = None
    if start is not None:
        out.append((start, len(flags) - 1))
    return out


def _boxes(im):
    """Each panel on a sheet, as (x, y, w, h). Panels are separated by fully
    transparent columns, which is how these sheets are laid out."""
    w, h = im.size
    px = im.load()
    cols = [any(px[x, y][3] > 0 for y in range(h)) for x in range(w)]
    rows = [any(px[x, y][3] > 0 for x in range(w)) for y in range(h)]
    out = []
    for x0, x1 in _runs(cols):
        # Rows are measured inside this column band, not across the whole
        # sheet, so a tall panel beside a short one is not padded out to match.
        band = [any(px[x, y][3] > 0 for x in range(x0, x1 + 1)) for y in range(h)]
        spans = _runs(band)
        if not spans:
            continue
        y0, y1 = spans[0][0], spans[-1][1]
        out.append((x0, y0, x1 - x0 + 1, y1 - y0 + 1))
    return out


def cmd_panels(args):
    im = _load(args.sheet)
    boxes = _boxes(im)
    print(f"{args.sheet}  {im.size[0]}x{im.size[1]}  -> {len(boxes)} panel(s)")
    for i, (x, y, w, h) in enumerate(boxes):
        print(f"  [{i}] x={x} y={y} w={w} h={h}")
    return 0


def cmd_cut(args):
    im = _load(args.sheet)
    if "," in args.which:
        x, y, w, h = (int(v) for v in args.which.split(","))
    else:
        boxes = _boxes(im)
        idx = int(args.which)
        if idx >= len(boxes):
            sys.exit(f"sheet has {len(boxes)} panel(s); no index {idx}")
        x, y, w, h = boxes[idx]
    im.crop((x, y, x + w, y + h)).save(args.out)
    print(f"wrote {args.out}  {w}x{h}  from ({x},{y})")
    return 0


def _ring_thickness(px, w, h):
    """How many pixels of border there are, read down the middle of each side.

    Taken from the middle rather than a corner because a corner is rounded --
    the curve is handled separately by the staircase measurement.
    """
    mid_y, mid_x = h // 2, w // 2
    fill = px[mid_x, mid_y][:3]
    left = next(i for i in range(w) if px[i, mid_y][:3] == fill)
    top = next(i for i in range(h) if px[mid_x, i][:3] == fill)
    right = next(i for i in range(w) if px[w - 1 - i, mid_y][:3] == fill)
    bottom = next(i for i in range(h) if px[mid_x, h - 1 - i][:3] == fill)
    return fill, left, top, right, bottom


def _staircase(px, h):
    """How far in the rounded corner cuts, by counting the transparent steps
    down the top-left corner. A slice margin has to clear this or the corner
    gets stretched."""
    steps = 0
    for y in range(h):
        row = 0
        while px[row, y][3] == 0:
            row += 1
        if row == 0:
            break
        steps = max(steps, row)
    return steps


def _uniform(px, w, h, margin, fill):
    """Does every pixel the nine-slice will tile from hold one flat colour?

    This is the check that actually matters. The middle of each edge and the
    centre are what Godot repeats or stretches, so if any of them carries
    detail it will smear or band when the panel is resized.
    """
    bad = []
    for y in (margin, h // 2, h - 1 - margin):
        for x in range(margin, w - margin):
            if px[x, y][:3] != fill:
                bad.append((x, y, px[x, y][:3]))
    for x in (margin, w // 2, w - 1 - margin):
        for y in range(margin, h - margin):
            if px[x, y][:3] != fill:
                bad.append((x, y, px[x, y][:3]))
    return bad


def cmd_measure(args):
    im = _load(args.panel)
    w, h = im.size
    px = im.load()
    fill, left, top, right, bottom = _ring_thickness(px, w, h)
    stairs = _staircase(px, h)
    # The margin has to clear both the border and the rounded corner, plus a
    # pixel so the slice line does not land on the last step of the curve.
    want = max(left, top, right, bottom, stairs) + 1

    print(f"{args.panel}  {w}x{h}")
    print(f"  fill          #{'%02x%02x%02x' % fill}")
    print(f"  border        left={left} top={top} right={right} bottom={bottom}")
    print(f"  corner curve  {stairs}px")
    print(f"  suggested     margin {want}")

    for margin in sorted({want, args.margin} if args.margin else {want}):
        bad = _uniform(px, w, h, margin, fill)
        verdict = "clean" if not bad else f"{len(bad)} px of detail"
        print(f"  margin {margin}: edges and centre tile {verdict}")
        for entry in bad[:4]:
            print(f"      x={entry[0]} y={entry[1]} #{'%02x%02x%02x' % entry[2]}")
    return 0


TRES = """[gd_resource type="StyleBoxTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="{res}" id="1_panel"]

[resource]
texture = ExtResource("1_panel")
texture_margin_left = {m}.0
texture_margin_top = {m}.0
texture_margin_right = {m}.0
texture_margin_bottom = {m}.0
content_margin_left = {px}.0
content_margin_top = {py}.0
content_margin_right = {px}.0
content_margin_bottom = {py}.0
"""


def cmd_tres(args):
    path = args.panel.replace("\\", "/")
    res = "res://" + path.split("Assets/", 1)[-1] if "Assets/" in path else "res://" + path
    if "Assets/" in path:
        res = "res://Assets/" + path.split("Assets/", 1)[1]
    out = args.out or args.panel.rsplit(".", 1)[0] + ".tres"
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(TRES.format(res=res, m=args.margin, px=args.pad,
                             py=args.pad_y if args.pad_y is not None else args.pad))
    print(f"wrote {out}  margin {args.margin}  texture {res}")
    print("  the uid is left off on purpose: let Godot fill it in on import,")
    print("  and check it against the .png.import file after any rename.")
    return 0


def cmd_shade(args):
    im = _load(args.panel)
    px = im.load()
    w, h = im.size
    step = -1 if args.down else 1
    index = {c: i for i, c in enumerate(LADDER)}
    moved, unknown = 0, Counter()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if (r, g, b) not in index:
                unknown[(r, g, b)] += 1
                continue
            # Clamped, not wrapped: the ends of the ladder stay put rather than
            # flipping to the opposite shade and inverting the plate.
            i = min(max(index[(r, g, b)] + step, 0), len(LADDER) - 1)
            px[x, y] = LADDER[i] + (a,)
            moved += 1
    im.save(args.out)
    print(f"wrote {args.out}  {moved} px shifted {'down' if args.down else 'up'} the ladder")
    for colour, count in unknown.most_common(3):
        print(f"  left alone (not on the ladder): #{'%02x%02x%02x' % colour} x{count}")
    return 0


def cmd_verify(args):
    """Measure a panel in a rendered frame.

    Placement and proportion are the things that survive a passing logic test
    and still look wrong, so they get read off the screen instead of worked out
    on paper.
    """
    im = Image.open(args.render).convert("RGB")
    w, h = im.size
    px = im.load()
    pal = set(LADDER)
    xs = [x for x in range(w) if any(px[x, y] in pal for y in range(h))]
    ys = [y for y in range(h) if any(px[x, y] in pal for x in range(w))]
    if not xs or not ys:
        sys.exit("no panel palette found in that frame -- was it rendered windowed?")
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    pw, ph = x1 - x0 + 1, y1 - y0 + 1
    print(f"{args.render}  frame {w}x{h}")
    print(f"  panel rect   x={x0} y={y0} w={pw} h={ph}")
    print(f"  ratio        {pw / ph:.5f}")
    print(f"  centre off   {((x0 + x1 + 1) / 2 - w / 2, (y0 + y1 + 1) / 2 - h / 2)}")
    ok = True
    if args.ratio:
        good = abs(pw / ph - args.ratio) < 0.005
        ok &= good
        print(f"  want ratio {args.ratio}: {'OK' if good else 'WRONG'}")
    if args.size:
        want = tuple(int(v) for v in args.size.lower().split("x"))
        good = (pw, ph) == want
        ok &= good
        print(f"  want size {want[0]}x{want[1]}: {'OK' if good else 'WRONG'}")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")

    p = sub.add_parser("panels"); p.add_argument("sheet"); p.set_defaults(fn=cmd_panels)

    p = sub.add_parser("cut")
    p.add_argument("sheet"); p.add_argument("which"); p.add_argument("out")
    p.set_defaults(fn=cmd_cut)

    p = sub.add_parser("measure")
    p.add_argument("panel"); p.add_argument("--margin", type=int)
    p.set_defaults(fn=cmd_measure)

    p = sub.add_parser("tres")
    p.add_argument("panel"); p.add_argument("--margin", type=int, default=6)
    p.add_argument("--pad", type=int, default=8); p.add_argument("--pad-y", type=int)
    p.add_argument("--out"); p.set_defaults(fn=cmd_tres)

    p = sub.add_parser("shade")
    p.add_argument("panel"); p.add_argument("out")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--down", action="store_true"); g.add_argument("--up", action="store_true")
    p.set_defaults(fn=cmd_shade)

    p = sub.add_parser("verify")
    p.add_argument("render"); p.add_argument("--ratio", type=float); p.add_argument("--size")
    p.set_defaults(fn=cmd_verify)

    args = ap.parse_args()
    if not args.cmd:
        ap.print_help()
        return 0
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
