using Godot;

public partial class Main : Node
{
	Vector2 GridToWorld(Vector2I gridPos)
	{
		var gridPosTile = gridPos * GameConfig.TileSize;
		return new Vector2(gridPosTile.X + GameConfig.HalfTileSize, gridPosTile.Y + GameConfig.HalfTileSize);
	}

	Vector2 WorldToGrid(Vector2 worldPos)
	{
		return worldPos * GameConfig.TileSize;
	}
}
