using System;
using Godot;
using System.Collections.Generic;
using System.Linq;

// One run played is milliseconds; one run played by hand is forty minutes. That
// is the whole argument for this file existing, and the reason every number in
// Phase 3 came off it rather than out of a spreadsheet.
//
//   dotnet run --project Harness
//
// Run it after every price change. The numbers it prints are the ones the bill
// schedule is tuned against, and a schedule tuned against stale numbers is the
// failure this project keeps finding in other forms.
public static class Program
{
	public static void Main()
	{
		var debt = new Debt();
		int tiles = FarmGrid.StartingFarmSize * FarmGrid.StartingFarmSize;

		Console.WriteLine($"ladang buka {FarmGrid.StartingFarmSize}x{FarmGrid.StartingFarmSize} = {tiles} tile   "
			+ $"energi {Energy.DailyBudget}/hari   modal {Economy.StartingGold}   {Simulator.Days} hari");
		Console.WriteLine($"biaya kerja: cangkul {WorkCost.Of(FarmAction.Till)}, "
			+ $"tanam {WorkCost.Of(FarmAction.Plant)}, panen {WorkCost.Of(FarmAction.Harvest)}, "
			+ $"beli {WorkCost.Of(FarmAction.Buy)}");
		Console.WriteLine($"tanah: {LandPrice.PerTile}/tile   "
			+ $"jalur pertama {FarmGrid.StartingFarmSize} tile = {FarmGrid.StartingFarmSize * LandPrice.PerTile}");
		Console.WriteLine();

		foreach (var crop in CropTypes.All)
		{
			Console.WriteLine($"  {crop.Name,-8} {crop.DaysOccupied,2} hari, {ChainTable.Effort(crop)} aksi, "
				+ $"laba {ChainTable.Profit(crop),4}   "
				+ $"{ChainTable.Profit(crop) / (double)crop.DaysOccupied,5:F1}/hari-tile   "
				+ $"{ChainTable.Profit(crop) / (double)ChainTable.Effort(crop),5:F1}/energi");
		}

		Console.WriteLine();
		Console.WriteLine($"utang: {debt.Schedule.Count} pembayaran, total {debt.Total}");
		Console.WriteLine("  " + string.Join("  ", debt.Schedule.Select(p => $"h{p.Day}:{p.Amount}")));
		Console.WriteLine();

		int bound = UpperBound.Compute(out int boundTiles, out int boundEffort);
		// Counted off a real island rather than assumed, because since 4.3 the
		// map is generated and no two seeds deal the same amount of land.
		int mapTiles = new FarmGrid(seed: Simulator.DefaultSeed).BuyableTileCount;
		int landOnly = mapTiles * ChainTable.V(Simulator.Days - 1)
			- (mapTiles - tiles) * LandPrice.PerTile;
		int budget = Simulator.Days * Energy.DailyBudget;

		Console.WriteLine($"BATAS ATAS (modal bebas, energi dijumlah bukan per hari): {bound}");
		Console.WriteLine($"  tercapai dengan {boundTiles} tile ({boundTiles - tiles} dibeli) "
			+ $"dan {boundEffort} dari {budget} energi");
		Console.WriteLine($"  batas tanah saja, tanpa energi: {mapTiles} x V(29) - tanah = {landOnly}");

		// Worth saying out loud rather than leaving to be noticed: when the two
		// agree, the effort relaxation did nothing, and every bit of the gap
		// down to the floor is the one thing still relaxed — capital.
		//
		// 4.1 is expected to flip this line, and if it does not then the price of
		// land is wrong. With the field fixed at 25 tiles, effort was slack and
		// the ceiling was set by how much land existed; with land on sale at any
		// price below what a tile earns, the only thing left holding the ceiling
		// down is the eighteen effort a day.
		Console.WriteLine(bound >= landOnly
			? $"  -> energi TIDAK mengikat di relaksasi ini ({boundEffort} dari {budget} terpakai). "
				+ "Langit-langit ditentukan tanah; sisa celah ke lantai adalah modal."
			: $"  -> energi mengikat: batas turun {landOnly - bound} di bawah batas tanah. "
				+ $"Ladang berhenti tumbuh di {boundTiles} tile karena energi, bukan karena peta.");

		// Said here rather than left to be inferred from the gap, because the
		// gap moved for a reason that has nothing to do with the game getting
		// easier. 4.1 added a fourth relaxation — land arrives on day 1, paid for
		// with capital nobody has to earn — and it is by far the loosest of the
		// four. A ceiling that rose from 10,625 to nearly 20,000 is not evidence
		// that a real player got twice as strong; it is this bound getting weaker
		// at the job it exists for, which is telling us whether the schedule is
		// tuned against a straw man. Tightening it means bounding how fast land
		// can actually be paid for, and that is not a relaxation away.
		Console.WriteLine("  CATATAN: relaksasi keempat (tanah datang di h1, modal bebas) adalah yang "
			+ "paling longgar dari empat. Celah yang melebar sejak 4.1 adalah batas ini yang melemah, "
			+ "bukan pemain yang menguat.");
		Console.WriteLine();

		// An explicit empty schedule, not null: RunState reads null as "ship the
		// default", so passing nothing here would have measured the floor with
		// the bills still being charged. It did, for one run of this file, and
		// the floor came out at a third of its real value.
		var noDebt = new Debt(Array.Empty<Payment>());

		var strategies = Policies();
		var unburdened = strategies.Select(s => Simulator.Play(s, noDebt)).ToList();
		var charged = strategies.Select(s => Simulator.Play(s, debt)).ToList();

		int floor = unburdened.Max(r => r.Profit);
		var survivors = charged.Where(r => r.Survived).OrderByDescending(r => r.Profit).ToList();
		var dumb = charged[0];

		var floorRun = unburdened.OrderByDescending(r => r.Profit).First();
		Console.WriteLine($"LANTAI (terbaik dari {strategies.Count} kebijakan, tanpa utang): {floor}");
		Console.WriteLine($"  {floorRun.Strategy}   " + string.Join(" ", floorRun.Planted.Select(p => $"{p.Key}:{p.Value}")));
		Console.WriteLine($"  celah lantai..batas atas: {bound - floor}  ({100.0 * floor / bound:F0}% batas atas tercapai)");

		// The question this whole file exists to answer. A schedule is only
		// meaningful if it still bites the strongest player who could possibly
		// exist, and the bound is what makes that sayable instead of hoped.
		Console.WriteLine($"  utang {debt.Total} = {100.0 * debt.Total / floor:F0}% lantai, "
			+ $"{100.0 * debt.Total / bound:F0}% batas atas "
			+ $"-> pemain sempurna pun membayar {100.0 * debt.Total / bound:F0}% dari maksimum mutlaknya");
		Console.WriteLine();
		Console.WriteLine("dengan jadwal utang terpasang:");
		Console.WriteLine($"  {dumb.Strategy,-38} {(dumb.Survived ? $"selamat, sisa {dumb.Profit}" : $"BANGKRUT h{dumb.EndedOnDay}")}");
		Console.WriteLine($"  {survivors.Count}/{charged.Count - 1} kebijakan cerdas selamat");

		foreach (var report in survivors.Take(3))
		{
			Console.WriteLine($"    {report.Strategy,-38} sisa {report.Profit,5}   "
				+ string.Join(" ", report.Planted.Select(p => $"{p.Key[0]}{p.Value}")));
		}

		Console.WriteLine();
		Console.WriteLine(Verdict(dumb, survivors, floor, bound, debt));

		if (survivors.Count > 0)
		{
			ShowCash(charged[0], survivors[0]);
			ShowDecisions(survivors[0]);
			ShowSpread(survivors);
		}

		ShowLandSweep(debt);
		ShowMaps();
	}

