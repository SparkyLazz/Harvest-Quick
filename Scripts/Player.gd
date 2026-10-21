class_name Player
extends CharacterBody2D

## Top-down 4-direction character driven by the Sprout Lands premium spritesheet.
## Movement is grid-free: WASD (or the arrow keys) pick a direction, and the
## facing is kept on the last non-zero input so the idle pose stays consistent.
##
## The use input acts on the tile the character faces, and what it does depends
## on the held hotbar item:
##   hoe           clears the grass, uncovering tilled soil -- but only open
##                 grass: a tree, stump, flower, fence or building standing on
##                 the cell has to be cleared with the axe first
##   watering can  waters the soil
##   axe           chops a tree (then its stump), breaks a decoration (a
##                 flower, a mushroom, a fence), or grows grass back over
##                 hoed soil
##   seeds         plant in tilled soil
##   tree seeds    plant in open grass, and grow into a tree
##   anything else harvests a ripe crop (a ripe crop is picked with any item
##                 except the watering can)

## Emitted once the hoe has actually cleared a cell, for sound or particles.
signal tilled(cell: Vector2i)
## Emitted once the axe has grown grass back over a hoed cell.
signal untilled(cell: Vector2i)

const FACING_DIRS := {
	"down": Vector2i.DOWN,
	"up": Vector2i.UP,
	"right": Vector2i.RIGHT,
	"left": Vector2i.LEFT,
}

@export_group("Movement")
## Base walking speed, in pixels per second.
@export_range(0.0, 400.0, 1.0, "or_greater") var move_speed: float = 60.0
## Speed used while the run input is held. Ignored when `can_run` is off.
@export_range(0.0, 600.0, 1.0, "or_greater") var run_speed: float = 110.0
## How fast the character reaches its target speed. 0 means instant.
@export_range(0.0, 4000.0, 10.0, "or_greater") var acceleration: float = 900.0
## How fast the character stops once the input is released. 0 means instant.
@export_range(0.0, 4000.0, 10.0, "or_greater") var friction: float = 1200.0
## Lets diagonal input move at the same speed as a straight line.
@export var normalize_diagonals: bool = true
## Enables the run state (hold Shift) and its faster animation.
@export var can_run: bool = true

@export_group("Animation")
## Playback speed of the idle cycle, in frames per second.
@export_range(1.0, 30.0, 0.5) var idle_fps: float = 6.0
## Playback speed of the walk cycle, in frames per second.
@export_range(1.0, 30.0, 0.5) var walk_fps: float = 10.0
## Playback speed of the run cycle, in frames per second.
@export_range(1.0, 30.0, 0.5) var run_fps: float = 14.0
## Direction the character faces when the scene starts.
@export_enum("down", "up", "right", "left") var start_facing: String = "down"
## Playback speed of the hoe swing, in frames per second.
@export_range(1.0, 30.0, 0.5) var hoe_fps: float = 12.0
## Playback speed of the watering animation, in frames per second.
@export_range(1.0, 30.0, 0.5) var water_fps: float = 10.0
## Playback speed of the axe swing, in frames per second.
@export_range(1.0, 30.0, 0.5) var axe_fps: float = 12.0

@export_group("Hoeing")
## HUD that owns the hotbar. The swing only happens while its held item
## matches `hoe_item`, so the bar is what decides, not the key.
@export var hud_path: NodePath = ^"../HUD"
## Item id that counts as a hoe. Empty disables the check entirely.
@export var hoe_item: String = ItemDB.HOE
## Layer the hoe clears. Defaults to a sibling named "Grass Layer".
@export var grass_layer_path: NodePath = ^"../Grass Layer"
## Frame of the swing that lands the hit. The swing is 8 frames and the dust
## puff is drawn on frame 4, so the tile clears in step with the animation.
@export_range(0, 7) var hoe_impact_frame: int = 4
## Re-fit the grass around a cleared cell so it grows a proper edge, the way a
## hole painted with the terrain tool looks. Off leaves a hard square.
@export var refit_grass_edges: bool = true

@export_group("Interaction")
## Layer the furniture is painted on. Each tile carries its own verb in the
## tileset's "interact" data, so a wardrobe or a bed works wherever it is
## painted, with no node to place beside it.
@export var props_layer_path: NodePath = ^"../Props"
## Layer trees are painted on, as scene tiles. Planted tree seeds go here too.
@export var trees_layer_path: NodePath = ^"../Trees"

