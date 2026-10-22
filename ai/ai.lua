-- FORT 9000 - erweitert die eingebaute Forts-KI (data/ai/ai.lua).
-- Forts fuehrt diese Datei NACH der eingebauten KI aus, deshalb koennen wir deren
-- Funktionen und Tabellen hier erweitern. Bauen, Zielen, Reparieren bleiben wie gehabt;
-- neu sind:
--   1. Adaptive Zielwahl: die Prioritaetslisten werden laufend neu sortiert, nach
--      Grundwert (Strategy.TargetValue) + Bedrohung (wer schiesst und trifft uns gerade?)
--   2. Aggression je Spielphase und Wirtschaftslage
--   3. Luftabwehr, die bei starkem Beschuss mit Raketen/Moersern hochfaehrt
-- Alle Entscheidungen werden mit [CAI] ins Log geschrieben.
-- Wichtig: nur deterministische Werte verwenden (keine Uhrzeit, kein math.random),
-- sonst laufen Replays und Multiplayer auseinander.

--------------------------------------------------------------------------------
-- Strategie laden (dofile ist nur hier, bei der Initialisierung, erlaubt)

local CAI_StrategyFiles = { "mods/fort-9000/ai/strategy.lua" }
if type(path) == "string" then
	table.insert(CAI_StrategyFiles, 1, path .. "/ai/strategy.lua")
end
Strategy = nil
for _, f in ipairs(CAI_StrategyFiles) do
	if Strategy == nil then
		pcall(dofile, f)
	end
end

local CAI_Defaults =
{
	Version = 0, TrainedGames = 0, LogDecisions = true, ThinkInterval = 5,
	ThreatWeight = 30, ThreatHalf = 10, ThreatDecay = 0.85, ThreatPerShot = 1, ThreatPerHit = 3, ThreatPerReactorHit = 6,
	EarlySeconds = 120, LateSeconds = 480,
	Aggression = { Early = 0.85, Mid = 1.0, Late = 1.2 },
	AggressionExclude = { machinegun = true },
	RichMetal = 1500, RichBoost = 1.15, PoorMetal = 150, PoorEnergy = 300, PoorFactor = 0.75,
	IndirectThreatTypes = { mortar = true, mortar2 = true, missile = true, missileinv = true, missile2 = true, missile2inv = true },
	AntiAirThreatShots = 6, AntiAirBoostMax = 1.4,
	RebuildGiveUpSeconds = 120,
	BuildSkipSeconds = 90, BuildSkipMinMetal = 300,
	Fire = { Enabled = true, Interval = 1.0, WeaponsPerTick = 3, AlwaysOffensive = true, RebuildFireFactor = 2.5 },
	Tempo = { UpdatePeriod = 2.0, UpdatePeriodEasy = 4.0, UpdatePeriodNormal = 2.0, UpdatePeriodHard = 1.0, UpdateAfterRebuildDelay = 0.625, ConstructionMean = 20, ConstructionMin = 12,
		NonConstructionMean = 6, NonConstructionMin = 3, RepairPeriod = 6,
		RepairPeriodEasy = 12, RepairPeriodNormal = 6, RepairPeriodHard = 3 },
	TargetValue = { Heavy = {}, Small = {} },
}

local CAI_StrategyLoaded = (type(Strategy) == "table")
if not CAI_StrategyLoaded then
	Strategy = {}
end
for k, v in pairs(CAI_Defaults) do
	if Strategy[k] == nil then
		Strategy[k] = v
	end
end
if Strategy.TargetValue.Heavy == nil then Strategy.TargetValue.Heavy = {} end
if Strategy.TargetValue.Small == nil then Strategy.TargetValue.Small = {} end

--------------------------------------------------------------------------------
-- Eigene Bauplaene aus dem Mod-Ordner (mods/fort-9000/fortplans/<Karte>/)
-- Forts entfernt fremde Dateien aus data/maps, deshalb liegen die Plaene im Mod.
--
-- Ablauf:
--  1. Beim Initialisieren (nur hier ist dofile erlaubt) werden alle eigenen Plaene und die
--     Originalplaene der Karten vorgeladen. Zu diesem Zeitpunkt kennt die KI weder ihr Team
--     noch die Karte.
--  2. Das Spiel ruft spaeter OffsetFort/MirrorFort (Plan an die echte Festung anpassen) und
--     Load auf. Beim ersten dieser Aufrufe wird getauscht: Karte am Spielplan erkennen,
--     eigenen Plan waehlen, in die Koordinaten des Spielplans verschieben, einsetzen.
--     Das Spiel wendet danach seine eigene Verschiebung/Spiegelung auf unseren Plan an.

CAI_Plan = { maps = {}, done = false, notes = {} }

local function CAI_PlanNote(msg)
	Log("[CAI] T" .. tostring(teamId) .. " " .. msg)
end

-- Direkter Zugriff auf die Plan-Variablen (rawget/rawset gibt es in Forts nicht)
local function CAI_GetPlanGlobals()
	return { Fort = Fort, FortTeam = FortTeam, FortId = FortId, FortPos = FortPos,
		FortTableStartLine = FortTableStartLine, FortTableCommentLines = FortTableCommentLines }
