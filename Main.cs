using Godot;

public partial class Main : Node
{
	public override void _Ready()
	{
		var grid = new FarmGrid(5, 5);
		var player = new PlayerState(grid, 0, 0);
		grid.GetTile(2, 0).State = TileState.Fence;
		GD.Print($"Right: {player.TryMove(Direction.Right)} -> ({player.X}, {player.Y})");
		GD.Print($"Right: {player.TryMove(Direction.Right)} -> ({player.X}, {player.Y})");
		GD.Print($"Right: {player.TryMove(Direction.Right)} -> ({player.X}, {player.Y})");

	}
}