	// Every policy the search covers, built once so the sweep below plays the
	// same set at every price. The land knobs multiply the list rather than
	// replacing it: a landless variant of every farming policy stays in, because
	// "would this run have been better off not buying" is the question the price
	// is being set against, and it can only be answered by the same farmer
	// playing both ways.
	private static List<Strategy> Policies()
	{
		var strategies = new List<Strategy> { new CheapestEverywhere() };

		// Null first, and it is the control: the same farming line with land
		// switched off.
		var lands = new List<LandPolicy> { null };
		foreach (int until in new[] { 8, 14, 20 })
		{
			foreach (int keep in new[] { 0, 200, 600 })
			{
				lands.Add(new LandPolicy(until, keep));
			}
		}

		foreach (var land in lands)
		{
			foreach (int gold in new[] { 0, 150, 300, 450, 600, 900, 1400, 2200 })
			{
				foreach (int hold in new[] { 0, 2, 3, 5, 8, 12 })
				{
					strategies.Add(new ChainValue(gold, hold) { Land = land });
				}
			}

			foreach (var target in CropTypes.All)
			{
				foreach (int hold in new[] { 0, 3, 8 })
				{
					strategies.Add(new FillTheField(target, hold) { Land = land });
				}
			}
		}

		return strategies;
	}

