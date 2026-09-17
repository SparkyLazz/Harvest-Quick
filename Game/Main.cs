using System.Collections.Generic;
using System.Linq;
using Godot;

public partial class Main : Node
{
	// Lima lapisan, dari bawah ke atas. Susunannya bukan selera melainkan aturan
	// dunia ini, dan tiap lapisan menjawab satu pertanyaan tentang satu tile:
	//
	// WaterLayer  laut, beranimasi, mengisi seluruh peta sekali dan tidak pernah
	//             berubah. Yang menutupinya adalah pulau.
	// GroundLayer tanah pulau. Ini fondasinya, dan dia ada di bawah rumput —
	//             karena mencangkul bukan "mengubah tanah jadi tanah garapan"
	//             melainkan "mengupas rumput sampai tanahnya kelihatan".
	// DarkerLayer rumput gelap, menutupi seluruh pulau. Ini rupa tanah yang
	//             belum dibeli, dan sekaligus yang mengintip di tepi rumput
	//             terang karena lembar rumput itu berlapis dan tepinya tembus.
	// GrassLayer  rumput terang, hanya di petak yang sudah dibeli dan belum
	//             dicangkul. Tepinya yang tembus itulah batas ladang, digambar
	//             oleh art dan bukan oleh garis.
	// BushLayer   semak, hanya di petak yang belum dibeli. Membeli petak
	//             menghapus semaknya.
	//
	// Mencangkul menghapus dua lapisan sekaligus, rumput dan rumput gelap, dan
	// itu yang membuat tanah di bawahnya terlihat. Tidak ada "tile tanah
	// garapan" yang digambar di atas rumput; yang ada cuma rumput yang hilang.
	[Export]
	public TileMapLayer WaterLayer;
	[Export]
	public TileMapLayer GroundLayer;
	[Export]
	public TileMapLayer DarkerLayer;
	[Export]
	public TileMapLayer GrassLayer;
	[Export]
	public TileMapLayer BushLayer;
	[Export]
	public TileMapLayer FenceLayer;
	[Export]
	public TileMapLayer ObjectLayer;
	[Export]
	public CropLayer CropLayer;
	[Export]
	public AnimatedSprite2D PlayerSprite;
	[Export]
	public Sprite2D Cursor;

	// Anak dari Player, jadi dia mengikuti tanpa kode. Yang butuh kode cuma satu
	// hal, dan itu di StartRun: menghentikan gelincir pertamanya.
	[Export]
	public Camera2D Camera;

	[Export]
	public Label DateLabel;
	[Export]
	public Label GoldLabel;
	[Export]
	public Label BagLabel;
	[Export]
	public Label EnergyLabel;
	[Export]
	public Label DebtLabel;

	// Satu run, satu objek. Grid, player dan kalender tidak lagi berdiri
	// sendiri-sendiri di sini, jadi memulai run baru nanti cukup satu penugasan.
	private RunState _run;
	private bool _isMoving;

	// Sprite tanpa entri di tabel art tidak digambar. Itu nyaris selalu entri
	// yang lupa didaftarkan, bukan keadaan normal, jadi harus bersuara. Sekali
	// saja per sprite: 576 tile tidak boleh jadi 576 baris log.
	static readonly HashSet<TileSprite> WarnedSprites = new HashSet<TileSprite>();

	// Urutannya mengikuti enum Direction: Up, Down, Left, Right.
	static readonly StringName[] IdleAnimations =
		{ "idle_up", "idle_down", "idle_left", "idle_right" };
	static readonly StringName[] WalkAnimations =
		{ "walk_up", "walk_down", "walk_left", "walk_right" };

	// Satu tombol per jenis benih. Belum ada inventori atau pemilihan benih,
	// dan mengarang satu sekarang berarti menebak bentuk UI yang belum ada.
	// Tiga tombol cukup untuk menguji tiga kurva pertumbuhan.
	static readonly StringName[] PlantActions =
		{ "plant_1", "plant_2", "plant_3", "plant_4" };
	
	Vector2 GridToWorld(Vector2I gridPos)
	{
		var gridPosTile = gridPos * GameConfig.TileSize;
		return new Vector2(gridPosTile.X + GameConfig.HalfTileSize, gridPosTile.Y + GameConfig.HalfTileSize);
	}

	Vector2I WorldToGrid(Vector2 worldPos)
	{
		return new Vector2I(Mathf.FloorToInt(worldPos.X / GameConfig.TileSize), Mathf.FloorToInt(worldPos.Y / GameConfig.TileSize));
	}

