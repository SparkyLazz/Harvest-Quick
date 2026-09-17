using System.Collections.Generic;
using Godot;

// Menggambar seluruh tanaman di ladang, dan tidak menyimpan apa pun tentang
// mereka. Tidak ada node per tanaman, tidak ada Dictionary<Vector2I, Sprite2D>:
// yang tergambar adalah fungsi murni dari isi grid pada saat _Draw dipanggil.
//
// Itulah yang menjamin render tidak bisa menyimpang dari simulasi. Wipe run
// cukup mengikat grid baru — tidak ada node lama yang tertinggal dan bocor.
// Jalur simulasi yang menghapus Crop tanpa memberi tahu siapa pun tidak punya
// siapa pun untuk diberi tahu.
public partial class CropLayer : Node2D
{
	// Hanya FarmGrid, bukan RunState. _Draw cuma perlu menyusuri tile; memberi
	// RunState berarti memberi kalender dan pemain sekalian, dan pintu yang
	// tidak dibutuhkan sebaiknya tidak ada.
	private FarmGrid _grid;

	private static readonly HashSet<CropType> WarnedTypes = new HashSet<CropType>();

	public void Bind(FarmGrid grid)
	{
		_grid = grid;
		QueueRedraw();
	}

	public override void _Draw()
	{
		// Belum diikat: menggambar ladang kosong, bukan crash.
		if (_grid is null) return;

		// Baris di luar, kolom di dalam. Baris bawah digambar belakangan, jadi
		// tanaman tinggi menutupi tanaman di belakangnya dan bukan sebaliknya.
		for (int y = 0; y < _grid.GridSize; y++)
		{
			for (int x = 0; x < _grid.GridSize; x++)
			{
				var cell = new Vector2I(x, y);
				if (_grid.GetTile(cell).Occupant is Crop crop) DrawCrop(cell, crop);
			}
		}
	}

	private void DrawCrop(Vector2I cell, Crop crop)
	{
		if (!GameConfig.CropArt.TryGetValue(crop.Type, out var art))
		{
			if (WarnedTypes.Add(crop.Type))
			{
				GD.PushWarning($"CropType '{crop.Type.Name}' tidak punya entri di GameConfig.CropArt, jadi tidak digambar.");
			}
			return;
		}

		// Kolom adalah tahap tumbuh, baris adalah jenisnya. Keduanya datang dari
		// CropArt, jadi di sini tidak ada satu pun angka tentang lembarnya.
		var frame = art.FrameForStage(crop.GrowthStage, crop.Type.GrowthStages);
		var source = new Rect2(
			frame * GameConfig.TileSize,
			art.SourceRow * GameConfig.TileSize,
			art.FrameSize.X,
			art.FrameSize.Y);

		// Dasar tanaman menempel di dasar selnya dan sisanya menjulur ke atas —
		// itu sebabnya frame 16x32 boleh ada, dan satu-satunya yang memakainya
		// adalah jagung di dua tahap terakhirnya.
		var origin = new Vector2(
			cell.X * GameConfig.TileSize,
			(cell.Y + 1) * GameConfig.TileSize - art.FrameSize.Y);

		DrawTextureRectRegion(GameConfig.CropSheet, new Rect2(origin, art.FrameSize), source);
	}
}
