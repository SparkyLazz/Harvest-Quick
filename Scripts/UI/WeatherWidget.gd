@tool
class_name WeatherWidget
extends Control

## The farm's weather panel: a weather icon, a day/night dial, a
## thermometer and a date plate.
##
## The casing is the finished panel the artist drew into Weather_UI.png,
## with all four utilities already welded together. It is drawn last, on
## top of everything, so its cut-outs become the windows the moving parts
## show through. It arrives in two pieces only because a loose sprite on
## the sheet overlaps the lower right of its rectangle; the seam at y=60
## falls in empty space and is invisible. Nothing here positions the panel
## and nothing builds a node: the layout is
## [code]WeatherWidget.tscn[/code], and this script only fills the holes.
##
## Three things move. The needle leans to wherever the sun is, reading
## against the day/night wheel behind it — up at noon, down at midnight.
## The icon never cuts: its backing and its symbol cross-dissolve, and the
## symbol breathes on a slow bob. The mercury climbs through the artist's
## own nine states rather than jumping, so a warming day is something you
## can watch happen.
##
## Left alone it finds the [DayNightCycle] in the "day_night" group and
## follows it.

## What the icon window is showing.
enum Weather {
	CLEAR,
	PARTLY_CLOUDY,
	CLOUDY,
	OVERCAST,
	WINDY,
	RAIN,
	STORM,
	SNOW,
	RAINBOW, ## Morning only — noon and night fall back to [constant Weather.CLEAR].
}

## Time of day the icon is tinted for. Mirrors [enum DayNightCycle.Phase]
## value for value, so the cycle's phase can be handed straight over.
enum Phase { MORNING, NOON, NIGHT }

## Icon sheet geometry. Cells are 48x48 holding 34x34 of art, and the
## sheet is banded: composed icons on rows 0-2, the bare symbol three rows
## below that, its backing tile three rows below again. The panel uses the
## bottom two bands so the symbol can move without dragging its
## background along with it.
const CELL: int = 48
const CELL_INSET: int = 7
const ICON_SIZE: int = 34
const GLYPH_BAND: int = 3
const BACK_BAND: int = 6

## Sheet cell per weather, in [enum Phase] order. The three palettes are
## column groups — mint 0-3, amber 4-6, dusk 7-9 — so a change of phase is
## a change of column.
const ICON_CELL: Dictionary = {
	Weather.CLEAR: [Vector2i(0, 0), Vector2i(6, 0), Vector2i(8, 0)],
	Weather.PARTLY_CLOUDY: [Vector2i(2, 0), Vector2i(4, 0), Vector2i(7, 0)],
	Weather.CLOUDY: [Vector2i(0, 1), Vector2i(4, 1), Vector2i(7, 1)],
	Weather.OVERCAST: [Vector2i(1, 1), Vector2i(5, 1), Vector2i(8, 1)],
	Weather.WINDY: [Vector2i(2, 1), Vector2i(6, 1), Vector2i(9, 1)],
	Weather.RAIN: [Vector2i(2, 2), Vector2i(5, 2), Vector2i(8, 2)],
	Weather.STORM: [Vector2i(3, 2), Vector2i(5, 2), Vector2i(9, 2)],
	Weather.SNOW: [Vector2i(3, 1), Vector2i(4, 2), Vector2i(7, 2)],
	Weather.RAINBOW: [Vector2i(0, 2), Vector2i(6, 0), Vector2i(8, 0)],
}

## Needle frames, highest first. Five leans cover the day: straight up is
## noon, level is dawn and dusk, straight down is midnight.
const NEEDLE_REGION: Array[Rect2] = [
	Rect2(338, 1, 13, 13),
	Rect2(337, 18, 15, 12),
	Rect2(336, 34, 16, 12),
	Rect2(337, 50, 15, 12),
	Rect2(338, 66, 13, 13),
]
## Where each frame hangs so they all pivot on the same nub, the one cast
## into the casing at the left edge of the dial.
const NEEDLE_POS: Array[Vector2] = [
	Vector2(51, 16),
	Vector2(51, 17),
	Vector2(51, 19),
	Vector2(51, 22),
	Vector2(51, 24),
]

