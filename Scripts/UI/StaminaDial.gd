class_name StaminaDial
extends Sprite2D

## The little dial that floats by the player's shoulder and shows what they
## have left in them.
##
## The artist drew the whole gauge as thirty-seven pictures, a wedge further
## round in each, and the colour turns with it — green while there is a day's
## work left, amber in the afternoon, red at the end of it. So nothing here
## tints or stretches anything: the reading is which frame is showing, and
## every pixel on screen is the artist's.
##
## It sits next to the player rather than in a corner of the screen, because
## that is where the player is already looking. The cost of that is that it
## would be in the way all day, so it is only there when it has something to
## say: it fades in on the first swing, stays while the pool is short, and
## fades out again once the player is rested.
##
## It is interface, not scenery, so it hangs in a [CanvasLayer] of its own and
## tracks the player's place on screen from [member anchor_path] every frame.
## That is not tidiness. The world is tinted by [DayNightCycle], and at
## midnight the multiply is a dark blue — which would take the one thing this
## dial says and throw it away, because a red wedge and a green one multiplied
## by the same blue are the same blue. Out of the world canvas the colours
## stay the artist's at every hour.
##
## The shake is the drain. A swing knocks the dial, harder the more tired the
## player is, and a swing there was nothing left for knocks it hardest of all
## and flashes red — which is the only answer a refused swing gets, so it has
## to be one you cannot miss.

## The pool this is showing, or empty to find the one in the "stamina" group.
@export var stamina_path: NodePath

## What the dial hangs off, in the world. Empty finds the player.
@export var anchor_path: NodePath

## Where the dial sits relative to the anchor, in screen pixels. Up and to
## the right, clear of the head.
@export var screen_offset: Vector2 = Vector2(44.0, -76.0)

## How big the dial sits at rest. The sheet's cells are sixteen pixels and
## these are screen pixels now, so this is a whole number: a fractional one
## would resample the pixel art unevenly, which the world-space version got
## away with only because the camera's own zoom put it back on the grid.
@export var rest_scale: float = 3.0:
	set(value):
		rest_scale = value
		scale = Vector2.ONE * rest_scale

@export_group("Showing")
## Seconds to fade in or out.
@export var fade_time: float = 0.25

## Seconds the dial stays up after the pool fills again, so the last of the
## recovery is watched rather than cut away from.
@export var linger: float = 1.0

## Keep it on screen always, for a player who would rather see it.
@export var always_visible: bool = false:
	set(value):
		always_visible = value
		if is_node_ready():
			_refresh_showing()

@export_group("Sweep")
## Seconds for the wedge to travel to a new reading. The dial sweeps rather
## than cutting, so a drain is something you watch happen.
@export var sweep_time: float = 0.3

@export_group("Shake")
## How far the dial is knocked by a swing at full stamina, in pixels.
@export var shake_strength: float = 5.0

## How much harder the knock lands when the pool is empty, as a multiplier on
## [member shake_strength]. Tiredness is the thing being communicated, so the
## shake has to grow with it.
@export var tired_shake: float = 2.6

## How hard a refused swing knocks it, in pixels. Deliberately past anything
## a successful swing reaches.
@export var refused_shake: float = 18.0

## Seconds a knock takes to die away.
@export var shake_time: float = 0.3

## How quickly the dial is jostled while it shakes, in knocks per second.
## Low enough to read as a wobble rather than as noise.
@export var shake_rate: float = 34.0

## How far past its size the dial swells when knocked. 1.0 is no punch.
@export var punch: float = 1.18

## What a refused swing flashes.
@export var refused_colour: Color = Color(1.0, 0.45, 0.4)

## Frames on the sheet, full left to full right.
var _frames: int = 1

var _stamina: Stamina
var _anchor: Node2D
## The reading on screen, which trails the pool while the wedge sweeps.
var _shown: float = 1.0
var _sweep: Tween
var _fade: Tween
var _punch: Tween

## How far the dial is currently being thrown, in pixels. Decays to nothing.
var _shake: float = 0.0
## How hard the knock being decayed started out, so every knock takes
## [member shake_time] to die away whatever its size.
var _shake_from: float = 0.0
## Where in the jostle we are, so the knocks land at [member shake_rate]
## rather than once per frame — a new offset every frame is a blur, not a
## shake.
var _shake_phase: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

## Seconds left before the dial fades out. Negative means it is not counting.
var _linger_left: float = -1.0
## Whether the dial is meant to be on screen. Kept apart from the alpha
## because the alpha spends a quarter of a second disagreeing with it.
var _wanted: bool = false

func _ready() -> void:
	_frames = maxi(hframes * vframes, 1)
	modulate.a = 0.0
	scale = Vector2.ONE * rest_scale
	_bind()
	_anchor = (get_node_or_null(anchor_path) if not anchor_path.is_empty()
		else get_tree().get_first_node_in_group("player")) as Node2D
	_follow()
	if _stamina != null:
		_shown = _stamina.fraction()
	_show_reading(_shown)
	_refresh_showing()

func _process(delta: float) -> void:
	_tick_shake(delta)
	_follow()
	if _linger_left >= 0.0:
		_linger_left -= delta
		if _linger_left < 0.0:
			_linger_left = -1.0
			_want(false)

