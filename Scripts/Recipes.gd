class_name RecipeDB
extends RefCounted

## What the crafting tab can make. There is one kind of recipe so far: produce
## back into seed, so a good harvest reseeds the field instead of being sold.
##
## The table is generated from CropDB rather than written out, so a crop added
## there turns up here with no second edit.

## Produce spent per batch.
const SEED_COST := 2
## Seeds a batch yields.
const SEED_YIELD := 3


## Every recipe, in CropDB's own order. Each entry is
## {id, name, out, out_count, costs: {item id: count}}.
static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crop: String in CropDB.CROPS:
		out.append({
			"id": crop + "_reseed",
			"name": CropDB.CROPS[crop]["name"] + " Seeds",
			"out": crop + ItemDB.SEED_SUFFIX,
			"out_count": SEED_YIELD,
			"costs": {crop: SEED_COST},
		})
	return out


## A sentence for the detail box.
static func describe(recipe: Dictionary) -> String:
	var crop: String = String(recipe["costs"].keys()[0])
	return "Threshes %d %s into %d seeds, ready to plant again." % [
		SEED_COST, ItemDB.display_name(crop).to_lower(), SEED_YIELD]


## Does the inventory hold everything the recipe asks for?
static func can_make(recipe: Dictionary, inventory: Inventory) -> bool:
	if inventory == null:
		return false
	for item: String in recipe["costs"]:
		if inventory.count_of(item) < int(recipe["costs"][item]):
			return false
	return inventory.can_add(recipe["out"], int(recipe["out_count"]))


## Spends the ingredients and adds the result. False, and nothing spent, if the
## inventory cannot cover it -- checked again here because the button's state is
## only as fresh as the last redraw.
static func make(recipe: Dictionary, inventory: Inventory) -> bool:
	if not can_make(recipe, inventory):
		return false
	for item: String in recipe["costs"]:
		_take(inventory, item, int(recipe["costs"][item]))
	inventory.add(recipe["out"], int(recipe["out_count"]))
	return true


## Pulls `amount` of an item out of wherever it is, emptying stacks in order.
static func _take(inventory: Inventory, item: String, amount: int) -> void:
	var left := amount
	for i in inventory.size():
		if left <= 0:
			break
		if inventory.item_at(i) != item:
			continue
		var taken := mini(inventory.count_at(i), left)
		inventory.remove_from_slot(i, taken)
		left -= taken
