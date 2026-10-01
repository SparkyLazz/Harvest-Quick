class_name Stamina
extends Node

## How much work the player has left in them today.
##
## A plain pool with a cost per tool. Swinging spends, standing still earns
## it back, and a swing the pool cannot pay for does not happen — which is
## the whole of the rule, and the reason this is a node of its own rather
## than four more fields on the player. The player asks [method spend] and
## believes the answer; nothing here knows what a hoe does to the ground.
##
## Costs are named by [member ItemData.action], the same name the swing
## animations are filed under, so a new tool costs what its action costs and
## adding one is an entry in [member costs] rather than a branch.
##
## Everything watchable is a signal, because the dial that shows this is not
## the only thing that will want to know: a refused swing is worth a sound,
## and running out is worth more than a bar going dark.

## Emitted whenever the pool moves, with how full it now is from 0 to 1.
## Carries the fraction rather than the figure because every watcher so far
## wants the fraction, and the figure is a property away.
signal changed(fraction: float)

## Emitted when a swing is paid for, with the action and what it cost.
signal spent(action: StringName, cost: float)

## Emitted when a swing is turned down for want of stamina, with the action
## that was asked for. This is the only report the player gets, so something
## had better be listening.
signal refused(action: StringName)

## Emitted the moment the pool empties.
signal emptied

## Emitted when the pool fills again, having been short of full.
signal filled

## How much work a full day holds. The costs below are in the same units, so
## this is really a count of swings: a hundred against a hoe at six is
## sixteen rows worked before a rest.
@export var capacity: float = 100.0:
	set(value):
		capacity = maxf(value, 1.0)
		_current = minf(_current, capacity)
		changed.emit(fraction())

## What each tool takes out of the pool, by action name. An action with no
## entry here costs [member default_cost], so a tool added without being
## priced still costs something rather than being free.
@export var costs: Dictionary[StringName, float] = {
	&"hoe": 7.0,
	&"axe": 9.0,
	&"water": 4.0,
}

## What an unpriced action costs.
@export var default_cost: float = 5.0

@export_group("Recovery")
## How much comes back each second once the player stops working.
@export var regen_rate: float = 6.0

## Seconds of not spending before recovery starts. Without the pause the
## pool creeps up between swings and a long job never actually tires anyone.
@export var regen_delay: float = 1.2

## How much slower recovery is while the pool is empty, as a multiplier.
## Running dry should be worth avoiding, not merely a moment's wait.
@export_range(0.0, 1.0, 0.05) var empty_penalty: float = 0.45

## How far back up from empty the penalty lasts, as a fraction. Past this
## the player has caught their breath and recovers at the full rate.
@export_range(0.0, 1.0, 0.05) var winded_until: float = 0.25

var _current: float = 0.0
## Seconds since the last spend, counted only up to [member regen_delay].
var _rested: float = 0.0
## Whether the pool has been reported empty, so [signal emptied] goes out
## once per bout of exhaustion rather than every frame spent at zero.
var _was_empty: bool = false

## How much is left.
var current: float:
	get:
		return _current

func _ready() -> void:
	# Findable the way the player is, so a dial can be hung anywhere in the
	# scene and still find the pool it belongs to.
	add_to_group("stamina")
	_current = capacity

func _process(delta: float) -> void:
	if _current >= capacity:
		return
	if _rested < regen_delay:
		_rested += delta
		return
	var rate := regen_rate
	if fraction() < winded_until:
		rate *= empty_penalty
	_set_current(_current + rate * delta)

## How full the pool is, from 0 to 1.
func fraction() -> float:
	return clampf(_current / capacity, 0.0, 1.0)

## Whether the player is out of work for the moment.
func is_empty() -> bool:
	return _current <= 0.0

## What [param action] costs.
func cost_of(action: StringName) -> float:
	return costs.get(action, default_cost)

## Whether there is enough left for [param action].
##
## Asked every frame by the cursor as well as once per swing, so it says
## nothing and changes nothing: the refusal is [method spend]'s to report.
func can_afford(action: StringName) -> bool:
	return _current >= cost_of(action)

## Pays for [param action] and says whether it could.
##
## A swing is all or nothing: a hoe swung on four stamina does not turn half
## the soil, so the pool is either drawn on in full or left alone and the
## swing refused. Paying exactly to zero is allowed — the last swing of the
## day is the one worth having.
func spend(action: StringName) -> bool:
	var cost := cost_of(action)
	if cost > _current:
		refused.emit(action)
		return false
	_rested = 0.0
	_set_current(_current - cost)
	spent.emit(action, cost)
	return true

## Puts [param amount] back, for a bed, a meal or whatever else comes to
## mean rest. Recovers past the delay, because sleeping is not resting.
func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	_rested = regen_delay
	_set_current(_current + amount)

## Fills the pool, for the start of a new day.
func refill() -> void:
	restore(capacity)

func _set_current(value: float) -> void:
	var clamped := clampf(value, 0.0, capacity)
	if is_equal_approx(clamped, _current):
		return
	var was_full := _current >= capacity
	_current = clamped
	changed.emit(fraction())

	# Both edges are reported from here so there is one place that decides
	# what empty and full mean, and no way for a path through the pool to
	# move it without saying so.
	if is_empty() and not _was_empty:
		_was_empty = true
		emptied.emit()
	elif not is_empty():
		_was_empty = false
	if _current >= capacity and not was_full:
		filled.emit()