	public override void _Ready()
	{
		StartRun();
	}

	// "Mulai run baru cukup satu penugasan" akhirnya ditagih. Dipanggil saat
	// start dan saat pemain menekan ulang setelah bangkrut.
	//
	// Pagar smoke-test Fase 2 yang dulu berdiri di sini sudah dicabut. Dia ada
	// supaya object layer punya sesuatu untuk digambar saat belum ada apa-apa,
	// dan sejak ladang menyusut ke 5x5 dia memakan satu dari 25 tile secara
	// permanen — 4% ladang, dan 4% yang tidak diketahui harness. Setiap angka
	// di Fase 3 dihitung untuk 25 tile; game mengirim 24.
	void StartRun()
	{
		_run = new RunState();
		_isMoving = false;

		// CropLayer membaca grid, tidak pernah memilikinya. Mengikat grid baru
		// di sini sudah cukup — tidak ada sisa run lama yang perlu dibersihkan
		// karena tidak ada yang disimpan.
		CropLayer.Bind(_run.Grid);

		RenderAll(_run.Grid);
		CropLayer.QueueRedraw();
		RenderPlayer(_run.Player);

		// Setelah pemain ditempatkan, bukan sebelumnya. Kamera adalah anak dari
		// Player dan pelicinnya menyimpan posisi sendiri, jadi tanpa baris ini
		// tiap run dibuka dengan kamera meluncur dari sudut peta ke ladang —
		// pemain melihat satu setengah detik laut sebelum melihat ladangnya.
		Camera?.ResetSmoothing();

		UpdateAnimation();
		UpdateCursor();
		UpdateFacingReadout();
		UpdateHud();

		// Satu baris konfigurasi tiap run dimulai. Bukan debug: angka-angka ini
		// yang dituning harness, dan sesi yang berjalan dengan angka lain dari
		// yang kamu kira adalah cara paling murah membuang satu playtest.
		GD.Print($"Run baru — {_run.Grid.OwnedSize.X}x{_run.Grid.OwnedSize.Y} = "
			+ $"{_run.Grid.OwnedTileCount} tile, gold {_run.Economy.Gold}, "
			+ $"energi {_run.Energy.Max}/hari, tanah {_run.Grid.LandPricePerTile}/tile, "
			+ $"utang {_run.Debt.Total} dalam {_run.Debt.Schedule.Count} pembayaran.");
	}

	// Label keempat, dan satu-satunya yang berubah saat pemain cuma berputar.
	// Itu sebabnya dia tidak ikut UpdateHud: tiga angka di sana berubah kalau
	// ada yang terjadi, yang ini berubah tiap langkah dan tiap belokan, persis
	// seperti cursor — dan dipanggil berdampingan dengannya karena keduanya
	// menjawab pertanyaan yang sama, "aku sedang menghadap apa".
	//
	// Biayanya harus terlihat sebelum ditekan. Alasannya identik dengan jadwal
	// utang yang wajib terlihat sejak hari 1: "energiku sisa 2, cangkul butuh 3"
	// hanya jadi keputusan kalau pemain tahu duluan. Kalau tidak, itu kejutan.
	//
	// AvailableAction yang menjawab aksi mana, bukan rangkaian if di sini. Kalau
	// readout menurunkan sendiri aturannya, dia bisa berselisih dengan cangkul.
	// Kata "Energi" sudah tidak ditulis: ikon baterai di sebelahnya yang
	// mengatakannya. Itu berlaku untuk gold dan tas juga di UpdateHud, dan
	// alasannya bukan kerapian — HUD sekarang duduk di atas panel selebar
	// readout-nya, dan lima baris yang masing-masing mulai dengan kata benda
	// membuat angkanya, satu-satunya yang benar-benar berubah, jadi yang paling
	// sulit ditemukan mata.
	void UpdateFacingReadout()
	{
		var energy = $"{_run.Energy.Current}/{_run.Energy.Max}";

		if (_run.Grid.AvailableAction(_run.Player.FacingPosition) is not FarmAction action)
		{
			EnergyLabel.Text = energy;
			return;
		}

		var cost = WorkCost.Of(action);
		var name = GameConfig.ActionNames[action];

		// Membeli punya dua harga, dan keduanya wajib terlihat sebelum ditekan
		// dengan alasan yang sama seperti jadwal utang: satu jalur bisa 5 tile
		// atau 8, dan "beli lahan atau simpan tunai untuk h27" hanya jadi
		// keputusan kalau angkanya ada di layar lebih dulu. Jumlah tile ikut
		// ditampilkan karena itu yang membuat harga bisa dibaca — 550 tidak
		// berarti apa-apa sampai pemain tahu itu lima tile.
		//
		// Angkanya datang dari strip yang sama yang akan dibebankan ke dompet,
		// bukan dari perkalian kedua di sini.
		var strip = action == FarmAction.Buy
			? _run.Grid.StripAt(_run.Player.FacingPosition)
			: null;

		var label = strip is LandStrip offer
			? $"{name} {offer.TileCount} tile   {cost} energi   {offer.Price} gold"
			: $"{name} {cost}";

		var affordable = _run.Energy.CanAfford(cost)
			&& (strip is not LandStrip priced || _run.Economy.CanAfford(priced.Price));

		// Terlalu lelah untuk aksi yang sedang dihadapi adalah keadaan yang
		// paling perlu dibaca, jadi dia yang paling jelas ditandai.
		EnergyLabel.Text = affordable
			? $"{energy}   {label}"
			: $"{energy}   {label}  (tidak cukup)";
	}

