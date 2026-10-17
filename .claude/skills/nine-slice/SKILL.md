---
name: nine-slice
description: Cut a panel out of a UI sheet and make it a stretchable nine-slice (nine-patch) box for Godot — measuring its border, writing the StyleBoxTexture .tres, generating shade variants, and proving the result by rendering a frame. Use this whenever the work involves panel or window art: slicing a plate, making a box stretchable, a panel that looks squashed or seamed at some sizes, adding a new window or dialog background, reskinning existing panels onto new art, or anything mentioning 9-slice, nine-patch, patch margins, texture_margin, StyleBoxTexture or NinePatchRect. Reach for it even when the request is as short as "slice this" or "make this panel stretch" — the measuring and the render check are the parts that are easy to skip and expensive to get wrong.
---

# Nine-slicing a panel

A nine-slice box keeps its corners, repeats its edges, and stretches its middle,
so one small plate dresses a window of any size. Everything below exists because
the two numbers that make it work — where the panel is, and how thick its border
is — look obvious and are not. Guessing either puts a seam or a smeared corner
through every window in the game, at only some sizes, which is exactly the kind
of bug that survives a passing test suite.

So: **measure, then render and measure again.** Never derive a border thickness
by eye, and never call a panel done because the code looks right.

`scripts/slice.py` does the measuring. Run it with `python -I` (the project's
Python has Pillow). Every subcommand prints what it found, so its output is the
record of what the art actually is.

## The workflow

### 1. Find the panel on the sheet

Pack sheets hold several panels side by side, separated by transparent columns.

```bash
python -I .claude/skills/nine-slice/scripts/slice.py panels Assets/UI/Sheet.png
```

It prints each panel's exact box. Confirm with the user which one they meant if
the sheet has more than one and they described it loosely ("the right one").

### 2. Cut it out exactly

```bash
python -I .claude/skills/nine-slice/scripts/slice.py cut Assets/UI/Sheet.png 1 Assets/UI/Panel_Thing.png
```

The index comes from `panels`; `x,y,w,h` works too. Crop to the panel's true
bounds — a row of transparent padding left on an edge becomes a transparent
stripe down the middle of every stretched window.

### 3. Measure the border

```bash
python -I .claude/skills/nine-slice/scripts/slice.py measure Assets/UI/Panel_Thing.png
```

This reports the border thickness on each side, how far the rounded corner cuts
in, a suggested margin, and — the part that matters — whether the pixels the
slice will tile from hold one flat colour.

That last check is the whole game. Godot repeats the middle of each edge and
stretches the centre, so if any of them carries detail it smears or bands when
the panel resizes. "Clean" means the slice is safe at every size.

The suggested margin is the *floor*, not the house style. **This project slices
every panel at 6**, which clears the pack's corner curve and matches the plates
already in `Scripts/ProfilePanel.gd`. Prefer 6 when `measure --margin 6` says it
is clean; go higher only when the art needs it, and lower only deliberately.

### 4. Write the StyleBoxTexture

```bash
python -I .claude/skills/nine-slice/scripts/slice.py tres Assets/UI/Panel_Thing.png --margin 6 --pad 8
```

`--pad` is the content margin: the breathing room between the plate's edge and
whatever sits inside it. The `.tres` is written without a `uid`, on purpose —
Godot fills that in, and a hand-written one goes stale (see Traps).

A `.tres` is right for a panel used at one padding. Panels reused at several
paddings are better built in code: `ProfilePanel._sliced(texture, 6, pad_x,
pad_y)` is that pattern, and reusing it keeps one definition of "6".

### 5. Import, so Godot can see it

```bash
"D:/Applications/Godot 4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe" --headless --path . --import --quit-after 200
```

This generates the `.png.import` and registers any new `class_name`. A script
with a new `class_name` is invisible to every other script until this runs —
the symptom is `Could not find type "X" in the current scope` from a file that
is plainly correct.

### 6. Render it and measure the result

Headless proves logic, not placement. Draw the panel at sizes it was never
authored at and read the pixels back.

