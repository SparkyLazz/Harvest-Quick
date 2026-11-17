# HarvestQuick — Technical Notes

How the game is put together, how to run and check it, and the traps already
found. The game design (story, numbers, plan) is in `Docs/GAME_DESIGN.md`.

Last updated: 2026-11-06.

---

## 1. Engine and running

- **Godot 4.7.2**, GDScript. Main scene: `Scenes/Dev.tscn` (the farm).
- Godot is **not on PATH**. Editor binary:
  `D:\Applications\Godot 4.7.2\Godot_v4.7.2-stable_mono_win64_console.exe`
  (use the `_console` one for command-line work). Below, `<godot>` means that.
- Run a test: `<godot> --headless --path . --script Tools/test_clock.gd`
- Re-import assets (also registers a new `class_name`): `<godot> --headless --path . --import --quit-after 200`
- Render frames (needs a window, not `--headless`): `<godot> --path . --script Tools/shoot_clock.gd`

## 2. Controls

| Key | Action |
|---|---|
| WASD / arrows | Move |
| Shift | Run |
| Space / left mouse | Use the held item, or interact (bed, chest, wardrobe, shipping bin, seed-shop sign) |
| Click / Shift-click in the seed shop | Buy one packet / five |
| 1–9, mouse wheel | Pick hotbar slot |
| E | Profile screen (inventory, crafting, settings) |
| Esc | Close the open window |

## 3. Scripts