	// Tiga angka yang tidak bisa dibaca dari ladang, dan tiap satunya ada karena
	// sebuah keputusan bergantung padanya.
	//
	// Tanggal, karena tiap penanaman adalah taruhan pada sisa hari: tomat di
	// hari 4 masuk akal, tomat di hari 20 tidak pernah sempat matang lima kali.
	// Gold, karena benih dibayar dengannya. Isi tas, karena penjualan otomatis
	// saat tidur — pemain harus tahu berapa yang akan masuk sebelum memutuskan
	// tidur, bukan sesudahnya.
	//
	// Dipanggil dari tiga tempat yang benar-benar mengubahnya, bukan tiap frame.
	// Alasannya sama dengan aksi menggambar ulang satu lapisan dan bukan empat:
	// yang digambar ulang cuma yang berubah.
	//
	// Slot keempat, biaya aksi, menyusul di 3.6. VBox dipilih supaya menambahnya
	// satu node, bukan menata ulang.
	void UpdateHud()
	{
		DateLabel.Text = $"Bulan {_run.Calendar.Month}   Hari {_run.Calendar.Day}";
		GoldLabel.Text = $"{_run.Economy.Gold}";
		BagLabel.Text = $"{_run.Inventory.TotalValue}";

		// Terlihat sejak hari 1, dan itu syarat bukan hiasan. Keputusan paling
		// berharga dalam satu run adalah "sisakan berapa tunai", dan itu cuma
		// bisa diambil kalau pemain tahu kapan tagihan datang. Ditagih mendadak,
		// pemain yang bertani paling baik justru yang paling sering kering tunai
		// di tengah run — dia dihukum karena bermain bagus.
		// Seluruh kurva, bukan cuma pembayaran berikutnya. Syaratnya "jadwal
		// terlihat sejak hari 1", dan satu baris "Tagihan h6: 10" tidak
		// memenuhinya: pemain baru melihat h14 pada h11, terlambat untuk
		// merencanakan apa pun terhadapnya. Yang berikutnya diapit tanda supaya
		// tetap menonjol di antara tujuh yang lain.
		var runDay = _run.Calendar.RunDay;
		var next = _run.Debt.NextFrom(runDay);
		var curve = string.Join("  ", _run.Debt.Schedule.Select(p =>
			p.Day < runDay ? $"h{p.Day}:lunas"
			: next is Payment n && n.Day == p.Day ? $">h{p.Day}:{p.Amount}<"
			: $"h{p.Day}:{p.Amount}"));

		DebtLabel.Text = _run.Outcome switch
		{
			// Berapa kurangnya, bukan cuma bahwa kurang. RunState sengaja tidak
			// memotong apa pun saat gagal supaya angka ini masih ada untuk
			// dibaca.
			RunOutcome.Bankrupt =>
				$"BANGKRUT h{_run.Calendar.RunDay} — kurang {_run.Debt.AmountDueOn(_run.Calendar.RunDay) - _run.Economy.Gold}",
			_ => curve,
		};
	}

