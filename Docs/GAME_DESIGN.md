# HarvestQuick — Game Design

The agreed design for the game: story, rules, numbers, and the build plan with
what is done. Decisions here were made with the developer (Rui); anything
marked **open** has not been decided yet, so ask before assuming.

Last updated: 2026-11-05.

---

## 1. Pitch

A Harvest Moon / Stardew Valley–style farming game with a small city. It is
**half story game**: the farming is how you survive, and the story is why.

**The story.** The player's mother gambles. She keeps taking on debt **in the
player's name**. The player (male — "his name") can't run from it: he has to
farm, keep up with the payments, and save up for a **lawyer** who can stop his
mother from ever using his name again.

- **Mom is never seen.** She exists only through **letters** in the mailbox,
  and each letter brings more debt.
- **No romance.** The friendly neighbour is support, not a love interest.

## 2. Core loop

1. Farm during the day (till, plant, water, harvest), raise animals, fish.
2. Sell produce for money.
3. Pay the **debt collector** his weekly minimum.
4. Read Mom's letters — usually more debt.
5. Do story quests in town to gather **evidence** for the lawyer.
6. Save up the lawyer's fee. With fee + evidence → good ending.

## 3. Time and calendar (built)

Stardew's calendar:

| Unit | Value |
|---|---|
| Season | 28 days |
| Year | Spring, Summer, Fall, Winter = 112 days = 16 weeks |
| Week | Mon–Sun; day 1 is **Mon 1 Spring, Year 1** |
| Story length | planned around **2 years (32 weeks)** |

- A day runs **6:00 am → 2:00 am**. The clock moves in 10-minute steps, every
  7 real seconds, so a full day is about 14 real minutes.
- The clock stops while a menu/window is open and during screen fades.
- **Sleep** in bed: next day at 6:00, full stamina.
- **Pass out** at 2:00 am: wake next to the bed next morning with **half**
  stamina. (Later this could also cost money — the collector "helps himself".)
- **Crops grow overnight**: each night the soil was watered counts as one day
  grown; all soil is dry again in the morning, so you water every day.
- **Winter has no crops** (planned; crop seasons are not enforced yet — see
  §9). Winter income comes from animals and fishing.

## 4. The debt (designed, not built yet)

Starting debt **1000**. It must grow slowly, and be mathematically fair.
Numbers tuned with `Tools/econ_sim.py` (run it to re-check).

| Rule | Formula | Examples |
|---|---|---|
| Starting debt | 1000 | — |
| Weekly minimum payment | the higher of **40 + 8 × week** or **4% of the debt** | wk 1: 48, wk 16: 168, wk 32: 296 |
| Interest | **1% per week** on the unpaid balance | 1000 → +10 a week |
| Mom's letters | every **2 weeks**, **(80 + 30 × week) ± 25%** | wk 2: ~140, wk 16: ~560 |
| Missed payment | **+10%** of the missed minimum added as a late fee, and **1 strike** | 3 strikes → bad ending |
| Lawyer | **10,000** + evidence; evidence can't be complete before **week 12** | voids Mom's debt, stops her letters |

Most of the growth comes from Mom's letters, not interest — the player can see
who is to blame.

**Simulated results** (300 runs per skill level, assuming 45% of income is
reinvested in seeds/tools/animals):

| Player | Hires the lawyer | Median week |
|---|---|---|
| Expert | 100% | 12 (as soon as evidence allows) |
| Good | 100% | 17 (start of year 2) |
| Casual | 100% | 23 (summer of year 2) |
| Struggling | 0% | still in debt at week 32 |

**Why it's fair:**
- **Winter is the real test**, as in Stardew: winter income ≈ 60–80 a week
  against a ≈150 minimum. A player who enters winter with nothing misses three
  payments and loses; one who saved ~600 is fine. Warn the player in late fall
  (e.g. a letter from the friendly neighbour).
- The player has a real choice: pay extra now to slow interest, or save for
  the lawyer, who wipes out all of Mom's debt in one go.
