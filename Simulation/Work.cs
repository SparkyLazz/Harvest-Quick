using System;
using System.Collections.Generic;

// The things a day can be spent on. One member per action that costs effort,
// and nothing else: walking is deliberately absent, because a 5x5 field
// is eight steps corner to corner and no price for a step is both large enough
// to matter against a day's budget and small enough to leave the rest of the
// game standing. When the field outgrows 8x8 this enum is where the fourth
// member goes, and nothing else has to move.
//
// It doubles as the answer to "what does this tile invite", which is why it
// lives here and not beside the input handling.
public enum FarmAction
{
	Till,
	Plant,
	Harvest,

	// Buying the strip of land the faced tile lies in. In this enum rather than
	// off to one side because the readout, the cursor and the refusal chain all
	// ask "what does this tile invite" and there must be exactly one answer to
	// that question — a fourth action that answered it somewhere else would be
	// the second copy of a rule that this file exists to prevent.
	Buy,
}

// What each action takes out of a day. One table, in one place, so tuning is an
// edit rather than a search — the same reason the bill schedule will be data.
//
// Tilling costs three and the other two cost one, and the reason is structural
// rather than thematic. Harvesting and planting recur: they come in pairs, once
// per crop cycle, and they consume capacity. Tilling happens once per tile for
// the whole run and buys capacity permanently. Priced the same, tilling would
// be under a tenth of a run's work and the budget would not gate expansion at
// all — which is precisely where Phase 4 needs a lever when land goes on sale.
//
// At three, opening one new tile costs the same as turning over one and a half
// existing ones. That is the trade meant to be a decision, and it is now the
// trade that prices expansion: a five-tile strip is fifteen effort of hoeing
// before it grows anything, which is most of a day.
//
// Buying costs two, and the two is a transaction and not labour — signing for
// the land, not working it. It is small on purpose. The real cost of a strip is
// the tilling above and the gold in LandPrice; what this number buys is the
// guarantee that a purchase is never free of the day it happens on, so land
// cannot be picked up in the dead minutes of a day that had nothing else to do.
public static class WorkCost
{
	//                                    biaya
	private static readonly IReadOnlyDictionary<FarmAction, int> Table =
		new Dictionary<FarmAction, int>
		{
			[FarmAction.Harvest] = 1,
			[FarmAction.Plant] = 1,
			[FarmAction.Till] = 3,
			[FarmAction.Buy] = 2,
		};

	// Throws on a member with no price rather than assuming one. A new action
	// added to the enum and forgotten here is a bug, and a silent default of
	// zero would make it a free one.
	public static int Of(FarmAction action)
	{
		if (Table.TryGetValue(action, out var cost)) return cost;

		throw new ArgumentOutOfRangeException(nameof(action),
			$"FarmAction.{action} has no price in the work table.");
	}
}
