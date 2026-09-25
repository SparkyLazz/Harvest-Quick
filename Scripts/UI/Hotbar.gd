class_name Hotbar
extends CanvasLayer

## Inventory hotbar: a row of slots on a stretchable wooden bar, with a
## four-corner cursor marking the selected slot.
##
## The bar art is a single 110x29 panel drawn as a [NinePatchRect], so the
## corners and edges keep their hand-drawn pixels while the middle repeats
## to whatever width the row needs. Change [member slot_count] and the bar
## resizes around it; nothing has to be redrawn.
##
## Slots come in two hand-drawn sizes. The selected one wears the larger
## art and the rest wear the smaller, and every slot sits centred in a cell
## the size of the larger one, so the row's spacing never shifts. Changing
## the selection swaps both textures at once and then tweens their scale
## from the size they just left back to 1, which reads as a grow and a
## shrink while leaving both resting states on native, unscaled pixels.
##
## Slots are built in [method _ready] rather than authored in the scene, so
## the count stays a single number instead of nine nodes to keep in step.

## Emitted when a different slot becomes the selected one.
signal slot_selected(index: int)

@export_group("Layout")
## How many slots the bar holds.
@export_range(1, 20) var slot_count: int = 9:
	set(value):
		slot_count = maxi(value, 1)
		if is_node_ready():
			_rebuild()
## Gap between neighbouring slot cells, in panel pixels.
@export var slot_gap: int = 2:
	set(value):
		slot_gap = maxi(value, 0)
		if is_node_ready():
			_rebuild()
## Space between the bar's outer edge and the row of slots, left and right.
##
## This is measured from the edge, not from the nine-patch margins: those
## describe how big the corner artwork is, which is wider than the drawn
## border, so adding the two together padded the frame out twice over. The
## default is the smallest that keeps the cursor — which overhangs its slot
## by two pixels — clear of the bar's rounded corners.
@export var padding: int = 8:
	set(value):
		padding = maxi(value, 0)
		if is_node_ready():
			_rebuild()
## Space above the row of slots. The bar's lip is drawn along its top, so
## this is larger than [member padding_bottom].
@export var padding_top: int = 6:
	set(value):
		padding_top = maxi(value, 0)
		if is_node_ready():
			_rebuild()
## Space below the row of slots.
@export var padding_bottom: int = 2:
	set(value):
		padding_bottom = maxi(value, 0)
		if is_node_ready():
			_rebuild()
## Gap between the bar and the bottom of the screen, in panel pixels.
## 0 sits the bar flush against the edge; the value is scaled along with
## the rest of the panel, so 1 here is [member Node2D.scale] screen pixels.
@export var bottom_margin: int = 0:
	set(value):
		bottom_margin = value
		if is_node_ready():
			_reposition()

@export_group("Art")
## Slot background for the slots that are not selected: the smaller of the
## two hand-drawn sizes.
@export var slot_texture: Texture2D
## Size an unselected slot is drawn at. The sheet only holds two slot
## sizes, so anything between them is this art scaled up, which spreads its
## pixels a little unevenly. Whole numbers keep the rect itself on the
## pixel grid. Zero on either axis draws the art at its own size.
@export var unselected_size: Vector2i = Vector2i(36, 38):
	set(value):
		unselected_size = value
		if is_node_ready():
			_rebuild()
## Slot background for the selected slot. Its size also sets the cell every
## slot is centred in, so it should be the larger of the two.
@export var selected_slot_texture: Texture2D
## Four-corner cursor drawn over the selected slot. Centred on the cell, so
## it may be larger than a slot.
@export var cursor_texture: Texture2D

@export_group("Motion")
## Seconds a slot takes to grow into, or shrink out of, being selected.
## 0 swaps the sizes with no travel.
@export var grow_duration: float = 0.12

@onready var _root: Node2D = $Root
@onready var _bar: NinePatchRect = $Root/Bar
@onready var _cursor: TextureRect = $Root/Bar/Cursor

var _slots: Array[TextureRect] = []
var _selected: int = 0
var _tween: Tween

## Index of the slot the cursor sits on.
var selected: int:
	get:
		return _selected
	set(value):
		select(value)

func _ready() -> void:
	_rebuild()
	get_viewport().size_changed.connect(_reposition)

