-- FORT 9000 - custom build plans per map
-- The plan files live in mods/fort-9000/fortplans/<map>/ (not in data/maps,
-- where Forts removes foreign files). This file is NOT modified by training.
--
-- Originals:       original plans of the map (in data/maps/<map>/) - the AI recognises the map by them
-- ReactorsPerSide: reactors per side (distinguishes e.g. Abyss from Abyss 2v2 with identical plans)
-- Plans:           plans the AI picks from at random; "original" = keep the game's plan
-- Strategy:        optional map-specific AI settings, override ai/strategy.lua for this
--                  map (tables are merged), e.g. Strategy = { Tempo = { UpdatePeriod = 0.8 } },
-- OriginalsDir:    folder of the original plans, if not maps/<map>/ (e.g. ai/forts/vanilla/mid/)
-- Force:           force a plan (for testing), e.g. Force = { Abyss = "fort-t1f1-Abyss-2.lua" },

FortPlanConfig =
{
	Maps =
	{
		Abyss =
		{
			Originals = { "fort-t1f1-Abyss-1.lua", "fort-t1f1-Abyss-ToGA1.lua" },
			ReactorsPerSide = 1,
			Plans = { "original", "fort-t1f1-Abyss-2.lua", "fort-t1f1-Abyss-3.lua", "fort-t1f1-Abyss-4.lua" },
		},
		-- Template map: the starting fort comes from ai/forts/vanilla/mid (shared with Penguin, Caverns, ...).
		-- Detected by FortPos + action count, so plans/values apply on all maps with these mid plans.
		Vanilla =
		{
			OriginalsDir = "ai/forts/vanilla/mid/",
			Originals = { "fort-t1f1-Template-1.lua", "fort-t1f1-Template-2.lua" },
			Plans = { "original", "fort-t1f1-Vanilla-2.lua", "fort-t1f1-Vanilla-3.lua", "fort-t1f1-Vanilla-4.lua", "fort-t1f1-Vanilla-5.lua" },
			-- wide, flat map (forts ~6000 units apart, no cover): slower start,
			-- economy and long-range weapons (mortar/sniper) matter more
			Strategy =
			{
				EarlySeconds = 150,
				Aggression = { Early = 0.8 },
				TargetValue =
				{
					Heavy = { mine = 85, turbine = 90 },
					Small = { mortar = 90, sniper = 105 },
				},
			},
		},
		-- Vanilla 2v2, fort 2 (upper platform): starting fort = mirrored mid fort, plan ai/forts/vanilla/long.
		-- The plans are the Vanilla plans, converted into the coordinate system of the long plan (tools/fortgen/mid_to_long.py).
		VanillaLong =
		{
			OriginalsDir = "ai/forts/vanilla/long/",
			Originals = { "fort-t2f1-Template-1.lua" },
			Plans = { "original", "fort-t2f3-VanillaLong-2.lua", "fort-t2f3-VanillaLong-3.lua", "fort-t2f3-VanillaLong-4.lua", "fort-t2f3-VanillaLong-5.lua" },
			Strategy =
			{
				EarlySeconds = 150,
				Aggression = { Early = 0.8 },
				TargetValue =
				{
					Heavy = { mine = 85, turbine = 90 },
					Small = { mortar = 90, sniper = 105 },
				},
			},
		},
	},
	Force =
	{
	},
}
