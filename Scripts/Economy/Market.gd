extends Node

## What the town wants this week, and what it will pay for it.
##
## The farm is the easy half of this game. The hard half is that a seed takes
## five days to become a carrot, and the price of carrots on the day it comes
## up is not the price on the day it went in. So the player is never really
## planting a crop — they are taking a position on what the town will want
## next week, and the whole skill of it is reading that early enough to act.
##
## Three things move a price, and they are deliberately different in kind so
## that a player can tell them apart:
##
## - [b]Drift[/b] is noise. Every good wanders a little each night, by its own
##   [member MarketGood.volatility], pulled back toward ordinary. It cannot be
##   predicted and is not meant to be; it is there so that no price is ever
##   exactly the number the player memorised.
## - [b]Spikes[/b] are the game. A festival wants pumpkins; an inn wants
##   eggplant. These are rolled for the whole run at the start and announced
##   in advance through [method forecast], so a spike is never a surprise — it
##   is a deadline. Missing one is the player's fault, which is the only way
##   hitting one can feel like theirs too.
## - [b]Glut[/b] is the player's own doing. Everything sold sits on the market
##   and holds the price down until the town works through it. This is why the
##   answer is never "plant the whole farm with the one good crop": the
##   thirtieth carrot of the day is worth a fraction of the first.
##
## Prices are read, never stored on the item. An [ItemData] is a description
## that does not change while the game runs — see its own note — so what a
## carrot is worth today lives here, keyed by [member ItemData.id].
##
## Reached as the [code]Market[/code] autoload, or through the "market" group.

## Emitted once the night's drift and decay are in, with the new day.
## Anything showing a price should redraw on this rather than poll.
signal prices_moved(day: int)

## Emitted when a spike comes into view, with the good, the day it lands and
## how strong it is. The forecast board's whole content.
signal demand_announced(id: StringName, day: int, strength: float)

## Emitted when a spike's day arrives, with the good and its strength.
signal demand_peaked(id: StringName, strength: float)

## Emitted when the player sells, with the good, how many and what was paid.
## Carries the total rather than the unit price because the price falls as the
## stack goes across the counter, so there is no one unit price to report.
signal sold(id: StringName, count: int, paid: int)

@export_group("Goods")
## Everything the town trades in. A good missing from here has no price and
## cannot be sold, which is how a tool stays untradeable without needing a
## flag saying so.
##
## Filled from [member goods_dir] on load rather than listed here, because an
## autoload has no scene to be configured in. Adding a crop to the economy is
## dropping a resource in a folder, which is the same bargain the nature kinds
## make — and a test can fill this directly instead.
@export var goods: Array[MarketGood] = []

## Where the goods are kept. Everything in it is loaded, so a resource in this
## folder is in the economy by virtue of being there.
@export_dir var goods_dir: String = "res://Assets/Market"

@export_group("Drift")
## How hard an unusual price is pulled back toward ordinary each night, 0 to
## 1. Low and a bad week lasts a month; high and nothing ever strays. This is
## what stops [member MarketGood.volatility] wandering off to nothing.
@export_range(0.0, 1.0, 0.01) var mean_reversion: float = 0.25

## How far demand may stray on drift alone, before any spike is counted.
@export var drift_floor: float = 0.55
@export var drift_ceiling: float = 1.8

@export_group("Spikes")
## How many days before a spike lands that the player is told. The single most
## important number in the game: it has to be longer than a crop takes to grow
## or the forecast is useless, and short enough that the player is committing
## rather than strolling.
@export var notice_days: int = 12

## Days between spikes, roughly. Rolled per gap so they do not fall on a beat.
@export var spike_gap: Vector2i = Vector2i(4, 8)

## How strong a spike is, as a multiplier on an ordinary price.
@export var spike_strength: Vector2 = Vector2(1.8, 3.2)

## How many days a spike holds before it fades.
@export var spike_days: Vector2i = Vector2i(1, 3)

@export_group("Glut")
## How much of the unsold pile the town works through each night, 0 to 1.
## The pile is what the player dumped; this is how fast dumping is forgiven.
@export_range(0.0, 1.0, 0.01) var glut_recovery: float = 0.45

## How far a price can ever be driven down by flooding. Without a floor a big
## enough harvest makes produce worthless and the player has thrown away a
## week for nothing.
@export var glut_floor: float = 0.25

@export_group("Shop")
## What the shop adds on top of the market price. The shop buys nothing back,
## so this is not a spread — it is the cost of not growing it yourself.
@export var shop_markup: float = 1.0

## A dated run on one good: the town wanting something, from a day, for a few
## days, by some multiple.
class Spike:
	var id: StringName
	var day: int
	var days: int
	var strength: float

	func covers(d: int) -> bool:
		return d >= day and d < day + days

	func _init(p_id: StringName, p_day: int, p_days: int, p_strength: float) -> void:
		id = p_id
		day = p_day
		days = p_days
		strength = p_strength