	// Satu-satunya tempat offset visual dipakai, supaya render awal dan tujuan
	// tween tidak bisa berbeda rumus.
	// Titik tengah tile, tanpa koreksi apa pun, dan itu berubah bersama paket
	// aset. Sprite lama 32x32 berpijak di dasar selnya, jadi dia butuh offset
	// setengah selisih tinggi dikurangi padding — satu rumus dengan tiga
	// konstanta yang harus benar bersamaan. Karakter Sprout Lands digambar 16x16
	// di tengah kanvas 48x48, jadi sprite yang dipusatkan di tengah tile sudah
	// duduk tepat di tile itu. Rumusnya hilang, dan bersamanya tiga konstanta.
	Vector2 SpriteAnchor(Vector2I gridPos)
	{
		return GridToWorld(gridPos);
	}

	void RenderPlayer(PlayerState player)
	{
		PlayerSprite.Position = SpriteAnchor(player.Position);
	}

	public override void _Process(double delta)
	{
		// Di atas gerbang IsOver, karena ini satu-satunya tombol yang harus
		// tetap menjawab setelah run berakhir.
		if (Input.IsActionJustPressed("restart"))
		{
			StartRun();
			return;
		}

		// Run yang sudah berakhir tidak menerima apa pun. Simulasi juga menolak
		// sendiri — keempat aksi dan AdvanceDay memeriksa IsOver — jadi ini bukan
		// satu-satunya penjaga. Gunanya di sini beda: supaya pemain tidak
		// menekan tombol yang diam, dan supaya layar berhenti di hari kekalahan
		// alih-alih terus hidup seolah masih ada yang bisa dilakukan.
		if (_run.IsOver) return;

		// Sengaja di atas gerbang _isMoving. Langkah yang ditolak di tepi ladang
		// tetap memutar Facing, dan sprite harus ikut berputar: arah hadap
		// adalah satu-satunya petunjuk tile mana yang sedang dituju pemain.
		UpdateAnimation();
		UpdateCursor();
		UpdateFacingReadout();

		// Sengaja di atas gerbang _isMoving juga. Cursor sudah menunjukkan tile
		// sasaran sepanjang langkah, jadi menelan tekanan tombol di tengah
		// animasi akan terasa seperti input yang hilang.
		// Tidak ada pemeriksaan apa pun di sini: boleh atau tidaknya mencangkul
		// dijawab simulasi, dan false berarti tidak ada yang perlu digambar.
		// Lewat _run, bukan _run.Player, sejak mencangkul memakan energi. Ketiga
		// aksi kini sama bentuknya, dan ketiganya menolak dengan cara yang sama.
		// Ketiga lapisan rumput digambar ulang, bukan satu sel, dan itu bukan
		// pemborosan melainkan syarat: satu petak yang kehilangan rumputnya
		// mengubah gambar tetangganya juga, karena tetangga itu baru saja jadi
		// tepi. Autotile tidak punya versi "satu sel saja" yang benar.
		if (Input.IsActionJustPressed("till") && _run.TryTill())
		{
			RefreshGrassNear(_run.Grid, new[] { _run.Player.FacingPosition });
		}

		// Aksi keempat, dan satu-satunya yang mengubah lebih dari satu tile
		// sekaligus — jadi satu-satunya yang menggambar ulang sebuah jalur, bukan
		// sebuah sel. Jalurnya datang dari TryBuyLand sendiri, bukan dihitung
		// lagi di sini: kalau layar menurunkan sendiri tile mana yang berpindah
		// tangan, dia bisa berselisih dengan ladang yang sebenarnya dibeli.
		//
		// RenderGrass dan bukan sel-sel jalurnya saja, dengan alasan yang sama
		// seperti mencangkul di atas: baris teratas ladang lama berhenti menjadi
		// tepi begitu ada jalur baru di atasnya, dan tile-nya harus ikut berganti.
		// Menggambar jalur baru sendirian akan meninggalkan garis tepi rumput
		// membelah ladang.
		//
		// Satu panggilan mengerjakan keduanya yang dijanjikan aturan dunia ini:
		// semak di jalur itu hilang, dan rumput gelapnya berganti jadi rumput
		// terang. Keduanya cuma akibat dari IsOwned yang sekarang menjawab ya.
		if (Input.IsActionJustPressed("buy_land") && _run.TryBuyLand(out var bought))
		{
			RefreshGrassNear(_run.Grid, bought.Positions());
			RenderFence(_run.Grid);

			UpdateHud();
			GD.Print($"Beli {bought.TileCount} tile seharga {bought.Price}. "
				+ $"Ladang {_run.Grid.OwnedSize.X}x{_run.Grid.OwnedSize.Y} = "
				+ $"{_run.Grid.OwnedTileCount} tile, gold {_run.Economy.Gold}.");
		}

		// Kebalikan dari mencangkul: sehari berganti bisa mengubah banyak tile
		// sekaligus karena semua tanaman tumbuh bersamaan, jadi di sini gambar
		// ulang penuh justru bentuk yang tepat.
		// HUD sudah menampilkan tanggal dan gold; GD.Print tetap ada karena dia
		// satu-satunya yang mencatat urutan kejadian, dan begitu tagihan masuk di
		// 3.3 urutan itu yang perlu dibaca, bukan angka akhirnya.
		// Catatan: ini juga di atas gerbang _isMoving, jadi hari bisa maju di
		// tengah animasi langkah. Sekarang aman — Tween tetap selesai dan posisi
		// simulasi sudah benar sebelum animasinya. Tapi begitu pergantian hari
		// punya konsekuensi berat (tagihan, kondisi kalah), gerbangnya kemungkinan
		// harus dipasang: tidur di tengah langkah bukan keadaan yang ingin diuji.
		if (Input.IsActionJustPressed("advance_day"))
		{
			_run.AdvanceDay();
			RenderAll(_run.Grid);
			CropLayer.QueueRedraw();
			UpdateHud();

			if (_run.IsOver)
			{
				GD.Print($"Run berakhir di hari {_run.Calendar.RunDay}: {_run.Outcome}. "
					+ $"Tagihan {_run.Debt.AmountDueOn(_run.Calendar.RunDay)}, gold {_run.Economy.Gold}.");
			}
			else
			{
				GD.Print($"Bulan {_run.Calendar.Month}, Hari {_run.Calendar.Day}. Gold {_run.Economy.Gold}.");
			}
		}

		// Lewat _run, bukan _run.Player: panen menyentuh grid dan inventori
		// sekaligus, dan hanya RunState yang memegang keduanya. Bentuk
		// pemanggilannya menunjukkan seberapa jauh akibatnya.
		if (Input.IsActionJustPressed("harvest") && _run.TryHarvest(out var yield))
		{
			CropLayer.QueueRedraw();
			UpdateHud();
			GD.Print($"Panen {yield.Name}. Tas bernilai {_run.Inventory.TotalValue}.");
		}

		// Menanam tidak mengubah apa pun di ground atau object layer, jadi yang
		// digambar ulang cuma yang benar-benar berubah.
		//
		// Lewat _run, bukan _run.Player, dan itu berubah di fase ini: benih kini
		// dibayar dari gold, jadi menanam menyentuh dompet dan grid sekaligus.
		// Bentuk pemanggilannya menunjukkan seberapa jauh akibatnya, persis
		// seperti panen di atas.
		for (int i = 0; i < PlantActions.Length && i < CropTypes.All.Count; i++)
		{
			if (!Input.IsActionJustPressed(PlantActions[i])) continue;
			if (!_run.TryPlant(CropTypes.All[i])) continue;

			CropLayer.QueueRedraw();
			UpdateHud();
		}

		if (_isMoving) return;

		var held = HeldDirection();
		if (held.HasValue) Step(held.Value);
	}

