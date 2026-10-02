class_name ShopPanel
extends TwoPagePanel

## The seed merchant, and the first decision of every day.
##
## He comes in the morning and he is the only way seeds are got, which makes
## opening this the moment the run is actually played. Everything else — the
## hoe, the can, the ten days of waiting — is carrying out whatever was decided
## here. By the time a cauliflower is ripe the interesting part is a fortnight
## old.
##
## The left page is the shelf — what there is and what it costs, which is the
## question "can I afford it". The right is the one thing picked off that shelf,
## answered properly: how long it takes, what it yields, what the town pays for
## it today, and which seasons it will consent to grow in. A player choosing
## between a ten-day cauliflower and a five-day carrot on price alone is
## choosing on the least interesting number of the two.
##
## [b]The calendar is a wall, and this is where it is seen.[/b] Winter takes
## twenty of the twenty-eight crops off the table, and a season with four days
## left will not finish a ten-day crop. Both refuse the sale here, with the
## reason spelled out, because a player who learns them by planting learns them
## a fortnight too late. Whatever can go in the ground today sorts to the top:
## with eight winter crops among twenty-eight, a plain price sort buries every
## usable seed under twenty greyed-out ones.

## Emitted when something is bought, with the item, how many and what it cost.
signal bought(item: ItemData, count: int, paid: int)

## Emitted when a sale is refused, with a line saying why.
signal declined(reason: String)

## The category icons on the button sheet, in [enum MarketGood.Shelf] order.
const SHELF_ICONS: Array[Rect2] = [
	Rect2(0, 384, 32, 32), ## sprout
	Rect2(128, 352, 32, 32), ## paw
	Rect2(128, 160, 32, 32), ## house
]
const SHELF_NAMES: Array[String] = ["Crops", "Animals", "Deco"]

@export_group("Buying")
@export var click_buys: int = 1
## What a shift or right click buys — the handful, for a decided player.
@export var shift_buys: int = 10

@export_group("Shop")
## Whether the merchant lets himself in on the run's first morning.
##
## The first only. He used to arrive every morning, and a day is ten seconds —
## so the window shoved itself back over the farm every ten seconds and there
## was no keeping it shut. After day one the cart in the column brightens
## instead, which says the same thing and asks for nothing.
@export var open_on_first_day: bool = true

var _rows: Array[Dictionary] = []
var _tabs: Array[Dictionary] = []
var _shelf: int = MarketGood.Shelf.CROP
var _picked: StringName = &""

func _ready() -> void:
	super()
	_extra.add_child(_tab_strip())
	Market.prices_moved.connect(func(_d: int) -> void:
		if is_open():
			refresh())
	var run := get_tree().get_first_node_in_group("run")
	if run != null:
		run.began.connect(func(_s: int) -> void:
			if open_on_first_day:
				open())
		# Later mornings only refresh what is already up. Prices and the
		# calendar have moved, so an open window would otherwise be showing
		# yesterday's shelf.
		run.day_began.connect(func(_d: int) -> void:
			if is_open():
				rebuild())

## One button per shelf. The chosen one stays bright and the others dim, which
## is the whole of the selection — a strip of three needs no more than that.
func _tab_strip() -> Control:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 3)
	for shelf in SHELF_NAMES.size():
		var button := TextureRect.new()
		button.texture = _atlas(SHELF_ICONS[shelf], buttons)
		button.custom_minimum_size = Vector2(22, 22)
		button.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		button.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.tooltip_text = SHELF_NAMES[shelf]
		button.gui_input.connect(_on_tab_input.bind(shelf))
		strip.add_child(button)
		_tabs.append({"shelf": shelf, "button": button})
	strip.add_child(_stretch())
	return strip

# --- the shelf --------------------------------------------------------------

func rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	var stock := Market.stock(_shelf)
	# What can go in the ground today floats to the top, and price orders the
	# rest. See the note at the top of this file.
	stock.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_out := refusal(a["id"]) != ""
		var b_out := refusal(b["id"]) != ""
		if a_out != b_out:
			return b_out
		return a["price"] < b["price"])
	for entry in stock:
		_add_row(entry["id"], entry["item"])
	if is_open():
		_centre.call_deferred()
	_empty.visible = stock.is_empty()
	_empty.text = "No %s for sale yet." % SHELF_NAMES[_shelf].to_lower()
	# Keep whatever was being read if it is still on this shelf, so flipping to
	# another tab and back does not lose the player's place.
	var still := false
	for row in _rows:
		if row["id"] == _picked:
			still = true
	if not still:
		_picked = _rows[0]["id"] if not _rows.is_empty() else &""
	refresh()

func _add_row(id: StringName, item: ItemData) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_style(false))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_input.bind(id))
	_list.add_child(row)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	var box := TextureRect.new()
	box.texture = _atlas(BOX_REGION, sheet)
	box.custom_minimum_size = BOX_REGION.size
	# Held at the size the artist drew it; left to fill, the row's height
	# stretches the box and smears the bevel down one side.
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(box)

	var icon := TextureRect.new()
	# expand_mode first, and before the texture: while it is still
	# EXPAND_KEEP_SIZE the texture's own 32x32 is the minimum size, and the
	# 22x22 asked for below is silently clamped back up to it.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = item.icon
	icon.position = ICON_INSET
	icon.size = ICON_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var name_label := _text(item.display_name, HORIZONTAL_ALIGNMENT_LEFT, INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name_label)

	var price := _text("", HORIZONTAL_ALIGNMENT_RIGHT, INK)
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.custom_minimum_size = Vector2(28.0, 0.0)
	line.add_child(price)

	_rows.append({"id": id, "item": item, "row": row, "price": price,
		"name": name_label, "box": box})