	// The 4.1 tuning pass, and the only honest way to pick LandPrice.PerTile.
	//
	// One line per candidate price, and three columns that between them say
	// whether that price is a decision. How many surviving policies bought
	// anything at all: at zero the price is above what land is worth and the
	// fourth action is dead. How much the best survivor bought: if every price
	// in the sweep drives the field to the same size, the price is not what is
	// binding — effort is, and the number should be chosen on the other two
	// columns. And whether the best line with land beats the best line without:
	// a price where buying is strictly worse is a price nobody should pay, and a
	// price where not buying is strictly worse is a price that has removed the
	// decision from the other side.
	//
	// The band to look for is the one where both appear near the top — where the
	// best run buys and a run that does not buy is still close behind it.
	private static void ShowLandSweep(Debt debt)
	{
		Console.WriteLine();
		Console.WriteLine("HARGA TANAH — sapuan (jadwal utang terpasang, kebijakan sama di tiap harga):");
		Console.WriteLine("  /tile  jalur  selamat  beli>0 |  sisa terbaik  tanpa tanah  |  pembeli terbaik: sisa  tile  beli-1  hari-kep");

		foreach (int price in new[] { 30, 40, 45, 50, 55, 60, 70, 90, 120 })
		{
			var runs = Policies()
				.Select(s => (Policy: s, Report: Simulator.Play(s, debt, price)))
				.Where(r => r.Report.Survived)
				.OrderByDescending(r => r.Report.Profit)
				.ToList();

			if (runs.Count == 0)
			{
				Console.WriteLine($"  {price,5}  tidak ada yang selamat");
				continue;
			}

			// Three readings of the same price, because the overall best hides
			// the thing being measured: if the winner happens not to buy, the
			// table would report a column of zeroes and say nothing about
			// whether buying was close.
			var best = runs[0].Report;
			var landless = runs.FirstOrDefault(r => r.Policy.Land is null).Report;
			var buyer = runs.FirstOrDefault(r => r.Report.TilesBought > 0).Report;
			var buyers = runs.Count(r => r.Report.TilesBought > 0);

			// The day the first strip went in, which is the number that says
			// whether the price or the calendar is doing the refusing.
			var firstDay = 0;
			if (buyer is not null)
			{
				for (int day = 1; day <= Simulator.Days && firstDay == 0; day++)
				{
					if (buyer.LandBoughtByDay[day] > 0) firstDay = day;
				}
			}

			Console.WriteLine($"  {price,5}  {price * FarmGrid.StartingFarmSize,5}  {runs.Count,7}  {buyers,6} | "
				+ $"{best.Profit,13}  {(landless is null ? "-" : landless.Profit.ToString()),11}  | "
				+ $"{(buyer is null ? "-" : buyer.Profit.ToString()),22}"
				+ $"  {(buyer is null ? "-" : (FarmGrid.StartingFarmSize * FarmGrid.StartingFarmSize + buyer.TilesBought).ToString()),4}"
				+ $"  {(firstDay == 0 ? "-" : $"h{firstDay}"),6}"
				+ $"  {(buyer is null ? "-" : buyer.DaysWithDecision.ToString()),8}");
		}

		Console.WriteLine($"  (harga terpasang: {LandPrice.PerTile}. 'jalur' = harga jalur pertama, 5 tile.");
		Console.WriteLine("   'beli>0' nol berarti aksi keempat mati. 'pembeli terbaik' di bawah "
			+ "'sisa terbaik' berarti membeli itu pilihan yang salah di harga itu.)");
	}

