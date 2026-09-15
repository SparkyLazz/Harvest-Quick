using Godot;

public class PlayerState(FarmGrid grid, int startX, int startY)
{
	public int X { get; private set; } = startX;
	public int Y { get; private set; } = startY;
	public Direction Facing { get; private set; } = Direction.Down;
	private readonly FarmGrid _grid = grid;

	//Turning is deliberately independent of moving. At the edge of the field
	//every step outward is refused, and facing unowned land is how it gets
	//bought later, so a refused step must still turn the player.
	public void Face(Direction direction)
	{
		Facing = direction;
	}

	//Possible User can spawn in Non-Eligible Grid (-5, 999)
	public bool TryMove(Direction direction)
	{
		Face(direction);
		var (dx, dy) = direction.ToOffset();
		var target = new Vector2I(X + dx, Y + dy);
		if (!_grid.IsWalkable(target)) return false;
		X = target.X;
		Y = target.Y;
		return true;
	}

	public Vector2I FacingPosition
	{
		get
		{
			var (dx, dy) = Facing.ToOffset();
			return new Vector2I(X + dx, Y + dy);
		}
	}

	//Unowned tiles come back as ordinary tiles. null means outside the array,
	//which is the cursor's cue to hide itself.
	public Tile GetFacingTile()
	{
		return _grid.GetTile(FacingPosition);
	}
}
