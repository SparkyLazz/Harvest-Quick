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
##
## It also owns the one rule that no single view could enforce on its own:
## a stack lifted onto the cursor has to end up back in a slot. The window
## can be shut on it, the mouse can be let go over the field beside it, and
## either way the items are the player's and must still be there afterwards.
## Both paths lead to [method Inventory.return_grab] from here.

var _hotbar: Hotbar
var _profile: ProfilePanel
var _panel: InventoryPanel

func _ready() -> void:
	_hotbar = _find("Hotbar") as Hotbar
	_profile = _find("ProfilePanel") as ProfilePanel
	_panel = _find("InventoryPanel") as InventoryPanel

	Inventory.changed.connect(_refresh)
	Inventory.selection_changed.connect(_on_inventory_selected)
	if _hotbar != null:
		_hotbar.selection_changed.connect(_on_hotbar_selected)
	if _panel != null:
		_panel.opened.connect(_on_panel_opened)
		_panel.closed.connect(_on_panel_closed)
		_on_panel_closed()

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

## A press out in the field, while a stack is being carried, puts it back.
##
## This is only half the rule. A press inside the window is swallowed by the
## window and never reaches the unhandled stage, so [InventoryPanel] answers
## that half itself — see its own backdrop handler. Here is for the other
## half: the player has the window open, a stack on the cursor, and clicks
## the farm beside it.
##
## Taking the press also keeps it from reaching the player, so putting a
## stack down is never also a swing at the ground.
func _unhandled_input(event: InputEvent) -> void:
	if not Inventory.has_grab():
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	Inventory.return_grab()
	get_viewport().set_input_as_handled()

func _on_panel_opened() -> void:
	if _hotbar != null:
		_hotbar.moves_items = true

func _on_panel_closed() -> void:
	if _hotbar != null:
		_hotbar.moves_items = false
	# Nothing may be left riding on the cursor once the window is gone —
	# there would be no way to put it down again.
	Inventory.return_grab()
