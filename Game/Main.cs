using Godot;

public partial class Main : Node
{
	[Export]
	public TileMapLayer GroundLayer;
	[Export]
	public TileMapLayer ObjectLayer;
	[Export]
	public AnimatedSprite2D PlayerSprite;
	[Export]
	public Sprite2D Cursor;

	private PlayerState _player;
	private bool _isMoving;

	// Urutannya mengikuti enum Direction: Up, Down, Left, Right.
	static readonly StringName[] IdleAnimations =
		{ "idle_up", "idle_down", "idle_left", "idle_right" };
	static readonly StringName[] WalkAnimations =
		{ "walk_up", "walk_down", "walk_left", "walk_right" };
	
	Vector2 GridToWorld(Vector2I gridPos)
	{
		var gridPosTile = gridPos * GameConfig.TileSize;
		return new Vector2(gridPosTile.X + GameConfig.HalfTileSize, gridPosTile.Y + GameConfig.HalfTileSize);
	}

	Vector2I WorldToGrid(Vector2 worldPos)
	{
		return new Vector2I(Mathf.FloorToInt(worldPos.X / GameConfig.TileSize), Mathf.FloorToInt(worldPos.Y / GameConfig.TileSize));
	}

	public override void _Ready()
	{
		FarmGrid grid = new FarmGrid();

		// Smoke test: satu pagar tepat di atas pusat ladang, supaya object
		// layer punya sesuatu untuk digambar.
		grid.GetTile(grid.StartingFarmCenter + Vector2I.Up).State = TileState.Fence;

		_player = new PlayerState(grid, grid.StartingFarmCenter.X, grid.StartingFarmCenter.Y);

		RenderGrid(grid);
		RenderPlayer(_player);
		UpdateAnimation();
		UpdateCursor();
	}

	// Satu-satunya tempat offset visual dipakai, supaya render awal dan tujuan
	// tween tidak bisa berbeda rumus.
	Vector2 SpriteAnchor(Vector2I gridPos)
	{
		return GridToWorld(gridPos) - new Vector2(0, GameConfig.PlayerVisualOffsetY);
	}

	void RenderPlayer(PlayerState player)
	{
		PlayerSprite.Position = SpriteAnchor(player.Position);
	}

	public override void _Process(double delta)
	{
		// Sengaja di atas gerbang _isMoving. Langkah yang ditolak di tepi ladang
		// tetap memutar Facing, dan sprite harus ikut berputar: arah hadap
		// adalah satu-satunya petunjuk tile mana yang sedang dituju pemain.
		UpdateAnimation();
		UpdateCursor();

		if (_isMoving) return;

		var held = HeldDirection();
		if (held.HasValue) Step(held.Value);
	}

	// Satu arah saja per langkah; diagonal bukan gerakan yang sah di grid ini.
	Direction? HeldDirection()
	{
		if (Input.IsActionPressed("move_up")) return Direction.Up;
		if (Input.IsActionPressed("move_down")) return Direction.Down;
		if (Input.IsActionPressed("move_left")) return Direction.Left;
		if (Input.IsActionPressed("move_right")) return Direction.Right;
		return null;
	}

	// Satu arah aliran: state memilih animasi. Tidak ada yang bertanya balik
	// frame mana yang sedang tampil.
	void UpdateAnimation()
	{
		var next = (_isMoving ? WalkAnimations : IdleAnimations)[(int)_player.Facing];
		if (PlayerSprite.Animation != next) PlayerSprite.Play(next);
	}

	// Tanpa offset visual player: cursor 16x16 dan GridToWorld sudah memberi
	// titik tengah tile, jadi keduanya berimpit persis.
	void UpdateCursor()
	{
		// null hanya berarti satu hal: di luar array. Tile yang belum dimiliki
		// tetap kembali sebagai tile biasa.
		var tile = _player.GetFacingTile();
		Cursor.Visible = tile != null;
		if (tile == null) return;

		Cursor.Position = GridToWorld(_player.FacingPosition);
		Cursor.Modulate = tile.IsOwned
			? GameConfig.CursorOwnedTint
			: GameConfig.CursorUnownedTint;
	}

	void Step(Direction direction)
	{
		// TryMove sudah memutar Facing walau langkah ditolak. Itu aturan
		// simulasi; di sini cukup ikut, jangan diulang atau dibatalkan.
		if (!_player.TryMove(direction)) return;

		_isMoving = true;
		var tween = CreateTween();
		tween.TweenProperty(PlayerSprite, "position", SpriteAnchor(_player.Position),
			GameConfig.StepDuration);
		tween.Finished += OnStepFinished;
	}

	void OnStepFinished()
	{
		_isMoving = false;

		// Sambung di sini, jangan serahkan ke _Process frame berikutnya. Jeda
		// satu frame itu yang terasa sebagai patahan di setiap tile saat tombol
		// ditahan untuk jalan lurus.
		var held = HeldDirection();
		if (held.HasValue) Step(held.Value);
	}


	void RenderGrid(FarmGrid grid)
	{
		GroundLayer.Clear();
		ObjectLayer.Clear();

		for (int x = 0; x < grid.GridSize; x++)
		{
			for (int y = 0; y < grid.GridSize; y++)
			{
				var cell = new Vector2I(x, y);
				var tile = grid.GetTile(cell);

				var groundTile = tile.IsOwned ? GameConfig.OwnedGrassTile : GameConfig.UnOwnedGrassTile;
				GroundLayer.SetCell(cell, GameConfig.GrassSheetId, groundTile);

				if (tile.State == TileState.Fence)
				{
					ObjectLayer.SetCell(cell, GameConfig.FenceSheetId, GameConfig.FenceTile);
				}
			}
		}
	}
}
