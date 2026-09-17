// What a tile of the world is made of, before anyone farms it.
//
// A third axis on Tile, and the argument for it is the one Tile.cs already
// makes about the other two: this is a different question from "has it been
// hoed" and from "what is standing on it". A mountain is not an occupant you
// could clear and it is not a state of the soil — it is what the land is, it
// was there before the run started, and nothing in a run changes it.
//
// That permanence is the whole point. Ground and Occupant are what the player
// does to the world; this is the world they were given, and it is what makes
// one run's island different from the next one's.
public enum Terrain
{
	// Sea. Not land, cannot be entered, cannot be bought, and the only member
	// for which all three are true.
	Water,

	// The beach. Land and walkable, but nothing grows in salt sand — so it is
	// the one terrain that is land and still not for sale. It exists because an
	// island needs a shore for its coastline to be drawn against the sea, and
	// because "you have reached the edge of the world" reads better as a beach
	// than as an invisible refusal.
	Sand,

	// Open ground. The only terrain that can be bought and farmed, which makes
	// its shape the shape of the whole game: where the grass is, is where the
	// farm can go.
	Grass,

	// Trees. Land, blocks walking, and not for sale — for now. This is the
	// terrain most likely to change: clearing forest into grass is the obvious
	// home for the work-over-several-days idea that Debris.WorkRemaining was
	// built for in Phase 2 and has never been used for.
	Forest,

	// Rock and height. Land, blocks walking, never for sale and never cleared.
	// Forest is an obstacle the player might one day remove; this is the one
	// that answers "no" permanently, and a map needs some of those or every
	// direction is eventually the same direction.
	Mountain,

	// The little island across the water, where other people live. Land, walked
	// on freely, and never for sale — not because it is difficult but because it
	// is not yours and never will be.
	//
	// A terrain rather than a flag on the tiles, because "can this be bought"
	// already has exactly one home and adding a second way to answer it is how
	// the two start disagreeing. The town is simply made of a material that
	// nobody sells.
	Town,

	// Planks over the sea. Not land — there is water under it — but walkable,
	// and the only member for which those two differ. That pair is the whole
	// reason it exists: the bridge is what makes the town reachable without
	// making the strait farmable.
	Bridge,
}

public static class TerrainRules
{
	// Sea or not — solid ground that the island's soil is drawn under.
	//
	// The bridge is deliberately not land: there is water beneath it, and the
	// renderer has to keep drawing sea there or the strait would silently become
	// a sandbar. Walkable and land are separate questions and the bridge is the
	// tile that proves it.
	public static bool IsLand(this Terrain terrain) =>
		terrain is not (Terrain.Water or Terrain.Bridge);

	// Can a strip of this ever be bought. Grass and only grass: sand is barren,
	// forest and mountain are in the way, water is not land.
	//
	// One method, asked by FarmGrid.BuyableStrips and by nothing else that
	// decides — the cursor and the readout ask AvailableAction, which asks this.
	// That chain is what stops the map the player sees from disagreeing with the
	// map the purchase rule believes in.
	public static bool IsBuyable(this Terrain terrain) => terrain == Terrain.Grass;

	// Physical passability of the land itself, before anything standing on it
	// gets a say. Deliberately separate from the occupant's own BlocksMovement:
	// a crop on grass is walkable, a crop could never be on a mountain, and the
	// two refusals have different reasons.
	//
	// Sand, town and bridge are all walked on and none of them can be farmed,
	// which is the combination that lets the player leave the farm and come
	// back without the farm growing an inch.
	public static bool BlocksMovement(this Terrain terrain) =>
		terrain is Terrain.Water or Terrain.Forest or Terrain.Mountain;
}
