using System;

// A day's worth of work, and what is left of it. Deliberately the same shape as
// Economy — CanAfford to ask, Spend to do, never negative — because gold and
// effort are two budgets under the same rules, and a caller that has learned to
// refuse one should not have to learn a second way to refuse the other.
//
// The one thing that differs is where it goes: gold carries over and effort
// does not. Saving today's energy buys nothing, which is what makes "which tile
// do I work today" a question rather than an ordering.
public class Energy
{
	// Paired with FarmGrid.StartingFarmSize, and only correct together. A 5x5
	// field turned over entirely on carrots needs a harvest and a planting per
	// tile every three days: 25 x 2 / 3 = 16.7 a day, against 18.
	//
	// That margin is the whole design. A full field is barely sustainable, and
	// only if the plantings are staggered — 25 tiles ripening on the same
	// morning is 50 work in one day and simply cannot be done. Change this
	// number and the field size has to move with it.
	public const int DailyBudget = 18;

	public Energy(int dailyBudget = DailyBudget)
	{
		if (dailyBudget < 1)
		{
			throw new ArgumentOutOfRangeException(nameof(dailyBudget),
				"a day with no work in it is not a day.");
		}

		Max = dailyBudget;
		Current = dailyBudget;
	}

	public int Max { get; }
	public int Current { get; private set; }

	public bool CanAfford(int cost)
	{
		return Current >= cost;
	}

	// Not a Try, for the same reason Economy.Spend is not: CanAfford is where
	// the question gets asked, so a false return here could only be a bug.
	public void Spend(int cost)
	{
		if (cost < 0)
		{
			throw new ArgumentOutOfRangeException(nameof(cost),
				"spending negative effort is resting; there is no such action.");
		}

		if (cost > Current)
		{
			throw new InvalidOperationException(
				$"spending {cost} with {Current} left. Ask CanAfford first.");
		}

		Current -= cost;
	}

	// Full, never partial and never carried over. Called by StartTomorrow.
	public void Restore()
	{
		Current = Max;
	}
}