- The income side of the simulation is a guess (6–10 profit per tile per day,
  like Stardew's parsnip/cauliflower). **Rerun the simulation once real crop
  prices exist.**

## 5. Endings

- **Bad ending**: 3 missed payments → you lose the farm.
- **Good ending**: lawyer hired (fee + evidence) → Mom can't use your name.
- **Open:** what happens if you survive 2 years without the lawyer? Suggested:
  a neutral ending — "still trapped, but survived".

## 6. Characters

| Who | Role |
|---|---|
| Player | The protagonist (male). The debt is in his name. |
| Mom | **Never seen.** Letters only; gambles; adds debt. |
| Debt collector | Comes every week for the minimum. The pressure; sort of the villain. |
| Lawyer | The goal. Gives the main quest: fee + evidence. |
| Seed seller | The shop for seeds. |
| Animal & fish trader | Sells chickens and cows, buys fish. |
| Friendly neighbour | Emotional support, hints, warnings. **No romance.** |

## 7. Story delivery

- **Day to day:** mailbox letters and talking to NPCs.
- **Big moments:** short scripted scenes — the first collector visit, meeting
  the lawyer, the endings.
- **Evidence** comes through quests: Mom's letters and IOUs, plus what
  townspeople tell you.

## 8. Income sources

- **Crops** — built (growing). Selling not built yet.
- **Animals** (chickens, cows: eggs, milk) — planned.
- **Fishing** — planned.
- Not planned for now (assets exist): mining, jam/preserves, bees.

## 9. Build plan and status

| # | Step | Status |
|---|---|---|
| — | Farming: hoe, plant, water, harvest; trees and axe; wood; tree seeds | **Done** |
| — | Inventory (45 slots, 9-slot hotbar), profile screen (inventory/crafting/settings tabs), crafting (produce → seeds) | **Done** |
| — | Player house: doors, bed, wardrobes and chests with storage | **Done** |
| 1 | **Day clock and sleep**: calendar, time, overnight growth, sleep, passing out, clock UI | **Done** |
| 2 | **Coins, shipping bin / market, seed shop** — first income | **Next** |
| 3 | **Weekly debt collector + bad ending** — after this the game is playable end to end (small) | Planned |
| 4 | **Mailbox and Mom's letters** — new debt + story | Planned |
| 5 | **Dialogue system + the city scene** (dialogue boxes, portrait frames from the UI pack) | Planned |
| 6 | **Lawyer evidence quests + good ending** | Planned |
| 7 | **Animals** | Planned |
| 8 | **Fishing** | Planned |

**Open / not done yet:**
- Crops are not tied to seasons (you can plant anything in winter). Do it
  with the seed shop (step 2).
- No evening darkening of the screen.
- No rain / weather (the clock already has the weather icons ready).
- No saving to disk: everything lives in memory for one run (see
  `Docs/TECH_NOTES.md`).
- Stamina refills by itself over a few seconds of rest. Stardew only refills
  it by sleeping or eating — **open** whether to change that.
- Neutral ending (§5).

## 10. The clock (built) — what the player sees

Top-left corner of the screen, built from the UI pack's weather frame:

- **Window picture** shows the part of the day: dawn 6:00 (orange sunrise),
  day 8:00 (green sun), dusk 17:00 (orange sunset), night 20:00 (blue moon),
  late 24:00 (moon with stars). Changes play a cute "set and rise": the old
  picture sinks, the sky colour cross-fades, the new one bounces up.
- **Dial and arrow**: the arrow is the time — up at the sun at 6:00, level at
  18:00, down at the moon by 2:00 (5 drawn steps, each with a springy pop).
  There is **no written time** on purpose.
- **Thermometer**: season warmth (summer hottest, then spring, fall, winter),
  a notch warmer in the afternoon and cooler at night.
- **Date plate** (the developer picked design 5 of 11): the season on top
  ("SUMMER", softer brown) over the date ("MON 15", dark brown), both
  centred in the pack's small 5px font.

## 11. Asset packs

All by Cup Nooble (Sprout Lands). Originals are in the developer's Downloads:

| Pack | Path | Highlights |
|---|---|---|
| Sprites — premium | `C:\Users\Rui\Downloads\Sprout Lands - Sprites - premium pack` | Chickens/cows in 5 colours + babies, eggs, coops, barn, fruit trees (apple/orange/peach/pear), work station, well, boats, signs, mailbox animation, animated doors and fence gates, tilesets |
| UI — premium | `C:\Users\Rui\Downloads\Sprout Lands - UI Pack - Premium pack` | Coins, hearts, stars, stamina circle, thermometer and weather icons, dialogue boxes, portrait frames, speech bubbles, settings menu, sliders, buttons, cursors, emotes, fonts (TTF in `fonts/Font files TTF`) |
| Sorry pack (early access) | `C:\Users\Rui\Downloads\Sprout Sorry pack` | **Fishing** (casting animations, rods, ~40 fish, junk, treasure), crops v2 + jams/juices/pickles, bread/honey, **bees**, **mines** (pickaxe, ores, gems, carts, bats, slimes), **village houses**, birch/cherry/pine biomes, frogs, new furniture and chests, **winter** (snow, ice, campfire, presents) |

Imported into `Assets/` so far: tiles, crops, trees, house, furniture, chest,
items, the player character, UI sheets, fonts, the clock atlas and the big
weather icons. The Sorry pack is early access — its art may change.
