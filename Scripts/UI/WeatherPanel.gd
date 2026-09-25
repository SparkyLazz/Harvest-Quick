class_name WeatherPanel
extends CanvasLayer

## Weather dial HUD: a weather icon on the left, a day/night disc on the
## right and a thermometer below, all behind a wooden frame, with an arrow
## that swings up, level or down depending on the time of day.
##
## The arrow is never rotated at runtime. [member swing_textures] holds the
## hand-drawn swing from the weather sheet, ordered from fully up (index 0)
## to fully down (the last index), so the pixels stay crisp. A phase change
## walks the arrow through the in-between frames one [member step_duration]
## at a time instead of snapping straight to the new direction.
##
## Each frame has its tail in a slightly different corner, so every frame
## carries a matching offset in [member swing_offsets] that keeps the tail
## seated in the frame's pivot knob.
##
## The panel finds the cycle through the "day_night" group and follows its
## [signal DayNightCycle.phase_changed], so it needs no wiring in the editor.

@export_group("Arrow")
## Arrow directions, from fully up to fully down.
@export var swing_textures: Array[Texture2D] = []
## Panel-space position for each entry in [member swing_textures].
@export var swing_offsets: PackedVector2Array = PackedVector2Array()
## Seconds the arrow spends on each frame while swinging. 0 snaps instantly.
@export var step_duration: float = 0.07

@export_group("Thermometer")
## Mercury levels, from coldest (index 0) to hottest.
##
## The thermometer is four layers: an unfilled-glass backing, the mercury
## rung, the panel frame, and a housing sprite on top. The housing comes
## from the same sheet as the mercury, so its glass is exactly as wide as
## the column; the older thermometer baked into the frame is a pixel wider
## and would leave a see-through sliver beside a filled tube.
@export var mercury_textures: Array[Texture2D] = []
## Panel-space position for each entry in [member mercury_textures]. The
## rungs are different heights, so each carries the offset that lands its
## bulb in the frame's.
@export var mercury_offsets: PackedVector2Array = PackedVector2Array()
## Seconds the mercury spends on each rung while rising or falling.
@export var mercury_step_duration: float = 0.09
## Mercury level while the cycle is in morning.
@export var morning_level: int = 4
## Mercury level while the cycle is in the noon half of the day.
@export var noon_level: int = 7
## Mercury level while the cycle is in night.
@export var night_level: int = 1

@export_group("Weather icon")
## Left-window icon while the cycle is in morning.
@export var morning_icon: Texture2D
## Left-window icon while the cycle is in the noon half of the day.
@export var noon_icon: Texture2D
## Left-window icon while the cycle is in night.
@export var night_icon: Texture2D
## Seconds an icon takes to roll up through the window. 0 swaps instantly.
@export var icon_slide_duration: float = 0.28
## Rolls the starting icon in rather than having it already in place.
@export var animate_on_start: bool = true

@onready var _arrow: Sprite2D = $Panel/Arrow
@onready var _mercury: Sprite2D = $Panel/Mercury
@onready var _icon_window: Control = $Panel/IconWindow
@onready var _icon: Sprite2D = $Panel/IconWindow/Icon
@onready var _outgoing_icon: Sprite2D = $Panel/IconWindow/OutgoingIcon

var _cycle: DayNightCycle
var _step: int = 0
var _target_step: int = 0
var _elapsed: float = 0.0
var _mercury_step: int = 0
var _mercury_target: int = 0
var _mercury_elapsed: float = 0.0
var _icon_tween: Tween

func _ready() -> void:
	set_process(false)
	_outgoing_icon.texture = null

	_cycle = get_tree().get_first_node_in_group("day_night") as DayNightCycle
	if _cycle == null:
		push_warning("WeatherPanel: no DayNightCycle in the \"day_night\" group; the dial will not move.")
		show_weather(noon_icon, animate_on_start)
		snap_mercury(noon_level)
		return

	_cycle.phase_changed.connect(_on_phase_changed)

	# The dial starts already pointing at the right phase rather than
	# swinging into place on the first frame of the game. The icon still
	# rolls in, so the panel arrives with a bit of life.
	var phase := _cycle.get_phase()
	_step = step_for_phase(phase)
	_target_step = _step
	_show_step(_step)
	snap_mercury(level_for_phase(phase))
	show_weather(icon_for_phase(phase), animate_on_start)

## Swings the arrow and rolls in the matching icon, so both halves of the
## panel move together on a phase change.
func _on_phase_changed(phase: DayNightCycle.Phase) -> void:
	swing_to(phase)
	warm_to(level_for_phase(phase))
	show_weather(icon_for_phase(phase))

func _process(delta: float) -> void:
	var arrow_busy := _advance_arrow(delta)
	var mercury_busy := _advance_mercury(delta)
	if not arrow_busy and not mercury_busy:
		set_process(false)

