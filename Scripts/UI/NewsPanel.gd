class_name NewsPanel
extends TwoPagePanel

## The market paper: what the town is saying, and what it means for the farm.
##
## The economy has always known more than the player could see. Spikes are
## rolled for the whole run at the start and announced days in advance; the
## calendar decides what may be planted; the collector's schedule is fixed the
## moment a run opens. All of that was sitting in [Market] and [Debt] with
## nothing to read it out. This is the reading.
##
## [b]What the paper will and will not print.[/b] It prints what is already
## decided and not yet obvious: the demand the town has committed to, the day
## the season turns, the day the collector is due, how badly the market is
## glutted, and which way prices moved overnight. It does not print a guess
## about tomorrow's drift, because drift is the one part of this economy that is
## meant to be unknowable — a paper that predicted it would turn the whole game
## into reading a number off a page. The rule is: report facts and commitments,
## never forecasts of noise.
##
## That line is also what keeps the game honest. Every story here could have
## been worked out by a player who watched carefully for a week. The paper saves
## them the bookkeeping, not the thinking.
##
## Stories are not stored. They are worked out from live state each time the
## window opens, which means they cannot go stale and there is no second copy of
## the economy to keep in step. The only thing kept is a short log of things
## that happened and would otherwise be lost — the mother's nights out, the
## collector's visits — because those are events rather than conditions.

## Cells of the emoji sheet, sampled rather than counted by eye — row 8 is the
## symbols, 9 the hearts, 10 the stars and coins, 11 the thumbs, 24 the tools,
## 31 the suns and 33 the moons. Reading the rows off the whole sheet put every
## one of these a row low on the first attempt.
const PIC_SPIKE := Rect2(0, 320, 32, 32)      ## star
const PIC_COLLECTOR := Rect2(160, 256, 32, 32) ## !
const PIC_MOTHER := Rect2(192, 256, 32, 32)    ## ?
const PIC_SEASON := Rect2(64, 992, 32, 32)    ## sun
const PIC_WINTER := Rect2(0, 1056, 32, 32)     ## moon
const PIC_GLUT := Rect2(96, 352, 32, 32)       ## thumb down
const PIC_RISE := Rect2(0, 352, 32, 32)        ## thumb up
const PIC_DEBT := Rect2(192, 320, 32, 32)      ## coin
const PIC_LAWYER := Rect2(0, 768, 32, 32)      ## key
const PIC_PAID := Rect2(0, 256, 32, 32)        ## check

## Below this, the town is working through a glut and the paper says so.
const GLUT_WORRY: float = 0.80
## A price has to move at least this much overnight to be worth a column inch.
const SWING_WORTH: float = 0.12

@export_group("News")
## The emoji sheet the little pictures come from.
@export var emoji: Texture2D
## How many past events to keep. The paper is a day's news, not an archive.
@export var log_length: int = 12

var _rows: Array[Dictionary] = []
var _stories: Array[Dictionary] = []
var _picked: int = 0
## Things that happened, newest last. Conditions are worked out; events are not
## recoverable after the fact, so they are caught as they go past.
var _log: Array[Dictionary] = []

func _ready() -> void:
	super()
	Market.prices_moved.connect(func(_d: int) -> void:
		if is_open():
			rebuild())
	Debt.mother_gambled.connect(func(added: int, owed: int) -> void:
		_remember(PIC_MOTHER, "Your mother, again",
			"She was seen at the tables on the night the collector called. %d more "
			% added + "has gone onto the loan in your name, which now stands at %d. "
			% owed + "The rent is a share of that figure, so it has just gone up too."))
	Debt.paid.connect(func(amount: int, left: int) -> void:
		_remember(PIC_PAID, "Collector paid",
			"%d handed over at the gate. The principal is untouched at %d — that "
			% [amount, left] + "payment was interest, and interest is all he ever takes."))
	Debt.missed.connect(func(short: int, took: int, _phase: int) -> void:
		_remember(PIC_COLLECTOR, "Collector left short",
			"He took the %d that was in the purse and left %d short. The shortfall "
			% [took, short] + "has been added to the principal, so next time he calls "
			+ "he will want more than he did today."))

# --- gathering the news ------------------------------------------------------

func rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_stories = _gather()
	for i in _stories.size():
		_add_row(i, _stories[i])
	if is_open():
		_centre.call_deferred()
	_empty.visible = _stories.is_empty()
	_empty.text = "No news today."
	_picked = clampi(_picked, 0, maxi(_stories.size() - 1, 0))
	refresh()

