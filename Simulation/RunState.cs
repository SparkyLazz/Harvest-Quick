using Godot;

// Why a run stopped. One member today, because there is one way to stop.
//
// An enum behind a nullable rather than a bool, for the reason RegrowStage is
// an int? instead of a bool beside an int: "the run is over and nobody said
// why" has no way to be written down. A bool would make the shorter path the
// wrong one — the readout would have to work out for itself whether the run
// ending was a good thing, and it would work it out from the purse, which is
// exactly the kind of second derivation AvailableAction was written to kill.
//
// When Phase 5 adds a way to win, it adds a member here and every place that
// reads Outcome has to say what it means. That is the point of the shape.
public enum RunOutcome
{
	// A payment fell due and the money was not there.
	Bankrupt,
}

// One run of the game: the clock, the land, and the player who works it. Built
// together and held together, so starting a run over is one assignment instead
// of three that can drift apart.
public class RunState
{
	public Calendar Calendar { get; }
	public FarmGrid Grid { get; }
	public PlayerState Player { get; }
	public Inventory Inventory { get; }
	public Economy Economy { get; }
	public Energy Energy { get; }
	public Debt Debt { get; }

	// Null while the run is still being played. Set once and never cleared:
	// starting over builds a new RunState, the same way a new run gets a new
	// grid and an empty bag.
	public RunOutcome? Outcome { get; private set; }

	public bool IsOver => Outcome.HasValue;

	// The schedule and the price of land arrive through the constructor for the
	// same reason starting gold and the daily budget do: they are the numbers
	// being tuned, and tuning them means running the same run against a hundred
	// of them. Omitting either takes the one the game ships with.
	public RunState(int gridSize = FarmGrid.DefaultGridSize, Debt debt = null,
		int landPricePerTile = LandPrice.PerTile, int seed = FarmGrid.NoSeed)
	{
		Grid = new FarmGrid(gridSize, landPricePerTile, seed);
		Calendar = new Calendar();
		Inventory = new Inventory();
		Economy = new Economy();
		Energy = new Energy();
		Debt = debt ?? new Debt();
		Player = new PlayerState(Grid, Grid.StartingFarmCenter.X, Grid.StartingFarmCenter.Y);
	}

	// Where the two halves of a harvest meet. FarmGrid takes the crop off the
	// tile and hands back what came off; Inventory takes it in. Neither knows
	// the other exists, and neither should: a grid that knew about pockets
	// could not be reused by anything without them.
	//
	// This is RunState's actual job, the same one AdvanceDay does — it is the
	// only thing here that owns both sides, so it is the only thing that can
	// join them without pointing a dependency the wrong way.
	//
	// Note the asymmetry with TryTill and TryPlant, which are still reached
	// through Player. That is not an oversight: those touch the grid alone, and
	// the call site saying so is useful. When planting starts spending a seed
	// out of the inventory, it moves up here for exactly this reason.
	// Takes the tile it works on. That is the base form of all four actions
	// here, and the no-argument wrappers below fill in the tile the player is
	// facing — the same split FarmGrid and PlayerState already use, where the
	// rule lives in one place and the aiming lives in a wrapper.
	//
	// It matters beyond tidiness. Until this existed, nothing could work a tile
	// without walking a player to it, so the harness that sets the bill schedule
	// had to restate these refusals in its own words. A schedule tuned against a
	// restatement is a schedule tuned against something that can already have
	// drifted.
	public bool TryHarvest(Vector2I pos, out CropType yield)
	{
		var work = WorkCost.Of(FarmAction.Harvest);
		yield = null;

		if (IsOver) return false;
		if (!Energy.CanAfford(work)) return false;
		if (!Grid.TryHarvest(pos, out yield)) return false;

		Inventory.Add(yield);
		Energy.Spend(work);
		return true;
	}

	public bool TryHarvest(out CropType yield)
	{
		return TryHarvest(Player.FacingPosition, out yield);
	}

	// Up here with the other two now, for the same reason they are: it costs a
	// day's effort, and Energy lives at this level.
	//
	// Nothing here decides whether the ground can be broken. That is still
	// FarmGrid's, asked once in AvailableAction.
	public bool TryTill(Vector2I pos)
	{
		var work = WorkCost.Of(FarmAction.Till);

		if (IsOver) return false;
		if (!Energy.CanAfford(work)) return false;
		if (!Grid.TryTill(pos)) return false;

		Energy.Spend(work);
		return true;
	}

	public bool TryTill()
	{
		return TryTill(Player.FacingPosition);
	}

