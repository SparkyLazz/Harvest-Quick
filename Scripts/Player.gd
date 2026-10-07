class_name Player
extends CharacterBody2D

## Top-down 4-direction character driven by the Sprout Lands premium spritesheet.
## Movement is grid-free: WASD (or the arrow keys) pick a direction, and the
## facing is kept on the last non-zero input so the idle pose stays consistent.

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

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _facing: String = "down"

func _ready() -> void:
	_facing = start_facing
	_apply_animation_speeds()
	_play("idle")

func _physics_process(delta: float) -> void:
	var input := _read_input()
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
	for direction in ["down", "up", "right", "left"]:
		frames.set_animation_speed("idle_%s" % direction, idle_fps)
		frames.set_animation_speed("walk_%s" % direction, walk_fps)
		frames.set_animation_speed("run_%s" % direction, run_fps)
