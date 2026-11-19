extends Node

## What the player keeps when the scene changes.
##
## Each scene builds its own HUD and its own Player, so anything those two hold
## is born fresh with them -- walk through a door and your bag and your stamina
## are back to their opening values. This autoload is the one copy that outlives
## the swap: the HUD borrows its inventory from here instead of making one, and
## the Player checks its stamina out on ready and hands it back as it changes.
##
## It is also the save game. Everything above is plain data, so the whole of
## it goes to disk with FileAccess.store_var -- Vector2i keys and all -- every
## morning, the way Stardew saves when you sleep. When the game starts it is
## read back and you wake in bed. There is one slot; a day played and not slept
## on is lost, as in Stardew. `new_game` starts over.

## Emitted when stamina changes, so a gauge can follow it without polling.
signal stamina_changed(value: float, maximum: float)
## Emitted after sleeping, with the day just begun.
signal day_changed(day: int)
## Emitted when the clock reaches its next STEP, so a face can redraw.
signal time_changed(minutes: int)
## Emitted the moment the clock hits PASS_OUT, before the screen goes dark.
signal passed_out
## Emitted whenever the purse changes, with what is in it now.
signal coins_changed(coins: int)
## Emitted overnight when the shipping bin sold something, with what it made.
signal shipped(earned: int)
## Emitted once the game has been written to disk.
signal saved

## How many slots a wardrobe holds. Three rows of nine, as chests usually are.
const STORAGE_SLOTS := 27
## Coins in hand on day one. Tools/econ_sim.py starts its runs from the same.
const START_COINS := 200
## The shipping bin's contents, under this key in `storage_for`. There is one
## bin however many are painted, as in Stardew: whatever is in it at night is
## sold, and the coins are there in the morning.
const SHIPPING_KEY := "shipping"
## Where you wake after collapsing, and the marker in it beside the bed.
const HOUSE_SCENE := "res://Scenes/PlayerHouse.tscn"
const BED_SPOT := &"Bed"
## Share of full stamina you wake with after passing out instead of going to bed.
const PASS_OUT_STAMINA := 0.5
## Bumped whenever what is saved changes shape; a save from another version is
## not read (the game starts new instead of half-loading it).
##   1 -> 2: the debt (step 3). Saves from 1 are refused and start a new game.
##   2 -> 3: the post (step 4). Same again.
##   3 -> 4: the lawyer's case (step 6). Same again.
const SAVE_VERSION := 4

## Where the game is kept. Tests point this somewhere of their own.
var save_path := "user://save.dat"
## Save every morning. Off when launched with --script, so tools and tests
## never read or overwrite the player's real save.
var autosave := true

## The bag. Built on first use from whatever HUD asks for, then kept.
var inventory: Inventory

var stamina: float = 0.0
var max_stamina: float = 0.0
var coins: int = START_COINS
var day: int = 1
## Minutes since midnight of `day`; see Calendar for why it runs past 24:00.
var minutes: int = Calendar.DAY_START

var _started := false
## Real seconds not yet worth a whole game minute.
var _carry := 0.0
var _passing_out := false
## Every wardrobe's contents, keyed by scene and cell -- see `storage_for`.
var _stores: Dictionary = {}
## What has been done to each map, keyed by scene path -- see `world_for`.
var _worlds: Dictionary = {}


## Reads the save, if there is one, and puts the player back in bed. Tools and
## tests (anything run with --script) are kept away from the save entirely.
func _ready() -> void:
	if _launched_by_tool():
		autosave = false
		return
	if load_game():
		# Deferred: the other autoloads and the first scene are not up yet.
		_wake_in_bed.call_deferred()


static func _launched_by_tool() -> bool:
	var args := OS.get_cmdline_args()
	return "--script" in args or "-s" in args


## The morning a save was made on: black at once, so the scene the game boots
## into is never seen, then the house with the player beside the bed.
func _wake_in_bed() -> void:
	SceneTransition.cover()
	SceneTransition.go_to(HOUSE_SCENE, BED_SPOT)


## Writes everything that outlives a scene to `save_path`. Whatever holds live
## map state only in memory (the farm, between visits) is asked to write it
## into its map's record first. Written to a .tmp file and swapped in, so a
## crash mid-write never leaves a half-saved game.
func save_game() -> bool:
	get_tree().call_group(&"saves_world", &"write_world")
	var stores := {}
	for key: String in _stores:
		stores[key] = _pack(_stores[key])
	var data := {
		"version": SAVE_VERSION,
		"day": day,
		"minutes": minutes,
		"coins": coins,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"started": _started,
		"inventory": _pack(inventory) if inventory != null else {},
		"stores": stores,
		"worlds": _worlds,
		# The debt and the post keep their own state; both hand over plain data
		# to go in here. Both autoloads are registered before this one so they
		# are nodes by the time a save is read, below.
		"debt": Debt.to_record(),
		"mail": Mail.to_record(),
		"lawyer": Lawyer.to_record(),
	}
	var tmp := save_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("PlayerState: cannot write %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_var(data)
	file.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
			ProjectSettings.globalize_path(save_path))
	if err != OK:
		push_error("PlayerState: cannot replace %s: %s" % [save_path, error_string(err)])
		return false
	saved.emit()
	return true


