using System.Collections.Generic;

// What the player is carrying. Held by RunState and wiped with it, so a new run
// starts with empty hands as a consequence of building a new RunState rather
// than as a Clear() somebody has to remember.
public class Inventory
{
	private readonly Dictionary<CropType, int> _crops = new Dictionary<CropType, int>();

	public void Add(CropType type, int count = 1)
	{
		_crops.TryGetValue(type, out var have);
		_crops[type] = have + count;
	}

	// Zero for anything never carried, so callers never have to branch on the
	// difference between "none" and "no entry".
	public int CountOf(CropType type)
	{
		return _crops.TryGetValue(type, out var count) ? count : 0;
	}

	public IReadOnlyDictionary<CropType, int> Crops => _crops;

	// Selling is the only thing that takes crops back out, and it always takes
	// all of them, so this is the only removal the bag offers. Handing the
	// dictionary out mutable would allow half a sale, which is a state nothing
	// should be able to write down.
	public void Clear()
	{
		_crops.Clear();
	}

	// What the bag would fetch if it were all sold today. Not money: selling is
	// its own action and has not been written yet.
	public int TotalValue
	{
		get
		{
			var total = 0;
			foreach (var entry in _crops) total += entry.Key.SellPrice * entry.Value;
			return total;
		}
	}
}
