using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

// What one run came to. Everything a tuning pass wants to read, and nothing a
// strategy is allowed to write.
public sealed class RunReport
{
	public string Strategy { get; init; }
	public RunOutcome? Outcome { get; init; }

	// The run day the game ended on, or 0 if it never did. Read together with
	// Outcome: a run that survives to the end of the schedule has neither.
	public int EndedOnDay { get; init; }

	public int Profit { get; init; }

	// Gold plus the unsold bag, on each run day, as the bill sees it. One-based,
	// so CashByDay[7] is day seven. This is the curve the schedule is shaped
	// against, so it is kept rather than reduced to a total.
	public int[] CashByDay { get; init; }

	public Dictionary<string, int> Planted { get; init; }

	// Of those, the ones that went in while ranked first among the crops that
	// fitted, and the last day each managed it.
	public Dictionary<string, int> SownAsBest { get; init; }
	public Dictionary<string, int> LastBestDay { get; init; }

	// How many genuinely different things could have been done on each run day,
	// measured before the strategy moved: zero when no tile was free to decide
	// about, otherwise the number of species that both fitted in the days left
	// and could be paid for. One is not a decision, it is the only move.
	//
	// It is not a measure of whether a run is interesting — a person can be
	// bored with three options open, or absorbed while executing a plan they
	// settled a week ago. It is the ceiling on interest: past the last day this
	// reaches two, there is provably nothing left to choose.
	public int[] ChoicesByDay { get; init; }

	// Effort left unspent at the end of each day. While this is zero the day was
	// a triage problem; once it stops being zero, "which tile today" has stopped
	// being a question.
	public int[] SlackByDay { get; init; }

	// What went into the ground each day, as a signature rather than a tally.
	public string[] SownByDay { get; init; }

	// Tiles of land bought on each run day, and the field's size measured before
	// the strategy moved. Two series rather than one, because a run that buys
	// nothing and a run that has nothing left to buy look identical in the first
	// and different in the second.
	public int[] LandBoughtByDay { get; init; }
	public int[] FieldTilesByDay { get; init; }

	public int TilesBought { get; init; }
	public int GoldOnLand { get; init; }

	// Tiles that could have taken a seed that day: already bare, holding
	// something ripe, or wild and waiting for the hoe. Counted before the
	// strategy moved, so it is opportunity offered rather than opportunity used.
	public int[] OpenTilesByDay { get; init; }

	// How many days the field had somewhere to put a seed.
	public int DaysWithOpenTile => Count(day => OpenTilesByDay[day] > 0);

	// How many days a seed actually went in. This is the one that matters: it is
	// the number of days the run asked the player a question instead of asking
	// them to carry out an answer they gave earlier.
	//
	// The gap between the two says which thing is missing. Open tiles but no
	// sowing means the player could not afford anything or nothing was worth
	// planting; no open tiles means the field itself has stopped asking, and no
	// amount of money would change that.
	public int DaysWithSowing => Count(day => !string.IsNullOrEmpty(SownByDay[day]));

	// The one Phase 4 is aimed at. Sowing was the only decision a day could
	// contain until land went on sale, so DaysWithSowing was the whole measure;
	// now a day spent buying and breaking new ground is a day that asked a
	// question even though no seed went in, and counting it as quiet would
	// undersell exactly the thing 4.1 was built to add.
	public int DaysWithDecision =>
		Count(day => !string.IsNullOrEmpty(SownByDay[day]) || LandBoughtByDay[day] > 0);

	private int Count(Func<int, bool> predicate)
	{
		var total = 0;
		for (int day = 1; day <= Simulator.Days; day++)
		{
			if (predicate(day)) total++;
		}

		return total;
	}

	public bool Survived => Outcome is null;

	// The last day that offered a real choice. Everything after it is execution.
	public int LastChoiceDay
	{
		get
		{
			for (int day = Simulator.Days; day >= 1; day--)
			{
				if (ChoicesByDay[day] >= 2) return day;
			}

			return 0;
		}
	}

