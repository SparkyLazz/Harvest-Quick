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
| Space / left mouse | Use the held item, or interact (bed, chest, wardrobe, shipping bin, seed-shop sign, the debt collector, the mailbox, **the townsfolk**); turns the page in a conversation |
| Click / Shift-click in the seed shop | Buy one packet / five |
| 1–9, mouse wheel | Pick hotbar slot |
| E | Profile screen (inventory, crafting, settings) |
| Esc | Close the open window |
| F9 (debug builds) | Step the sky: calendar → clear → rain → storm → calendar (§5a) |

## 3. Scripts

| Script | What it is |
|---|---|
| `PlayerState.gd` | **Autoload, and the save game** (`save_game`/`load_game`/`new_game`, §4). What survives scene changes: inventory, stamina, **coins** (`earn`/`spend`, `coins_changed`), day, clock minutes, storage contents (the **shipping bin** too, under `SHIPPING_KEY`), each map's changes. Sleep, pass-out and the overnight sale (`_ship`) live here. |
| `SceneTransition.gd` | **Autoload.** Fade-to-black scene changes (`go_to`, `fade_through`). Pauses the tree during the fade; places the player on `SceneTree.scene_changed` (built in since 4.5), not after a guessed number of frames. |
| `MouseCursor.gd` | **Autoload.** Cursor icon by context: arrow, paw over usable furniture (never over an open window), closed paw while a panel carries a stack. |
| `Weather.gd` | **Autoload.** What the sky is doing, worked out from the day number and stored nowhere (§5a). `today()`, `kind_for(day)`, `is_wet_today()`, the pure `rolled_for(day)`, the `forced` override and the `changed(kind)` signal. |
| `Rain.gd` | The rain you see: two GPUParticles2D sheets, an overcast wash and lightning, on a CanvasLayer at layer 5 — over the world, under the HUD (§5a). Only the outdoor scene carries one. |
| `Debt.gd` | **Autoload, and the first one registered** (see §4b). Mom's debt: balance, weekly minimum, interest, late fees, strikes, and the `lost` signal the ending listens for. Rules only — it never touches the screen. |
| `Mail.gd` | **Autoload**, registered after `Debt` and before `PlayerState` (see §4c). The post: what arrives on which day, what Mom's letters cost, and the inbox. Puts her money on the debt the moment a letter lands. |
| `Mailbox.gd` | The box beside the house. Waves two frames of the pack's letter animation while anything is unread, plain otherwise. Another `interactable` node. |
| `MailPanel.gd` | The post window: letters down the left (newest first, `!` for unread), the picked one on the right with what it cost in red. |
| `EndingScreen.gd` | **Autoload.** The bad ending, drawn above the fade (layer 200) and ignoring the pause, because it lands while the player is asleep behind a scene change. |
| `Lawyer.gd` | **Autoload.** The case against Mom: the four pieces of evidence and what each one waits on, the fee, and `hire()` -- which voids the debt and ends the game well (5c). |
| `Dialogue.gd` | **Autoload.** Who is talking and what is left to say: `say(who, lines, face, tint)`, `advance()`, `stop()`. A flat list of lines and no branching -- the choosing happens before a conversation starts. |
| `DialogueBox.gd` | The speech box: the pack's **premade** plate drawn whole, with the name, the line and the click-to-continue chevron placed at measured spots inside it (5b). |
| `Townsfolk.gd` | The people in town -- one script, a `person` id picks the name, the tint and the lines. Another `interactable` node. |
| `Collector.gd` | The debt collector standing at the farm gate on Sundays. The first thing in the world that is a node rather than a painted tile, so the first user of the `interactable` group (§4b). |
| `DebtPanel.gd` | His bill: the figures and the three pay buttons. Same chrome as the storage window, its own `BASE_SIZE`, whole-number zoom. |
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
  counts}, stores: {key: {items, counts}}, worlds, debt, mail, lawyer}`. The
  last three are whatever `Debt`, `Mail` and `Lawyer` hand over from their
  own `to_record()`.
  - **`SAVE_VERSION` is 4.** 1 → 2 added the debt, 2 → 3 the post, 3 → 4 the
    lawyer's case. A save of another version is
    refused outright and the game starts new; there is no migration, by design
    (`_readable`). The weather, by contrast, added no field at all — it is
    worked out from the day number (§5a), which is why it needed no bump.
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

## 4b. The debt, the collector and the ending (`Debt.gd` and friends)

- **Rules in `Debt.gd`, nothing else.** Its constants are `econ_sim.py`'s,
  spelled the same, so the simulation's claim about fairness is a claim about
  this code. The game rounds the balance to whole coins every week; the
  simulator does not, so they drift by a coin or two over a run.
- **The week is the unit.** `paid_this_week` piles up, and `_settle()` runs
  once per week turn on `day_changed`: minimum met or missed → late fee and a
  strike → interest on what is left. A part payment comes off the debt but is
  still a miss. Three strikes emits `lost`.
- **Autoload order matters, and `Debt` is first.** `PlayerState` reads the
  save in its own `_ready` and calls `Debt.from_record` while doing it, so
  `Debt` has to be a node by then. That in turn means `Debt` cannot connect to
  `PlayerState.day_changed` in its own `_ready` — nothing else exists yet — so
  it defers the connection by a frame (`_bind.call_deferred`). `EndingScreen`
  defers for the mirror reason: it is registered last, so a game that was
  *already* lost when the save loaded is noticed a frame later.
- **Nodes you can use, not just tiles.** Furniture is painted and has no node,
  so `Player._try_interact` reads a verb off the tile. The collector is a
  node, so `Player._interactable_in_reach()` checks the `interactable` group
  first (`Collector.GROUP`) and people win over furniture behind them. Reach is
  loose on purpose, as it is for furniture: anyone on or beside your own cell
  counts, facing or not.
- **The collector finds the HUD through a group** (`HUD.GROUP`, `&"hud"`),
  since he lives in the map and the windows live in the HUD.
- **The ending is above everything.** Layer 200 (the fade is 128),
  `PROCESS_MODE_ALWAYS`, and it pauses the tree — but only *after*
  `SceneTransition.is_busy()` goes false, because the fade unpauses the tree
  when it finishes and would undo an earlier pause.
- **His sprite origin was measured, not guessed.** The art fills x 17..31,
  y 16..32 of the basic sheet's 48px cell, so `FEET` is (24, 32). Guessed at
  40 first, which floated him eight pixels off the ground: every test passed
  and the render showed it at once.

## 4c. The post (`Mail.gd`, `Mailbox.gd`, `MailPanel.gd`)

- **Delivery is by day, and idempotent.** `deliver_due(day)` is called on every
  `day_changed` and once at bind; each letter has an id (`mom-w4`,
  `winter-y1`, `opening`) and `_delivered` remembers it, so nothing can arrive
  twice however the days are walked -- a load, a catch-up, a debug jump.
- **Mom's figure is not rolled, it is mixed.** `mom_amount(week)` runs the week
  number through the same kind of mixer `Weather` uses, so week 30's letter is
  always week 30's letter. The inbox *is* saved, because read/unread is real
  state that no formula can recover.
- **Her money goes on the debt at delivery, not at reading.** `Mail._deliver`
  calls `Debt.add`. Reading only clears the dot.
- **Autoload order, again** (§4b has the first half): `Debt`, then `Mail`, then
  `PlayerState`. Both of the first two must be nodes before `PlayerState`
  reads a save, and both defer their signal hook-ups; because deferred calls
  run in the order they were queued, and `Debt` is registered first, the week
  is settled before Mom is added to it on the morning a week turns. That is
  `econ_sim`'s order, and `test_mail` pins it with a figure that differs by
  one coin if the two ever swap (1127 against 1128).
- **`Mail.delivering`** turns delivery off. `test_debt` sets it false so its
  figures are about the debt's rules alone; nothing in the game touches it.
- **The box's frames were measured.** The sheet is 32x48 cells, five across,
  seven down; the post stands on y 41, centred on x 12, in every frame used.
  Frame (0,4) is the plain box, (0,2) and (1,2) the letter up -- those two
  alternate to make the wave.

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

## 5b. Dialogue and the town (step 5)

- **The box is the pack's premade plate, drawn whole.** The portrait window,
  its wooden rails, the bubble and the tail pointing back at the speaker are
  one image; the box never stretches it, only scales it by a whole number, and
  everything on it is a measured rect *inside* it (`RECESS`, `BUBBLE`,
  `NAME_AT`, `LINE_AT`, `MORE_AT`). The first attempt nine-sliced the bubble
  and placed a cut-out tail beside a separate portrait frame -- the join never
  sat right, and there was no reason for it: the asset already is the layout.
- **One line, and it has to fit.** The bubble is as tall as it is drawn, so a
  line does not wrap. `DialogueBox.fits()` measures a line against
  `LINE_WIDTH`, and `test_town` runs every written line of every character
  through it in every state -- 240 of them -- so writing too long for the art
  fails a test instead of being cut off in play.
- **Branching lives with the writer, not in the system.** `Dialogue` runs a
  flat list; `Townsfolk._lines_for()` and `Collector._lines()` read the debt,
  the calendar and the weather and pick one. Nothing in a conversation can
  change its mind halfway.
- **A window that is not a window.** The box does not wash the world out --
  you are standing in front of whoever is talking -- but `HUD.is_inventory_open`
  counts it, so the clock stops and the player stands still. The HUD takes the
  use key while it is up, so `Player` never sees it; and the box ignores a
  press on the frame it opened, so the press that started the conversation
  cannot also turn its first page.
- **The town's layout is painted by hand, in the editor** (decided
  2026-11-19). It was generated by a script first and it looked generated:
  houses standing on grass with their doors opening onto nothing, a road
  stabbing into an empty yard. That script is gone.
- **`Tools/new_city_scene.gd` writes a blank one** -- the six layers, a 14x10
  patch of grass over soil to stand on, water round it, the ferry, the three
  people in a row, the player and the HUD. A frame, not a town: everything it
  draws is meant to be painted over or rubbed out. It **refuses to run while
  `Scenes/City.tscn` exists**, so it can never take a drawn map with it.
  A headless save strips every `uid://`, so **run
  `python -I Tools/fix_city_uids.py` straight after** -- it puts them back
  from each file's own `.uid`, `.import` or header. `Scenes/Player.tscn` and
  `Scenes/Door.tscn` have no uid of their own and are referenced by path, as
  `Dev.tscn` already does.