	// Satu arah saja per langkah; diagonal bukan gerakan yang sah di grid ini.
	Direction? HeldDirection()
	{
		if (Input.IsActionPressed("move_up")) return Direction.Up;
		if (Input.IsActionPressed("move_down")) return Direction.Down;
		if (Input.IsActionPressed("move_left")) return Direction.Left;
		if (Input.IsActionPressed("move_right")) return Direction.Right;
		return null;
	}

	// Satu arah aliran: state memilih animasi. Tidak ada yang bertanya balik
	// frame mana yang sedang tampil.
	void UpdateAnimation()
	{
		var next = (_isMoving ? WalkAnimations : IdleAnimations)[(int)_run.Player.Facing];
		if (PlayerSprite.Animation != next) PlayerSprite.Play(next);
	}

	// Tanpa offset visual player: cursor 16x16 dan GridToWorld sudah memberi
	// titik tengah tile, jadi keduanya berimpit persis.
	void UpdateCursor()
	{
		// null hanya berarti satu hal: di luar array. Tile yang belum dimiliki
		// tetap kembali sebagai tile biasa.
		var pos = _run.Player.FacingPosition;
		Cursor.Visible = _run.Grid.IsInsideBounds(pos);
		if (!Cursor.Visible) return;

		Cursor.Position = GridToWorld(pos);

		// Hijau untuk tanah yang dijual. Yang menentukannya StripAt, aturan yang
		// sama yang dipakai TryBuyLand, jadi cursor tidak bisa menjanjikan
		// pembelian yang akan ditolak.
		Cursor.Modulate =
			_run.Grid.IsOwned(pos) ? GameConfig.CursorOwnedTint
			: _run.Grid.StripAt(pos) is not null ? GameConfig.CursorBuyableTint
			: GameConfig.CursorUnownedTint;
	}

