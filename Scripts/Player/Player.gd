extends CharacterBody2D

## Top-down 8-way movement for the Premium Charakter spritesheet.
## Animations live in Assets/Characters/PlayerFrames.tres and are named
## "<state>_<facing>", e.g. "walk_left" or "run_down".

@export var walk_speed: float = 55.0
@export var run_speed: float = 100.0
@export var acceleration: float = 800.0
@export var friction: float = 1000.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var facing: String = "down"

func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var is_running := Input.is_action_pressed("run")
	var target_speed := run_speed if is_running else walk_speed

	if direction != Vector2.ZERO:
		velocity = velocity.move_toward(direction * target_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	_update_animation(direction, is_running)

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
