-- FORT 9000 - eigene Bauplaene je Karte
-- Die Plan-Dateien liegen in mods/fort-9000/fortplans/<Karte>/ (nicht in data/maps,
-- dort entfernt Forts fremde Dateien). Diese Datei wird vom Training NICHT veraendert.
--
-- Originals:       Originalplaene der Karte (in data/maps/<Karte>/) - daran erkennt die KI die Karte
-- ReactorsPerSide: Reaktoren pro Seite (unterscheidet z.B. Abyss von Abyss 2v2 mit gleichen Plaenen)
-- Plans:           Plaene, aus denen die KI per Zufall waehlt; "original" = Plan des Spiels behalten
-- Strategy:        optionale kartenbezogene KI-Einstellungen, ueberschreiben ai/strategy.lua fuer diese
--                  Karte (Tabellen werden zusammengefuehrt), z.B. Strategy = { Tempo = { UpdatePeriod = 0.8 } },
-- OriginalsDir:    Ordner der Originalplaene, falls nicht maps/<Karte>/ (z.B. ai/forts/vanilla/mid/)
-- Force:           einen Plan erzwingen (zum Testen), z.B. Force = { Abyss = "fort-t1f1-Abyss-2.lua" },

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
		-- Vorlagen-Karte: Startfestung kommt aus ai/forts/vanilla/mid (geteilt mit Penguin, Caverns, ...).
		-- Erkennung per FortPos + Aktionszahl, daher gelten Plaene/Werte auf allen Karten mit diesen Mid-Plaenen.
		Vanilla =
		{
			OriginalsDir = "ai/forts/vanilla/mid/",
			Originals = { "fort-t1f1-Template-1.lua", "fort-t1f1-Template-2.lua" },
			Plans = { "original", "fort-t1f1-Vanilla-2.lua", "fort-t1f1-Vanilla-3.lua", "fort-t1f1-Vanilla-4.lua", "fort-t1f1-Vanilla-5.lua" },
			-- weite, flache Karte (Festungen ~6000 Einheiten auseinander, keine Deckung): langsamerer Start,
			-- Wirtschaft und Fernwaffen (Moerser/Sniper) zaehlen mehr
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
		-- Vanilla 2v2, Festung 2 (obere Plattform): Startfestung = gespiegelte Mid-Festung, Plan ai/forts/vanilla/long.
		-- Die Plaene sind die Vanilla-Plaene, umgerechnet ins Koordinatensystem des Long-Plans (tools/fortgen/mid_to_long.py).
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
