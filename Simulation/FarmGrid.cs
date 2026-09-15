using Godot;

public class FarmGrid
{
	// Full array size. Fixed for the whole game, the field never reallocates.
	public const int GridSize = 24;

	// Side of the square the player already owns on a fresh save.
	public const int StartingFarmSize = 6;

	// Kept in the center so expansion is possible in all four directions.
	public static readonly Vector2I StartingFarmOrigin =
		new((GridSize - StartingFarmSize) / 2, (GridSize - StartingFarmSize) / 2);

	// Handy for player spawn and camera framing.
	public static readonly Vector2I StartingFarmCenter =
		StartingFarmOrigin + new Vector2I(StartingFarmSize / 2, StartingFarmSize / 2);

	private readonly Tile[,] _tiles = new Tile[GridSize, GridSize];

	public FarmGrid()
	{
		for (int x = 0; x < GridSize; x++)
		{
			for (int y = 0; y < GridSize; y++)
			{
				_tiles[x, y] = new Tile
				{
					State = TileState.Grass
				};
			}
		}

		for (int x = 0; x < StartingFarmSize; x++)
		{
			for (int y = 0; y < StartingFarmSize; y++)
			{
				_tiles[StartingFarmOrigin.X + x, StartingFarmOrigin.Y + y].IsOwned = true;
			}
		}
	}

	// Inside the array. The cursor hides itself when this is false.
	public bool IsInsideBounds(Vector2I pos)
	{
		return pos.X is >= 0 and < GridSize && pos.Y is >= 0 and < GridSize;
	}

	// Part of the field. Outside it the cursor still draws, just differently.
	public bool IsOwned(Vector2I pos)
	{
		return IsInsideBounds(pos) && _tiles[pos.X, pos.Y].IsOwned;
	}

	// Ownership is required, but the tile's own state still has a say: a fence
	// inside your own field blocks you.
	public bool IsWalkable(Vector2I pos)
	{
		return IsOwned(pos) && _tiles[pos.X, pos.Y].IsWalkable;
	}

	// Returns unowned tiles on purpose. Standing at the edge of the field and
	// facing empty land is a valid state, and that is how land gets bought
	// later. Only out-of-array gives null.
	public Tile GetTile(Vector2I pos)
	{
		return IsInsideBounds(pos) ? _tiles[pos.X, pos.Y] : null;
	}
}
