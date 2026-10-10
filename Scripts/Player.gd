class_name Player
extends CharacterBody2D

## Top-down 4-direction character driven by the Sprout Lands premium spritesheet.
## Movement is grid-free: WASD (or the arrow keys) pick a direction, and the
## facing is kept on the last non-zero input so the idle pose stays consistent.
##
## The use input acts on the tile the character faces, and what it does depends
## on the held hotbar item:
##   hoe           clears the grass, uncovering tilled soil
##   watering can  waters the soil
##   seeds         plant in tilled soil
##   anything else harvests a ripe crop (a ripe crop is picked with any item
##                 except the watering can)

## Emitted once the hoe has actually cleared a cell, for sound or particles.
signal tilled(cell: Vector2i)

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

@export_group("Farming")
## Farm that owns planting, watering and harvesting. Without one, only the
## hoe works.
@export var farm_path: NodePath = ^"../Farm"
## Item id that counts as a watering can.
@export var watering_can_item: String = ItemDB.WATERING_CAN
## Frame of the watering animation where water leaves the can.
@export_range(0, 7) var water_impact_frame: int = 3

@export_group("Stamina")
## Stamina when full.
@export_range(1.0, 500.0, 1.0, "or_greater") var max_stamina: float = 100.0
## What a hoe swing costs. Only paid when the swing actually hits ground to till.
@export_range(0.0, 100.0, 0.5) var hoe_cost: float = 8.0
## What a watering costs. Only paid on tilled soil.
@export_range(0.0, 100.0, 0.5) var water_cost: float = 5.0
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
var _action: String = ""         # "hoe" / "water" while a swing is playing
var _hit_landed: bool = false
var _grass_layer: TileMapLayer
var _soil_layer: TileMapLayer
var _hud: Node
var _farm: Farm
var _emote: EmoteBubble
var _just_denied: bool = false

func _ready() -> void:
	_facing = start_facing
	stamina = max_stamina
	_grass_layer = get_node_or_null(grass_layer_path) as TileMapLayer
	_soil_layer = get_node_or_null(soil_layer_path) as TileMapLayer
	_hud = get_node_or_null(hud_path)
	_farm = get_node_or_null(farm_path) as Farm
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
	if ItemDB.is_seed(item):
		return _try_plant(item, input)
	return false


## Swinging turns the character to face the input first, so you can work a tile
## to the side without having to step towards it.
func _start_action(action: String, input: Vector2) -> bool:
	if input != Vector2.ZERO:
		_facing = _facing_for(input)
	# The swing plays either way, but only a swing that does something costs.
	var cell := facing_cell() if _grass_layer != null else Vector2i.ZERO
	var hits := _can_hoe(cell) if action == "hoe" else (_farm != null and _farm.is_tilled(cell))
	if hits and not _pay(hoe_cost if action == "hoe" else water_cost):
		return false
	_action = action
	_hit_landed = false
	velocity = Vector2.ZERO
	sprite.play("%s_%s" % [action, _facing])
	return true


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


## The cell the character is standing on, offset one step along the facing.
func facing_cell() -> Vector2i:
	var here := _grass_layer.local_to_map(_grass_layer.to_local(global_position))
	return here + FACING_DIRS[_facing]

## World position of a cell's centre.
func cell_center(cell: Vector2i) -> Vector2:
	return _grass_layer.to_global(_grass_layer.map_to_local(cell))


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
	if ItemDB.is_seed(item):
		return _farm != null and _farm.is_tilled(cell) and not _farm.has_crop(cell) 				and stamina >= plant_cost
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
	_since_spent = 0.0
	return true


## Refills after a pause since the last spend. Walking does not hold it up, only
## acting does.
func _regen(delta: float) -> void:
	_since_spent += delta
	if stamina >= max_stamina or _since_spent < regen_delay:
		return
	stamina = minf(stamina + regen_rate * delta, max_stamina)


func _can_hoe(cell: Vector2i) -> bool:
	return _grass_layer != null and _grass_layer.get_cell_tile_data(cell) != null


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
	if data == null:
		_react("question")
		return                                   # already bare soil
	# Read the terrain set off the tile we are about to remove, so the re-fit
	# works for whatever terrain the layer was painted with.
	var terrain_set := data.terrain_set

	if refit_grass_edges and terrain_set >= 0:
		# Painting the cell with terrain -1 clears it *and* re-runs the solver
		# over its neighbours, so the grass closes around the hole with its own
		# edge tiles. Plain erase_cell leaves them untouched and the hole comes
		# out a hard square.
		_grass_layer.set_cells_terrain_connect([cell], terrain_set, -1, false)
	else:
		_grass_layer.erase_cell(cell)

	_stamp_tilled_soil(cell)
	tilled.emit(cell)
	_react("sweat")

## Swap the exposed ground for one of the plain soil variants, so a hoed patch
## reads as turned earth instead of whatever the terrain happened to paint.
func _stamp_tilled_soil(cell: Vector2i) -> void:
	if _soil_layer == null or tilled_soil_tiles.is_empty():
		return
	_soil_layer.set_cell(cell, tilled_soil_source, tilled_soil_tiles.pick_random(), 0)

func _on_sprite_frame_changed() -> void:
	if _hit_landed:
		return
	if _action == "hoe" and sprite.frame >= hoe_impact_frame:
		_land_hoe_hit()
	elif _action == "water" and sprite.frame >= water_impact_frame:
		_land_water()

func _on_sprite_animation_finished() -> void:
	if _action.is_empty():
		return
	# A very short swing can finish before frame_changed reports the impact.
	if not _hit_landed:
		if _action == "hoe":
			_land_hoe_hit()
		else:
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
