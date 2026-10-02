class_name TwoPagePanel
extends Control

## The open book the farm's interfaces are read out of: a shelf on the left, the
## one thing picked off it on the right.
##
## There are two of these now — the store and the paper — and there will be more.
## Everything they share is here, which is nearly all of it: the frame, the two
## pages, the scrollbar, the header, the buttons in its corner, and the handful
## of layout rules that took a while to get right and should not have to be got
## right again. What a subclass supplies is the content of the two pages and
## nothing else.
##
## Three of those rules are worth keeping in sight, because each one was a bug
## before it was a rule:
##
## - [b]A [PanelContainer], never a [NinePatchRect].[/b] The window is as tall as
##   its contents and a NinePatchRect never takes its size from what is inside
##   it, so a frame built that way draws as a bar with the content spilling out.
## - [b]Every label is clipped.[/b] A plain [Label] reports its text as its
##   minimum width, so one long name widens the page, the page widens the window,
##   and a window that centres itself then sits somewhere else. Clipped, nothing
##   can push. The cost is that a clipped label in a row with a spacer gets no
##   width at all, so anything in a header reserves its own.
## - [b]Wrapped text has its height measured here.[/b] A wrapping label asks for
##   the height its current width implies, and inside a [VBoxContainer] it has no
##   width when asked — so it asks for one pixel and is never seen.

signal opened
signal closed

## Emitted when the corner button is pressed.
signal close_pressed

const WINDOW_REGION := Rect2(323, 162, 42, 44)
const PAGE_REGION := Rect2(227, 162, 42, 44)
const BOX_REGION := Rect2(281, 73, 30, 32)
const ICON_INSET := Vector2(4.0, 4.0)
const ICON_SIZE := Vector2(22.0, 22.0)

## The rail and grabber on the slider sheet, and the gutter kept for them.
const SCROLL_TRACK := Rect2(182, 5, 4, 38)
const SCROLL_GRAB := Rect2(133, 5, 7, 18)
const SCROLL_WIDTH: float = 7.0

## The corner button on the icon sheet, unpressed and pressed.
const CLOSE_ICON := Rect2(128, 0, 32, 32)
const CLOSE_DOWN := Rect2(160, 0, 32, 32)

## The one size every label in these windows is set at. Nine, because it is the
## only size the rest of the game's interface uses, and a seven-pixel font asked
## for eight comes back with uneven stems.
const TEXT_SIZE: int = 9

const INK := Color(0.33, 0.24, 0.19)
const INK_SOFT := Color(0.42, 0.32, 0.26)
const INK_BAD := Color(0.70, 0.26, 0.24)
const INK_GOOD := Color(0.29, 0.45, 0.25)

## Widths reserved in the header, so its labels render without being able to
## widen the window when the purse grows a digit.
const HEAD_NAME_W: float = 96.0
const HEAD_DATE_W: float = 118.0
const HEAD_PURSE_W: float = 54.0

@export_group("Look")
@export var sheet: Texture2D
@export var buttons: Texture2D
@export var sliders: Texture2D
@export var font: Font
@export var title: String = ""
@export var list_width: float = 184.0
@export var detail_width: float = 172.0
@export var list_height: float = 160.0

@export_group("Motion")
## How a window arrives and leaves.
##
## It is a short one on purpose. These windows are opened and shut dozens of
## times in a run — the store every morning, the paper whenever a price looks
## odd — and an animation that is a pleasure the first time is a toll the
## fortieth. Long enough to say the window came from somewhere, over before
## anyone is waiting on it.
@export var open_time: float = 0.17
@export var shut_time: float = 0.11
## How small it starts, as a fraction of its size. The overshoot on the way in
## is [constant Tween.TRANS_BACK] doing the work, not a second tween.
@export_range(0.5, 1.0, 0.01) var open_from: float = 0.92
## How long the right-hand page takes to fade when the selection changes.
@export var page_turn: float = 0.13