var _rng := RandomNumberGenerator.new()
var _by_id: Dictionary[StringName, MarketGood] = {}
## Where each good's appetite currently sits. 1.0 is ordinary.
var _demand: Dictionary[StringName, float] = {}
## How much of each good is sitting unsold on the market.
var _pile: Dictionary[StringName, float] = {}
## What each good fetched when yesterday closed, so the paper can say which way
## a price went without every reader keeping its own history.
var _yesterday: Dictionary[StringName, int] = {}
var _spikes: Array[Spike] = []
var _announced: Dictionary[int, bool] = {}
var _day: int = 1

func _ready() -> void:
	add_to_group("market")
	_load_goods()

## Read every good out of [member goods_dir], skipping anything already listed
## so that a test which filled [member goods] by hand is left alone.
func _load_goods() -> void:
	if goods_dir.is_empty():
		return
	var listed: Dictionary[StringName, bool] = {}
	for good in goods:
		if good != null and good.item != null:
			listed[good.item.id] = true
	for file in DirAccess.get_files_at(goods_dir):
		# An exported build ships these as .remap; the loader wants the path
		# without it, so the suffix comes off before anything is asked for.
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres") and not name.ends_with(".res"):
			continue
		var good := ResourceLoader.load(goods_dir.path_join(name)) as MarketGood
		if good == null or good.item == null or listed.has(good.item.id):
			continue
		listed[good.item.id] = true
		goods.append(good)

## Open the market for a run. The seed decides every spike in it, so the same
## seed is the same economy — which is what makes one run worth comparing to
## another, and what makes the forecast something the player can trust.
func open(market_seed: int, last_day: int = 60) -> void:
	_rng.seed = market_seed if market_seed != 0 else randi()
	_by_id.clear()
	_demand.clear()
	_pile.clear()
	_spikes.clear()
	_announced.clear()
	_day = 1
	for good in goods:
		if good == null or good.item == null:
			continue
		_by_id[good.item.id] = good
		_demand[good.item.id] = 1.0
		_pile[good.item.id] = 0.0
	_roll_spikes(last_day)
	_announce_visible()

## Roll the whole run's worth of spikes up front.
##
## Up front rather than night by night because the forecast has to promise
## something [member notice_days] out, and a market that decided at the last
## moment could not. It also makes a run's economy a fact about its seed
## rather than about how long the player has been playing.
func _roll_spikes(last_day: int) -> void:
	var tradeable: Array[StringName] = []
	for id in _by_id:
		if not _by_id[id].in_shop:
			tradeable.append(id)
	if tradeable.is_empty():
		return
	var day := _rng.randi_range(spike_gap.x, spike_gap.y)
	while day <= last_day:
		var id := tradeable[_rng.randi_range(0, tradeable.size() - 1)]
		_spikes.append(Spike.new(
			id,
			day,
			_rng.randi_range(spike_days.x, spike_days.y),
			_rng.randf_range(spike_strength.x, spike_strength.y),
		))
		day += _rng.randi_range(spike_gap.x, spike_gap.y)

## Move the market on a night. Driven by the day clock, never by a timer.
func advance_to(day: int) -> void:
	# Taken before anything moves, so "yesterday" means the prices the player
	# went to bed on rather than the ones they woke to.
	for id in _by_id:
		_yesterday[id] = price(id)
	_day = day
	for id in _demand:
		var good: MarketGood = _by_id[id]
		var next: float = _demand[id] + _rng.randfn(0.0, good.volatility)
		next = lerpf(next, 1.0, mean_reversion)
		_demand[id] = clampf(next, drift_floor, drift_ceiling)
		_pile[id] = _pile[id] * (1.0 - glut_recovery)
	_announce_visible()
	for spike in _spikes:
		if spike.day == day:
			demand_peaked.emit(spike.id, spike.strength)
	prices_moved.emit(day)

## Tell the player about anything now inside the notice window and not yet
## mentioned. Each spike is announced once; the board keeps showing it after.
func _announce_visible() -> void:
	for i in _spikes.size():
		var spike := _spikes[i]
		if _announced.has(i):
			continue
		if spike.day - _day > notice_days:
			continue
		_announced[i] = true
		demand_announced.emit(spike.id, spike.day, spike.strength)

