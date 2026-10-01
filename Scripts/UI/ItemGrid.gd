@tool
class_name ItemGrid
extends GridContainer

## The backpack: the grid of slots on the inventory window's last tab.
##
## It shows the satchel from [member first_slot] onwards, which is the far
## side of the hotbar. The hotbar's own slots are left out on purpose — they
## are already on screen along the bottom, and a player looking at two copies
## of the same nine slots would reasonably wonder which copy they were moving
## things out of. Shift-click is how a stack crosses between the two, and
## while the window is open the real hotbar takes clicks as well, so there is
## still a way to put something in one particular slot.
##
## A [GridContainer] rather than a plain [Control] because it has to be
## measured: it sits in a [ScrollContainer], which can only know how far
## there is to scroll by asking its content how tall it is, and a Control
## would answer with its own size rather than its children's.
##
## Unlike [Hotbar], this builds its own slots. The hotbar's count is a
## decision about the screen and belongs in its scene; this one's is however
## many slots the satchel turns out to have, and a grid that could disagree
## with [constant Inventory.SLOT_COUNT] would be a grid with slots leading
## nowhere.
##
## It knows nothing about what a click means — that is all
## [method Inventory.click_slot]. What it does is work out which slot was
## clicked and with which button, which is the only part of it that is about
## being a grid.

## Emitted when a slot is clicked, with its index in the satchel, after the
## satchel has already answered the click.
signal slot_clicked(index: int)

## The slot box the artist drew, on the inventory sheet.
const BOX_REGION := Rect2(281, 73, 30, 32)
## Where the icon sits inside that box, and how big it is drawn.
const ICON_INSET := Vector2(4.0, 4.0)
const ICON_SIZE := Vector2(22.0, 22.0)

## The sheet the slot box is cut from.
@export var sheet: Texture2D:
	set(value):
		sheet = value
		_rebuild()

## The font the stack counts are written in.
@export var font: Font:
	set(value):
		font = value
		_rebuild()

## Colour of the stack counts.
@export var count_colour: Color = Color(0.301961, 0.207843, 0.192157):
	set(value):
		count_colour = value
		_rebuild()

## Which satchel slot the grid starts at. The hotbar sits below it, on the
## screen rather than in the window.
@export var first_slot: int = 9:
	set(value):
		first_slot = maxi(value, 0)
		_rebuild()

@export_group("Motion")
## Seconds a slot takes to settle back after being clicked. Zero is no pop.
@export var click_pop: float = 0.18

var _boxes: Array[TextureRect] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _pops: Array[Tween] = []

func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	Inventory.changed.connect(refresh)
	refresh()

## How many slots the grid holds.
func slot_count() -> int:
	return maxi(Inventory.SLOT_COUNT - first_slot, 0)

## Redraws every slot from the satchel.
func refresh() -> void:
	if _icons.is_empty():
		return
	for i in _icons.size():
		var index := first_slot + i
		var item: ItemData = Inventory.item_at(index)
		var count: int = Inventory.count_at(index)
		_icons[i].texture = item.icon if item != null else null
		_counts[i].text = str(count) if item != null and count > 1 else ""
		# The name is worth having somewhere, and the slot is already the
		# thing the mouse is resting on.
		_boxes[i].tooltip_text = item.display_name if item != null else ""

## Builds the slots. Called whenever something that changes their number or
## their look is set, so the grid can be dressed in the editor.
func _rebuild() -> void:
	if not is_node_ready():
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_boxes.clear()
	_icons.clear()
	_counts.clear()
	_pops.clear()
	for i in slot_count():
		_add_slot(i)
	if not Engine.is_editor_hint():
		refresh()

func _add_slot(i: int) -> void:
	var box := TextureRect.new()
	box.custom_minimum_size = BOX_REGION.size
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	if sheet != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = BOX_REGION
		box.texture = atlas
	# Scaled about the middle, so a clicked slot pops in place rather than
	# sliding off its own corner.
	box.pivot_offset = BOX_REGION.size * 0.5
	box.gui_input.connect(_on_slot_input.bind(i))
	add_child(box)

	var icon := TextureRect.new()
	icon.position = ICON_INSET
	icon.size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var count := Label.new()
	# Set where the hotbar sets its own counts — lower middle of the box
	# with a few pixels of margin, not down on the bottom bevel.
	count.position = Vector2(0.0, 14.0)
	count.size = Vector2(BOX_REGION.size.x - 4.0, 12.0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		count.add_theme_font_override("font", font)
	count.add_theme_font_size_override("font_size", 9)
	count.add_theme_color_override("font_color", count_colour)
	box.add_child(count)

	_boxes.append(box)
	_icons.append(icon)
	_counts.append(count)
	_pops.append(null)

## Turns a click on slot [param i] into a move, and lets the satchel decide
## what the move is.
##
## Shift is asked about first. It is the one modifier that changes which
## slots are involved rather than how many, so a shift-click that found
## somewhere to send the stack has already done the whole job and must not
## then also be read as picking it up.
func _on_slot_input(event: InputEvent, i: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	var left := button.button_index == MOUSE_BUTTON_LEFT
	var right := button.button_index == MOUSE_BUTTON_RIGHT
	if not left and not right:
		return

	var index := first_slot + i
	var moved := false
	if left and button.shift_pressed:
		moved = Inventory.quick_move(index)
	else:
		moved = Inventory.click_slot(index, left)

	# Taken either way. A click that moved nothing still landed on a slot,
	# and letting it through would have the window's backdrop read it as a
	# click on nothing and put the carried stack away.
	accept_event()
	if moved:
		_pop(i)
		slot_clicked.emit(index)

## A small squash as a slot is clicked, so a move that changed nothing
## visible — topping up a stack that was already nearly full — still shows
## that the click arrived.
func _pop(i: int) -> void:
	if click_pop <= 0.0 or i < 0 or i >= _boxes.size():
		return
	var tween: Tween = _pops[i]
	if tween != null:
		tween.kill()
	_boxes[i].scale = Vector2.ONE * 0.86
	var pop := create_tween()
	pop.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_boxes[i], "scale", Vector2.ONE, click_pop)
	_pops[i] = pop
