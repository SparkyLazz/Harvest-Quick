class_name StatsList
extends Control

## The farm tab: how things stand, as a short column of plaques.
##
## Each reading sits on its own light block with a picture beside it,
## rather than as a caption written straight onto the panel. The panel is
## a mid brown and a dimmed brown caption on it comes out at almost
## exactly the panel's own lightness, which is no contrast at all — the
## words are there and cannot be read. A plaque gives the lettering its
## own ground to sit on, and the picture means the row can be found
## without reading anything.
##
## Every line is worked out from somewhere that already owns the number —
## the clock, the purse, the bag — at the moment it is asked for. Nothing
## is cached and nothing is counted twice, so there is no stat here that
## can be wrong.
##
## The clock's picture changes with the time of day, so the row says
## morning, afternoon or night twice over: once in the word and once in
## the sky beside it.

## Height of one plaque: the boxed picture with a pixel of air above and
## below it. Shorter than twice the block's corner and it stops being a
## plaque and starts being a lozenge.
const ROW_HEIGHT: int = 28
## Space between plaques.
const ROW_GAP: int = 2

## The rows, in order: the id the reading is filed under, its picture and
## its caption. The clock's picture is replaced as the day turns, so it
## is given the noon one to start from.
const ROWS: Array = [
	[&"date", MenuTheme.SYMBOL_CALENDAR, "DATE"],
	[&"time", MenuTheme.SYMBOL_SUN, "TIME"],
	[&"money", ItemDatabase.COIN_CELL, "PURSE"],
	[&"bag", MenuTheme.SYMBOL_JAR, "BAG"],
	[&"kinds", MenuTheme.SYMBOL_STAR, "SEEN"],
]

@export var padding: int = 0

var _values: Dictionary[StringName, Label] = {}
var _symbols: Dictionary[StringName, NinePatchRect] = {}
var _cycle: DayNightCycle

func _ready() -> void:
	_cycle = get_tree().get_first_node_in_group("day_night") as DayNightCycle
	_build()

	PlayerProfile.money_changed.connect(func(_amount: int) -> void: refresh())
	PlayerInventory.inventory.slot_changed.connect(func(_index: int) -> void: refresh())
	PlayerInventory.inventory.contents_changed.connect(refresh)
	if _cycle != null:
		_connect_cycle()
	else:
		_find_cycle.call_deferred()

	# Read every frame while showing, for the reason [ProfilePanel] gives:
	# two clocks on two timers drift apart, and both are on screen at
	# once.
	set_process(is_visible_in_tree())
	refresh()

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
	_cycle.hour_passed.connect(func(_hour: int) -> void: refresh())

func refresh() -> void:
	if _values.is_empty():
		return

	var inventory := PlayerInventory.inventory
	var used := 0
	var total := 0
	var kinds := {}
	for i in inventory.slot_count():
		var stack := inventory.stack_at(i)
		if stack == null:
			continue
		used += 1
		total += stack.count
		kinds[stack.id] = true

	var day: int = _cycle.day if _cycle != null else 1
	_write(&"date", "%s  DAY %d" % [WeatherPanel.date_string(day), day])
	_write(&"time", "%s  %s" % [
		_cycle.get_time_string() if _cycle != null else "--:--", _phase_name()])
	_write(&"money", "%dG" % PlayerProfile.money)
	_write(&"bag", "%d / %d  %d HELD" % [used, inventory.slot_count(), total])
	_write(&"kinds", "%d / %d" % [kinds.size(), ItemDb.all_ids().size()])

	# The clock wears the sky it is telling the time of.
	if _cycle != null:
		var sky: NinePatchRect = _symbols.get(&"time")
		if sky != null:
			MenuTheme.boxed_icon(sky).texture = ItemDb.icon_at(
				MenuTheme.phase_symbol(_cycle.get_phase()))

func _phase_name() -> String:
	if _cycle == null:
		return ""
	match _cycle.get_phase():
		DayNightCycle.Phase.MORNING: return "MORNING"
		DayNightCycle.Phase.NOON: return "AFTERNOON"
		DayNightCycle.Phase.NIGHT: return "NIGHT"
	return ""

func _write(row: StringName, text: String) -> void:
	var label: Label = _values.get(row)
	if label != null:
		label.text = text

func _process(_delta: float) -> void:
	refresh()

func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED or _values.is_empty():
		return
	set_process(is_visible_in_tree())
	if is_visible_in_tree():
		refresh()

# --- Building ----------------------------------------------------------

func _build() -> void:
	var y := padding
	for row in ROWS:
		_build_row(row[0], row[1], row[2], y)
		y += ROW_HEIGHT + ROW_GAP

	custom_minimum_size = Vector2(custom_minimum_size.x, y - ROW_GAP + padding)
	size.y = custom_minimum_size.y

## A plaque with the picture on its left, the caption beside it and the
## reading against the right edge. The plaque is added first and the rest
## put on top of it, so the lettering is never behind its own ground.
func _build_row(id: StringName, cell: Vector2i, caption: String, y: int) -> void:
	var plaque := MenuTheme.plaque(0, ROW_HEIGHT)
	# Spans the list's full width, whatever the scrollbar leaves it.
	MenuTheme.span(plaque, y, ROW_HEIGHT, padding, padding)
	add_child(plaque)

	var symbol := MenuTheme.boxed_symbol(cell)
	symbol.position = Vector2(2, (ROW_HEIGHT - MenuTheme.SYMBOL_BOX_SIZE) * 0.5)
	plaque.add_child(symbol)
	_symbols[id] = symbol

	var label := MenuTheme.label(caption, MenuTheme.TEXT_DARK_SOFT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(2 + MenuTheme.SYMBOL_BOX_SIZE + 8, 0)
	label.size.y = ROW_HEIGHT
	plaque.add_child(label)

	var value := MenuTheme.label("", MenuTheme.TEXT_DARK)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MenuTheme.span(value, 0, ROW_HEIGHT, 0, 8)
	plaque.add_child(value)
	_values[id] = value
