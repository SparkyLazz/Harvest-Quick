extends CharacterBody2D

## Top-down 8-way movement for the Premium Charakter spritesheet.
## Animations live in Assets/Characters/PlayerFrames.tres and are named
## "<state>_<facing>", e.g. "walk_left" or "run_down".
##
## The same naming carries the tool swings: the item in hand names an action
## — hoe, axe or water — and the swing is that action and the facing, so
## "hoe_left" is the hoe swung west. Nothing here knows what a hoe is for;
## it plays the swing, holds the player still until it lands, and says so
## through [signal tool_used] for whoever is listening.

## Emitted when a swing lands, with the action swung and the spot in front
## of the player it was aimed at. Nothing consumes it yet — the crops and
## trees it is meant for do not exist — but the swing already knows both,
## so it is worth saying out loud rather than working out again later.
signal tool_used(action: StringName, at: Vector2)

## Emitted when something is set down, with the item it came out of and the
## tile it landed on.
signal thing_placed(item: PlaceableData, at: Vector2i)

## Emitted when something is taken back up, with the item it turned back
## into and the tile it left.
signal thing_recovered(item: PlaceableData, at: Vector2i)

@export var walk_speed: float = 55.0
@export var run_speed: float = 100.0
@export var acceleration: float = 800.0
@export var friction: float = 1000.0

@export_group("Tools")
## Input action that swings whatever is in hand.
@export var use_action: StringName = &"use"
## How far in front of the player a swing reaches, in pixels. One tile.
@export var reach: float = 16.0
## Which frame of the eight the swing lands on, counting from zero. The
## artist draws the strike fifth, with the white arc.
@export var impact_frame: int = 4

@export_group("Placing")
## Input action that opens, or otherwise pokes, whatever is being faced.
## Separate from [member use_action] because the two ask opposite questions
## — one puts a thing down, the other reaches for one already there — and
## sharing a key would make which of them happened depend on what the tile
## in front already held.
@export var interact_action: StringName = &"interact"

## The tool that takes placed things back up, named as an [member
## ItemData.action] rather than an input action — it is a swing like any
## other, and which swing it is depends on what is in hand.
##
## This is not a convenience. A crop plot may be built on, so the only thing
## standing between a misplaced chest and a plot lost for the rest of the
## game is being able to lift the chest off again.
@export var recover_action: StringName = &"axe"

## Where each facing points, for working out what a swing is aimed at.
const FACING_STEP := {
	"down": Vector2.DOWN,
	"up": Vector2.UP,
	"left": Vector2.LEFT,
	"right": Vector2.RIGHT,
}

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var water: AnimatedSprite2D = $Water
@onready var ghost: PlacementGhost = $PlacementGhost

var facing: String = "down"

## The layer placed things live in. Looked up once and kept, because the
## ghost asks for it every frame and the answer only changes when the whole
## farm does.
var _world_cache: WorldObjects

## The action being swung, or empty when the player is free to move. Movement
## is read every frame either way, so this is the only thing keeping a swing
## from being walked out of.
var _swinging: StringName = &""
## Whether [signal tool_used] has already gone out for this swing.
var _landed: bool = false

func _ready() -> void:
	# Findable by the things that react to a swing without the player having
	# to know they exist.
	add_to_group("player")
	sprite.animation_finished.connect(_on_swing_finished)
	water.animation_finished.connect(water.hide)
	water.hide()