## The mercury's nine drawn states, coldest first. They share a bottom
## edge and differ in height, so the reading is which sprite is showing —
## not a scale, and not a tinted rectangle. The casing's tick marks sit in
## front of them, because the casing is drawn last.
const MERCURY_REGION: Array[Rect2] = [
	Rect2(108, 125, 8, 8),
	Rect2(76, 125, 8, 8),
	Rect2(44, 121, 8, 12),
	Rect2(12, 119, 8, 14),
	Rect2(140, 68, 8, 17),
	Rect2(108, 62, 8, 23),
	Rect2(76, 57, 8, 28),
	Rect2(44, 57, 8, 28),
	Rect2(12, 57, 8, 28),
]
## Left edge and floor of the glass, taken from the casing's own cut-out.
const MERCURY_X: float = 6.0
const MERCURY_FLOOR: float = 86.0

## Season names for the date plate, four to a year.
const SEASONS: Array[String] = ["SPR", "SUM", "AUT", "WIN"]
## Days in one season.
const SEASON_LENGTH: int = 28

@export var weather: Weather = Weather.CLEAR:
	set(value):
		if weather == value:
			return
		weather = value
		_refresh_icon(true)

@export var phase: Phase = Phase.MORNING:
	set(value):
		if phase == value:
			return
		phase = value
		_refresh_icon(true)

@export_group("Dial")
## Position in the day: 0 is midnight, 0.5 is noon. The needle reads this
## against the wheel behind it.
@export_range(0.0, 1.0, 0.001) var time_of_day: float = 0.3:
	set(value):
		time_of_day = value
		_refresh_needle()

@export_group("Thermometer")
## Reading the mercury shows, in the same units as the two bounds below.
@export var temperature: float = 18.0:
	set(value):
		temperature = value
		_refresh_mercury()
## Temperature at which the glass is empty.
@export var coldest: float = -10.0:
	set(value):
		coldest = value
		_refresh_mercury()
## Temperature at which the glass is full.
@export var hottest: float = 38.0:
	set(value):
		hottest = value
		_refresh_mercury()

@export_group("Motion")
## Seconds for the icon to dissolve into a new one.
@export var icon_fade: float = 0.35
## Seconds for the mercury to climb or fall to a new reading. It passes
## through every state in between rather than cutting.
@export var mercury_slide: float = 0.7
## Seconds for the needle to swing to a new lean.
@export var needle_swing: float = 0.45
## Seconds for one breath of the icon's idle bob. Zero holds it still.
@export var bob_period: float = 2.4

@export_group("Date")
## What the plate reads. Overwritten every midnight while
## [member follow_day_night] is on.
@export var date_text: String = "SPR.01":
	set(value):
		date_text = value
		_refresh_date()

@export_group("Binding")
## Take the phase, the clock and the date from the [DayNightCycle] in the
## "day_night" group.
@export var follow_day_night: bool = true

@onready var _back: TextureRect = $IconWindow/Back
@onready var _back_prev: TextureRect = $IconWindow/BackPrev
@onready var _bob: Control = $IconWindow/Bob
@onready var _glyph: TextureRect = $IconWindow/Bob/Glyph
@onready var _glyph_prev: TextureRect = $IconWindow/Bob/GlyphPrev
@onready var _needle: TextureRect = $Needle
@onready var _mercury: TextureRect = $Thermometer/Mercury
@onready var _mercury_next: TextureRect = $Thermometer/MercuryNext
@onready var _date: Label = $Date

var _cycle: Node
var _needle_index: int = -1
var _shown_level: float = -1.0
var _icon_tween: Tween
var _mercury_tween: Tween
var _needle_tween: Tween
var _bob_tween: Tween

