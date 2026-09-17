using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

// One way of playing. Owns a whole day, because the order of harvesting,
// planting and breaking ground is itself a decision and splitting it across
// three hooks would take that decision away from the strategy.
//
// Everything it does goes through RunState's priced actions, so a strategy has
// no way to cheat and no way to disagree with the game about what is allowed.
public abstract class Strategy
{
	protected abstract string BaseName { get; }

	// The land rule is bolted on rather than built into each family, because
	// "how do I farm" and "do I buy more ground" are independent questions and
	// pairing every answer to the first with every answer to the second is the
	// only way to find out whether they interact. Null means the run never buys,
	// which is what every policy did before 4.1 and is kept as the control.
	public LandPolicy Land { get; init; }

	public string Name => Land is null ? BaseName : $"{BaseName} + {Land}";

	// Seeds tallied so a report can say which species a line actually used, as
	// opposed to which ones a table says should win.
	public Dictionary<string, int> Planted { get; } = new Dictionary<string, int>();

	// Seeds that went in while they were the best thing that fitted, as opposed
	// to the best thing that could be paid for. The difference is the whole
	// question: a species that only ever gets planted because the ones above it
	// were out of reach is not a choice the player is making, it is change from
	// a purchase they could not afford.
	public Dictionary<string, int> SownAsBest { get; } = new Dictionary<string, int>();

	// The last run day each species went in as that best-thing-that-fitted.
	public Dictionary<string, int> LastBestDay { get; } = new Dictionary<string, int>();

	// Cleared here, and it has to be: the same Strategy object plays a run
	// without debt and then the same run with it, so a tally that survived
	// between them counted every seed twice.
	public virtual void BeginRun(RunState run)
	{
		Planted.Clear();
		SownAsBest.Clear();
		LastBestDay.Clear();
	}

	public abstract void PlayDay(RunState run, IReadOnlyList<Vector2I> field);

	protected bool Plant(RunState run, Vector2I pos, CropType type, bool wasBest = true)
	{
		if (!run.TryPlant(pos, type)) return false;

		Planted.TryGetValue(type.Name, out var count);
		Planted[type.Name] = count + 1;

		if (!wasBest) return true;

		SownAsBest.TryGetValue(type.Name, out var best);
		SownAsBest[type.Name] = best + 1;
		LastBestDay[type.Name] = run.Calendar.RunDay;
		return true;
	}

	// Called by each family at the point in its day where land competes with
	// seed. Nothing is tallied here: Simulator measures the field before and
	// after the day, so the size of the farm is read off the game rather than
	// off a counter a strategy could forget to increment.
	protected void BuyLand(RunState run, int reserve)
	{
		Land?.Buy(run, reserve);
	}
}

// When to buy a strip, as two knobs on top of whatever the strategy is already
// doing with money.
//
// UntilDay, because land is a bet on the days that are left and the bet goes
// bad at some point before day 30. This is the crude version of that judgement:
// after this day, no more land. Sweeping it is how the harness finds where the
// judgement actually lies instead of asserting it.
//
// Keep, because the real question 4.1 asks is "land or seed", and a policy that
// spends every coin above the next bill on dirt never has to answer it. This is
// the gold held back beyond the debt reserve — money kept liquid for the crop
// that goes in tomorrow rather than the ground it goes into.
//
// The reserve itself is passed in rather than computed here. The strategy owns
// that rule and there must be one copy of it: a land policy with its own idea
// of how much to hold for the bill would be a second answer to a question the
// strategy has already answered.
public sealed class LandPolicy
{
	private readonly int _untilDay;
	private readonly int _keep;

	public LandPolicy(int untilDay, int keep)
	{
		_untilDay = untilDay;
		_keep = keep;
	}

	public override string ToString() => $"tanah s/d h{_untilDay}, sisakan {_keep}";