	void Step(Direction direction)
	{
		// TryMove sudah memutar Facing walau langkah ditolak. Itu aturan
		// simulasi; di sini cukup ikut, jangan diulang atau dibatalkan.
		if (!_run.Player.TryMove(direction)) return;

		_isMoving = true;
		var tween = CreateTween();
		tween.TweenProperty(PlayerSprite, "position", SpriteAnchor(_run.Player.Position),
			GameConfig.StepDuration);
		tween.Finished += OnStepFinished;
	}

	void OnStepFinished()
	{
		_isMoving = false;

		// Sambung di sini, jangan serahkan ke _Process frame berikutnya. Jeda
		// satu frame itu yang terasa sebagai patahan di setiap tile saat tombol
		// ditahan untuk jalan lurus.
		var held = HeldDirection();
		if (held.HasValue) Step(held.Value);
	}

	static void WarnMissingArt(TileSprite sprite)
	{
		if (!WarnedSprites.Add(sprite)) return;
		GD.PushWarning($"TileSprite.{sprite} tidak punya entri di GameConfig.ObjectArt, jadi tidak digambar.");
	}

	// Laut, seluruh peta, sekali saja, termasuk di bawah pulau.
	//
	// Di bawah pulau juga, bukan cuma di sekelilingnya, dan itu sengaja: satu
	// lubang di lapisan paling bawah akan menampakkan latar jendela, dan
	// menghitung tepi pulau di dua tempat adalah cara paling mudah membuat
	// lubang itu. Yang menutupinya adalah tanah, dan tanah tahu bentuknya
	// sendiri.
	//
	// Animasinya urusan tileset: tile-nya sendiri yang punya empat frame, jadi
	// SetCell sudah cukup dan airnya bergerak.
	void RenderWater(FarmGrid grid)
	{
		WaterLayer.Clear();

		foreach (var pos in grid.AllPositions())
		{
			WaterLayer.SetCell(pos, GameConfig.WaterArt.SheetId, GameConfig.WaterArt.AtlasCoords);
		}
	}

	// Pulau: semua yang bukan laut, sebagai terrain, digambar sekali dan tidak
	// pernah lagi.
	//
	// "Tidak pernah lagi" itu syarat, bukan penghematan. Petak yang dicangkul
	// ditimpa SetCell dengan tanah polos siap tanam, dan tile polos itu tidak
	// bertanda terrain — jadi kalau terrain connect dijalankan lagi di
	// sekitarnya, dia akan membaca petak tergarap sebagai "bukan tanah" dan
	// menggambar pantai di tengah ladang. Bentuk pulau tidak pernah berubah
	// sepanjang run, jadi sekali sudah cukup dan masalahnya tidak bisa terjadi.
	void RenderIsland(FarmGrid grid)
	{
		GroundLayer.Clear();

		var cells = new Godot.Collections.Array<Vector2I>();
		foreach (var pos in grid.AllPositions())
		{
			if (grid.IsLand(pos)) cells.Add(pos);
		}

		GroundLayer.SetCellsTerrainConnect(
			cells, GameConfig.GroundTerrainSet, GameConfig.SoilTerrain);
	}

