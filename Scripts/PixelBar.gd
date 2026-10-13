class_name PixelBar
extends Control

## A filled bar cut from the UI pack's own progress-bar art: a trough with a
## cream outline, and a rounded green fill that slides inside it.
##
## Both pieces are nine-sliced, so the bar is whatever width it is given and the
## fill keeps its rounded caps at any value. Three things keep the art honest at
## sizes it was never drawn for:
##
##   The fill is clipped, not squashed. A stretched sprite would pull its end cap
##   out of shape, and at low values the cap would be wider than the bar itself.
##
##   The fill is drawn at the height its green actually occupies and dropped into
##   the trough's hollow, rather than being scaled to the whole control. Scaled,
##   its one-pixel top highlight and two-pixel shadow smear across each other.
##
##   Both pieces tile their middles instead of stretching them, so a bar four
##   times the sprite's width is four copies of the pattern rather than one
##   pulled thin. The caps are the only part that never repeats.
##
## The art is green. `fill_color` recolours it by multiplying, so the shading
## ramp baked into the sprite survives the change; the factor is worked out
## against the sprite's own mid green, which is why a colour brighter than that
## green comes out right instead of washing flat.

const TROUGH := preload("res://Assets/UI/Bar_Trough.png")
const FILL := preload("res://Assets/UI/Bar_Fill.png")

## The mid tone of the fill sprite, the colour every tint is measured against.
const FILL_BASE := Color8(164, 194, 99)

## Height of the trough in source pixels; the art is drawn for exactly this.
const BAR_HEIGHT := 14
## The trough's hollow, measured off its own sprite: the cream outline takes two
## pixels on each side and three top and bottom.
const INSET_X := 2
const INSET_Y := 3
## Nine-slice margin along the bar. The rounded caps are well inside 4px on both
## sprites, and the middles tile from there.
const PATCH := 4
## The fill's own margins. Its highlight is the top row and its shadow the bottom
## two, so only the rows between those may be repeated. The right margin is wider
## than the cap needs: the artist put a glint six pixels in, and a margin short of
## it would leave that one bright pixel inside the tiled middle, repeating down
## the bar as a dotted line. Held in the cap, it reads as a shine on the end of a
## full bar, which is where it was drawn to be.
const FILL_PATCH_RIGHT := 7
const FILL_PATCH_TOP := 1
const FILL_PATCH_BOTTOM := 2

## Where the bar stands, in whatever unit `max_value` is counted in.
@export var value: float = 1.0: set = set_value
## The full end of the bar. Values are clamped into 0..max_value.
@export var max_value: float = 1.0: set = set_max_value
## Multiplied over the sprite's green. Leave at the base green for no change.
@export var fill_color: Color = FILL_BASE: set = set_fill_color
## Seconds the fill takes to catch up with a new value. 0 snaps.
@export_range(0.0, 1.0, 0.01) var slide_time: float = 0.18

var _trough: NinePatchRect
var _clip: Control
var _fill: NinePatchRect
## Where the fill is drawn, which trails `value` while it slides. -1 until the
## first layout, which is what makes the very first draw snap rather than wind
## up from empty.
var _shown: float = -1.0

func _init() -> void:
	custom_minimum_size.y = BAR_HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_trough = _patch(TROUGH, PATCH, PATCH, PATCH)
	_trough.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_trough)

	# The fill lives inside a clipping Control: the fill keeps its full width
	# and the clip shortens, so the right-hand cap is cut off mid-bar instead of
	# being scaled down to nothing.
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.position = Vector2(INSET_X, INSET_Y)
	add_child(_clip)

	_fill = _patch(FILL, FILL_PATCH_RIGHT, FILL_PATCH_TOP, FILL_PATCH_BOTTOM)
	_clip.add_child(_fill)
	# A declared default never runs its own setter, so the tint is applied here.
	set_fill_color(fill_color)


func _ready() -> void:
	resized.connect(_layout)
	set_process(false)
	_layout()


## The slide runs here rather than on a tween: these bars track values that move
## every frame, like stamina, and a tween rebuilt that often costs more than the
## lerp it would replace.
func _process(delta: float) -> void:
	var target := _ratio()
	if slide_time <= 0.0:
		_shown = target
	else:
		_shown = lerpf(_shown, target, clampf(delta * 3.0 / slide_time, 0.0, 1.0))
		# Snap the last sliver, so a bar that is logically full is drawn full.
		if absf(target - _shown) < 0.002:
			_shown = target
	_layout()
	if is_equal_approx(_shown, target):
		set_process(false)


## Jumps straight to a value with no slide. For the first fill of a panel, where
## watching every bar wind up from empty would read as a loading screen.
func set_instantly(new_value: float, new_max: float = -1.0) -> void:
	if new_max > 0.0:
		max_value = new_max
	value = new_value
	_shown = _ratio()
	set_process(false)
	_layout()


func set_value(v: float) -> void:
	value = v
	_start_slide()


func set_max_value(v: float) -> void:
	max_value = maxf(v, 0.0001)
	_start_slide()


func set_fill_color(c: Color) -> void:
	fill_color = c
	if _fill:
		# Component-wise, so a tint brighter than the sprite's own green lifts
		# it rather than clipping it.
		_fill.modulate = Color(
				c.r / FILL_BASE.r, c.g / FILL_BASE.g, c.b / FILL_BASE.b, c.a)


func _ratio() -> float:
	return clampf(value / max_value, 0.0, 1.0)


func _start_slide() -> void:
	if not is_inside_tree():
		return
	if _shown < 0.0 or slide_time <= 0.0:
		_shown = _ratio()
		_layout()
		return
	if not is_equal_approx(_shown, _ratio()):
		set_process(true)


func _layout() -> void:
	if _clip == null:
		return
	if _shown < 0.0:
		_shown = _ratio()
	var inner := maxf(size.x - INSET_X * 2.0, 0.0)
	_fill.size = Vector2(inner, maxf(size.y - INSET_Y * 2.0, 0.0))
	var shown_width := roundf(inner * _shown)
	_clip.size = Vector2(shown_width, _fill.size.y)
	# A fill narrower than its two caps has nothing left to draw and renders as
	# a sliver of cap; hide it instead so an empty bar looks empty.
	_clip.visible = shown_width >= PATCH


func _patch(texture: Texture2D, right: int, top: int, bottom: int) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = texture
	n.patch_margin_left = PATCH
	n.patch_margin_right = right
	n.patch_margin_top = top
	n.patch_margin_bottom = bottom
	# Repeat the middle rather than pulling it. The pattern then stays at the
	# size it was drawn, however long the bar gets.
	n.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	n.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return n