## Everything the player has been told about and that has not yet passed,
## soonest first. The forecast board reads this and nothing else.
func forecast() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in _spikes.size():
		var spike := _spikes[i]
		if not _announced.has(i) or spike.day + spike.days <= _day:
			continue
		out.append({
			"id": spike.id,
			"day": spike.day,
			"days": spike.days,
			"strength": spike.strength,
			"in": spike.day - _day,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["day"] < b["day"])
	return out

## How much the town wants [param id] today, spikes included. 1.0 is ordinary.
func demand_for(id: StringName) -> float:
	if not _demand.has(id):
		return 0.0
	var d: float = _demand[id]
	for spike in _spikes:
		if spike.id == id and spike.covers(_day):
			d *= spike.strength
	return d

## What the next one sold would fetch. Falls as the pile grows, which is why
## [method sell] does not simply multiply this by the stack size.
func price(id: StringName) -> int:
	if not _by_id.has(id):
		return 0
	var good: MarketGood = _by_id[id]
	return maxi(1, roundi(good.base_price * demand_for(id) * _glut(id)))

## What the shop charges for one.
func shop_price(id: StringName) -> int:
	if not _by_id.has(id) or not _by_id[id].in_shop:
		return 0
	return maxi(1, roundi(price(id) * shop_markup))

## The drag the unsold pile puts on a price.
func _glut(id: StringName) -> float:
	var good: MarketGood = _by_id[id]
	if good.absorbs <= 0.0:
		return 1.0
	return maxf(glut_floor, 1.0 / (1.0 + _pile[id] / good.absorbs))

## Whether the town buys this at all.
##
## It does not buy back what the shop sold. A market that refunded seed corn
## would let the player undo a planting the moment the forecast moved, and
## committing to a planting before you know is the whole game.
func buys(id: StringName) -> bool:
	return _by_id.has(id) and not _by_id[id].in_shop

## Sell [param count] of [param id] and pay for them, one at a time.
##
## One at a time because each one sold makes the next worth slightly less, and
## a stack priced at its first unit would let the player dump a whole harvest
## at the spike price — the exact move the glut exists to prevent. The loop is
## the mechanic, not an implementation detail.
func sell(id: StringName, count: int) -> int:
	if not buys(id) or count <= 0:
		return 0
	var paid := 0
	for _i in count:
		paid += price(id)
		_pile[id] = _pile[id] + 1.0
	Wallet.earn(paid, &"market")
	sold.emit(id, count, paid)
	return paid

## What selling [param count] would fetch, without selling it. For a till that
## shows the figure before the player commits to it.
func quote(id: StringName, count: int) -> int:
	if not buys(id) or count <= 0:
		return 0
	var kept: float = _pile[id]
	var paid := 0
	for _i in count:
		paid += price(id)
		_pile[id] = _pile[id] + 1.0
	_pile[id] = kept
	return paid

## Buy up to [param count] of [param id] from the shop, as many as the purse
## covers. Returns how many were actually bought.
func buy(id: StringName, count: int) -> int:
	if not _by_id.has(id) or not _by_id[id].in_shop or count <= 0:
		return 0
	var unit := shop_price(id)
	var afford: int = mini(count, Wallet.coins / unit)
	if afford <= 0:
		Wallet.refused.emit(unit - Wallet.coins)
		return 0
	Wallet.spend(unit * afford, &"shop")
	return afford

## Everything the shop stocks today, with its price and its shelf.
##
## Pass a [enum MarketGood.Shelf] for one shelf's worth. The shop asks per shelf
## because that is how it is laid out, and a panel filtering a full catalogue
## itself would be a second place that knows what a shelf is.
func stock(shelf: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _by_id:
		var good: MarketGood = _by_id[id]
		if not good.in_shop:
			continue
		if shelf >= 0 and good.shelf != shelf:
			continue
		out.append({
			"id": id,
			"item": good.item,
			"price": shop_price(id),
			"shelf": good.shelf,
		})
	return out

## Which shelf [param id] sits on, or -1 if the shop does not stock it.
func shelf_of(id: StringName) -> int:
	return _by_id[id].shelf if _by_id.has(id) else -1

## The item a good stands for, for a panel that has an id and needs an icon.
func item_for(id: StringName) -> ItemData:
	return _by_id[id].item if _by_id.has(id) else null

## What [param id] fetched yesterday, or today's price on the first morning.
func price_yesterday(id: StringName) -> int:
	return _yesterday.get(id, price(id))

## How far [param id] has moved overnight, as a fraction — 0.2 is up a fifth.
func price_swing(id: StringName) -> float:
	var was := price_yesterday(id)
	return 0.0 if was <= 0 else (price(id) - was) / float(was)

## The drag the unsold pile is currently putting on [param id]'s price, 1.0
## being none at all. Below 1 the town is still working through a glut.
func pressure(id: StringName) -> float:
	return _glut(id) if _by_id.has(id) else 1.0

## How many of [param id] are sitting unsold on the market.
func pile_of(id: StringName) -> float:
	return _pile.get(id, 0.0)

## Everything the town trades in but does not sell, soonest use first: the
## produce side of the catalogue.
func produce_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _by_id:
		if not _by_id[id].in_shop:
			out.append(id)
	return out

## Which day the market thinks it is.
func day() -> int:
	return _day
