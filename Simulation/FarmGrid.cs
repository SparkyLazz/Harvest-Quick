public class FarmGrid
{
	private int Width { get; }
	private int Height { get; }
	private readonly Tile[,] _tiles;

	public FarmGrid(int width, int height)
	{
		Width = width;
		Height = height;
		_tiles = new Tile[Width, Height];
		for (int x = 0; x < width; x++)
		{
			for (int y = 0; y < height; y++)
			{
				_tiles[x, y] = new Tile
				{
					State = TileState.Grass
				};
			}
		}
	}

	public bool CanMoveTo(int x, int y)
	{
		return IsInBounds(x, y) && _tiles[x, y].IsWalkable;
	}

	public Tile GetTile(int x, int y)
	{
		return !IsInBounds(x, y) ? null : _tiles[x, y];
	}
	
	//List of Eligible Tile
	private bool IsInBounds(int x, int y)
	{
		return x < Width && x >= 0 && y < Height && y >= 0;
	}
}
