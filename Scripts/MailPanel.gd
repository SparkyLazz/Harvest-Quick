class_name MailPanel
extends Control

## The post, opened: the letters down the left, the one you picked on the
## right.
##
## Same shape as the storage window -- two halves on the pack's plates, one
## title row, the X in its corner -- because a window is a window. The left
## half is a list of everything that has ever come, newest first, with a dot
## beside anything unread. Picking one marks it read.
##
## Reading costs nothing and changes nothing: a letter's money was taken the
## morning it arrived (`Mail`). The window says so in red under the body, so
## the player can see where the debt came from.

signal closed

const PANEL_BOX := preload("res://Assets/UI/Panel_Plate.tres")
const INNER_BOX := preload("res://Assets/UI/Panel_Plate_Tip.tres")
const BUTTON_TEXTURE := preload("res://Assets/UI/Panel_Plate_Dark.png")
const CROSS := preload("res://Assets/UI/Cross.png")

const INK := UISkin.TEXT_COLOR
const MUTED := UISkin.MUTED_COLOR
const WARN := UISkin.SHORT_COLOR
const RULE := UISkin.RULE_COLOR

const HOVER_TINT := Color(1.12, 1.12, 1.12)
const PRESS_TINT := Color(0.88, 0.88, 0.88)

## 16:10, like the storage window, and for the same reason: a window read as a
## list wants a frame that is the same shape on every screen.
const BASE_SIZE := Vector2(304, 190)
const MAX_FILL := 0.82
const DIM_COLOR := Color(0.1, 0.06, 0.04, 0.45)
const SPLIT_GAP := 6

const TITLE := "POST"
const EMPTY_BOX := "THE BOX IS EMPTY."
const NOTHING_PICKED := "PICK A LETTER."
## The mark beside a letter that has not been read. An exclamation mark, not a
## star: at this face's size a "*" draws as a small x, which reads as "gone".
const UNREAD_MARK := "!"

var hud: HUD

var _dim: ColorRect
var _window: PanelContainer
var _close_button: TextureButton
var _list: VBoxContainer
var _from: Label
var _subject: Label
var _when: Label
var _body: VBoxContainer
var _cost: Label
## The id of the letter on the right, "" for none.
var _showing := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	get_viewport().size_changed.connect(_recenter)
	Mail.changed.connect(_on_mail_changed)


func bind(target: HUD) -> void:
	hud = target
	_build()
	refresh()
	_recenter()


func is_open() -> bool:
	return visible


## Opens the post, on the oldest unread letter if there is one -- that is the
## one the player came to read -- and otherwise on the newest.
func open() -> void:
	visible = true
	_showing = ""
	var pick := ""
	for letter in Mail.letters:
		if not letter["read"]:
			pick = letter["id"]
			break
	if pick.is_empty() and not Mail.letters.is_empty():
		pick = Mail.letters[-1]["id"]
	refresh()
	if not pick.is_empty():
		show_letter(pick)
	_recenter()


func close() -> void:
	if not visible:
		return
	if _close_button != null:
		_close_button.self_modulate = Color.WHITE
	visible = false
	closed.emit()


## Puts one letter on the right and marks it read.
func show_letter(id: String) -> void:
	for letter in Mail.letters:
		if letter["id"] != id:
			continue
		_showing = id
		_from.text = letter["from"]
		_subject.text = letter["subject"]
		_when.text = "%s %s, %s" % [Calendar.weekday(letter["day"]),
				Calendar.day_of_season(letter["day"]),
				Calendar.season(letter["day"]).to_upper()]
		_fill_body(letter["lines"])
		var debt: int = letter["debt"]
		_cost.text = "+%d ON YOUR DEBT." % debt if debt > 0 else ""
		# Marking read re-emits `changed`, which rebuilds the list below.
		Mail.mark_read(id)
		return


## Rebuilds the list and, if nothing is picked, the empty right half.
func refresh() -> void:
	if _window == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	# Newest first: the letter you have just been handed is the one you want.
	for i in range(Mail.letters.size() - 1, -1, -1):
		var letter: Dictionary = Mail.letters[i]
		_list.add_child(_entry(letter))
	if _showing.is_empty():
		_from.text = ""
		_subject.text = EMPTY_BOX if Mail.letters.is_empty() else NOTHING_PICKED
		_when.text = ""
		_cost.text = ""
		_fill_body([])