## Moves the cursor to [param index], wrapping at either end so scrolling
## past the last slot comes back round to the first.
func select(index: int) -> void:
	if _slots.is_empty():
		return

	var wrapped := posmod(index, _slots.size())
	if wrapped == _selected:
		return

	var previous := _selected
	_selected = wrapped
	_dress_slot(previous, false)
	_dress_slot(_selected, true)
	_place_cursor()

	if grow_duration > 0.0:
		_animate([_slots[previous], _slots[_selected], _cursor])
	else:
		_settle([_slots[previous], _slots[_selected], _cursor])

	slot_selected.emit(_selected)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# KEY_1..KEY_9 are consecutive, so digit N picks slot N - 1.
		var digit: int = event.keycode - KEY_1
		if digit >= 0 and digit < mini(_slots.size(), 9):
			select(digit)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select(_selected + 1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select(_selected - 1)
			get_viewport().set_input_as_handled()

# --- Motion ------------------------------------------------------------

## Scales each node from wherever [method _dress_slot] parked it back to
## its own size. The textures have already been swapped, so starting from
## the ratio of the old size to the new one turns the swap into travel.
func _animate(nodes: Array) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()

	_tween = create_tween().set_parallel()
	for node in nodes:
		var rect := node as TextureRect
		if rect == null:
			continue
		_tween.tween_property(rect, "scale", Vector2.ONE, grow_duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _settle(nodes: Array) -> void:
	for node in nodes:
		var rect := node as TextureRect
		if rect != null:
			rect.scale = Vector2.ONE

## Gives slot [param index] the art for its new state and parks it at the
## size it is leaving, so the tween has somewhere to travel from.
func _dress_slot(index: int, is_selected: bool) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot := _slots[index]
	var was := slot.size
	slot.texture = selected_slot_texture if is_selected else slot_texture
	_fit(slot, Vector2.ZERO if is_selected else _unselected_size())
	_centre_in_cell(slot, index)
	if was.x > 0.0 and was.y > 0.0 and slot.size.x > 0.0 and slot.size.y > 0.0:
		slot.scale = was / slot.size

# --- Layout ------------------------------------------------------------

func _rebuild() -> void:
	for slot in _slots:
		slot.queue_free()
	_slots.clear()

	if slot_texture == null or selected_slot_texture == null:
		push_warning("Hotbar: slot_texture and selected_slot_texture must both be set; the bar will be empty.")
		return

	_selected = clampi(_selected, 0, slot_count - 1)
	for i in slot_count:
		var slot := TextureRect.new()
		var is_selected := i == _selected
		slot.texture = selected_slot_texture if is_selected else slot_texture
		_fit(slot, Vector2.ZERO if is_selected else _unselected_size())
		_bar.add_child(slot)
		# Ahead of the cursor in the tree would draw over it, so put every
		# slot behind the cursor node that the scene already holds.
		_bar.move_child(slot, _cursor.get_index())
		_slots.append(slot)
		_centre_in_cell(slot, i)

	var cell := _cell_size()
	var row_width := slot_count * cell.x + maxi(slot_count - 1, 0) * slot_gap
	_bar.size = Vector2(
		padding + row_width + padding,
		padding_top + cell.y + padding_bottom)

	_place_cursor()
	_settle(_slots)
	_settle([_cursor])
	_reposition()

## Every slot occupies a cell big enough for the larger of the two states,
## so the row's spacing does not shift when a slot grows or shrinks.
func _cell_size() -> Vector2:
	if selected_slot_texture == null:
		return Vector2.ZERO
	return selected_slot_texture.get_size().max(_unselected_size())

## Size an unselected slot is drawn at. [member unselected_size] overrides
## the art's own size; a zero or negative axis falls back to it.
func _unselected_size() -> Vector2:
	var native: Vector2 = slot_texture.get_size() if slot_texture != null else Vector2.ZERO
	if unselected_size.x <= 0 or unselected_size.y <= 0:
		return native
	return Vector2(unselected_size)

## Top-left of cell [param i] inside the bar.
func _cell_origin(i: int) -> Vector2:
	return Vector2(
		padding + i * (_cell_size().x + slot_gap),
		padding_top)

func _fit(rect: TextureRect, drawn_size: Vector2 = Vector2.ZERO) -> void:
	var native: Vector2 = rect.texture.get_size() if rect.texture != null else Vector2.ZERO
	rect.size = drawn_size if drawn_size.x > 0.0 and drawn_size.y > 0.0 else native
	# Scale has to work out from the middle, or a growing slot would push
	# itself down and to the right instead of swelling in place.
	rect.pivot_offset = rect.size * 0.5

func _centre_in_cell(rect: TextureRect, i: int) -> void:
	# Round, so a slot whose size is an odd number of pixels away from the
	# cell still lands on whole pixels instead of straddling half of one.
	rect.position = (_cell_origin(i) + (_cell_size() - rect.size) * 0.5).round()

func _place_cursor() -> void:
	if cursor_texture == null or _slots.is_empty():
		_cursor.visible = false
		return

	_cursor.texture = cursor_texture
	_cursor.visible = true
	_fit(_cursor)
	_centre_in_cell(_cursor, _selected)
	# The cursor never changes texture, so it has no old size to start
	# from. Give it the slot's ratio instead, and it swells in step with
	# the slot it just landed on.
	if slot_texture != null and selected_slot_texture != null:
		_cursor.scale = _unselected_size() / selected_slot_texture.get_size()

## Centres the bar along the bottom of the screen.
func _reposition() -> void:
	var view := get_viewport().get_visible_rect().size
	var bar := _bar.size * _root.scale
	_root.position = Vector2(
		roundf((view.x - bar.x) * 0.5),
		roundf(view.y - bar.y - bottom_margin * _root.scale.y))