	// Moved up from PlayerState, exactly as the note above said it would be the
	// day planting started spending a seed. It now touches the purse and the
	// grid, and this is the only thing holding both.
	//
	// Four refusals in an order that is not arbitrary, and the same order all
	// four actions use: effort first, because it is the budget that runs out
	// soonest and the one the player cannot top up; then the action's own price,
	// here the seed; then the grid, unchanged and still living in FarmGrid. Both
	// charges last, after every question has been answered yes, so there is no
	// way to rearrange these lines that spends anything on a seed which never
	// went into the ground.
	public bool TryPlant(Vector2I pos, CropType type)
	{
		var work = WorkCost.Of(FarmAction.Plant);

		if (IsOver) return false;
		if (!Energy.CanAfford(work)) return false;
		if (!Economy.CanAfford(type.SeedPrice)) return false;
		if (!Grid.TryPlant(pos, type)) return false;

		Economy.Spend(type.SeedPrice);
		Energy.Spend(work);
		return true;
	}

	public bool TryPlant(CropType type)
	{
		return TryPlant(Player.FacingPosition, type);
	}

	// Land. The same four refusals in the same order as planting — effort, then
	// the action's own price, then the grid — and the order is load-bearing for
	// the same reason: there is no rearrangement of these lines that pays for a
	// strip which was never added to the field.
	//
	// The one thing that differs from the other three is that the price is not a
	// constant the caller already knows. It is asked of the grid, once, before
	// anything is spent, and the strip that comes back out of TryBuyLand is the
	// same object it was priced from — so the figure charged here and the figure
	// the readout shows cannot come from two different computations.
	//
	// Up here rather than in FarmGrid because it spends gold, which is the exact
	// argument that moved planting up in 3.2. A grid that knew what a purse was
	// could not be reused by anything without one.
	public bool TryBuyLand(Vector2I pos, out LandStrip bought)
	{
		var work = WorkCost.Of(FarmAction.Buy);
		bought = default;

		if (IsOver) return false;
		if (!Energy.CanAfford(work)) return false;

		// Asked before the grid is touched, so a strip that cannot be paid for
		// is never added and then billed. Null here is the grid refusing the
		// purchase outright, which is the same refusal TryBuyLand would give —
		// asked early only so there is a price to check against.
		if (Grid.StripAt(pos) is not LandStrip offered) return false;
		if (!Economy.CanAfford(offered.Price)) return false;
		if (!Grid.TryBuyLand(pos, out bought)) return false;

		Economy.Spend(bought.Price);
		Energy.Spend(work);
		return true;
	}

	public bool TryBuyLand(out LandStrip bought)
	{
		return TryBuyLand(Player.FacingPosition, out bought);
	}

	// The mirror of TryHarvest, and the third place the two halves meet: the
	// bag says what it is worth and empties, the purse takes it in, neither
	// knows the other exists.
	//
	// Automatic at the end of the day rather than an errand at a market tile.
	// Carrying a full bag across the field is not a decision — the player would
	// make the trip every single time, and a trip with one answer is a queue,
	// not a choice. What is actually being decided is what to grow and when to
	// pick it, and that is settled long before the bag is full.
	private void SellToday()
	{
		var takings = Inventory.TotalValue;
		if (takings == 0) return;

		Inventory.Clear();
		Economy.Earn(takings);
	}

	// A day turning over is two events, not one. Kept as two methods rather
	// than one flat list because the halves answer different questions, and a
	// flat list makes it easy to drop something into the wrong one: a bill that
	// runs after the date moved charges the wrong day and nothing complains.
	public void AdvanceDay()
	{
		// A finished run has no next day. Guarded here rather than only at the
		// input side, so nothing — the harness included — can keep playing one.
		if (IsOver) return;

		EndToday();

		// Asked again because EndToday is where a run ends. Tomorrow must not
		// open on a run that closed tonight: the date would move past the day
		// the player actually lost on, and that day is the only thing the
		// readout has left to show them.
		if (IsOver) return;

		StartTomorrow();
	}

	// Closing today's books. Everything here judges the day that just happened,
	// so all of it must run before the date moves.
	private void EndToday()
	{
		// First, and the order is load-bearing: the bill must be payable with
		// what was picked today. A player who harvests on the morning a payment
		// falls due has earned that money, and the schedule will be tuned as
		// though they are holding it.
		SellToday();

		// Read before anything is spent, so the check below judges the real
		// number rather than whatever is left after it.
		var due = Debt.AmountDueOn(Calendar.RunDay);
		if (due == 0) return;

		// Nothing is taken on the way out, deliberately. A purse emptied here
		// would erase the evidence: how short the player was is the one number
		// worth showing them, and a balance of zero does not say it.
		if (!Economy.CanAfford(due))
		{
			Outcome = RunOutcome.Bankrupt;
			return;
		}

		Economy.Spend(due);
	}

	// Opening tomorrow. The date moves first, because everything after it may
	// want to ask what day it is.
	private void StartTomorrow()
	{
		Calendar.AdvanceDay();

		// Full, and nothing carries over. Yesterday's unspent effort is gone,
		// which is what stops the player banking six quiet days and then doing
		// the whole field in one — the shape this whole mechanic exists to
		// prevent.
		Energy.Restore();

		Grid.GrowCrops();
		// TODO: today's weather
		// TODO: mother's letter, which arrives on a particular day
	}
}
