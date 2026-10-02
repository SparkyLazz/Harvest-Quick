class_name MarketGood
extends Resource

## One thing the town will trade in, and how steady its price is.
##
## A good is nearly all data, the same way a [NatureKind] is: the item it
## stands for, what it is worth on an ordinary day, and how wildly the town
## changes its mind about it. The [Market] does the arithmetic; this only says
## what to do it with.
##
## Seeds and produce are both goods. A packet of seeds is simply a good with
## little [member volatility] — the shop's prices wobble, but they do not
## swing, because a player who cannot guess what seed corn costs cannot plan
## at all. The crop it grows into is the volatile end of the same trade, and
## that gap is where the game is.

## The shop's three shelves.
##
## A shelf rather than a type test, because what a thing is and where it is sold
## are different questions: seeds and a sapling are both planted and belong
## together, while a fence and a scarecrow are placed exactly like a chest and do
## not. Guessing the shelf from the class would tie the catalogue's layout to the
## code's inheritance, and those two have no reason to agree.
enum Shelf {
	CROP, ## Seeds and anything else that goes in the ground.
	ANIMAL, ## Livestock, bought young and grown into.
	DECO, ## Everything set down rather than sown.
}

## Which shelf of the shop it sits on. Ignored unless [member in_shop].
@export var shelf: Shelf = Shelf.CROP

## Which item this is the price of. Matched by [member ItemData.id], so a
## good and the item it prices can be moved about on disk independently.
@export var item: ItemData

## What one of them fetches when the town neither wants nor is sick of it.
## Every other price in the game is this multiplied by something.
@export var base_price: int = 10

## How far the town's appetite drifts in a night, as a standard deviation on
## [member Market.demand_for]. 0 is a fixed price; 0.3 is a crop whose worth
## can double over a week of bad luck.
@export_range(0.0, 1.0, 0.01) var volatility: float = 0.15

## Whether the shop stocks it. Produce is sold *to* the market and never
## bought back, which is what stops a player buying carrots at the shop price
## and selling them into a spike for free money.
@export var in_shop: bool = false

## How many of them the town can absorb before the price starts to sag. The
## glut in [method Market.price] is measured against this, so a crop the town
## eats by the sackful can be grown in bulk and a luxury cannot.
@export var absorbs: float = 30.0
