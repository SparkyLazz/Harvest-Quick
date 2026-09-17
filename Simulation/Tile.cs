// The soil itself. Every tile always has one, there is no such thing as a tile
// without ground, so this axis is an enum with no empty member.
public enum GroundState
{
	Wild,
	Tilled,
}

// What the object layer is told to draw. Deliberately a name and not an atlas
// coordinate: Simulation must not know which sheet the art lives on, and the
// mapping from name to cell belongs in GameConfig with every other tileset
// detail.
//
// Crops are not in this list and cannot be. Thirteen of the twenty crop sheets
// are taller than one tile and two are wider, and this whole path assumes one
// tile-sized cell. They render elsewhere.
public enum TileSprite
{
	Fence,
	Rock,
	Wood,
}

// Everything that can stand on a tile. A base class and not an interface,
// because this is a category and not a capability: an interface says what a
// type can do and invites unrelated types to implement it, a base class says
// what a type is, and "the thing occupying this tile" is a closed family.
// Single inheritance costs nothing here precisely because occupancy is
// exclusive, and the class buys what an interface cannot: shared state and a
// shared default, both used by Debris below.
//
// Only one question is genuinely universal. An earlier version of this file
// also demanded a sprite from every occupant, on the assumption that every
// occupant is one tile-sized static image. Crops broke that assumption, so the
// sprite question moved down to the objects it is actually true for.
public abstract class TileObject
{
	public abstract bool BlocksMovement { get; }
}

// Objects that draw as a single tile-sized cell on the object layer. The split
// is by render path, not by kind of thing, which is why RenderCell needs one
// type test rather than one per type.
public abstract class TileSpriteObject : TileObject
{
	// Computed by the object itself rather than looked up from outside, because
	// only it knows its own state.
	public abstract TileSprite Sprite { get; }
}

// Rock and wood are the same kind of problem: something lying on the land that
// takes a few days of work to clear. This shared field is the concrete reason
// the hierarchy is classes rather than interfaces.
public abstract class Debris : TileSpriteObject
{
	// Days of work left before the tile is free. Counted down by the tool, not
	// by the tile.
	public int WorkRemaining { get; set; }

	public override bool BlocksMovement => true;
}

public sealed class Rock : Debris
{
	public override TileSprite Sprite => TileSprite.Rock;
}

public sealed class Wood : Debris
{
	public override TileSprite Sprite => TileSprite.Wood;
}

// Player-placed, so not debris: pulling it out is a decision, not a chore. If
// fences ever need work to remove, they move under Debris and nothing else in
// the file changes.
public sealed class Fence : TileSpriteObject
{
	public override TileSprite Sprite => TileSprite.Fence;
	public override bool BlocksMovement => true;
}

// Off the TileSprite path entirely: a crop's picture depends on its species and
// its stage, and most species do not fit in a 16x16 cell. It carries no art of
// its own, only what it is and how far along it is.
public sealed class Crop : TileObject
{
	// A crop without a species is not a thing, so it has no way to be written.
	public Crop(CropType type)
	{
		Type = type;
	}

	public CropType Type { get; }

	// Only Grow moves this, so nothing outside can put a crop at a stage its
	// species does not have.
	public int GrowthStage { get; private set; }

	public bool IsRipe => GrowthStage >= Type.DaysToRipen;

	// Moved by Harvest alone, the way GrowthStage is moved by Grow alone, so a
	// plant has no way to reach a count its species does not allow.
	public int HarvestsTaken { get; private set; }

	// Whether picking this plant would also clear the tile. Harvest is the only
	// thing that decides this, so Harvest is where the rule is written and this
	// only asks it one step early.
	//
	// It exists because "is this tile about to come free" is a real question
	// with a real answer, and anything that works it out for itself from
	// HarvestsTaken and MaxHarvests is a second copy of a rule that already
	// lives here. A ripe tomato with pickings left looks exactly like a ripe
	// carrot from outside, and it is not: one frees its tile and the other does
	// not.
	public bool SpentByNextHarvest =>
		Type.RegrowStage is not int || HarvestsTaken + 1 >= Type.MaxHarvests;

	// Walking over your own crop is allowed, same as the old Planted state.
	public override bool BlocksMovement => false;

	// The crop owns its own growth rule. Growth stops at ripe: rotting is a
	// different feature, and counting past DaysToRipen would make it look like
	// one already exists.
	public void Grow()
	{
		if (GrowthStage < Type.DaysToRipen) GrowthStage++;
	}

	// Picking it. The species decides what is left behind: a single-harvest
	// crop comes up with its fruit, one that fruits again stays in the ground
	// and falls back to the stage its type names — until it has been picked as
	// often as its species allows, and then it comes up too.
	//
	// Returns whether the plant is still standing. Pulling it off the tile is
	// the grid's job, because the grid is the only thing holding tiles — the
	// crop knows what should happen, not how to do it.
	//
	// Assumes it is ripe. That rule lives in FarmGrid.TryHarvest with every
	// other refusal, and is not repeated here.
	public bool Harvest()
	{
		var spent = SpentByNextHarvest;
		HarvestsTaken++;

		if (spent) return false;

		GrowthStage = Type.RegrowStage.Value;
		return true;
	}
}

public class Tile
{
	// Axis zero, and it comes first because it decides whether the other two
	// mean anything: what this land is. Written once by MapGenerator and never
	// again — a run changes what is on the land and what has been done to it,
	// never what it is.
	//
	// Water rather than Grass as the default, so a tile nobody generated is sea
	// and therefore inert. The opposite default would make a forgotten tile
	// silently farmable, which is the kind of bug that looks like a feature.
	public Terrain Terrain { get; set; } = Terrain.Water;

	// Axis one: always has a value.
	public GroundState Ground { get; set; } = GroundState.Wild;

	// Axis two: can be empty, and empty is null.
	public TileObject Occupant { get; set; }

	// There was an IsOwned flag here, and it is gone. The comment defending it
	// said the two axes above say what the tile is while ownership says what the
	// player may do with it — which was the argument for moving it out, not for
	// keeping it here. Ownership is a fact about the field, not about the soil,
	// and since 4.1 the field is a rectangle: FarmGrid holds that rectangle and
	// answers IsOwned from it. A flag per tile could disagree with the shape the
	// purchase rule believes it is maintaining; a rectangle cannot disagree with
	// itself.

	// Physical passability only. Ownership is FarmGrid's question and it
	// already asks it separately in FarmGrid.IsWalkable. Ground has no say
	// here, so a new ground type cannot break walking, and a new object type
	// answers for itself.
	public bool IsWalkable => Occupant is null || !Occupant.BlocksMovement;
}
