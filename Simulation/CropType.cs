using System;
using System.Collections.Generic;

// One species of crop: the numbers that are identical for every plant of that
// kind, held once instead of copied into every Crop standing in the field.
//
// A class, not a struct. Crop holds a reference to its species, and "is this a
// carrot?" should be answered by comparing identity, not by comparing numbers
// that happen to match. Not a record either, for the same reason: records
// compare by value, so two species tuned to identical numbers would silently
// become the same species.
//
// Simulation data only. Texture, frame size and frame count are art and live in
// the Game layer keyed by this type, exactly the way ObjectArt is keyed by
// TileSprite. The current sheet draws every crop in four frames and nobody
// waits four days for a pumpkin: frame count and growth length are two
// different numbers, and a single field holding both would make one of them
// quietly wrong. The art pack has now been swapped once without this file
// changing a single number, which is what that separation was for.
public sealed class CropType
{
	public CropType(string name, int daysToRipen, int seedPrice, int sellPrice,
		int? regrowStage = null, int maxHarvests = 1)
	{
		if (daysToRipen < 1)
		{
			throw new ArgumentOutOfRangeException(nameof(daysToRipen),
				$"{name}: a crop that ripens in no days is not a crop.");
		}

		// A regrow stage at or past ripeness would make the plant harvestable
		// again the instant it is picked, and one below zero is not a stage.
		// Caught here, at startup, rather than as an infinite harvest later.
		if (regrowStage is int stage && (stage < 0 || stage >= daysToRipen))
		{
			throw new ArgumentOutOfRangeException(nameof(regrowStage),
				$"{name}: regrow stage {stage} must sit between 0 and {daysToRipen - 1}.");
		}

		// Regrowth and harvest count are one decision written as two numbers, so
		// the pairs that contradict each other are refused here rather than left
		// to behave oddly in the field. A plant that does not regrow comes up
		// with its fruit and cannot be picked twice; one that regrows and is
		// picked once is a single-harvest crop written the long way.
		if (regrowStage is null && maxHarvests != 1)
		{
			throw new ArgumentOutOfRangeException(nameof(maxHarvests),
				$"{name}: a crop that does not regrow can only be picked once.");
		}

		if (regrowStage is not null && maxHarvests < 2)
		{
			throw new ArgumentOutOfRangeException(nameof(maxHarvests),
				$"{name}: a crop that regrows must be picked at least twice.");
		}

		Name = name;
		DaysToRipen = daysToRipen;
		SeedPrice = seedPrice;
		SellPrice = sellPrice;
		RegrowStage = regrowStage;
		MaxHarvests = maxHarvests;
	}

	// An identifier, not display text. What the player reads comes from the
	// Game layer, the same rule that keeps atlas coordinates out of Simulation.
	// It is also the obvious key to serialise against when saving arrives,
	// since a reference cannot be written to disk.
	public string Name { get; }

	// Days from planting to harvestable. This is the number a designer thinks
	// in, so it is the one stored; the stage count is derived from it rather
	// than kept beside it.
	public int DaysToRipen { get; }

	// Stage 0 is the day it went in the ground and stage DaysToRipen is ripe,
	// so there is always one more stage than there are days of waiting.
	public int GrowthStages => DaysToRipen + 1;

	public int SeedPrice { get; }
	public int SellPrice { get; }

	// Null means the plant comes up with the harvest. A value means it stays in
	// the ground and falls back to that stage, so the number is also how long
	// the next fruiting takes: DaysToRipen minus this.
	//
	// Null rather than a bool beside an int, so "regrows but nobody said from
	// where" has no way to be written down.
	public int? RegrowStage { get; }

	public bool Regrows => RegrowStage.HasValue;

	// How many times the plant can be picked before it is spent and the tile
	// comes free. One for everything that comes up with its fruit.
	//
	// It exists because without it a regrowing plant holds its tile until the
	// run ends, which makes it the only species valued as a commitment rather
	// than as one link in a chain of plantings. Such a species either loses at
	// every planting day or wins a dozen of them in a row, with nothing in
	// between, and no pair of seed and sell prices gives it a band in the
	// middle. This is the number that puts it back in the chain.
	public int MaxHarvests { get; }

	// Days between the second harvest and every one after it.
	public int DaysBetweenHarvests =>
		RegrowStage is int stage ? DaysToRipen - stage : DaysToRipen;

	// Days the tile stays occupied, planting to last picking. The number the
	// economy actually turns on: a crop is this many days of one tile bought
	// for SeedPrice, and all four species are bidding for the same days.
	public int DaysOccupied =>
		DaysToRipen + (MaxHarvests - 1) * DaysBetweenHarvests;
}

// Four species, deliberately not twenty. Three single-harvest crops tracing a
// "fast and cheap" to "slow and dear" line, plus one that fruits again so the
// second axis has something to stand on.
//
// Tuned against the question a player actually faces, which is never "which
// crop is best" but "which crop is best in this tile today, with this many days
// left in the run". A tile that is picked comes free the same day, so a species
// is worth one cycle of its own profit plus the best that can follow it.
//
// There used to be a table of winning days here. It is gone on purpose: it went
// stale the first time a price moved, and a comment that has to be right about
// numbers it cannot recompute is a comment that will eventually lie. The
// harness prints the live version, and it is one command.
//
// The number these prices are now tuned against is not gold. It is how many of
// a run's thirty days ask the player a question at all. Before tomato's
// occupancy was cut, the best line planted everything it would ever plant by
// day twelve and spent the remaining eighteen days picking on a fixed three-day
// rhythm: sixty per cent of a run on autopilot, invisible to any measure of
// profit. DaysOccupied is the field that controls this, and it is the first
// place to look when a run goes quiet.
public static class CropTypes
{
	//                                                  hari  benih  jual
	public static readonly CropType Carrot = new CropType("Carrot", 3, 10, 35);
	public static readonly CropType Corn = new CropType("Corn", 5, 30, 95);
	public static readonly CropType Pumpkin = new CropType("Pumpkin", 8, 60, 180);

	// Spent after the third picking: 12 days in the ground, the largest block any
	// species asks for, and then the tile comes free.
	//
	// It was five pickings first, and five was still a tenant. Eighteen days out
	// of thirty meant one planting decision held a tile for the rest of the run,
	// and the field stopped asking anything after day twelve. Twelve days fits
	// twice, so the same tile is decided on again in the last third.
	//
	// The price of that: it returns 12.9 a tile-day against pumpkin's 15, and
	// 38.8 an effort against pumpkin's 60, so it no longer wins on either axis
	// outright. It is still planted, but it is the species to watch if the next
	// tuning pass pushes it out of the field entirely.
	//
	// It was a tomato until the art pack changed. Sprout Lands ships fourteen
	// crops and no tomato, so the species was renamed and every number kept
	// exactly as the harness left it — an eggplant fruits again after picking
	// just as readily, and the role this crop plays is the second harvest axis,
	// not the fruit. Renaming it rather than retuning is deliberate: the whole
	// of Phase 3 and the 5,390 schedule are balanced against these six numbers,
	// and art has no business moving them.
	public static readonly CropType Eggplant =
		new CropType("Eggplant", 6, 25, 60, regrowStage: 3, maxHarvests: 3);

	public static readonly IReadOnlyList<CropType> All =
		new[] { Carrot, Corn, Pumpkin, Eggplant };
}