func _on_row_input(event: InputEvent, id: StringName) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	# A click picks it up to read; buying is the second click, or a modified
	# one. So a player can look at a ten-day crop in a four-day season without
	# having bought it by looking.
	if _picked != id:
		_picked = id
		refresh()
		turn_page()
		for row in _rows:
			if row["id"] == id:
				pop_row(row["row"])
		return
	var many := button.shift_pressed or button.button_index == MOUSE_BUTTON_RIGHT
	if button.button_index == MOUSE_BUTTON_LEFT or many:
		buy(id, shift_buys if many else click_buys)

func _on_tab_input(event: InputEvent, shelf: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if _shelf != shelf:
		_shelf = shelf
		rebuild()

# --- the calendar -----------------------------------------------------------

## Why [param id] cannot be bought today, or "" when it can.
##
## Both answers are about the calendar. The second — not enough season left —
## is the one that catches people out: a crop can be perfectly in season on a
## day that is still far too late to sow it.
func refusal(id: StringName) -> String:
	var crop := _crop_of(id)
	if crop == null:
		return ""
	var day := _today()
	var season := Season.of_day(day)
	if not crop.grows_in(season):
		return "Will not grow in %s." % Season.name_of(season)
	if crop.days_to_ripe() > Season.days_left(day):
		return "Needs %d days; only %d left in %s." % [
			crop.days_to_ripe(), Season.days_left(day), Season.name_of(season)]
	return ""

## The crop behind a shop entry, or null for anything that is not a seed.
func _crop_of(id: StringName) -> CropData:
	var seed_item := Market.item_for(id) as SeedData
	return seed_item.crop if seed_item != null else null

# --- buying -----------------------------------------------------------------

## Buys up to [param count] of [param id], stopping at the calendar, the purse
## and the satchel, in that order.
func buy(id: StringName, count: int) -> int:
	var item := Market.item_for(id)
	if item == null or count <= 0:
		return 0
	var why := refusal(id)
	if why != "":
		declined.emit(why)
		refresh()
		return 0
	var unit := Market.shop_price(id)
	if unit <= 0:
		return 0
	if not Wallet.can_afford(unit):
		declined.emit("Not enough coin.")
		refresh()
		return 0
	# Trimmed to what will fit before any money changes hands: a purchase with
	# nowhere to go would be paid for and lost, the same bargain
	# [method Inventory.has_room_for] makes for a felled tree.
	var room := count
	while room > 0 and not Inventory.has_room_for(item, room):
		room -= 1
	if room <= 0:
		declined.emit("No room in the satchel.")
		refresh()
		return 0
	var got := Market.buy(id, room)
	if got <= 0:
		return 0
	Inventory.add(item, got)
	bought.emit(item, got, unit * got)
	refresh()
	return got

# --- drawing ----------------------------------------------------------------

func refresh() -> void:
	if not is_node_ready():
		return
	_head_refresh()
	for tab in _tabs:
		tab["button"].modulate = Color.WHITE if tab["shelf"] == _shelf \
			else Color(1, 1, 1, 0.45)
	for row in _rows:
		var id: StringName = row["id"]
		var price: int = Market.shop_price(id)
		var blocked := refusal(id) != ""
		var affordable := Wallet.can_afford(price)
		row["price"].text = str(price)
		# Three states told apart by colour alone, because a row has no room
		# for a reason: readable, dimmed for out of season, red for unaffordable.
		var tint := Color.WHITE
		if blocked:
			tint = Color(1, 1, 1, 0.42)
		elif not affordable:
			tint = Color(1.0, 0.72, 0.68)
		row["box"].modulate = tint
		row["name"].modulate = tint
		row["price"].modulate = Color(1, 1, 1, 0.42) if blocked \
			else (Color.WHITE if affordable else INK_BAD)
		row["row"].add_theme_stylebox_override("panel", _row_style(id == _picked))
	_draw_detail()

func _draw_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	if _picked == &"":
		_detail.add_child(_text("Nothing selected.", HORIZONTAL_ALIGNMENT_LEFT, INK_SOFT))
		return
	var item := Market.item_for(_picked)
	if item == null:
		return

	_detail.add_child(_text(item.display_name, HORIZONTAL_ALIGNMENT_LEFT, INK))
	_detail.add_child(_line("Price", "%d g" % Market.shop_price(_picked)))

	var crop := _crop_of(_picked)
	if crop != null:
		_detail.add_child(_line("Grows in", crop.season_names()))
		_detail.add_child(_line("Ready in", "%d days" % crop.days_to_ripe()))
		var yields := "%d %s" % [crop.produce_count, crop.produce.display_name] \
			if crop.produce != null else "-"
		_detail.add_child(_line("Yields", yields))
		if crop.produce != null and Market.buys(crop.produce.id):
			_detail.add_child(_line("Sells for", "%d g" % Market.price(crop.produce.id)))

	if item.description != "":
		_detail.add_child(_wrapped(item.description, INK_SOFT))

	_detail.add_child(_stretch())
	var why := refusal(_picked)
	if why != "":
		_detail.add_child(_wrapped(why, INK_BAD))
	else:
		_detail.add_child(_text("Click again to buy. Shift: %d" % shift_buys,
			HORIZONTAL_ALIGNMENT_LEFT, INK_GOOD))
