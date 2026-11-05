# HarvestQuick — Technical Notes

How the game is put together, how to run and check it, and the traps already
found. The game design (story, numbers, plan) is in `Docs/GAME_DESIGN.md`.

Last updated: 2026-11-05.

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
| Space / left mouse | Use the held item, or interact (bed, chest, wardrobe) |
| 1–9, mouse wheel | Pick hotbar slot |
| E | Profile screen (inventory, crafting, settings) |
| Esc | Close the open window |

## 3. Scripts

| Script | What it is |
|---|---|
| `PlayerState.gd` | **Autoload.** What survives scene changes: inventory, stamina, day, clock minutes, storage contents, each map's changes. Sleep and pass-out live here. |
| `SceneTransition.gd` | **Autoload.** Fade-to-black scene changes (`go_to`, `fade_through`). Pauses the tree during the fade. |
| `MouseCursor.gd` | **Autoload.** Cursor icon by context. |
| `Calendar.gd` | Day number → season, weekday, week, date text; clock constants (`DAY_START`, `PASS_OUT`, `SECONDS_PER_MINUTE`). |
| `ClockPlate.gd` | The top-left clock UI (see §6). |
| `HUD.gd` | Hearts + hotbar; owns the profile and storage windows and the clock; **ticks the clock** each frame while no window is open. |
| `Player.gd` | Movement, tools, stamina, planting, harvesting, interacting via the tileset's `interact` custom data (`bed`, `chest`, `wardrobe`). |
| `Farm.gd` | Tilled soil, crops, watering, overnight growth, harvest. |
| `Crops.gd` (`CropDB`) | Crop table: sprite row, stages, **days to ripen**. |
| `ChoppableTree.gd` | Trees: chopping, stumps, saplings that grow a stage per night. |
| `Items.gd` (`ItemDB`) | Item ids, names, icons, tooltips. Tools, seeds, produce, wood, tree seeds. |
| `Recipes.gd` (`RecipeDB`) | Crafting recipes (only produce → seeds so far). |
| `Inventory.gd`, `InventorySlot.gd`, `CarriedStack.gd` | Bag data, slot UI, the stack on the cursor. |
| `ProfilePanel.gd`, `StoragePanel.gd` | The E screen and the chest/wardrobe window. |
| `UIFont.gd`, `UISkin.gd`, `PixelBar.gd` | Pixel fonts, shared window look, bars. |
| `Door.gd`, `PropAnimator.gd`, `GridCursor.gd`, `EmoteBubble.gd` | Doors, opening props, the tile cursor, reaction bubbles. |

## 4. State and persistence

- **Nothing is saved to disk yet.** `PlayerState` keeps everything in memory
  for one run. A real save system is still to do.
- Each map's changes live in `PlayerState.world_for(map)`, a dictionary that
  the owners read on load and write on unload:
  `hoed` and `broken` (Player), `trees` (ChoppableTree), `farm` (Farm:
  `{tilled, wet, crops, day}`).
- Stamina is checked out by the Player on load and handed back as it changes.

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
  `SceneTransition.go_to(PlayerHouse, "Bed" marker, sleep(false))`. The
  `during` callback runs while the screen is black **before** the old scene is
  freed, so a farm on screen still hears `day_changed` and grows.
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
  catches a corner of the dial); bakes all 5 arrows onto one pivot; and seals
  the thermometer so no background shows through (holes only where liquid
  goes, an empty-tube piece behind the fill).
  Re-run: `python Tools/cut_clock.py "<UI pack>/emojis/emoji style ui/weather" Assets/UI/Clock.png`
- Layers, back to front: window (sky, picture) → dial → empty tube → fill →
  frame → arrow → text.
- Static rules (tested): `phase_at(minutes)`, `arrow_frame_at(minutes)`,
  `heat_at(day, minutes)`.
- Placed top-left, 10px from the edges, scaled by the HUD's `ui_scale` (2).
- Date plate text: season over date, `UIFont.small()` at `SMALL_SIZE` 8,
  centred, rows measured from a render (2 above, 3 between, 3 below).
- `Tools/shoot_plate_options.gd` + `Tools/plate_options.py` render a gallery
  of plate text designs (`Tools/plate_options.png`) for picking a new one.

## 7. Fonts

| Font | Use | Size |
|---|---|---|
| `UIFont.title()` — pixelFont-4 7×7 | Headings, stack counts | `UIFont.SIZE` = 10 |
| `UIFont.body()` — pixelFont-3 7×5 | Descriptions | 10 |
| `UIFont.small()` — pixelFont-2 5×5 | Tight spots (clock plate) | `UIFont.SMALL_SIZE` = 8 |

Each pixel font is only crisp at one size. The 5×5 face doubles some strokes
at 10; 8 was found by rendering several sizes.

## 8. Tools

| Tool | Purpose |
|---|---|
| `test_clock.gd` | Calendar, clock ticking/pausing, clock face rules and swap, plate fit for every day, overnight growth, catch-up, passing out. |
| `test_axe.gd` | Axe, trees, saplings (grown by sleeping), grass regrowth, persistence. |
| `test_props`, `test_autotile`, `test_interior`, `test_door`, `test_cursor`, `test_storage`, `test_storage_moves`, `test_craft_card`, `test_panel` | Older suites. |
| `shoot_clock.gd` | Renders the clock at each part of the day + a winter night + a swap animation strip (Mon 15 Summer, the widest date). |
| `shoot*.gd` | Other frame captures for checking art placement. |
| `cut_clock.py` | Builds `Assets/UI/Clock.png` (§6). |
| `plate_options.py`, `shoot_plate_options.gd` | Clock plate design gallery (§6). |
| `econ_sim.py` | Debt economy simulator (`Docs/GAME_DESIGN.md` §4). |
| `strip_halo.py` | Makes plain inventory icons from outlined drop icons. |
| `sweep.py` | Measures a tile's true draw position by diffing two renders. |

**Known failures that predate the clock work** (seen on clean `main`, not
caused by recent changes):
- `test_interior`: "the 8 dressers read as wardrobes (got 0)".
- `test_door`: 3 checks about walking out of the house.
- `test_cursor`: script error (`get_custom_data` on null).
- `test_storage`, `test_storage_moves`, `test_craft_card`, `test_panel`: they
  save screenshots, which fails headless (`save_png` on null), so they stop
  early; `test_storage` also fails "the wardrobe opens the window".

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
  code; read or grep the scripts.
