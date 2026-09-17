using System;
using System.Collections.Generic;
using Godot;

public class FarmGrid
{
	// Side of the whole map, water included, when the caller does not ask for a
	// specific size.
	public const int DefaultGridSize = 100;

	// The seed a run gets when the caller does not pick one. Zero means "roll
	// one", so the game gets a different island every launch and the harness gets
	// the same one every time by naming a number.
	public const int NoSeed = 0;

	// Side of the square the player already owns on a fresh save.
	//
	// Paired with Energy.DailyBudget and only correct together: 25 tiles worked
	// entirely on carrots costs 16.7 effort a day against a budget of 18. Six a
	// side would be 24 a day against the same 18, which is not a field that is
	// hard to keep up with — it is a field that cannot be run at all.
	//
	// Since 4.1 it is also only the opening size. It stays the smaller half of a
	// decision Phase 4 sells: a field that feels tight is motivation, and the
	// answer to it is now on sale at the edge.
	public const int StartingFarmSize = 5;

	// Full array size. Fixed for the lifetime of this grid, the field never
	// reallocates, but a different run may build a different size.
	public int GridSize { get; }

	// The island this run was dealt. Kept so a run can be replayed, and so the
	// harness can say which seed a result came from — a policy that dies on one
	// island and thrives on the next is telling you about the generator, not
	// about the policy, and without this there is no way to tell the two apart.
	public int Seed { get; }

	// Kept in the center so expansion is possible in all four directions.
	public Vector2I StartingFarmOrigin { get; }

	// Handy for player spawn and camera framing.
	public Vector2I StartingFarmCenter { get; }

	// What a tile of land costs in this run. Held rather than read from
	// LandPrice at the point of sale, for the reason Debt's schedule arrives
	// through a constructor: it is the number under tuning, and the harness
	// plays the same policies against a dozen values of it in one process.
	public int LandPricePerTile { get; }

	private readonly Tile[,] _tiles;

	public FarmGrid(int gridSize = DefaultGridSize, int landPricePerTile = LandPrice.PerTile,
		int seed = NoSeed)
	{
		GridSize = gridSize;
		LandPricePerTile = landPricePerTile;
		Seed = seed != NoSeed ? seed : System.Environment.TickCount;

		StartingFarmOrigin = new Vector2I(
			(GridSize - StartingFarmSize) / 2, (GridSize - StartingFarmSize) / 2);
		StartingFarmCenter =
			StartingFarmOrigin + new Vector2I(StartingFarmSize / 2, StartingFarmSize / 2);

		OwnedOrigin = StartingFarmOrigin;
		OwnedSize = new Vector2I(StartingFarmSize, StartingFarmSize);

		_tiles = new Tile[GridSize, GridSize];

		for (int x = 0; x < GridSize; x++)
		{
			for (int y = 0; y < GridSize; y++)
			{
				// Wild ground with nothing standing on it, which is exactly what
				// a default Tile already means. What it is made of comes next.
				_tiles[x, y] = new Tile();
			}
		}

		// The island is dealt before anything else reads a tile, so there is no
		// moment at which the grid exists with no terrain in it.
		MapGenerator.Generate(_tiles, GridSize, StartingFarmCenter, Seed);

		foreach (var tile in _tiles)
		{
			if (tile.Terrain.IsBuyable()) BuyableTileCount++;
		}
	}

	// The field, as a rectangle rather than as a flag on every tile. This is the
	// whole of what ownership is, and holding it in one place is what makes the
	// purchase rule impossible to break: LandStrip grows this rectangle by one
	// row or column, so a field that is not a rectangle has no way to exist and
	// "the player owns two disconnected patches" is not a state the game can be
	// put into.
	//
	// The invariant everything below leans on: this rectangle is always wholly
	// inside the array, because TryBuyLand refuses a strip that is not.
	public Vector2I OwnedOrigin { get; private set; }
	public Vector2I OwnedSize { get; private set; }