@export_group("Farming")
## Farm that owns planting, watering and harvesting. Without one, only the
## hoe works.
@export var farm_path: NodePath = ^"../Farm"
## Item id that counts as a watering can.
@export var watering_can_item: String = ItemDB.WATERING_CAN
## Frame of the watering animation where water leaves the can.
@export_range(0, 7) var water_impact_frame: int = 3

@export_group("Axe")
## Item id that counts as an axe.
@export var axe_item: String = ItemDB.AXE
## Frame of the axe swing that lands the chop. The swoosh is drawn on frame 4.
@export_range(0, 7) var axe_impact_frame: int = 4

@export_group("Stamina")
## Stamina when full.
@export_range(1.0, 500.0, 1.0, "or_greater") var max_stamina: float = 100.0
## What a hoe swing costs. Only paid when the swing actually hits ground to till.
@export_range(0.0, 100.0, 0.5) var hoe_cost: float = 8.0
## What a watering costs. Only paid on tilled soil.
@export_range(0.0, 100.0, 0.5) var water_cost: float = 5.0
## What an axe swing costs. Only paid when it hits a tree or hoed soil.
@export_range(0.0, 100.0, 0.5) var axe_cost: float = 6.0
## What planting a seed costs.
@export_range(0.0, 100.0, 0.5) var plant_cost: float = 2.0
## Below this share of full stamina, every interaction shows the tired emote
## instead of its usual one. There is no gauge; the emote is the warning.
@export_range(0.0, 1.0, 0.05) var low_stamina_fraction: float = 0.25
## Seconds after the last action before stamina starts to refill.
@export_range(0.0, 10.0, 0.1) var regen_delay: float = 1.5
## Stamina regained per second once refilling.
@export_range(0.0, 200.0, 0.5) var regen_rate: float = 15.0

@export_group("Emotes")
## Pop a reaction over the character after each interaction.
@export var show_emotes: bool = true

@export_group("Cursor")
## Show the marker on the tile the next action would hit.
@export var show_cursor: bool = true

@export_group("Tilled Soil")
## Layer restamped where the grass was cleared. Defaults to "Soil Layer".
@export var soil_layer_path: NodePath = ^"../Soil Layer"
## Atlas source holding the soil variants.
@export var tilled_soil_source: int = 0
## Plain soil variants, one picked at random per cleared cell. These are the
## decoration rows of the soil sheet, which carry no terrain, so stamping one
## will not disturb the terrain-painted tiles around it.
@export var tilled_soil_tiles: Array[Vector2i] = [
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
	Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6),
]

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _facing: String = "down"
var stamina: float = 0.0
var _since_spent: float = 0.0
var _action: String = ""         # "hoe" / "water" / "axe" while a swing is playing
var _hit_landed: bool = false
var _grass_layer: TileMapLayer
var _soil_layer: TileMapLayer
var _props: TileMapLayer
var _trees_layer: TileMapLayer
var _prop_anim: PropAnimator
## The prop whose window is up, so its lid can be shut again when the window
## goes. Unset between times rather than left pointing at the last chest used.
var _open_prop: Variant = null
var _hud: Node
var _farm: Farm
var _emote: EmoteBubble
var _just_denied: bool = false
## What each hoed cell looked like before, so the axe can put it back, and
## which soil tile it was given. Lives in PlayerState's record of this map, so
## it survives the scene being swapped out -- see `_restore_world`.
var _hoed := {}
## Decorations the axe has broken on this map, in order: [layer name, cell].
var _broken: Array = []
## Every map layer beside the player, topmost first, for the axe to search for
## tiles marked "breakable" -- so a flower breaks whichever layer it was painted on.
var _map_layers: Array[TileMapLayer] = []
## The layers drawn over the grass: whatever is painted on them stands on the
## ground, so the hoe can't dig there until it is gone.
var _cover_layers: Array[TileMapLayer] = []