@export_group("Behaviour")
## The action that opens and shuts it.
@export var toggle_action: StringName = &""
## How big the corner button is drawn. The sheet's cells are 32 with a few
## pixels of air around the glyph, so at sixteen the X was a speck on a window
## four hundred wide and easy to miss twice before hitting it.
@export var corner_button_size: float = 26.0

## The other window of the pair.
##
## There was a button in the corner for going between them, and it is gone: the
## column under the weather panel has one for each window, so a second way in
## was a second thing to explain. What this is still for is that only one of the
## two may be open — they share the middle of the screen — so whichever is being
## opened shuts this one on the way in.
@export var sibling: NodePath

## Whether the window is meant to be up. Kept apart from
## [member CanvasItem.visible] because the shutting animation needs the node to
## go on drawing after the player has asked for it to go away — everything that
## asks "is this window open" wants the intent, not the drawing.
var _shown: bool = false
var _base_scale: Vector2 = Vector2.ONE
var _motion: Tween
var _page_fade: Tween

var _frame: PanelContainer
var _extra: VBoxContainer
var _list: VBoxContainer
var _detail: VBoxContainer
var _purse: Label
var _season: Label
var _empty: Label

func _ready() -> void:
	_base_scale = scale
	_build()
	visible = false
	get_viewport().size_changed.connect(_centre)
	close_pressed.connect(close)
	Wallet.changed.connect(func(_c: int) -> void:
		if _shown:
			refresh())

func _unhandled_input(event: InputEvent) -> void:
	if toggle_action != &"" and InputMap.has_action(toggle_action) \
			and event.is_action_pressed(toggle_action):
		toggle()
		get_viewport().set_input_as_handled()
	elif _shown and event.is_action_pressed(&"inventory"):
		close()
		get_viewport().set_input_as_handled()

## Whether the window is up, or on its way there.
func is_open() -> bool:
	return _shown

func open() -> void:
	if _shown:
		return
	_shown = true
	rebuild()
	visible = true
	_centre.call_deferred()
	_play_open.call_deferred()
	opened.emit()

func close() -> void:
	if not _shown:
		return
	_shown = false
	_play_shut()
	closed.emit()

func toggle() -> void:
	if _shown:
		close()
	else:
		open()

## Comes in small and slightly over its own size, which is the whole of it.
func _play_open() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	pivot_offset = _frame.size * 0.5
	modulate.a = 0.0
	scale = _base_scale * open_from
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(self, "modulate:a", 1.0, open_time * 0.7)
	_motion.tween_property(self, "scale", _base_scale, open_time) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Goes out faster than it came in, and only stops drawing at the end of it.
##
## The hiding hangs off a timer rather than off the tween. Chaining a callback
## onto a tween that is set parallel runs it alongside the properties instead of
## after them, and its [signal Tween.finished] did not arrive either — both
## attempts left a window that was flagged shut and still being drawn. A timer
## for the same length is a thing that can be read and trusted.
func _play_shut() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	pivot_offset = _frame.size * 0.5
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(self, "modulate:a", 0.0, shut_time)
	_motion.tween_property(self, "scale", _base_scale * open_from, shut_time) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(shut_time).timeout
	# Checked rather than assumed: the window may have been opened again while
	# it was still going out, and hiding it then would leave a window that is
	# meant to be up and is not drawn.
	if not _shown and is_inside_tree():
		visible = false
		scale = _base_scale
		modulate.a = 1.0

## Fades the right-hand page, for when the player has picked something else to
## read. Called by subclasses from the click, not from every refresh — a page
## that flickered each time a price moved would be a twitch, not a turn.
func turn_page() -> void:
	if _page_fade != null and _page_fade.is_valid():
		_page_fade.kill()
	_detail.modulate.a = 0.0
	_page_fade = create_tween()
	_page_fade.tween_property(_detail, "modulate:a", 1.0, page_turn)

## A row that has just been picked, nudged once so the click is felt.
func pop_row(row: Control) -> void:
	if row == null:
		return
	row.pivot_offset = row.size * 0.5
	var pop := create_tween()
	pop.tween_property(row, "scale", Vector2(1.03, 1.03), 0.07) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(row, "scale", Vector2.ONE, 0.10) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## Which day the window is being read on. Taken from the run, falling back to
