class_name ProfilePanel
extends NinePatchRect

## The menu's left panel: who the player is, framed portrait at the top,
## a nameplate under it and a column of readings under that.
##
## The column scrolls. Before it did, the portrait had to be given
## whatever height the rows left over, and every row added took a bite
## out of Teemo — four rows already had her down to the smallest her
## frame could hold. Scrolling breaks that trade: the portrait takes the
## width it is given and the rows run on past the bottom of the panel for
## as long as they need to.
##
## The bar itself is hidden. It would be a second scrollbar on screen
## beside the one the sections already have, on a column that is barely
## taller than its panel, and the clipped row at the bottom says there is
## more to see well enough on its own. The wheel and dragging still work;
## only the bar is gone.
##
## Nothing on the panel owns what it shows. The name and the purse come
## from [PlayerProfile], the date and the clock from the [DayNightCycle]
## in the "day_night" group, the bag from [PlayerInventory], each row
## subscribing to whatever it reads so it cannot drift out of step with
## it. The clock has no signal fine enough to follow minute by minute, so
## the readings are taken every frame while the menu is open and not at
## all while it is shut.

## Rows under the nameplate, in order: the id the value is filed under
## and the picture that stands for it.
##
## A picture rather than a word, and not for decoration. A caption here
## would be a second, quieter piece of lettering on a mid-brown panel,
## and there is no brown quiet enough to be secondary and still be read —
## the words come out at the panel's own lightness. A seedling, a coin, a
## page, the sky and a jar say the same five things and cannot be
## illegible. The clock's picture changes with the time of day.
const ROWS: Array = [
	[&"farm", MenuTheme.SYMBOL_SPROUT],
	[&"money", ItemDatabase.COIN_CELL],
	[&"date", MenuTheme.SYMBOL_CALENDAR],
	[&"time", MenuTheme.SYMBOL_SUN],
	[&"bag", MenuTheme.SYMBOL_JAR],
]
## Height of one reading row: the boxed picture with a little air.
const ROW_HEIGHT: int = 28

@export var panel_margin: int = 10
## Space between the panel's edge and the column that scrolls inside it.
## The column is clipped to this, so it has to clear the frame's rounded
## corners or a scrolled row will show through them.
@export var padding: int = 8
## Gap between the portrait and the nameplate under it.
@export var portrait_gap: int = 4
## Gap between the nameplate and the first reading.
@export var name_gap: int = 4
## Height of the nameplate.
@export var name_height: int = 20
## Biggest the portrait is allowed to get, whatever room the panel has.
##
## Scrolling means this is a choice rather than whatever the rows leave
## over, and the choice is a trade: every pixel given to Teemo is a
## pixel of reading pushed below the fold. This is the largest that
## still leaves three of the five rows showing before anyone has to
## scroll, which is a little larger than the portrait could be when the
## column had to fit.
@export var max_portrait: int = 128

var _view: ScrollContainer
var _column: Control
var _portrait: TeemoPortrait
var _name: Label
var _values: Dictionary[StringName, Label] = {}
var _symbols: Dictionary[StringName, NinePatchRect] = {}
var _cycle: DayNightCycle

func _ready() -> void:
	patch_margin_left = panel_margin
	patch_margin_top = panel_margin
	patch_margin_right = panel_margin
	patch_margin_bottom = panel_margin

	_cycle = get_tree().get_first_node_in_group("day_night") as DayNightCycle

	_build()
	_subscribe()
	refresh()

## Pops the portrait in. The menu calls this each time it opens.
func greet() -> void:
	if _portrait != null:
		_portrait.greet()