	// The last day whose effort budget actually ran out.
	public int LastTightDay
	{
		get
		{
			for (int day = Simulator.Days; day >= 1; day--)
			{
				if (SlackByDay[day] == 0) return day;
			}

			return 0;
		}
	}

	// The day the run stopped being new and became a loop, and how long that
	// loop is.
	//
	// Counting the last day with two options answers a different question than
	// the one worth asking. A menu that sits at three for ten days running is
	// not ten decisions, it is one decision taken ten times — the choice is
	// still there and the thinking is not. So this looks for the earliest day
	// from which everything afterwards repeats: same options, same effort left,
	// same seed going into the ground, on a fixed period.
	//
	// Two full turns of the loop are required before it counts. One repeat is a
	// coincidence; the crop cycles here are three, five, eight and eighteen days
	// long, so any of them lands twice by chance.
	public (int Day, int Period) FindLoop()
	{
		for (int start = 1; start <= Simulator.Days; start++)
		{
			for (int period = 1; period <= (Simulator.Days - start + 1) / 2; period++)
			{
				var holds = true;
				for (int day = start; day + period <= Simulator.Days && holds; day++)
				{
					holds = Signature(day) == Signature(day + period);
				}

				if (holds) return (start, period);
			}
		}

		return (0, 0);
	}

	// What the player decided that day, and nothing else.
	//
	// SlackByDay used to be in here and it was the bug that hid a 55 day loop.
	// Effort left over is a consequence of a decision, not a decision — and it
	// wobbles by a point or two as the field's ripening drifts, so two days that
	// planted exactly the same thing in exactly the same field would compare
	// unequal over a difference nobody can see or act on. A 100 day run that sat
	// in an eight day cycle from h40 to h95 was reported as "period 2 days
	// starting h97", which is to say: not detected.
	//
	// ChoicesByDay is still deliberately out, for the opposite reason. The menu
	// narrows on its own as the horizon runs out — a crop that no longer fits
	// stops being offered — so a signature carrying it can never repeat and the
	// detector would report that no run ever settles. That is the calendar
	// shrinking, not the player thinking.
	private string Signature(int day) =>
		$"{SownByDay[day]}|{LandBoughtByDay[day]}";

	// How many genuinely different days this run contained: the number of times
	// it did something it had not done before.
	//
	// This is the number DaysWithDecision should have been all along. That one
	// counts days on which a seed went into the ground, which on a large field
	// is nearly every day — forty-five consecutive days of planting the same
	// pumpkins scored forty-five. The project wrote the rule down in FindLoop
	// and then never measured against it: a menu that sits still for ten days is
	// one decision taken ten times.
	public int NovelDecisionDays
	{
		get
		{
			var seen = new HashSet<string>();
			var novel = 0;
			for (int day = 1; day <= Simulator.Days; day++)
			{
				if (string.IsNullOrEmpty(SownByDay[day]) && LandBoughtByDay[day] == 0) continue;
				if (seen.Add(Signature(day))) novel++;
			}

			return novel;
		}
	}

	// The same count without the quantities: how many different *kinds* of day
	// there were, where planting four carrots and planting five is the same kind
	// of day. Reported beside the exact count because the two disagreeing is
	// itself the finding — a run whose signatures are all distinct but whose
	// species mixes repeat is a run doing one thing at slightly different scales.
	public int NovelMixDays
	{
		get
		{
			var seen = new HashSet<string>();
			var novel = 0;
			for (int day = 1; day <= Simulator.Days; day++)
			{
				if (string.IsNullOrEmpty(SownByDay[day])) continue;

				var kinds = new string(SownByDay[day].Where(c => !char.IsDigit(c)).ToArray());
				if (seen.Add(kinds)) novel++;
			}

			return novel;
		}
	}

	// The last day anything was planted. The plainest reading of when the run
	// stopped asking: after it, every remaining day is picking what is already
	// standing.
	public int LastSowingDay => LastDay(day => !string.IsNullOrEmpty(SownByDay[day]));

