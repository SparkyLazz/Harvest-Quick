using System;

public enum Direction { Up, Down, Left, Right }
public static class DirectionExtensions
{
    public static (int dx, int dy) ToOffset(this Direction dir)
    {
        return dir switch
        {
            Direction.Up => (0, -1),
            Direction.Down => (0, 1),
            Direction.Left => (-1, 0),
            Direction.Right => (1, 0),

            _ => throw new ArgumentOutOfRangeException(nameof(dir))
        };
    }
}