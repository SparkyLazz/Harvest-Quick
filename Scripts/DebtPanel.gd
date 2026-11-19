class_name DebtPanel
extends Control

## The bill the collector hands over: what is owed, what this week wants, how
## many strikes are against you, and the buttons to pay.
##
## The same window chrome as the storage panel -- the pack's plate, the one
## face, the X in the title row -- because it is the same game. It is smaller
## and it holds no grid, so it is authored at its own `BASE_SIZE` and scaled by
## a whole number the same way, which keeps the pixel art and the pixel font on
## their grid.
##
## The panel decides nothing. Every rule lives in `Debt`; this reads it and
## calls `Debt.pay`.

## Fires when the window goes away, so the collector could react if he ever
## learns to.
signal closed

const PANEL_BOX := preload("res://Assets/UI/Panel_Plate.tres")
const INNER_BOX := preload("res://Assets/UI/Panel_Plate_Tip.tres")
const BUTTON_TEXTURE := preload("res://Assets/UI/Panel_Plate_Dark.png")
const CROSS := preload("res://Assets/UI/Cross.png")

const INK := UISkin.TEXT_COLOR
const MUTED := UISkin.MUTED_COLOR
## The colour a number wears when it is bad news: what is still owed, and the
## strikes once any have landed.
const WARN := UISkin.SHORT_COLOR
const RULE := UISkin.RULE_COLOR

const HOVER_TINT := Color(1.12, 1.12, 1.12)
const PRESS_TINT := Color(0.88, 0.88, 0.88)

## The window in source pixels. Tall enough for the five lines and the row of
## buttons and no taller -- measured off a render, not guessed: the first try
## at 150 left a finger's width of empty plate under the last line.
const BASE_SIZE := Vector2(228, 112)
## The most of the screen it may take before the zoom steps down.
const MAX_FILL := 0.82
## The wash over the world behind it, the same one every other window uses.
const DIM_COLOR := Color(0.1, 0.06, 0.04, 0.45)

const TITLE := "DEBT COLLECTOR"
## What one press of the middle button puts towards the debt, over and above
## the minimum. Paying ahead is a real choice (§4): it slows the interest, at
## the cost of the lawyer's fee coming later.
const EXTRA := 100

var hud: HUD

var _dim: ColorRect
var _window: PanelContainer
var _close_button: TextureButton
var _wallet: Label
var _owed: Label
var _due: Label
var _strikes: Label
var _week: Label
var _note: Label
var _pay_min: Button
var _pay_extra: Button
var _pay_all: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	get_viewport().size_changed.connect(_recenter)
	PlayerState.coins_changed.connect(func(_coins: int) -> void: refresh())
	Debt.changed.connect(refresh)


## Hooks the panel to a HUD, which is where its zoom comes from.
func bind(target: HUD) -> void:
	hud = target
	_build()
	refresh()
	_recenter()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	refresh()
	_recenter()


func close() -> void:
	if not visible:
		return
	if _close_button != null:
		_close_button.self_modulate = Color.WHITE
	visible = false
	closed.emit()