	// The one thing a tuning pass actually wants to know, said in words rather
	// than left to be read off four numbers.
	private static string Verdict(RunReport dumb, List<RunReport> survivors, int floor, int bound, Debt debt)
	{
		if (dumb.Survived)
		{
			return $"TERLALU LONGGAR: strategi terbodoh selamat dengan sisa {dumb.Profit}. Naikkan total {debt.Total}.";
		}

		if (survivors.Count == 0)
		{
			return $"TERLALU KETAT: tidak ada kebijakan yang selamat. Turunkan total {debt.Total}, "
				+ "dan turunkan pembayaran awal lebih dulu — gold hari 6 bernilai berlipat gold hari 30.";
		}

		var note = bound > floor * 1.5
			? $"\nPERINGATAN: batas atas {bound} jauh di atas lantai {floor}. Pemain jauh lebih baik "
				+ "mungkin ada, dan jadwal ini dituning melawan yang belum tentu terkuat."
			: $"\nCelah lantai..batas atas sempit ({bound - floor}), jadi lantai ini pemain yang layak dilawan.";

		return $"JENDELA: bodoh bangkrut h{dumb.EndedOnDay}, {survivors.Count} kebijakan cerdas selamat, "
			+ $"terbaik sisa {survivors[0].Profit}." + note;
	}