## Rewrites every reading. Cheap enough to do wholesale rather than track
## which of five short strings actually moved.
func refresh() -> void:
	if _name == null:
		return

	var inventory := PlayerInventory.inventory
	var used := 0
	for i in inventory.slot_count():
		if not inventory.is_empty(i):
			used += 1

	_name.text = PlayerProfile.player_name
	_write(&"farm", PlayerProfile.farm_name)
	_write(&"money", "%dG" % PlayerProfile.money)
	_write(&"date", WeatherPanel.date_string(_cycle.day if _cycle != null else 1))
	_write(&"time", _cycle.get_time_string() if _cycle != null else "--:--")
	_write(&"bag", "%d / %d" % [used, inventory.slot_count()])

	# The clock wears the sky it is telling the time of.
	if _cycle != null:
		var sky: NinePatchRect = _symbols.get(&"time")
		if sky != null:
			MenuTheme.boxed_icon(sky).texture = ItemDb.icon_at(
				MenuTheme.phase_symbol(_cycle.get_phase()))

func _write(row: StringName, text: String) -> void:
	var label: Label = _values.get(row)
	if label != null:
		label.text = text

# --- Wiring ------------------------------------------------------------

func _subscribe() -> void:
	PlayerProfile.money_changed.connect(func(_amount: int) -> void: refresh())
	if _cycle != null:
		_connect_cycle()
	else:
		_find_cycle.call_deferred()

	# The cycle reports whole hours and the panel shows minutes, so the
	# clock row has to be looked at rather than waited for. A timer would
	# do it, but two panels on two timers tick out of phase, and at a
	# short day length that is minutes of daylight between two readings
	# of the same clock sitting side by side. Reading it every frame
	# costs a handful of string formats and cannot drift.
	set_process(is_visible_in_tree())

## The cycle adds itself to its group in its own [method Node._ready], so
## a panel built before it comes up would find nothing there. Looking
## again once the whole tree is ready costs one deferred call and makes
## the order the two sit in irrelevant.
func _find_cycle() -> void:
	_cycle = get_tree().get_first_node_in_group("day_night") as DayNightCycle
	if _cycle == null:
		return
	_connect_cycle()
	refresh()

func _connect_cycle() -> void:
	_cycle.day_passed.connect(func(_day: int) -> void: refresh())

func _process(_delta: float) -> void:
	refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _name != null:
		# Nothing worth reading while the menu is shut.
		set_process(is_visible_in_tree())
		if is_visible_in_tree():
			refresh()

# --- Building ----------------------------------------------------------

func _build() -> void:
	_view = ScrollContainer.new()
	_view.position = Vector2(padding, padding)
	_view.size = size - Vector2.ONE * padding * 2
	_view.clip_contents = true
	_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Scrolling, without a bar to show for it.
	_view.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_view)

	_column = Control.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_column)

	var width := _view.size.x
	var y := 0.0

	_portrait = TeemoPortrait.new()
	_portrait.frame_size = mini(int(width), max_portrait)
	_portrait.position = Vector2(roundf((width - _portrait.frame_size) * 0.5), y)
	_column.add_child(_portrait)
	y += _portrait.frame_size + portrait_gap

	_build_nameplate(width, y)
	y += name_height + name_gap

	for row in ROWS:
		_build_row(row[0], row[1], y)
		y += ROW_HEIGHT

	# What the scroll container measures the column by.
	_column.custom_minimum_size = Vector2(width, y)
	_column.size = _column.custom_minimum_size

## The name on its own light block, which is what makes the column read
## as a card about someone rather than as a list.
func _build_nameplate(width: float, y: float) -> void:
	var plate := MenuTheme.plaque(width, name_height)
	plate.position = Vector2(0, y)
	_column.add_child(plate)

	_name = MenuTheme.label(PlayerProfile.player_name, MenuTheme.TEXT_DARK)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MenuTheme.span(_name, 0, name_height)
	plate.add_child(_name)

## One reading: its picture in a cell on the left, the value against the
## far edge.
func _build_row(id: StringName, cell: Vector2i, y: float) -> void:
	var symbol := MenuTheme.boxed_symbol(cell)
	symbol.position = Vector2(0, y + (ROW_HEIGHT - MenuTheme.SYMBOL_BOX_SIZE) * 0.5)
	_column.add_child(symbol)
	_symbols[id] = symbol

	var value := MenuTheme.label("", MenuTheme.TEXT_LIGHT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MenuTheme.span(value, y, ROW_HEIGHT, 0, 2)
	_column.add_child(value)
	_values[id] = value
