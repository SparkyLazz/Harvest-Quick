# HarvestQuick — Game Design

The agreed design for the game: story, rules, numbers, and the build plan with
what is done. Decisions here were made with the developer (Rui); anything
marked **open** has not been decided yet, so ask before assuming.

Last updated: 2026-11-06.

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

## 2a. The world: zones, not one big map (decided 2026-11-18)

The world is built the way Harvest Moon and Stardew build theirs: **a set of
separate maps joined by doors and paths**, each its own scene, with a short
fade between them. It is **not an open world** — there is no single continuous
landscape streamed in as you walk, and you cannot see the town from the farm.

This was settled after it was asked directly. What the player gets is
*open-ended*, not open-world: free to spend each day however they like, no
forced path through the story. That is the freedom the game wants, and zones
give it without the cost of one huge map.

It is also what the code already does, so nothing had to change:
`SceneTransition.go_to()` fades to black, swaps the scene and stands the
player on a named `Marker2D`; `Door.gd` carries the target scene and spawn
point. Adding a zone is adding a scene and a door.

| Zone | Scene | Status |
|---|---|---|
| The farm | `Scenes/Dev.tscn` | **Built.** The only outdoor map, so the only one that carries the rain layer (§9a). |
| Player house | `Scenes/PlayerHouse.tscn` | **Built.** Bed, wardrobes, chests. |
| The city | — | Step 5. Village-house art is in the Sorry pack, not imported yet. The seed-shop sign on the farm stands in for the seller until then (§13). |
| Interiors in the city (shop, lawyer's office, neighbour's house) | — | Step 5 and after, one scene each, as Stardew does. |

**Open:** whether the city is one zone or several; whether there is anything
between the farm and the city (a path screen) or the door leads straight in.

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
- **Sleep** in bed: next day at 6:00, full stamina — and the game **saves**
  (§15).
- **Pass out** at 2:00 am: wake next to the bed next morning with **half**
  stamina. (Later this could also cost money — the collector "helps himself".)
- **Stamina refills by itself** after a few seconds of rest — decided
  2026-11-06, instead of Stardew's refill only by sleeping or eating. So
  stamina never caps a day's farming; the 14-minute day does, which is what
  `econ_sim.py` assumes (up to 80 watered tiles a day) and why its results in
  §4 stand. Known side effect: waking on half stamina costs almost nothing,
  since it is back to full within seconds — if passing out should hurt, the
  cost has to come from elsewhere (the collector, above).
- **Crops grow overnight**: each night the soil was watered counts as one day
  grown; all soil is dry again in the morning, so you water every day.
- **Crops keep to their seasons** (built, §13): seeds are only sold and can
  only be planted in their seasons, and the morning a new season starts,
  anything that does not grow in it dies (the soil stays tilled). **Winter
  has no crops**; winter income comes from animals and fishing.

## 4. The debt (built — see §4a for what the player does)

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

Everything in that table is built. `Debt.gd` holds the rules; its constants are
`econ_sim.py`'s, name for name, so the two cannot drift apart unnoticed. The
one difference is rounding: the game owes whole coins and rounds the balance
every week, while the simulator carries the fraction, so a long run ends a coin
or two apart.

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

No skill level loses in the simulation (0% bad endings, even struggling): the
sim's player always pays when they can, so only a player who stops paying
reaches the collector's third strike.

**Why it's fair:**
- **Winter is the real test**, as in Stardew: winter income ≈ 60–80 a week
  against a ≈150 minimum. A player who enters winter with nothing misses three
  payments and loses; one who saved ~600 is fine. Warn the player in late fall
  (e.g. a letter from the friendly neighbour).
- The player has a real choice: pay extra now to slow interest, or save for
  the lawyer, who wipes out all of Mom's debt in one go.
- The farm's side of the simulation now uses the game's real crop prices
  (§13): a tile kept planted takes in about 6.2 a day in Spring, 9.1 in Summer
  and 9.7 in Fall. Rerun on 2026-11-06 with them: the results above hold
  exactly (casual week 23, good 17, expert 12, struggling never). Animals and
  fishing are still a guess until they are built.

## 4a. The collector (built) — what the player does

