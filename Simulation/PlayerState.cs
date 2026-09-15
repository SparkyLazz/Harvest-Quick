public class PlayerState(FarmGrid grid, int startX, int startY)
{
	public int X { get; private set; } = startX;
	public int Y { get; private set; } = startY;
	private readonly FarmGrid _grid = grid;
	//Possible User can spawn in Non-Eligible Grid (-5, 999)
	public bool TryMove(Direction direction)
	{
		var (dx, dy) = direction.ToOffset();
		var targetX = X + dx;
		var targetY = Y + dy;
		if (!_grid.CanMoveTo(targetX, targetY)) return false;
		X =  targetX;
		Y =  targetY;
		return true;
	}
}