func _ready() -> void:
	_facing = start_facing
	# Checked out of PlayerState, so walking indoors does not refill the bar.
	stamina = PlayerState.take_stamina(max_stamina)
	_grass_layer = get_node_or_null(grass_layer_path) as TileMapLayer
	_soil_layer = get_node_or_null(soil_layer_path) as TileMapLayer
	_props = get_node_or_null(props_layer_path) as TileMapLayer
	_trees_layer = get_node_or_null(trees_layer_path) as TileMapLayer
	if _props != null:
		_prop_anim = PropAnimator.new()
		add_child(_prop_anim)
	_hud = get_node_or_null(hud_path)
	if _hud != null and _hud.has_signal("storage_closed"):
		_hud.connect("storage_closed", _on_storage_closed)
	_farm = get_node_or_null(farm_path) as Farm
	if get_parent() != null:
		for node in get_parent().get_children():
			if node is TileMapLayer:
				_map_layers.push_front(node)
		# _map_layers runs topmost first, so everything before the grass is over it.
		for layer in _map_layers:
			if layer == _grass_layer:
				break
			_cover_layers.append(layer)
		var world := PlayerState.world_for(get_parent())
		_hoed = world["hoed"]
		_broken = world["broken"]
		_restore_world()
	_apply_animation_speeds()
	if show_emotes:
		_emote = EmoteBubble.new()
		add_child(_emote)
	if show_cursor and _grass_layer != null:
		var cursor := GridCursor.new()
		cursor.player = self
		add_child(cursor)
	sprite.frame_changed.connect(_on_sprite_frame_changed)
	sprite.animation_finished.connect(_on_sprite_animation_finished)
	_play("idle")

func _physics_process(delta: float) -> void:
	_regen(delta)
	if not _action.is_empty():
		# Stay put for the whole swing; the animation drives the rest.
		velocity = _approach(velocity, Vector2.ZERO, friction, delta)
		move_and_slide()
		return

	# The inventory is a menu: while it is open the character stands still.
	var blocked: bool = _hud != null and _hud.has_method("is_inventory_open") 			and _hud.call("is_inventory_open")
	var input := Vector2.ZERO if blocked else _read_input()

	if not blocked and Input.is_action_just_pressed("use") and _use_held_item(input):
		return

	var speed := run_speed if _is_running(input) else move_speed
	var target := input * speed

	if input == Vector2.ZERO:
		velocity = _approach(velocity, Vector2.ZERO, friction, delta)
	else:
		velocity = _approach(velocity, target, acceleration, delta)
		_facing = _facing_for(input)

	move_and_slide()
	_play(_state_for(input))

func _read_input() -> Vector2:
	if normalize_diagonals:
		return Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"),
	)

func _is_running(input: Vector2) -> bool:
	return can_run and input != Vector2.ZERO and Input.is_action_pressed("run")

func _state_for(input: Vector2) -> String:
	if input == Vector2.ZERO:
		return "idle"
	return "run" if _is_running(input) else "walk"

## Vertical input wins ties so that pure diagonals keep a stable facing.
func _facing_for(input: Vector2) -> String:
	if absf(input.x) > absf(input.y):
		return "right" if input.x > 0.0 else "left"
	return "down" if input.y > 0.0 else "up"

func _held() -> String:
	if _hud == null or not _hud.has_method("held_item"):
		return ""
	return _hud.call("held_item")


## The hotbar decides what the key does. With no HUD wired up the player still
## hoes, so the character works on its own.
## Returns true when something started, so the caller can skip walking.
func _use_held_item(input: Vector2) -> bool:
	_just_denied = false
	var started := _dispatch_use(input)
	# Nothing happened and it wasn't for want of stamina: say so.
	if not started and not _just_denied:
		_react("question")
	return started


## Pops an emote, swapping in the tired one while stamina is low.
func _react(emote: String) -> void:
	if _emote == null:
		return
	if emote != "question" and stamina <= max_stamina * low_stamina_fraction:
		emote = "tired"
	_emote.show_emote(emote)


func _dispatch_use(input: Vector2) -> bool:
	if _try_interact(input):
		return true
	var item := _held()
	if _hud == null:
		return _start_action("hoe", input)
	# A ripe crop is picked before anything else, unless the can is out.
	if item != watering_can_item and _try_harvest(input):
		return true
	if item == hoe_item or hoe_item.is_empty():
		return _start_action("hoe", input)
	if item == watering_can_item and _farm != null:
		return _start_action("water", input)
	if item == axe_item and not axe_item.is_empty():
		return _start_action("axe", input)
	if ItemDB.is_seed(item):
		return _try_plant(item, input)
	if ItemDB.is_tree_seed(item):
		return _try_plant_tree(item, input)
	return false