- **He comes on Sundays**, the last day of each week, and stands at the farm
  below the house. He waits all day and is gone by Monday. A Sunday spent
  indoors is how a payment gets missed.
- **Walking up to him and using him opens the bill**: the week, what is OWED,
  what THIS WEEK wants, the strikes so far, and three buttons — pay the
  minimum, pay 100 towards the debt, or pay it off whole. Buttons grey out
  when the purse cannot cover them. He does not speak: the dialogue system is
  step 5, and the bill speaks for him until then.
- **The week is settled the night it turns**, as you sleep from Sunday into
  Monday: minimum met or missed, then the late fee and the strike if missed,
  then interest on what is left. Paying *something* still counts as a miss —
  it comes off the debt, but it does not buy off the strike, which is how
  `econ_sim` plays it.
- **Paying ahead is a real choice** (§4): it slows the interest, at the cost of
  the lawyer's fee coming later.
- **Three strikes ends the game** — a full-screen ending over the black of the
  night you lost on, with the week and what you still owed, and one way out:
  a new game. A lost save stays lost: loading it brings the ending straight
  back.
- **Open:** he has no dialogue, no arrival warning (a letter, a knock, an
  emote), and no reaction to being paid or missed. All of that wants step 5.
  His sprite is the pack's *basic* character tinted cold — a stand-in, not art.

## 4b. The post (built) — Mom's letters

The mailbox stands beside the house and waves a letter whenever something is
unread; using it opens the post, the letters down the left and the one you
picked on the right. The story is told here, day to day (§7).

- **Mom writes every 2 weeks**, on the Monday that opens weeks 2, 4, 6…, for
  **(80 + 30 × week) ± 25%** — econ_sim's rule, and the biggest share of the
  debt's growth. Four letters of hers rotate; she never quite apologises and
  the money is always already gone.
- **Her money lands when the letter does, not when it is read.** The post does
  not wait for you to open it, and leaving the box shut is not a way to dodge
  her. The letter says in red what it cost, so the player can see where the
  debt came from.
- **The week is settled before she is added to it** — the collector takes
  Sunday's account on the night the week turns, then Monday's letter arrives.
  Same order as econ_sim.
- **An opening letter** is in the box on day 1: the farm is yours, so is the
  rest of it, the man comes on Sundays.
- **The neighbour writes once a year**, on the Monday that opens the last week
  of Fall, warning that nothing grows in winter and to put money by. §4 asks
  for exactly this warning; winter is where a run is won or lost.
- **Nothing is rolled at runtime.** A week's figure comes out of a mixer fed
  the week number, like the weather, so it is the same figure every time it is
  asked for. The inbox itself is saved, because which letters you have read is
  real state.
- **Open:** letters cannot be thrown away, there is no sound or notification
  when one lands, and the neighbour has nothing else to say. Mom's four bodies
  repeat once a year has gone by.

## 4c. The town and talking (built)

The town is the second outdoor zone (2a), across the water from the farm.

- **Getting there**: a rowing boat on the farm's east shore. Walk into it and
  you are in town; the boat on the town's west shore brings you back. The farm
  is an island, so there is no road -- the ferry is the crossing.
- **The town** holds three people: the **seed seller**, the **neighbour** and
  the **lawyer**. Its **layout is drawn by hand in the editor** (decided
  2026-11-19) -- a generated one was tried first and read as generated. What
  the code needs from the scene is a short list, written down in
  `Docs/TECH_NOTES.md` 5b and checked by the tests; the map itself is free.
  **Open:** the map is a blank patch of grass with the three of them stood in
  a row on it, waiting to be drawn.
- **Talking** is the same gesture as using a chest: walk up, press use. A line
  types itself out; pressing on finishes a line that is still typing, and
  turns a finished one. The pack's own click-to-continue chevron says when it
  is waiting on you. Esc walks away.
- **What people say depends on the game**, not on a tree: the neighbour has a
  different word for a clear day, a rainy one, late Fall, one strike and two;
  the seller sells the season and has nothing for you in Winter; the lawyer
  states his price (ten thousand and proof she signed as you) and says the
  proof is not ready. Choosing happens before the conversation starts, so
  there are no branches inside one.
- **The collector talks too** now, before he hands the bill over, with a line
  for a first week, a missed one, a last warning and a week already paid.