func _unhandled_input(event: InputEvent) -> void:
	# Through _unhandled_input rather than polled, so a click that the
	# inventory window has already answered is not also a swing at the dirt.
	#
	# Interact is offered the press first. It only answers when something is
	# actually standing there, so nothing is taken away from use by asking.
	if _pressed(event, interact_action) and _try_interact():
		get_viewport().set_input_as_handled()
		return
	if _pressed(event, use_action) and _try_use():
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if _swinging != &"":
		# Planted for the length of the swing, but still slowed by friction
		# so a run does not stop dead on the first frame.
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		_check_impact()
		_update_ghost()
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var is_running := Input.is_action_pressed("run")
	var target_speed := run_speed if is_running else walk_speed

	if direction != Vector2.ZERO:
		velocity = velocity.move_toward(direction * target_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	_update_animation(direction, is_running)
	_update_ghost()

## Whether a swing is under way.
func is_swinging() -> bool:
	return _swinging != &""

## The spot a swing from here would land on.
func aim_point() -> Vector2:
	return global_position + (FACING_STEP[facing] as Vector2) * reach

## The tile a swing or a placement from here would land on.
func aim_tile() -> Vector2i:
	var world := _world()
	return world.tile_at(aim_point()) if world != null else Vector2i.ZERO

## Answers a press of [member use_action] with whatever the item in hand is
## for: a placeable is set down, a tool is swung, and anything else is only
## carried. Returns whether the press was spent.
func _try_use() -> bool:
	var item: ItemData = Inventory.selected_item()
	if item is PlaceableData:
		return _try_place(item as PlaceableData)
	return _try_swing()

## Sets [param placeable] down on the tile in front and spends one from the
## slot it came out of. Returns whether anything was placed — a press aimed
## at the farm plot, at water, or at ground already taken is simply nothing
## happening, not an error.
func _try_place(placeable: PlaceableData) -> bool:
	if _swinging != &"":
		return false
	var world := _world()
	if world == null:
		return false
	var tile := world.tile_at(aim_point())
	if world.place(placeable, tile) == null:
		return false
	Inventory.take(Inventory.selected, 1)
	thing_placed.emit(placeable, tile)
	return true

## Pokes whatever stands on the tile in front. Returns whether anything
## answered, so a press at empty ground falls through to whatever else wants
## the key rather than being swallowed.
func _try_interact() -> bool:
	if _swinging != &"":
		return false
	var world := _world()
	if world == null:
		return false
	var thing := world.at(world.tile_at(aim_point()))
	if thing == null or not thing.has_method("interact"):
		return false
	return thing.interact()

## Puts the square of light on the tile the held thing would land on, and
## takes it away when there is nothing in hand to land.
func _update_ghost() -> void:
	if ghost == null:
		return
	var placeable := Inventory.selected_item() as PlaceableData
	var world := _world()
	if placeable == null or world == null:
		ghost.hide_ghost()
		return
	var tile := world.tile_at(aim_point())
	var cell := world.tile_size()
	ghost.show_at(
		world.tile_centre(tile) - cell * 0.5,
		cell * Vector2(placeable.footprint),
		world.can_place(placeable, tile))

## Whether [param event] is [param action] being pressed. Tolerates an
## action the project has not bound, so the player still works in a scene
## that wires up only some of them.
func _pressed(event: InputEvent, action: StringName) -> bool:
	if action == &"" or not InputMap.has_action(action):
		return false
	return event.is_action_pressed(action)

## The layer placed things live in, or null in a scene without one.
func _world() -> WorldObjects:
	if _world_cache == null or not is_instance_valid(_world_cache):
		_world_cache = get_tree().get_first_node_in_group("world_objects") as WorldObjects
	return _world_cache

## Starts a swing if something swingable is in hand. Returns whether one
## started, so the caller knows whether the press was spent.
func _try_swing() -> bool:
	if _swinging != &"":
		return false
	var item: ItemData = Inventory.selected_item()
	if item == null or not item.is_tool():
		return false
	if not sprite.sprite_frames.has_animation("%s_%s" % [item.action, facing]):
		return false
	_swinging = item.action
	_landed = false
	velocity = Vector2.ZERO
	sprite.play("%s_%s" % [_swinging, facing])
	if _swinging == &"water":
		# The spray is its own sheet, drawn over the pose it belongs to. It
		# runs a frame longer than the swing and hides itself at the end.
		water.show()
		water.play(facing)
	return true

## Calls the swing landed once the strike frame is on screen.
func _check_impact() -> void:
	if _landed or sprite.frame < impact_frame:
		return
	_land_swing()

## Says the swing landed, and lets it take something back up on the way.
##
## Both the strike frame and the end of a short animation arrive here, so
## there is one place that decides what landing means and no chance of the
## two drifting apart.
func _land_swing() -> void:
	_landed = true
	tool_used.emit(_swinging, aim_point())
	if _try_water(_swinging):
		return
	_try_recover(_swinging)

## Wets whatever is growing where the swing landed. Returns whether anything
## drank it, so a can emptied over bare ground is not mistaken for a watered
## crop.
func _try_water(action: StringName) -> bool:
	if action != &"water":
		return false
	var world := _world()
	if world == null:
		return false
	var thing := world.at(world.tile_at(aim_point()))
	if thing == null or not thing.has_method("water"):
		return false
	return thing.water()

## Takes back whatever the swing landed on, when the tool swung is the one
## that lifts things and the thing agrees to be lifted. Returns whether
## anything was recovered.
func _try_recover(action: StringName) -> bool:
	if action != recover_action or recover_action == &"":
		return false
	var world := _world()
	if world == null:
		return false
	var tile := world.tile_at(aim_point())
	var thing := world.at(tile)
	if thing == null or not thing.has_method("recover"):
		return false
	var item: PlaceableData = thing.recover()
	if item == null:
		return false
	# Only let go of it once there is somewhere for it to land. Lifting a
	# chest into a full satchel would drop it out of the world entirely.
	if Inventory.add(item, 1) > 0:
		return false
	var taken := world.remove(tile)
	if taken != null:
		taken.queue_free()
	thing_recovered.emit(item, tile)
	return true

func _on_swing_finished() -> void:
	if _swinging == &"":
		return
	if not _landed:
		# A swing shorter than [member impact_frame] still landed.
		_land_swing()
	_swinging = &""
	sprite.play("idle_%s" % facing)

func _update_animation(direction: Vector2, is_running: bool) -> void:
	if direction != Vector2.ZERO:
		# Horizontal input wins ties so diagonals keep a readable side pose.
		if absf(direction.x) >= absf(direction.y):
			facing = "right" if direction.x > 0.0 else "left"
		else:
			facing = "down" if direction.y > 0.0 else "up"

	var state := "idle"
	if velocity.length() > 5.0:
		state = "run" if is_running else "walk"

	sprite.play("%s_%s" % [state, facing])
