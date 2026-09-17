using System;
using System.Collections.Generic;

// One payment: the day of the run it falls due, and what it costs.
//
// A record struct because it is two numbers that are meaningless apart and
// never change once written. Compared by value on purpose, unlike CropType:
// two payments of the same size on the same day really are the same payment,
// and the validation below relies on being able to say so.
public readonly record struct Payment(int Day, int Amount);

// What the player owes and when. Holds a schedule and answers two questions
// about it: what falls due today, and what falls due next.
//
// The second question is not a convenience. A schedule the player cannot see
// ahead turns "how much cash do I hold back" from a decision into a guess, and
// the harness says that decision is the most valuable one in the run: through
// the middle of a run the player with the better farm is the one holding less
// money, because theirs is in the ground. Charged by surprise, that player is
// punished for playing well. Charged on a visible schedule, they are being
// asked a question.
public class Debt
{
	// Data, not logic, and the only place the curve lives. Every number here
	// came off the harness rather than out of taste.
	//
	// Total is 5,390, which is well under what a good run earns unburdened —
	// about 7,900 — and it has to be. Paying a bill does not cost its face
	// value, it costs the face value plus everything that money would have
	// grown into. A schedule totalling 6,000 was tried first and killed every
	// strategy tested, the good ones included.
	//
	// The shape follows the cash curve, and that curve says two things. The
	// better farmer is the one holding less money through the middle of a run,
	// because theirs is in the ground. And a coin early is worth several late,
	// because carrot compounds at about 1.5x a day until the field is full.
	//
	//   h6      one carrot seed. Small enough to cost nothing, visible enough
	//           to teach that bills exist before one matters. Raising it to 60,
	//           still a rounding error against the total, cut the number of
	//           surviving strategies from fifteen to seven.
	//   h10     the first real earnings have landed.
	//   h14-21  the tight middle, where the better farmer is the poorer one.
	//           The most sensitive numbers in the file: a hundred added here
	//           costs more survivors than a thousand added at the end.
	//   h24-30  two thirds of the total. Both players are liquid by now, and
	//           the good one has pulled away while the bad one has not.
	//
	// Against this curve a player who plants the cheapest seed everywhere fails
	// the final payment on day 30, and fifteen of twenty tested good policies
	// finish with roughly 2,300 to spare.
	public static readonly IReadOnlyList<Payment> DefaultSchedule = new[]
	{
		//           hari  jumlah
		new Payment( 6,   10),
		new Payment(10,   50),
		new Payment(14,  150),
		new Payment(18,  320),
		new Payment(21,  580),
		new Payment(24,  930),
		new Payment(27, 1390),
		new Payment(30, 1960),
	};

	public Debt(IReadOnlyList<Payment> schedule = null)
	{
		Schedule = schedule ?? DefaultSchedule;

		// Checked once, at startup, rather than discovered as a bill that never
		// arrives or one that arrives twice. A schedule is edited by hand every
		// time it is tuned, and these are the three ways a hand slips.
		var previousDay = 0;
		foreach (var payment in Schedule)
		{
			if (payment.Day <= previousDay)
			{
				throw new ArgumentException(
					$"schedule must run forwards and charge a day at most once; day {payment.Day} follows day {previousDay}.",
					nameof(schedule));
			}

			if (payment.Amount <= 0)
			{
				throw new ArgumentException(
					$"day {payment.Day} charges {payment.Amount}; a payment of nothing is not a payment.",
					nameof(schedule));
			}

			previousDay = payment.Day;
			Total += payment.Amount;
		}
	}

	// Kept in order, so the player can be shown the whole curve on day 1 and
	// the two lookups below can stop at the first day past the one asked for.
	public IReadOnlyList<Payment> Schedule { get; }

	public int Total { get; }

	// Zero on every day that is not a due date, which is most of them. Callers
	// never have to ask whether there is a bill before asking how big it is.
	public int AmountDueOn(int runDay)
	{
		foreach (var payment in Schedule)
		{
			if (payment.Day == runDay) return payment.Amount;
			if (payment.Day > runDay) break;
		}

		return 0;
	}

	// The next payment due on or after this day, or null once the last one has
	// been charged. Null is what the readout shows as an empty slot; it is not
	// an error, it is the end of the schedule.
	public Payment? NextFrom(int runDay)
	{
		foreach (var payment in Schedule)
		{
			if (payment.Day >= runDay) return payment;
		}

		return null;
	}
}