- **The seed shop has moved into the conversation**: talk to the seller and
  his stall opens when he has finished. The sign on the farm still works and
  still sells the same stock -- retiring it is a decision for when the town is
  somewhere the player has a reason to be every week.
- **Open:** nobody walks, nobody has their own art (they are the pack's basic
  character in three tints), there are no interiors in town, no choices in a
  conversation, and the lawyer cannot yet be hired -- that is step 6.

## 4d. The lawyer and the good ending (built)

The way out of the debt, and the only way to win.

- **Four pieces of evidence**, one from each of §7's sources and then one more:
  **her own letters** (three of Mom's letters arriving is the exhibit -- nobody
  has to be asked), **the neighbour's word**, **the seller's ledger**, and
  **the collector's own copy** of the signed form. He hands it over without a
  fight: by then you have been paying him for months and he has no reason to
  keep it back. It is the turn of the knife -- the man collecting the debt
  gives you the paper that undoes it.
- **They come in that order.** Each waits on the one before it, so the case is
  gathered rather than scrambled.
- **The case cannot be whole before week 12** (§4). That is not a check laid
  on top: the collector's copy *is* the last piece and he will not part with it
  before week 12, so there is no order of play that finishes early.
- **The fee is 10,000.** A whole case is not enough on its own, and the fee is
  not enough on its own.
- **Hiring him wins the game.** The debt goes **void**, not paid -- the point
  of him is that it was never your debt. Mom stops writing, because the name
  she was signing with is no longer one a court will accept. The strikes stay
  on the record and have nothing left to count towards.
- **The lawyer is also the quest log**: he says how many pieces he holds and
  names what is still wanting, because there is no screen that does.
- **Open:** no quest log of its own, no scene when the case completes, and the
  evidence cannot be looked at anywhere but in his mouth.

## 5. Endings

- **Bad ending** (built): 3 missed payments → you lose the farm (§4a).
- **Good ending** (built): lawyer hired (fee + evidence) → Mom can't use
  your name (§4d).
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

- **Day to day:** mailbox letters (built — §4b) and talking to NPCs.
- **Big moments:** short scripted scenes — the first collector visit, meeting
  the lawyer, the endings. The dialogue system they need is built (4c).
- **Evidence** comes through quests: Mom's letters, what townspeople tell
  you, and the collector's own copy of the form (built -- §4d).

## 8. Income sources

- **Crops** — built: grown on the farm, sold through the shipping bin, seeds
  bought at the seed shop (§13). Wood and tree seeds sell too, for little.
- **Animals** (chickens, cows: eggs, milk) — planned.
- **Fishing** — planned.
- Not planned for now (assets exist): mining, jam/preserves, bees.

## 9. Build plan and status

| # | Step | Status |
|---|---|---|
| — | Farming: hoe, plant, water, harvest; trees and axe; wood; tree seeds | **Done** |
| — | Inventory (45 slots, 9-slot hotbar), profile screen (inventory/crafting/settings tabs), crafting (produce → seeds) | **Done** |
| — | Player house: doors, bed, wardrobes and chests with storage | **Done** |
| — | **Save game**: one slot, saved every night, wake in bed; New Game in Settings (§15) | **Done** |
| 1 | **Day clock and sleep**: calendar, time, overnight growth, sleep, passing out, clock UI | **Done** |
| 2 | **Coins, shipping bin / market, seed shop** — first income (and crop seasons) | **Done** |
| 3 | **Weekly debt collector + bad ending** — the game is now playable end to end | **Done** |
| 4 | **Mailbox and Mom's letters** — new debt + story | **Done** |
| 5 | **Dialogue system + the city scene** (dialogue boxes, portrait frames from the UI pack) | **Done** |
| 6 | **Lawyer evidence quests + good ending** | **Done** |
| 7 | **Animals** | **Next** |
| 8 | **Fishing** | Planned |

**Open / not done yet:**
- No evening darkening of the screen.
- Neutral ending (§5).

## 9a. Weather (built)

Three skies: **clear**, **rain** and **storm**. Which one a day gets is not
stored anywhere — it is worked out from the day number, so every scene, the
clock and a save reloaded a week later all agree without anything on disk.
Ask for any day, past or future, and the answer is the same one.

