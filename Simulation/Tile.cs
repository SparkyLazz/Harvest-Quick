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
	//Owned means the tile belongs to the field. Unowned tiles are still real
	//tiles, they just cannot be entered or worked until they are bought.
	public bool IsOwned { get; set; }
	//Automatically set IsWalkable true if the state meet those who is an eligible
	public bool IsWalkable => State is TileState.Grass or TileState.Tilled or TileState.Planted;
}