## the market so a panel poked without a run still reads correctly.
func _today() -> int:
	if _today_override > 0:
		return _today_override
	var run := get_tree().get_first_node_in_group("run")
	return run.day if run != null else Market.day()

## Forces [method _today] to a given day, for a probe that needs to see what a
## window says in a season two months off. 0 is off.
var _today_override: int = 0

# --- what subclasses fill in -------------------------------------------------

## Throw the left page away and build it again. Subclasses override.
func rebuild() -> void:
	pass

## Redraw without rebuilding. Subclasses override.
func refresh() -> void:
	pass

# --- the window --------------------------------------------------------------

func _build() -> void:
	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", _style(WINDOW_REGION))
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_frame)

	var pad := _margins(7, 7, 6, 8)
	_frame.add_child(pad)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	pad.add_child(body)

	body.add_child(_head())

	_extra = VBoxContainer.new()
	_extra.add_theme_constant_override("separation", 3)
	body.add_child(_extra)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 5)
	body.add_child(split)
	split.add_child(_left_page())
	split.add_child(_right_page())

func _head() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	var name_label := _text(title, HORIZONTAL_ALIGNMENT_LEFT, INK)
	name_label.custom_minimum_size = Vector2(HEAD_NAME_W, 0.0)
	head.add_child(name_label)
	head.add_child(_stretch())
	_season = _text("", HORIZONTAL_ALIGNMENT_RIGHT, INK_SOFT)
	_season.custom_minimum_size = Vector2(HEAD_DATE_W, 0.0)
	head.add_child(_season)
	_purse = _text("", HORIZONTAL_ALIGNMENT_RIGHT, INK)
	_purse.custom_minimum_size = Vector2(HEAD_PURSE_W, 0.0)
	head.add_child(_purse)
	head.add_child(_corner_button(CLOSE_ICON, CLOSE_DOWN, "Close",
		func() -> void: close_pressed.emit()))
	return head

## The little button in the window's top corner.
##
## The pressed frame goes on as the button goes down and comes off as it comes
## up, and the press only counts on the way up — so a click dragged off the
## button still looks like it was let go, and does not fire.
func _corner_button(up: Rect2, down: Rect2, tip: String, hit: Callable) -> Control:
	var button := TextureRect.new()
	button.texture = _atlas(up, buttons)
	button.custom_minimum_size = Vector2(corner_button_size, corner_button_size)
	button.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	button.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = tip
	button.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or click.button_index != MOUSE_BUTTON_LEFT:
			return
		button.texture = _atlas(down if click.pressed else up, buttons)
		if not click.pressed:
			hit.call())
	return button

func _left_page() -> Control:
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", _style(PAGE_REGION))
	var pad := _margins(5, 5, 5, 6)
	page.add_child(pad)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(list_width, list_height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Always shown, never only when needed: a bar that appeared on the fourth
	# entry would shift every row left on the day a fourth was added.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_dress_scrollbar(scroll.get_v_scroll_bar())
	pad.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_empty = _text("", HORIZONTAL_ALIGNMENT_CENTER, INK_SOFT)
	_empty.clip_text = false
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Given the page's full height. It shares a MarginContainer with the scroll,
	# which hands a child its minimum size, and a wrapped label's minimum height
	# comes back as one pixel.
	_empty.custom_minimum_size = Vector2(list_width, list_height)
	_empty.visible = false
	pad.add_child(_empty)
	return page

func _right_page() -> Control:
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", _style(PAGE_REGION))
	var pad := _margins(6, 6, 6, 7)
	page.add_child(pad)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 3)
	_detail.custom_minimum_size = Vector2(detail_width, list_height)
	pad.add_child(_detail)
	return page