- **What the code needs from the town scene**, whatever it is painted to look
  like. `Tools/test_town.gd` checks exactly this list and measures nothing
  else -- no size, no house count, no named cell -- so the map can be redrawn
  freely without a test going red over it. **While there is no
  `Scenes/City.tscn` at all** -- one is being drawn from scratch -- the suite
  says `SKIP` for the handful of checks that need it and runs everything else
  on the farm, with the three people stood in it by hand:

  | Node | Why |
  |---|---|
  | `Grass Layer` (TileMapLayer, painted) | The grid every cell lookup comes off: `Player.grass_layer_path`, and the `ground_layer_path` of each person standing in it. |
  | `FromFarm` (Marker2D) | Where the farm's ferry puts the player down. |
  | `Ferry/Door` (the `Door` scene) | `target_scene` the farm, `spawn_point` `FromTown`. The farm's own `Ferry/Door` points back here with `FromFarm`. |
  | `Player`, `HUD` | As every other map has them. |
  | A `Townsfolk` node per person | `person` set to `seller`, `lawyer` or `neighbour`. They find the HUD through its group, so they can sit anywhere in the tree. |
  | **No** `Farm` node | Which is what stops the hoe digging the town up. |

  `Props`, `Decorations`, `Buildings`, `Soil Layer` and `Water Layer` are the
  farm's names and worth keeping for consistency, but nothing requires them:
  people are reachable without a props layer (§5b, "People before props").
