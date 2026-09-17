using System.Collections.Generic;
using Godot;

// Satu sel di tileset: sumber mana, petak mana di dalamnya. Dua angka yang
// tidak pernah berguna sendiri-sendiri, jadi mereka satu nilai.
// readonly record struct, bukan tuple (int, Vector2I): tipe bernama ini muncul
// di signature dan di out-parameter, sedangkan nama field sebuah tuple harus
// ditulis ulang di tiap tempat dan tidak ada yang memaksa keduanya cocok.
// Struct berarti lookup tabel tidak mengalokasikan apa pun.
public readonly record struct TileArt(int SheetId, Vector2I AtlasCoords);

// Art satu jenis tanaman: baris mana di lembar tanaman, dan berapa frame
// pertumbuhan yang dipakai baris itu.
//
// Bentuknya berubah total saat paket aset diganti, dan perubahannya adalah
// penyederhanaan. Paket lama memberi satu tekstur per tanaman dengan tiga
// geometri berbeda — 16x16, 16x32, 18x32 — sehingga ukuran frame harus
// diturunkan dari tiap file supaya tidak berselisih dengannya. Paket Sprout
// Lands memberi satu lembar 5x15 sel: satu baris per tanaman, semua sel 16x16.
// Jadi yang perlu disimpan tinggal nomor baris.
//
// Yang tersisa dari kerumitan lama cuma satu hal, dan itu nyata: jagung. Dua
// tahap terakhirnya lebih tinggi dari satu tile dan menjulur ke baris di
// atasnya, yang di lembar ini adalah baris 0 dan sengaja dibiarkan kosong untuk
// itu. Tall menandainya, dan satu-satunya akibatnya adalah region sumber mulai
// satu baris lebih atas dan tingginya dua kali.
//
// GrowthFrames tetap terpisah dari jumlah tahap simulasi. Semua tanaman di
// lembar ini digambar dalam 4 frame (jagung 5), sedangkan labu matang dalam 8
// hari dan wortel dalam 3. Memetakan tahap ke frame adalah urusan sisi art,
// persis seperti sebelumnya.
public sealed class CropArt
{
	public CropArt(int sheetRow, int growthFrames, bool tall = false)
	{
		SheetRow = sheetRow;
		GrowthFrames = growthFrames;
		Tall = tall;
	}

	public int SheetRow { get; }
	public int GrowthFrames { get; }
	public bool Tall { get; }

	public Vector2I FrameSize => new Vector2I(
		GameConfig.TileSize, Tall ? GameConfig.TileSize * 2 : GameConfig.TileSize);

	// Baris tempat region sumber mulai. Tanaman tinggi mulai satu baris lebih
	// atas supaya bagian yang menjulur ikut terbaca.
	public int SourceRow => Tall ? SheetRow - 1 : SheetRow;

	// Tahap tumbuh disebar rata ke rentang frame pertumbuhan. Tahap terakhir
	// selalu mendarat di frame matang, berapa pun jumlah tahap jenis ini —
	// itulah gunanya pemetaan tinggal di sisi art: simulasi tidak perlu tahu
	// bahwa labu 8 hari dan wortel 3 hari memakai jumlah frame yang sama.
	public int FrameForStage(int stage, int growthStages)
	{
		if (growthStages <= 1) return GrowthFrames - 1;
		return Mathf.Clamp(stage * (GrowthFrames - 1) / (growthStages - 1), 0, GrowthFrames - 1);
	}
}

public static class GameConfig
{
	public const int TileSize = 16;
	public const float HalfTileSize = (float)TileSize / 2;

	// Karakter Sprout Lands digambar 16x16 di tengah kanvas 48x48. Frame-nya
	// yang 48, bukan gambarnya — itu ruang untuk animasi mengayun alat. Sprite
	// 48x48 yang dipusatkan di tile 16x16 sudah duduk benar tanpa offset, jadi
	// PlayerVisualOffsetY yang dulu ada di sini tidak lagi diperlukan dan sudah
	// dicabut: paket lama memakai sprite 32x32 yang berpijak di dasar selnya.
	public const int PlayerFrameSize = 48;

	// Lama animasi satu langkah antar-tile.
	public const float StepDuration = 0.12f;