	// The same reading widened to the fourth action, and the number 4.4 is
	// looking at: the last day the run asked anything at all.
	public int LastDecisionDay =>
		LastDay(day => !string.IsNullOrEmpty(SownByDay[day]) || LandBoughtByDay[day] > 0);

	public int LastLandDay => LastDay(day => LandBoughtByDay[day] > 0);

	private int LastDay(Func<int, bool> predicate)
	{
		for (int day = Simulator.Days; day >= 1; day--)
		{
			if (predicate(day)) return day;
		}

		return 0;
	}
}

// Plays runs. Owns the loop and the measuring; a Strategy owns the deciding.
//
// The split matters because of a lesson this project has now learned three
// times: whenever something outside the simulation works out an answer the
// simulation already has, the two drift. So this asks RunState whether the run
// is over rather than deciding for itself, works tiles through RunState's own
// priced actions rather than restating the refusals, and never touches Grid,
// Economy or Energy directly.
public static class Simulator
{
	// Long enough to reach the last payment on the shipped schedule, and the
	// horizon every crop's value is computed against.
	public const int Days = 30;

	// Asked of the grid rather than rebuilt from StartingFarmSize, and asked
	// again every morning rather than once before the loop. It used to be a
	// hardcoded 5x5 computed once, which was correct for exactly as long as the
	// field could not grow: the day land went on sale that version would have
	// gone on farming twenty-five tiles of a field that had become forty, and
	// every number this harness prints would have been measured against a farm
	// the game was not playing.
	public static IReadOnlyList<Vector2I> Field(RunState run)
	{
		return new List<Vector2I>(run.Grid.OwnedPositions());
	}

	// A fixed seed by default, and that is not laziness. Since 4.3 the island is
	// generated, so two runs of the same policy on two seeds are two different
	// problems — and a floor measured across a hundred policies that each got a
	// different island is not a floor, it is an average of unrelated games. One
	// seed for every policy makes the comparison mean something; sweeping seeds
	// is a separate question, asked deliberately, about how much the map matters.
	public const int DefaultSeed = 20260917;

	public static RunReport Play(Strategy strategy, Debt debt = null,
		int landPricePerTile = LandPrice.PerTile, int seed = DefaultSeed)
	{
		var run = new RunState(debt: debt, landPricePerTile: landPricePerTile, seed: seed);
		var cash = new int[Days + 2];
		var choices = new int[Days + 2];
		var slack = new int[Days + 2];
		var sown = new string[Days + 2];
		var open = new int[Days + 2];
		var land = new int[Days + 2];
		var tiles = new int[Days + 2];
		for (int i = 0; i < sown.Length; i++) sown[i] = "";

		strategy.BeginRun(run);

		for (int day = 1; day <= Days; day++)
		{
			var field = Field(run);
			tiles[day] = field.Count;
			open[day] = CountOpenTiles(run, field);

			// A day with no free tile can still offer the fourth action, so the
			// menu is no longer gated on there being somewhere to plant. That
			// gate was right when every decision was a planting decision and is
			// exactly what 4.1 changes: a full field with a strip on sale beside
			// it is a field that is still asking something.
			choices[day] = CountMenu(run, open[day]);

			var before = new Dictionary<string, int>(strategy.Planted);
			var tilesBefore = run.Grid.OwnedTileCount;
			strategy.PlayDay(run, field);

			slack[day] = run.Energy.Current;
			sown[day] = Sown(before, strategy.Planted);
			land[day] = run.Grid.OwnedTileCount - tilesBefore;

			// Before the day turns, because that is when EndToday charges.
			cash[day] = run.Economy.Gold + run.Inventory.TotalValue;

			run.AdvanceDay();

			if (run.IsOver) return Report(strategy, run, day, cash, choices, slack, sown, open, land, tiles);
		}

		return Report(strategy, run, 0, cash, choices, slack, sown, open, land, tiles);
	}

