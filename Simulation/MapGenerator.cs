using System;
using Godot;

// Makes an island. Not one island — rules that make islands, a different one
// per seed, and that difference is the point: a map that is the same every run
// is a map that could have been drawn by hand and saved.
//
// Two dials decide everything, and they pull against each other. Too uniform
// and generating is pointless, because every run gives the same shape with the
// bumps in different places. Too wild and some runs are unwinnable — a farm
// hemmed in by rock on three sides is not a hard run, it is a broken one. The
// guarantee below is what keeps the wild end honest: a cleared disc of grass
// around the start, large enough that the first several strips are always for
// sale whichever way the player faces.
//
// No engine types beyond Vector2I and no System.Random. The noise and the
// shuffling are written out here because the harness plays thousands of runs
// and has to get the same island from the same seed every time, in this build
// and the next one — and Random makes no such promise across runtimes.
public static class MapGenerator
{
	// Land above this, sea below. The single number that decides how much of the
	// map is island; everything else shapes what is left.
	//
	// It was 0.42 and that made islands of about 500 tiles on a 10,000 cell map
	// — nine parts water to one part land, and a coast only nineteen tiles from
	// the middle. The arithmetic is worth keeping because it is not obvious: the
	// shore sits where noise, which averages about a half, stops beating
	// SeaLevel plus the falloff, so lowering this by a tenth moves the coast out
	// much further than a tenth.
	private const float SeaLevel = 0.30f;

	// How hard the map is pulled down to sea at the edges. Without it the noise
	// runs off the side of the array and the island becomes a continent with
	// square corners, which is what the fixed rectangle used to look like.
	private const float FalloffPower = 2.6f;

	// Rock, off a field of its own.
	//
	// Its own, and that is a correction rather than a preference. Mountains used
	// to be the high ground of the same field that decides land and sea, which
	// sounds right and is not: that field has the falloff subtracted from it, so
	// by the time you are far enough from the middle to be outside the starting
	// clearing, the falloff has already eaten more height than any noise peak
	// puts back. Eight seeds out of nine came out with no mountains at all. A
	// separate field has no falloff in it and puts massifs where it likes.
	//
	// Coarse on purpose: at this frequency the field turns over about every
	// eighteen tiles, so rock arrives as ranges rather than as gravel.
	private const float MountainLevel = 0.62f;
	private const float MountainScale = 0.055f;

	// Trees come off their own field too, at a finer scale, so woods are smaller
	// than mountains and sit in the gaps between them.
	private const float ForestLevel = 0.56f;
	private const float ForestScale = 0.11f;

	// Radius, in tiles, of guaranteed open grass around the starting farm.
	//
	// Sized against the purchase rule rather than against taste: a strip is
	// refused unless every tile of it is grass, so this has to cover the field
	// plus several strips in every direction or a seed could open with nothing
	// for sale. 5x5 farm, plus room for six strips a side, plus one.
	private const int ClearRadius = 12;

	// Where the beach ends and the meadow starts, measured in tiles from the
	// sea rather than from a noise value, so the shore is always a shore and
	// never a stripe that happens to fall there.
	private const int SandDepth = 2;

	// The town across the water, and the strait between.
	//
	// Small on purpose: it is somewhere to go, not somewhere to farm, and a town
	// the size of the farm would read as a second island the player had failed
	// to buy. The gap is wide enough that the bridge is visibly a bridge and
	// narrow enough that the crossing is not a journey.
	private const int TownRadius = 6;
	private const int StraitWidth = 5;
	private const int MinStraitWidth = 2;
	private const int BridgeHalfWidth = 1;

	public static void Generate(Tile[,] tiles, int gridSize, Vector2I center, int seed)
	{
		var height = new Noise(seed);
		var trees = new Noise(seed ^ 0x5bf03635);
		var rock = new Noise(seed ^ 0x2f1c7a19);

		// Pass one: sea, land, and the high ground.
		for (int x = 0; x < gridSize; x++)
		{
			for (int y = 0; y < gridSize; y++)
			{
				var elevation = Elevation(height, x, y, gridSize);
				var tile = tiles[x, y];

				// The clearing is tested before the sea, and that ordering is the
				// whole guarantee. Tested after, it only ever overrode forest and
				// rock — so a seed whose height field dipped under sea level at
				// the middle of the map drowned the starting farm, and the run
				// opened with the player standing in the water with nothing for
				// sale in any direction. Nothing but grass may be written here,
				// and now nothing else can be.
				if (WithinClearing(center, x, y))
				{
					tile.Terrain = Terrain.Grass;
					continue;
				}

				if (elevation < SeaLevel)
				{
					tile.Terrain = Terrain.Water;
					continue;
				}

				if (rock.At(x * MountainScale, y * MountainScale) > MountainLevel)
				{
					tile.Terrain = Terrain.Mountain;
					continue;
				}

				tile.Terrain = trees.At(x * ForestScale, y * ForestScale) > ForestLevel
					? Terrain.Forest
					: Terrain.Grass;
			}
		}

		// Pass two: the beach. Separate because it is a fact about distance to
		// water, and distance to water is not known until every tile's terrain
		// is. Written over grass and forest alike — a tree on the sand is not
		// wrong, but a beach that stops where a tree starts looks like a bug.
		for (int x = 0; x < gridSize; x++)
		{
			for (int y = 0; y < gridSize; y++)
			{
				var tile = tiles[x, y];
				if (tile.Terrain is Terrain.Water or Terrain.Mountain) continue;
				if (WithinClearing(center, x, y)) continue;
				if (!NearWater(tiles, gridSize, x, y)) continue;

				tile.Terrain = Terrain.Sand;
			}
		}

		// Pass three: the town and the way to it. Last, so it writes over
		// whatever the island's own rules put there — a town is a decision about
		// the world, not a consequence of the noise, and it has to win.
		StampTown(tiles, gridSize, center, seed);
	}

