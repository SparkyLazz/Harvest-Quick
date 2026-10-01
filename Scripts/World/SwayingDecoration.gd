class_name SwayingDecoration
extends Decoration

## Scenery that moves: a tree turning over in the wind.
##
## The frames run left to right from the kind's region, so a swaying kind is
## an ordinary kind with a frame count. What it adds is a [Timer] rather than
## an [AnimatedSprite2D], because the frames are regions of a shared sheet and
## building a [SpriteFrames] per tree would mean one resource per tree on the
## map.
##
## Every tree is started at a frame of its own choosing. A wood where every
## trunk leans the same way at the same moment does not read as wind; it reads
## as a mistake.

## Seconds between frames.
var _interval: float = 0.16
var _first: Rect2
var _frames: int = 1
var _frame: int = 0
var _clock: Timer

## Points it at a strip of [param count] frames running right from [param
## region], played at [param fps].
func show_strip(sheet: Texture2D, region: Rect2, count: int, fps: float, rng: RandomNumberGenerator) -> void:
	_first = region
	_frames = maxi(count, 1)
	_interval = 1.0 / maxf(fps, 0.1)
	show_art(sheet, region)
	if _frames <= 1:
		return
	# Somewhere in the middle of the loop, so the wood is not in step.
	_frame = rng.randi_range(0, _frames - 1)
	_show_frame()
	_clock = Timer.new()
	_clock.wait_time = _interval
	_clock.autostart = true
	_clock.timeout.connect(_advance)
	add_child(_clock)

func _advance() -> void:
	_frame = (_frame + 1) % _frames
	_show_frame()

func _show_frame() -> void:
	if sprite == null:
		return
	sprite.region_rect = Rect2(
		_first.position + Vector2(_first.size.x * float(_frame), 0.0), _first.size)
