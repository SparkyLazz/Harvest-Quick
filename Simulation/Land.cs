using System.Collections.Generic;
using Godot;

// One purchasable piece of land: a single row or column running the full width
// of the field, lying immediately outside one of its four edges.
//
// This type is the answer to all three questions Phase 4 opens with, which is
// why they are answered here rather than in three places.
//
// Satuan. Per tile would be twenty-five small decisions that are all the same
// decision, and the readout would say "Beli 1 tile" twenty-five times. A fixed
// plot lattice was the obvious alternative and it cannot be made to line up:
// the starting farm is five a side, five is prime, so any plot larger than one
// tile straddles the farm boundary and the player would be charged full price
// for tiles they already hold. A strip is the only unit that is always exactly
// the tiles not yet owned, whatever the field has grown to.
//
// Kedekatan. Required, and required for free. The field is a rectangle grown
// one edge at a time, so "next to the field" is not a rule that anything has to
// check — it is the only shape this data can take. There is no code path that
// buys the far corner of the map because there is no way to write one down.
// What is left to decide is which of the four edges, and that question has an
// answer the moment 4.3 scatters rock: at equal distance from the centre the
// four edges hold the same expected amount of debris and different actual
// amounts, so choosing an edge becomes reading the map.
//
// The unit widens as the field does — the first strip bought is five tiles, the
// fourth is seven — so the commitment escalates without a second price rule to
// tune. That widening and the calendar running out are between them the whole
// reason a run does not simply buy land until the map is gone.
public readonly record struct LandStrip(Vector2I Origin, Vector2I Size, int PricePerTile)
{
	public int TileCount => Size.X * Size.Y;

	// Harga. Per tile and nothing else. A strip already costs more as the field
	// grows, because it is wider, and a tile already earns less as the calendar
	// runs out, because there are fewer days to farm it — so a second escalating
	// term would be tuning the same pressure twice and the two could disagree
	// about which way it should lean.
	//
	// The rate rides on the offer rather than being read from the constant
	// below, for the reason Debt takes its schedule through a constructor: this
	// is the number being tuned, and tuning it means playing the same hundred
	// runs against a dozen values of it in one process. It is also where 4.3's
	// "land gets dearer the further out you go" would land, if the harness ever
	// says that pressure is needed — the offer already carries its own rate, so
	// nothing downstream would have to change.
	public int Price => TileCount * PricePerTile;

	public bool Contains(Vector2I pos) =>
		pos.X >= Origin.X && pos.X < Origin.X + Size.X &&
		pos.Y >= Origin.Y && pos.Y < Origin.Y + Size.Y;

	public IEnumerable<Vector2I> Positions()
	{
		for (int x = 0; x < Size.X; x++)
		{
			for (int y = 0; y < Size.Y; y++)
			{
				yield return Origin + new Vector2I(x, y);
			}
		}
	}
}

// What land costs, in one number, for the same reason WorkCost is one table:
// this is the figure being tuned and tuning it means running the same run
// against a hundred values of it.
public static class LandPrice
{
	// 50 a tile, so the opening strip of five costs 250 and the comparison the
	// player is actually making reads in one line: a square of dirt forever, or
	// most of one pumpkin seed this cycle.
	//
	// It came off the harness rather than out of taste, and the band is narrow
	// enough that taste would have missed it. What the sweep measures is not
	// profit but the gap between the best run that buys land and the best run by
	// the same farmer that does not:
	//
	//   42/tile   buys +550 over not buying — the first strip lands on h10 and
	//             compounds; there is no decision, only a delay in taking it.
	//   45        +140
	//   50        +115   <- shipped
	//   55         +25
	//   58         -75   buying has become a mistake
	//   66        -1320  the one policy that still buys goes broke doing it
	//
	// Anywhere in 45..55 land is a real question and the answer is close. The
	// middle is taken because the two failure modes are not symmetric: too cheap
	// silently deletes the decision, while too dear merely leaves the fourth
	// action unused and visible in the harness.
	//
	// Why the band sits here at all is worth keeping, because the naive figure
	// is ten times larger. A tile held from day 1 earns V(29) = 425, and at any
	// price near that land would never be refused. But the marginal tile is
	// priced by effort, not by the calendar: 25 tiles of carrot already costs
	// 16.7 of an 18 effort budget, so the farm is close to saturated before a
	// single strip is bought, and every tile added has to be paid for twice —
	// once here and once at three effort for the hoe. That is why the answer is
	// a fifth of 425 and not half of it.
	//
	// Expect it to fall once 4.2 puts rock on the land being sold. Clearing
	// spends the same effort that makes a tile worth owning, so debris is part
	// of the price in everything but name, and this constant is the half of it
	// that has to give way.
	public const int PerTile = 50;
}
