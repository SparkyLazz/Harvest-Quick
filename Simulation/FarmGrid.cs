using Godot;

public class FarmGrid
{
	// Side of the field when the caller does not ask for a specific size.
	public const int DefaultGridSize = 24;

	// Side of the square the player already owns on a fresh save.
	public const int StartingFarmSize = 6;

	// Full array size. Fixed for the lifetime of this grid, the field never
	// reallocates, but a different run may build a different size.
	public int GridSize { get; }

	// Kept in the center so expansion is possible in all four directions.
	public Vector2I StartingFarmOrigin { get; }

	// Handy for player spawn and camera framing.
	public Vector2I StartingFarmCenter { get; }

	private readonly Tile[,] _tiles;

	public FarmGrid(int gridSize = DefaultGridSize)
	{
		GridSize = gridSize;
		StartingFarmOrigin = new Vector2I(
			(GridSize - StartingFarmSize) / 2, (GridSize - StartingFarmSize) / 2);
		StartingFarmCenter =
			StartingFarmOrigin + new Vector2I(StartingFarmSize / 2, StartingFarmSize / 2);

		_tiles = new Tile[GridSize, GridSize];

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
		return pos.X >= 0 && pos.X < GridSize && pos.Y >= 0 && pos.Y < GridSize;
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