- **Ground under grass makes the path.** The town paints soil over the whole
  rectangle and grass over everything but the square and the road, so a path
  is grass taken away. The first version used the stone tileset and read as a
  car park; earth is the same palette as the rest of the game.
- **People before props.** `Player._interactable_in_reach()` is checked before
  the props layer is even looked for, so someone standing in front of the
  shipping bin is who you mean -- and a map with no props layer can still have
  people in it.
- **The hoe needs a farm.** `_land_hoe_hit` gives up with a shrug when there is
  no `Farm` node, which is what stops the town square being dug up.

## 5a. Weather (`Weather.gd`, `Rain.gd`)

- **Nothing is stored.** `Weather.rolled_for(day)` is a pure function of the
  day number: a 31-bit integer mix (multiply, fold the high bits down, mix
  again) turned into two rolls — one against the season's chance of rain, one
  against its share of storms. So the farm, the clock and a save reloaded a
  week later all agree with no new save field and no `SAVE_VERSION` bump.
  Chances live in `RAIN_CHANCE` / `STORM_SHARE`; day 1 is always clear.
- `Weather.forced` pins the sky (`-1` follows the calendar). **Anything run
  with `--script` is pinned to clear on `_ready`** — without that, a suite
  that sleeps through a dozen days passes or fails on which of them happened
  to be rainy; `test_clock`'s "comes back dry" did exactly that. `test_weather`
  and `shoot_rain` set `forced` themselves.
- `changed(kind)` is emitted when the sky actually changes — on `day_changed`
  and when `forced` is set, not every morning.
- **Farm.** `Farm._soak()` wets every tilled cell on a wet day; it is called
  after `_pass_night` (which dries the soil for the new day), on restore, and
  on `Weather.changed`. `_on_tilled` wets soil hoed in the rain. A clearing
  sky never takes water back, so yesterday's rain still grows tonight's crop.
- **Rain.gd.** Screen-space `CanvasLayer` at layer 5, so it needs no camera
  chasing and sits under the HUD (10) and the fade (128). Drops are made in
  code (`_streak()`: a 1×6 bar, brightest at the head) — there is no rain art
  in either pack. `particle_flag_align_y` turns each drop along its own
  velocity, so the lean and the art never disagree. Two sheets (near: bigger,
  faster, brighter; far: smaller, slower, fainter). Counts scale with window
  area; `preprocess` means the first frame is already a skyful. `_resize`
  follows `size_changed`.