end

local function CAI_SetPlanGlobals(t)
	Fort = t.Fort
	FortTeam = t.FortTeam
	FortId = t.FortId
	FortPos = t.FortPos
	FortTableStartLine = t.FortTableStartLine
	FortTableCommentLines = t.FortTableCommentLines
end

local function CAI_LoadPlanFile(path)
	local saved = CAI_GetPlanGlobals()
	CAI_SetPlanGlobals({})
	local ok, err = pcall(dofile, path)
	local t = CAI_GetPlanGlobals()
	CAI_SetPlanGlobals(saved)
	if ok and type(t.Fort) == "table" and #t.Fort > 0 and type(t.FortPos) == "table" then
		return t
	end
	return nil, (ok and "kein Fort" or tostring(err))
end

FortPlanConfig = nil
pcall(dofile, "mods/fort-9000/ai/fortplans.lua")
if type(FortPlanConfig) ~= "table" then FortPlanConfig = {} end

local function CAI_PreloadPlans()
	local summary = {}
	for mapName, m in pairs(FortPlanConfig.Maps or {}) do
		local entry = { sigs = {}, plans = {}, list = m.Plans or {}, reactors = m.ReactorsPerSide }
		for _, f in ipairs(m.Originals or {}) do
			local t = CAI_LoadPlanFile((m.OriginalsDir or ("maps/" .. mapName .. "/")) .. f)
			if t then
				table.insert(entry.sigs, { file = f, x = t.FortPos.x, y = t.FortPos.y, n = #t.Fort })
			end
		end
		local count = 0
		for _, f in ipairs(entry.list) do
			if f ~= "original" then
				local t, err = CAI_LoadPlanFile("mods/fort-9000/fortplans/" .. mapName .. "/" .. f)
				if t then
					entry.plans[f] = t
					count = count + 1
				else
					Log("[CAI] PLAN-LADEFEHLER " .. mapName .. "/" .. f .. ": " .. tostring(err))
				end
			end
		end
		CAI_Plan.maps[mapName] = entry
		table.insert(summary, mapName .. ":" .. count .. "/" .. #entry.sigs)
	end
	Log("[CAI] PLAN-VORLADEN " .. table.concat(summary, " ") .. " (eigene/originale)")
end

local okPre, errPre = pcall(CAI_PreloadPlans)
if not okPre then
	Log("[CAI] PLAN-VORLADEN FEHLER " .. tostring(errPre))
end

local function CAI_OwnReactors()
	local side = teamId % MAX_SIDES
	local n = 0
	for i = 0, (GetDeviceCountSide(side) or 0) - 1 do
		if GetDeviceType(GetDeviceIdSide(side, i)) == "reactor" then
			n = n + 1
		end
	end
	return n
end

local function CAI_IdentifyMap(engineFort, E)
	if type(GetMapFilename) == "function" then
		local ok, f = pcall(GetMapFilename)
		if ok and type(f) == "string" then
			local name = string.match(f, "maps[/\\]([^/\\]+)")
			if name and CAI_Plan.maps[name] then
				return name, "dateiname", nil
			end
		end
	end
	local cands = {}
	for name, entry in pairs(CAI_Plan.maps) do
		for _, sg in ipairs(entry.sigs) do
			if math.abs(sg.x - E.x) < 1 and math.abs(sg.y - E.y) < 1 and sg.n == #engineFort then
				table.insert(cands, { name = name, file = sg.file, entry = entry })
			end
		end
	end
	if #cands > 1 then
		local ok, r = pcall(CAI_OwnReactors)
		if ok then
			local filtered = {}
			for _, c in ipairs(cands) do
				if c.entry.reactors == nil or c.entry.reactors == r then table.insert(filtered, c) end
			end
			cands = filtered
		end
	end
	-- mehrere Originalplaene derselben Karte mit gleicher Signatur (z.B. Vanilla Template-1/-2) sind eindeutig
	local sameMap = #cands > 0
	for _, c in ipairs(cands) do
		if c.name ~= cands[1].name then sameMap = false end
	end
	if sameMap then
		return cands[1].name, "signatur", cands[1].file
	end
	return nil, (#cands == 0 and "kein-bekannter-spielplan" or "mehrdeutig")
end

local function CAI_ChoosePlan(entry, mapName)
	local forced = FortPlanConfig.Force and FortPlanConfig.Force[mapName]
	if forced then return forced, "erzwungen" end
	local n = #entry.list
	if n == 0 then return "original", "leer" end
	local idx = nil
	if type(GetRandomInteger) == "function" then
		local ok, r = pcall(GetRandomInteger, 1, n, "CAI plan " .. tostring(teamId))
		if ok and type(r) == "number" and r >= 1 and r <= n then idx = r end
	end
	if idx == nil then
		return entry.list[1 + (math.floor(type(teamId) == "number" and teamId or 0) % n)], "teamId"
	end
	return entry.list[idx], "zufall"
end

-- Kartenbezogene Einstellungen: FortPlanConfig.Maps[<Karte>].Strategy ueberschreibt Werte der
-- Strategiedatei (Tabellen werden zusammengefuehrt, z.B. nur Tempo.UpdatePeriod).
local function CAI_Merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			CAI_Merge(dst[k], v)
		else
			dst[k] = v
		end
	end
end

function CAI_ApplyMapStrategy(mapName)
	local m = FortPlanConfig.Maps and FortPlanConfig.Maps[mapName]
	if m and type(m.Strategy) == "table" then
		CAI_Merge(Strategy, m.Strategy)
		local keys = {}
		for k in pairs(m.Strategy) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		CAI_PlanNote("KARTE-STRATEGIE " .. mapName .. ": " .. table.concat(keys, ","))
	end
end

function CAI_TrySwapPlan(where)
	if CAI_Plan.done then return end
	CAI_Plan.done = true
	local engineFort, E = Fort, FortPos
	if type(engineFort) ~= "table" or #engineFort == 0 or type(E) ~= "table" then
		CAI_PlanNote("PLAN file=original grund=kein-spielplan bei=" .. where)
		return
	end
	local mapName, how, engineFile = CAI_IdentifyMap(engineFort, E)
	if not mapName then
		CAI_PlanNote("PLAN file=original grund=" .. tostring(how) .. " bei=" .. where)
		return
	end
	local entry = CAI_Plan.maps[mapName]
	pcall(CAI_ApplyMapStrategy, mapName)
	local choice, why = CAI_ChoosePlan(entry, mapName)
	local ours = entry.plans[choice]
	if choice == "original" or ours == nil then
		CAI_PlanNote("PLAN map=" .. mapName .. " file=" .. (engineFile or "original") .. " grund=" .. why
			.. (ours == nil and choice ~= "original" and " (eigener Plan fehlt)" or "") .. " bei=" .. where)
		return
	end
	-- in die Koordinaten des Spielplans verschieben
	local dx, dy = E.x - ours.FortPos.x, E.y - ours.FortPos.y
	local function Shift(p)
		if p then p.x = p.x + dx; p.y = p.y + dy end
	end
	for _, a in ipairs(ours.Fort) do
		Shift(a.PosA); Shift(a.PosB); Shift(a.NewNodePos); Shift(a.GroundPosition)
	end
	CAI_SetPlanGlobals({
		Fort = ours.Fort,
		FortTeam = ours.FortTeam or FortTeam,
		FortId = ours.FortId or FortId,
		FortPos = { x = E.x, y = E.y },
	})
	CAI_PlanNote("PLAN map=" .. mapName .. " file=" .. choice .. " aktionen=" .. #ours.Fort .. " statt=" .. tostring(engineFile)
		.. " wahl=" .. why .. " erkannt=" .. how .. " bei=" .. where .. " verschiebung=" .. math.floor(dx + 0.5) .. "," .. math.floor(dy + 0.5))
end

local CAI_BaseOffsetFort = OffsetFort
function OffsetFort(offset, structureId)
	local ok, err = pcall(CAI_TrySwapPlan, "OffsetFort")
	if not ok then Log("[CAI] PLAN-FEHLER " .. tostring(err)) end
	CAI_PlanNote("TRANSFORM OffsetFort " .. tostring(offset and offset.x) .. "," .. tostring(offset and offset.y))
	return CAI_BaseOffsetFort(offset, structureId)
end

local CAI_BaseMirrorFort = MirrorFort
function MirrorFort(pivot, offset, structureId)
	local ok, err = pcall(CAI_TrySwapPlan, "MirrorFort")
	if not ok then Log("[CAI] PLAN-FEHLER " .. tostring(err)) end
	CAI_PlanNote("TRANSFORM MirrorFort pivot=" .. tostring(pivot) .. " " .. tostring(offset and offset.x) .. "," .. tostring(offset and offset.y))
	return CAI_BaseMirrorFort(pivot, offset, structureId)
end

--------------------------------------------------------------------------------
-- Hilfsfunktionen

function CAI_Log(msg)
	if Strategy.LogDecisions then
		Log("[CAI] T" .. tostring(teamId) .. " " .. tostring(msg))
	end
end

local function CAI_Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function CAI_Side(id)
	if type(id) ~= "number" then return -1 end
	return id % MAX_SIDES
end

local function CAI_Round(v)
	return math.floor(v * 100 + 0.5) / 100
end

--------------------------------------------------------------------------------
-- Bautempo: die eingebaute KI fuehrt pro Durchlauf (data.UpdatePeriod) nur EINE Bauaktion aus
-- und legt zwischen Bauphasen (ConstructionPeriod) lange Pausen ein (NonConstructionPeriod).

function CAI_ApplyTempo()
	local t = Strategy.Tempo
	if type(t) ~= "table" then return "aus" end
	if data.CAI then
		data.CAI.baseTempo = { data.UpdatePeriod, data.UpdateAfterRebuildDelay, data.ConstructionPeriodMean, data.ConstructionPeriodMin,
			data.NonConstructionPeriodMean, data.NonConstructionPeriodMin, data.RepairPeriod }
	end
	if t.UpdatePeriod then data.UpdatePeriod = t.UpdatePeriod end
	-- Takt und Reparaturzeit je Schwierigkeit: leicht (0) / normal (0,5) / schwer (1), dazwischen linear
	local function byDifficulty(easy, normal, hard)
		local d = tonumber(data.difficulty) or 0.5
		if d < 0 then d = 0 elseif d > 1 then d = 1 end
		if d <= 0.5 then return easy + (d / 0.5) * (normal - easy) end
		return normal + ((d - 0.5) / 0.5) * (hard - normal)
	end
	if t.UpdatePeriodEasy and t.UpdatePeriodNormal and t.UpdatePeriodHard then
		data.UpdatePeriod = byDifficulty(t.UpdatePeriodEasy, t.UpdatePeriodNormal, t.UpdatePeriodHard)
	end
	if t.UpdateAfterRebuildDelay then data.UpdateAfterRebuildDelay = t.UpdateAfterRebuildDelay end
	if t.ConstructionMean then data.ConstructionPeriodMean = t.ConstructionMean end
	if t.ConstructionMin then data.ConstructionPeriodMin = t.ConstructionMin end
	if t.NonConstructionMean then data.NonConstructionPeriodMean = t.NonConstructionMean end
	if t.NonConstructionMin then data.NonConstructionPeriodMin = t.NonConstructionMin end
	if t.RepairPeriod then data.RepairPeriod = t.RepairPeriod end
	if t.RepairPeriodEasy and t.RepairPeriodNormal and t.RepairPeriodHard then
		data.RepairPeriod = byDifficulty(t.RepairPeriodEasy, t.RepairPeriodNormal, t.RepairPeriodHard)
	end
	return "schwierigkeit=" .. tostring(data.difficulty) .. " takt=" .. tostring(data.UpdatePeriod) .. "s bauen=" .. tostring(data.ConstructionPeriodMean)
		.. "s pause=" .. tostring(data.NonConstructionPeriodMean) .. "s reparatur=" .. tostring(data.RepairPeriod) .. "s"
end

--------------------------------------------------------------------------------
-- Feuersteuerung: die eingebaute KI feuert nur in Baupausen und hoechstens eine Waffe pro
-- Durchlauf; beim Bauen spart sie zusaetzlich. Hier: immer angriffsbereit, mehr Feuer beim
-- Bauen und ein eigener Takt, der pro Sekunde mehrere bereite Waffen feuern laesst.
-- TryFireGun prueft selbst Bereitschaft, Tueren, Gruppen und Ziel.

function CAI_ApplyFire()
	local f = Strategy.Fire
	if type(f) ~= "table" or not f.Enabled then return "aus" end
	data.CAI.baseFire = { HardThreshold = data.HardThreshold, Rebuild = {} }
	if f.AlwaysOffensive then
		data.HardThreshold = 0
	end
	if type(data.FireDuringRebuildProbability) == "table" then
		for k, v in pairs(data.FireDuringRebuildProbability) do
			data.CAI.baseFire.Rebuild[k] = v
			data.FireDuringRebuildProbability[k] = CAI_Clamp(v * (f.RebuildFireFactor or 1), 0, 1)
		end
	end
	data.CAI.firePtr = 0
	data.CAI.fireAttempts = 0
	if ScheduledCallCountOfFunc(CAI_FireTick) == 0 then
		ScheduleCall(f.Interval or 1, CAI_FireTick)
	end
	return "takt=" .. tostring(f.Interval) .. "s waffen=" .. tostring(f.WeaponsPerTick) .. " immer=" .. tostring(f.AlwaysOffensive)
		.. " beimBauen=x" .. tostring(f.RebuildFireFactor)
end

function CAI_RestoreFire()
	local b = data.CAI and data.CAI.baseFire
	if not b then return end
	data.HardThreshold = b.HardThreshold
	for k, v in pairs(b.Rebuild) do
		data.FireDuringRebuildProbability[k] = v
	end
end

function CAI_FireTick()
	local st = data.CAI
	local f = Strategy.Fire
	if st == nil or data.gameEnded or data.defeated or data.Disable or data.DisableOffence or data.HumanAssist then
		return
	end
	local ok, err = pcall(function()
		local n = GetWeaponCount(teamId) or 0
		if n == 0 or (data.offencePoints or 1) < 1 then return end
		local tries = math.min(f.WeaponsPerTick or 3, n)
		for i = 1, tries do
			if st.firePtr >= n then st.firePtr = 0 end
			local id = GetWeaponId(teamId, st.firePtr)
			st.firePtr = st.firePtr + 1
			if id and id > 0 and not IsDummy(id) and IsAIDeviceAvailable(id) and IsWeaponReadyToFire(id)
				and (data.ActionQueue == nil or data.ActionQueue[id] == nil) then
				st.fireAttempts = st.fireAttempts + 1
				TryFireGun(id)
			end
		end
	end)
	if not ok then
		CAI_Log("FEHLER Feuersteuerung: " .. tostring(err))
	end
	ScheduleCall(f.Interval or 1, CAI_FireTick)
end

--------------------------------------------------------------------------------
-- Fehlersuche: fehlgeschlagene Bauversuche mit Fehlercode ins Log schreiben
-- (je Strebe/Geraet und Fehler nur einmal, damit das Log klein bleibt)

local CAI_BuildErrSeen = {}
local CAI_BuildErrCount = 0

local function CAI_ResultName(r)
	if type(CS) == "table" and CS[r] then return tostring(CS[r]) end
	return tostring(r)
end

local function CAI_NoteBuildError(kind, what, a, b, r)
	if data.CAI == nil or data.HumanAssist then return end
	local key = kind .. ":" .. tostring(what) .. ":" .. tostring(a) .. ":" .. tostring(b) .. ":" .. tostring(r)
	if CAI_BuildErrSeen[key] or CAI_BuildErrCount >= 200 then return end
	CAI_BuildErrSeen[key] = true
	CAI_BuildErrCount = CAI_BuildErrCount + 1
	CAI_Log("BAUFEHLER " .. kind .. " " .. tostring(what) .. " " .. tostring(a) .. "-" .. tostring(b)
		.. " " .. CAI_ResultName(r) .. " aktion=" .. tostring(data.fortIndex))
end

local function CAI_IsSuccess(r)
	return r == CS_SUCCESS
end

-- Die Bau-Funktionen stellt das Spiel erst nach dem Initialisieren bereit,
-- deshalb werden sie erst in Load eingehaengt.
CAI_BuildLoggingInstalled = false

function CAI_InstallBuildLogging()
	if CAI_BuildLoggingInstalled then return "schon aktiv" end
	CAI_BuildLoggingInstalled = true
	local hooked = {}
	if type(CreateLink) == "function" then
		local CAI_BaseCreateLink = CreateLink
		CreateLink = function(team, material, nodeA, nodeB, ...)
			local r = CAI_BaseCreateLink(team, material, nodeA, nodeB, ...)
			if not CAI_IsSuccess(r) and r ~= CS_INSUFFICIENTRESOURCES then
				pcall(CAI_NoteBuildError, "Strebe", material, nodeA, nodeB, r)
			end
			return r
		end
		table.insert(hooked, "CreateLink")
	end
	if type(CreateNode) == "function" then
		local CAI_BaseCreateNode = CreateNode
		CreateNode = function(team, material, nodeA, pos, ...)
			local r = CAI_BaseCreateNode(team, material, nodeA, pos, ...)
			if type(r) == "number" and r < 0 and r ~= CS_INSUFFICIENTRESOURCES then
				pcall(CAI_NoteBuildError, "Knoten", material, nodeA, pos and (math.floor(pos.x) .. "," .. math.floor(pos.y)), r)
			end
			return r
		end
		table.insert(hooked, "CreateNode")
	end
	if type(CreateDeviceWithFlags) == "function" then
		local CAI_BaseCreateDeviceWithFlags = CreateDeviceWithFlags
		CreateDeviceWithFlags = function(team, saveName, nodeA, nodeB, t, ...)
			local r = CAI_BaseCreateDeviceWithFlags(team, saveName, nodeA, nodeB, t, ...)
			if type(r) == "number" and r < 0 and r ~= CS_INSUFFICIENTRESOURCES then
				pcall(CAI_NoteBuildError, "Geraet", saveName, nodeA, nodeB, r)
			end
			return r
		end
		table.insert(hooked, "CreateDeviceWithFlags")
	end
	if type(CreateGroundDevice) == "function" then
		local CAI_BaseCreateGroundDevice = CreateGroundDevice
		CreateGroundDevice = function(team, saveName, pos, ...)
			local r = CAI_BaseCreateGroundDevice(team, saveName, pos, ...)
			if type(r) == "number" and r < 0 and r ~= CS_INSUFFICIENTRESOURCES then
				pcall(CAI_NoteBuildError, "Bodengeraet", saveName, pos and (math.floor(pos.x) .. "," .. math.floor(pos.y)), "", r)
			end
			return r
		end
		table.insert(hooked, "CreateGroundDevice")
	end
	if type(UpgradeDevice) == "function" then
		local CAI_BaseUpgradeDevice = UpgradeDevice
		UpgradeDevice = function(id, saveName, ...)
			local r = CAI_BaseUpgradeDevice(id, saveName, ...)
			if type(r) == "number" and r < 0 and r ~= CS_INSUFFICIENTRESOURCES then
				pcall(CAI_NoteBuildError, "Upgrade", saveName, id, "", r)
			end
			return r
		end
		table.insert(hooked, "UpgradeDevice")
	end
	return (#hooked > 0) and table.concat(hooked, ",") or "keine Bau-Funktionen gefunden"
end

--------------------------------------------------------------------------------
-- Initialisierung

function CAI_Init()
	if data.CAI and data.CAI.initialised then
		return
	end
	data.CAI =
	{
		initialised = true,
		ticks = 0,
		threat = {},       -- gegnerischer Waffentyp -> Bedrohung (zerfaellt mit der Zeit)
		shots = {},        -- gegnerischer Waffentyp -> Schuesse gesamt
		recentIndirect = 0,
		projOwner = {},    -- Projektil-Node -> Waffentyp, um Treffer einer Waffe zuzuordnen
		projCount = 0,
		lost = {},         -- eigene verlorene Geraete nach Typ
		kills = {},        -- zerstoerte Gegnergeraete nach Typ
		baseOff = {},
		baseAA = {},
	}
	for k, v in pairs(data.OffensiveFireProbability) do
		data.CAI.baseOff[k] = v
	end
	for k, v in pairs(data.AntiAirFireProbability) do
		data.CAI.baseAA[k] = v
	end
	CAI_Log("INIT strategy=v" .. tostring(Strategy.Version) .. " trained=" .. tostring(Strategy.TrainedGames)
		.. " loaded=" .. tostring(CAI_StrategyLoaded) .. " difficulty=" .. tostring(data.difficulty))
end

--------------------------------------------------------------------------------
-- 1. Adaptive Zielwahl

function CAI_BuildPriorityList(baseList, values)
	local entries = {}
	for i, saveName in ipairs(baseList) do
		local base = values[saveName]
		if base == nil then
			base = math.max(5, 100 - 4 * (i - 1))
		end
		-- saettigend: bei ThreatHalf gibt es den halben, bei viel Bedrohung fast den vollen Bonus
		local threat = data.CAI.threat[saveName] or 0
		local bonus = Strategy.ThreatWeight * threat / (threat + Strategy.ThreatHalf)
		table.insert(entries, { name = saveName, score = base + bonus, idx = i })
	end
	-- stabil und deterministisch sortieren
	table.sort(entries, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.idx < b.idx
	end)
	local list = {}
	for i, e in ipairs(entries) do
		list[i] = e.name
	end
	return list, entries
end

local function CAI_TopString(entries, n)
	local parts = {}
	for i = 1, math.min(n, #entries) do
		parts[#parts + 1] = entries[i].name .. ":" .. CAI_Round(entries[i].score)
	end
	return table.concat(parts, ",")
end

function CAI_UpdateTargets()
	local heavy, heavyEntries = CAI_BuildPriorityList(HeavyArmsPriorities, Strategy.TargetValue.Heavy)
	local small, smallEntries = CAI_BuildPriorityList(SmallArmsPriorities, Strategy.TargetValue.Small)
	data.HeavyArmsPrioritiesOverride = heavy
	data.SmallArmsPrioritiesOverride = small
	return "heavy=" .. CAI_TopString(heavyEntries, 4) .. " small=" .. CAI_TopString(smallEntries, 4)
end

--------------------------------------------------------------------------------
-- 2. Aggression je Phase und Wirtschaft

function CAI_UpdateAggression(elapsed)
	local s = Strategy
	local phase, mult
	if elapsed < s.EarlySeconds then
		phase, mult = "early", s.Aggression.Early
	elseif elapsed < s.LateSeconds then
		phase, mult = "mid", s.Aggression.Mid
	else
		phase, mult = "late", s.Aggression.Late
	end

	local metal, energy = -1, -1
	local res = GetTeamResources(teamId)
	if type(res) == "table" or type(res) == "userdata" then
		metal = res.metal or -1
		energy = res.energy or -1
	end
	local econ = "normal"
	if metal >= s.RichMetal then
		mult = mult * s.RichBoost
		econ = "rich"
	elseif (metal >= 0 and metal <= s.PoorMetal) or (energy >= 0 and energy <= s.PoorEnergy) then
		mult = mult * s.PoorFactor
		econ = "poor"
	end

	for k, base in pairs(data.CAI.baseOff) do
		if not s.AggressionExclude[k] then
			data.OffensiveFireProbability[k] = CAI_Clamp(base * mult, 0, 1)
		end
	end
	return "phase=" .. phase .. " econ=" .. econ .. " m=" .. CAI_Round(metal) .. " e=" .. CAI_Round(energy) .. " aggr=" .. CAI_Round(mult)
end

--------------------------------------------------------------------------------
-- 3. Luftabwehr nach Beschussdruck

function CAI_UpdateAntiAir()
	local s = Strategy
	local pressure = CAI_Clamp(data.CAI.recentIndirect / math.max(1, s.AntiAirThreatShots), 0, 1)
	data.CAI.recentIndirect = 0
	local factor = 1 + (s.AntiAirBoostMax - 1) * pressure
	for k, base in pairs(data.CAI.baseAA) do
		data.AntiAirFireProbability[k] = CAI_Clamp(base * factor, 0, 1)
	end
	return "aa=" .. CAI_Round(factor)
end

--------------------------------------------------------------------------------
-- Denkschleife

function CAI_Think()
	if data.gameEnded or data.CAI == nil then
		return
	end
	local st = data.CAI
	st.ticks = st.ticks + 1
	local elapsed = st.ticks * Strategy.ThinkInterval

	for k, v in pairs(st.threat) do
		st.threat[k] = v * Strategy.ThreatDecay
	end

	-- Bau-Fortschritt und Notbremse: die eingebaute KI baut nichts Neues, solange eine
	-- vorgemerkte Wiederaufbau-Aktion scheitert. Haengt eine zu lange, wird sie aufgegeben.
	local rebuildCount = 0
	st.rebuildSince = st.rebuildSince or {}
	-- Wartet die KI nur auf Metall, laeuft die Uhr nicht weiter: solche Aktionen sind nicht
	-- "kaputt", sie werden gebaut, sobald wieder genug Metall da ist.
	local okRes, resNow = pcall(GetTeamResources, teamId)
	local metalNow = (okRes and resNow and resNow.metal) or 0
	local starved = data.ResourceStarved or metalNow < Strategy.BuildSkipMinMetal
	if type(data.Rebuild) == "table" then
		for k in pairs(data.Rebuild) do
			rebuildCount = rebuildCount + 1
			local since = st.rebuildSince[k]
			if since ~= nil and starved then
				st.rebuildSince[k] = since + Strategy.ThinkInterval
			elseif since == nil then
				st.rebuildSince[k] = elapsed
			elseif elapsed - since >= Strategy.RebuildGiveUpSeconds then
				data.Rebuild[k] = nil
				st.rebuildSince[k] = nil
				local a = Fort and Fort[k]
				CAI_Log("AUFGEGEBEN Aktion " .. tostring(k) .. " typ=" .. tostring(a and a.Type)
					.. " " .. tostring(a and (a.DeviceSaveName or a.MaterialSaveName)) .. " nach " .. Strategy.RebuildGiveUpSeconds .. "s")
			end
		end
		for k in pairs(st.rebuildSince) do
			if not data.Rebuild[k] then st.rebuildSince[k] = nil end
		end
	end

	-- Zweite Notbremse: haengt der normale Weiterbau an derselben Aktion, obwohl Metall da ist,
	-- wird die Aktion uebersprungen (die eingebaute KI wartet sonst endlos).
	local fi = data.fortIndex
	if type(fi) == "number" and Fort and fi <= #Fort then
		if st.buildIndex ~= fi or rebuildCount > 0 then
			-- neue Aktion, oder der Bau wartet gerade auf Wiederaufbau: Uhr neu starten
			if st.buildIndex ~= fi then st.buildHadRes = false end
			st.buildIndex = fi
			st.buildSince = elapsed
		else
			local okR, res = pcall(GetTeamResources, teamId)
			if okR and res and (res.metal or 0) >= Strategy.BuildSkipMinMetal then
				st.buildHadRes = true
			end
			if st.buildHadRes and elapsed - st.buildSince >= Strategy.BuildSkipSeconds then
				local a = Fort[fi]
				CAI_Log("UEBERSPRUNGEN Aktion " .. fi .. " typ=" .. tostring(a and a.Type) .. " "
					.. tostring(a and (a.DeviceSaveName or a.MaterialSaveName)) .. " nach " .. (elapsed - st.buildSince) .. "s")
				data.fortIndex = fi + 1
				st.buildIndex = fi + 1
				st.buildSince = elapsed
				st.buildHadRes = false
			end
		end
	end

	local parts = { "THINK t=" .. elapsed .. " bau=" .. tostring(data.fortIndex) .. "/" .. tostring(Fort and #Fort) .. " wiederaufbau=" .. rebuildCount }
	local ok, res = pcall(CAI_UpdateTargets)
	parts[#parts + 1] = ok and res or ("FEHLER Ziele: " .. tostring(res))
	ok, res = pcall(CAI_UpdateAggression, elapsed)
	parts[#parts + 1] = ok and res or ("FEHLER Aggression: " .. tostring(res))
	ok, res = pcall(CAI_UpdateAntiAir)
	parts[#parts + 1] = ok and res or ("FEHLER Luftabwehr: " .. tostring(res))
	parts[#parts + 1] = "feuer=" .. tostring(st.fireAttempts or 0)
	st.fireAttempts = 0
	CAI_Log(table.concat(parts, " "))

	ScheduleCall(Strategy.ThinkInterval, CAI_Think)
end

--------------------------------------------------------------------------------
-- Einhaengen in die Ereignisse der eingebauten KI

local CAI_BaseLoad = Load
function Load(gameStart)
	local okSwap, errSwap = pcall(CAI_TrySwapPlan, "Load")
	if not okSwap then Log("[CAI] PLAN-FEHLER " .. tostring(errSwap)) end
	CAI_BaseLoad(gameStart)
	-- Hilfs-KI auf der Seite eines menschlichen Spielers (z.B. Luftabwehr-Assistent): nicht anfassen
	if data.HumanAssist then
		Log("[CAI] T" .. tostring(teamId) .. " ASSIST FORT-9000-KI inaktiv (Hilfs-KI eines Spielers)")
		return
	end
	local ok, err = pcall(CAI_Init)
	if not ok then
		Log("[CAI] FEHLER bei Init: " .. tostring(err))
		return
	end
	local okT, tempo = pcall(CAI_ApplyTempo)
	CAI_Log("TEMPO " .. tostring(tempo))
	local okF, fire = pcall(CAI_ApplyFire)
	CAI_Log("FEUER " .. tostring(fire))
	local okL, logging = pcall(CAI_InstallBuildLogging)
	CAI_Log("FEHLERSUCHE " .. tostring(logging))
	if ScheduledCallCountOfFunc(CAI_Think) == 0 then
		ScheduleCall(Strategy.ThinkInterval, CAI_Think)
	end
end

-- Das Spiel macht eine KI erst NACH Load() zur Hilfs-KI eines Spielers (Luftabwehr-Assistent).
-- Dann die FORT-9000-KI abschalten und die veraenderten Werte zuruecksetzen.
local CAI_BaseEnableHumanAssist = EnableHumanAssist
function EnableHumanAssist()
	if data.CAI and data.CAI.baseOff then
		for k, v in pairs(data.CAI.baseOff) do
			data.OffensiveFireProbability[k] = v
		end
	end
	if data.CAI and data.CAI.baseTempo then
		local b = data.CAI.baseTempo
		data.UpdatePeriod, data.UpdateAfterRebuildDelay, data.ConstructionPeriodMean, data.ConstructionPeriodMin = b[1], b[2], b[3], b[4]
		data.NonConstructionPeriodMean, data.NonConstructionPeriodMin, data.RepairPeriod = b[5], b[6], b[7]
	end
	pcall(CAI_RestoreFire)
	data.CAI = nil
	data.HumanAssistOverrides = nil
	data.HeavyArmsPrioritiesOverride = nil
	data.SmallArmsPrioritiesOverride = nil
	if CAI_BaseEnableHumanAssist then CAI_BaseEnableHumanAssist() end
	Log("[CAI] T" .. tostring(teamId) .. " ASSIST FORT-9000-KI inaktiv (Hilfs-KI eines Spielers)")
end

local CAI_BaseOnWeaponFired = OnWeaponFired
function OnWeaponFired(weaponTeamId, saveName, weaponId, projectileNodeId, projectileNodeIdFrom)
	CAI_BaseOnWeaponFired(weaponTeamId, saveName, weaponId, projectileNodeId, projectileNodeIdFrom)
	local st = data.CAI
	if st == nil or CAI_Side(weaponTeamId) ~= enemyTeamId then
		return
	end
	st.shots[saveName] = (st.shots[saveName] or 0) + 1
	st.threat[saveName] = (st.threat[saveName] or 0) + Strategy.ThreatPerShot
	if Strategy.IndirectThreatTypes[saveName] then
		st.recentIndirect = st.recentIndirect + 1
	end
	if type(projectileNodeId) == "number" and projectileNodeId > 0 then
		if st.projCount > 400 then
			st.projOwner = {}
			st.projCount = 0
		end
		st.projOwner[projectileNodeId] = saveName
		st.projCount = st.projCount + 1
	end
end

local CAI_BaseOnDeviceHit = OnDeviceHit
function OnDeviceHit(deviceTeamId, deviceId, saveName, newHealth, projectileNodeId, projectileTeamId, pos, reflectedByEnemy)
	if CAI_BaseOnDeviceHit then
		CAI_BaseOnDeviceHit(deviceTeamId, deviceId, saveName, newHealth, projectileNodeId, projectileTeamId, pos, reflectedByEnemy)
	end
	local st = data.CAI
	if st == nil or CAI_Side(deviceTeamId) ~= CAI_Side(teamId) or CAI_Side(projectileTeamId) ~= enemyTeamId then
		return
	end
	local weapon = st.projOwner[projectileNodeId]
	if weapon then
		local add = Strategy.ThreatPerHit
		if saveName == "reactor" then
			add = add + Strategy.ThreatPerReactorHit
		end
		st.threat[weapon] = (st.threat[weapon] or 0) + add
	end
end

local CAI_BaseOnDeviceDestroyed = OnDeviceDestroyed
function OnDeviceDestroyed(deviceTeamId, deviceId, saveName, nodeA, nodeB, t)
	CAI_BaseOnDeviceDestroyed(deviceTeamId, deviceId, saveName, nodeA, nodeB, t)
	local st = data.CAI
	if st == nil then
		return
	end
	if CAI_Side(deviceTeamId) == CAI_Side(teamId) then
		st.lost[saveName] = (st.lost[saveName] or 0) + 1
	elseif CAI_Side(deviceTeamId) == enemyTeamId then
		st.kills[saveName] = (st.kills[saveName] or 0) + 1
		-- eine zerstoerte Waffe bedroht uns nicht mehr so stark
		if st.threat[saveName] then
			st.threat[saveName] = st.threat[saveName] * 0.7
		end
	end
end

local CAI_BaseOnGameResult = OnGameResult
function OnGameResult(winningTeamId)
	if CAI_BaseOnGameResult then
		CAI_BaseOnGameResult(winningTeamId)
	end
	local st = data.CAI
	if st == nil then
		return
	end
	local function Dump(t)
		local keys = {}
		for k in pairs(t) do keys[#keys + 1] = k end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do parts[#parts + 1] = k .. ":" .. t[k] end
		return table.concat(parts, ",")
	end
	CAI_Log("END winner=" .. tostring(winningTeamId) .. " kills=" .. Dump(st.kills) .. " lost=" .. Dump(st.lost) .. " enemyShots=" .. Dump(st.shots))
end