	public int OwnedTileCount => OwnedSize.X * OwnedSize.Y;

	// Every tile of the field. Enumerated from the rectangle, so nothing outside
	// this class has to know how ownership is stored — the harness asked the old
	// grid for a hardcoded 5x5 and would have kept farming 25 tiles of a field
	// that had grown to 40.
	public IEnumerable<Vector2I> OwnedPositions()
	{
		for (int x = 0; x < OwnedSize.X; x++)
		{
			for (int y = 0; y < OwnedSize.Y; y++)
			{
				yield return OwnedOrigin + new Vector2I(x, y);
			}
		}
	}

	// Inside the array. The cursor hides itself when this is false.
	public bool IsInsideBounds(Vector2I pos)
	{
		return pos.X >= 0 && pos.X < GridSize && pos.Y >= 0 && pos.Y < GridSize;
	}

	// How much of this island could ever be farmed. Counted once, at build time,
	// because it is a fact about the map rather than about the run — and because
	// it is the number a report wants: "the seed dealt you 1,240 workable tiles"
	// says something about a run that the grid size never could.
	public int BuyableTileCount { get; private set; }

	// What this tile is made of. Water for anything off the array, so a caller
	// that walks off the edge gets sea rather than an exception — the map has no
	// border, it just stops being land.
	public Terrain TerrainAt(Vector2I pos)
	{
		return IsInsideBounds(pos) ? _tiles[pos.X, pos.Y].Terrain : Terrain.Water;
	}

	// Land rather than sea. The renderer asks this to decide where to stop
	// drawing the island, and the purchase rule asks it too — so the coastline
	// the player sees is the coastline the rules use, rather than two shapes
	// that agree until one of them is edited.
	public bool IsLand(Vector2I pos) => TerrainAt(pos).IsLand();

	// Every cell of the map, for the renderer. The island is no longer a
	// rectangle anyone can enumerate, so the whole grid is walked and each tile
	// says what it is — which is also the only version that stays correct when
	// the generator's rules change.
	public IEnumerable<Vector2I> AllPositions()
	{
		for (int x = 0; x < GridSize; x++)
		{
			for (int y = 0; y < GridSize; y++)
			{
				yield return new Vector2I(x, y);
			}
		}
	}

	// Part of the field. Outside it the cursor still draws, just differently.
	//
	// No bounds test, and none is needed: the owned rectangle is kept inside the
	// array, so anything inside it is inside the array too. One question, asked
	// once.
	public bool IsOwned(Vector2I pos)
	{
		return pos.X >= OwnedOrigin.X && pos.X < OwnedOrigin.X + OwnedSize.X
			&& pos.Y >= OwnedOrigin.Y && pos.Y < OwnedOrigin.Y + OwnedSize.Y;
	}

	// Two refusals, and ownership is no longer one of them. The land itself can
	// be impassable — sea, trees, rock — and something standing on it can block.
	//
	// Dropping the ownership test is the change the town forced, and it is a
	// real change to how the game feels rather than a tidy-up. Until now the
	// player was penned inside the field and every tile they could reach was a
	// tile they could work; now they can walk the whole island, cross the bridge
	// and stand in a town they will never own.
	//
	// Nothing about farming loosens with it. Owning is still what TryTill,
	// TryPlant and TryHarvest ask for, and strips are still offered against the
	// field's edges rather than against wherever the player happens to be
	// standing — so walking somewhere buys nothing, it just lets you go and look.
	public bool IsWalkable(Vector2I pos)
	{
		if (!IsInsideBounds(pos)) return false;
		if (_tiles[pos.X, pos.Y].Terrain.BlocksMovement()) return false;

		return _tiles[pos.X, pos.Y].IsWalkable;
	}