## Rereads the debt. Called on every change, so the numbers can never be a
## frame behind the purse.
func refresh() -> void:
	if _window == null:
		return
	var due := Debt.still_due()
	_wallet.text = str(PlayerState.coins)
	_owed.text = str(Debt.balance)
	_week.text = "WEEK %d" % Debt.week
	_strikes.text = "%d / %d" % [Debt.strikes, Debt.STRIKES_TO_LOSE]
	_strikes.add_theme_color_override("font_color", WARN if Debt.strikes > 0 else INK)

	if Debt.balance <= 0:
		_due.text = "NOTHING"
		_due.add_theme_color_override("font_color", INK)
		_note.text = "THE DEBT IS PAID."
	elif due == 0:
		_due.text = "PAID"
		_due.add_theme_color_override("font_color", INK)
		_note.text = "SETTLED UNTIL NEXT WEEK."
	else:
		_due.text = str(due)
		_due.add_theme_color_override("font_color", WARN)
		_note.text = "MISS IT AND THAT IS A STRIKE."
	_note.add_theme_color_override("font_color",
			MUTED if due == 0 or Debt.balance <= 0 else WARN)

	var purse := PlayerState.coins
	_pay_min.text = "PAY %d" % due if due > 0 else "PAID"
	_pay_min.disabled = due <= 0 or purse < due
	var extra := mini(EXTRA, Debt.balance)
	_pay_extra.text = "PAY %d" % extra
	_pay_extra.disabled = extra <= 0 or purse < extra
	_pay_all.text = "PAY ALL"
	_pay_all.disabled = Debt.balance <= 0 or purse < Debt.balance


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	# STOP, not IGNORE: while the bill is up a click belongs to it, not to the
	# hoe swing underneath.
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

	# Title, purse and the X share a row, as the storage window's do.
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label(TITLE, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var coin := TextureRect.new()
	coin.texture = UISkin.atlas(UISkin.COINS, UISkin.COIN)
	coin.stretch_mode = TextureRect.STRETCH_KEEP
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(coin)
	_wallet = _label("", INK)
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_wallet)
	_close_button = _cross()
	head.add_child(_close_button)

	var rule := ColorRect.new()
	rule.color = RULE
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)

	# The figures, on the lighter plate so they read as a statement rather than
	# as part of the frame.
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", INNER_BOX)
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sheet)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	sheet.add_child(rows)

	_week = _label("", MUTED)
	rows.add_child(_week)
	_owed = _row(rows, "OWED")
	_due = _row(rows, "THIS WEEK")
	_strikes = _row(rows, "STRIKES")
	_note = _label("", MUTED)
	rows.add_child(_note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	box.add_child(buttons)
	_pay_min = _button(buttons, func() -> void: _pay(Debt.still_due()))
	_pay_extra = _button(buttons, func() -> void: _pay(EXTRA))
	_pay_all = _button(buttons, func() -> void: _pay(Debt.balance))


## One "LABEL        value" line. Hands back the value's label, which is the
## part that changes.
func _row(parent: Control, name_: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var left := _label(name_, MUTED)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var value := _label("", INK)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIFont.body())
	label.add_theme_font_size_override("font_size", UIFont.SIZE)
	label.add_theme_color_override("font_color", color)
	return label


func _button(parent: Control, on_press: Callable) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 19
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", UIFont.title())
	button.add_theme_font_size_override("font_size", UIFont.SIZE)
	for role: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(role, INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	_style_button(button)
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


## The same four states the profile screen's buttons wear, so a button is a
## button wherever it is. The pack ships one plate, so the feedback is a tint.
func _style_button(button: Button) -> void:
	var shades := {"normal": Color.WHITE, "hover": Color(1.07, 1.07, 1.07),
			"pressed": Color(0.9, 0.9, 0.9), "disabled": Color(0.86, 0.84, 0.82)}
	for state: String in shades:
		var box := UISkin.sliced(BUTTON_TEXTURE, 6, 4, 4)
		box.modulate_color = shades[state]
		button.add_theme_stylebox_override(state, box)
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


func _pay(amount: int) -> void:
	if Debt.pay(amount) > 0:
		refresh()


## The biggest whole-number zoom the window fits the screen at. Whole numbers
## only: a fractional one puts seams through the plate's border.
func _zoom() -> int:
	var want: int = hud.ui_scale if hud != null else 2
	var room := get_viewport_rect().size * MAX_FILL
	while want > 1 and (BASE_SIZE.x * want > room.x or BASE_SIZE.y * want > room.y):
		want -= 1
	return want


func _recenter() -> void:
	# A Control under a CanvasLayer gets no size from anchors, so fit the
	# screen by hand -- the same thing the other windows have to do.
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