func _on_mail_changed() -> void:
	if not visible:
		return
	refresh()


## One row of the list: an unread mark, who it is from, and the day.
func _entry(letter: Dictionary) -> Button:
	var button := Button.new()
	var mark := UNREAD_MARK if not letter["read"] else " "
	button.text = "%s %s  %s %d" % [mark, letter["from"],
			Calendar.season(letter["day"]).substr(0, 2).to_upper(),
			Calendar.day_of_season(letter["day"])]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 17
	button.add_theme_font_override("font", UIFont.body())
	button.add_theme_font_size_override("font_size", UIFont.SIZE)
	var ink := INK if not letter["read"] else MUTED
	for role: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(role, ink)
	_style_button(button, letter["id"] == _showing)
	var id: String = letter["id"]
	button.pressed.connect(func() -> void: show_letter(id))
	return button


func _fill_body(lines: Array) -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for line in lines:
		_body.add_child(_label(str(line), INK, HORIZONTAL_ALIGNMENT_LEFT))


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = PanelContainer.new()
	_window.add_theme_stylebox_override("panel", PANEL_BOX)
	_window.custom_minimum_size = BASE_SIZE
	_window.size = BASE_SIZE
	add_child(_window)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_window.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label(TITLE, INK, HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	_close_button = _cross()
	head.add_child(_close_button)

	var rule := ColorRect.new()
	rule.color = RULE
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", SPLIT_GAP)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)

	# Left: the letters, scrolling, on the lighter plate.
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", INNER_BOX)
	left.custom_minimum_size.x = 112
	split.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.theme = UISkin.scroll_theme()
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.x = 112 - UISkin.SCROLLBAR_WIDTH - 16
	scroll.add_child(_list)

	# Right: the letter itself.
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", INNER_BOX)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 2)
	right.add_child(page)

	var sender := HBoxContainer.new()
	page.add_child(sender)
	_from = _label("", MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sender.add_child(_from)
	_when = _label("", MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	sender.add_child(_when)
	_subject = _label("", INK, HORIZONTAL_ALIGNMENT_LEFT)
	page.add_child(_subject)
	var under := ColorRect.new()
	under.color = RULE
	under.custom_minimum_size.y = 1
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(under)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 2)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_body)
	_cost = _label("", WARN, HORIZONTAL_ALIGNMENT_LEFT)
	page.add_child(_cost)


func _label(text: String, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align
	label.add_theme_font_override("font", UIFont.body())
	label.add_theme_font_size_override("font_size", UIFont.SIZE)
	label.add_theme_color_override("font_color", color)
	return label


## The row's plate. The letter being read wears the lighter one, so the list
## shows where you are without a separate highlight.
func _style_button(button: Button, picked: bool) -> void:
	var texture: Texture2D = INNER_BOX.texture if picked else BUTTON_TEXTURE
	var shades := {"normal": Color.WHITE, "hover": Color(1.07, 1.07, 1.07),
			"pressed": Color(0.9, 0.9, 0.9)}
	for state: String in shades:
		var style := UISkin.sliced(texture, 6, 4, 2)
		style.modulate_color = shades[state]
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _cross() -> TextureButton:
	var cross := TextureButton.new()
	cross.texture_normal = CROSS
	cross.focus_mode = Control.FOCUS_NONE
	cross.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cross.pressed.connect(close)
	cross.mouse_entered.connect(func() -> void: cross.self_modulate = HOVER_TINT)
	cross.mouse_exited.connect(func() -> void: cross.self_modulate = Color.WHITE)
	cross.button_down.connect(func() -> void: cross.self_modulate = PRESS_TINT)
	cross.button_up.connect(func() -> void: cross.self_modulate = Color.WHITE)
	return cross


func _zoom() -> int:
	var want: int = hud.ui_scale if hud != null else 2
	var room := get_viewport_rect().size * MAX_FILL
	while want > 1 and (BASE_SIZE.x * want > room.x or BASE_SIZE.y * want > room.y):
		want -= 1
	return want


func _recenter() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if _dim != null:
		_dim.position = Vector2.ZERO
		_dim.size = size
	if _window == null:
		return
	var zoom := _zoom()
	_window.scale = Vector2.ONE * zoom
	_window.size = BASE_SIZE
	_window.position = ((size - BASE_SIZE * zoom) * 0.5).round()