## Acts on whatever furniture is being faced. The verb comes off the tile, so
## this stays the same however the room is rearranged.
## What using the tile ahead would do, by name, or "" for nothing. The prompt
## sign reads this too, so what it offers and what the key does cannot drift.
func interaction_ahead() -> String:
	if _props == null or not _action.is_empty():
		return ""
	if _hud != null and _hud.has_method("is_inventory_open") and _hud.call("is_inventory_open"):
		return ""
	var data := _props.get_cell_tile_data(prop_in_reach())
	return str(data.get_custom_data("interact")) if data != null else ""


## The prop this player can use.
##
## A prop's hitbox is the floor in front of it, not the square it stands on, so
## simply walking up to a chest is enough: standing on that floor counts even
## without lining the facing up. Whatever is being faced still counts too, which
## is what makes a bed usable from its side.
func prop_in_reach() -> Vector2i:
	var faced := facing_cell()
	if _props.get_cell_tile_data(faced) != null:
		return faced
	var layer := _grid()
	if layer == null:
		return faced
	var standing := layer.local_to_map(layer.to_local(global_position))
	var behind := standing - Vector2i(0, 1)
	return behind if _props.get_cell_tile_data(behind) != null else faced


func _try_interact(input: Vector2) -> bool:
	if _props == null:
		return false
	if input != Vector2.ZERO:
		_facing = _facing_for(input)
	var cell := prop_in_reach()
	var data := _props.get_cell_tile_data(cell)
	if data == null:
		return false
	match str(data.get_custom_data("interact")):
		"chest":
			# Opens a shut lid and shuts an open one. Which it is comes off the
			# tile, so a chest left open stays open until someone closes it.
			if _prop_anim == null:
				return false
			# Read which way the lid is about to go before moving it: the window
			# follows the lid, so a chest being shut takes its window with it.
			var opening := not _prop_anim.is_open(_props, cell)
			if not _prop_anim.toggle(_props, cell):
				return false
			if opening:
				_open_storage(cell)
			else:
				_close_storage()
			return true
		"wardrobe":
			# A dresser has the one frame, so there is nothing to animate --
			# using it is the window opening and nothing else.
			return _open_storage(cell)
		"bed":
			return _sleep()
	return false


## Puts the storage window up on the furniture at `cell`. The cell is the
## furniture's identity -- painted props have no node to name -- so the window
## comes back to the same contents every time that one is opened.
func _open_storage(cell: Vector2i) -> bool:
	if _hud == null or not _hud.has_method("open_storage"):
		return false
	_play("idle")
	velocity = Vector2.ZERO
	_open_prop = cell
	_hud.call("open_storage", PlayerState.storage_key(get_tree().current_scene, cell))
	return true


func _close_storage() -> void:
	if _hud != null and _hud.has_method("close_storage"):
		_hud.call("close_storage")


## The window has gone, so the furniture goes back to how it was found. Esc and
## the profile key close the window without going through the chest, so without
## this a chest is left standing open with nothing on screen to close it.
##
## Shutting a lid that is already travelling is refused by the animator, so the
## ordinary case -- using the chest again, which shuts the lid and the window
## together -- is not animated twice.
func _on_storage_closed(_key: String) -> void:
	var cell: Variant = _open_prop
	_open_prop = null
	if cell == null or _prop_anim == null or _props == null:
		return
	if _prop_anim.can_animate(_props, cell) and _prop_anim.is_open(_props, cell):
		_prop_anim.play(_props, cell, false)


func _sleep() -> bool:
	_play("idle")
	velocity = Vector2.ZERO
	SceneTransition.fade_through(func() -> void:
		PlayerState.sleep()
		stamina = PlayerState.stamina)
	return true


## Swinging turns the character to face the input first, so you can work a tile
## to the side without having to step towards it.
func _start_action(action: String, input: Vector2) -> bool:
	if input != Vector2.ZERO:
		_facing = _facing_for(input)
	# The swing plays either way, but only a swing that does something costs.
	var cell := facing_cell() if _grass_layer != null else Vector2i.ZERO
	if _action_hits(action, cell) and not _pay(_action_cost(action)):
		return false
	_action = action
	_hit_landed = false
	velocity = Vector2.ZERO
	sprite.play("%s_%s" % [action, _facing])
	return true


