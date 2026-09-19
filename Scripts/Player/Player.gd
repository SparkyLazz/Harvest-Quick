class_name Player
extends CharacterBody2D

## Top-down player controller driven by "Premium Charakter Spritesheet.png".
##
## The sheet is 8 columns x 24 rows of 48x48 frames, grouped in blocks of four
## rows (down, up, right, left):
##   rows  0-3   idle      rows  4-7   walk     rows  8-11  run
##   rows 12-15  axe       rows 16-19  hoe      rows 20-23  watering can
## Those 24 clips live in PlayerFrames.tres as "<state>_<direction>".

enum Tool { HOE, AXE, WATERING_CAN }

## Animation prefix for each tool, matching the clip names in PlayerFrames.tres.
const TOOL_ANIMATIONS := {
	Tool.HOE: "hoe",
	Tool.AXE: "axe",
	Tool.WATERING_CAN: "water",
}

@export_group("Movement")
@export var walk_speed: float = 45.0
@export var run_speed: float = 80.0
## How fast the body reaches its target speed / comes back to a stop, in px/s².
@export var acceleration: float = 600.0
@export var friction: float = 900.0

## The grid aiming helper. Left unset, the player still swings but nothing in
## the world changes -- handy for testing the animations on their own.
@export var tile_cursor_path: NodePath = ^"../TileCursor"

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _cursor: TileCursor = get_node_or_null(tile_cursor_path) as TileCursor

## One of "down", "up", "right", "left" -- the direction half of the clip name.
var facing: String = "down"
var current_tool: Tool = Tool.HOE

## True while a tool animation is playing. Tool clips are one-shot, so this
## locks out movement and re-triggering until animation_finished fires.
var _using_tool: bool = false
## The tile this swing was aimed at, held until the swing lands.
var _target_cell: Vector2i = Vector2i.MAX


func _ready() -> void:
	_sprite.animation_finished.connect(_on_animation_finished)
	_sprite.play("idle_down")


func _physics_process(delta: float) -> void:
	_poll_tool_selection()

	if _using_tool:
		# Rooted in place for the swing; just bleed off any leftover momentum.
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input != Vector2.ZERO:
		facing = _facing_from(input)

	if Input.is_action_just_pressed("use_tool"):
		_start_tool()
		move_and_slide()
		return

	if input != Vector2.ZERO:
		var running := Input.is_action_pressed("run")
		var speed := run_speed if running else walk_speed
		velocity = velocity.move_toward(input * speed, acceleration * delta)
		_play("run" if running else "walk")
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		_play("idle")

	move_and_slide()


## Number keys pick the tool the next swing will use.
func _poll_tool_selection() -> void:
	if Input.is_action_just_pressed("tool_hoe"):
		current_tool = Tool.HOE
	elif Input.is_action_just_pressed("tool_axe"):
		current_tool = Tool.AXE
	elif Input.is_action_just_pressed("tool_watering_can"):
		current_tool = Tool.WATERING_CAN


func _start_tool() -> void:
	_using_tool = true
	velocity = Vector2.ZERO
	# Swings happen whether or not the target is workable -- refusing to animate
	# reads as an unresponsive button. It simply has no effect on landing.
	_target_cell = _cursor.target if _cursor != null else Vector2i.MAX
	if _target_cell != Vector2i.MAX:
		facing = _facing_toward(_target_cell)
	_sprite.play("%s_%s" % [TOOL_ANIMATIONS[current_tool], facing])


## Turns to face the tile being worked, so the swing lands where the player aims
## rather than wherever they last walked.
func _facing_toward(cell: Vector2i) -> String:
	var here := _cursor.get_parent().cell_at(global_position) as Vector2i
	var delta := cell - here
	if delta == Vector2i.ZERO:
		return facing
	return _facing_from(Vector2(delta))


## The sheet has no diagonals, so the dominant axis wins.
func _facing_from(input: Vector2) -> String:
	if absf(input.x) > absf(input.y):
		return "right" if input.x > 0.0 else "left"
	return "down" if input.y > 0.0 else "up"


func _play(state: String) -> void:
	var animation := "%s_%s" % [state, facing]
	if _sprite.animation != animation:
		_sprite.play(animation)


## Only the one-shot tool clips emit this; the movement clips loop forever.
func _on_animation_finished() -> void:
	if not _using_tool:
		return
	_using_tool = false
	if _cursor != null and _target_cell != Vector2i.MAX:
		_cursor.apply(_target_cell)
	_target_cell = Vector2i.MAX
	_play("idle")
