using System;

// How much a run could possibly be worth. Not how much the best player gets —
// a number no player can beat, which is a different and much cheaper thing to
// compute.
//
// It exists to answer one question: is the bill schedule tuned against a
// straw man? A strategy search only ever finds a floor, and a floor on its own
// says nothing about how much room is above it. With a ceiling too, the gap
// between them is the honest measure of how much is still unknown.
//
// Four relaxations, each of which can only ever make a run easier, which is
// what makes the result a genuine bound rather than an estimate:
//
//   1. Gold is unlimited. Seed and land are still subtracted from profit, but
//      never have to be affordable at the moment of buying. This is the biggest
//      of the four: the real run spends its first week unable to buy what it
//      wants.
//   2. Effort is capped over the whole run instead of per day. 30 days at 18 is
//      540, and a plan that fits inside the daily cap always fits inside the
//      total, so nothing feasible is excluded. What this throws away is every
//      constraint of timing — the real run cannot pick 25 ripe tiles in one
//      morning, and this says it can.
//   3. Tiles are independent. True already, once gold and the daily cap are
//      gone: the only thing left connecting two tiles is the effort budget,
//      and that is carried explicitly below.
//   4. Bought land arrives on day 1 and the buying itself is free of effort.
//      Both are over-estimates of the real thing, which is the point: a strip
//      bought on day 12 has eighteen days to pay for itself and this gives it
//      twenty-nine, and the two effort per strip this ignores is at most 38 of
//      540.
//
// What stays real: the calendar, every crop's cycle length and price, the cost
// of breaking ground once per tile, the gold price of every tile of land beyond
// the opening farm, and the fact that a tile can only hold one thing at a time.
public static class UpperBound
{
	// Enough headroom for the most action-hungry chain 29 nights allows, which
	// is carrots end to end: nine cycles of a planting and a picking.
	private const int MaxEffortPerTile = 48;

	public static int Compute(out int usedTiles, out int usedEffort,
		int landPricePerTile = LandPrice.PerTile)
	{
		int nights = Simulator.Days - 1;
		int startingTiles = FarmGrid.StartingFarmSize * FarmGrid.StartingFarmSize;
		int effortBudget = Simulator.Days * Energy.DailyBudget;
		int tillCost = WorkCost.Of(FarmAction.Till);

		// How many tiles are worth considering at all. A tile that earns anything
		// has to be broken, planted and picked, so anything past this many tiles
		// cannot be reached with the effort in the run however much land is
		// bought — and the map's own limit is well above it.
		//
		// This is where 4.1 changes the shape of this file. The old version
		// asked for exactly 25 tiles because 25 was all a player could ever
		// have; a bound that still said 25 would be a ceiling on a game that no
		// longer exists, and it would be *below* what a real run can now reach.
		int minEffortPerTile = tillCost + WorkCost.Of(FarmAction.Plant) + WorkCost.Of(FarmAction.Harvest);
		// Bounded by effort, not by land. An island varies with its seed, so no
		// single land count is right for every run — and a bound may overestimate
		// land without ceasing to be a bound, while underestimating it would stop
		// being one. Effort is the tighter cap by a wide margin anyway: 540 effort
		// over 30 days buys at most 108 worked tiles, against islands that deal out
		// well over a thousand.
		int maxTiles = Math.Min(FarmGrid.DefaultGridSize * FarmGrid.DefaultGridSize,
			effortBudget / minEffortPerTile);

		// best[r, e] = most one tile earns with r nights left and e effort to
		// spend on it. Leaving the tile idle a night is always allowed, which is
		// what the first branch says.
		var best = new int[nights + 1, MaxEffortPerTile + 1];
		for (int r = 1; r <= nights; r++)
		{
			for (int e = 0; e <= MaxEffortPerTile; e++)
			{
				int value = best[r - 1, e];
				foreach (var crop in CropTypes.All)
				{
					int cost = ChainTable.Effort(crop);
					if (r < crop.DaysOccupied || e < cost) continue;

					value = Math.Max(value, ChainTable.Profit(crop) + best[r - crop.DaysOccupied, e - cost]);
				}

				best[r, e] = value;
			}
		}

		// A tile that grows anything has to be broken first, once, ever. A tile
		// that grows nothing costs nothing — so the bound is free to use fewer
		// than all of them if the effort is better spent elsewhere.
		var perTile = new int[MaxEffortPerTile + 1];
		for (int e = 0; e <= MaxEffortPerTile; e++)
		{
			perTile[e] = e < tillCost ? 0 : best[nights, e - tillCost];
		}

		// Spread the effort budget across the tiles.
		var total = new int[maxTiles + 1, effortBudget + 1];
		for (int t = 1; t <= maxTiles; t++)
		{
			for (int e = 0; e <= effortBudget; e++)
			{
				int value = total[t - 1, e];
				for (int spend = 1; spend <= Math.Min(MaxEffortPerTile, e); spend++)
				{
					value = Math.Max(value, total[t - 1, e - spend] + perTile[spend]);
				}

				total[t, e] = value;
			}
		}

		// Land costs the same per tile however the field is grown, and that is
		// not an approximation — a strip is priced at LandPrice.PerTile a tile
		// and adds exactly those tiles, so reaching any area costs
		// (area - 25) x PerTile whichever order and whichever shape got there.
		// It is the one thing about expansion that needs no search.
		//
		// So the ceiling is a straight trade: one more tile is worth whatever the
		// effort budget can still do with it, minus a fixed price. The best
		// number of tiles to own is wherever that stops being positive, and the
		// t this lands on is worth reading — it is the largest farm the run's
		// own effort can justify at the current price.
		int bound = 0;
		usedTiles = startingTiles;
		for (int t = 1; t <= maxTiles; t++)
		{
			int land = Math.Max(0, t - startingTiles) * landPricePerTile;
			int value = total[t, effortBudget] - land;
			if (value <= bound) continue;

			bound = value;
			usedTiles = t;
		}

		// Smallest budget that still reaches the bound, which says whether the
		// ceiling is set by land or by effort.
		int landAtBest = Math.Max(0, usedTiles - startingTiles) * landPricePerTile;
		usedEffort = effortBudget;
		for (int e = 0; e <= effortBudget; e++)
		{
			if (total[usedTiles, e] - landAtBest < bound) continue;

			usedEffort = e;
			break;
		}

		return bound;
	}
}
