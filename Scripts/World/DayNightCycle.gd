class_name DayNightCycle
extends CanvasModulate

## Looping day/night cycle that tints the whole 2D canvas.
##
## One full day (midnight to midnight) takes [member day_duration] real
## seconds. Other systems can read [member time_of_day] / [method get_hour]
## or connect to the signals below instead of tracking time themselves.
## The node adds itself to the "day_night" group, so it can be reached with
## get_tree().get_first_node_in_group("day_night").

## Emitted when the in-game hour ticks over, with the new hour (0-23).
signal hour_passed(hour: int)
## Emitted at midnight, with the new day number.
signal day_passed(day: int)
## Emitted when the clock crosses [member sunrise_hour].
signal became_day
## Emitted when the clock crosses [member sunset_hour].
signal became_night

## Real seconds for one in-game day. 600 = 10 minutes.
@export var day_duration: float = 600.0
## In-game hour the cycle starts on.
@export_range(0.0, 24.0, 0.1) var start_hour: float = 7.0
## Colour ramp sampled with [member time_of_day]. Left empty, the built-in
## sunrise/sunset ramp is used.
@export var sky_gradient: Gradient
## Stops the clock without pausing the rest of the game.
@export var paused: bool = false

@export_group("Transitions")
## Hour [signal became_day] fires on.
@export_range(0.0, 24.0, 0.1) var sunrise_hour: float = 6.0
## Hour [signal became_night] fires on.
@export_range(0.0, 24.0, 0.1) var sunset_hour: float = 20.0

## Position in the day: 0 = midnight, 0.25 = 06:00, 0.5 = noon, 0.75 = 18:00.
var time_of_day: float = 0.0
## Days elapsed, starting at 1.
var day: int = 1

var _last_hour: int = -1
var _was_night: bool = false

func _ready() -> void:
	add_to_group("day_night")
	set_time(start_hour)

func _process(delta: float) -> void:
	if paused or day_duration <= 0.0:
		return

	time_of_day += delta / day_duration
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		day_passed.emit(day)

	_apply_tint()
	_emit_transitions()

## Jumps the clock to [param hour] (0-24) without emitting transition signals.
func set_time(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0) / 24.0
	_last_hour = get_hour()
	_was_night = is_night()
	_apply_tint()

func get_hour() -> int:
	return int(time_of_day * 24.0) % 24

func get_minute() -> int:
	return int(time_of_day * 1440.0) % 60

func is_night() -> bool:
	var hour := time_of_day * 24.0
	return hour < sunrise_hour or hour >= sunset_hour

## 24-hour clock reading, e.g. "07:30".
func get_time_string() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]

## Builds the fallback ramp on first use so the tint also works when the
## cycle is driven before _ready(), or when the gradient is cleared.
func _apply_tint() -> void:
	if sky_gradient == null:
		sky_gradient = _build_default_gradient()
	color = sky_gradient.sample(time_of_day)

func _emit_transitions() -> void:
	var hour := get_hour()
	if hour != _last_hour:
		_last_hour = hour
		hour_passed.emit(hour)

	var night := is_night()
	if night != _was_night:
		_was_night = night
		if night:
			became_night.emit()
		else:
			became_day.emit()

## Ramp from midnight blue through sunrise, daylight, sunset and back.
## The first and last colours match so the cycle loops seamlessly.
func _build_default_gradient() -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([
		0.00, 0.21, 0.25, 0.32, 0.40, 0.62, 0.72, 0.79, 0.86, 1.00,
	])
	ramp.colors = PackedColorArray([
		Color(0.19, 0.22, 0.40), # 00:00 night
		Color(0.21, 0.24, 0.43), # 05:00 first light
		Color(0.78, 0.55, 0.52), # 06:00 sunrise
		Color(1.00, 0.94, 0.88), # 07:40 morning
		Color(1.00, 1.00, 1.00), # 09:36 full daylight
		Color(1.00, 1.00, 1.00), # 14:53 full daylight
		Color(1.00, 0.85, 0.68), # 17:17 golden hour
		Color(0.85, 0.50, 0.42), # 18:58 sunset
		Color(0.33, 0.30, 0.52), # 20:38 dusk
		Color(0.19, 0.22, 0.40), # 24:00 night
	])
	return ramp