	public void Buy(RunState run, int reserve)
	{
		if (run.Calendar.RunDay > _untilDay) return;

		// Keeps buying while the rule allows, rather than capping at one strip a
		// day. There is no rule in the game capping it either, and inventing one
		// here would hide the thing worth knowing: if a run can profitably buy
		// four strips in a morning then the price is wrong, and the harness
		// should say so rather than be written so it cannot.
		while (true)
		{
			// Re-asked every time, because buying moves the field's edges and
			// the strip that was on sale a moment ago is now inside the farm.
			//
			// The first one offered, and which one that is does not currently
			// matter: every strip costs the same per tile, so the four edges are
			// interchangeable and taking the first simply grows the field along
			// one axis in the cheapest possible lumps. 4.3 is what makes this
			// line a decision — once rock is scattered, the four edges cost the
			// same gold and different amounts of work, and this is where a
			// policy that reads the ground would go.
			LandStrip? offered = null;
			foreach (var strip in run.Grid.BuyableStrips())
			{
				offered = strip;
				break;
			}

			if (offered is not LandStrip next) return;

			// The bag counts, because it sells before tonight's bill — the same
			// reading of "what can I afford" the planting rules use.
			var purse = run.Economy.Gold + run.Inventory.TotalValue;
			if (purse - next.Price < reserve + _keep) return;

			// Gold alone here, not the bag: the purchase happens now and the bag
			// has not sold yet. So a policy can want a strip, be able to afford
			// it by tonight, and still not get it today. That is the game's rule
			// and not this file's, which is why the refusal is left to come back
			// from RunState rather than being predicted.
			if (!run.TryBuyLand(next.Origin, out _)) return;
		}
	}
}

// The floor. Picks whatever is ripe, puts the cheapest seed in every tile it
// can, breaks ground with whatever effort is left. No sense of the calendar, so
// it plants three-day carrots on day 29 and pays for seed that never ripens.
//
// It is here to be beaten. A schedule this strategy survives is a schedule that
// asks nothing.
public sealed class CheapestEverywhere : Strategy
{
	protected override string BaseName => "termurah di mana-mana";

	public override void PlayDay(RunState run, IReadOnlyList<Vector2I> field)
	{
		var cheapest = CropTypes.All.OrderBy(crop => crop.SeedPrice).First();

		foreach (var pos in field) run.TryHarvest(pos, out _);
		foreach (var pos in field) Plant(run, pos, cheapest);
		foreach (var pos in field) run.TryTill(pos);
	}
}

// Plays the chain table: at every planting it takes the crop worth the most
// over the days that are left, counting what can follow it rather than assuming
// the same species is replanted. Two knobs on top of that.
//
// Bootstrap, because the table is blind to capital. Carrot multiplies money at
// about 1.5x a day and nothing else comes close, so below a threshold of gold
// the right move is carrot regardless of what the table says.
//
// Reserve, because the table is blind to the schedule. Holding back the next
// payment for a few days before it falls due is the decision a visible schedule
// exists to create, and a strategy that spends to zero is one that never makes
// it.
public sealed class ChainValue : Strategy
{
	private readonly int _bootstrapGold;
	private readonly int _reserveDays;

	public ChainValue(int bootstrapGold, int reserveDays)
	{
		_bootstrapGold = bootstrapGold;
		_reserveDays = reserveDays;
	}

	protected override string BaseName => $"nilai rantai (modal<{_bootstrapGold}, tahan {_reserveDays}h)";

	public override void PlayDay(RunState run, IReadOnlyList<Vector2I> field)
	{
		foreach (var pos in field) run.TryHarvest(pos, out _);

		var daysLeft = Simulator.Days - run.Calendar.RunDay;
		var reserve = Reserve(run);

		// Between harvesting and planting, which is where the decision actually
		// sits: the money in hand at this moment is the money that could be
		// either seed or ground, and putting the purchase after the planting
		// loop would only ever buy land with what the seeds did not want.
		BuyLand(run, reserve);

		// Re-read, because the field may be bigger than it was this morning. The
		// tiles just bought are wild ground, so what they actually collect below
		// is the hoe — a strip bought today is a strip planted tomorrow, which is
		// the same one-day lag tilling has always had.
		field = Simulator.Field(run);

		var order = Order(run, daysLeft);

		// The crops that fit the calendar, best first. Whatever sits at the head
		// of this is what the table says to plant today; anything further down
		// only goes in because the head could not be paid for.
		var viable = order.Where(crop => daysLeft >= crop.DaysOccupied).ToList();
		var first = viable.Count > 0 ? viable[0] : null;

		foreach (var pos in field)
		{
			foreach (var crop in viable)
			{
				// Spending down to the reserve is allowed; spending through it
				// is not. The bag counts, because it sells before the bill.
				if (run.Economy.Gold + run.Inventory.TotalValue - crop.SeedPrice < reserve) continue;
				if (Plant(run, pos, crop, wasBest: crop == first)) break;
			}
		}

		foreach (var pos in field) run.TryTill(pos);
	}