	// Finds open water off one shore, puts a small island in it, and lays planks
	// across the gap.
	//
	// The direction is drawn from the seed, so the town is somewhere different
	// each run and the player has to look for it. It is the first thing on this
	// map that rewards walking away from the farm.
	private static void StampTown(Tile[,] tiles, int gridSize, Vector2I center, int seed)
	{
		// Four candidates, tried in an order the seed shuffles. One of them has
		// to work or there is no town, so this tries them all rather than
		// trusting the first: an island whose east shore runs close to the edge
		// of the array has no room for a town that way, and that is a normal
		// map, not a broken one.
		var directions = new[]
		{
			new Vector2I(1, 0), new Vector2I(-1, 0), new Vector2I(0, 1), new Vector2I(0, -1),
		};

		// Widest strait first, then narrower, and the retry is not a nicety.
		// Seed 1337 deals the largest island the rules can make — 1,701 tiles of
		// grass — and on that map every shore sits too close to the edge of the
		// array for five tiles of water plus a town to fit. All four headings
		// failed and the run came out with no town and no bridge at all, which
		// for a game with a city in it is not a variation, it is a broken map.
		//
		// A narrower crossing still reads as a crossing, so giving up the gap is
		// much cheaper than giving up the town.
		var first = (seed & 0x7fffffff) % directions.Length;
		for (int strait = StraitWidth; strait >= MinStraitWidth; strait--)
		{
			for (int i = 0; i < directions.Length; i++)
			{
				var step = directions[(first + i) % directions.Length];
				if (TryStamp(tiles, gridSize, center, step, strait)) return;
			}
		}
	}

	private static bool TryStamp(Tile[,] tiles, int gridSize, Vector2I center, Vector2I step, int strait)
	{
		// Walk out from the middle until the land runs out. That is the shore on
		// this heading, and everything else is measured from it — so the strait
		// is always the width it says it is, however far out the coast happens
		// to lie on this seed.
		var shore = center;
		while (true)
		{
			var next = shore + step;
			if (!Inside(gridSize, next)) return false;
			if (tiles[next.X, next.Y].Terrain == Terrain.Water) break;

			shore = next;
		}

		var townCenter = shore + step * (strait + TownRadius);

		// The whole town, not just its middle, has to be on the map — and there
		// has to be sea where it is going. A town stamped over the main island's
		// own far shore would join the two into one landmass and the bridge
		// would cross nothing.
		if (!Inside(gridSize, townCenter + step * TownRadius)) return false;
		if (!Inside(gridSize, townCenter + Perpendicular(step) * TownRadius)) return false;
		if (!Inside(gridSize, townCenter - Perpendicular(step) * TownRadius)) return false;

		for (int x = townCenter.X - TownRadius; x <= townCenter.X + TownRadius; x++)
		{
			for (int y = townCenter.Y - TownRadius; y <= townCenter.Y + TownRadius; y++)
			{
				var pos = new Vector2I(x, y);
				if (!Inside(gridSize, pos)) return false;
				if (tiles[x, y].Terrain != Terrain.Water) return false;
			}
		}

		// Round, so it reads as an island rather than as a plot. Its own beach,
		// for the same reason the main island has one: the soil terrain needs a
		// bare ring to draw a coast against.
		for (int x = townCenter.X - TownRadius; x <= townCenter.X + TownRadius; x++)
		{
			for (int y = townCenter.Y - TownRadius; y <= townCenter.Y + TownRadius; y++)
			{
				var dx = x - townCenter.X;
				var dy = y - townCenter.Y;
				var distance = dx * dx + dy * dy;
				if (distance > TownRadius * TownRadius) continue;

				tiles[x, y].Terrain = distance > (TownRadius - 1) * (TownRadius - 1)
					? Terrain.Sand
					: Terrain.Town;
			}
		}

		// Planks from one shore to the other. Written over water only, so it
		// cannot eat into either island's beach and leave a plank lying on sand.
		var across = Perpendicular(step);
		for (var pos = shore + step; ; pos += step)
		{
			if (!Inside(gridSize, pos)) break;
			if (tiles[pos.X, pos.Y].Terrain != Terrain.Water) break;

			for (int w = -BridgeHalfWidth; w <= BridgeHalfWidth; w++)
			{
				var plank = pos + across * w;
				if (!Inside(gridSize, plank)) continue;
				if (tiles[plank.X, plank.Y].Terrain != Terrain.Water) continue;

				tiles[plank.X, plank.Y].Terrain = Terrain.Bridge;
			}
		}

		return true;
	}