	// Source id di Assets/Tilemap/Tilemap.tres, ditulis tangan di editor Godot.
	// Angka-angka ini dibaca dari file itu, bukan ditebak — Tools/dump_tileset.gd
	// mencetaknya, dan itu yang harus dijalankan lebih dulu kalau tileset diubah.
	public const int SoilSheetId = 0;
	public const int GrassSheetId = 1;
	public const int DarkerSheetId = 2;
	public const int BushSheetId = 3;
	public const int WaterSheetId = 4;

	// Satu terrain set berisi empat terrain, dan satu itulah yang benar: tanah,
	// rumput, rumput gelap dan semak semuanya saling bertetangga, jadi mereka
	// harus bisa saling melihat saat memilih tile. Dua set akan membuat tiap
	// wilayah buta terhadap yang lain dan menggambar tepi ke ruang kosong.
	public const int GroundTerrainSet = 0;
	public const int SoilTerrain = 0;
	public const int GrassTerrain = 1;
	public const int DarkerTerrain = 2;
	public const int BushTerrain = 3;

	// Pagar punya terrain set sendiri, dan memang harus: pagar tidak melebur ke
	// rumput atau ke tanah, dia cuma menyambung ke pagar. Satu set berisi satu
	// terrain adalah bentuk yang tepat untuk sesuatu yang hanya bertetangga
	// dengan dirinya sendiri.
	public const int FenceTerrainSet = 1;
	public const int FenceTerrain = 0;

	// Laut: satu tile beranimasi, diulang ke seluruh peta sebagai dasar paling
	// bawah. Tanpa terrain, karena air tidak punya tepi di sini — pulaunya yang
	// menggambar pantai, dari atas.
	public static readonly TileArt WaterArt =
		new TileArt(WaterSheetId, new Vector2I(0, 0));

	// Tanah yang siap ditanami, di luar blob autotile dan memang harus di luar:
	// tile blob menggambar tepi, dan petak yang baru dicangkul di tengah ladang
	// tidak punya tepi untuk digambar. Tiga varian, dipilih dari posisinya
	// sendiri supaya satu petak besar tanah garapan tidak jadi bidang rata.
	//
	// Koordinatnya aturan, bukan selera: di lembar Soil_Ground_Tiles hanya baris
	// 5 dan 6 yang berisi tanah polos tanpa transisi, dan (0,5)..(2,5) adalah
	// yang berbintik kerikil.
	public static readonly IReadOnlyList<Vector2I> PlantableSoil = new[]
	{
		new Vector2I(0, 5),
		new Vector2I(1, 5),
		new Vector2I(2, 5),
	};

	// Varian tanah garapan untuk satu petak, dipilih dari koordinatnya sendiri.
	// Fungsi dari posisi dan bukan acak, jadi menggambar ulang petak yang sama
	// selalu memberi gambar yang sama — tanpa itu, tiap kali RenderSoil jalan
	// seluruh ladang akan berkedip ke pola bintik yang berbeda.
	public static Vector2I PlantableSoilAt(Vector2I cell)
	{
		var hash = (cell.X * 73856093) ^ (cell.Y * 19349663);
		return PlantableSoil[Mathf.Abs(hash) % PlantableSoil.Count];
	}

	// Satu-satunya tempat yang tahu sprite mana menjadi gambar mana.
	//
	// Kosong, dan itu bukan kelalaian: tileset yang sekarang memuat lima sumber
	// — tanah, rumput, rumput gelap, semak, air — dan tidak satu pun berisi batu
	// atau kayu. Lembar aslinya ada di paket ("Mushrooms, Flowers, Stones" dan
	// "Trees, stumps and bushes"), tapi belum didaftarkan sebagai source di
	// Tilemap.tres, jadi tidak ada koordinat yang bisa disebut di sini.
	//
	// Belum ada yang menempatkan batu atau kayu, jadi tabel kosong tidak
	// menghilangkan apa pun hari ini. Yang perlu terjadi sebelum 4.2: dua source
	// itu ditambahkan ke tileset, lalu dua barisnya ditulis di sini.
	// RenderObjects sudah memperingatkan sekali per sprite kalau ada occupant
	// yang tidak punya entri, jadi kelupaan ini akan bersuara, bukan diam.
	public static readonly IReadOnlyDictionary<TileSprite, TileArt> ObjectArt =
		new Dictionary<TileSprite, TileArt>();

