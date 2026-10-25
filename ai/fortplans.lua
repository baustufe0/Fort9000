-- FORT 9000 - custom build plans per map
-- The plan files live in mods/fort-9000/fortplans/<map>/ (not in data/maps,
-- where Forts removes foreign files). This file is NOT modified by training.
--
-- Originals:       original plans of the map (in data/maps/<map>/) - the AI recognises the map by them;
--                  an entry containing "/" is a full path (e.g. a plan from another mod)
-- ReactorsPerSide: reactors per side (distinguishes e.g. Abyss from Abyss 2v2 with identical plans)
-- Plans:           plans the AI picks from at random; "original" = keep the game's plan
-- Strategy:        optional map-specific AI settings, override ai/strategy.lua for this
--                  map (tables are merged), e.g. Strategy = { Tempo = { UpdatePeriod = 0.8 } },
-- OriginalsDir:    folder of the original plans, if not maps/<map>/ (e.g. ai/forts/vanilla/mid/)
-- Force:           force a plan (for testing), e.g. Force = { Abyss = "fort-t1f1-Abyss-2.lua" },
-- Probe:           CS_UNSTABLE probe (testing only, sandbox without combat; never commit it switched on):
--                  once the plan is finished (or after At seconds) the AI stops and tries each device at each
--                  LinkT on every strut of its fort (docs/debugging.md, tools/fortgen/probe.py), e.g.
--                  Probe = { At = 480, Devices = { "sniper", "cannon" }, LinkT = { 0.2, 0.5, 0.8 },
--                            Materials = { "bracing", "armour" }, MaxAngle = 20, Interval = 0.2, Hold = 0, Max = 3000,
--                            Box = { x0, y0, x1, y1 } },   -- Box (world coordinates), Hold, Max optional;
--                  MaxAngle: steeper struts are skipped (devices need roughly level struts: CS_INVALIDNODES)

FortPlanConfig =
{
	Maps =
	{
		Abyss =
		{
			Originals = { "fort-t1f1-Abyss-1.lua", "fort-t1f1-Abyss-ToGA1.lua" },
			ReactorsPerSide = 1,
			Plans = { "original", "fort-t1f1-Abyss-2.lua", "fort-t1f1-Abyss-3.lua", "fort-t1f1-Abyss-4.lua", "fort-t1f1-Abyss-5.lua" },
		},
		-- Template map: the starting fort comes from ai/forts/vanilla/mid (shared with Penguin, Caverns, ...).
		-- Detected by FortPos + action count, so plans/values apply on all maps with these mid plans.
		Vanilla =
		{
			OriginalsDir = "ai/forts/vanilla/mid/",
			-- weapon_pack mod plans: same starting fort as Template-1, recorded at a different FortPos
			-- (ignored when the mod is not installed)
			Originals = { "fort-t1f1-Template-1.lua", "fort-t1f1-Template-2.lua",
				"mods/weapon_pack/ai/forts/vanilla/mid/fort-t1f1-Template-ToGAF1.lua",
				"mods/weapon_pack/ai/forts/vanilla/mid/fort-t1f1-Template-ToGWM2.lua" },
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