	// When the run stops asking anything. Two series, because a farming day can
	// go quiet in two different ways and they do not fail together.
	//
	// Pilihan is how many species were on the menu with a tile free to put one
	// in. Sisa is the effort left at day's end: while that is zero the day was a
	// triage problem, and once it stops being zero the field is no longer asking
	// which tile gets worked.
	//
	// Neither says whether the run is fun. Together they say when it stops being
	// possible for it to be: past the last day with two options and spare
	// effort, everything remaining is execution of a plan already made.
	private static void ShowDecisions(RunReport best)
	{
		Console.WriteLine();
		Console.WriteLine("ruang keputusan per hari (kebijakan terbaik yang selamat):");
		Console.Write("  pilihan ");
		for (int day = 1; day <= Simulator.Days; day++) Console.Write(best.ChoicesByDay[day]);
		Console.WriteLine();
		Console.Write("  sisa    ");
		for (int day = 1; day <= Simulator.Days; day++)
		{
			Console.Write(best.SlackByDay[day] == 0 ? "." : Math.Min(best.SlackByDay[day], 9).ToString());
		}

		Console.WriteLine("        (titik = energi habis)");
		Console.WriteLine($"  hari 1                       10                  20                  30");
		Console.WriteLine();
		Console.Write("  tanam   ");
		for (int day = 1; day <= Simulator.Days; day++)
		{
			Console.Write(string.IsNullOrEmpty(best.SownByDay[day]) ? "." : best.SownByDay[day][0]);
		}

		Console.WriteLine("        (huruf = jenis benih, titik = tidak menanam)");

		// Under the sowing line on purpose: the two are read together, because a
		// day with a dot above and a digit below is exactly the kind of day 4.1
		// exists to create — nothing planted, and still a decision taken.
		Console.Write("  tanah   ");
		for (int day = 1; day <= Simulator.Days; day++)
		{
			Console.Write(best.LandBoughtByDay[day] == 0
				? "."
				: Math.Min(best.LandBoughtByDay[day], 9).ToString());
		}

		Console.WriteLine("        (angka = tile dibeli hari itu)");
		Console.Write("  luas    ");
		for (int day = 1; day <= Simulator.Days; day++)
		{
			Console.Write(Math.Min(best.FieldTilesByDay[day] / 10, 9).ToString());
		}

		Console.WriteLine("        (puluhan tile ladang pagi itu)");
		Console.WriteLine();
		Console.WriteLine();
		Console.WriteLine("  benih: ditanam / di antaranya sebagai pilihan teratas / terakhir jadi pilihan teratas");
		foreach (var crop in CropTypes.All)
		{
			best.Planted.TryGetValue(crop.Name, out var sown);
			best.SownAsBest.TryGetValue(crop.Name, out var asBest);
			var last = best.LastBestDay.TryGetValue(crop.Name, out var day) ? $"h{day}" : "TIDAK PERNAH";
			var note = sown > 0 && asBest == 0 ? "   <- selalu pilihan sisa" : "";
			Console.WriteLine($"    {crop.Name,-8} {sown,3} / {asBest,3} / {last,-11}{note}");
		}

		Console.WriteLine();
		Console.WriteLine($"  hari ada aktivitas    : {best.DaysWithDecision}/{Simulator.Days}"
			+ $"  ({100.0 * best.DaysWithDecision / Simulator.Days:F0}%)"
			+ $" — tanam {best.DaysWithSowing}, tanah {CountLandDays(best)};"
			+ $" tile bebas di {best.DaysWithOpenTile}/{Simulator.Days} hari");

		// The line the old one should have been. "Days something happened" is
		// not decision density; "days something new happened" is.
		Console.WriteLine($"  KEPADATAN KEPUTUSAN   : {best.NovelDecisionDays} hari benar-benar baru"
			+ $"  ({100.0 * best.NovelDecisionDays / Simulator.Days:F0}% dari {Simulator.Days})"
			+ $", {best.NovelMixDays} campuran benih berbeda");
		Console.WriteLine($"  ladang akhir          : {FarmGrid.StartingFarmSize * FarmGrid.StartingFarmSize}"
			+ $" -> {FarmGrid.StartingFarmSize * FarmGrid.StartingFarmSize + best.TilesBought} tile"
			+ $" ({best.TilesBought} dibeli, {best.GoldOnLand} gold)");
		Console.WriteLine($"  energi habis terakhir : hari {best.LastTightDay}");
		Console.WriteLine($"  pilihan terakhir >=2  : hari {best.LastChoiceDay}");

		var (loopDay, period) = best.FindLoop();
		Console.WriteLine($"  penanaman terakhir    : hari {best.LastSowingDay}");
		Console.WriteLine($"  pembelian terakhir    : hari {best.LastLandDay}");
		Console.WriteLine(loopDay == 0
			? "  tidak pernah berulang: tiap hari berbeda dari sebelumnya sampai akhir"
			: $"  pola berulang mulai   : hari {loopDay}, periode {period} hari");

		// Measured against the last decision of any kind, not the last sowing.
		// Before 4.1 those were the same number because sowing was the only
		// decision there was; keeping the old reading would credit expansion with
		// nothing, since land is bought early and the quiet days are at the end.
		Console.WriteLine($"  -> {Simulator.Days - best.LastDecisionDay} dari {Simulator.Days} hari "
			+ $"({100.0 * (Simulator.Days - best.LastDecisionDay) / Simulator.Days:F0}%) tanpa satu pun keputusan");
	}

	private static int CountLandDays(RunReport report)
	{
		var days = 0;
		for (int day = 1; day <= Simulator.Days; day++)
		{
			if (report.LandBoughtByDay[day] > 0) days++;
		}

		return days;
	}