	// Lembar tanaman: satu tekstur untuk semuanya, 5 kolom x 15 baris sel 16x16.
	// Dimuat sekali di sini, bukan sekali per jenis, karena memang satu file.
	public static readonly Texture2D CropSheet = GD.Load<Texture2D>(
		"res://Assets/Sprout Lands - Sprites - premium pack/Objects/Farming Plants.png");

	// Ikon benih dan hasil panen, 2 kolom x 15 baris: kolom 0 kantong benih,
	// kolom 1 hasilnya. Barisnya sama dengan lembar tanaman, jadi satu nomor
	// baris di CropArt menjawab ketiganya.
	public static readonly Texture2D CropItemSheet = GD.Load<Texture2D>(
		"res://Assets/Sprout Lands - Sprites - premium pack/Objects/Items/Farming Plants items.png");

	// Satu entri per CropType, dan nomor barisnya dibaca dari lembar aslinya:
	// baris 1 jagung, 2 wortel, 5 terung, 9 labu. Empat dari empat belas yang
	// tersedia, dan tetap empat — harga benih, harga jual dan seluruh jadwal
	// utang dituning melawan empat kurva ini, jadi menambah jenis berarti
	// menuning ulang semuanya, bukan menambah satu baris di sini.
	public static readonly IReadOnlyDictionary<CropType, CropArt> CropArt =
		new Dictionary<CropType, CropArt>
		{
			//                                       baris  frame  tinggi
			[CropTypes.Carrot] = new CropArt(2, 4),
			[CropTypes.Corn] = new CropArt(1, 5, tall: true),
			[CropTypes.Pumpkin] = new CropArt(9, 4),
			[CropTypes.Eggplant] = new CropArt(5, 4),
		};

	// Satu entri per FarmAction. Di sini, bukan di Simulation, dengan alasan yang
	// sama seperti CropType.Name bukan teks tampilan: apa yang dibaca pemain
	// adalah art, dan Simulation tidak boleh tahu bahasanya. Bentuknya sama
	// dengan ObjectArt — tabel yang di-key enum, jadi menambah aksi berarti
	// menambah satu entri, bukan cabang baru di tempat menggambar.
	public static readonly IReadOnlyDictionary<FarmAction, string> ActionNames =
		new Dictionary<FarmAction, string>
		{
			[FarmAction.Till] = "Cangkul",
			[FarmAction.Plant] = "Tanam",
			[FarmAction.Harvest] = "Panen",
			[FarmAction.Buy] = "Beli",
		};

	// Ikon HUD. Region di lembar ikon paket UI, dipilih sekali di sini supaya
	// scene tidak menyimpan koordinat atlas di enam tempat.
	//
	// Semuanya varian berkontur putih, baris kedua tiap lembar, karena HUD
	// duduk di atas panel terang dan varian tanpa kontur hilang di dalamnya.
	public const string IconSheetPath =
		"res://Assets/Sprout Lands - UI Pack - Basic pack/Sprite sheets/Icons/All Icons.png";
	public const string SpecialIconSheetPath =
		"res://Assets/Sprout Lands - UI Pack - Basic pack/Sprite sheets/Icons/special icons/Special Icons.png";

	// Cursor memakai satu tekstur putih; warnanya yang membedakan kondisi.
	//
	// Tiga warna, bukan dua, dan yang ketiga ini bukan hiasan: sejak 4.1 ada
	// perbedaan yang harus terbaca antara tanah liar yang bisa dibeli dan tanah
	// liar yang tidak. Keduanya di luar ladang dan keduanya kembali sebagai tile
	// biasa, jadi satu-satunya yang bisa membedakannya di mata pemain adalah
	// warna cursor — dan yang menentukannya tetap AvailableAction, bukan
	// perhitungan kedua di sisi tampilan.
	public static readonly Color CursorOwnedTint = new Color(1f, 1f, 1f);
	public static readonly Color CursorBuyableTint = new Color(0.55f, 0.95f, 0.55f);
	public static readonly Color CursorUnownedTint = new Color(1f, 0.42f, 0.35f);
}