| Script | What it is |
|---|---|
| `PlayerState.gd` | **Autoload, and the save game** (`save_game`/`load_game`/`new_game`, §4). What survives scene changes: inventory, stamina, **coins** (`earn`/`spend`, `coins_changed`), day, clock minutes, storage contents (the **shipping bin** too, under `SHIPPING_KEY`), each map's changes. Sleep, pass-out and the overnight sale (`_ship`) live here. |
| `SceneTransition.gd` | **Autoload.** Fade-to-black scene changes (`go_to`, `fade_through`). Pauses the tree during the fade; places the player on `SceneTree.scene_changed` (built in since 4.5), not after a guessed number of frames. |
| `MouseCursor.gd` | **Autoload.** Cursor icon by context: arrow, paw over usable furniture (never over an open window), closed paw while a panel carries a stack. |
| `Calendar.gd` | Day number → season, weekday, week, date text; clock constants (`DAY_START`, `PASS_OUT`, `SECONDS_PER_MINUTE`). |
| `ClockPlate.gd` | The top-left clock UI (see §6). |
| `StatusSign.gd` | The top-right sign: hearts on a nine-sliced plate, the purse on a smaller one hung under it on two posts (art: `Assets/UI/Status.png`, cut by `Tools/cut_status.py`). One node, everything in one `_draw`; hops the coin when the amount changes. `StatusSign.heart_for(i, health)` is the one full/half/empty rule — the profile book draws its hearts with it too. |
| `HUD.gd` | The hotbar; owns the profile and storage windows, the clock and the status sign (forwards `max_hearts`/`health` to it); **ticks the clock** each frame while no window is open. A hotbar slot's item and count are drawn by an `InventorySlot` laid over the plate, the same drawing as the panels' grids. |
| `Player.gd` | Movement, tools, stamina, planting (only in season), harvesting, interacting via the tileset's `interact` custom data (`bed`, `chest`, `wardrobe`, `ship`, `shop`). |
| `Farm.gd` | Tilled soil, crops, watering, overnight growth, harvest; out-of-season crops die at the season change (live and on catch-up). |
| `Crops.gd` (`CropDB`) | Crop table: sprite row, stages, **days to ripen**, **seasons**, **price** and **seed** cost (`Tools/econ_sim.py` keeps a copy). |
| `ChoppableTree.gd` | Trees: chopping, stumps, saplings that grow a stage per night. |
| `Items.gd` (`ItemDB`) | Item ids, names, icons, tooltips. Tools, seeds, produce, wood, tree seeds. `info()` is worked out once per id and handed out **read-only** and shared. |
| `Recipes.gd` (`RecipeDB`) | Crafting recipes (only produce → seeds so far). |
| `Inventory.gd`, `InventorySlot.gd`, `CarriedStack.gd` | Bag data, slot UI, the stack on the cursor (one per panel, same rules). |
| `ProfilePanel.gd`, `StoragePanel.gd` | The E screen (a two-page book: `_window` is a VBox of the bookmark tabs and the book, overlapped by a negative separation so the book covers the tabs' feet; the portrait is a `NinePatchRect` of `Assets/UI/Portrait_Frame.png`, patch margin 20, sized from `PORTRAIT_MARGIN`, with a clipping recess so the poked cat never draws over the posts; tabs are `Tab_On.png`/`Tab_Off.png`) and the chest/wardrobe window, which is also the shipping bin's window and, with `open_shop()`, the seed shop (priced stock, click buys). Closing never destroys the carried stack: bag, then chest, else the window stays up. |
| `UIFont.gd`, `UISkin.gd`, `PixelBar.gd` | The one pixel face and `draw_haloed()` (see §7), shared window look and shared `UISkin.atlas()` cut-outs, bars. |
| `Door.gd`, `PropAnimator.gd`, `GridCursor.gd`, `EmoteBubble.gd` | Doors, opening props, the tile cursor, reaction bubbles. |

## 4. State and persistence

- **The save game is `PlayerState` on disk.** Everything below is plain data,
  so `save_game()` writes it whole with `FileAccess.store_var` (Vector2i keys
  and typed arrays survive as they are) to `user://save.dat` — on Windows
  `%APPDATA%\Godot\app_userdata\Harvest Quick\save.dat`. Shape: `{version,
  day, minutes, coins, stamina, max_stamina, started, inventory: {items,
  counts}, stores: {key: {items, counts}}, worlds}`.
  - **When:** the end of `sleep()`, after `day_changed` (crops grown, bin sold)
    — bed and passing out alike. It first calls the group **`saves_world`**
    (`write_world()`), so map state held only in memory (the Farm's plots,
    between visits) is in the record before writing.
  - **Safely:** written to `save.dat.tmp`, then renamed over the save; a
    `.tmp` left by a crash between the two is read if the save is missing.
  - **Loading:** `PlayerState._ready` reads it and, deferred, covers the screen
    (`SceneTransition.cover()`) and `go_to`s the house's `Bed` marker, so the
    farm the game boots into is never seen. `get_var(false)`: a save can never
    make objects. A file whose length disagrees with its header, or of another
    `SAVE_VERSION`, is refused and the game starts new.
  - **New game:** `new_game()` deletes the save, `reset()`s, and goes to the
    main scene (Settings → GAME → NEW GAME, a two-press button).
  - **Tools and tests never touch it:** launched with `--script`, loading and
    autosave are off; `test_save.gd` sets `save_path` to a file of its own.
- Each map's changes live in `PlayerState.world_for(map)`, a dictionary that
  the owners read on load and write on unload:
  `hoed` and `broken` (Player), `trees` (ChoppableTree), `farm` (Farm:
  `{tilled, wet, crops, day}`).
- Stamina is checked out by the Player on load and handed back as it changes.
- **Coins** live in `PlayerState.coins` (start 200). The **shipping bin** is
  `storage_for(SHIPPING_KEY)`: one inventory whatever bin tile is used, whose
  `Inventory.accepts` filter only takes things with a sell price (adding and
  every click rule check `Inventory.takes`). `sleep()` sells its contents
  (`_ship`) after the day turns but **before** `day_changed`, so anything
  that wakes on it already sees the coins; `shipped(earned)` is emitted then.

## 5. Time, sleep and growth

- `PlayerState.minutes` = minutes since midnight of the current day; it runs
  past 24:00 (25:30 = 1:30 am) up to `Calendar.PASS_OUT` (26:00 = 2 am).
- The HUD calls `PlayerState.pass_time(delta)` every frame unless a window is
  open; the tree is paused during fades, which also stops it.
- Signals: `time_changed(minutes)` on every 10-minute step,
  `day_changed(day)` after sleeping, `passed_out` at 2 am.
- `PlayerState.sleep(rested)` → day + 1, clock to 6:00, stamina full (or half
  when `rested` is false), emits `day_changed`.
- Bed → `Player._sleep()` → `SceneTransition.fade_through(PlayerState.sleep)`.
- 2 am → `PlayerState._pass_out()` →
  `await SceneTransition.go_to(PlayerHouse, "Bed" marker, sleep(false))`. The
  `during` callback runs while the screen is black **before** the old scene is
  freed, so a farm on screen still hears `day_changed` and grows. It awaits
  `go_to` itself, not `arrived`, so a house that failed to load cannot leave
  the pass-out flag stuck.
- **Crops** store `grown` (watered nights). `CropDB.stage_after(crop, grown)`
  picks the sprite stage. A loaded farm grows on `day_changed`. A farm that
  was not loaded catches up on load from its record's `day`: one night grows
  what was wet, later nights find dry soil and change nothing.
- **Saplings** grow one stage per night (no real-time growth any more).

## 6. The clock UI (`ClockPlate.gd`)

- Art: `Assets/UI/Clock.png`, an atlas made by `Tools/cut_clock.py` from the
  UI pack's weather sheets; plus `Assets/UI/Weather/Weather_Icons_Big.png`
  (48px cells: rows 0–2 icons with backdrop, 3–5 without, 6–8 bare
  backdrops; green = day, orange = dusk, blue = night).
- `cut_clock.py` cuts the frame by its **pixel outline**, not its box (a box
  catches a corner of the dial); bakes all 5 arrows onto one pivot; seals
  the thermometer so no background shows through (holes only where liquid
  goes, an empty-tube piece behind the fill); and **bleeds** everything drawn
  behind the frame — dial, tube and bulb, the three skies, the liquid
  sideways — one pixel under the rim (`ClockPlate.BLEED`), so no seam can open
  at a fractional window scale (see §9). The skies are cut from
  `Weather_Icons_Big.png` into the atlas for that; only the pictures still come
  from the big icon sheet.
  Re-run (the zip extracted into a folder of the same name, hence the double):
  `python -I Tools/cut_clock.py "C:/Users/Rui/Downloads/Sprout Lands - UI Pack - Premium pack/Sprout Lands - UI Pack - Premium pack/emojis/emoji style ui/weather" Assets/UI/Clock.png`,
  then re-import.
- Layers, back to front: skies (unclipped, bled) → window (pictures, clipped
  at the sill) → dial → empty tube → fill → frame → arrow → text.
- Static rules (tested): `phase_at(minutes)`, `arrow_frame_at(minutes)`,
  `heat_at(day, minutes)`.
- Placed top-left, 10px from the edges, scaled by the HUD's `ui_scale` (2).
- Date plate text: season over date, `UIFont.small()` at `SMALL_SIZE` 8,
  centred, rows measured from a render (2 above, 3 between, 3 below).
- `Tools/shoot_plate_options.gd` + `Tools/plate_options.py` render a gallery
  of plate text designs (`Tools/plate_options.png`) for picking a new one.

## 7. Fonts

**One face for all text** (since 2026-11-06): pixelFont-2 5×5, the clock
plate's font, at `UIFont.SIZE` = 8 — HUD, every panel, tooltips, the clock and
the pop-ups in the world. `UIFont.title()`, `body()` and `small()` are kept
as roles and all return that face; a heading differs from a description by
colour (`TEXT_COLOR` over `MUTED_COLOR`), the way the plate sets the date
under the season. To give headings their own face again, change `title()`.

- It is only crisp at 8 (at 10 it doubles some strokes). Never ask for another
  size; scale the node by whole numbers instead.
- Crispness comes from the import settings (antialiasing None, subpixel
  positioning Disabled), not from code.
- **Text over things** (stack counts over icons, "+3" over grass) uses
  `UIFont.draw_haloed()`: dark ink, ringed one pixel wide in the colour of
  what it normally sits on, so the ring only shows where it crosses something.
  Slot counts take the slot's face colour (`InventorySlot.FACE_*`); pop-ups
  take the drop sprites' cream halo, `#f3f4e7`.
- **In the world** the camera zooms 4×, so world text is scaled by a multiple
  of 0.25 to keep each font pixel on whole screen pixels (pop-ups: 0.75).
- The retired 7×7 and 7×5 faces are still in `Assets/Fonts` for the font
  comparison tools.

## 8. Tools

| Tool | Purpose |
|---|---|
| `test_regressions.gd` | Bugs from the 2026-11-05 review, pinned: hotbar icon surviving an empty-and-refill in one frame, closing with a full bag, crafting while carrying, grab cursor, per-frame allocations, read-only item info, failed scene loads. |
| `test_clock.gd` | Calendar, clock ticking/pausing, clock face rules and swap, plate fit for every day, overnight growth, catch-up, passing out. |
| `test_clock_seams.gd` | **Windowed** (SKIP headless): draws the clock over magenta at 8 window scales × 3 skies and counts any background showing through its openings (fails on the pre-bleed clock); then the status sign's posts and plates at the same 8 scales (fails on a deliberate 1px gap). |
| `test_axe.gd` | Axe, trees, saplings (grown by sleeping), grass regrowth, persistence. |
| `test_props`, `test_autotile`, `test_interior`, `test_door`, `test_cursor`, `test_storage`, `test_storage_moves`, `test_craft_card`, `test_panel` | Older suites. |
| `shoot_clock.gd` | Renders the clock at each part of the day + a winter night + a swap animation strip (Mon 15 Summer, the widest date). |
| `shoot*.gd` | Other frame captures for checking art placement. |
| `cut_clock.py` | Builds `Assets/UI/Clock.png` (§6). |
| `plate_options.py`, `shoot_plate_options.gd` | Clock plate design gallery (§6). |
| `test_save.gd` | The save game: round trip of day, coins, bag, chests, the bin (still refusing tools) and the farm; a save taken with the farm on screen; autosave on sleep; waking in bed at start; damaged and other-version saves refused; new game carrying nothing over. Uses its own save file. |
| `test_economy.gd` | Step 2: prices and seasons (and that they hit the sim's per-season targets), the purse, the bin (refuses tools, sells overnight), the shop (buy, batch, broke, full bag, Winter), planting in season, crops dying at the season turn, live and on catch-up. |
| `econ_sim.py` | Debt economy simulator (`Docs/GAME_DESIGN.md` §4). Its farm income comes from a copy of `CropDB`'s prices (`CROPS`). |
| `cut_status.py` | Builds `Assets/UI/Status.png` for the status sign from the UI pack's all-in-one sheet (two plates, a post) and `Hearts.png` (the three big hearts). |
| `setup_farm_props.py` | Copies the bin, sign and coin art in from the packs, adds tileset sources 28 (bin, 5 lid frames, `ship`) and 29 (signs, carrot = `shop`) by **text edit**, and paints both on the farm's `Props` layer. Idempotent; re-import after. |
| `strip_halo.py` | Makes plain inventory icons from outlined drop icons. |
| `sweep.py` | Measures a tile's true draw position by diffing two renders. |

**All fifteen suites pass headless** (as of 2026-11-06) and exit non-zero on
a failure, so they can be run in a loop. The old "known failures" were stale
tests, not game bugs: the house was redrawn (two chests, no dresser, the exit
moved down the hall) and three suites still pointed at the old cells; the
screenshot suites crashed headless on `save_png`. Now:
- Tests find furniture **by its verb**, never by a hard-coded cell, and walk
  into the actual `Door` node. `test_interior`/`test_storage` paint the
  tileset's dresser in themselves, since the house has none at the moment.
- Screenshots are saved only when windowed (`DisplayServer.get_name() !=
  "headless"`), so the same suite runs both ways.
- `test_storage`'s real click on the window's X needs a pointer, which
  headless never has: it prints `SKIP` there and is checked windowed.

## 9. Traps already found

- **Verify visuals by rendering.** Tests prove logic, not placement. Render
  a frame and measure pixels; a tile's `texture_origin` was got wrong three
  times by reasoning about it.
- **Test scripts can't name `class_name` scripts that use autoloads.** A
  `--script` test compiles before autoloads exist, so writing
  `ClockPlate.phase_at(...)` in a test breaks `ClockPlate` for the whole run.
  Reach them through an instance (`plate.phase_at(...)`), and reach autoloads
  with `root.get_node("PlayerState")`.
- **Headless runs frames far faster than 60/s.** To wait for an animation,
  `await create_timer(seconds).timeout`, not a frame count.
- **Labels: add to the tree before setting text and size.** Set the other way
  round, a centred label landed half its width too far right.
- **Centred/right-set text counts the last letter's 1px spacing** as width, so
  it sits a pixel off; the clock nudges it back (`TEXT_NUDGE`).
- **An `AtlasTexture` with an empty region draws the whole sheet.** Always
  give layers a real region.
- **The plate outline is the same brown as the soft text colour** (#90625d):
  measure text ink inside the plate's face only.
- **A headless `ResourceSaver.save()` strips every `uid://`** from the saved
  file. Check `git diff` after any headless save of `.tres`/`.tscn`.
- **graphify doesn't read GDScript** — don't use `graphify query` for this
  code; read or grep the scripts. The PreToolUse hook in
  `.claude/settings.json` still prints "MANDATORY: run graphify query" on every
  search and read; that predates this finding, so ignore it here.
- **Don't free a UI node you might look up again in the same frame.**
  `queue_free()` only happens at the end of the frame; until then
  `get_node("Item")` still finds the dying node, hands it new content, and it
  vanishes anyway. A slot can empty and refill inside one frame (crafting does
  exactly that), which blanked hotbar slots. Hide and reuse instead.
- **A closing window must not drop the carried stack.** `spill_into()` returns
  what did not fit and leaves it on the cursor; the storage window tries the
  bag, then the chest, and otherwise refuses to close. The profile screen puts
  the stack back when you leave the inventory tab, because crafting can fill
  the very slot it was lifted from.
- **Shared, read-only data.** `ItemDB.info()` returns one cached dictionary per
  id, made read-only — `duplicate()` it before changing anything.
  `UISkin.atlas()` textures are shared between every node that shows that
  cut-out — never change one in place; ask for the region you want.
- **Headless can't click a Control.** Mouse events parsed in a headless run do
  not press buttons (no pointer moves over them). Key/action events work.
- **Tests: find things by what they are, not where they are.** Three suites
  broke when the house was redrawn because they named cells like `(11, 4)`.
- **A map owner must hold its record from `_ready`.** The Farm writes its
  plots on `_exit_tree`; it used to look its record up again there, which
  after a `reset()` or a load *created* a fresh record and wrote the old farm
  into the new game. It now keeps `_record` from `_ready`, like the Player
  (`_hoed`, `_broken`) and the trees (`_state`) always did; `reset()` drops the
  records from `_worlds` rather than emptying them, so an exiting scene's
  writes land nowhere.
- **Anything new that only writes its state on exit** must join the
  `saves_world` group with a `write_world()`, or a save taken while it is on
  screen misses its latest.
- **Do not re-run `setup_interior_tiles.py` as it stands.** It deletes every
  `custom_data_layer` line and writes back only the first four (interact,
  frames, step, frame), so it would drop `breakable` and `drop` — the axe's
  data. Add tiles the way `setup_farm_props.py` does: text edits that only
  add or replace their own pieces (no `ResourceSaver`, so no uid loss), run
  twice to prove they are idempotent, and keep Godot's blank line between
  `.tres` sections.
- **A 2×2 tile on the 16px grid is placed like the house chest's 1×2 one:**
  drawn centred on its cell, so `texture_origin = (0, 8)` stands a bottom-
  aligned 32px frame on the cell's floor. Measured for the bin (art spans
  x 192–208, y 98–112 on cell (12, 6)), not assumed.
- **Never use a font's `outline_size` on the 5×5 face.** Godot strokes the
  glyph's vector shape: at 1 it is half a pixel a side and breaks into dots,
  at 2 it chips the corners, at 3 it fills the one-pixel gaps between letters
  and a count turns into a dark block. Any outline also fills those gaps, so
  "+3" merges. Use `UIFont.draw_haloed()` (§7). Found by rendering 0–3.
- **Layers that meet edge to edge open seams at fractional window sizes.**
  The stretch mode is `canvas_items`, so any window that is not a whole
  multiple of 1152×648 scales the UI by a fraction, and each layer then rounds
  to screen pixels on its own. Where the piece behind a hole ended exactly at
  the hole's edge, a one-pixel line of background showed (the clock's
  thermometer, window and dial; 443 pixels across 8 scales). Whole-number
  renders never show it, which is why it got past every test. It happens
  between **separate nodes**, each rounding its own position. Two cures: give
  anything seen through a hole a pixel of spare art under the rim (bleed —
  the clock), or draw the touching pieces from **one node in one `_draw`**,
  where a shared edge goes through the same transform and lands on the same
  pixel (the status sign: its posts needed no bleed). Either way, check at a
  fractional `content_scale_factor` — `test_clock_seams.gd` does.
- **The hotbar slots are scaled by the selection pop** (0.88 shrunk, 1.25
  held), so what is drawn in them lands on 1.76 or 2.5 screen pixels per
  source pixel — strokes come out a little uneven there, unlike the panels'
  clean 2×. Check hotbar art and text at those scales, not only at 2×.