	// One builder for both exits. There were two copies of this literal and they
	// were one field apart from each other twice already; a run that ends early
	// and a run that survives differ in two values, so two values is what this
	// takes.
	private static RunReport Report(Strategy strategy, RunState run, int endedOnDay,
		int[] cash, int[] choices, int[] slack, string[] sown, int[] open, int[] land, int[] tiles)
	{
		var bought = run.Grid.OwnedTileCount - FarmGrid.StartingFarmSize * FarmGrid.StartingFarmSize;

		return new RunReport
		{
			Strategy = strategy.Name,
			Outcome = run.Outcome,
			EndedOnDay = endedOnDay,
			Profit = run.Economy.Gold - Economy.StartingGold,
			CashByDay = cash,
			ChoicesByDay = choices,
			SlackByDay = slack,
			SownByDay = sown,
			OpenTilesByDay = open,
			LandBoughtByDay = land,
			FieldTilesByDay = tiles,
			TilesBought = bought,
			GoldOnLand = bought * run.Grid.LandPricePerTile,
			Planted = new Dictionary<string, int>(strategy.Planted),
			SownAsBest = new Dictionary<string, int>(strategy.SownAsBest),
			LastBestDay = new Dictionary<string, int>(strategy.LastBestDay),
		};
	}

	// What this day put in the ground, as the difference between two running
	// tallies. Sorted, so two days that sowed the same thing read the same.
	private static string Sown(Dictionary<string, int> before, Dictionary<string, int> after)
	{
		var parts = new List<string>();
		foreach (var entry in after)
		{
			before.TryGetValue(entry.Key, out var had);
			if (entry.Value > had) parts.Add($"{entry.Key}{entry.Value - had}");
		}

		parts.Sort();
		return string.Join(",", parts);
	}

	// Asked before the strategy moves, so it counts what was on offer rather
	// than what got taken.
	//
	// A tile holding a ripe crop counts as free: picking it is this day's work
	// and the tile is plantable the same day. Gold is today's purse, which is
	// right — today's harvest sells tonight and cannot pay for today's seed.
	private static int CountOpenTiles(RunState run, IReadOnlyList<Vector2I> field)
	{
		var open = 0;
		foreach (var pos in field)
		{
			var action = run.Grid.AvailableAction(pos);
			if (action is FarmAction.Plant or FarmAction.Till)
			{
				open++;
				continue;
			}

			// A ripe crop only frees its tile if the picking finishes it. A
			// tomato with pickings left comes up ripe, gets picked, and is still
			// standing there — the tile was never on offer. Counting those as
			// open said this field had somewhere to plant on 27 days out of 30,
			// which was flatly untrue and made the metric worthless.
			if (action is not FarmAction.Harvest) continue;
			if (run.Grid.GetTile(pos).Occupant is Crop crop && crop.SpentByNextHarvest) open++;
		}

		return open;
	}

	// Gold is today's purse, which is right: today's harvest sells tonight and
	// cannot pay for today's seed.
	//
	// Seeds only count while there is a tile free to put one in, which is what
	// openTiles is for. Land counts separately and on its own terms, because a
	// strip on sale is an option whether or not the field has a gap in it — and
	// it is the only option that creates the gaps.
	private static int CountMenu(RunState run, int openTiles)
	{
		var daysLeft = Days - run.Calendar.RunDay;
		var menu = 0;

		if (openTiles > 0)
		{
			foreach (var crop in CropTypes.All)
			{
				if (crop.DaysOccupied > daysLeft) continue;
				if (crop.SeedPrice > run.Economy.Gold) continue;

				menu++;
			}
		}

		// The cheapest strip on offer, and only if there is still time to grow
		// something in it. Tilling costs three and the fastest crop occupies
		// three days, so a strip bought with fewer than four nights left cannot
		// return a single carrot and is not an option in any sense worth
		// counting.
		foreach (var strip in run.Grid.BuyableStrips())
		{
			if (strip.Price > run.Economy.Gold) continue;
			if (daysLeft < CropTypes.Carrot.DaysOccupied + 1) continue;

			menu++;
			break;
		}

		return menu;
	}
}
