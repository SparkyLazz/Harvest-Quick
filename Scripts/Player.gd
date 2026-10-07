class_name Player
extends CharacterBody2D

## Top-down 4-direction character driven by the Sprout Lands premium spritesheet.
## Movement is grid-free: WASD (or the arrow keys) pick a direction, and the
## facing is kept on the last non-zero input so the idle pose stays consistent.
##
## Pressing the hoe input swings at the tile the character faces and clears it
## from the grass layer, uncovering the soil underneath.

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

@export_group("Hoeing")
## Layer the hoe clears. Defaults to a sibling named "Grass Layer".
@export var grass_layer_path: NodePath = ^"../Grass Layer"
## Frame of the swing that lands the hit. The swing is 8 frames and the dust
## puff is drawn on frame 4, so the tile clears in step with the animation.
@export_range(0, 7) var hoe_impact_frame: int = 4
## Re-fit the grass around a cleared cell so it grows a proper edge, the way a
## hole painted with the terrain tool looks. Off leaves a hard square.
@export var refit_grass_edges: bool = true

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
var _hoeing: bool = false
var _hit_landed: bool = false
var _grass_layer: TileMapLayer
var _soil_layer: TileMapLayer

func _ready() -> void:
	_facing = start_facing
	_grass_layer = get_node_or_null(grass_layer_path) as TileMapLayer
	_soil_layer = get_node_or_null(soil_layer_path) as TileMapLayer
	_apply_animation_speeds()
	sprite.frame_changed.connect(_on_sprite_frame_changed)
	sprite.animation_finished.connect(_on_sprite_animation_finished)
	_play("idle")

func _physics_process(delta: float) -> void:
	if _hoeing:
		# Stay put for the whole swing; the animation drives the rest.
		velocity = _approach(velocity, Vector2.ZERO, friction, delta)
		move_and_slide()
		return

	var input := _read_input()

	if Input.is_action_just_pressed("hoe"):
		_start_hoe(input)
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

## Swinging turns the character to face the input first, so you can hoe a tile
## to the side without having to step towards it.
func _start_hoe(input: Vector2) -> void:
	if input != Vector2.ZERO:
		_facing = _facing_for(input)
	_hoeing = true
	_hit_landed = false
	velocity = Vector2.ZERO
	sprite.play("hoe_%s" % _facing)

## The cell the character is standing on, offset one step along the facing.
func facing_cell() -> Vector2i:
	var here := _grass_layer.local_to_map(_grass_layer.to_local(global_position))
	return here + FACING_DIRS[_facing]

func _land_hoe_hit() -> void:
	_hit_landed = true
	if _grass_layer == null:
		push_warning("Player: no grass layer at '%s', nothing to hoe." % grass_layer_path)
		return
	var cell := facing_cell()
	var data := _grass_layer.get_cell_tile_data(cell)
	if data == null:
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

## Swap the exposed ground for one of the plain soil variants, so a hoed patch
## reads as turned earth instead of whatever the terrain happened to paint.
func _stamp_tilled_soil(cell: Vector2i) -> void:
	if _soil_layer == null or tilled_soil_tiles.is_empty():
		return
	_soil_layer.set_cell(cell, tilled_soil_source, tilled_soil_tiles.pick_random(), 0)

func _on_sprite_frame_changed() -> void:
	if _hoeing and not _hit_landed and sprite.frame >= hoe_impact_frame:
		_land_hoe_hit()

func _on_sprite_animation_finished() -> void:
	if not _hoeing:
		return
	# A very short swing can finish before frame_changed reports the impact.
	if not _hit_landed:
		_land_hoe_hit()
	_hoeing = false
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