	// Tiga lapisan tumbuhan, dihitung bersama karena ketiganya dijawab oleh dua
	// pertanyaan yang sama tentang tiap petak: terbuat dari apa, dan sudah jadi
	// milik siapa.
	//
	//   pasir, gunung   tidak ada apa-apa. Tanah polos yang terlihat, dan itu
	//                   yang menggambar pantai dan puncak batu.
	//   hutan           rumput gelap dan semak. Semak adalah pohonnya, dan
	//                   hutan tidak pernah dijual.
	//   rumput, belum   rumput gelap saja. Gelap tanpa semak berarti "ini bisa
	//   dibeli          kaubeli", dan itu satu-satunya petunjuk yang pemain
	//                   punya tentang ke arah mana ladang boleh tumbuh.
	//   rumput, dibeli  rumput terang di atas rumput gelap.
	//   sudah dicangkul tidak ada rumput sama sekali, tanahnya kelihatan, dan
	//                   petaknya diganti tanah polos siap tanam.
	//
	// Rumput gelap ada di bawah rumput terang, bukan di sebelahnya. Lembar
	// rumput terang itu berlapis dan tepinya tembus pandang, jadi yang mengintip
	// di sepanjang batas ladang adalah rumput gelap di bawahnya — transisi yang
	// digambar pelukisnya, bukan garis yang digambar kode.
	void RenderGrass(FarmGrid grid)
	{
		DarkerLayer.Clear();
		GrassLayer.Clear();
		BushLayer.Clear();

		var darker = new Godot.Collections.Array<Vector2I>();
		var grass = new Godot.Collections.Array<Vector2I>();
		var bush = new Godot.Collections.Array<Vector2I>();
		var tilled = new List<Vector2I>();

		foreach (var pos in grid.AllPositions()) Classify(grid, pos, darker, grass, bush, tilled);

		DarkerLayer.SetCellsTerrainConnect(
			darker, GameConfig.GroundTerrainSet, GameConfig.DarkerTerrain);
		GrassLayer.SetCellsTerrainConnect(
			grass, GameConfig.GroundTerrainSet, GameConfig.GrassTerrain);
		BushLayer.SetCellsTerrainConnect(
			bush, GameConfig.GroundTerrainSet, GameConfig.BushTerrain);

		foreach (var pos in tilled) PaintPlantable(pos);
	}

	// Satu petak dan tetangganya, alih-alih seluruh peta.
	//
	// Ada karena peta sekarang 100x100. RenderGrass menyusuri sepuluh ribu sel
	// dan memanggil terrain connect tiga kali; itu benar, tapi tidak boleh
	// dijalankan tiap kali pemain menekan cangkul. Yang berubah saat satu petak
	// dicangkul adalah petak itu dan delapan tetangganya — tetangga ikut karena
	// mereka baru saja jadi tepi — jadi itu yang digambar ulang.
	//
	// Aturannya sama persis dengan RenderGrass, lewat Classify yang sama, supaya
	// jalur cepat dan jalur lengkap tidak bisa berselisih.
	void RefreshGrassNear(FarmGrid grid, IEnumerable<Vector2I> changed)
	{
		var touched = new HashSet<Vector2I>();
		foreach (var pos in changed)
		{
			for (int ox = -1; ox <= 1; ox++)
			{
				for (int oy = -1; oy <= 1; oy++)
				{
					var neighbour = pos + new Vector2I(ox, oy);
					if (grid.IsInsideBounds(neighbour)) touched.Add(neighbour);
				}
			}
		}

		// Dihapus lebih dulu, semuanya, baru digambar ulang. Tanpa ini petak yang
		// baru dicangkul akan tetap memakai tile rumputnya yang lama: terrain
		// connect hanya menulis sel yang diberikan kepadanya, dan sel itu justru
		// yang tidak lagi diberikan.
		foreach (var pos in touched)
		{
			DarkerLayer.EraseCell(pos);
			GrassLayer.EraseCell(pos);
			BushLayer.EraseCell(pos);
		}

		var darker = new Godot.Collections.Array<Vector2I>();
		var grass = new Godot.Collections.Array<Vector2I>();
		var bush = new Godot.Collections.Array<Vector2I>();
		var tilled = new List<Vector2I>();

		foreach (var pos in touched) Classify(grid, pos, darker, grass, bush, tilled);

		DarkerLayer.SetCellsTerrainConnect(
			darker, GameConfig.GroundTerrainSet, GameConfig.DarkerTerrain);
		GrassLayer.SetCellsTerrainConnect(
			grass, GameConfig.GroundTerrainSet, GameConfig.GrassTerrain);
		BushLayer.SetCellsTerrainConnect(
			bush, GameConfig.GroundTerrainSet, GameConfig.BushTerrain);

		foreach (var pos in tilled) PaintPlantable(pos);
	}