	// One line is one policy, so a number that only holds for the top-scoring
	// run does not get to stand as the answer.
	private static void ShowSpread(List<RunReport> survivors)
	{
		var decision = survivors.Select(r => r.LastDecisionDay).OrderBy(d => d).ToList();
		var loops = survivors.Select(r => r.FindLoop().Day).Where(d => d > 0).OrderBy(d => d).ToList();

		Console.WriteLine();
		Console.WriteLine($"lintas {survivors.Count} kebijakan yang selamat:");
		Console.WriteLine($"  keputusan terakhir: paling awal hari {decision.First()}, "
			+ $"tengah hari {decision[decision.Count / 2]}, paling akhir hari {decision.Last()}");
		var density = survivors.Select(r => r.DaysWithDecision).OrderBy(d => d).ToList();
		var openDays = survivors.Select(r => r.DaysWithOpenTile).OrderBy(d => d).ToList();
		var grown = survivors.Select(r => r.TilesBought).OrderBy(d => d).ToList();
		Console.WriteLine($"  hari berkeputusan : paling sedikit {density.First()}, "
			+ $"tengah {density[density.Count / 2]}, paling banyak {density.Last()} dari {Simulator.Days}");
		Console.WriteLine($"  hari ada tile bebas: paling sedikit {openDays.First()}, "
			+ $"tengah {openDays[openDays.Count / 2]}, paling banyak {openDays.Last()} dari {Simulator.Days}");
		Console.WriteLine($"  tile dibeli       : paling sedikit {grown.First()}, "
			+ $"tengah {grown[grown.Count / 2]}, paling banyak {grown.Last()}"
			+ $"  ({survivors.Count(r => r.TilesBought > 0)} dari {survivors.Count} membeli sesuatu)");
		Console.WriteLine(loops.Count == 0
			? "  tidak ada yang jatuh ke pola berulang"
			: $"  pola berulang     : paling awal hari {loops.First()}, "
				+ $"tengah hari {loops[loops.Count / 2]}, paling akhir hari {loops.Last()} "
				+ $"({loops.Count} dari {survivors.Count})");
	}

	// Kept because the shape of the schedule comes from this curve, not from the
	// total. Through the middle of a run the better farmer holds less cash, and
	// a payment placed there punishes the player it should reward.
	private static void ShowCash(RunReport dumb, RunReport best)
	{
		Console.WriteLine();
		Console.WriteLine("tunai saat tagihan ditagih (gold + tas):");
		Console.WriteLine("  hari  bodoh  bagus  |  hari  bodoh  bagus  |  hari  bodoh  bagus");

		for (int i = 1; i <= 10; i++)
		{
			var cells = new List<string>();
			for (int k = 0; k < 3; k++)
			{
				int day = i + k * 10;
				cells.Add($" h{day,-3} {dumb.CashByDay[day],6} {best.CashByDay[day],6}");
			}

			Console.WriteLine(" " + string.Join(" |", cells));
		}
	}

	// What the generator actually deals, across seeds.
	//
	// 4.3 asked for rules that make a good map rather than one good map, and the
	// only way to tell those apart is to look at more than one. Two things are
	// being checked and they pull in opposite directions: that the islands differ
	// from each other at all, and that none of them is unplayable.
	//
	// Unplayable has a precise meaning here and it is not "small". A run needs
	// open grass to grow into from the very first strip, so the number that
	// matters is not how much land there is but how much of it is reachable from
	// the farm — a thousand tiles of grass on the far side of a mountain range
	// buys nothing. That is what the flood fill below counts.
	private static void ShowMaps()
	{
		Console.WriteLine();
		Console.WriteLine("PETA — sapuan benih:");
		Console.WriteLine("  benih      air  pasir  rumput  hutan  gunung  kota  jembatan  |  bisa dibeli  tersambung ke ladang");

		var reachable = new List<int>();
		var townless = new List<int>();
		foreach (int seed in new[] { Simulator.DefaultSeed, 1, 2, 3, 7, 11, 42, 1337, 99999 })
		{
			var grid = new FarmGrid(seed: seed);
			var counts = new Dictionary<Terrain, int>();
			foreach (var pos in grid.AllPositions())
			{
				var terrain = grid.TerrainAt(pos);
				counts.TryGetValue(terrain, out var had);
				counts[terrain] = had + 1;
			}

			var connected = CountReachable(grid);
			reachable.Add(connected);
			if (Count(counts, Terrain.Town) == 0) townless.Add(seed);

			Console.WriteLine($"  {seed,9}  {Count(counts, Terrain.Water),5}  {Count(counts, Terrain.Sand),5}"
				+ $"  {Count(counts, Terrain.Grass),6}  {Count(counts, Terrain.Forest),5}"
				+ $"  {Count(counts, Terrain.Mountain),6}  {Count(counts, Terrain.Town),4}  {Count(counts, Terrain.Bridge),8}  |  {grid.BuyableTileCount,11}  {connected,20}");
		}

		reachable.Sort();
		Console.WriteLine($"  tersambung: paling sedikit {reachable[0]}, tengah {reachable[reachable.Count / 2]}, "
			+ $"paling banyak {reachable[reachable.Count - 1]}");
		Console.WriteLine(reachable[0] < 200
			? $"  PERINGATAN: benih terburuk cuma memberi {reachable[0]} tile tersambung. "
				+ "Sebagian run bisa kehabisan tanah sebelum kehabisan energi."
			: "  Tiap benih memberi jauh lebih banyak tanah tersambung daripada yang sempat digarap 30 hari.");

		Console.WriteLine(townless.Count == 0
			? "  Tiap benih dapat kota dan jembatan."
			: $"  PERINGATAN: {townless.Count} benih tanpa kota sama sekali ({string.Join(", ", townless)}). "
				+ "Pulau terlalu besar sampai tidak ada laut tersisa untuk menaruhnya.");

		ShowOne(Simulator.DefaultSeed);
	}