## Open grass only: nothing standing on it, tilled soil included -- a tree
## needs the ground the hoe has not had.
func can_plant_tree(cell: Vector2i, seed_item: String) -> bool:
	return _trees_layer != null and _tree_scene_id(ItemDB.info(seed_item).get("tree", "")) >= 0 \
			and _grass_layer != null and _grass_layer.get_cell_tile_data(cell) != null \
			and not is_covered(cell)


func _try_plant_tree(seed_item: String, input: Vector2) -> bool:
	if _hud.inventory == null:
		return false
	if input != Vector2.ZERO:
		_facing = _facing_for(input)
	var cell := facing_cell()
	if not can_plant_tree(cell, seed_item) or not _pay(plant_cost):
		return false
	var scene_id := _tree_scene_id(ItemDB.info(seed_item)["tree"])
	# The record goes in first: the tile spawns the tree, and the tree reads it.
	PlayerState.world_for(get_parent())["trees"][cell] = ChoppableTree.planted_state(scene_id)
	_trees_layer.set_cell(cell, _tree_source_id(), Vector2i.ZERO, scene_id)
	_hud.inventory.remove_from_slot(_hud.selected_slot, 1)
	_react("check")
	_play("idle")
	return true


## The tileset's scene-collection source, the one trees are painted from.
func _tree_source_id() -> int:
	if _trees_layer == null or _trees_layer.tile_set == null:
		return -1
	var tiles := _trees_layer.tile_set
	for i in tiles.get_source_count():
		var id := tiles.get_source_id(i)
		if tiles.get_source(id) is TileSetScenesCollectionSource:
			return id
	return -1


## Which scene tile grows `species`, read off the scenes themselves so the
## tileset can be reordered freely. -1 if no tile grows it.
func _tree_scene_id(species: String) -> int:
	var source_id := _tree_source_id()
	if source_id < 0 or species.is_empty():
		return -1
	var source := _trees_layer.tile_set.get_source(source_id) as TileSetScenesCollectionSource
	for i in source.get_scene_tiles_count():
		var id := source.get_scene_tile_id(i)
		var scene := source.get_scene_tile_scene(id)
		if scene != null and _species_of(scene) == species:
			return id
	return -1


static func _species_of(scene: PackedScene) -> String:
	var state := scene.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"species":
			return state.get_node_property_value(0, i)
	# An inherited scene that doesn't set it takes its base's.
	var base := state.get_node_instance(0)
	return _species_of(base) if base != null else "oak"


func _try_plant(seed_item: String, input: Vector2) -> bool:
	if _farm == null or _hud.inventory == null:
		return false
	if input != Vector2.ZERO:
		_facing = _facing_for(input)
	var crop: String = ItemDB.info(seed_item)["crop"]
	var cell := facing_cell()
	if not _farm.is_tilled(cell) or _farm.has_crop(cell):
		return false
	if not _pay(plant_cost):
		return false
	_farm.plant(cell, crop)
	_react("check")
	_hud.inventory.remove_from_slot(_hud.selected_slot, 1)
	_play("idle")
	return true


func _try_harvest(input: Vector2) -> bool:
	if _farm == null or _hud.inventory == null:
		return false
	if input != Vector2.ZERO:
		_facing = _facing_for(input)
	var cell := facing_cell()
	var yield_ := _farm.peek_harvest(cell)
	# Leave the crop standing rather than lose it to a full inventory.
	if yield_.is_empty() or not _hud.inventory.can_add(yield_["item"], yield_["amount"]):
		return false
	_farm.harvest(cell)
	_hud.inventory.add(yield_["item"], yield_["amount"])
	_react("sparkle")
	_play("idle")
	return true


## Would `action` do anything to `cell`? Only a swing that does pays stamina.
func _action_hits(action: String, cell: Vector2i) -> bool:
	match action:
		"hoe":
			return _can_hoe(cell)
		"water":
			return _farm != null and _farm.is_tilled(cell)
		"axe":
			return _can_axe(cell)
	return false


func _action_cost(action: String) -> float:
	match action:
		"hoe":
			return hoe_cost
		"water":
			return water_cost
		"axe":
			return axe_cost
	return 0.0


