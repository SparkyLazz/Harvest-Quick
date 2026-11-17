"""Debt economy simulator: the numbers behind Docs/GAME_DESIGN.md's debt rules.

Plays the debt rules against an income curve for players of four skill
levels, 300 runs each, and reports how often each one loses and when each one
can hire the lawyer. The farm's side now comes from the game's real crop
prices (CROPS below, a copy of Scripts/Crops.gd); animals and fishing are
still a guess until they are built. Retune the rules if the results drift.

Calendar is Stardew's: 4 seasons x 4 weeks = 16 weeks a year; a run is 2 years.

    python Tools/econ_sim.py          # the summary table
    python Tools/econ_sim.py 0.65     # one casual run, week by week

Agreed targets: casual ~week 23 (summer of year 2), good ~17, expert ~12 (the
evidence quests cannot finish earlier); a struggling player survives but never
saves enough; a player who goes into winter broke misses payments and loses.
"""
import random
import statistics
import sys

WEEKS_PER_SEASON = 4
SEASONS = ["Spring", "Summer", "Fall", "Winter"]
RUN_WEEKS = 32

# --- debt rules ---
START_DEBT = 1000
INTEREST = 0.01                 # weekly, on the unpaid balance
MIN_BASE, MIN_STEP = 40, 8      # minimum payment = base + step*week ...
MIN_PCT = 0.04                  # ... or 4% of the debt, whichever is higher
LATE_FEE = 0.10                 # of the missed minimum, added to the debt
STRIKES_TO_LOSE = 3
MOM_EVERY = 2                   # Mom's letters: one every 2 weeks ...
MOM_BASE, MOM_STEP, MOM_SPREAD = 80, 30, 0.25   # ... of (80 + 30*week) +/- 25%
LAWYER_FEE = 10000
EVIDENCE_WEEK = 12              # story: the earliest week all evidence can be found

# --- income model ---
REINVEST = 0.45                 # share of income spent on seeds, tools, animals
# The crops as Scripts/Crops.gd prices them: (days to ripen, price, seasons).
# A copy -- keep the two in step. Tools/test_economy.gd checks the game's side
# against the per-season figures this produces (Spring ~6, Summer ~9, Fall ~10).
CROPS = {
    "corn": (10, 95, ("Summer", "Fall")),
    "carrot": (4, 24, ("Spring",)),
    "cauliflower": (10, 70, ("Spring",)),
    "tomato": (8, 72, ("Summer",)),
    "eggplant": (5, 50, ("Fall",)),
    "bluebell": (5, 32, ("Spring",)),
    "lettuce": (5, 30, ("Spring",)),
    "wheat": (4, 32, ("Summer", "Fall")),
    "pumpkin": (12, 130, ("Fall",)),
    "turnip": (4, 22, ("Spring",)),
    "rose": (7, 63, ("Summer",)),
    "beet": (6, 60, ("Fall",)),
    "starfruit": (13, 140, ("Summer",)),
    "cucumber": (8, 68, ("Summer",)),
}


def tile_profit(season: str) -> float:
    """What a tile kept planted takes in a day in `season`: the average over that
    season's crops of price / days. Seeds are paid for out of REINVEST."""
    rates = [price / days for days, price, seasons in CROPS.values() if season in seasons]
    return sum(rates) / len(rates) if rates else 0.0


TILE_PROFIT = {s: tile_profit(s) for s in ("Spring", "Summer", "Fall", "Winter")}
START_TILES, TILE_GROWTH, TILE_CAP = 12, 4, 80                     # tiles kept watered
SIDE = {"Spring": 20, "Summer": 40, "Fall": 50, "Winter": 160}      # animals + fishing a week


def season(week: int) -> str:
    return SEASONS[((week - 1) // WEEKS_PER_SEASON) % 4]


def run(skill: float, seed: int, verbose: bool = False) -> tuple[str, int]:
    """One playthrough. Returns ("LOSE" | "LAWYER" | "SURVIVED", week)."""
    rng = random.Random(seed)
    debt, cash, strikes = START_DEBT, 200.0, 0
    tiles = START_TILES
    for w in range(1, RUN_WEEKS + 1):
        s = season(w)
        income = tiles * TILE_PROFIT[s] * 7 * skill + SIDE[s] * skill * min(1, w / 8)
        income *= rng.uniform(0.85, 1.15)
        cash += income * (1 - REINVEST)
        if s != "Winter":
            tiles = min(TILE_CAP, tiles + TILE_GROWTH * skill)
        if w % MOM_EVERY == 0:
            debt += (MOM_BASE + MOM_STEP * w) * rng.uniform(1 - MOM_SPREAD, 1 + MOM_SPREAD)
        minimum = min(max(MIN_BASE + MIN_STEP * w, MIN_PCT * debt), debt)
        if cash >= minimum:
            cash -= minimum
            debt -= minimum
        else:
            debt += minimum * LATE_FEE
            strikes += 1
        debt *= 1 + INTEREST
        if verbose:
            print(f"wk{w:2} {s:6} income {income:6.0f} min {minimum:5.0f} "
                  f"debt {debt:6.0f} cash {cash:6.0f} strikes {strikes}")
        if strikes >= STRIKES_TO_LOSE:
            return ("LOSE", w)
        # Keep enough back for the next couple of payments (winter!).
        reserve = minimum * 2.5
        if cash - reserve >= LAWYER_FEE and w >= EVIDENCE_WEEK:
            return ("LAWYER", w)
    return ("SURVIVED", RUN_WEEKS)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        run(float(sys.argv[1]), 1, verbose=True)
        sys.exit()
    for name, skill in [("struggling", 0.45), ("casual", 0.65), ("good", 0.85), ("expert", 1.0)]:
        results = [run(skill, s) for s in range(300)]
        lose = sum(r[0] == "LOSE" for r in results)
        hired = [r[1] for r in results if r[0] == "LAWYER"]
        median = statistics.median(hired) if hired else "-"
        print(f"{name:10} lose {lose / 3:5.1f}%  lawyer {len(hired) / 3:5.1f}%  median lawyer week {median}")