	private static int Count(Dictionary<Terrain, int> counts, Terrain terrain) =>
		counts.TryGetValue(terrain, out var n) ? n : 0;

	// Grass the farm could actually grow into, by walking outwards from the
	// starting field through grass only. Counted rather than assumed, because
	// "how much land is on this island" and "how much land can this farm have"
	// are different numbers as soon as a mountain sits between them.
	private static int CountReachable(FarmGrid grid)
	{
		var seen = new HashSet<Vector2I>();
		var queue = new Queue<Vector2I>();

		foreach (var pos in grid.OwnedPositions())
		{
			if (seen.Add(pos)) queue.Enqueue(pos);
		}

		var steps = new[] { new Vector2I(1, 0), new Vector2I(-1, 0), new Vector2I(0, 1), new Vector2I(0, -1) };
		while (queue.Count > 0)
		{
			var pos = queue.Dequeue();
			foreach (var step in steps)
			{
				var next = pos + step;
				if (!grid.IsInsideBounds(next) || seen.Contains(next)) continue;
				if (!grid.TerrainAt(next).IsBuyable()) continue;

				seen.Add(next);
				queue.Enqueue(next);
			}
		}

		return seen.Count;
	}

	// One island, drawn small. Every character is a 4x4 block of the map reduced
	// to whatever terrain is commonest in it, which is lossy on purpose: what is
	// being checked here is the shape — is it an island, does it have a coast,
	// are the mountains in clumps or in a spray — and that reads better small.
	private static void ShowOne(int seed)
	{
		const int Block = 4;
		var grid = new FarmGrid(seed: seed);

		Console.WriteLine();
		Console.WriteLine($"  benih {seed}  ('~' laut  '.' pasir  ',' rumput  '#' hutan  '^' gunung  'T' kota  '=' jembatan  'O' ladang)");

		for (int by = 0; by < grid.GridSize; by += Block)
		{
			var line = "  ";
			for (int bx = 0; bx < grid.GridSize; bx += Block)
			{
				var tally = new Dictionary<Terrain, int>();
				var owned = false;

				for (int x = bx; x < bx + Block && x < grid.GridSize; x++)
				{
					for (int y = by; y < by + Block && y < grid.GridSize; y++)
					{
						var pos = new Vector2I(x, y);
						if (grid.IsOwned(pos)) owned = true;

						var terrain = grid.TerrainAt(pos);
						tally.TryGetValue(terrain, out var had);
						tally[terrain] = had + 1;
					}
				}

				if (owned)
				{
					line += "O";
					continue;
				}

				var top = Terrain.Water;
				var best = -1;
				foreach (var entry in tally)
				{
					if (entry.Value <= best) continue;
					best = entry.Value;
					top = entry.Key;
				}

				line += top switch
				{
					Terrain.Water => "~",
					Terrain.Sand => ".",
					Terrain.Grass => ",",
					Terrain.Forest => "#",
					Terrain.Mountain => "^",
					Terrain.Town => "T",
					_ => "=",
				};
			}

			Console.WriteLine(line);
		}
	}
}