	// Satu petak, satu jawaban, dipakai oleh gambar-ulang penuh dan gambar-ulang
	// setempat. Satu-satunya tempat aturan tampilan tanah ditulis.
	static void Classify(FarmGrid grid, Vector2I pos,
		Godot.Collections.Array<Vector2I> darker, Godot.Collections.Array<Vector2I> grass,
		Godot.Collections.Array<Vector2I> bush, List<Vector2I> tilled)
	{
		var terrain = grid.TerrainAt(pos);

		// Pasir, batu, laut dan jembatan tidak menumbuhkan apa pun.
		if (terrain is Terrain.Water or Terrain.Sand or Terrain.Mountain or Terrain.Bridge) return;

		if (terrain == Terrain.Forest)
		{
			darker.Add(pos);
			bush.Add(pos);
			return;
		}

		// Kota digambar dengan rumput terang seperti ladang yang dimiliki, karena
		// memang tanah terawat — bedanya bukan di rumputnya melainkan di cursor:
		// menghadapnya memberi merah, bukan hijau, karena AvailableAction menolak.
		if (terrain == Terrain.Town)
		{
			darker.Add(pos);
			grass.Add(pos);
			return;
		}

		if (grid.IsOwned(pos) && grid.GetTile(pos).Ground == GroundState.Tilled)
		{
			tilled.Add(pos);
			return;
		}

		darker.Add(pos);
		if (grid.IsOwned(pos)) grass.Add(pos);
	}

	// Pagar, satu cincin persis di luar persegi ladang.
	//
	// Di luar, bukan di atasnya, dan itu satu-satunya tempat yang benar: Fence
	// adalah TileSpriteObject yang menghalangi jalan, jadi pagar yang berdiri di
	// tile ladang akan memakan tile itu — di ladang 5x5 itu 16 dari 25. Cincin
	// di luar tidak memakan apa pun, dan karena dia cuma gambar (tidak ada
	// occupant yang ditulis ke tile mana pun) dia juga tidak menghalangi pemain
	// keluar-masuk.
	//
	// Rumput gelap menandai luas, pagar menandai batas, dan keduanya menjawab
	// pertanyaan yang berbeda: "mana yang belum kubeli" dan "sampai mana
	// ladangku". Membeli satu jalur memindahkan cincin ini keluar satu baris,
	// dan itu satu-satunya umpan balik yang menunjukkan pembelian berhasil tanpa
	// pemain harus membaca angka.
	void RenderFence(FarmGrid grid)
	{
		FenceLayer.Clear();

		var origin = grid.OwnedOrigin - Vector2I.One;
		var size = grid.OwnedSize + new Vector2I(2, 2);

		var cells = new Godot.Collections.Array<Vector2I>();
		for (int x = 0; x < size.X; x++)
		{
			for (int y = 0; y < size.Y; y++)
			{
				// Cincinnya saja, bukan isinya.
				if (x != 0 && x != size.X - 1 && y != 0 && y != size.Y - 1) continue;

				var pos = origin + new Vector2I(x, y);
				if (!grid.IsInsideBounds(pos)) continue;

				cells.Add(pos);
			}
		}

		FenceLayer.SetCellsTerrainConnect(
			cells, GameConfig.FenceTerrainSet, GameConfig.FenceTerrain);
	}

	// Tanah siap tanam, langsung per sel. Bukan terrain dan tidak boleh jadi
	// terrain: tile blob menggambar tepi, dan satu petak tergarap di tengah
	// ladang tidak punya tepi untuk digambar — yang mengelilinginya tetap tanah
	// pulau yang sama.
	void PaintPlantable(Vector2I pos)
	{
		GroundLayer.SetCell(pos, GameConfig.SoilSheetId, GameConfig.PlantableSoilAt(pos));
	}

	// Batu, kayu dan pagar. Bukan terrain dan tidak akan pernah: satu batu
	// adalah satu benda di satu tile, dan dua batu bersebelahan tetap dua batu.
	//
	// Satu uji tipe, dan yang diuji jalur render-nya, bukan jenis bendanya.
	// Occupant yang menggambar di luar satu sel — tanaman — tidak lewat sini
	// sama sekali; CropLayer yang mengurusnya.
	void RenderObjects(FarmGrid grid)
	{
		ObjectLayer.Clear();

		foreach (var cell in grid.AllPositions())
		{
			if (grid.GetTile(cell).Occupant is not TileSpriteObject spriteObject) continue;

			if (!GameConfig.ObjectArt.TryGetValue(spriteObject.Sprite, out var art))
			{
				WarnMissingArt(spriteObject.Sprite);
				continue;
			}

			ObjectLayer.SetCell(cell, art.SheetId, art.AtlasCoords);
		}
	}

	// Seluruh dunia dari nol. Dipakai saat run dimulai; aksi memakai
	// RefreshGrassNear, karena sepuluh ribu sel bukan harga yang pantas dibayar
	// untuk satu cangkulan.
	void RenderAll(FarmGrid grid)
	{
		RenderWater(grid);
		RenderIsland(grid);
		RenderGrass(grid);
		RenderFence(grid);
		RenderObjects(grid);
	}
}