## Knocks the dial by [param strength] pixels.
func knock(strength: float) -> void:
	_shake = maxf(_shake, strength)
	_shake_from = maxf(_shake_from, _shake)
	# Thrown on the frame it lands, rather than waiting for the jostle to
	# come round and pick a direction. A knock whose first frames sit still
	# is a knock that arrives late, which is the whole of what it had to do.
	_shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	_shake_phase = 0.0
	if punch > 1.0:
		if _punch != null:
			_punch.kill()
		scale = Vector2.ONE * rest_scale * punch
		_punch = create_tween()
		(_punch.tween_property(self, "scale", Vector2.ONE * rest_scale, shake_time)
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

func _bind() -> void:
	if stamina_path.is_empty():
		_stamina = get_tree().get_first_node_in_group("stamina") as Stamina
	else:
		_stamina = get_node_or_null(stamina_path) as Stamina
	if _stamina == null:
		return
	_stamina.changed.connect(_on_changed)
	_stamina.spent.connect(_on_spent)
	_stamina.refused.connect(_on_refused)

func _on_changed(fraction: float) -> void:
	_sweep_to(fraction)
	_refresh_showing()

func _on_spent(_action: StringName, _cost: float) -> void:
	# Knocked harder the emptier the pool, so the dial itself reports how
	# much is left even while the wedge is still travelling.
	var tired := 1.0 - (_stamina.fraction() if _stamina != null else 1.0)
	knock(lerpf(shake_strength, shake_strength * tired_shake, tired))

func _on_refused(_action: StringName) -> void:
	knock(refused_shake)
	_flash(refused_colour)
	# A refusal must be seen, whatever the dial was doing a moment ago.
	_show_now()

## Sends the wedge to [param fraction], travelling rather than cutting.
func _sweep_to(fraction: float) -> void:
	if _sweep != null:
		_sweep.kill()
	if sweep_time <= 0.0:
		_show_reading(fraction)
		return
	_sweep = create_tween()
	_sweep.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_sweep.tween_method(_show_reading, _shown, fraction, sweep_time)

## Puts the frame for [param fraction] on screen.
func _show_reading(fraction: float) -> void:
	_shown = fraction
	frame = clampi(roundi(fraction * float(_frames - 1)), 0, _frames - 1)

## Decides whether the dial should be on screen at all, and starts the fade
## that gets it there.
##
## One place answers this, because the three things that could show it — a
## swing, a recovery finishing, the linger running out — would otherwise
## each have their own idea of when to hide it again and the dial would
## flicker between them.
func _refresh_showing() -> void:
	if always_visible:
		_linger_left = -1.0
		_want(true)
		return
	var full := _stamina == null or _stamina.fraction() >= 1.0
	if not full:
		_linger_left = -1.0
		_want(true)
		return
	# Full. If it was never up there is nothing to take down, and if the
	# goodbye is already counting it is not started again.
	if not _wanted or _linger_left >= 0.0:
		return
	_linger_left = linger

## Asks for the dial to be on screen or away, and fades it there.
func _want(shown: bool) -> void:
	_wanted = shown
	_fade_to(1.0 if shown else 0.0)

## Brings it up at once, however full the pool is.
func _show_now() -> void:
	_linger_left = linger
	_want(true)

func _fade_to(alpha: float) -> void:
	if is_equal_approx(modulate.a, alpha):
		return
	if _fade != null:
		_fade.kill()
	if fade_time <= 0.0:
		modulate.a = alpha
		return
	_fade = create_tween()
	_fade.set_trans(Tween.TRANS_SINE)
	_fade.tween_property(self, "modulate:a", alpha, fade_time)

## Tints the dial and lets it bleed back to its own colours.
func _flash(colour: Color) -> void:
	var alpha := modulate.a
	modulate = Color(colour.r, colour.g, colour.b, alpha)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	# Only the colour is tweened back; the alpha belongs to the fade, which
	# may well be running at the same time.
	tween.tween_method(_set_tint, colour, Color.WHITE, shake_time * 1.6)

func _set_tint(colour: Color) -> void:
	modulate = Color(colour.r, colour.g, colour.b, modulate.a)

## Puts the dial back beside the anchor, wherever the camera has since put
## that, and adds whatever is left of the last knock.
##
## The anchor is in the world canvas and the dial is not, so neither one's
## coordinates mean anything to the other. The player's point is carried out
## through the camera into the viewport, and then back in through this
## layer's own transform — which is what keeps the dial on the shoulder
## through the camera's smoothing and through a resize under it.
##
## Both steps are canvas transforms, deliberately. The viewport transform
## would have been the obvious reach, but it carries the window's stretch as
## well, and the anchor's side of this does not — so the two would disagree
## by whatever the window had been scaled to and the dial would sit a
## screenful away.
func _follow() -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		return
	var screen := _anchor.get_global_transform_with_canvas().origin
	var here := get_canvas_transform().affine_inverse() * (screen + screen_offset)
	global_position = here + _shake_offset * _shake

## Lets the last knock die away.
##
## The throw itself is added in [method _follow] rather than written to the
## position here, because the position is recomputed from the anchor every
## frame: a knock written straight to it would be wiped the same frame it
## landed.
func _tick_shake(delta: float) -> void:
	if _shake <= 0.01:
		if _shake_offset != Vector2.ZERO:
			_shake_offset = Vector2.ZERO
		_shake = 0.0
		_shake_from = 0.0
		return
	_shake_phase += delta * shake_rate
	if _shake_phase >= 1.0:
		_shake_phase = fmod(_shake_phase, 1.0)
		_shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	# Linear decay over shake_time, so the knock is spent when it says it is
	# rather than trailing off forever the way an exponential would.
	_shake = maxf(_shake - delta * (_shake_from / maxf(shake_time, 0.01)), 0.0)