## Any layer will do to turn a position into a cell -- they share one grid --
## so indoors, where there is no farmland, the furniture layer stands in.
func _grid() -> TileMapLayer:
	return _grass_layer if _grass_layer != null else _props


## The cell the character is standing on, offset one step along the facing.
func facing_cell() -> Vector2i:
	var layer := _grid()
	if layer == null:
		return Vector2i.ZERO
	var here := layer.local_to_map(layer.to_local(global_position))
	return here + FACING_DIRS[_facing]

## World position of a cell's centre.
func cell_center(cell: Vector2i) -> Vector2:
	var layer := _grid()
	return layer.to_global(layer.map_to_local(cell)) if layer != null else global_position


## Would the held item do anything on this cell right now? Mirrors the order in
## `_use_held_item`, and drives the cursor's green/red.
func can_use_at(cell: Vector2i) -> bool:
	var item := _held()
	if _hud == null:
		return _can_hoe(cell) and stamina >= hoe_cost
	if item != watering_can_item and _farm != null and _hud.inventory != null:
		var yield_ := _farm.peek_harvest(cell)
		if not yield_.is_empty():
			return _hud.inventory.can_add(yield_["item"], yield_["amount"])
	if item == hoe_item or hoe_item.is_empty():
		return _can_hoe(cell) and stamina >= hoe_cost
	if item == watering_can_item:
		return _farm != null and _farm.is_tilled(cell) and stamina >= water_cost
	if item == axe_item and not axe_item.is_empty():
		return _can_axe(cell) and stamina >= axe_cost
	if ItemDB.is_seed(item):
		return _farm != null and _farm.is_tilled(cell) and not _farm.has_crop(cell) 				and stamina >= plant_cost
	if ItemDB.is_tree_seed(item):
		return can_plant_tree(cell, item) and stamina >= plant_cost
	return false


