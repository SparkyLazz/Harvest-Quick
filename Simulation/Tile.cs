public enum TileState
{
	Grass,
	Tilled,
	Planted,
	Fence,
}

public class Tile
{
	
	public TileState State { get; set; }
	//Automatically set IsWalkable true if the state meet those who is an eligible
	public bool IsWalkable => State is TileState.Grass or TileState.Tilled or TileState.Planted;
}
	