func _advance_arrow(delta: float) -> bool:
	if _step == _target_step:
		return false

	_elapsed += delta
	while _step != _target_step and _elapsed >= step_duration:
		_elapsed -= step_duration
		_step += signi(_target_step - _step)
		_show_step(_step)
	return _step != _target_step

func _advance_mercury(delta: float) -> bool:
	if _mercury_step == _mercury_target:
		return false

	_mercury_elapsed += delta
	while _mercury_step != _mercury_target and _mercury_elapsed >= mercury_step_duration:
		_mercury_elapsed -= mercury_step_duration
		_mercury_step += signi(_mercury_target - _mercury_step)
		_show_mercury(_mercury_step)
	return _mercury_step != _mercury_target

# --- Arrow -------------------------------------------------------------

## Starts the arrow swinging towards [param phase]. Public so the dial can
## also be driven by hand, e.g. from a cutscene or a debug menu.
func swing_to(phase: DayNightCycle.Phase) -> void:
	_target_step = step_for_phase(phase)
	if step_duration <= 0.0:
		_step = _target_step
		_show_step(_step)
		return

	_elapsed = 0.0
	set_process(_step != _target_step)

## Where [param phase] sits in [member swing_textures]: morning fully up,
## night fully down, noon halfway between.
func step_for_phase(phase: DayNightCycle.Phase) -> int:
	var last := maxi(swing_textures.size() - 1, 0)
	match phase:
		DayNightCycle.Phase.MORNING:
			return 0
		DayNightCycle.Phase.NIGHT:
			return last
		_:
			return last / 2

func _show_step(step: int) -> void:
	if step >= 0 and step < swing_textures.size():
		_arrow.texture = swing_textures[step]
	if step >= 0 and step < swing_offsets.size():
		_arrow.position = swing_offsets[step]

# --- Thermometer -------------------------------------------------------

## Starts the mercury climbing or dropping towards [param level], one rung
## at a time, so it reads as the column moving rather than jumping.
func warm_to(level: int) -> void:
	_mercury_target = _clamp_level(level)
	if mercury_step_duration <= 0.0:
		snap_mercury(_mercury_target)
		return

	_mercury_elapsed = 0.0
	if _mercury_step != _mercury_target:
		set_process(true)

## The mercury level that stands for [param phase]: coolest at night,
## warmest through the noon half of the day.
func level_for_phase(phase: DayNightCycle.Phase) -> int:
	match phase:
		DayNightCycle.Phase.MORNING:
			return morning_level
		DayNightCycle.Phase.NIGHT:
			return night_level
		_:
			return noon_level

## Puts the mercury at [param level] with no travel, for the first frame of
## the game or when the animation is switched off.
func snap_mercury(level: int) -> void:
	_mercury_step = _clamp_level(level)
	_mercury_target = _mercury_step
	_show_mercury(_mercury_step)

func _show_mercury(level: int) -> void:
	if level >= 0 and level < mercury_textures.size():
		_mercury.texture = mercury_textures[level]
	if level >= 0 and level < mercury_offsets.size():
		_mercury.position = mercury_offsets[level]

func _clamp_level(level: int) -> int:
	return clampi(level, 0, maxi(mercury_textures.size() - 1, 0))

# --- Weather icon ------------------------------------------------------

## The icon that stands for [param phase]. Each one is the clear-sky icon
## from its own palette on the sheet: mint for morning, amber for noon and
## a blue moon for night.
func icon_for_phase(phase: DayNightCycle.Phase) -> Texture2D:
	match phase:
		DayNightCycle.Phase.MORNING:
			return morning_icon
		DayNightCycle.Phase.NIGHT:
			return night_icon
		_:
			return noon_icon

## Rolls [param texture] up into the left window, carrying the icon that was
## there out through the top. The window clips both, so the icons only ever
## show inside the frame.
func show_weather(texture: Texture2D, animate: bool = true) -> void:
	if texture == _icon.texture:
		return

	var travel := _icon_window.size.y
	if not animate or icon_slide_duration <= 0.0:
		_icon.texture = texture
		_icon.position = Vector2.ZERO
		_outgoing_icon.texture = null
		return

	_outgoing_icon.texture = _icon.texture
	_outgoing_icon.position = Vector2.ZERO
	_icon.texture = texture
	_icon.position = Vector2(0.0, travel)

	if _icon_tween != null and _icon_tween.is_running():
		_icon_tween.kill()
	_icon_tween = create_tween().set_parallel()
	_icon_tween.tween_method(_slide.bind(_icon), travel, 0.0, icon_slide_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_icon_tween.tween_method(_slide.bind(_outgoing_icon), 0.0, -travel, icon_slide_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Icons are whole-pixel art, so the slide lands on whole pixels too rather
## than smearing across a fraction of one.
func _slide(offset: float, sprite: Sprite2D) -> void:
	sprite.position.y = roundf(offset)