	// The four strips on sale: one along each edge of the field, each as wide as
	// the field is on that axis. A strip that would reach past the shore is not
	// offered, which is the only thing stopping the field from growing into the
	// sea — and the reason the purchase rule needs no separate bounds check.
	//
	// Returned in Direction order, so a caller that wants a stable "first
	// buyable strip" gets the same one twice.
	public IEnumerable<LandStrip> BuyableStrips()
	{
		var wide = new Vector2I(OwnedSize.X, 1);
		var tall = new Vector2I(1, OwnedSize.Y);

		var above = new LandStrip(OwnedOrigin - new Vector2I(0, 1), wide, LandPricePerTile);
		var below = new LandStrip(OwnedOrigin + new Vector2I(0, OwnedSize.Y), wide, LandPricePerTile);
		var left = new LandStrip(OwnedOrigin - new Vector2I(1, 0), tall, LandPricePerTile);
		var right = new LandStrip(OwnedOrigin + new Vector2I(OwnedSize.X, 0), tall, LandPricePerTile);

		foreach (var strip in new[] { above, below, left, right })
		{
			if (Fits(strip)) yield return strip;
		}
	}

	// Which strip this tile would be bought as part of, or null if buying it is
	// not on offer — it is already owned, it is off the map, or it sits past the
	// edge strips, which includes the four diagonal corners belonging to no
	// strip at all.
	//
	// The price lives on the strip rather than being computed by whoever is
	// about to pay, for the reason AvailableAction exists: a caller that works
	// out the cost for itself is a second copy of the rule, and the readout
	// saying "Beli 5 tile 550" has to agree with what the purse is charged.
	public LandStrip? StripAt(Vector2I pos)
	{
		if (!IsInsideBounds(pos) || IsOwned(pos)) return null;

		foreach (var strip in BuyableStrips())
		{
			if (strip.Contains(pos)) return strip;
		}

		return null;
	}

	// Every tile of it open grass — not just the two ends, and that is the change
	// that finally gives the four edges different answers.
	//
	// Before the map had terrain, a strip was refused only for leaving the
	// array, so all four directions were interchangeable and "which edge do I
	// buy" had no answer worth thinking about. Now one boulder anywhere along a
	// row refuses the whole row, and the player has to read the ground and grow
	// the other way. That is the decision 4.1 was missing and could not have
	// without a map that is not the same in every direction.
	//
	// The whole strip rather than a short one, for the reason the old version
	// checked both ends: a strip that stops early would let the field stop being
	// as wide as it is, and the rectangle is what the whole purchase rule rests
	// on.
	private bool Fits(LandStrip strip)
	{
		foreach (var pos in strip.Positions())
		{
			if (!TerrainAt(pos).IsBuyable()) return false;
		}

		return true;
	}

	// What this tile would accept right now, and null for the tiles that will
	// not take anything: outside the array, too far out to buy, blocked by a
	// rock, or holding a crop that is not ready.
	//
	// Every refusal in the file now lives in this one method, and the four Try
	// methods below are each one line of it. That matters more than the lines
	// it saves: the readout telling the player "Cangkul 3" has to ask the same
	// question the hoe asks, and two methods computing that separately are two
	// methods that can disagree after the next rule is added.
	//
	// Ownership no longer short-circuits the whole method, and that is the one
	// structural change 4.1 makes here. It used to be the first refusal for
	// every action because every action needed owned land; buying is the action
	// that needs the opposite, so ownership is now the fork rather than the
	// gate. It still comes first, and it still answers the bounds question for
	// everything below it.
	public FarmAction? AvailableAction(Vector2I pos)
	{
		// Unowned land invites exactly one thing, and only where a strip reaches.
		// StripAt answers the bounds question on this branch.
		if (!IsOwned(pos)) return StripAt(pos) is null ? null : FarmAction.Buy;

		var tile = _tiles[pos.X, pos.Y];

		// A ripe crop wants picking; an unripe one wants leaving alone. Anything
		// else standing on the tile has to be cleared before the tile is worth
		// anything, and clearing is not a tool that exists yet.
		if (tile.Occupant is Crop crop) return crop.IsRipe ? FarmAction.Harvest : null;
		if (tile.Occupant is not null) return null;

		// Bare ground, so the only question left is whether it is broken. Wild
		// ground wants the hoe even though nothing is on it, and that refusal is
		// what makes the hoe worth carrying.
		return tile.Ground == GroundState.Tilled ? FarmAction.Plant : FarmAction.Till;
	}