	private static Vector2I Perpendicular(Vector2I step) => new Vector2I(-step.Y, step.X);

	private static bool Inside(int gridSize, Vector2I pos) =>
		pos.X >= 0 && pos.Y >= 0 && pos.X < gridSize && pos.Y < gridSize;

	// The height field: noise pulled down towards the edges of the map.
	private static float Elevation(Noise noise, int x, int y, int gridSize)
	{
		var half = gridSize / 2f;
		var dx = (x - half) / half;
		var dy = (y - half) / half;

		// Round rather than square, so the falloff does not leave four corners
		// of coastline running at right angles.
		var distance = MathF.Min(1f, MathF.Sqrt(dx * dx + dy * dy));
		var falloff = MathF.Pow(distance, FalloffPower);

		// Three octaves. One is a blob, two is a blob with a dent, and three is
		// where bays and headlands start appearing without the shape coming
		// apart into noise.
		var value =
			noise.At(x * 0.035f, y * 0.035f) * 0.6f
			+ noise.At(x * 0.080f, y * 0.080f) * 0.3f
			+ noise.At(x * 0.170f, y * 0.170f) * 0.1f;

		return value - falloff;
	}

	private static bool WithinClearing(Vector2I center, int x, int y)
	{
		var dx = x - center.X;
		var dy = y - center.Y;
		return dx * dx + dy * dy <= ClearRadius * ClearRadius;
	}

	// Within SandDepth tiles of open water, measured square rather than round
	// because a beach a tile wider on the diagonal is not something anyone will
	// ever notice and the round version costs a square root per tile per ring.
	private static bool NearWater(Tile[,] tiles, int gridSize, int x, int y)
	{
		for (int ox = -SandDepth; ox <= SandDepth; ox++)
		{
			for (int oy = -SandDepth; oy <= SandDepth; oy++)
			{
				var nx = x + ox;
				var ny = y + oy;

				// Off the array counts as water. Without this the island would
				// grow a grass edge wherever it touched the border of the map,
				// which is the one place a coastline is guaranteed.
				if (nx < 0 || ny < 0 || nx >= gridSize || ny >= gridSize) return true;
				if (tiles[nx, ny].Terrain == Terrain.Water) return true;
			}
		}

		return false;
	}
}

// Value noise, smooth, in 0..1. Small enough to read in one sitting, which is
// the reason it is here rather than FastNoiseLite: Simulation uses exactly one
// type from the engine and that is a coordinate struct. A run must be
// reproducible from its seed for the harness to mean anything, and that is a
// promise this file can make and a library's internals cannot.
public sealed class Noise
{
	private readonly int _seed;

	public Noise(int seed)
	{
		_seed = seed;
	}

	public float At(float x, float y)
	{
		var x0 = (int)MathF.Floor(x);
		var y0 = (int)MathF.Floor(y);
		var fx = x - x0;
		var fy = y - y0;

		// Smoothstep on both axes: with straight lerp the grid the noise was
		// built on stays visible as a lattice of creases, and on a coastline
		// that reads as unnatural straight runs.
		var sx = fx * fx * (3f - 2f * fx);
		var sy = fy * fy * (3f - 2f * fy);

		var top = Lerp(Corner(x0, y0), Corner(x0 + 1, y0), sx);
		var bottom = Lerp(Corner(x0, y0 + 1), Corner(x0 + 1, y0 + 1), sx);
		return Lerp(top, bottom, sy);
	}

	private static float Lerp(float a, float b, float t) => a + (b - a) * t;

	// One hash per lattice point. Integer mixing rather than a table, so there
	// is no array to size and no wrap-around to think about.
	private float Corner(int x, int y)
	{
		unchecked
		{
			var h = x * 374761393 + y * 668265263 + _seed * 1274126177;
			h = (h ^ (h >> 13)) * 1274126177;
			h ^= h >> 16;
			return (h & 0x7fffffff) / (float)0x7fffffff;
		}
	}
}
