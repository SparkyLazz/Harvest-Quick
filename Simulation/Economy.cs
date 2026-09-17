using System;

// The purse. One number, and the three things that can be asked of it.
//
// Deliberately not part of Inventory. A bag of crops and a pile of gold are the
// same thing only after somebody decides to sell, and that decision belongs to
// whoever owns both sides. Keeping them apart is what makes selling a step in
// EndToday that can be moved, priced or refused, instead of something that
// happens silently the moment a crop is picked.
public class Economy
{
	// What a run opens with. Small on purpose: nothing but carrots pays back
	// fast enough to fill a field from here, so the first week has a shape
	// whether the player has worked that out yet or not.
	//
	// Expect it to move in tuning, and expect it to move less than it looks.
	// Anywhere between 50 and 200 lands within a few hundred gold of the same
	// result, because carrot multiplies money faster than that gap.
	public const int StartingGold = 100;

	public Economy(int startingGold = StartingGold)
	{
		Gold = startingGold;
	}

	public int Gold { get; private set; }

	// The question callers branch on, asked separately from the spending so a
	// refusal can be handled before anything else has happened.
	public bool CanAfford(int cost)
	{
		return Gold >= cost;
	}

	// Not a Try. Whether the money is there is a real question with a real
	// answer, and CanAfford is where it is asked; by the time this runs the
	// answer is already yes, so a false return here could only ever be a bug
	// wearing a bool. It throws instead.
	//
	// The balance never goes negative. Debt is a schedule, not an overdraft:
	// a bill that cannot be paid ends the run, and that is Debt's call to make
	// in Phase 3.3 — a quietly negative purse would imply a decision nobody
	// made.
	public void Spend(int cost)
	{
		if (cost < 0)
		{
			throw new ArgumentOutOfRangeException(nameof(cost),
				"spending a negative amount is earning; say so.");
		}

		if (cost > Gold)
		{
			throw new InvalidOperationException(
				$"spending {cost} with {Gold} in hand. Ask CanAfford first.");
		}

		Gold -= cost;
	}

	public void Earn(int amount)
	{
		if (amount < 0)
		{
			throw new ArgumentOutOfRangeException(nameof(amount),
				"earning a negative amount is spending; say so.");
		}

		Gold += amount;
	}
}