	// False means nothing changed, whichever of the refusals it was. If the
	// player ever needs to be told which, AvailableAction already knows.
	public bool TryTill(Vector2I pos)
	{
		if (AvailableAction(pos) != FarmAction.Till) return false;

		_tiles[pos.X, pos.Y].Ground = GroundState.Tilled;
		return true;
	}

	// Same shape. Which seed goes in is the caller's business; whether anything
	// may go in at all is this method's.
	public bool TryPlant(Vector2I pos, CropType type)
	{
		if (AvailableAction(pos) != FarmAction.Plant) return false;

		_tiles[pos.X, pos.Y].Occupant = new Crop(type);
		return true;
	}

	// Same shape a third time. The yield leaves through an out parameter instead
	// of being deposited anywhere, because a grid that knows what an inventory
	// is could not be reused by anything without pockets — that dependency runs
	// the wrong way. Whoever owns both sides joins them.
	public bool TryHarvest(Vector2I pos, out CropType yield)
	{
		yield = null;

		if (AvailableAction(pos) != FarmAction.Harvest) return false;

		var tile = _tiles[pos.X, pos.Y];
		var crop = (Crop)tile.Occupant;
		yield = crop.Type;

		// The crop decides whether it survives being picked; the tile is only
		// cleared when it does not.
		var stillStanding = crop.Harvest();
		if (!stillStanding) tile.Occupant = null;

		return true;
	}

	// The fourth action, and the same shape a fourth time. The land arrives as
	// wild ground with whatever is standing on it left standing — buying a tile
	// buys the right to work it, not a tile that has been worked.
	//
	// Nothing here knows what a strip costs or whether the purse can cover it.
	// Money is RunState's, the same way the seed price is, and the strip is
	// handed back so the caller that does hold the purse can charge the figure
	// this class already computed rather than a second one of its own.
	public bool TryBuyLand(Vector2I pos, out LandStrip bought)
	{
		bought = default;

		if (AvailableAction(pos) != FarmAction.Buy) return false;

		bought = StripAt(pos).Value;

		// Union of two rectangles that share a full edge, which is the only kind
		// of strip StripAt returns — so this cannot produce anything but a
		// rectangle, and the field's shape invariant holds by construction
		// rather than by being checked afterwards.
		var min = new Vector2I(
			Math.Min(OwnedOrigin.X, bought.Origin.X),
			Math.Min(OwnedOrigin.Y, bought.Origin.Y));
		var max = new Vector2I(
			Math.Max(OwnedOrigin.X + OwnedSize.X, bought.Origin.X + bought.Size.X),
			Math.Max(OwnedOrigin.Y + OwnedSize.Y, bought.Origin.Y + bought.Size.Y));

		OwnedOrigin = min;
		OwnedSize = max - min;
		return true;
	}

	// Loops the whole grid on purpose. 576 checks once a day is nothing, and
	// the honest fix if it ever stops being nothing is a list of planted tiles
	// kept up to date by planting and harvesting, not a cleverer loop here.
	public void GrowCrops()
	{
		foreach (var tile in _tiles)
		{
			if (tile.Occupant is Crop crop) crop.Grow();
		}
	}

	// Returns unowned tiles on purpose. Standing at the edge of the field and
	// facing empty land is a valid state, and that is how land gets bought.
	// Only out-of-array gives null.
	public Tile GetTile(Vector2I pos)
	{
		return IsInsideBounds(pos) ? _tiles[pos.X, pos.Y] : null;
	}
}