## Everything worth printing today, most pressing first.
func _gather() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_debt_stories())
	out.append_array(_season_stories())
	out.append_array(_demand_stories())
	out.append_array(_glut_stories())
	out.append_array(_swing_stories())
	# The log last and newest first: it is what already happened, and the page
	# is for what is about to.
	for i in range(_log.size() - 1, -1, -1):
		out.append(_log[i])
	return out

func _debt_stories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Debt.settled:
		out.append(_story(PIC_LAWYER, "The debt is finished",
			"The lawyer did what no amount of paying ever would. Nothing is owed."))
		return out
	var days := Debt.days_until_visit(_today())
	var due := Debt.installment
	var head := "Collector due today" if days <= 0 \
		else ("Collector due tomorrow" if days == 1 \
		else "Collector due in %d days" % days)
	var short := maxi(due - Wallet.coins, 0)
	var body := "He wants %d, at %d in the hundred on a principal of %d. " % [
		due, roundi(Debt.rate * 100.0), Debt.owed]
	body += ("The purse covers it with %d to spare." % (Wallet.coins - due)) if short == 0 \
		else ("The purse is %d short. Come up empty and it costs a heart, the shortfall goes onto the principal, and the rent rises with it." % short)
	out.append(_story(PIC_COLLECTOR if short > 0 else PIC_DEBT, head, body))

	var toward := Wallet.coins - Debt.lawyer_fee
	out.append(_story(PIC_LAWYER, "Lawyer asks %d" % Debt.lawyer_fee,
		("Affordable today, and the only way this ends. Paying the collector forever is losing slowly." if toward >= 0
		else "Another %d and the debt can be ended outright. Interest paid so far: %d, none of which touched the principal." % [-toward, Debt.interest_paid])))
	return out

func _season_stories() -> Array[Dictionary]:
	var day := _today()
	var left := Season.days_left(day)
	var now := Season.of_day(day)
	var next := Season.after(now)
	var pic := PIC_WINTER if next == Season.Of.WINTER else PIC_SEASON
	var body := "%d days of %s remain. " % [left, Season.name_of(now)]
	# Named rather than counted, because what matters is which crops the turn
	# takes away, and that is a short enough list to print.
	var dying: Array[String] = []
	var coming: Array[String] = []
	for entry in Market.stock(MarketGood.Shelf.CROP):
		var seed_item := Market.item_for(entry["id"]) as SeedData
		if seed_item == null or seed_item.crop == null:
			continue
		var crop: CropData = seed_item.crop
		var short_name: String = entry["item"].display_name.replace(" Seeds", "")
		if crop.grows_in(now) and not crop.grows_in(next):
			dying.append(short_name)
		elif not crop.grows_in(now) and crop.grows_in(next):
			coming.append(short_name)
	if not dying.is_empty():
		body += "Out with the season: %s. " % ", ".join(dying)
	if not coming.is_empty():
		body += "In with the next: %s." % ", ".join(coming)
	return [_story(pic, "%s ends in %d days" % [Season.name_of(now), left], body)]

func _demand_stories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in Market.forecast():
		var item := Market.item_for(f["id"])
		if item == null:
			continue
		var name := item.display_name
		var away: int = f["in"]
		var head := "%s wanted%s" % [name, "" if away > 0 else " today"]
		var body := "Word from the town: %s will fetch about %s times the usual " % [
			name, ("%.1f" % f["strength"]).rstrip("0").rstrip(".")]
		body += "for %d day%s from %s. " % [
			f["days"], "" if f["days"] == 1 else "s", Season.label(f["day"])]
		body += _can_make_it(f["id"], away)
		out.append(_story(PIC_SPIKE, head, body))
	return out