```bash
# NOTE: no --headless. Headless uses the dummy renderer and hands back a null
# frame, so get_texture().get_image() returns nothing to save.
"D:/Applications/Godot 4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe" --path . --script Tools/test_panel.gd
python -I .claude/skills/nine-slice/scripts/slice.py verify Tools/panel_stretch.png --ratio 1.6
```

`Tools/test_panel.gd` is the template: it draws the box wider and narrower than
its art and saves the frame. `verify` reads the panel's true rect, ratio and
centring out of that frame.

What to look for, in the render and in `verify`:

- **Corners unchanged** — a stretched corner means the margin is too small.
- **Edges repeat without banding** — banding means detail inside the slice.
- **No hairline between stacked panels** — see the fractional-middle trap.
- **The rect is the size and ratio intended**, not merely close to it.

## Shade variants

The pack's plates are one ramp of six shades:

`90625d → aa7959 → c49a6c → dcb98a → e8cfa6 → f3e5c2`

So a darker or lighter plate is a step along that ladder, not a `modulate`.
Tinting multiplies colours off the ramp and makes pixel art look washed; the
ladder lands exactly on the pack's own palettes.

```bash
python -I .claude/skills/nine-slice/scripts/slice.py shade Panel_Plate.png --down Panel_Plate_Dark.png
python -I .claude/skills/nine-slice/scripts/slice.py shade Panel_Plate.png --up   Panel_Plate_Tip.png
```

One step down reproduces `Panel_Dark`'s palette exactly; one step up reproduces
`Tooltip_Box`'s. Colours off the ladder are left alone and reported.

Before collapsing several plates onto one shape, check what the shades are
*doing*. In `ProfilePanel` the dark plate is not decoration — it is how an
unselected tab differs from the selected one. Reskinning that to a single shade
silently removes the selection feedback.

## Traps

These each cost real time here. They are not hypothetical.

**Headless renders nothing.** `--headless` loads the dummy renderer;
`root.get_texture().get_image()` returns null and `save_png` fails on it. Run
any frame capture windowed. Logic-only suites are fine headless.

**A stale uid in a `.tres`.** Renaming a `.png` makes Godot mint a new uid in
the `.png.import`. A `.tres` carrying the old one still loads by path, but the
pairing is broken. After any rename, compare the uid in the `.tres` against the
one in the `.png.import` and fix it.

**Headless `ResourceSaver.save()` strips every uid** from whatever it writes,
because the uid cache is not loaded outside the editor. Check `git diff` after
any headless save that touches a `.tres` or `.tscn` and restore them.

**Open-bottomed art is not a closed plate.** The pack's bar strips are drawn
flat to their last row so they can stack flush against a screen edge, which is
why `HUD.gd` sliced them with a bottom margin of 0. Reskinning such a bar to a
plate with a real border means the border now needs somewhere to be: give the
container a margin off the screen edge, and a gap between stacked plates, or the
border is cropped and reads as a bar cut in half.

**A gap between plates is part of the stack's height.** Adding separation to a
container without adding it to whatever computes that container's height hangs
the difference off the end. `HUD._reposition` had exactly this bug.

**Fractional middles seam.** When a slice's middle has to stretch by a
fractional factor the boundary can land mid-pixel and show as a hairline.
Whole-number zooms avoid it; so does a 0 margin on an edge that is flat colour
anyway.

**Whole-number zoom only.** Scale pixel art by integers. If a panel must hold a
fixed aspect ratio, author it once in source pixels at that ratio and multiply —
`StoragePanel` is 192x120 (16:10) times an integer, which is why its ratio
measures 1.60000 at every screen size rather than drifting.

## What good looks like

A finished slice has: the cropped `.png` at true bounds, its `.png.import`, a
`.tres` or a `_sliced(...)` call with a measured margin, and a rendered frame
whose measured rect matches what was intended. Report the measured numbers —
rect, ratio, "edges and centre tile clean" — not just that it is done.