- The overcast wash must be **darker than the art it lies over**. The first
  try was a mid blue-grey, and at a strength you could see at all the farm
  went pale rather than overcast.
- **The clock** picks its picture from row 5 of the icon sheet on a wet day
  (`ClockPlate.RAIN_ROW`, same columns as the dry row). The sheet has no
  orange storm cloud, so dawn and dusk show the plain rain picture for both.

## 5c. The lawyer (`Lawyer.gd`)

- **Four pieces, gathered in order**, each with its own condition in
  `can_take`. `letters` needs three of Mom's letters and takes itself when
  they arrive; `word` needs `letters`; `ledger` needs `word`; `paper` needs
  `ledger` **and** week 12.
- **Week 12 is structural, not a guard.** The rule in §4 is that the case
  cannot be complete before week 12, and it is true here because the last
  piece is the one with the calendar on it. There is no separate check that
  could be forgotten, and no route round it.
- **A piece is taken once and then kept.** The condition is checked when the
  piece is offered and never again, so what survives a save is the piece, not
  the circumstance that allowed it.
- **`Debt.void_debt()` is the lawyer's and nobody else's.** The balance does
  not go to zero by being settled; it stops existing. Strikes are left alone.
- **Who hands what over lives in the people, not here.** `Townsfolk.interact`
  and `Collector.interact` ask `Lawyer.piece_from(person)` and take it before
  the conversation starts, so the lines they then choose describe the state
  the player is actually in.
- **The ending screen has two faces** and is otherwise one screen: same plate,
  same button, different words. A game already won or lost when the save
  loaded ends again at once, winning checked first.
- **Autoload order**: `Debt`, `Mail`, `Lawyer`, then `PlayerState` -- all
  three must be nodes before a save is read, and all three defer their signal
  hook-ups by a frame for the same reason (§4b, §4c).

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
| `test_debt.gd` | The debt: the minimum (both branches, clamped), the collector's day, paying, a week met and a week missed and a week half paid, three strikes and the ending, the save round trip, and the bill's buttons. Checks the numbers against §4 by hand, so a constant changed by accident fails here. |
| `shoot_debt.gd` | **Windowed.** The collector at the gate, his bill, and the bad ending (`Tools/shot_collector.png`, `shot_debt_bill.png`, `shot_debt_ending.png`). |
| `test_mail.gd` | The post: what Mom costs and that it is steady, the opening letter, delivery on even weeks only, the settle-then-deliver order, nothing arriving twice, the neighbour's Fall warning, reading, the save round trip, and the box and window. |
| `shoot_mail.gd` | **Windowed.** The box waving, the post window, and one of Mom's letters with what it cost (`Tools/shot_mailbox.png`, `shot_mail_panel.png`, `shot_mail_mom.png`). |
| `test_lawyer.gd` | Step 6: the four pieces and their order, that no route finishes the case before week 12, the fee, the debt going void, Mom falling silent, the good ending, the save, and what he says at each stage. |
| `shoot_endings.gd` | **Windowed.** Both endings (`Tools/shot_ending_won.png`, `shot_ending_lost.png`). |
| `test_town.gd` | Step 5: the dialogue system on its own, what each person says in which state, that every written line fits the bubble, the town map, the ferry both ways, the hoe refusing the town square, and the collector talking before he bills. |
| `shoot_city.gd` | **Windowed.** The town square and a conversation in it (`Tools/shot_city.png`, `shot_dialogue.png`). |
| `new_city_scene.gd`, `fix_city_uids.py` | Write a **blank** `Scenes/City.tscn` and put its uids back (5b). The town is painted by hand; this only makes the frame. |
| `test_weather.gd` | The weather: the roll repeating, each season's rain, the `forced` override, rain watering the farm and growing what it waters (and a dry night growing nothing), the clock's window per sky, and the rain layer emitting/washing/flashing. |
| `shoot_rain.gd` | **Windowed.** Renders the farm under clear, rain and storm, plus a storm caught mid-flash (`Tools/shot_sky_*.png`). |
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

**All twenty suites pass headless** (as of 2026-11-19) and exit non-zero on
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
  times by reasoning about it, and the collector's `FEET` a fourth (§4b) --
  every test passed while he floated eight pixels off the ground.
- **Autoloads that talk to each other: order is the contract.** An autoload
  can only reach another one *as a node* if that one is registered earlier, so
  anything it does in `_ready` has to be deferred when it is the earlier one.
  `Debt` is registered before `PlayerState` (the save reads it) and defers its
  own signal hook-up; `EndingScreen` is last and defers its check of an
  already-lost save. Getting this wrong fails only when a save exists, which
  tools and tests never have.
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
