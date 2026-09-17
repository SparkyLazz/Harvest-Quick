# Reads the ground sheets' alpha and prints, per 16x16 cell, which of its eight
# neighbours the artwork says the terrain continues into. Run it headless:
#
#   godot --headless --script res://Tools/probe_ground.gd
#
# It exists because the peering bits in a Godot terrain set have to agree with
# what is actually drawn, and a blob sheet has 47 cells whose shapes are easy to
# mis-assign by eye. Deriving them from the pixels is the only version that
# cannot disagree with the art.
extends SceneTree

const CELL := 16

const SHEETS := [
	"res://Assets/Sprout Lands - Sprites - premium pack/Tilesets/ground tiles/Old tiles/Tilled_Dirt.png",
	"res://Assets/Sprout Lands - Sprites - premium pack/Tilesets/ground tiles/Old tiles/Grass.png",
	"res://Assets/Sprout Lands - Sprites - premium pack/Tilesets/ground tiles/New tiles/Darker_Grass_Tiles_v2.png",
]

func _init() -> void:
	for path in SHEETS:
		_probe(path)
	quit()

func _probe(path: String) -> void:
	var image := Image.load_from_file(path)
	if image == null:
		print("MISSING: ", path)
		return

	var cols := image.get_width() / CELL
	var rows := image.get_height() / CELL
	print("\n=== ", path.get_file(), "  ", cols, " x ", rows, " cells ===")

	for r in range(rows):
		var line := ""
		for c in range(cols):
			line += _signature(image, c, r) + " "
		print("r%2d: %s" % [r, line])

# Nine probes in a 3x3: the four corners, the four side midpoints and the
# centre, one pixel inside the cell so the terrain's own outline is not mistaken
# for empty space. Printed as centre-then-eight so a cell reads at a glance:
# "O" means the centre is drawn at all, and each surrounding slot says whether
# the sheet keeps drawing in that direction.
func _signature(image: Image, c: int, r: int) -> String:
	var x0 := c * CELL
	var y0 := r * CELL
	var lo := 1
	var mid := CELL / 2
	var hi := CELL - 2

	if not _solid(image, x0 + mid, y0 + mid):
		return "...|...|..."

	var s := ""
	for py in [lo, mid, hi]:
		for px in [lo, mid, hi]:
			s += "#" if _solid(image, x0 + px, y0 + py) else "."
		s += "|"

	return s.substr(0, s.length() - 1)

func _solid(image: Image, x: int, y: int) -> bool:
	return image.get_pixel(x, y).a > 0.03