## Whether there is still time to grow into a spike. The one piece of arithmetic
## the paper does for the player, because it is the whole point of knowing early.
func _can_make_it(produce_id: StringName, away: int) -> String:
	var seed_id := StringName("%s_seeds" % produce_id)
	var seed_item := Market.item_for(seed_id) as SeedData
	if seed_item == null or seed_item.crop == null:
		return ""
	var needs := seed_item.crop.days_to_ripe()
	# The calendar is checked before the clock. A crop that will not grow in the
	# season the spike lands in cannot be reached by planting sooner, and
	# telling a player they merely left it late would be a lie that costs them
	# a fortnight finding out.
	var crop: CropData = seed_item.crop
	var now := Season.of_day(_today())
	if not crop.grows_in(now):
		return "It will not grow in %s, so this one is for a farm that is not yours this season." % Season.name_of(now)
	if away <= 0:
		return "Anything already in the ground should come up to it."
	if needs <= away:
		return "Sown today it takes %d days, so there is time — with %d to spare." % [
			needs, away - needs]
	return "It takes %d days to grow and the day is %d off, so only a field already planted will see it." % [
		needs, away]

func _glut_stories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var worst: Array[Dictionary] = []
	for id in Market.produce_ids():
		var drag := Market.pressure(id)
		if drag < GLUT_WORRY:
			worst.append({"id": id, "drag": drag})
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["drag"] < b["drag"])
	for entry in worst.slice(0, 3):
		var item := Market.item_for(entry["id"])
		if item == null:
			continue
		out.append(_story(PIC_GLUT, "Glut of %s" % item.display_name.to_lower(),
			"About %d sit unsold, holding the price to %d in the hundred of what it " % [
				roundi(Market.pile_of(entry["id"])), roundi(entry["drag"] * 100.0)]
			+ "would otherwise be. It recovers by itself overnight, a little at a time. "
			+ "Selling more today only presses it further down."))
	return out

func _swing_stories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var best := {"id": &"", "swing": 0.0}
	var worst := {"id": &"", "swing": 0.0}
	for id in Market.produce_ids():
		var swing := Market.price_swing(id)
		if swing > best["swing"]:
			best = {"id": id, "swing": swing}
		if swing < worst["swing"]:
			worst = {"id": id, "swing": swing}
	for entry in [best, worst]:
		if entry["id"] == &"" or absf(entry["swing"]) < SWING_WORTH:
			continue
		var item := Market.item_for(entry["id"])
		if item == null:
			continue
		var up: bool = entry["swing"] > 0.0
		out.append(_story(PIC_RISE if up else PIC_GLUT,
			"%s %s overnight" % [item.display_name, "up" if up else "down"],
			"From %d to %d, a move of %d in the hundred. Ordinary drift, not a " % [
				Market.price_yesterday(entry["id"]), Market.price(entry["id"]),
				roundi(absf(entry["swing"]) * 100.0)]
			+ "promise — the town has committed to nothing here and it may go back tomorrow."))
	return out

func _story(pic: Rect2, head: String, body: String) -> Dictionary:
	return {"pic": pic, "head": head, "body": body, "day": _today()}

func _remember(pic: Rect2, head: String, body: String) -> void:
	_log.append(_story(pic, head, body))
	while _log.size() > log_length:
		_log.remove_at(0)
	if is_open():
		rebuild()

# --- the page ---------------------------------------------------------------

func _add_row(index: int, story: Dictionary) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_style(false))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_input.bind(index))
	_list.add_child(row)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	var pic := TextureRect.new()
	# expand_mode before the texture, or the emoji's own 32x32 becomes the
	# minimum size and the 20x20 asked for is clamped back up to it.
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture = _atlas(story["pic"], emoji)
	pic.custom_minimum_size = Vector2(20, 20)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(pic)

	var head := _text(story["head"], HORIZONTAL_ALIGNMENT_LEFT, INK)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(head)

	_rows.append({"row": row, "head": head})

func _on_row_input(event: InputEvent, index: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	_picked = index
	refresh()
	turn_page()
	if index < _rows.size():
		pop_row(_rows[index]["row"])

func refresh() -> void:
	if not is_node_ready():
		return
	_head_refresh()
	for i in _rows.size():
		_rows[i]["row"].add_theme_stylebox_override("panel", _row_style(i == _picked))
	_draw_detail()

func _draw_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	if _stories.is_empty():
		_detail.add_child(_text("Nothing to report.", HORIZONTAL_ALIGNMENT_LEFT, INK_SOFT))
		return
	var story: Dictionary = _stories[clampi(_picked, 0, _stories.size() - 1)]
	_detail.add_child(_wrapped(story["head"], INK))
	_detail.add_child(_wrapped(story["body"], INK_SOFT))
	_detail.add_child(_stretch())
	_detail.add_child(_text(Season.label(story["day"]), HORIZONTAL_ALIGNMENT_RIGHT, INK_SOFT))
