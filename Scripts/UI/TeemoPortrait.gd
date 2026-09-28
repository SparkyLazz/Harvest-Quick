class_name TeemoPortrait
extends Control

## The framed portrait on the profile panel: Teemo inside a wooden frame,
## idling until you tap her.
##
## The frame is the 80x80 [code]backdrops_big1[/code] block drawn as a
## [NinePatchRect]. Its corner knobs are 31 pixels across and everything
## between them repeats, so the frame can be grown to whatever the panel
## has room for and only its opening gets bigger. [member frame_size] is
## that grown size; the portrait inside is centred in the opening, which
## widens pixel for pixel with the frame.
##
## The emote sheet is 32x32 cells, thirteen to a row, and each row is one
## beat of an animation rather than a whole emote: a row to get into the
## pose, a row or two of loop, a row to come out of it again. [constant
## ANIMATIONS] stitches those rows back into the three animations the
## portrait actually plays, so the table reads as "happy is rows 6 to 9"
## instead of as a list of ninety frames.
##
## Only [code]idle[/code] loops. The other two are one-shots that hand
## back to idle when they end, which is what makes a tap feel like a
## reaction rather than a mode.

## Emitted when the player taps the portrait, before the reaction plays.
signal tapped()

const SHEET: Texture2D = preload("res://Assets/UI/Emotes/Teemo premium emote animations sprite sheet-export.png")
const FRAME_TEXTURE: Texture2D = preload("res://Assets/UI/Frame/backdrops_big1.png")
const CELL: int = 32
const SHEET_COLUMNS: int = 13
## Size of the frame's corner artwork, and so its nine-patch margin.
const FRAME_MARGIN: int = 31
## How far below the middle of its cell Teemo's art actually sits. She is
## drawn standing on the cell floor, so centring the cell leaves her low
## in the opening by this much; measured across every frame the portrait
## plays, they all agree on one pixel.
const CELL_DROP: int = 1
## Opening in the frame at the texture's own size. Growing the frame by a
## pixel grows the opening by a pixel, so this is what the portrait's room
## is measured from.
const FRAME_OPENING: int = 21

## Each animation as the rows of the sheet it is stitched from, with how
## many frames of each row to take. Rows are [code](row, frames)[/code].
const ANIMATIONS: Dictionary = {
	# Pops in from nothing. Played when the menu opens.
	&"appear": [Vector2i(0, 13)],
	# Two near-identical poses a pixel apart: she breathes.
	&"idle": [Vector2i(3, 2)],
	# Squints, beams, blushes, grows a heart, bobs with it, lets it go.
	&"happy": [
		Vector2i(6, 7), Vector2i(7, 2), Vector2i(8, 2),
		Vector2i(7, 2), Vector2i(8, 2), Vector2i(9, 5),
	],
}
## Animations that run once and then hand back to [code]idle[/code].
const ONE_SHOTS: Array[StringName] = [&"appear", &"happy"]

## Frames a second, per animation. Idle is slow on purpose: at speed the
## two-frame breath reads as a twitch.
const SPEEDS: Dictionary = {
	&"appear": 14.0,
	&"idle": 1.6,
	&"happy": 11.0,
}

## Outside size of the frame. The portrait grows with it.
@export var frame_size: int = 128:
	set(value):
		frame_size = maxi(value, FRAME_MARGIN * 2)
		if is_node_ready():
			_layout()
## How much bigger than its 32x32 cell Teemo is drawn. Whole numbers only,
## or her pixels stop being square.
@export_range(1, 6) var portrait_zoom: int = 2:
	set(value):
		portrait_zoom = maxi(value, 1)
		if is_node_ready():
			_layout()

var _frame: NinePatchRect
var _sprite: AnimatedSprite2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	_frame = NinePatchRect.new()
	_frame.texture = FRAME_TEXTURE
	_frame.patch_margin_left = FRAME_MARGIN
	_frame.patch_margin_top = FRAME_MARGIN
	_frame.patch_margin_right = FRAME_MARGIN
	_frame.patch_margin_bottom = FRAME_MARGIN
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _build_frames()
	_sprite.centered = true
	_sprite.animation_finished.connect(_on_animation_finished)
	add_child(_sprite)

	_layout()
	play(&"idle")

## Starts [param anim] from its first frame. Unknown names are ignored
## rather than clearing the portrait.
func play(anim: StringName) -> void:
	if _sprite == null or not _sprite.sprite_frames.has_animation(anim):
		return
	_sprite.play(anim)

## Which animation is playing.
func current_animation() -> StringName:
	return _sprite.animation if _sprite != null else &""

## Pops her in as though she had just arrived. The menu calls this when it
## opens, so she is not simply already there.
func greet() -> void:
	play(&"appear")

## Plays the reaction. Tapping her does this; so can anything else with
## good news.
func cheer() -> void:
	play(&"happy")

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit()
		cheer()
		accept_event()

func _on_animation_finished() -> void:
	if _sprite.animation in ONE_SHOTS:
		play(&"idle")

# --- Building ----------------------------------------------------------

## Turns [constant ANIMATIONS] into [SpriteFrames], one [AtlasTexture] per
## cell of the sheet.
func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")

	for anim: StringName in ANIMATIONS:
		frames.add_animation(anim)
		frames.set_animation_speed(anim, SPEEDS.get(anim, 8.0))
		frames.set_animation_loop(anim, not anim in ONE_SHOTS)
		for run: Vector2i in ANIMATIONS[anim]:
			for column in run.y:
				frames.add_frame(anim, _cell(column, run.x))

	return frames

func _cell(column: int, row: int) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = SHEET
	texture.region = Rect2(Vector2i(column, row) * CELL, Vector2i(CELL, CELL))
	texture.filter_clip = true
	return texture

# --- Layout ------------------------------------------------------------

func _layout() -> void:
	if _frame == null:
		return

	custom_minimum_size = Vector2(frame_size, frame_size)
	size = custom_minimum_size
	_frame.size = custom_minimum_size

	var opening := FRAME_OPENING + frame_size - int(FRAME_TEXTURE.get_size().x)
	if CELL * portrait_zoom > opening:
		push_warning("TeemoPortrait: %dx zoom needs a %dpx opening but the frame has %dpx; raise frame_size."
				% [portrait_zoom, CELL * portrait_zoom, opening])

	_sprite.scale = Vector2.ONE * portrait_zoom
	# Centring the cell would leave her [constant CELL_DROP] low in the
	# opening, so the sprite is hung that much higher and her art, rather
	# than her cell, ends up in the middle of the frame.
	var middle := Vector2(frame_size, frame_size) * 0.5
	_sprite.position = middle - Vector2(0, CELL_DROP * portrait_zoom)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _frame != null:
		_frame.size = size
