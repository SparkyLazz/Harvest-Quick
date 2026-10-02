class_name ShippingCrate
extends Placed

## The crate the farm's produce leaves in, and the first place a carrot becomes
## a coin.
##
## Everything up to here already worked — a seed went in, was watered, grew on
## the day clock, was picked, fell in the row and was walked over into the
## satchel — and then stopped. The satchel was the end of the line. This is the
## other end, and it is deliberately the only one: nothing else in the game
## calls [method Market.sell].
##
## It ships [b]everything the town buys[/b] in one press rather than asking which
## and how many. A till that made the player pick through a satchel would turn
## the interesting decision — what to plant, three weeks ago — into a chore
## performed after the decision stopped mattering. The price is already decided
## by then; the only thing left is to find out what it was.
##
## Which means the player can be wrong about when to press it. Produce held back
## through a spike is produce sold at the price after it, and a harvest dumped
## the morning of a glut is worth a fraction of the same harvest sold across
## three days. That is [method Market.sell]'s falling price doing the work, and
## it is why this says what it paid rather than only that it sold.
##
## It is a fixture, not a placeable. There is one, it came with the farm, and an
## axe does nothing to it — [member Placed.broken_by] is left empty, so the
## inherited [method Placed.hit] refuses every tool without this having to know
## what a tool is.

## Emitted when produce goes off, with how many items and what they fetched.
signal shipped(items: int, paid: int)

## Emitted when the press found nothing to send, so a prompt can say so rather
## than the crate seeming broken.
signal nothing_to_ship

## The animation on the chest sheet: shut on the first frame, wide on the last.
const LID := &"lid"

## How long the lid stays open after a shipment before it shuts again.
@export var open_time: float = 0.6

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _busy: bool = false

func _ready() -> void:
	# Parked on the shut frame rather than played, so a crate that has always
	# been shut does not flap when the farm loads — the same reason [Chest] does.
	_sprite.animation = LID
	_sprite.frame = 0

## Ship the satchel. Returns whether the press was spent, which it is even for
## an empty satchel — the crate answered, it simply had nothing to send.
func interact() -> bool:
	if _busy:
		return true
	var items := 0
	var paid := 0
	# By slot rather than by kind, because the satchel is slots: the same crop
	# can sit in two of them, and each has to be emptied on its own.
	for i in Inventory.SLOT_COUNT:
		var item := Inventory.item_at(i)
		if item == null or not Market.buys(item.id):
			continue
		var count := Inventory.count_at(i)
		if count <= 0:
			continue
		# Taken before it is sold. Selling first and failing to take afterwards
		# would pay the player for produce still in the satchel.
		var taken := Inventory.take(i, count)
		if taken <= 0:
			continue
		items += taken
		paid += Market.sell(item.id, taken)
	if items <= 0:
		nothing_to_ship.emit()
		return true
	_flash(paid)
	shipped.emit(items, paid)
	return true

## Opens the lid, says something about the price, and shuts again.
##
## The emote is the only read on whether the timing was good, and it is chosen
## against the price rather than the total: a big cheque for a huge harvest sold
## into a glut is not a success, and a small one at triple the usual rate is.
func _flash(paid: int) -> void:
	_busy = true
	_sprite.play(LID)
	Emote.pop(get_parent(), global_position + Vector2(0, -10),
		Emote.STAR if paid > 0 else Emote.NOTE)
	var timer := get_tree().create_timer(open_time)
	await timer.timeout
	if is_inside_tree():
		_sprite.play_backwards(LID)
	_busy = false

## Nothing in the satchel the town would take, so the prompt can stay quiet.
func has_anything_to_ship() -> bool:
	for i in Inventory.SLOT_COUNT:
		var item := Inventory.item_at(i)
		if item != null and Market.buys(item.id) and Inventory.count_at(i) > 0:
			return true
	return false
