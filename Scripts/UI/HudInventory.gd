extends CanvasLayer

## Keeps the HUD showing what the player is actually carrying.
##
## The hotbar and the tool row inside the inventory window are both built to
## be told what to show and nothing more — neither reads the satchel, and
## neither knows the other exists. This sits above them and does the telling,
## so the two stay in step without either growing a dependency it was
## deliberately written without.
##
## It finds them rather than being pointed at them, so moving either one
## around the HUD does not leave a stale path behind. Finding nothing is not
## an error: a HUD with no hotbar in it simply has nothing to keep in step.

var _hotbar: Hotbar
var _profile: ProfilePanel

func _ready() -> void:
	_hotbar = _find("Hotbar") as Hotbar
	_profile = _find("ProfilePanel") as ProfilePanel

	Inventory.changed.connect(_refresh)
	Inventory.selection_changed.connect(_on_inventory_selected)
	if _hotbar != null:
		_hotbar.selection_changed.connect(_on_hotbar_selected)

	# The satchel filled itself before the farm loaded, so its opening
	# announcement is long gone. Ask once instead of waiting for the next one.
	_refresh()
	_on_inventory_selected(Inventory.selected)

## The first node of [param type] anywhere under the HUD, or null. Nodes
## inside an instanced scene belong to that scene rather than to this one,
## so the search has to reach past ownership to see them at all.
func _find(type: String) -> Node:
	var found := find_children("*", type, true, false)
	return found.front() if not found.is_empty() else null

func _refresh() -> void:
	if _hotbar != null:
		for i in _hotbar.slot_count():
			var item: ItemData = Inventory.item_at(i)
			_hotbar.set_item(i, item.icon if item != null else null, Inventory.count_at(i))
	if _profile != null:
		for i in _profile.tool_count():
			var item: ItemData = Inventory.item_at(i)
			_profile.set_tool(i, item.icon if item != null else null)

func _on_inventory_selected(index: int) -> void:
	if _hotbar != null:
		_hotbar.selected = index

func _on_hotbar_selected(index: int) -> void:
	Inventory.selected = index