## Reads the game back from `save_path`. False, and nothing touched, when there
## is no save or it is not one this version can read. A .tmp left by a crash
## between writing and swapping is used if the save itself is missing.
func load_game() -> bool:
	var path := save_path
	if not FileAccess.file_exists(path):
		path = save_path + ".tmp"
		if not FileAccess.file_exists(path):
			return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	# store_var writes the data's length first. A file that disagrees with its
	# own length is damaged; refused here, quietly, rather than by get_var.
	if file.get_length() < 4 or file.get_32() != file.get_length() - 4:
		file.close()
		push_warning("PlayerState: %s is damaged." % path)
		return false
	file.seek(0)
	# Plain data only: a save file is never allowed to make objects.
	var data: Variant = file.get_var(false)
	file.close()
	if not _readable(data):
		push_warning("PlayerState: %s is not a save this version can read." % path)
		return false
	day = data["day"]
	minutes = data["minutes"]
	coins = data["coins"]
	stamina = data["stamina"]
	max_stamina = data["max_stamina"]
	_started = data["started"]
	_carry = 0.0
	_passing_out = false
	inventory = _unpack(data["inventory"]) if not data["inventory"].is_empty() else null
	_stores.clear()
	for key: String in data["stores"]:
		_fill(storage_for(key), data["stores"][key])
	_worlds = data["worlds"]
	Debt.from_record(data["debt"])
	Mail.from_record(data["mail"])
	Lawyer.from_record(data["lawyer"])
	coins_changed.emit(coins)
	time_changed.emit(minutes)
	return true