- **Chance of rain** per season: Spring 28%, Summer 16%, Fall 24%, Winter 0%.
  Of the rainy days, some come down as storms instead: Spring 10%, Summer 35%,
  Fall 15% — summer's few rains are the violent ones.
- **Winter is dry.** The icon sheet has snow, but nothing in the game knows
  what snow does yet, so winter stays clear rather than pretending. **Open:**
  what snow should do when winter gets its own pass.
- **Day 1 is always clear.** The first morning on the farm should not be spent
  indoors.
- **Rain waters the farm.** Every tilled cell is wet from the morning on, and
  soil hoed while it rains comes up wet too, so a rainy day is a day off from
  the watering can — which is the whole point of it. The night that follows
  grows crops exactly as a hand-watered one would. The sky clearing does not
  dry what it already wet.
- **What the player sees**: two sheets of falling streaks (near and far), an
  overcast wash over the world, and in a storm a darker sky with lightning
  every 7–18 seconds. There is no rain art in either pack, so a drop is a few
  pixels made in code. Indoors there is no rain — only the outdoor map carries
  the rain layer.
- **The clock's window** shows the sky: a rain cloud instead of the sun or
  moon, a dark cloud or lightning in a storm. The sheet has no orange storm
  cloud, so dawn and dusk show the plain rain picture for both.
- **Open:** no rain sound; no puddles or wet-ground tiles; rain does not stop
  or start mid-day (a day is one sky all through).

## 10. The clock (built) — what the player sees

Top-left corner of the screen, built from the UI pack's weather frame:

- **Window picture** shows the part of the day: dawn 6:00 (orange sunrise),
  day 8:00 (green sun), dusk 17:00 (orange sunset), night 20:00 (blue moon),
  late 24:00 (moon with stars). On a wet day it shows the weather instead —
  see §9a. Changes play a cute "set and rise": the old picture sinks, the sky
  colour cross-fades, the new one bounces up.
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
| UI — premium | `C:\Users\Rui\Downloads\Sprout Lands - UI Pack - Premium pack\Sprout Lands - UI Pack - Premium pack` (extracted into a folder of the same name) | Coins, hearts, stars, stamina circle, thermometer and weather icons, dialogue boxes, portrait frames, speech bubbles, settings menu, sliders, buttons, cursors, emotes, fonts (TTF in `fonts/Font files TTF`) |
| Sorry pack (early access) | `C:\Users\Rui\Downloads\Sprout Sorry pack` | **Fishing** (casting animations, rods, ~40 fish, junk, treasure), crops v2 + jams/juices/pickles, bread/honey, **bees**, **mines** (pickaxe, ores, gems, carts, bats, slimes), **village houses**, birch/cherry/pine biomes, frogs, new furniture and chests, **winter** (snow, ice, campfire, presents) |

Imported into `Assets/` so far: tiles, crops, trees, house, furniture, chest,
items, the player character, UI sheets, fonts, the clock atlas and the big
weather icons; and for step 2 the coins (UI pack), the signs (Sprites pack)
and the Oak chest from the Sorry pack, as the shipping bin. The Sorry pack
is early access — its art may change.

The UI pack's own **money-and-hearts sign** (plates hung on posts) exists
only on its all-in-one sheet, `UI Sprites/ALL UI ASSETS on one sheet.png`,
around x 721–893, y 430–606 — no separate file. `Tools/cut_status.py` cuts
it into `Assets/UI/Status.png`; the big hearts come from
`UI Sprites/Icons/special icons/Hearts.png`, the very same pixels.

## 12. Text

- **All game text uses the clock plate's font** — the pack's 5×5 capitals —
  chosen by the developer (2026-11-06) as the easiest to read. That covers
  the hotbar, the profile screen, storage, tooltips, the clock and the "+3"
  pop-ups over harvests and chopped trees.
- One face means headings and descriptions differ by **colour**, as on the
  plate: dark brown for names and values, softer brown for labels.
- Stack counts and pop-ups are **dark ink, no outline**, like the plate; a
  one-pixel halo in the colour behind them keeps them clear where they cross
  an icon or the grass.

## 13. Money: prices, seasons, the bin and the shop (built)

- **Coins**: a new game starts with **200** (as `econ_sim.py` does). The
  purse is on the status sign in the top-right corner (§14) and in the title
  row of every storage window.
