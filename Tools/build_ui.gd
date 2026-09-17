# Generates the two UI textures the pack does not ship in a usable form.
#
#   godot --headless --path . --script res://Tools/build_ui.gd
#
# Both are derived rather than drawn, so neither can drift from the pack's
# palette when the pack is updated.
extends SceneTree

const UI := "res://Assets/Sprout Lands - UI Pack - Basic pack/"
const OUT_DIR := "res://Assets/UI/"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_panel()
	_cursor()
	quit()

# A nine-patch panel for the HUD, cut from the pack's dialog box.
#
# The pack's box is a speech bubble: it has a tail on the left edge, three
# quarters of the way down. A nine-patch repeats its edge runs to stretch, so
# that tail would be tiled down the whole left side of the readout. Rather than
# hand-draw a replacement, the clean right edge is mirrored onto the left — same
# pixels, same palette, no tail, and it stays correct if the pack's box is
# redrawn.
func _panel() -> void:
	var src := Image.load_from_file(UI + "Sprite sheets/Dialouge UI/dialog box.png")
	if src == null:
		print("MISSING dialog box.png")
		return

	var size := src.get_width()
	var out := Image.create(size, size, false, src.get_format())

	# Right half copied as-is, left half taken from the right and flipped. The
	# box is symmetrical apart from the tail, so the seam down the middle lands
	# on flat fill and is invisible.
	var half := size / 2
	for y in range(size):
		for x in range(size):
			var read_x := x if x >= half else size - 1 - x
			out.set_pixel(x, y, src.get_pixel(read_x, y))

	var err := out.save_png(ProjectSettings.globalize_path(OUT_DIR + "panel.png"))
	print("panel.png  ", size, "x", size, "  err ", err,
		"   (nine-patch margin 16 on every side)")

# The tile cursor. Corner brackets rather than a full outline: a closed box on a
# 16px tile hides the tile's own edge pixels, which is exactly where the tilled
# soil transition is drawn, so the cursor would cover the thing the player is
# aiming at. Brackets leave the middle of every edge clear.
#
# Pure white, because Main tints it: white for owned, green for land on sale,
# red for out of reach. One texture, three meanings, and the meaning is decided
# by AvailableAction rather than by three textures.
func _cursor() -> void:
	const SIZE := 16
	const ARM := 5

	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 1, 1, 0))

	for i in range(ARM):
		for corner in [Vector2i(0, 0), Vector2i(SIZE - 1, 0), Vector2i(0, SIZE - 1), Vector2i(SIZE - 1, SIZE - 1)]:
			var sx := -1 if corner.x > 0 else 1
			var sy := -1 if corner.y > 0 else 1
			out.set_pixel(corner.x + sx * i, corner.y, Color.WHITE)
			out.set_pixel(corner.x, corner.y + sy * i, Color.WHITE)

	var err := out.save_png(ProjectSettings.globalize_path(OUT_DIR + "cursor.png"))
	print("cursor.png ", SIZE, "x", SIZE, "  err ", err)
