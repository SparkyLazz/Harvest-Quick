using Godot;

public static class GameConfig
{
	public const int TileSize = 16;
	public const float HalfTileSize = (float)TileSize / 2;
	public const int PlayerSpriteHeight = 32;
	public const int PlayerSpriteBottomPadding = 8;
	public const float PlayerVisualOffsetY =
		(float)(PlayerSpriteHeight - TileSize) / 2 - PlayerSpriteBottomPadding;

	// Lama animasi satu langkah antar-tile.
	public const float StepDuration = 0.12f;

	public const int GrassSheetId = 0;
	public const int FenceSheetId = 3;
	
	public static readonly Vector2I OwnedGrassTile = new Vector2I(1, 4);
	public static readonly Vector2I UnOwnedGrassTile= new Vector2I(1, 9);
	public static readonly Vector2I FenceTile = new Vector2I(1, 3);

	// Cursor memakai satu tekstur putih; warnanya yang membedakan kondisi.
	public static readonly Color CursorOwnedTint = new Color(1f, 1f, 1f);
	public static readonly Color CursorUnownedTint = new Color(1f, 0.42f, 0.35f);
}
