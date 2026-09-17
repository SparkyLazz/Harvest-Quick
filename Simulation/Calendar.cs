// Pure time. It knows nothing about the grid, the player or money, so nothing
// that happens on the farm has any way of making the date wrong.
public class Calendar
{
	// Four weeks. Divisible by seven, so weekdays stay stable if they ever
	// matter, and if a month later becomes a season then this is the number
	// that decides how long a season lasts. Expect it to move during tuning:
	// that is why it is one constant in one place.
	public const int DaysPerMonth = 28;

	// The only stored state. Day and month are derived from it rather than
	// kept beside it, so "day 35 of month 2" has no way to exist. Same reason
	// Tile has one ground field instead of one field per combination.
	public int DaysElapsed { get; private set; }

	// Both one-based: a run opens on day 1 of month 1.
	public int Day => DaysElapsed % DaysPerMonth + 1;
	public int Month => DaysElapsed / DaysPerMonth + 1;

	// The run's own day count, one-based and never wrapping. Day and Month are
	// what the player reads; this is what the bill schedule is written against,
	// because a schedule keyed on Day would come due a second time in any run
	// that outlasts a month — day 29 reads as day 1 again.
	public int RunDay => DaysElapsed + 1;

	// Month keeps counting instead of wrapping, so no information is lost and
	// no year field is invented before something needs one. When seasons
	// arrive, season is (Month - 1) % 4 and year is (Month - 1) / 4, both
	// derived from what is already stored here.
	public void AdvanceDay()
	{
		DaysElapsed++;
	}
}
