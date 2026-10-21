extends Node

## What the player keeps when the scene changes.
##
## Each scene builds its own HUD and its own Player, so anything those two hold
## is born fresh with them -- walk through a door and your bag and your stamina
## are back to their opening values. This autoload is the one copy that outlives
## the swap: the HUD borrows its inventory from here instead of making one, and
## the Player checks its stamina out on ready and hands it back as it changes.
##
## Nothing in here is saved to disk; it lasts for the run, not between runs.

## Emitted when stamina changes, so a gauge can follow it without polling.
signal stamina_changed(value: float, maximum: float)
## Emitted after sleeping, with the day just begun.
signal day_changed(day: int)

## How many slots a wardrobe holds. Three rows of nine, as chests usually are.
const STORAGE_SLOTS := 27

## The bag. Built on first use from whatever HUD asks for, then kept.
var inventory: Inventory

var stamina: float = 0.0
var max_stamina: float = 0.0
var day: int = 1

var _started := false
## Every wardrobe's contents, keyed by scene and cell -- see `storage_for`.
var _stores: Dictionary = {}
## What has been done to each map, keyed by scene path -- see `world_for`.
var _worlds: Dictionary = {}


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
		_stores[key] = Inventory.new(STORAGE_SLOTS)
	return _stores[key]


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
##   farm    {tilled, wet, crops}                   (Farm)
func world_for(map: Node) -> Dictionary:
	var key := map.scene_file_path if map != null else ""
	if not _worlds.has(key):
		_worlds[key] = {"hoed": {}, "broken": [], "trees": {}, "farm": {}}
	return _worlds[key]


## Turns in for the night: a day passes and the gauge comes back full.
func sleep() -> int:
	day += 1
	put_stamina(max_stamina)
	day_changed.emit(day)
	return day


## Wipes everything, for a new game.
func reset() -> void:
	inventory = null
	stamina = 0.0
	day = 1
	_stores.clear()
	_worlds.clear()
	_started = false