## Forgets the save file.
func delete_save() -> void:
	for path in [save_path, save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Starts over: no save, no changes anywhere, the first morning on the farm.
## Whatever is on screen as it goes cannot write itself back -- the farm, the
## player and the trees all hold their own map records, which `reset` leaves
## behind rather than clears.
func new_game() -> void:
	delete_save()
	reset()
	SceneTransition.go_to(ProjectSettings.get_setting("application/run/main_scene"))


static func _readable(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != SAVE_VERSION:
		return false
	for key in ["day", "minutes", "coins"]:
		if typeof(data.get(key)) != TYPE_INT:
			return false
	for key in ["inventory", "stores", "worlds", "debt", "mail", "lawyer"]:
		if typeof(data.get(key)) != TYPE_DICTIONARY:
			return false
	return typeof(data.get("stamina")) in [TYPE_FLOAT, TYPE_INT] \
			and typeof(data.get("max_stamina")) in [TYPE_FLOAT, TYPE_INT] \
			and typeof(data.get("started")) == TYPE_BOOL


static func _pack(inv: Inventory) -> Dictionary:
	return {"items": inv.items.duplicate(), "counts": inv.counts.duplicate()}


static func _unpack(packed: Dictionary) -> Inventory:
	var inv := Inventory.new(maxi(packed.get("items", []).size(), 1))
	_fill(inv, packed)
	return inv


static func _fill(inv: Inventory, packed: Dictionary) -> void:
	inv.items.assign(packed.get("items", []))
	inv.counts.assign(packed.get("counts", []))


## The inventory to use, made to `fill`'s measurements the first time anyone
## asks and simply handed back every time after. `fill` is only consulted on
## that first call, so a later scene cannot quietly reset the bag.
func take_inventory(slot_total: int, fill: Callable = Callable()) -> Inventory:
	if inventory == null:
		inventory = Inventory.new(slot_total)
		if fill.is_valid():
			fill.call(inventory)
	return inventory


## Checks stamina out for a Player that is coming up. The first Player to ask
## sets the opening value; the ones after it inherit whatever is left.
func take_stamina(maximum: float) -> float:
	max_stamina = maximum
	if not _started:
		_started = true
		stamina = maximum
	stamina = minf(stamina, maximum)
	return stamina


## Hands the current value back, so the next scene picks up where this one left.
func put_stamina(value: float) -> void:
	var clamped := clampf(value, 0.0, max_stamina)
	if is_equal_approx(clamped, stamina):
		return
	stamina = clamped
	stamina_changed.emit(stamina, max_stamina)


## The contents of one piece of furniture.
##
## Furniture is painted, not placed, so there is no node to hang an inventory
## off. What a wardrobe does have is the cell it occupies, which is as stable as
## any node name, so that is the identity used here: two wardrobes in the same
## room keep separate contents, and the one you filled yesterday still has your
## things in it tomorrow.
func storage_for(key: String) -> Inventory:
	if not _stores.has(key):
		var inv := Inventory.new(STORAGE_SLOTS)
		if key == SHIPPING_KEY:
			# Only what can be sold goes in: anything else would sit there,
			# or worse, look sold and be gone.
			inv.accepts = func(item: String) -> bool: return ItemDB.sell_price(item) > 0
		_stores[key] = inv
	return _stores[key]


## Adds to the purse.
func earn(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	coins_changed.emit(coins)


## Takes `amount` from the purse. False, and nothing taken, if it holds less.
func spend(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false
	if amount > 0:
		coins -= amount
		coins_changed.emit(coins)
	return true


## Builds the key `storage_for` wants. Scene included so the same cell in two
## different buildings is not the same wardrobe.
static func storage_key(scene: Node, cell: Vector2i) -> String:
	var where := scene.scene_file_path.get_file().get_basename() if scene else "?"
	return "%s:%d,%d" % [where, cell.x, cell.y]


## Everything the player has changed on one map, so it is still changed when
## they come back: a scene file only knows how the map started.
##
## `map` is the scene's root. The dictionary is handed out live, so whoever
## changes the map writes straight into it, and on the way back in reads what
## to put back. What each part holds is up to its owner:
##   hoed    cell -> what the hoe dug up            (Player)
##   broken  [[layer name, cell], ...] in order     (Player)
##   trees   cell -> {hits, stump, gone}            (ChoppableTree)
##   farm    {tilled, wet, crops, day}              (Farm)
func world_for(map: Node) -> Dictionary:
	var key := map.scene_file_path if map != null else ""
	if not _worlds.has(key):
		_worlds[key] = {"hoed": {}, "broken": [], "trees": {}, "farm": {}}
	return _worlds[key]


## Runs the clock on by `seconds` of real time. Whoever owns the screen calls
## this -- the HUD, and only while no window is up -- so the day stands still
## behind menus and during fades without this node having to know about either.
func pass_time(seconds: float) -> void:
	_carry += seconds
	var before := minutes
	while _carry >= Calendar.SECONDS_PER_MINUTE and minutes < Calendar.PASS_OUT:
		_carry -= Calendar.SECONDS_PER_MINUTE
		minutes += 1
	if minutes / Calendar.STEP != before / Calendar.STEP:
		time_changed.emit(minutes)
	if minutes >= Calendar.PASS_OUT:
		_carry = 0.0
		_pass_out()


## Turns in for the night: a day passes, the clock goes back to morning and the
## gauge comes back -- all of it after a proper night in bed, half after
## dropping where you stood.
func sleep(rested: bool = true) -> int:
	day += 1
	minutes = Calendar.DAY_START
	_carry = 0.0
	put_stamina(max_stamina if rested else max_stamina * PASS_OUT_STAMINA)
	# The bin is emptied while you sleep, so the morning starts paid -- before
	# day_changed, so anything that wakes up on it already sees the coins.
	_ship()
	day_changed.emit(day)
	time_changed.emit(minutes)
	# Saved once the night has fully happened -- crops grown, bin sold -- so the
	# save is the morning you wake to. Bed and passing out both come through here.
	if autosave:
		save_game()
	return day


## Sells everything in the shipping bin.
func _ship() -> void:
	if not _stores.has(SHIPPING_KEY):
		return
	var bin: Inventory = _stores[SHIPPING_KEY]
	var earned := ItemDB.value_of(bin)
	if earned <= 0:
		return
	for i in bin.size():
		if bin.item_at(i) != "":
			bin.set_slot(i, "", 0)
	earn(earned)
	shipped.emit(earned)


## Two in the morning and still up. The screen goes dark wherever the player is
## and they wake in bed the next day, short on stamina. Reloading the house even
## when already in it is what stands them by the bed.
##
## A door already mid-swing refuses the move, so this backs off and the next
## tick of the clock tries again once the screen is free.
func _pass_out() -> void:
	if _passing_out or SceneTransition.is_busy():
		return
	_passing_out = true
	passed_out.emit()
	# Awaiting the move itself rather than its `arrived` signal: a house that
	# fails to load never arrives, and this flag would then block every
	# pass-out after it.
	await SceneTransition.go_to(HOUSE_SCENE, BED_SPOT, sleep.bind(false))
	_passing_out = false


## Wipes everything, for a new game.
func reset() -> void:
	inventory = null
	stamina = 0.0
	coins = START_COINS
	day = 1
	minutes = Calendar.DAY_START
	_carry = 0.0
	_passing_out = false
	_stores.clear()
	_worlds.clear()
	_started = false
	Debt.reset()
	Lawyer.reset()
	# After Debt, and after `day` is back to 1: the post puts the opening
	# letter in the box for the new game, and it is addressed to day one.
	Mail.reset()