## Puts the window in the middle of the screen.
##
## In script rather than with anchors because the window has no authored size,
## and deferred because a container cannot say how big it is until it has been
## laid out once.
func _centre() -> void:
	if _frame == null:
		return
	var box: Vector2 = _frame.size
	if box == Vector2.ZERO:
		box = _frame.get_combined_minimum_size()
	# The pivot is the catch. A control scaled about a pivot draws at
	# position + pivot * (1 - scale), so with the pivot at the middle and a
	# scale of two the window drew half its own size up and to the left of
	# wherever it was put. Solving that for the position that lands the frame's
	# centre on the screen's cancels the scale out entirely, and what is left is
	# the unscaled size — which looks wrong and is right.
	pivot_offset = box * 0.5
	position = ((get_viewport_rect().size - box) * 0.5).floor()

## Keeps the header's date and purse current. Subclasses call this from refresh.
func _head_refresh() -> void:
	var day := _today()
	_purse.text = "%d g" % Wallet.coins
	_season.text = "%s  day %d of %d   " % [
		Season.label(day), Season.day_of(day), Season.LENGTH]

# --- the pieces --------------------------------------------------------------

func _dress_scrollbar(bar: VScrollBar) -> void:
	if bar == null or sliders == null:
		return
	bar.custom_minimum_size = Vector2(SCROLL_WIDTH, 0.0)
	var rail := StyleBoxTexture.new()
	rail.texture = _atlas(SCROLL_TRACK, sliders)
	rail.texture_margin_top = 2
	rail.texture_margin_bottom = 2
	var grab := StyleBoxTexture.new()
	grab.texture = _atlas(SCROLL_GRAB, sliders)
	grab.texture_margin_top = 6
	grab.texture_margin_bottom = 6
	for slot in ["scroll", "scroll_focus"]:
		bar.add_theme_stylebox_override(slot, rail)
	for slot in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(slot, grab)

## A row's backing: nothing at all, or a warm wash for the one being read.
func _row_style(picked: bool) -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.76, 0.62, 0.42, 0.55) if picked else Color(0, 0, 0, 0)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 2
	# Clear of the scrollbar, which is drawn over the content's right edge
	# rather than beside it.
	style.content_margin_right = SCROLL_WIDTH + 4.0
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style

func _style(region: Rect2) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _atlas(region, sheet)
	style.texture_margin_left = 4
	style.texture_margin_top = 4
	style.texture_margin_right = 4
	style.texture_margin_bottom = 6
	return style

func _atlas(region: Rect2, from: Texture2D) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = from
	atlas.region = region
	atlas.filter_clip = true
	return atlas

func _margins(left: int, right: int, top: int, bottom: int) -> MarginContainer:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", left)
	pad.add_theme_constant_override("margin_right", right)
	pad.add_theme_constant_override("margin_top", top)
	pad.add_theme_constant_override("margin_bottom", bottom)
	return pad

func _stretch() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

## A label that cannot widen whatever it is put in. See the note at the top.
func _text(body: String, align: int, colour: Color) -> Label:
	var label := Label.new()
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.text = body
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", TEXT_SIZE)
	label.add_theme_color_override("font_color", colour)
	return label

## A label that wraps, with its height worked out in advance. See the note.
func _wrapped(body: String, colour: Color, width: float = -1.0) -> Label:
	var across := detail_width if width <= 0.0 else width
	var label := _text(body, HORIZONTAL_ALIGNMENT_LEFT, colour)
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tall := float(TEXT_SIZE)
	if font != null:
		tall = font.get_multiline_string_size(
			body, HORIZONTAL_ALIGNMENT_LEFT, across, TEXT_SIZE).y
	label.custom_minimum_size = Vector2(across, ceilf(tall) + 2.0)
	return label

## A name on the left and a figure on the right, with no spacer between them —
## both are clipped, so a spacer set to expand would take the row and leave them
## nothing.
func _line(name: String, value: String, value_width: float = 82.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var left := _text(name, HORIZONTAL_ALIGNMENT_LEFT, INK_SOFT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right := _text(value, HORIZONTAL_ALIGNMENT_RIGHT, INK)
	right.custom_minimum_size = Vector2(value_width, 0.0)
	row.add_child(right)
	return row