func _ready() -> void:
	_refresh_icon(false)
	_refresh_needle()
	_show_mercury(mercury_reading())
	_refresh_date()
	_restart_bob()
	if Engine.is_editor_hint() or not follow_day_night:
		set_process(false)
		return
	_bind_day_night()

func _process(_delta: float) -> void:
	# The needle is the one part that wants the clock every frame; the
	# phase and the date arrive on their own signals.
	if _cycle != null:
		time_of_day = _cycle.time_of_day

## Shows the day on the plate as a season and a number, e.g. "SUM.14".
func set_date(day: int) -> void:
	var index := maxi(day, 1) - 1
	var season: String = SEASONS[(index / SEASON_LENGTH) % SEASONS.size()]
	date_text = "%s.%02d" % [season, index % SEASON_LENGTH + 1]

## Where [member temperature] falls among the nine mercury states, as a
## fraction — 3.5 means halfway between the fourth state and the fifth.
##
## Kept fractional because nine states over the whole range is a step of
## several degrees, and a reading that only ever lands on one of nine
## heights cannot show a mild morning differing from a warm one. What the
## fraction is *for* is [method _show_mercury], which dissolves one state
## into the next.
func mercury_reading() -> float:
	var last := MERCURY_REGION.size() - 1
	if is_equal_approx(hottest, coldest):
		return 0.0
	var t := clampf(inverse_lerp(coldest, hottest, temperature), 0.0, 1.0)
	return t * last

## Which of the nine drawn states is nearest the current reading.
func mercury_level() -> int:
	return clampi(roundi(mercury_reading()), 0, MERCURY_REGION.size() - 1)

## Which needle frame [member time_of_day] calls for. Noon puts the sun
## overhead and the needle with it; midnight drops both.
func needle_index() -> int:
	var elevation := -cos(TAU * time_of_day)
	var steps := NEEDLE_REGION.size() - 1
	return clampi(roundi((1.0 - elevation) * 0.5 * steps), 0, steps)

func _bind_day_night() -> void:
	_cycle = get_tree().get_first_node_in_group("day_night")
	if _cycle == null:
		set_process(false)
		return
	_cycle.phase_changed.connect(_on_phase_changed)
	_cycle.day_passed.connect(set_date)
	_on_phase_changed(_cycle.get_phase())
	set_date(_cycle.day)
	time_of_day = _cycle.time_of_day

func _on_phase_changed(new_phase: int) -> void:
	phase = new_phase as Phase

func _cell_region(cell: Vector2i, band: int) -> Rect2:
	return Rect2(
		cell.x * CELL + CELL_INSET,
		(cell.y + band) * CELL + CELL_INSET,
		ICON_SIZE,
		ICON_SIZE,
	)

func _refresh_icon(animate: bool) -> void:
	if not is_node_ready():
		return
	var cell: Vector2i = ICON_CELL[weather][phase]
	var back_atlas := _back.texture as AtlasTexture
	var glyph_atlas := _glyph.texture as AtlasTexture
	var back_region := _cell_region(cell, BACK_BAND)
	var glyph_region := _cell_region(cell, GLYPH_BAND)
	if back_atlas.region == back_region and glyph_atlas.region == glyph_region:
		return

	if not animate or Engine.is_editor_hint() or icon_fade <= 0.0:
		back_atlas.region = back_region
		glyph_atlas.region = glyph_region
		_back.modulate.a = 1.0
		_glyph.modulate.a = 1.0
		_back_prev.modulate.a = 0.0
		_glyph_prev.modulate.a = 0.0
		return

	# Hand the outgoing pair to the ghost layers, then dissolve across.
	(_back_prev.texture as AtlasTexture).region = back_atlas.region
	(_glyph_prev.texture as AtlasTexture).region = glyph_atlas.region
	back_atlas.region = back_region
	glyph_atlas.region = glyph_region

	_back_prev.modulate.a = 1.0
	_glyph_prev.modulate.a = 1.0
	_back.modulate.a = 0.0
	_glyph.modulate.a = 0.0
	_glyph.position.y = 3.0
	_glyph_prev.position.y = 0.0

	if _icon_tween != null:
		_icon_tween.kill()
	_icon_tween = create_tween()
	_icon_tween.set_parallel(true)
	_icon_tween.set_trans(Tween.TRANS_SINE)
	_icon_tween.tween_property(_back, "modulate:a", 1.0, icon_fade)
	_icon_tween.tween_property(_back_prev, "modulate:a", 0.0, icon_fade)
	_icon_tween.tween_property(_glyph, "modulate:a", 1.0, icon_fade)
	_icon_tween.tween_property(_glyph, "position:y", 0.0, icon_fade)
	_icon_tween.tween_property(_glyph_prev, "modulate:a", 0.0, icon_fade)
	_icon_tween.tween_property(_glyph_prev, "position:y", -3.0, icon_fade)