- **Shipping bin** — beside the house's front door, cell (12, 6). Put
  produce in like a chest; whatever is in it at night is **sold overnight** and
  the coins are there in the morning (bed or passing out alike). It only takes
  things that sell — no tools — and says what its contents will fetch. One bin
  for the whole farm, however many are painted (as in Stardew).
- **Seed shop** — the carrot sign two cells along, (14, 6), standing in for the
  seed seller until the town exists (step 5). Click a packet to buy one,
  **Shift**-click for five; it sells only **this season's** seeds, and nothing
  in Winter. It buys nothing — selling is the bin's job.
- **Seeds sell back at half** their price, so packets bought by mistake are not
  wasted and buying to sell can never pay. Wood sells for 2, tree seeds for 5.

Prices are set so a tile kept planted earns what `econ_sim.py` needs (about
6 / 9 / 10 a day in Spring / Summer / Fall), packets at ~40% of the crop:

| Crop | Seasons | Days | Packet | Sells for |
|---|---|---|---|---|
| Turnip | Spring | 4 | 8 | 22 |
| Carrot | Spring | 4 | 10 | 24 |
| Lettuce | Spring | 5 | 12 | 30 |
| Bluebell | Spring | 5 | 14 | 32 |
| Cauliflower | Spring | 10 | 30 | 70 |
| Wheat | Summer, Fall | 4 | 12 | 32 |
| Rose | Summer | 7 | 26 | 63 |
| Cucumber | Summer | 8 | 26 | 68 |
| Tomato | Summer | 8 | 28 | 72 |
| Corn | Summer, Fall | 10 | 38 | 95 |
| Starfruit | Summer | 13 | 60 | 140 |
| Eggplant | Fall | 5 | 20 | 50 |
| Beet | Fall | 6 | 24 | 60 |
| Pumpkin | Fall | 12 | 52 | 130 |

These live in `Scripts/Crops.gd`; `Tools/econ_sim.py` keeps a copy to
simulate with, so change both (`test_economy.gd` checks the game's side).
The season assignments and prices were chosen in building step 2 to hit the
simulation's targets — they are tunable, not sacred.

## 14. Screen layout (HUD)

Decided by the developer, 2026-11-06:

- **Top-left: the clock** (§10).
- **Top-right: the status sign** — the UI pack's own design for health and
  money: the hearts on a wide plate, and the purse (coin and amount) on a
  smaller plate hung under it on two posts. It mirrors the clock: same 10px
  margin, same zoom. The hearts plate widens for more hearts, the purse plate
  for longer amounts.
- **Bottom: the hotbar**, alone. The heart bar that used to sit on top of it,
  and the purse plate briefly hung under the clock's date, are gone.
- The profile screen's left page shows the **same hearts** as the sign (the
  developer's call, same day), so health looks one way everywhere.
- **The profile screen is a two-page book** (the developer picked design 5 of
  5, 2026-11-17, from mock-ups cut from the pack's all-in-one sheet). Left page:
  the cat in the pack's bolted wooden frame, with name, held item and coins
  beside it, then hearts, stamina, pack and the farm totals two to a line.
  Right page: inventory / crafting / settings. The tabs are bookmarks standing
  up off the book's top edge over the right page, the open one lighter and
  taller. The developer asked for the frame to be **bigger, with clear space
  between the cat and the frame** -- 6px of recess all round (`PORTRAIT_MARGIN`).
  The book must fit a 1152px window at zoom 2 with the 9-slot hotbar row.

## 15. Saving (built)

Decided 2026-11-06, on the developer's go-ahead for "save first, then the
debt collector":

- **One save slot**, written **every night** — after a sleep in bed or passing
  out, once the night is over (crops grown, the shipping bin sold), so the
  save is the morning you wake to. As in Stardew, a day played and not slept
  on is not kept.
- **Opening the game** reads the save and you **wake in bed** in the house.
  With no save, it starts a new game on the farm, as before.
- **New game**: Settings → GAME → NEW GAME. The button asks once ("SURE?",
  for 3 seconds), then wipes the save and starts over on the farm, day one.
- Settings (UI scale, hotkeys, tooltips) are not part of the save yet.