	private int Reserve(RunState run)
	{
		var next = run.Debt.NextFrom(run.Calendar.RunDay);
		if (next is not Payment payment) return 0;

		return payment.Day - run.Calendar.RunDay <= _reserveDays ? payment.Amount : 0;
	}

	private List<CropType> Order(RunState run, int daysLeft)
	{
		var byValue = CropTypes.All
			.Where(crop => daysLeft >= crop.DaysOccupied)
			.OrderByDescending(crop => ChainTable.Value(crop, daysLeft))
			.ToList();

		if (run.Economy.Gold >= _bootstrapGold || daysLeft < CropTypes.Carrot.DaysOccupied) return byValue;

		return new[] { CropTypes.Carrot }.Concat(byValue).ToList();
	}
}

// V(R): the most one tile can earn with R nights left, choosing freely at every
// replanting. The number the crop prices were tuned against, and the thing a
// per-crop "profit if replanted forever" table gets wrong.
public static class ChainTable
{
	private static readonly int[] Best = Build();

	public static int Profit(CropType crop) =>
		(crop.Regrows ? crop.MaxHarvests * crop.SellPrice : crop.SellPrice) - crop.SeedPrice;

	// Effort the whole occupancy costs: one planting, then one picking per
	// harvest the species allows.
	public static int Effort(CropType crop) =>
		WorkCost.Of(FarmAction.Plant)
		+ (crop.Regrows ? crop.MaxHarvests : 1) * WorkCost.Of(FarmAction.Harvest);

	public static int V(int daysLeft) => daysLeft <= 0 ? 0 : Best[Math.Min(daysLeft, Best.Length - 1)];

	// One cycle of this crop plus the best that can follow it.
	public static int Value(CropType crop, int daysLeft) =>
		daysLeft < crop.DaysOccupied ? 0 : Profit(crop) + V(daysLeft - crop.DaysOccupied);

	private static int[] Build()
	{
		var best = new int[Simulator.Days];
		for (int r = 1; r < best.Length; r++)
		{
			foreach (var crop in CropTypes.All)
			{
				if (r < crop.DaysOccupied) continue;
				best[r] = Math.Max(best[r], Profit(crop) + best[r - crop.DaysOccupied]);
			}
		}

		return best;
	}
}

// Carrot until the purse can cover a whole field of one chosen species, then
// that species and nothing else. Crude, and on a 36-tile field it beat every
// table-driven line by a wide margin, because the table cannot see that money
// compounds and the field has a floor price.
//
// Kept because a floor is only as honest as the strategies that produced it,
// and a family that plays on a completely different principle is the cheapest
// way to find out whether the table-driven family is leaving money behind.
public sealed class FillTheField : Strategy
{
	private readonly CropType _target;
	private readonly int _reserveDays;

	public FillTheField(CropType target, int reserveDays)
	{
		_target = target;
		_reserveDays = reserveDays;
	}

	protected override string BaseName => $"penuhi ladang dgn {_target.Name} (tahan {_reserveDays}h)";

	public override void PlayDay(RunState run, IReadOnlyList<Vector2I> field)
	{
		foreach (var pos in field) run.TryHarvest(pos, out _);

		var daysLeft = Simulator.Days - run.Calendar.RunDay;
		var next = run.Debt.NextFrom(run.Calendar.RunDay);
		var reserve = next is Payment payment && payment.Day - run.Calendar.RunDay <= _reserveDays
			? payment.Amount
			: 0;

		BuyLand(run, reserve);
		field = Simulator.Field(run);

		// Read after the purchase on purpose, and it bites here in a way it does
		// not in ChainValue: this line is the whole of the strategy's patience,
		// and buying land makes the field it has to fill larger. A run that buys
		// a strip has just raised its own bar for switching off carrot, which is
		// a real cost of expansion and one no other policy in this file pays.
		var fieldPrice = field.Count * _target.SeedPrice;
		var purse = run.Economy.Gold + run.Inventory.TotalValue;

		// Below the field price the target is unaffordable in bulk, so the money
		// is worth more compounding than committed. Carrot is the only crop that
		// compounds fast enough for that to be true.
		var wanted = purse >= fieldPrice + reserve && daysLeft >= _target.DaysOccupied
			? _target
			: CropTypes.Carrot;

		foreach (var pos in field)
		{
			if (daysLeft < wanted.DaysOccupied) break;
			if (run.Economy.Gold + run.Inventory.TotalValue - wanted.SeedPrice < reserve) break;

			Plant(run, pos, wanted);
		}

		foreach (var pos in field) run.TryTill(pos);
	}
}