func _refresh_needle() -> void:
	if not is_node_ready():
		return
	var index := needle_index()
	if index == _needle_index:
		return
	_needle_index = index

	var region: Rect2 = NEEDLE_REGION[index]
	(_needle.texture as AtlasTexture).region = region
	_needle.size = region.size

	var target: Vector2 = NEEDLE_POS[index]
	if Engine.is_editor_hint() or needle_swing <= 0.0:
		_needle.position = target
		return
	if _needle_tween != null:
		_needle_tween.kill()
	_needle_tween = create_tween()
	_needle_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_needle_tween.tween_property(_needle, "position", target, needle_swing)

func _refresh_mercury() -> void:
	if not is_node_ready():
		return
	var target := mercury_reading()
	if is_equal_approx(target, _shown_level):
		return
	if Engine.is_editor_hint() or mercury_slide <= 0.0:
		_show_mercury(target)
		return
	# Walk the states rather than cutting to the new one, so the column is
	# seen to climb or drain.
	if _mercury_tween != null:
		_mercury_tween.kill()
	_mercury_tween = create_tween()
	_mercury_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_mercury_tween.tween_method(_show_mercury, _shown_level, target, mercury_slide)

## Shows a reading of [param level], dissolving the state below it into the
## state above.
##
## The artist drew nine columns and no more, and they differ in colour as
## well as height — a cold one is blue and short, a hot one red and full —
## so an in-between reading cannot be had by stretching one of them. Showing
## both and fading between is the one way to get a continuous column out of
## nine pictures while every pixel on screen is still the artist's.
##
## The warmer state is the one that fades in, and it is drawn second so its
## extra height arrives over the cooler column rather than under it.
func _show_mercury(level: float) -> void:
	_shown_level = level
	var last := MERCURY_REGION.size() - 1
	var lower := clampi(floori(level), 0, last)
	var upper := mini(lower + 1, last)
	_place_mercury(_mercury, MERCURY_REGION[lower])
	_mercury.modulate.a = 1.0
	if _mercury_next == null:
		return
	_place_mercury(_mercury_next, MERCURY_REGION[upper])
	# Nothing to blend into at the top of the scale, and nothing to blend
	# from when the reading sits exactly on a state.
	_mercury_next.modulate.a = 0.0 if upper == lower else clampf(level - float(lower), 0.0, 1.0)

## Stands [param rect] on the floor of the glass. The columns share a bottom
## edge and differ in height, so the top is what moves.
func _place_mercury(node: TextureRect, region: Rect2) -> void:
	(node.texture as AtlasTexture).region = region
	node.position = Vector2(MERCURY_X, MERCURY_FLOOR - region.size.y)
	node.size = region.size

func _restart_bob() -> void:
	if _bob_tween != null:
		_bob_tween.kill()
	_bob.position.y = 0.0
	if Engine.is_editor_hint() or bob_period <= 0.0:
		return
	_bob_tween = create_tween().set_loops()
	_bob_tween.set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(_bob, "position:y", -1.0, bob_period * 0.5)
	_bob_tween.tween_property(_bob, "position:y", 0.0, bob_period * 0.5)

func _refresh_date() -> void:
	if not is_node_ready():
		return
	_date.text = date_text
