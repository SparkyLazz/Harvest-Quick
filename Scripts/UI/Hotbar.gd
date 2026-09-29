@tool
class_name Hotbar
extends Control

## The row of item slots that sits along the bottom of the screen.
##
## The panel behind it is one bar sprite cut three ways, so it stretches to
## whatever [member slot_count] asks for without the chamfered ends ever
## smearing. Its bottom edge is flat because the artist drew it that way —
## it is meant to run off the bottom of the screen, not float above it.
##
## Every slot is a real node in [code]Hotbar.tscn[/code]; this script never
## builds one. It swaps each slot's box between the two sizes the artist
## drew, puts the cursor on the chosen one, and runs the swell that sells
## the change.
##
## Selection is the only state here. What the slots contain comes from
## outside through [method set_item], so this works the same whether it is
## driven by a real inventory or by nothing at all.

## Emitted when the highlighted slot changes, with the new index.
signal selection_changed(index: int)
## Emitted when a slot is clicked, with its index.
signal slot_activated(index: int)

## The slot box at rest.
const BOX_REGION := Rect2(281, 73, 30, 32)
## The bigger box the artist drew for the slot under the cursor.
const BOX_SELECTED_REGION := Rect2(227, 162, 42, 44)

@export_group("Selection")
## Which slot the cursor is on.
@export var selected: int = 0:
	set(value):
		var clamped := _wrap(value)
		if clamped == selected:
			return
		var previous := selected
		selected = clamped
		_apply_selection(previous, true)
		selection_changed.emit(selected)
## Let the selection roll off one end onto the other.
@export var wrap_around: bool = true

@export_group("Motion")
## Seconds for a slot to swell under the cursor, or settle back.
@export var slot_pop: float = 0.22
## How far past its size the chosen slot swells before settling. 1.0 is no
## overshoot.
@export var pop_overshoot: float = 1.12

var _slots: Control
var _cursor: Control
var _boxes: Array[TextureRect] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _pop_tweens: Array[Tween] = []

func _ready() -> void:
	_ensure_nodes()
	_apply_selection(-1, false)
	if Engine.is_editor_hint():
		return
	set_process_unhandled_input(true)

## Finds the slot nodes. Instantiating the scene builds them all, so this
## works before [method _ready] has run — which matters, because a caller
## restoring saved state will reasonably set [member selected] or call
## [method set_item] on the line after [code]instantiate()[/code].
func _ensure_nodes() -> void:
	if _slots != null:
		return
	_slots = get_node_or_null("Slots")
	_cursor = get_node_or_null("Cursor")
	if _slots != null:
		_collect()

## How many slots the scene actually holds.
func slot_count() -> int:
	_ensure_nodes()
	return _slots.get_child_count() if _slots != null else 0

## Puts [param texture] in slot [param index], with [param count] written in
## the corner when it is above one. A null texture empties the slot.
func set_item(index: int, texture: Texture2D, count: int = 1) -> void:
	_ensure_nodes()
	if index < 0 or index >= _icons.size():
		return
	_icons[index].texture = texture
	_counts[index].text = str(count) if texture != null and count > 1 else ""

## Empties every slot.
func clear_items() -> void:
	for i in _icons.size():
		set_item(i, null)

## Moves the cursor [param step] slots along.
func step_selection(step: int) -> void:
	selected = selected + step

func _collect() -> void:
	_boxes.clear()
	_icons.clear()
	_counts.clear()
	_pop_tweens.clear()
	for slot in _slots.get_children():
		_boxes.append(slot.get_node("Box"))
		_icons.append(slot.get_node("Icon"))
		_counts.append(slot.get_node("Count"))
		_pop_tweens.append(null)

func _wrap(value: int) -> int:
	var count: int = slot_count()
	if count <= 0:
		return 0
	if wrap_around:
		return posmod(value, count)
	return clampi(value, 0, count - 1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		if key >= KEY_1 and key <= KEY_9:
			var index := key - KEY_1
			if index < slot_count():
				selected = index
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step_selection(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step_selection(-1)
			get_viewport().set_input_as_handled()

## Puts the cursor and the two affected slots where they belong. [param
## previous] of -1 means "settle everything", which is what start-up wants.
func _apply_selection(previous: int, animate: bool) -> void:
	_ensure_nodes()
	if _slots == null or _boxes.is_empty():
		return
	# Tweens need the node in the tree, so anything before _ready settles
	# straight away.
	var instant := not animate or Engine.is_editor_hint() or not is_node_ready()
	for i in _boxes.size():
		if i == selected or i == previous or previous < 0:
			_set_box(i, i == selected, instant)
		# The chosen slot overlaps its neighbours, so it has to draw over
		# them. Lifting it by z_index rather than reordering the children
		# keeps every slot at the index its contents are filed under.
		(_slots.get_child(i) as CanvasItem).z_index = 1 if i == selected else 0
	_move_cursor()

func _set_box(index: int, is_selected: bool, instant: bool) -> void:
	var box := _boxes[index]
	var region := BOX_SELECTED_REGION if is_selected else BOX_REGION
	var atlas := box.texture as AtlasTexture
	if atlas == null:
		atlas = AtlasTexture.new()
		atlas.atlas = _shared_atlas()
		box.texture = atlas
	atlas.region = region

	var slot := _slots.get_child(index) as Control
	box.size = region.size
	box.position = slot.pivot_offset - region.size * 0.5

	var tween: Tween = _pop_tweens[index]
	if tween != null:
		tween.kill()
		_pop_tweens[index] = null
	if instant or slot_pop <= 0.0:
		slot.scale = Vector2.ONE
		return
	# Swell from the size it was, so growing and shrinking both read.
	slot.scale = Vector2.ONE * (0.82 if is_selected else 1.1)
	var pop := create_tween()
	pop.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_selected and pop_overshoot > 1.0:
		pop.tween_property(slot, "scale", Vector2.ONE * pop_overshoot, slot_pop * 0.5)
		pop.tween_property(slot, "scale", Vector2.ONE, slot_pop * 0.5)
	else:
		pop.tween_property(slot, "scale", Vector2.ONE, slot_pop)
	_pop_tweens[index] = pop

func _shared_atlas() -> Texture2D:
	# Every box in the scene already points at the sheet; borrow it so a
	# slot built without a texture still lands on the right image.
	for box in _boxes:
		var atlas := box.texture as AtlasTexture
		if atlas != null and atlas.atlas != null:
			return atlas.atlas
	return null

## The cursor does not animate — it is simply on whichever slot is chosen,
## and it gets there the moment the choice is made. The swell of the slot
## underneath is what carries the change.
##
## Each slot's [member Control.pivot_offset] is where its box is centred,
## which is not the middle of the slot's rectangle: the panel's top border
## eats a few pixels, so the contents sit lower than centre. Reading the
## pivot keeps the boxes, the cursor and the swell all agreeing on one
## point, and keeps that point in the scene where it can be nudged.
func _move_cursor() -> void:
	if _cursor == null:
		return
	var slot := _slots.get_child(selected) as Control
	_cursor.position = slot.position + slot.pivot_offset - _cursor.size * 0.5