## Takes stamina for an action. False, with the gauge told, if there isn't enough.
func _pay(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if stamina < cost:
		_just_denied = true
		_react("tired")
		return false
	stamina -= cost
	PlayerState.put_stamina(stamina)
	_since_spent = 0.0
	return true


## Refills after a pause since the last spend. Walking does not hold it up, only
## acting does.
func _regen(delta: float) -> void:
	_since_spent += delta
	if stamina >= max_stamina or _since_spent < regen_delay:
		return
	stamina = minf(stamina + regen_rate * delta, max_stamina)
	PlayerState.put_stamina(stamina)


func _can_hoe(cell: Vector2i) -> bool:
	return _grass_layer != null and _grass_layer.get_cell_tile_data(cell) != null 			and not is_covered(cell)


## Is something standing on this cell's ground? A tree or stump, or any tile
## painted on a layer above the grass -- a flower, a fence, the house.
func is_covered(cell: Vector2i) -> bool:
	if tree_at(cell) != null:
		return true
	for layer in _cover_layers:
		if layer.get_cell_source_id(cell) != -1:
			return true
	return false


## The tree standing in `cell`, or null. Trees are nodes with their own
## animation rather than tiles, so they are found through their group.
func tree_at(cell: Vector2i) -> ChoppableTree:
	var layer := _grid()
	if layer == null:
		return null
	for node in get_tree().get_nodes_in_group(&"choppable"):
		var tree := node as ChoppableTree
		if tree != null and tree.cell_on(layer) == cell:
			return tree
	return null


## The layer holding a breakable tile at `cell`, topmost first, or null.
## A tile is breakable when the tileset's "breakable" data says so.
func breakable_layer_at(cell: Vector2i) -> TileMapLayer:
	for layer in _map_layers:
		var data := layer.get_cell_tile_data(cell)
		if data != null and data.has_custom_data("breakable") and data.get_custom_data("breakable"):
			return layer
	return null


## A tree to chop, a decoration to break, or soil this player hoed with nothing
## planted in it.
func _can_axe(cell: Vector2i) -> bool:
	var tree := tree_at(cell)
	if tree != null:
		return tree.can_chop()
	return breakable_layer_at(cell) != null or _can_regrow(cell)


## Only ground the hoe dug can be grown back, and never from under a crop.
func _can_regrow(cell: Vector2i) -> bool:
	if not _hoed.has(cell) or _grass_layer == null:
		return false
	return _farm == null or not _farm.has_crop(cell)


func _land_axe_hit() -> void:
	_hit_landed = true
	var cell := facing_cell()
	var tree := tree_at(cell)
	if tree != null and tree.can_chop():
		var drops := tree.chop()
		if drops.is_empty():
			_react("sweat")
			return
		for i in drops.size():
			_collect(cell, drops[i]["item"], drops[i]["amount"], i)
		_react("sparkle")
		return
	var layer := breakable_layer_at(cell)
	if layer != null:
		_break_tile(layer, cell)
		return
	if _can_regrow(cell):
		_regrow_grass(cell)
		_react("sweat")
		return
	_react("question")


## Knocks a decoration off its layer. A tile that joins its neighbours, like a
## fence, is cleared through its terrain so the run re-fits around the gap
## instead of leaving rails pointing at nothing. Its "drop" data, if any, is
## what it gives up.
func _break_tile(layer: TileMapLayer, cell: Vector2i) -> void:
	var data := layer.get_cell_tile_data(cell)
	var drop := str(data.get_custom_data("drop")) if data.has_custom_data("drop") else ""
	_clear_tile(layer, cell)
	_broken.append([String(layer.name), cell])
	if not drop.is_empty():
		_collect(cell, drop, 1)
		_react("sparkle")
	else:
		_react("sweat")


func _clear_tile(layer: TileMapLayer, cell: Vector2i) -> void:
	var data := layer.get_cell_tile_data(cell)
	if data == null:
		return
	if data.terrain_set >= 0:
		layer.set_cells_terrain_connect([cell], data.terrain_set, -1, false)
	else:
		layer.erase_cell(cell)


## Puts the map back the way the player left it. The scene file only knows how
## it started, so what was dug and broken since is replayed over the top.
## Trees and the farm keep their own records and restore themselves.
func _restore_world() -> void:
	if _grass_layer != null:
		for cell: Vector2i in _hoed:
			var was: Dictionary = _hoed[cell]
			_dig(cell, was["terrain_set"])
			if _soil_layer != null and was.has("stamp"):
				_soil_layer.set_cell(cell, tilled_soil_source, was["stamp"], 0)
	for entry: Array in _broken:
		var layer := get_parent().get_node_or_null(NodePath(entry[0])) as TileMapLayer
		if layer != null:
			_clear_tile(layer, entry[1])
	# Trees grown from seed aren't in the scene file: paint them back. This also
	# covers a seed planted where a painted tree was cleared.
	if _trees_layer != null:
		var trees: Dictionary = PlayerState.world_for(get_parent())["trees"]
		for cell: Vector2i in trees:
			var tree: Dictionary = trees[cell]
			if tree.has("planted") and not tree["gone"]:
				_trees_layer.set_cell(cell, _tree_source_id(), Vector2i.ZERO, tree["planted"])


## Puts a drop in the bag. Whatever does not fit is lost rather than leaving
## the tree standing, since it is already on its way down. `order` fans out the
## pop-ups when one swing gives several things.
func _collect(cell: Vector2i, item: String, amount: int, order: int = 0) -> void:
	if _hud != null and _hud.inventory != null:
		_hud.inventory.add(item, amount)
	if _farm != null:
		_farm.float_icon(cell, item, amount, order)


## Undoes a hoe: the soil goes back to the tile it was, and the grass is painted
## back in with its own terrain so its edges close over the hole again.
func _regrow_grass(cell: Vector2i) -> void:
	var was: Dictionary = _hoed[cell]
	_hoed.erase(cell)
	if _soil_layer != null:
		if was["soil_source"] >= 0:
			_soil_layer.set_cell(cell, was["soil_source"], was["soil_atlas"], was["soil_alt"])
		else:
			_soil_layer.erase_cell(cell)
	if refit_grass_edges and was["terrain_set"] >= 0:
		_grass_layer.set_cells_terrain_connect([cell], was["terrain_set"], was["terrain"], false)
	else:
		_grass_layer.set_cell(cell, was["grass_source"], was["grass_atlas"], was["grass_alt"])
	untilled.emit(cell)


func _land_water() -> void:
	_hit_landed = true
	if _farm != null:
		_react("happy" if _farm.water(facing_cell()) else "question")


func _land_hoe_hit() -> void:
	_hit_landed = true
	if _grass_layer == null:
		push_warning("Player: no grass layer at '%s', nothing to hoe." % grass_layer_path)
		return
	var cell := facing_cell()
	var data := _grass_layer.get_cell_tile_data(cell)
	if data == null or is_covered(cell):
		_react("question")
		return                                   # bare soil, or something in the way
	# Read the terrain set off the tile we are about to remove, so the re-fit
	# works for whatever terrain the layer was painted with.
	_remember_ground(cell, data)
	_dig(cell, data.terrain_set)
	var stamp := _stamp_tilled_soil(cell)
	if stamp != Vector2i(-1, -1):
		_hoed[cell]["stamp"] = stamp
	tilled.emit(cell)
	_react("sweat")

## Notes what is about to be dug up, so the axe can put it back.
func _remember_ground(cell: Vector2i, grass: TileData) -> void:
	var has_soil := _soil_layer != null
	_hoed[cell] = {
		"terrain_set": grass.terrain_set,
		"terrain": grass.terrain,
		"grass_source": _grass_layer.get_cell_source_id(cell),
		"grass_atlas": _grass_layer.get_cell_atlas_coords(cell),
		"grass_alt": _grass_layer.get_cell_alternative_tile(cell),
		"soil_source": _soil_layer.get_cell_source_id(cell) if has_soil else -1,
		"soil_atlas": _soil_layer.get_cell_atlas_coords(cell) if has_soil else Vector2i(-1, -1),
		"soil_alt": _soil_layer.get_cell_alternative_tile(cell) if has_soil else 0,
	}

## Takes the grass off a cell.
func _dig(cell: Vector2i, terrain_set: int) -> void:
	if refit_grass_edges and terrain_set >= 0:
		# Painting the cell with terrain -1 clears it *and* re-runs the solver
		# over its neighbours, so the grass closes around the hole with its own
		# edge tiles. Plain erase_cell leaves them untouched and the hole comes
		# out a hard square.
		_grass_layer.set_cells_terrain_connect([cell], terrain_set, -1, false)
	else:
		_grass_layer.erase_cell(cell)


## Swap the exposed ground for one of the plain soil variants, so a hoed patch
## reads as turned earth instead of whatever the terrain happened to paint.
## Returns the variant used, or (-1, -1) when nothing was stamped.
func _stamp_tilled_soil(cell: Vector2i) -> Vector2i:
	if _soil_layer == null or tilled_soil_tiles.is_empty():
		return Vector2i(-1, -1)
	var tile: Vector2i = tilled_soil_tiles.pick_random()
	_soil_layer.set_cell(cell, tilled_soil_source, tile, 0)
	return tile

func _on_sprite_frame_changed() -> void:
	if _hit_landed:
		return
	if _action == "hoe" and sprite.frame >= hoe_impact_frame:
		_land_hoe_hit()
	elif _action == "water" and sprite.frame >= water_impact_frame:
		_land_water()
	elif _action == "axe" and sprite.frame >= axe_impact_frame:
		_land_axe_hit()

func _on_sprite_animation_finished() -> void:
	if _action.is_empty():
		return
	# A very short swing can finish before frame_changed reports the impact.
	if not _hit_landed:
		match _action:
			"hoe":
				_land_hoe_hit()
			"axe":
				_land_axe_hit()
			_:
				_land_water()
	_action = ""
	_play("idle")

func _approach(current: Vector2, target: Vector2, rate: float, delta: float) -> Vector2:
	if rate <= 0.0:
		return target
	return current.move_toward(target, rate * delta)

func _play(state: String) -> void:
	var anim := "%s_%s" % [state, _facing]
	if sprite.animation != anim:
		sprite.play(anim)

func _apply_animation_speeds() -> void:
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null:
		return
	# The .tres is shared between instances, so edit a private copy.
	frames = frames.duplicate(true)
	sprite.sprite_frames = frames
	for direction in FACING_DIRS:
		frames.set_animation_speed("idle_%s" % direction, idle_fps)
		frames.set_animation_speed("walk_%s" % direction, walk_fps)
		frames.set_animation_speed("run_%s" % direction, run_fps)
		frames.set_animation_speed("hoe_%s" % direction, hoe_fps)
		frames.set_animation_speed("water_%s" % direction, water_fps)
		frames.set_animation_speed("axe_%s" % direction, axe_fps)
