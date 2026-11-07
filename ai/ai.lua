-- FORT 9000 - extends the built-in Forts AI (data/ai/ai.lua).
-- Forts runs this file AFTER the built-in AI, so we can extend its functions and tables here.
-- Building, aiming and repairing stay as they are; new are:
--   1. Adaptive target selection: the priority lists are continuously re-sorted by
--      base value (Strategy.TargetValue) + threat (who is shooting and hitting us right now?)
--   2. Aggression by game phase and economy
--   3. Anti-air that ramps up under heavy mortar/missile fire
-- All decisions are written to the log with [CAI].
-- Important: use deterministic values only (no wall-clock time, no math.random),
-- otherwise replays and multiplayer desync.

--------------------------------------------------------------------------------
-- Load strategy (dofile is only allowed here, during initialisation)

-- Logging: on in the dev mod, off in the published mod (publish.py flips the LOGGING marker). Ctrl+Shift+L in a match
-- switches it (OnKey in script.lua sends the event below). Only the local log depends on it, never the game state, so
-- players may differ without a desync. Keep calls to CAI_Log as they are: some arguments do real work.
CAI_Logging = --[[LOGGING]] true

function Fort9000SetLogging(on, clientIndex)
	if clientIndex == nil or clientIndex == GetLocalClientIndex() then CAI_Logging = on end
end

-- The mod's own folder: the first of these that holds ai/strategy.lua. A Workshop subscriber has the mod only
-- as mods/<PublishedFileId>/, so publish.py puts that folder in front at the WORKSHOP marker. Every player must
-- load the same files, otherwise the AI state differs and multiplayer desyncs (Vanilla 2v2, 28.10.2026: the host
-- loaded the plans from mods/fort9000/, the subscriber found none and skipped the "CAI plan" random draw).
local CAI_ModDirs = { --[[WORKSHOP]] "mods/fort9000dev/" }
if type(path) == "string" then
	table.insert(CAI_ModDirs, 1, string.gsub(path, "[/\\]*$", "") .. "/")
end
CAI_ModDir = CAI_ModDirs[#CAI_ModDirs]
Strategy = nil
for _, d in ipairs(CAI_ModDirs) do
	if Strategy == nil then
		pcall(dofile, d .. "ai/strategy.lua")
		if Strategy ~= nil then CAI_ModDir = d end
	end
end

local CAI_Defaults =
{
	Version = 0, TrainedGames = 0, ThinkInterval = 5,
	ThreatWeight = 30, ThreatHalf = 10, ThreatDecay = 0.85, ThreatPerShot = 1, ThreatPerHit = 3, ThreatPerReactorHit = 6,
	EarlySeconds = 120, LateSeconds = 480,
	Aggression = { Early = 0.85, Mid = 1.0, Late = 1.2 },
	AggressionExclude = { machinegun = true },
	RichMetal = 1500, RichBoost = 1.15, PoorMetal = 150, PoorEnergy = 300, PoorFactor = 0.75,
	IndirectThreatTypes = { mortar = true, mortar2 = true, missile = true, missileinv = true, missile2 = true, missile2inv = true },
	AntiAirThreatShots = 6, AntiAirBoostMax = 1.4,
	RebuildGiveUpSeconds = 120,
	BuildSkipSeconds = 90, BuildSkipMinMetal = 300, StarvedFlatTicks = 4,
	-- RebuildCap: a device of these types lost more than Max[type] times in a row at one plan action (each loss
	-- within Window seconds of the one before) is not rebuilt again (Vanilla-5, 25.10.2026: one machine gun
	-- rebuilt ten times under mortar fire; Vanilla-5, 26.10.2026: a smoke launcher on an open roof five times)
	RebuildCap = { Window = 180, Max = { machinegun = 3, minigun = 3, smokebomb = 3 } },
	-- Socket (Bastion, plans with FortSockets): a socket whose weapon is lost SwapAfter times, each loss within Window
	-- seconds of the one before, gets the next of its Loadouts whose tech stands instead of the same weapon again
	-- Upgrade: a socket with Upgrade loadouts (FortSockets) whose weapon is one of From and alive is sold and rebuilt
	-- with the first upgrade whose tech stands (the posture's Prefer first) once the AI has held Metal and Energy for
	-- Seconds; one socket at a time (Rank order), Hold seconds apart (Vanilla-8 test 3, 03.11.2026: the plan ran out
	-- at ~565 s, both sides sat at 900 metal / 9000 energy behind two snipers each and no laser came)
	Socket = { SwapAfter = 2, Window = 180,
		-- WantWait: the first weapon of the socket's order is ready but not yet paid for: up to so many seconds it waits for
		-- the money instead of buying a cheaper one (the player, test 9: always the 20mm, never a cannon)
		Upgrade = { Metal = 450, Energy = 3000, Seconds = 15, Hold = 60, Timeout = 60, AtHand = 0.8, WantWait = 120, HeavyWait = 300, RefusedWait = 30, ParkFor = 300, CapSeconds = 60, CapShare = 0.95,
			From = { sniper = true, sniper2 = true, machinegun = true } },
		-- Refill: a socket with Upgrade loadouts empty for RefillAfter seconds with no rebuild queued (the built-in AI
		-- gave up, Vanilla-8 test 5: B2 empty for 450 s at 1200 metal) is queued again, RefillEvery seconds apart,
		-- each time with the next ready weapon (a refused one may fit where another did not)
		RefillAfter = 45, RefillEvery = 130 },
	-- SniperSight (plans with FortSockets): snipers fire only at a device they can really hit (test 5, the player: they
	-- fired all match at targets behind closed doors). Hitpoints: what the ray may pass, the AP sniper's
	-- PenetrationDamage (one door of 400, not two; the built-in value 810 passes two). AimUp: points tested above
	-- a device's centre, since a weapon's door is often cut to its barrel height
	-- Near: the ray must end this close to the point aimed at; any other device on the way (sandbags, test 6) is no target
	SniperSight = { Enabled = true, Hitpoints = { sniper = 0, sniper2 = 600 }, AimUp = { 0, 15, 30 }, Near = 60 },
	-- Buzzsaw (all plans; the player, 07.11.2026): a single-use weapon, three volleys of three blades, then it destroys
	-- itself (no blast). Its blades do x18.75 on bracing, x12.5 on background bracing and about nothing on anything else
	-- (measured in the game). Sight: it fires only when a ray from it towards an enemy device of Targets first hits enemy
	-- Wood within Near of the point aimed at (the device's platform point, its support, or its centre), else at enemy wood
	-- within Far of it; otherwise it holds (no fallback to the built-in search). Rebuild: a lost buzzsaw is rebuilt at most
	-- Rearm times per plan action, and with RearmNoTech not once a plant for heavy weapons stands (Bastion: the socket goes
	-- to the heavy weapon); it never counts as a socket loss or for the rebuild cap. Volleys: a loss after that many is a
	-- self-destruct (log only)
	Buzzsaw = { Enabled = true, Types = { buzzsaw = true }, Volleys = 3, Rearm = 1, RearmNoTech = true, Near = 60, Far = 250,
		Wood = { bracing = true, backbracing = true, rope = true },
		Targets = { "turbine2", "turbine", "battery", "store", "reactor", "munitions", "factory", "upgrade", "armoury", "workshop",
			"cannon", "laser", "firebeam", "cannon20mm", "sniper2", "sniper", "mortar2", "mortar", "rocket", "rocketemp",
			"missile2", "missile", "missile2inv", "missileinv", "minigun", "machinegun", "flak", "shotgun", "smokebomb",
			"mine2", "mine" } },
	-- FrontStrip (plans with FortStrip, the player 04.11.2026): while metal is below Below in the first Until seconds, the
	-- armour struts of the list become wood (armour reclaims 0.9 per unit of length, wood costs 0.1);
	-- once metal is at RestoreAbove after that, they become armour again, one per think step. Once per strut: a round
	-- trip loses metal
	-- RestoreHeavy: not before that many heavy weapons stand (the metal goes to them first; test 10: restored at 580-765 s,
	-- 580 metal, while they waited for metal; test 7: restored at 285-385 s, 600 metal, while the
	-- munitions plant waited)
	FrontStrip = { Enabled = true, Below = 150, Until = 300, RestoreAbove = 800, RestoreHeavy = 2 },
	-- BuildEnergyHold: these weapons hold fire while the plan's next device is short of energy only, so shots cannot starve the
	-- fort's building (2v6-3, match 07.11.2026: EMP rockets at 800 a shot, the upgrade centre's 3000 never saved up, no turbine
	-- planned before it: build stood at 188 of 342 for 340 s with metal at its cap). MaxHold, then Free seconds of fire
	BuildEnergyHold = { Enabled = true, Types = { rocket = true, rocketemp = true }, MaxHold = 90, Free = 30 },
	-- SocketVolley (plans with FortSockets, instead of Fire.Volley; the player, test 7): the heavy weapons fire together at
	-- one spot. MaxHold: seconds a ready weapon waits for the others and for the energy; then as many as can be paid fire
	-- together. While the group waits only for energy, other offensive weapons but the sniper hold fire (SaveEnergy).
	-- EnergyShot: what a shot costs (laser 5000, 2 cost more than the 9000 of three batteries, test 7): a module with
	-- Trigger Storage fires when the weapons' sum and Margin exceed the storage (3000 + Battery per battery)
	-- Classes, Gap (the player, test 8): a beam burns the shells in its way, so beams fire together and guns fire together,
	-- and one class waits Gap seconds after the other has fired
	SocketVolley = { Enabled = true, FirstShot = true, Types = { firebeam = true, laser = true, cannon20mm = true, cannon = true }, MaxHold = 90,
		Classes = { firebeam = "beam", laser = "beam", cannon20mm = "gun", cannon = "gun" }, Gap = 6,
		SaveEnergy = true, EnergyShot = { firebeam = 1500, laser = 5000, cannon20mm = 2000, cannon = 2000 }, Margin = 1000,
		BaseStorage = 3000, Battery = 2000, BaseMetal = 600, Store = 300 },
	-- RebuildHold (plans with FortSockets): while a lost heavy weapon is queued, these wait, so the metal adds up to its price
	-- (test 21: 1134 metal at 1000 s, 54 at 1050 s, never 900 again in 590 s, while 10 mortars, 7 turbine upgrades and 5 snipers went up).
	-- Struts, turbines, mines, stores, batteries and the plants go on: the weapon needs them. After MaxSeconds they get FreeSeconds,
	-- in case the metal never comes.
	RebuildHold = { Types = { mortar = true, mortar2 = true, sniper = true, sniper2 = true, machinegun = true, minigun = true,
		turbine2 = true, mine2 = true, upgrade = true }, MaxSeconds = 180, FreeSeconds = 45 },
	-- CombatLog (plans with FortSockets): every Every seconds COMBAT (reactors, sniper sight counts, shots) and DEALT
	-- (own hits by weapon on devices and struts, and at which height of the enemy fort)
	CombatLog = { Every = 60, TopY = 75, LowY = 300 },
	-- Zone (Bastion, plans with FortZones): damage per zone from enemy hits on own struts (OnLinkHit) and own struts
	-- lost (BreakDamage each, also beams and splash, which OnLinkHit does not see); Decay per think step for the logged
	-- pressure; zone modules fire on the undecayed sum since they last went in
	Zone = { BreakDamage = 100, Decay = 0.9, LogEvery = 30 },
	-- Posture (Bastion, plans with FortSockets): every think step a score per posture from the enemy's devices, the
	-- threat of their weapons, the zone pressure and the economy; the best one is taken when it beats the current one
	-- by Switch and the current one has held MinHold seconds. A posture boosts target values (Boost), picks the
	-- socket loadouts tried first after repeated losses (Prefer) and triggers modules (Trigger Postures)
	Posture = { MinHold = 30, Switch = 1.25, Base = 3, DeviceWeight = 2, SiegeScale = 50, PunishRich = 4,
		Threats = {
			AntiArtillery = { mortar = true, mortar2 = true },
			AntiSniper = { sniper2 = true, laser = true, firebeam = true },
			AntiAir = { missile = true, missile2 = true, missileinv = true, missile2inv = true, rocket = true, rocketemp = true },
		},
		Eco = { mine = true, mine2 = true, turbine = true, turbine2 = true, battery = true, store = true, solar = true },
		Weapons = { machinegun = true, minigun = true, sniper = true, sniper2 = true, mortar = true, mortar2 = true,
			cannon = true, cannon20mm = true, laser = true, firebeam = true, flak = true, shotgun = true, rocket = true,
			rocketemp = true, missile = true, missile2 = true, missileinv = true, missile2inv = true, buzzsaw = true,
			smokebomb = true, smokebomb2 = true },
		Boost = {
			Pressure = { sniper = 1.2, machinegun = 1.1, mine = 1.2, turbine = 1.2 },
			AntiArtillery = { mortar = 2.0, mortar2 = 2.0 },
			AntiSniper = { sniper2 = 2.0, sniper = 1.5, laser = 1.8, firebeam = 1.8 },
			AntiAir = { missile = 1.4, missile2 = 1.4, missileinv = 1.4, missile2inv = 1.4, rocket = 1.4, rocketemp = 1.4 },
			Siege = { cannon = 1.3, cannon20mm = 1.3, laser = 1.3, firebeam = 1.3, mortar2 = 1.2, buzzsaw = 1.3 },
			Punish = { mine = 1.4, mine2 = 1.4, turbine = 1.4, turbine2 = 1.4, battery = 1.3, store = 1.2 },
		},
		Prefer = {
			AntiAir = { direct = { "machinegun" } },
			AntiSniper = { direct = { "sniper" } },
			Siege = { direct = { "cannon", "laser", "cannon20mm", "firebeam" } },
			Punish = { direct = { "cannon", "laser", "cannon20mm", "firebeam" } },
		} },
	-- NoOffence: weapon types that never fire at the enemy fort (machine guns do little damage there; they stay
	-- anti-air), their turns in the fire control go to the other weapons (snipers)
	-- SmokeCover: while the team has a smoke launcher, rockets only fire from MinDelay to Window seconds after one
	-- of its smoke shells was fired (the enemy anti-air does not see them in the smoke); a ready launcher fires
	-- first when a rocket is ready; after MaxHold seconds without smoke the rockets fire anyway
	Fire = { Enabled = true, Interval = 1.0, WeaponsPerTick = 3, AlwaysOffensive = true, RebuildFireFactor = 2.5,
		NoOffence = { machinegun = true },
		-- AntiAirFirst: anti-air weapons that may also fire at the enemy fort (flak, its upgrade the shotgun) do so only
		-- while the enemy has none of the Threats they should shoot down (mortar shells, missiles, rockets)
		AntiAirFirst = { Types = { flak = true, shotgun = true },
			Threats = { mortar = true, mortar2 = true, missile = true, missile2 = true, missileinv = true, missile2inv = true,
				rocket = true, rocketemp = true } },
		SmokeCover = { Enabled = true, Smoke = { smokebomb = true, smokebomb2 = true }, Rockets = { rocket = true, rocketemp = true },
			MinDelay = 2, Window = 10, MaxHold = 30 },
		-- Volley: weapons of these types fire together as one group at the same spot (two beams cut what one only
		-- burns); a ready one waits for the others, after MaxHold seconds it fires alone
		Volley = { Enabled = true, Types = { firebeam = true }, MaxHold = 20 } },
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
-- Custom build plans from the mod folder (<CAI_ModDir>fortplans/<map>/)
-- Forts removes foreign files from data/maps, which is why the plans live in the mod.
--
-- Flow:
--  1. During initialisation (the only place where dofile is allowed) all custom plans and the
--     original plans of the maps are preloaded. At this point the AI knows neither its team nor the map.
--  2. Later the game calls OffsetFort/MirrorFort (adapt the plan to the real fort) and
--     Load. On the first of these calls we swap: identify the map from the game's plan,
--     choose a custom plan, shift it into the game plan's coordinates, insert it.
--     The game then applies its own offset/mirroring to our plan.

CAI_Plan = { maps = {}, done = false, notes = {} }

local function CAI_PlanNote(msg)
	if CAI_Logging then Log("[CAI] T" .. tostring(teamId) .. " " .. msg) end
end

-- Direct access to the plan variables (rawget/rawset do not exist in Forts)
local function CAI_GetPlanGlobals()
	return { Fort = Fort, FortTeam = FortTeam, FortId = FortId, FortPos = FortPos,
		FortTableStartLine = FortTableStartLine, FortTableCommentLines = FortTableCommentLines, FortModules = FortModules,
		FortRetire = FortRetire, FortSockets = FortSockets, FortZones = FortZones, FortStrip = FortStrip }
end

local function CAI_SetPlanGlobals(t)
	Fort = t.Fort
	FortTeam = t.FortTeam
	FortId = t.FortId
	FortPos = t.FortPos
	FortTableStartLine = t.FortTableStartLine
	FortTableCommentLines = t.FortTableCommentLines
	FortModules = t.FortModules
	FortRetire = t.FortRetire
	FortSockets = t.FortSockets
	FortStrip = t.FortStrip
	FortZones = t.FortZones
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
	return nil, (ok and "no fort" or tostring(err))
end

FortPlanConfig = nil
pcall(dofile, CAI_ModDir .. "ai/fortplans.lua")
if type(FortPlanConfig) ~= "table" then FortPlanConfig = {} end

local function CAI_PreloadPlans()
	local summary = {}
	for mapName, m in pairs(FortPlanConfig.Maps or {}) do
		local entry = { sigs = {}, plans = {}, list = m.Plans or {}, reactors = m.ReactorsPerSide, positions = m.FortPositions }
		for _, f in ipairs(m.Originals or {}) do
			-- entries with a folder are full paths (e.g. plans of other mods), others are relative to OriginalsDir
			local path = string.find(f, "/", 1, true) and f or ((m.OriginalsDir or ("maps/" .. mapName .. "/")) .. f)
			local t = CAI_LoadPlanFile(path)
			if t then
				table.insert(entry.sigs, { file = string.match(f, "([^/]+)$"), x = t.FortPos.x, y = t.FortPos.y, n = #t.Fort })
			end
		end
		local count = 0
		for _, f in ipairs(entry.list) do
			if f ~= "original" then
				local t, err = CAI_LoadPlanFile(CAI_ModDir .. "fortplans/" .. mapName .. "/" .. f)
				if t then
					entry.plans[f] = t
					count = count + 1
				else
					Log("[CAI] PLAN-LOAD-ERROR " .. mapName .. "/" .. f .. ": " .. tostring(err))
				end
			end
		end
		CAI_Plan.maps[mapName] = entry
		table.insert(summary, mapName .. ":" .. count .. "/" .. #entry.sigs)
	end
	if CAI_Logging then Log("[CAI] PLAN-PRELOAD " .. table.concat(summary, " ") .. " (custom/original)") end
end

local okPre, errPre = pcall(CAI_PreloadPlans)
if not okPre then
	Log("[CAI] PLAN-PRELOAD ERROR " .. tostring(errPre))
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

local function CAI_AtPosition(positions, real)
	for _, p in ipairs(positions) do
		if math.abs(p.x - real.x) < 50 and math.abs(p.y - real.y) < 50 then return true end
	end
	return false
end

-- real: where the fort really stands (the game plan's FortPos after OffsetFort/MirrorFort), nil when unknown
local function CAI_IdentifyMap(engineFort, E, real)
	if type(GetMapFilename) == "function" then
		local ok, f = pcall(GetMapFilename)
		if ok and type(f) == "string" then
			local name = string.match(f, "maps[/\\]([^/\\]+)")
			if name and CAI_Plan.maps[name] then
				return name, "filename", nil
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
	-- maps sharing the game's plans (2v6 Vanilla uses the Vanilla plans) are told apart by where the fort stands: an
	-- entry with FortPositions counts only at one of them and then wins over entries without
	local placed, others = {}, {}
	for _, c in ipairs(cands) do
		if c.entry.positions then
			if real and CAI_AtPosition(c.entry.positions, real) then table.insert(placed, c) end
		else
			table.insert(others, c)
		end
	end
	cands = #placed > 0 and placed or others
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
	-- several original plans of the same map with the same signature (e.g. Vanilla Template-1/-2) are unambiguous
	local sameMap = #cands > 0
	for _, c in ipairs(cands) do
		if c.name ~= cands[1].name then sameMap = false end
	end
	if sameMap then
		return cands[1].name, "signature", cands[1].file
	end
	return nil, (#cands == 0 and "unknown-game-plan" or "ambiguous")
end

local function CAI_ChoosePlan(entry, mapName)
	local forced = FortPlanConfig.Force and FortPlanConfig.Force[mapName]
	if forced then return forced, "forced" end
	local n = #entry.list
	if n == 0 then return "original", "empty" end
	local idx = nil
	if type(GetRandomInteger) == "function" then
		local ok, r = pcall(GetRandomInteger, 1, n, "CAI plan " .. tostring(teamId))
		if ok and type(r) == "number" and r >= 1 and r <= n then idx = r end
	end
	if idx == nil then
		return entry.list[1 + (math.floor(type(teamId) == "number" and teamId or 0) % n)], "teamId"
	end
	return entry.list[idx], "random"
end

-- Map-specific settings: FortPlanConfig.Maps[<map>].Strategy overrides values of the
-- strategy file (tables are merged, e.g. only Tempo.UpdatePeriod).
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
		CAI_PlanNote("MAP-STRATEGY " .. mapName .. ": " .. table.concat(keys, ","))
	end
end

-- realOf(E): where the game will put the plan's FortPos E (from the OffsetFort/MirrorFort arguments), nil at Load
function CAI_TrySwapPlan(where, realOf)
	if CAI_Plan.done then return end
	CAI_Plan.done = true
	local engineFort, E = Fort, FortPos
	if type(engineFort) ~= "table" or #engineFort == 0 or type(E) ~= "table" then
		CAI_PlanNote("PLAN file=original reason=no-game-plan at=" .. where)
		return
	end
	local real = realOf and realOf(E)
	local mapName, how, engineFile = CAI_IdentifyMap(engineFort, E, real)
	if not mapName then
		CAI_PlanNote("PLAN file=original reason=" .. tostring(how) .. " at=" .. where)
		return
	end
	local entry = CAI_Plan.maps[mapName]
	pcall(CAI_ApplyMapStrategy, mapName)
	local choice, why = CAI_ChoosePlan(entry, mapName)
	local ours = entry.plans[choice]
	if choice == "original" or ours == nil then
		CAI_PlanNote("PLAN map=" .. mapName .. " file=" .. (engineFile or "original") .. " reason=" .. why
			.. (ours == nil and choice ~= "original" and " (own plan missing)" or "") .. " at=" .. where)
		return
	end
	pcall(CAI_MapZones, ours)
	-- shift into the coordinates of the game's plan
	local dx, dy = E.x - ours.FortPos.x, E.y - ours.FortPos.y
	local function Shift(p)
		if p then p.x = p.x + dx; p.y = p.y + dy end
	end
	for k, a in ipairs(ours.Fort) do
		Shift(a.PosA); Shift(a.PosB); Shift(a.NewNodePos); Shift(a.GroundPosition)
		a.CAI_K = k   -- plan action number, for the modules' Requires
	end
	-- reactive build modules: appended so the game's transform renumbers and moves them with the plan,
	-- cut out again after Load (CAI_ExtractModules)
	local nMod = 0
	for i, m in ipairs(type(ours.FortModules) == "table" and ours.FortModules or {}) do
		for _, a in ipairs(m.Actions or {}) do
			Shift(a.PosA); Shift(a.PosB); Shift(a.NewNodePos); Shift(a.GroundPosition)
			a.CAI_Module = i
			table.insert(ours.Fort, a)
			nMod = nMod + 1
		end
	end
	CAI_Plan.modules = ours.FortModules
	CAI_Plan.retire = type(ours.FortRetire) == "table" and ours.FortRetire or nil
	CAI_Plan.sockets = type(ours.FortSockets) == "table" and ours.FortSockets or nil
	CAI_Plan.strip = type(ours.FortStrip) == "table" and ours.FortStrip or nil
	-- where the strip's plan positions really stand (2v6: the fort is not where its plan was recorded); nil at Load: unmoved
	CAI_Plan.stripFrame = real and { plan = { x = ours.FortPos.x, y = ours.FortPos.y }, real = real, mirrored = where == "MirrorFort" } or nil
	CAI_Plan.zones = type(ours.FortZones) == "table" and ours.FortZones or nil
	CAI_SetPlanGlobals({
		Fort = ours.Fort,
		FortTeam = ours.FortTeam or FortTeam,
		FortId = ours.FortId or FortId,
		FortPos = { x = E.x, y = E.y },
	})
	CAI_PlanNote("PLAN map=" .. mapName .. " file=" .. choice .. " actions=" .. (#ours.Fort - nMod) .. " instead=" .. tostring(engineFile)
		.. " choice=" .. why .. " detected=" .. how .. " at=" .. where .. " shift=" .. math.floor(dx + 0.5) .. "," .. math.floor(dy + 0.5)
		.. (real and (" fort=" .. math.floor(real.x + 0.5) .. "," .. math.floor(real.y + 0.5)) or ""))
	if CAI_Plan.retire then
		local items = {}
		for k, v in pairs(CAI_Plan.retire) do items[#items + 1] = tostring(k) .. ":" .. tostring(v) end
		table.sort(items)
		CAI_PlanNote("RETIRE-CONFIG " .. table.concat(items, ","))
	end
end

local CAI_BaseOffsetFort = OffsetFort
function OffsetFort(offset, structureId)
	local ok, err = pcall(CAI_TrySwapPlan, "OffsetFort", function(E)
		if type(offset) == "table" and offset.x and offset.y then return { x = E.x + offset.x, y = E.y + offset.y } end
	end)
	if not ok then Log("[CAI] PLAN-ERROR " .. tostring(err)) end
	CAI_PlanNote("TRANSFORM OffsetFort " .. tostring(offset and offset.x) .. "," .. tostring(offset and offset.y))
	return CAI_BaseOffsetFort(offset, structureId)
end

local CAI_BaseMirrorFort = MirrorFort
function MirrorFort(pivot, offset, structureId)
	-- the game mirrors x about the pivot, then adds the offset (Vanilla team 2: pivot 0, offset -3950,3300 moves
	-- weapon_pack's ToGAF1 FortPos (-6850,-2600) to (2900,700))
	local ok, err = pcall(CAI_TrySwapPlan, "MirrorFort", function(E)
		if type(offset) == "table" and offset.x and offset.y then
			return { x = 2 * (tonumber(pivot) or 0) - E.x + offset.x, y = E.y + offset.y }
		end
	end)
	if not ok then Log("[CAI] PLAN-ERROR " .. tostring(err)) end
	CAI_PlanNote("TRANSFORM MirrorFort pivot=" .. tostring(pivot) .. " " .. tostring(offset and offset.x) .. "," .. tostring(offset and offset.y))
	CAI_FortMirrored = true       -- SHAPE diagnostics report offsets in the plan's own frame
	return CAI_BaseMirrorFort(pivot, offset, structureId)
end

--------------------------------------------------------------------------------
-- Helper functions

function CAI_Log(msg)
	if CAI_Logging then
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
-- Build tempo: the built-in AI performs only ONE build action per pass (data.UpdatePeriod)
-- and inserts long pauses (NonConstructionPeriod) between build phases (ConstructionPeriod).

function CAI_ApplyTempo()
	local t = Strategy.Tempo
	if type(t) ~= "table" then return "off" end
	if data.CAI then
		data.CAI.baseTempo = { data.UpdatePeriod, data.UpdateAfterRebuildDelay, data.ConstructionPeriodMean, data.ConstructionPeriodMin,
			data.NonConstructionPeriodMean, data.NonConstructionPeriodMin, data.RepairPeriod }
	end
	if t.UpdatePeriod then data.UpdatePeriod = t.UpdatePeriod end
	-- Update period and repair time by difficulty: easy (0) / normal (0.5) / hard (1), linear in between
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
	return "difficulty=" .. tostring(data.difficulty) .. " period=" .. tostring(data.UpdatePeriod) .. "s build=" .. tostring(data.ConstructionPeriodMean)
		.. "s pause=" .. tostring(data.NonConstructionPeriodMean) .. "s repair=" .. tostring(data.RepairPeriod) .. "s"
end

--------------------------------------------------------------------------------
-- Fire control: the built-in AI only fires during build pauses and at most one weapon per
-- pass; while building it also holds back. Here: always ready to attack, more fire while
-- building, and a separate timer that fires several ready weapons per second.
-- TryFireGun itself checks readiness, doors, groups and target.

function CAI_ApplyFire()
	local f = Strategy.Fire
	if type(f) ~= "table" or not f.Enabled then return "off" end
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
	-- no offensive fire for NoOffence types (anti-air is separate: AntiAirFireProbability)
	-- a copy: AntiAirFirst adds and removes types during the match (CAI_UpdateAntiAirFirst)
	local no = {}
	for k, v in pairs(f.NoOffence or CAI_Defaults.Fire.NoOffence or {}) do no[k] = v end
	data.CAI.noOffence = no
	local noList = {}
	for k in pairs(no) do
		if data.OffensiveFireProbability[k] ~= nil then data.OffensiveFireProbability[k] = 0 end
		if type(data.FireDuringRebuildProbability) == "table" and data.FireDuringRebuildProbability[k] ~= nil then
			data.FireDuringRebuildProbability[k] = 0
		end
		noList[#noList + 1] = k
	end
	table.sort(noList)
	data.CAI.firePtr = 0
	data.CAI.fireAttempts = 0
	-- game seconds counted by the fire timer (deterministic), last own smoke shell, rockets held since
	data.CAI.fireClock = 0
	data.CAI.lastSmoke = nil
	data.CAI.rocketHoldSince = nil
	data.CAI.smokeCover = f.SmokeCover or CAI_Defaults.Fire.SmokeCover
	data.CAI.volley = (CAI_Plan.sockets and CAI_Defaults.SocketVolley) or f.Volley or CAI_Defaults.Fire.Volley
	data.CAI.volleyHoldSince = nil
	if ScheduledCallCountOfFunc(CAI_FireTick) == 0 then
		ScheduleCall(f.Interval or 1, CAI_FireTick)
	end
	return "period=" .. tostring(f.Interval) .. "s weapons=" .. tostring(f.WeaponsPerTick) .. " always=" .. tostring(f.AlwaysOffensive)
		.. " duringRebuild=x" .. tostring(f.RebuildFireFactor) .. " noOffence=" .. table.concat(noList, ",")
		.. " smokeCover=" .. tostring(data.CAI.smokeCover and data.CAI.smokeCover.Enabled or false)
		.. " volley=" .. tostring(data.CAI.volley and data.CAI.volley.Enabled or false)
end

-- Smoke before rockets (Fire.SmokeCover)
local function CAI_WeaponsOf(kinds)
	local out = {}
	if type(GetDeviceType) ~= "function" then return out end
	for i = 0, (GetWeaponCount(teamId) or 0) - 1 do
		local id = GetWeaponId(teamId, i)
		if id and id > 0 and not IsDummy(id) and kinds[GetDeviceType(id)] then
			out[#out + 1] = id
		end
	end
	return out
end

local function CAI_Ready(id)
	return IsAIDeviceAvailable(id) and IsWeaponReadyToFire(id) and (data.ActionQueue == nil or data.ActionQueue[id] == nil)
end

-- true if a rocket may fire now: no smoke launcher, smoke shell in the air long enough, or held too long
function CAI_RocketsMayFire()
	local st = data.CAI
	local sc = st and st.smokeCover
	if not sc or not sc.Enabled or st.fireClock == nil or data.HumanAssist then return true end
	local since = st.lastSmoke and (st.fireClock - st.lastSmoke)
	if since and since >= sc.MinDelay and since <= sc.Window then return true end
	if st.rocketRelease == st.fireClock then return true end   -- released after MaxHold, until the next tick
	if #CAI_WeaponsOf(sc.Smoke) == 0 then return true end
	if st.rocketHoldSince == nil then st.rocketHoldSince = st.fireClock end
	if st.fireClock - st.rocketHoldSince >= sc.MaxHold then
		CAI_Log("SMOKE_TIMEOUT rockets fire without smoke after " .. (st.fireClock - st.rocketHoldSince) .. "s")
		st.rocketHoldSince = nil               -- the next rocket waits again
		st.rocketRelease = st.fireClock
		return true
	end
	return false
end

-- true if the team can pay for the smoke shell and every ready rocket together (GetWeaponFireCost / CanAfford, as
-- the built-in AI's SelectWeaponGroup checks a group); true where the game functions are missing (tests)
local function CAI_CanAffordSmokeAndRockets(sid, rockets)
	if type(GetWeaponFireCost) ~= "function" or type(CanAfford) ~= "function" then return true end
	local total = GetWeaponFireCost(sid)
	for _, rid in ipairs(rockets) do total = total + GetWeaponFireCost(rid) end
	return CanAfford(GetTeamResources(teamId) - total)
end

-- a rocket is ready and waits for smoke: fire a ready smoke launcher (not if a shell is already on its way), but only
-- if a rocket can fire right after it: at least one rocket ready, and energy for the smoke and the ready rockets
-- together (a smoke shell the rockets cannot follow is wasted energy). Otherwise the rockets keep waiting (MaxHold).
-- Log once per change: SMOKE_WAIT energy | SMOKE_WAIT off
function CAI_FireSmokeFirst()
	local st = data.CAI
	local sc = st.smokeCover
	if st.lastSmoke and st.fireClock - st.lastSmoke < sc.MinDelay then return false end
	local rockets = {}
	for _, rid in ipairs(CAI_WeaponsOf(sc.Rockets)) do
		if CAI_Ready(rid) then rockets[#rockets + 1] = rid end
	end
	if #rockets == 0 then return false end
	for _, sid in ipairs(CAI_WeaponsOf(sc.Smoke)) do
		if CAI_Ready(sid) then
			local ok, afford = pcall(CAI_CanAffordSmokeAndRockets, sid, rockets)
			if ok and not afford then
				if not st.smokeWaitEnergy then
					st.smokeWaitEnergy = true
					CAI_Log("SMOKE_WAIT energy rockets=" .. #rockets)
				end
				return false
			end
			if st.smokeWaitEnergy then
				st.smokeWaitEnergy = nil
				CAI_Log("SMOKE_WAIT off")
			end
			st.fireAttempts = st.fireAttempts + 1
			st.smokeFiring = true
			st.smokeTried = sid
			local okF, errF = pcall(TryFireGun, sid)
			st.smokeFiring = nil
			if not okF then CAI_Log("ERROR smoke: " .. tostring(errF)) end
			return true
		end
	end
	return false
end

-- the built-in AI fires weapons itself too: rockets are held here until the smoke covers them
local CAI_BaseTryFireGun = TryFireGun

-- Volleys (Fire.Volley): weapons of these types fire together, as one group, at the same spot. The built-in AI
-- fires a group (TryFireGun with useGroup) at the leader's target, so two firebeams cut the same struts (a player's
-- laser and firebeam fired together cut two woodspam layers and the starting fort's front in seconds, Vanilla
-- 25.10.2026); weapon_pack gives firebeams no grouping affinity to each other, so the built-in AI fires them alone.
-- A ready weapon waits until every fully built weapon of the volley types is ready and the team can pay for all
-- their shots; after MaxHold seconds (fire clock) it fires alone. With only one such weapon nothing changes. A volley
-- skips the built-in AI's random fire chance (as its own group members do).
--   VOLLEY <n> leader=<id> ids=<id,...> fired=<k>   a volley tried; fired = members no longer ready afterwards
--                                             (0: the leader found no target, or doors are opening and the built-in
--                                             AI retries the group; Abyss-3 test 2: 16 volleys, about 5 beam shots)
--   VOLLEY_HOLD ready=<n>/<m> energy=<0|1>    once when the wait starts or its reason changes
--   VOLLEY_TIMEOUT <type> <id> after=<s>s     fires alone after MaxHold
local function CAI_VolleyMembers(v)
	local out = {}
	for _, id in ipairs(CAI_WeaponsOf(v.Types)) do
		if type(IsDeviceFullyBuilt) ~= "function" or IsDeviceFullyBuilt(id) then out[#out + 1] = id end
	end
	return out
end

-- the team can pay for every shot of the group; true where the game functions are missing (tests). The costs are
-- resource vectors in the game: the sum starts from the first one (0 + vector raised "attempt to index a number
-- value" in every volley of the first Abyss-3 match, 27.10.2026)
local function CAI_CanAffordGroup(ids)
	if type(GetWeaponFireCost) ~= "function" or type(CanAfford) ~= "function" then return true end
	local total = GetWeaponFireCost(ids[1])
	for k = 2, #ids do total = total + GetWeaponFireCost(ids[k]) end
	return CanAfford(GetTeamResources(teamId) - total)
end

-- true if the shot of weapon id was handled here (fired as a volley or held); false: fire it as usual
function CAI_Volley(id)
	local st = data.CAI
	local v = st and st.volley
	if not (v and v.Enabled and type(GetDeviceType) == "function" and v.Types[GetDeviceType(id)]) then return false end
	if not CAI_Ready(id) then return false end          -- reloading or a door action pending: the built-in AI handles it
	local all = CAI_VolleyMembers(v)
	if v.Classes then
		local class = v.Classes[GetDeviceType(id)]
		if st.volleyClass and st.volleyClass ~= class and (st.fireClock or 0) - (st.volleyClassAt or -1e9) < (v.Gap or 6) then
			return true        -- the other class has just fired: its shells or beams are still in the air
		end
		local same = {}
		for _, w in ipairs(all) do
			if v.Classes[GetDeviceType(w)] == class then same[#same + 1] = w end
		end
		all = same
	end
	if #all < 2 then return false end
	local group = { id }
	for _, w in ipairs(all) do
		if w ~= id and CAI_Ready(w) then group[#group + 1] = w end
	end
	local afford = CAI_CanAffordGroup(group)
	local now = st.fireClock or 0
	if #group >= #all and afford then
		st.volleyHoldSince, st.volleyHoldWhy, st.volleySaving = nil, nil, nil
		local ids = table.concat(group, ",")
		local members = { unpack(group) }   -- the built-in AI empties the group table while it fires
		CAI_BaseTryFireGun(id, group)
		local fired = 0
		for _, w in ipairs(members) do
			if not IsWeaponReadyToFire(w) then fired = fired + 1 end
		end
		CAI_Log("VOLLEY " .. #members .. " leader=" .. id .. " ids=" .. ids .. " fired=" .. fired)
		return true
	end
	-- FirstShot: a weapon that has not fired yet does not wait for one that is reloading: the first shot decides a duel (tests 12, 15, 18; test 18: a built
	-- cannon silent for 26 s behind the 20mm's reload, then destroyed)
	if v.FirstShot and not (st.volleyFired and st.volleyFired[id]) and CAI_CanAffordGroup({ id }) then
		CAI_Log("VOLLEY_FIRST " .. GetDeviceType(id) .. " " .. id .. " ready=" .. #group .. "/" .. #all)
		return false
	end
	if st.volleyHoldSince == nil then st.volleyHoldSince = now end
	if now - st.volleyHoldSince >= (v.MaxHold or 20) then
		CAI_Log("VOLLEY_TIMEOUT " .. GetDeviceType(id) .. " " .. id .. " after=" .. (now - st.volleyHoldSince) .. "s")
		st.volleyHoldSince, st.volleyHoldWhy, st.volleySaving = nil, nil, nil
		-- as many together as can be paid (SocketVolley); one alone as usual
		if v.SaveEnergy then
			while #group > 1 and not CAI_CanAffordGroup(group) do group[#group] = nil end
			if #group > 1 then
				local ids = table.concat(group, ",")
				CAI_BaseTryFireGun(id, group)
				CAI_Log("VOLLEY_PART ids=" .. ids)
				return true
			end
		end
		return false
	end
	st.volleySaving = v.SaveEnergy and #group >= #all and not afford or nil
	local why = "ready=" .. #group .. "/" .. #all .. " energy=" .. (afford and 1 or 0)
	if st.volleyHoldWhy ~= why then
		st.volleyHoldWhy = why
		CAI_Log("VOLLEY_HOLD " .. why)
	end
	return true
end

function TryFireGun(id, useGroup)
	local hold = false
	-- the heavy weapons save up for a volley: no other offensive shots but the sniper's (30 energy)
	if useGroup == nil and data.CAI and data.CAI.volleySaving and type(GetDeviceType) == "function" then
		local t, v = GetDeviceType(id), data.CAI.volley
		if not (v and v.Types[t]) and t ~= "sniper" then return end
	end
	-- volley weapons wait for each other (also when the built-in AI picks one); a group already firing goes on
	if useGroup == nil and data.CAI and data.CAI.volley then
		local ok, res = pcall(CAI_Volley, id)
		if not ok then
			CAI_Log("ERROR volley: " .. tostring(res))
		elseif res then
			return
		end
	end
	if useGroup == nil and data.CAI and data.CAI.smokeCover then   -- a group already firing is not interrupted
		local ok, res = pcall(function()
			local sc = data.CAI.smokeCover
			if not (sc.Enabled and type(GetDeviceType) == "function") then return false end
			-- a smoke launcher fires only as cover, from CAI_FireSmokeFirst (not when the built-in AI picks it)
			if sc.Smoke[GetDeviceType(id)] then return not data.CAI.smokeFiring end
			if not sc.Rockets[GetDeviceType(id)] then return false end
			if CAI_RocketsMayFire() then
				data.CAI.rocketHoldSince = nil
				return false
			end
			CAI_FireSmokeFirst()
			return true
		end)
		if not ok then
			CAI_Log("ERROR smoke cover: " .. tostring(res))
		else
			hold = res
		end
	end
	if hold then return end
	local okB, resB = pcall(CAI_BuildHoldsFire, id)
	if not okB then
		CAI_Log("ERROR build hold: " .. tostring(resB))
	elseif resB then
		return
	end
	local res = CAI_BaseTryFireGun(id, useGroup)
	local ok, err = pcall(CAI_RetireShot, id)
	if not ok then CAI_Log("ERROR retire: " .. tostring(err)) end
	return res
end

-- Missiles (swarm, warhead): the built-in AI paints the target with a sniper (PaintTarget) and launches 5 s later
-- (LaunchMissile) with FIREFLAG_TERRAINBLOCKS, which refuses a launcher with rock between it and the target: the
-- inverted launchers of Stalactites-4 hang in the mine pocket and fire down into a portal (02.11.2026: built, never
-- fired). Launched here without the terrain test; logged:
--   PAINT <ids> painted=<0|1> spotters=<n>       a missile group asked for a target (painted: a sniper marked one)
--   MISSILE <type> <id> marked=<0|1> result=<FIRE name>   the launch
-- Portals: the built-in AI connects them with a CONNECT plan action (ConnectPortals) and logs nothing. In the
-- Stalactites-4 test (02.11.2026) only the entry portal glowed and the launch was FIRE_BLOCKED. Logged per action
-- whenever its outcome changes:
--   CONNECT action=<k> <A>-<B> to <destA>-<destB> ok=<result> dest=<A-B's destination> back=<destA-B's destination>
local CAI_BaseExecuteFortAction = ExecuteFortAction
function ExecuteFortAction(action, index)
	-- RebuildHold: skipped like an action short of resources, without frustration
	if data.CAI and data.CAI.rebuildHold and CAI_Defaults.RebuildHold.Types[action.DeviceSaveName] then return false, true end
	local r, skip = CAI_BaseExecuteFortAction(action, index)
	if action.Type == CONNECT then
		CAI_Log("CONNECT action=" .. tostring(index) .. " ok=" .. tostring(r))
		local okC, errC = pcall(function()
			local m = data.OriginalToActual
			local a, b = m[action.OriginalNodeAId], m[action.OriginalNodeBId]
			local da, db = m[action.OriginalNodeAIdDest], m[action.OriginalNodeBIdDest]
			local function dest(p, q)
				if not (p and q and IsPortal(p, q)) then return "-" end
				return tostring(GetPortalDestinationA(p, q)) .. "-" .. tostring(GetPortalDestinationB(p, q))
			end
			local msg = "CONNECT action=" .. tostring(index) .. " " .. tostring(a) .. "-" .. tostring(b) .. " to "
				.. tostring(da) .. "-" .. tostring(db) .. " ok=" .. tostring(r) .. " dest=" .. dest(a, b)
				.. " back=" .. dest(da, db)
			local seen = data.CAI and data.CAI.connectLog
			if data.CAI and not seen then seen = {}; data.CAI.connectLog = seen end
			if not seen or seen[index] ~= msg then
				if seen then seen[index] = msg end
				CAI_Log(msg)
			end
		end)
		if not okC then CAI_Log("ERROR connect: " .. tostring(errC)) end
	end
	return r, skip
end

-- MirrorFort and OffsetFort first renumber the plan's own nodes (10000+) in the order they are created
-- (MakeAINodesInSequence), but only OriginalNodeAId/BId: a CONNECT's destination ids kept the old numbers and named
-- other nodes (fourth Stalactites-4 test, 02.11.2026: entry portal 308-304 "connected" to 307-308, the exit portal
-- 310-311 stayed dark). The same renumbering, with the destinations mapped too.
function MakeAINodesInSequence()
	local oldToNew = {}
	local current = AI_NODE_START
	if not Fort then return end
	for _, action in ipairs(Fort) do
		if action.Type == CREATE_NODE then
			oldToNew[action.OriginalNodeBId] = current
			current = current + 1
		end
		if oldToNew[action.OriginalNodeAId] ~= nil then
			action.OriginalNodeAId = oldToNew[action.OriginalNodeAId]
		end
		if oldToNew[action.OriginalNodeBId] ~= nil then
			action.OriginalNodeBId = oldToNew[action.OriginalNodeBId]
		end
	end
	for _, action in ipairs(Fort) do
		if action.OriginalNodeAIdDest and oldToNew[action.OriginalNodeAIdDest] then
			action.OriginalNodeAIdDest = oldToNew[action.OriginalNodeAIdDest]
		end
		if action.OriginalNodeBIdDest and oldToNew[action.OriginalNodeBIdDest] then
			action.OriginalNodeBIdDest = oldToNew[action.OriginalNodeBIdDest]
		end
	end
end

-- Safety net: every CAI_PORTAL_EVERY seconds of the fire clock each CONNECT of the plan whose portals stand is checked
-- and, if its portal does not lead to its destination (e.g. it was rebuilt), connected again:
--   PORTAL action=<k> <A>-<B> to <destA>-<destB> dest=<now> [cp=<ConnectPortals result>|err=<message>]
local CAI_PORTAL_EVERY = 5
function CAI_PortalTick(st)
	if (st.fireClock or 0) < (st.portalNext or 0) then return end
	st.portalNext = (st.fireClock or 0) + CAI_PORTAL_EVERY
	st.portalLog = st.portalLog or {}
	local m = data.OriginalToActual or {}
	for k, action in ipairs(Fort or {}) do
		if action.Type == CONNECT then
			local a, b = m[action.OriginalNodeAId], m[action.OriginalNodeBId]
			local da, db = m[action.OriginalNodeAIdDest], m[action.OriginalNodeBIdDest]
			local msg = "PORTAL action=" .. k .. " " .. tostring(a) .. "-" .. tostring(b) .. " to " .. tostring(da) .. "-"
				.. tostring(db)
			local ok, err = pcall(function()
				if not (a and b and da and db and IsPortal(a, b) and IsPortal(da, db)) then
					msg = msg .. " dest=- (portals not standing)"
					return
				end
				local pa, pb = GetPortalDestinationA(a, b), GetPortalDestinationB(a, b)
				msg = msg .. " dest=" .. tostring(pa) .. "-" .. tostring(pb)
				if not ((pa == da and pb == db) or (pa == db and pb == da)) then
					local cp = ConnectPortals(teamId, a, b, da, db)
					msg = msg .. " cp=" .. (cp == CP_SUCCESS and "CP_SUCCESS" or tostring(cp))
				end
			end)
			if not ok then msg = msg .. " err=" .. tostring(err) end
			if st.portalLog[k] ~= msg then
				st.portalLog[k] = msg
				CAI_Log(msg)
			end
		end
	end
end

local CAI_BasePaintTarget = PaintTarget
function PaintTarget(group, paintTarget)
	local res = CAI_BasePaintTarget(group, paintTarget)
	pcall(function()
		local ids, spotters = {}, 0
		for _, id in ipairs(group) do ids[#ids + 1] = tostring(id) end
		for i = 0, GetWeaponCount(teamId) - 1 do
			if IsSpotter(GetDeviceType(GetWeaponId(teamId, i)), teamId) then spotters = spotters + 1 end
		end
		CAI_Log("PAINT " .. table.concat(ids, ",") .. " painted=" .. (data.MissileLaunching[group[1]] and 1 or 0)
			.. " spotters=" .. spotters)
	end)
	return res
end

function LaunchMissile(group, currentTarget, spotterId)
	local doorBlock = false
	for k = #group, 1, -1 do
		local id = group[k]
		if not DeviceExists(id) then
			table.remove(group, k)
			data.MissileLaunching[id] = nil
		elseif not OpenAllWeaponDoors(id, currentTarget) then
			doorBlock = true
		end
	end
	if #group > 0 then
		if doorBlock then
			ScheduleCall(data.MissileDoorFireDelay, LaunchMissile, group, currentTarget, spotterId)
			return
		end
		for k = #group, 1, -1 do
			local id = group[k]
			local kind = GetDeviceType(id)
			local marked = IsAIDeviceAvailable(id) and GetWeaponPaintTargetMarked(id)
			local result
			if marked then
				result = FireWeaponHandler(id, kind, currentTarget, 0, FIREFLAG_EXTRACLEARANCE)
				if result == FIRE_SUCCESS then
					ScheduleCall(7.9, MissileLaunchEnded, id)
					ScheduleCall(8, TryCloseWeaponDoors, id)
				else
					data.MissileLaunching[id] = nil
					TryCloseWeaponDoors(id)
				end
			else
				data.MissileLaunching[id] = nil
				TryCloseWeaponDoors(id)
			end
			CAI_Log("MISSILE " .. tostring(kind) .. " " .. id .. " marked=" .. (marked and 1 or 0)
				.. " result=" .. tostring(result and (FIRE[result] or result) or "-"))
			ClearWeaponPaintTarget(id)
		end
	end
	data.SpotterInUse[spotterId] = nil
	TryCloseWeaponDoors(spotterId)
end

function CAI_RestoreFire()
	local b = data.CAI and data.CAI.baseFire
	if not b then return end
	data.HardThreshold = b.HardThreshold
	for k, v in pairs(b.Rebuild) do
		data.FireDuringRebuildProbability[k] = v
	end
end

-- Fire diagnostics: why an offence weapon did not fire, at most one line per weapon every
-- CAI_FIREWAIT_EVERY seconds of the fire clock (at once when the reason changes):
--   FIREWAIT <type> <id> avail=<0|1> ready=<0|1> code=<FIREFAIL name|-> queue=<0|1> m=<metal> e=<energy>
--     skipped: not available, not ready to fire (code: the engine's reason) or an action (doors) pending
--   FIRETRY <type> <id> fired=<0|1> code=<FIREFAIL name|-> [ray=<hit>:<side>:<material>@<x>,<y>] m=<metal> e=<energy>
--     after TryFireGun: fired = no longer ready (reloading); fired=0: the built-in AI declined
--     (no target, chance, cost); ray = what the targeting ray towards the enemy reactor hits first, with the
--     flags of the built-in TargetObstructed (own background bracing blocks it). A hint only: it does not say why the
--     weapon declined, and a lobbed weapon's shell does not fly that line (mortars: mostly the fire chance)
CAI_FIREWAIT_EVERY = 30

local function CAI_FireCode()
	if type(GetWeaponFireFailureCode) ~= "function" then return "-" end
	local c = GetWeaponFireFailureCode()
	return tostring(type(FIREFAIL) == "table" and FIREFAIL[c] or c)
end

local function CAI_FireRay(id)
	if type(CastRayFromDevice) ~= "function" or type(GetDeviceCountSide) ~= "function" then return "" end
	local target
	for i = 0, GetDeviceCountSide(enemyTeamId) - 1 do
		local d = GetDeviceIdSide(enemyTeamId, i)
		if GetDeviceType(d) == "reactor" then target = GetDevicePosition(d) break end
	end
	if target == nil then return " ray=no-reactor" end
	local flags = RAY_EXCLUDE_CONSTRUCTION + RAY_ALLIED_BG_BLOCKS + RAY_EXCLUDE_DYNAMIC_TERRAIN   -- separate bits (no | in Lua 5.1)
	local hit = CastRayFromDevice(id, target, 0, flags, 0)
	local name = tostring(type(RAY_HIT) == "table" and RAY_HIT[hit] or hit)
	local at = GetRayHitPosition and GetRayHitPosition()
	local mat = GetRayHitMaterialSaveName and GetRayHitMaterialSaveName() or nil
	return " ray=" .. name .. ":" .. tostring(GetRayHitSideId and GetRayHitSideId() or "?") .. ":" .. tostring(mat or "-")
		.. (at and string.format("@%d,%d", math.floor(at.x), math.floor(at.y)) or "")
end

local function CAI_FireNote(st, id, kind, line, why)
	st.fireNotes = st.fireNotes or {}
	local n = st.fireNotes[id]
	local now = st.fireClock or 0
	if n and n.why == why and now - n.at < CAI_FIREWAIT_EVERY then return end
	st.fireNotes[id] = { why = why, at = now }
	local m, e = -1, -1
	local res = GetTeamResources(teamId)
	if type(res) == "table" or type(res) == "userdata" then m, e = res.metal or -1, res.energy or -1 end
	CAI_Log(line .. " m=" .. CAI_Round(m) .. " e=" .. CAI_Round(e))
end

-- Retire: a weapon of a type in the plan's FortRetire table (type -> seconds) that declines to fire for that long
-- (TryFireGun leaves it ready: no target in reach) while energy is at least CAI_RETIRE_MIN_ENERGY is sold
-- (Abyss-2's early sniper, once the enemy's weapons are hidden or destroyed). Seconds with less energy do not count
-- (the built-in AI also declines when it cannot pay a shot). A sold device is not rebuilt: the built-in AI only
-- rebuilds a deleted device it marked itself (DeviceDeleteToRebuild); its plan entry is dropped as well.
--   RETIRE <type> <id> idle=<s> shots=<n> result=<DestroyDeviceById result>
CAI_RETIRE_MIN_ENERGY = 1000

-- a shot of a retire-type weapon resets its idle time, whoever fired it: the built-in AI fires through TryFireGun
-- outside the mod's round robin (Abyss-3 test 2, 28.10.2026: a sniper firing 17 times was sold as idle)
function CAI_RetireShot(id)
	local st = data.CAI
	local cfg = CAI_Plan.retire
	if not (st and cfg and id and type(GetDeviceType) == "function") then return end
	if not cfg[GetDeviceType(id)] or IsWeaponReadyToFire(id) then return end
	st.retire = st.retire or {}
	local r = st.retire[id]
	if r == nil then
		r = { idle = 0, at = st.fireClock or 0, shots = 0 }
		st.retire[id] = r
	end
	r.shots = r.shots + 1
	r.idle = 0
	r.at = st.fireClock or 0
end

function CAI_RetireCheck(st, id, kind, fired)
	local cfg = CAI_Plan.retire
	local limit = cfg and kind and tonumber(cfg[kind])
	if not limit or type(DestroyDeviceById) ~= "function" then return end
	st.retire = st.retire or {}
	local now = st.fireClock or 0
	local r = st.retire[id]
	if r == nil then
		r = { idle = 0, at = now, shots = 0 }
		st.retire[id] = r
	end
	local dt = now - r.at
	r.at = now
	if fired then
		r.idle = 0   -- counted by CAI_RetireShot
		return
	end
	local res = GetTeamResources(teamId)
	local e = (type(res) == "table" or type(res) == "userdata") and res.energy or 0
	if e >= CAI_RETIRE_MIN_ENERGY then r.idle = r.idle + dt end
	if r.idle < limit then return end
	st.retire[id] = nil
	if data.Devices then data.Devices[id] = nil end
	local result = DestroyDeviceById(id)
	CAI_Log("RETIRE " .. tostring(kind) .. " " .. id .. " idle=" .. CAI_Round(r.idle) .. " shots=" .. r.shots
		.. " result=" .. tostring(result))
end

-- smoke cover diagnostics (the round robin's FIRETRY / FIREWAIT do not see these shots), one line per weapon and
-- reason every CAI_FIREWAIT_EVERY seconds (Stalactites-3, 01.11.2026: the upgraded rockets never fired, unexplained):
--   FIRETRY <rocket> <id> fired=<0|1> code= [ray=] smoke=<s since the last smoke shell|->   rocket fired after smoke
--   SMOKETRY <launcher> <id> fired=<0|1> code= [ray=] smoke=                              smoke shell as cover
--   FIREHOLD <rocket> <id> fired=0 code= smoke=                                           held, no smoke fired
function CAI_SmokeCoverNote(st, id, what)
	local kind = type(GetDeviceType) == "function" and GetDeviceType(id) or "?"
	local fired = what ~= "FIREHOLD" and not IsWeaponReadyToFire(id)
	local ray = ""
	if what ~= "FIREHOLD" and not fired then
		local okRay, r = pcall(CAI_FireRay, id)
		ray = okRay and r or " ray=error"
	end
	local since = st.lastSmoke and st.fireClock and CAI_Round(st.fireClock - st.lastSmoke) or "-"
	CAI_FireNote(st, id, kind, what .. " " .. tostring(kind) .. " " .. id .. " fired=" .. (fired and 1 or 0)
		.. " code=" .. (fired and CAI_FireCode() or "-") .. ray .. " smoke=" .. since, what .. (fired and 1 or 0))
end

function CAI_FireTick()
	local st = data.CAI
	local f = Strategy.Fire
	if st == nil or data.gameEnded or data.defeated or data.Disable or data.DisableOffence or data.HumanAssist then
		return
	end
	st.fireClock = (st.fireClock or 0) + (f.Interval or 1)
	local okP, errP = pcall(CAI_PortalTick, st)
	if not okP then CAI_Log("ERROR portals: " .. tostring(errP)) end
	local ok, err = pcall(function()
		local n = GetWeaponCount(teamId) or 0
		if n == 0 or (data.offencePoints or 1) < 1 then return end
		local tries = math.min(f.WeaponsPerTick or 3, n)
		local no = st.noOffence or {}
		local checked = 0
		-- smoke cover: under smoke the ready rockets fire first; a ready rocket without smoke fires the smoke
		local sc = st.smokeCover
		local skip = {}
		for k in pairs(no) do skip[k] = true end
		-- volleys: one ready volley weapon per tick starts the volley or holds (CAI_Volley); the round robin skips
		-- the volley types without using up a turn (with fewer than two of them they fire there as usual)
		local v = st.volley
		if v and v.Enabled and type(GetDeviceType) == "function" and #CAI_VolleyMembers(v) >= 2 then
			for _, id in ipairs(CAI_VolleyMembers(v)) do
				if CAI_Ready(id) then
					st.fireAttempts = st.fireAttempts + 1
					TryFireGun(id)
					checked = checked + 1
					break
				end
			end
			for k in pairs(v.Types) do skip[k] = true end
		end
		if sc and sc.Enabled then
			-- smoke launchers only fire as cover for the rockets (CAI_FireSmokeFirst), never in the round robin
			for k in pairs(sc.Smoke) do skip[k] = true end
			local rockets = {}
			for _, id in ipairs(CAI_WeaponsOf(sc.Rockets)) do
				if CAI_Ready(id) then rockets[#rockets + 1] = id end
			end
			if #rockets > 0 then
				if CAI_RocketsMayFire() then
					for _, id in ipairs(rockets) do
						st.fireAttempts = st.fireAttempts + 1
						TryFireGun(id)
						checked = checked + 1
						CAI_SmokeCoverNote(st, id, "FIRETRY")
					end
				else
					st.smokeTried = nil
					if CAI_FireSmokeFirst() then checked = checked + 1 end
					if st.smokeTried then
						CAI_SmokeCoverNote(st, st.smokeTried, "SMOKETRY")
					else
						for _, id in ipairs(rockets) do CAI_SmokeCoverNote(st, id, "FIREHOLD") end
					end
				end
				-- fired or held: the round robin skips them without using up a turn
				for k in pairs(sc.Rockets) do skip[k] = true end
			end
		end
		-- round robin over the weapons; NoOffence types are skipped without using up a turn
		for step = 1, n do
			if checked >= tries then break end
			if st.firePtr >= n then st.firePtr = 0 end
			local id = GetWeaponId(teamId, st.firePtr)
			st.firePtr = st.firePtr + 1
			local kind = (type(GetDeviceType) == "function" and id and id > 0) and GetDeviceType(id) or nil
			if not (kind and skip[kind]) then
				checked = checked + 1
				if id and id > 0 and not IsDummy(id) then
					local avail = IsAIDeviceAvailable(id)
					local ready = IsWeaponReadyToFire(id)
					local code = ready and "-" or CAI_FireCode()
					local queued = data.ActionQueue ~= nil and data.ActionQueue[id] ~= nil
					if avail and ready and not queued then
						st.fireAttempts = st.fireAttempts + 1
						TryFireGun(id)
						local fired = not IsWeaponReadyToFire(id)
						local after = fired and CAI_FireCode() or "-"
						local ray = ""
						if not fired then
							local okRay, r = pcall(CAI_FireRay, id)
							ray = okRay and r or " ray=error"
						end
						CAI_FireNote(st, id, kind, "FIRETRY " .. tostring(kind) .. " " .. id .. " fired=" .. (fired and 1 or 0)
							.. " code=" .. after .. ray, "try" .. (fired and 1 or 0))
						CAI_RetireCheck(st, id, kind, fired)
					else
						CAI_FireNote(st, id, kind, "FIREWAIT " .. tostring(kind) .. " " .. id .. " avail=" .. (avail and 1 or 0)
							.. " ready=" .. (ready and 1 or 0) .. " code=" .. code .. " queue=" .. (queued and 1 or 0),
							"wait" .. tostring(avail) .. tostring(ready) .. code .. tostring(queued))
					end
				end
			end
		end
	end)
	if not ok then
		CAI_Log("ERROR fire control: " .. tostring(err))
	end
	ScheduleCall(f.Interval or 1, CAI_FireTick)
end

--------------------------------------------------------------------------------
-- Debugging: write failed build attempts with their error code to the log
-- (once per link/device and error, to keep the log small)

local CAI_BuildErrSeen = {}
local CAI_BuildErrCount = 0

local function CAI_ResultName(r)
	if type(CS) == "table" and CS[r] then return tostring(CS[r]) end
	return tostring(r)
end

-- name of a DestroyDevice result (DD_*), for the log
local function CAI_DestroyResultName(r)
	for name, v in pairs({ DD_FIRING = DD_FIRING, DD_INVALIDPLATFORM = DD_INVALIDPLATFORM, DD_INVALIDSCRIPT = DD_INVALIDSCRIPT,
			DD_MOVING = DD_MOVING, DD_NORECLAIM = DD_NORECLAIM, DD_NOTFOUND = DD_NOTFOUND, DD_NOTOWNED = DD_NOTOWNED }) do
		if v == r then return name end
	end
	return tostring(r)
end

-- sell the own device on the strut a-b by its id: the one whose platform is that strut (either order), else the
-- one standing closest to the strut, within 40 (test match 25.10.2026: the starting fort's machine gun matched
-- neither node order nor the platform lookup). Returns result or nil and, for the log, "scan=<devices>
-- match=<id|none>", with every device (type@platform:position) when none matched
local function CAI_DestroyOnPlatform(team, a, b)
	if type(GetDeviceCountSide) ~= "function" or type(DestroyDeviceById) ~= "function" then return nil, "scan=n/a" end
	local count = GetDeviceCountSide(team) or 0
	local pa, pb = NodePosition and NodePosition(a), NodePosition and NodePosition(b)
	local best, bestD, seen = nil, 40, {}
	for i = 0, count - 1 do
		local id = GetDeviceIdSide(team, i)
		local na, nb = GetDevicePlatformA(id), GetDevicePlatformB(id)
		if (na == a and nb == b) or (na == b and nb == a) then
			return DestroyDeviceById(id), "scan=" .. count .. " match=" .. tostring(id)
		end
		local q = GetDevicePosition and GetDevicePosition(id)
		if pa and pb and q then
			-- distance of the device from the strut a-b
			local dx, dy = pb.x - pa.x, pb.y - pa.y
			local len2 = dx * dx + dy * dy
			local t = len2 > 0 and math.max(0, math.min(1, ((q.x - pa.x) * dx + (q.y - pa.y) * dy) / len2)) or 0
			local ex, ey = q.x - (pa.x + t * dx), q.y - (pa.y + t * dy)
			local d = math.sqrt(ex * ex + ey * ey)
			if d < bestD then best, bestD = id, d end
		end
		seen[#seen + 1] = tostring(GetDeviceType(id)) .. "@" .. tostring(na) .. "-" .. tostring(nb)
			.. (q and (":" .. math.floor(q.x) .. "," .. math.floor(q.y)) or "")
	end
	if best then
		return DestroyDeviceById(best), "scan=" .. count .. " match=" .. tostring(best) .. " near=" .. math.floor(bestD)
	end
	return nil, "scan=" .. count .. " match=none devices=" .. table.concat(seen, ",")
end

local function CAI_NoteBuildError(kind, what, a, b, r)
	if not CAI_Logging or data.CAI == nil or data.HumanAssist then return end
	local key = kind .. ":" .. tostring(what) .. ":" .. tostring(a) .. ":" .. tostring(b) .. ":" .. tostring(r)
	if CAI_BuildErrSeen[key] or CAI_BuildErrCount >= 200 then return end
	CAI_BuildErrSeen[key] = true
	CAI_BuildErrCount = CAI_BuildErrCount + 1
	CAI_Log("BUILD_ERROR " .. kind .. " " .. tostring(what) .. " " .. tostring(a) .. "-" .. tostring(b)
		.. " " .. CAI_ResultName(r) .. " action=" .. tostring(data.fortIndex))
end

local function CAI_IsSuccess(r)
	return r == CS_SUCCESS
end

-- CS_UNSTABLE diagnostics: how strained are the links the device would hang on?
-- Rest lengths come from the plan (Fort, already moved to world coordinates by the game),
-- current lengths from the engine. Bracing breaks below 0.90 / above 1.10 of its length.
local CAI_PlanPos = nil
local CAI_PlanMat = nil       -- "<origA>:<origB>" -> material of the last plan action building that link
local CAI_ActualToOrig = nil
local CAI_UnstableCount = {}

local function CAI_PairKey(a, b)
	if a > b then a, b = b, a end
	return tostring(a) .. ":" .. tostring(b)
end

local function CAI_BuildPlanIndex()
	CAI_PlanPos = {}
	CAI_PlanMat = {}
	for _, a in ipairs(Fort or {}) do
		-- device positions are skipped: MirrorFort swaps a device's node ids but not PosA/PosB, which put both nodes
		-- of every device strut a strut length off in mirrored forts (the "sag" of 130 on Stalactites 2v2, 01.11.2026)
		if a.Type ~= CREATE_DEVICE then
			if a.OriginalNodeAId and a.PosA then CAI_PlanPos[a.OriginalNodeAId] = a.PosA end
			if a.OriginalNodeBId and a.PosB then CAI_PlanPos[a.OriginalNodeBId] = a.PosB end
			if a.OriginalNodeBId and a.NewNodePos then CAI_PlanPos[a.OriginalNodeBId] = a.NewNodePos end
		end
		if a.MaterialSaveName and a.OriginalNodeAId and a.OriginalNodeBId then
			CAI_PlanMat[CAI_PairKey(a.OriginalNodeAId, a.OriginalNodeBId)] = a.MaterialSaveName
		end
	end
end

-- "N<id>(x,y)-N<id>(x,y) <planned material>" for the log (positions now, in world coordinates)
local function CAI_LinkText(n1, p1, n2, p2, o1, o2)
	local mat = (o1 and o2 and CAI_PlanMat[CAI_PairKey(o1, o2)]) or "start-fort"
	return string.format("N%s(%d,%d)-N%s(%d,%d) %s", tostring(n1), math.floor(p1.x + 0.5), math.floor(p1.y + 0.5),
		tostring(n2), math.floor(p2.x + 0.5), math.floor(p2.y + 0.5), mat)
end

local function CAI_Dist(p, q)
	local dx, dy = p.x - q.x, p.y - q.y
	return math.sqrt(dx * dx + dy * dy)
end

-- Shape diagnostics: how far has every plan node moved from its planned position? One snapshot on the
-- first CS_UNSTABLE of a device and place, and one per game minute (CAI_Think), at most CAI_SHAPE_MAX.
-- Line: SHAPE t=<s> why=<minute|unstable:<device>> mirrored=<0|1> part=<k>/<n> <plan node id>:<dx>,<dy> ...
-- dx/dy are in the plan's own frame (x mirrored back if the game mirrored the plan), so they can be laid
-- over the plan file (.dev/tools/fortgen/shape.py). New nodes are placed relative to the current position of
-- their source node, so a lean while building is copied into everything built from it.
CAI_SHAPE_MAX = 40
CAI_SHAPE_PER_LINE = 25
CAI_ShapeCount = 0

function CAI_LogShape(why)
	if not CAI_Logging or data.CAI == nil or data.HumanAssist or CAI_ShapeCount >= CAI_SHAPE_MAX then return end
	if CAI_PlanPos == nil then CAI_BuildPlanIndex() end
	local items = {}
	for orig, act in pairs(data.OriginalToActual or {}) do
		local plan = CAI_PlanPos[orig]
		local pos = plan and NodePosition(act)
		if pos and pos.x then
			local dx = pos.x - plan.x
			if CAI_FortMirrored then dx = -dx end
			items[#items + 1] = { orig, math.floor(dx + 0.5), math.floor(pos.y - plan.y + 0.5) }
		end
	end
	if #items == 0 then return end
	CAI_ShapeCount = CAI_ShapeCount + 1
	table.sort(items, function(p, q) return p[1] < q[1] end)    -- pairs() has no fixed order
	local t = (data.CAI.ticks or 0) * (Strategy.ThinkInterval or 0)
	local parts = math.ceil(#items / CAI_SHAPE_PER_LINE)
	for k = 1, parts do
		local chunk = {}
		for i = (k - 1) * CAI_SHAPE_PER_LINE + 1, math.min(k * CAI_SHAPE_PER_LINE, #items) do
			chunk[#chunk + 1] = items[i][1] .. ":" .. items[i][2] .. "," .. items[i][3]
		end
		CAI_Log("SHAPE t=" .. t .. " why=" .. tostring(why) .. " mirrored=" .. (CAI_FortMirrored and 1 or 0)
			.. " part=" .. k .. "/" .. parts .. " " .. table.concat(chunk, " "))
	end
end

-- Stress diagnostics: the engine's own stress of the struts (EnumerateLinks hands it to the callback), on the
-- first CS_UNSTABLE of a device and place, at most CAI_STRESS_MAX times. The strain in the UNSTABLE line only
-- compares with plan lengths; struts built between nodes that had already moved have other rest lengths.
-- Line: STRESS <device> <a>-<b> at=<link> ... top=<link> ...
-- at = the struts at the device's two nodes, top = the CAI_STRESS_TOP most stressed struts of the fort (by |stress|);
-- <link> = <node>-<node>:<material>:<stress>, <node> = P<plan node id> if the node is in the plan, else N<actual id>
CAI_STRESS_MAX = 20
CAI_STRESS_TOP = 8
CAI_StressCount = 0
CAI_StressScan = nil

function CAI_EnumStress(nodeA, nodeB, saveName, relativeHealth, stress, segmentsOnFire, deviceId)
	local s = CAI_StressScan
	if s and nodeA and nodeB and type(stress) == "number" then
		local item = { nodeA, nodeB, tostring(saveName), stress }
		if s.at[nodeA] or s.at[nodeB] then s.near[#s.near + 1] = item end
		s.all[#s.all + 1] = item
	end
	return true      -- continue enumeration
end

function CAI_LogStress(what, a, b)
	if not CAI_Logging or type(EnumerateLinks) ~= "function" or CAI_StressCount >= CAI_STRESS_MAX then return end
	CAI_StressCount = CAI_StressCount + 1
	local toOrig = {}
	for orig, act in pairs(data.OriginalToActual or {}) do toOrig[act] = orig end
	CAI_StressScan = { at = { [a] = true, [b] = true }, near = {}, all = {} }
	local ok, err = pcall(EnumerateLinks, teamId, "CAI_EnumStress", 1, 1, "", false)
	local s = CAI_StressScan
	CAI_StressScan = nil
	if not ok then
		CAI_Log("ERROR stress diagnostics: " .. tostring(err))
		return
	end
	local function label(n) return toOrig[n] and ("P" .. toOrig[n]) or ("N" .. tostring(n)) end
	local function text(list, n)
		table.sort(list, function(p, q)
			if math.abs(p[4]) ~= math.abs(q[4]) then return math.abs(p[4]) > math.abs(q[4]) end
			if p[1] ~= q[1] then return p[1] < q[1] end
			return p[2] < q[2]
		end)
		local out = {}
		for i = 1, math.min(n, #list) do
			local l = list[i]
			out[#out + 1] = string.format("%s-%s:%s:%.3f", label(l[1]), label(l[2]), l[3], l[4])
		end
		return table.concat(out, " ")
	end
	CAI_Log("STRESS " .. tostring(what) .. " " .. tostring(a) .. "-" .. tostring(b) .. " links=" .. #s.all
		.. " at=" .. text(s.near, #s.near) .. " top=" .. text(s.all, CAI_STRESS_TOP))
end

local function CAI_NoteUnstable(what, a, b)
	if not CAI_Logging or data.CAI == nil or data.HumanAssist then return end
	local key = tostring(what) .. ":" .. tostring(a) .. ":" .. tostring(b)
	local n = (CAI_UnstableCount[key] or 0) + 1
	if n > 3 then return end                 -- three samples per device and place are enough
	CAI_UnstableCount[key] = n
	if CAI_PlanPos == nil then CAI_BuildPlanIndex() end
	CAI_ActualToOrig = {}
	for orig, act in pairs(data.OriginalToActual or {}) do CAI_ActualToOrig[act] = orig end
	local parts = {}
	local minR, maxR, links = 9, 0, 0
	local minL, maxL = "-", "-"
	for _, nid in ipairs({ a, b }) do
		local pos = NodePosition(nid)
		local orig = CAI_ActualToOrig[nid]
		local plan = orig and CAI_PlanPos[orig]
		local vel = NodeVelocity(nid)
		local speed = vel and math.sqrt(vel.x * vel.x + vel.y * vel.y) or -1
		parts[#parts + 1] = "N" .. tostring(nid) .. " sag=" .. (plan and pos and math.floor(CAI_Dist(pos, plan) + 0.5) or "?")
			.. " v=" .. math.floor(speed + 0.5)
		for k = 0, (NodeLinkCount(nid) or 0) - 1 do
			local other = NodeLinkedNodeId(nid, k)
			local o2 = CAI_ActualToOrig[other]
			local p1, p2 = plan, o2 and CAI_PlanPos[o2]
			local q2 = NodePosition(other)
			if p1 and p2 and pos and q2 then
				local rest = CAI_Dist(p1, p2)
				if rest > 1 then
					local r = CAI_Dist(pos, q2) / rest
					if r < minR then minR = r; minL = CAI_LinkText(nid, pos, other, q2, orig, o2) end
					if r > maxR then maxR = r; maxL = CAI_LinkText(nid, pos, other, q2, orig, o2) end
					links = links + 1
				end
			end
		end
	end
	CAI_Log(string.format("UNSTABLE %s %s-%s %s links=%d strain=%.3f..%.3f stretched=%s compressed=%s action=%s",
		tostring(what), tostring(a), tostring(b), table.concat(parts, " "), links, links > 0 and minR or 0, links > 0 and maxR or 0,
		maxL, minL, tostring(data.fortIndex)))
	if n == 1 then
		CAI_LogShape("unstable:" .. tostring(what))
		CAI_LogStress(what, a, b)
	end
end

-- The game only provides the build functions after initialisation,
-- so they are hooked in Load.
CAI_BuildLoggingInstalled = false

function CAI_InstallBuildLogging()
	if CAI_BuildLoggingInstalled then return "already active" end
	CAI_BuildLoggingInstalled = true
	local hooked = {}
	if type(CreateLink) == "function" then
		local CAI_BaseCreateLink = CreateLink
		CreateLink = function(team, material, nodeA, nodeB, ...)
			local r = CAI_BaseCreateLink(team, material, nodeA, nodeB, ...)
			if not CAI_IsSuccess(r) and r ~= CS_INSUFFICIENTRESOURCES then
				pcall(CAI_NoteBuildError, "link", material, nodeA, nodeB, r)
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
				pcall(CAI_NoteBuildError, "node", material, nodeA, pos and (math.floor(pos.x) .. "," .. math.floor(pos.y)), r)
			end
			return r
		end
		table.insert(hooked, "CreateNode")
	end
	if type(CreateDeviceWithFlags) == "function" then
		local CAI_BaseCreateDeviceWithFlags = CreateDeviceWithFlags
		CAI_RawCreateDeviceWithFlags = CAI_BaseCreateDeviceWithFlags    -- the probe places without diagnostics
		CreateDeviceWithFlags = function(team, saveName, nodeA, nodeB, t, ...)
			local r = CAI_BaseCreateDeviceWithFlags(team, saveName, nodeA, nodeB, t, ...)
			if type(r) == "number" and r < 0 and r ~= CS_INSUFFICIENTRESOURCES then
				pcall(CAI_NoteBuildError, "device", saveName, nodeA, nodeB, r)
				if r == CS_UNSTABLE then
					-- a heavy weapon refused: the socket's small weapon need not wait for it (CAI_SocketUpgrade)
					local st = data.CAI
					if st and (CAI_Defaults.SocketVolley.EnergyShot[saveName] or saveName == "upgrade") then
						st.heavyRefused = st.heavyRefused or st.ticks * Strategy.ThinkInterval
					end
					local ok, err = pcall(CAI_NoteUnstable, saveName, nodeA, nodeB)
					if not ok then CAI_Log("ERROR unstable diagnostics: " .. tostring(err)) end
				end
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
				pcall(CAI_NoteBuildError, "ground_device", saveName, pos and (math.floor(pos.x) .. "," .. math.floor(pos.y)), "", r)
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
				pcall(CAI_NoteBuildError, "upgrade", saveName, id, "", r)
			end
			return r
		end
		table.insert(hooked, "UpgradeDevice")
	end
	if type(DestroyDevice) == "function" then
		-- A device is found on a strut only in the node order it was built with (GetDeviceIdOnPlatform); a plan
		-- may name the strut the other way round (selling a device of the starting fort, whose order the plan
		-- does not know), so a sale that finds nothing is tried the other way round, as the built-in
		-- DestroyAttachedDevices does. Test matches 25.10.2026: the sale of the starting machine gun failed until
		-- the AI gave up, also with both orders (DD_NOTFOUND, though the machine gun stands on that strut); so
		-- then the own device whose platform is that strut is looked up and sold by its id.
		local CAI_BaseDestroyDevice = DestroyDevice
		DestroyDevice = function(team, nodeA, nodeB, ...)
			local r = CAI_BaseDestroyDevice(team, nodeA, nodeB, ...)
			if r ~= nil and r == DD_NOTFOUND then
				r = CAI_BaseDestroyDevice(team, nodeB, nodeA, ...)
			end
			local scan = ""
			if r ~= nil and r == DD_NOTFOUND then
				local ok, res, info = pcall(CAI_DestroyOnPlatform, team, nodeA, nodeB)
				if ok and res ~= nil then r = res end
				scan = ok and tostring(info) or ("ERROR " .. tostring(res))
			end
			if r ~= nil and r ~= DD_SUCCESS then
				pcall(CAI_NoteBuildError, "destroy", scan, nodeA, nodeB, CAI_DestroyResultName(r))
			end
			return r
		end
		table.insert(hooked, "DestroyDevice")
	end
	return (#hooked > 0) and table.concat(hooked, ",") or "no build functions found"
end

--------------------------------------------------------------------------------
-- CS_UNSTABLE probe (testing only; FortPlanConfig.Probe in ai/fortplans.lua, off by default)
-- Once the plan is finished (or after Probe.At seconds) the AI stops building (data.Disable) and tries every
-- device of Probe.Devices at every LinkT of Probe.LinkT on every strut of its fort made of Probe.Materials
-- and at most Probe.MaxAngle (default 20) degrees steep (steep = struts left out for that),
-- one attempt every Probe.Interval seconds. A device that is placed is removed again at once (refunded), or
-- after Probe.Hold seconds, when its load is measured. For a sandbox match without combat;
-- .dev/tools/fortgen/probe.py reads the lines:
--   PROBE START t=<s> devices=<a,b> linkt=<t,t> struts=<n> steep=<n> attempts=<n> mirrored=<0|1>
--   PROBE NODE part=<k>/<n> <id>:<x>,<y>:<plan node id|-> ...     every node of the fort (world coordinates)
--   PROBE LINK part=<k>/<n> <a>-<b>:<material>:<stress>[:<device>@<LinkT>,...] ...
--             every strut with the engine's stress and the devices standing on it
--   PROBE TRY <k> <device> <a>-<b> t=<LinkT> r=<OK|result> s=<stress> sn=<max |stress| at a, b> len=<length>
--             ang=<degrees from horizontal> sag=<a>,<b> v=<a>,<b> dv=<devices on the strut>
--             dn=<devices on the other struts at a or b> near=<their types, sorted|->
--   PROBE LOAD <k> <device> <a>-<b> s=<stress> sn=<..> top=<max |stress|>:<a>-<b> d=<dxA>,<dyA>,<dxB>,<dyB>
--   PROBE END tried=<n> placed=<n> unstable=<n> other=<n>
-- s/sn are measured before the attempt; sag = distance of a node from its plan position (-1: not a plan node);
-- d = how far the device's nodes moved while it stood. Short of resources, an attempt waits (PROBE WAIT) and
-- is repeated, at most CAI_PROBE_WAITS times.
CAI_PROBE_PER_LINE = 25
CAI_PROBE_WAITS = 30
CAI_Probe = nil
CAI_ProbeScan = nil

function CAI_EnumProbe(nodeA, nodeB, saveName, relativeHealth, stress, segmentsOnFire, deviceId)
	local s = CAI_ProbeScan
	if s and nodeA and nodeB then
		local key = CAI_PairKey(nodeA, nodeB)
		local l = s.seen[key]
		if not l then
			l = { nodeA, nodeB, tostring(saveName), type(stress) == "number" and stress or 0, devs = {} }
			s.seen[key] = l
			s.list[#s.list + 1] = l
		end
		-- a strut with devices may be enumerated once per device (the built-in DiscoverDevices relies on it)
		if type(deviceId) == "number" and deviceId > 0 and not s.devSeen[deviceId] then
			s.devSeen[deviceId] = true
			l.devs[#l.devs + 1] = deviceId
		end
	end
	return true      -- continue enumeration
end

-- every strut of the team: { nodeA, nodeB, material, stress, devs = { device id, ... } }, sorted by node ids
local function CAI_ProbeLinks()
	CAI_ProbeScan = { seen = {}, devSeen = {}, list = {} }
	local ok, err = pcall(EnumerateLinks, teamId, "CAI_EnumProbe", 1, 1, "", false)
	local s = CAI_ProbeScan
	CAI_ProbeScan = nil
	if not ok then error(err) end
	table.sort(s.list, function(p, q)
		if p[1] ~= q[1] then return p[1] < q[1] end
		return p[2] < q[2]
	end)
	return s.list
end

-- stress of strut a-b, the largest |stress| of the other struts at a or b, the largest of the fort and its strut
local function CAI_ProbeStress(list, a, b)
	local s, sn, top, topL = 0, 0, 0, "-"
	for _, l in ipairs(list) do
		local v = math.abs(l[4])
		if (l[1] == a and l[2] == b) or (l[1] == b and l[2] == a) then
			s = l[4]
		elseif l[1] == a or l[1] == b or l[2] == a or l[2] == b then
			if v > sn then sn = v end
		end
		if v > top then top, topL = v, l[1] .. "-" .. l[2] end
	end
	return s, sn, top, topL
end

-- devices on strut a-b, devices on the other struts at a or b, and the sorted types of the latter
local function CAI_ProbeDevices(list, a, b)
	local dv, dn, types = 0, 0, {}
	for _, l in ipairs(list) do
		if (l[1] == a and l[2] == b) or (l[1] == b and l[2] == a) then
			dv = dv + #l.devs
		elseif l[1] == a or l[1] == b or l[2] == a or l[2] == b then
			dn = dn + #l.devs
			for _, id in ipairs(l.devs) do types[#types + 1] = tostring(GetDeviceType(id)) end
		end
	end
	table.sort(types)
	return dv, dn, #types > 0 and table.concat(types, ",") or "-"
end

local function CAI_ProbeDeviceText(id)
	local t = (type(GetDeviceLinkPosition) == "function") and GetDeviceLinkPosition(id)
	return tostring(GetDeviceType(id)) .. (type(t) == "number" and string.format("@%.2f", t) or "")
end

local function CAI_ProbeLogParts(kind, items)
	local parts = math.ceil(#items / CAI_PROBE_PER_LINE)
	for k = 1, parts do
		local chunk = {}
		for i = (k - 1) * CAI_PROBE_PER_LINE + 1, math.min(k * CAI_PROBE_PER_LINE, #items) do chunk[#chunk + 1] = items[i] end
		CAI_Log("PROBE " .. kind .. " part=" .. k .. "/" .. parts .. " " .. table.concat(chunk, " "))
	end
end

local function CAI_ProbeSag(p, n, pos)
	local orig = p.toOrig[n]
	local plan = orig and CAI_PlanPos[orig]
	if plan and pos then return math.floor(CAI_Dist(pos, plan) + 0.5) end
	return -1
end

local function CAI_ProbeSpeed(n)
	local v = NodeVelocity(n)
	return v and math.floor(math.sqrt(v.x * v.x + v.y * v.y) + 0.5) or -1
end

function CAI_ProbeStart(elapsed)
	local cfg = FortPlanConfig.Probe
	if CAI_PlanPos == nil then CAI_BuildPlanIndex() end
	local toOrig = {}
	for orig, act in pairs(data.OriginalToActual or {}) do toOrig[act] = orig end
	local mats = {}
	for _, m in ipairs(cfg.Materials or { "bracing", "armour" }) do mats[m] = true end
	local devices = cfg.Devices or { "sniper" }
	local linkT = cfg.LinkT or { 0.5 }
	local box = cfg.Box
	-- devices only go on roughly level struts (first game run: every strut of 30 degrees or more was CS_INVALIDNODES)
	local maxAngle = cfg.MaxAngle or 20
	local list = CAI_ProbeLinks()
	local nodes, linkItems, struts, steep = {}, {}, {}, 0
	for _, l in ipairs(list) do
		local item = string.format("%d-%d:%s:%.3f", l[1], l[2], l[3], l[4])
		if #l.devs > 0 then
			local ds = {}
			for _, id in ipairs(l.devs) do ds[#ds + 1] = CAI_ProbeDeviceText(id) end
			item = item .. ":" .. table.concat(ds, ",")
		end
		linkItems[#linkItems + 1] = item
		nodes[l[1]], nodes[l[2]] = true, true
		local pa, pb = NodePosition(l[1]), NodePosition(l[2])
		local use = mats[l[3]] and pa ~= nil and pb ~= nil
		if use and math.deg(math.atan(math.abs(pb.y - pa.y) / math.max(math.abs(pb.x - pa.x), 0.001))) > maxAngle then
			use = false
			steep = steep + 1
		end
		if use and box then
			local mx, my = (pa.x + pb.x) / 2, (pa.y + pb.y) / 2
			use = mx >= box[1] and mx <= box[3] and my >= box[2] and my <= box[4]
		end
		if use then struts[#struts + 1] = l end
	end
	-- one device over the whole fort before the next, so a capped run still maps whole devices
	local attempts = {}
	for _, d in ipairs(devices) do
		for _, l in ipairs(struts) do
			for _, t in ipairs(linkT) do attempts[#attempts + 1] = { l[1], l[2], d, t } end
		end
	end
	while cfg.Max and #attempts > cfg.Max do table.remove(attempts) end
	local ids = {}
	for n in pairs(nodes) do ids[#ids + 1] = n end
	table.sort(ids)
	local nodeItems = {}
	for _, n in ipairs(ids) do
		local q = NodePosition(n)
		if q then nodeItems[#nodeItems + 1] = string.format("%d:%.1f,%.1f:%s", n, q.x, q.y, toOrig[n] and tostring(toOrig[n]) or "-") end
	end
	CAI_Probe = { cfg = cfg, attempts = attempts, k = 0, toOrig = toOrig, placed = 0, unstable = 0, other = 0, waits = 0,
		wasDisabled = data.Disable }
	data.Disable = true
	local ts = {}
	for i, t in ipairs(linkT) do ts[i] = string.format("%.2f", t) end    -- the game hands over 32-bit floats
	CAI_Log("PROBE START t=" .. elapsed .. " devices=" .. table.concat(devices, ",") .. " linkt=" .. table.concat(ts, ",")
		.. " struts=" .. #struts .. " steep=" .. steep .. " attempts=" .. #attempts .. " mirrored=" .. (CAI_FortMirrored and 1 or 0))
	CAI_ProbeLogParts("NODE", nodeItems)
	CAI_ProbeLogParts("LINK", linkItems)
	ScheduleCall(cfg.Interval or 0.2, CAI_ProbeTick)
end

local function CAI_ProbeFinish(p)
	p.done = true
	data.Disable = p.wasDisabled
	CAI_Log("PROBE END tried=" .. p.k .. " placed=" .. p.placed .. " unstable=" .. p.unstable .. " other=" .. p.other)
end

local function CAI_ProbeRemove(id)
	local r = DestroyDeviceById(id)
	if DD_SUCCESS ~= nil and r ~= DD_SUCCESS then CAI_Log("PROBE ERROR remove " .. tostring(id) .. " " .. tostring(r)) end
end

local function CAI_ProbeStep(p)
	p.wait = nil
	local h = p.hold
	if h then
		-- a placed device has stood for Probe.Hold seconds: measure its load, then remove it
		p.hold = nil
		local s, sn, top, topL = CAI_ProbeStress(CAI_ProbeLinks(), h.a, h.b)
		local qa, qb = NodePosition(h.a), NodePosition(h.b)
		local d = (qa and qb) and string.format("%d,%d,%d,%d", math.floor(qa.x - h.pa.x + 0.5), math.floor(qa.y - h.pa.y + 0.5),
			math.floor(qb.x - h.pb.x + 0.5), math.floor(qb.y - h.pb.y + 0.5)) or "-"
		CAI_Log(string.format("PROBE LOAD %d %s %d-%d s=%.3f sn=%.3f top=%.3f:%s d=%s", h.k, h.dev, h.a, h.b, s, sn, top, topL, d))
		CAI_ProbeRemove(h.id)
		return
	end
	if p.k >= #p.attempts then
		CAI_ProbeFinish(p)
		return
	end
	local k = p.k + 1
	local a, b, dev, t = p.attempts[k][1], p.attempts[k][2], p.attempts[k][3], p.attempts[k][4]
	local pa, pb = NodePosition(a), NodePosition(b)
	if pa == nil or pb == nil then
		p.k = k
		p.other = p.other + 1
		CAI_Log(string.format("PROBE TRY %d %s %d-%d t=%.2f r=GONE", k, dev, a, b, t))
		return
	end
	local list = CAI_ProbeLinks()
	local s, sn = CAI_ProbeStress(list, a, b)
	local dv, dn, near = CAI_ProbeDevices(list, a, b)
	local r = (CAI_RawCreateDeviceWithFlags or CreateDeviceWithFlags)(teamId, dev, a, b, t, 0, -1)
	local starved = r == CS_INSUFFICIENTRESOURCES or (CD_INSUFFICIENTRESOURCES ~= nil and r == CD_INSUFFICIENTRESOURCES)
	if starved and p.waits < CAI_PROBE_WAITS then
		if p.waits == 0 then CAI_Log("PROBE WAIT " .. k .. " " .. dev .. " resources") end
		p.waits = p.waits + 1
		p.wait = 1
		return
	end
	p.waits = 0
	p.k = k
	local placed = type(r) == "number" and r >= 0
	if placed then
		p.placed = p.placed + 1
	elseif r == CS_UNSTABLE then
		p.unstable = p.unstable + 1
	else
		p.other = p.other + 1
	end
	local dx, dy = pb.x - pa.x, pb.y - pa.y
	CAI_Log(string.format("PROBE TRY %d %s %d-%d t=%.2f r=%s s=%.3f sn=%.3f len=%.1f ang=%.1f sag=%d,%d v=%d,%d dv=%d dn=%d near=%s",
		k, dev, a, b, t, placed and "OK" or CAI_ResultName(r), s, sn, math.sqrt(dx * dx + dy * dy),
		math.deg(math.atan(math.abs(dy) / math.max(math.abs(dx), 0.001))), CAI_ProbeSag(p, a, pa), CAI_ProbeSag(p, b, pb),
		CAI_ProbeSpeed(a), CAI_ProbeSpeed(b), dv, dn, near))
	if placed then
		local hold = p.cfg.Hold or 0
		if hold > 0 then
			p.hold = { id = r, k = k, dev = dev, a = a, b = b, pa = { x = pa.x, y = pa.y }, pb = { x = pb.x, y = pb.y } }
			p.wait = hold
		else
			CAI_ProbeRemove(r)
		end
	end
end

function CAI_ProbeTick()
	local p = CAI_Probe
	if p == nil or p.done or data.gameEnded then return end
	local k, h = p.k, p.hold
	local ok, err = pcall(CAI_ProbeStep, p)
	if not ok then
		CAI_Log("ERROR probe: " .. tostring(err))
		p.hold, p.wait = nil, nil
		if h then pcall(DestroyDeviceById, h.id) end
		-- never retry a failing attempt forever
		if p.k == k and not h then p.k = k + 1 end
		if p.k >= #p.attempts then CAI_ProbeFinish(p) end
	end
	if not p.done then ScheduleCall(p.wait or p.cfg.Interval or 0.2, CAI_ProbeTick) end
end

--------------------------------------------------------------------------------
-- Initialisation

function CAI_Init()
	if data.CAI and data.CAI.initialised then
		return
	end
	data.CAI =
	{
		initialised = true,
		ticks = 0,
		threat = {},       -- enemy weapon type -> threat (decays over time)
		shots = {},        -- enemy weapon type -> total shots
		recentIndirect = 0,
		projOwner = {},    -- projectile node -> weapon type, to attribute hits to a weapon
		projCount = 0,
		lost = {},         -- own lost devices by type
		kills = {},        -- destroyed enemy devices by type
		baseOff = {},
		baseAA = {},
	}
	for k, v in pairs(data.OffensiveFireProbability) do
		data.CAI.baseOff[k] = v
	end
	local okS, errS = pcall(CAI_InitSockets)
	if not okS then CAI_Log("ERROR sockets: " .. tostring(errS)) end
	local okB, errB = pcall(CAI_InitBuzzsaw)
	if not okB then CAI_Log("ERROR buzzsaw: " .. tostring(errB)) end
	for k, v in pairs(data.AntiAirFireProbability) do
		data.CAI.baseAA[k] = v
	end
	CAI_Log("INIT strategy=v" .. tostring(Strategy.Version) .. " trained=" .. tostring(Strategy.TrainedGames)
		.. " loaded=" .. tostring(CAI_StrategyLoaded) .. " difficulty=" .. tostring(data.difficulty))
end

--------------------------------------------------------------------------------
-- 1. Adaptive target selection

function CAI_BuildPriorityList(baseList, values)
	local entries = {}
	for i, saveName in ipairs(baseList) do
		local base = values[saveName]
		if base == nil then
			base = math.max(5, 100 - 4 * (i - 1))
		end
		-- saturating: half the bonus at ThreatHalf, almost the full bonus under heavy threat
		local threat = data.CAI.threat[saveName] or 0
		local bonus = Strategy.ThreatWeight * threat / (threat + Strategy.ThreatHalf)
		-- the posture's boost (Bastion)
		local boost = data.CAI.postureBoost and data.CAI.postureBoost[saveName] or 1
		table.insert(entries, { name = saveName, score = (base + bonus) * boost, idx = i })
	end
	-- sort stably and deterministically
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
-- 2. Aggression by phase and economy

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

	local no = data.CAI.noOffence or {}
	for k, base in pairs(data.CAI.baseOff) do
		if not s.AggressionExclude[k] and not no[k] then
			data.OffensiveFireProbability[k] = CAI_Clamp(base * mult, 0, 1)
		end
	end
	return "phase=" .. phase .. " econ=" .. econ .. " m=" .. CAI_Round(metal) .. " e=" .. CAI_Round(energy) .. " aggr=" .. CAI_Round(mult)
end

--------------------------------------------------------------------------------
-- 3. Anti-air by incoming fire pressure

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
-- Think loop

--------------------------------------------------------------------------------
-- Reactive build modules (.dev/docs/ai.md): pre-generated snippets in the plan file (FortModules), put in front
-- of the rest of the plan when the enemy builds the devices of their trigger.

-- After the base Load: cut the module actions (appended on the swap, renumbered and moved by the game's
-- transform) out of Fort, so the built-in AI never reaches them on its own.
function CAI_ExtractModules()
	local defs = CAI_Plan.modules
	CAI_Plan.modules = nil
	if type(defs) ~= "table" or #defs == 0 or type(Fort) ~= "table" then return end
	local mods = { list = {} }
	for i, m in ipairs(defs) do
		mods.list[i] = { name = tostring(m.Name or i), trigger = m.Trigger or {}, requires = m.Requires or 0, actions = {},
			repeats = tonumber(m.Repeat) or 0, cooldown = tonumber(m.Cooldown) or 60, socket = m.Socket, retire = m.Retire, replace = m.Replace }
	end
	local kept = {}
	for _, a in ipairs(Fort) do
		local i = a.CAI_Module
		if i and mods.list[i] then
			table.insert(mods.list[i].actions, a)
		else
			table.insert(kept, a)
		end
	end
	for k = #Fort, 1, -1 do Fort[k] = nil end
	for k, a in ipairs(kept) do Fort[k] = a end
	data.CAIModules = mods
	CAI_PlanPos = nil   -- rebuilt with the module nodes on next use (SHAPE diagnostics)
	local parts = {}
	for _, m in ipairs(mods.list) do parts[#parts + 1] = m.name .. ":" .. #m.actions end
	CAI_Log("MODULES " .. table.concat(parts, ","))
end

-- enemy devices by type (game state, deterministic)
local function CAI_EnemyDevices()
	local count = {}
	for i = 0, GetDeviceCountSide(enemyTeamId) - 1 do
		local t = GetDeviceType(GetDeviceIdSide(enemyTeamId, i))
		if t then count[t] = (count[t] or 0) + 1 end
	end
	return count
end

-- the plan action number the AI has got to: the last plan action before data.fortIndex
local function CAI_PlanProgress()
	for k = math.min(data.fortIndex - 1, #Fort), 1, -1 do
		if Fort[k].CAI_K then return Fort[k].CAI_K end
	end
	return 0
end

function CAI_ListHas(list, v)
	for _, x in ipairs(list) do if x == v then return true end end
	return false
end

-- a plan action with its own position tables
function CAI_CopyAction(a)
	local c = {}
	for k, v in pairs(a) do
		if type(v) == "table" then
			local t = {}
			for kk, vv in pairs(v) do t[kk] = vv end
			c[k] = t
		else
			c[k] = v
		end
	end
	return c
end

-- insert n actions at index fi and move everything the built-in AI and the mod keep by action index
local function CAI_InsertActions(fi, actions)
	local n = #actions
	for j = n, 1, -1 do table.insert(Fort, fi, actions[j]) end
	local function ShiftKeys(t)
		if type(t) ~= "table" then return end
		local moved = {}
		for k, v in pairs(t) do
			if type(k) == "number" and k >= fi then moved[k] = v end
		end
		for k in pairs(moved) do t[k] = nil end
		for k, v in pairs(moved) do t[k + n] = v end
	end
	ShiftKeys(data.Rebuild)
	ShiftKeys(data.Frustration)
	if data.CAI then
		ShiftKeys(data.CAI.rebuildSince)
		ShiftKeys(data.CAI.rebuilds)
		data.CAI.buildIndex = nil   -- the skip valve starts a new clock
	end
	if type(data.Devices) == "table" then
		for id, k in pairs(data.Devices) do
			if type(k) == "number" and k >= fi then data.Devices[id] = k + n end
		end
	end
end

-- one think step: fire the modules whose trigger is reached, once per match each. Trigger: the enemy has Count
-- devices of Types together, or the game time has reached Time (seconds; a module that is also the plan's goal comes
-- even if the enemy never builds its trigger); After = <module name>: only once that module has gone in.
-- Surplus = { Metal = m, Energy = e, Seconds = s }: the plan (with the modules inserted so far) is built, no rebuild is
-- queued, and metal and energy have stayed at or above m and e for s seconds (default 20): the AI has nothing left
-- to build while its storage fills up.

-- "surplus:m=<metal>,e=<energy>" once module m's Surplus condition has held long enough, else nil
function CAI_SurplusReason(m, elapsed)
	local s = m.trigger.Surplus
	if type(s) ~= "table" then return nil end
	local idle = Fort ~= nil and data.fortIndex > #Fort and (type(data.Rebuild) ~= "table" or next(data.Rebuild) == nil)
	local metal, energy = -1, -1
	if idle then
		local res = GetTeamResources(teamId)
		if type(res) == "table" or type(res) == "userdata" then metal, energy = res.metal or -1, res.energy or -1 end
	end
	if not idle or metal < (s.Metal or 0) or energy < (s.Energy or 0) then
		m.surplusSince = nil
		return nil
	end
	m.surplusSince = m.surplusSince or elapsed
	if elapsed - m.surplusSince < (s.Seconds or 20) then return nil end
	return "surplus:m=" .. CAI_Round(metal) .. ",e=" .. CAI_Round(energy)
end

-- Replace = true (Bastion): the module's device takes over its socket from another weapon at another point of the strut.
-- The old actions leave the socket and are not rebuilt, the old weapon is sold (test 8: a heavy weapon for the front mortar).
-- a Replace module's socket and weapon: the first of the socket's list the tech standing allows and the storage can pay
-- (the first tech branch is chance), a weapon no other heavy socket holds before one that is (a mix)
function CAI_ModulePick(m)
	local name, w
	for _, a in ipairs(m.actions) do
		if a.Socket and a.Type == CREATE_DEVICE then name, w = a.Socket, a.DeviceSaveName end
	end
	local st = data.CAI
	local s = name and st and st.sockets and st.sockets[name]
	if not s then return nil, w end
	local own, placed = CAI_OwnDevices(true), CAI_OwnDevices()
	local list = s.upgrade or { "cannon", "cannon20mm", "laser", "firebeam" }
	for pass = 1, 2 do
		for _, c in ipairs(CAI_SocketOrder(s, list)) do
			local need = s.needs[c] or (c == "laser" or c == "firebeam") and "factory" or "munitions"
			-- a mix counts what is still under construction too (test 11: two cannons, the first not yet built)
			if (pass == 1) == ((placed[c] or 0) == 0) and (own[need] or 0) > 0 and CAI_Affordable(st, c) then
				return name, c
			end
		end
	end
	return name, w
end

-- a socket given up: its weapon is sold and neither rebuilt nor refilled (Vanilla-8's mortars, for the storey over C1)
function CAI_SocketRetire(name)
	local old = {}
	for k, a in ipairs(Fort) do
		if a.Socket == name then
			a.Socket = nil
			old[k] = true
			data.Rebuild[k] = nil
		end
	end
	local ids = {}
	for id, k in pairs(data.Devices) do
		if old[k] then ids[#ids + 1] = id end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		data.Devices[id] = nil
		local t = GetDeviceType(id)
		if t then CAI_Log("SOCKET " .. name .. " retired " .. tostring(t) .. " result=" .. tostring(DestroyDeviceById(id))) end
	end
end

function CAI_ModuleReplace(m)
	local name, w = CAI_ModulePick(m)
	local st = data.CAI
	if name == nil or st == nil or st.sockets == nil or st.sockets[name] == nil then return end
	local old = {}
	for k, a in ipairs(Fort) do
		if a.Socket == name then
			a.Socket = nil
			old[k] = true
			data.Rebuild[k] = nil
		end
	end
	local ids = {}
	for id, k in pairs(data.Devices) do
		if old[k] then ids[#ids + 1] = id end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		data.Devices[id] = nil
		local t = GetDeviceType(id)
		if t then
			local r = DestroyDeviceById(id)
			CAI_Log("SOCKET " .. name .. " replaced " .. tostring(t) .. "->" .. tostring(w) .. " result=" .. tostring(r))
		end
	end
	st.sockets[name].current = w
end

function CAI_ModuleAffordable(m)
	if type(GetDeviceCost) ~= "function" then return true end
	local res = GetTeamResources(teamId)
	if not (type(res) == "table" or type(res) == "userdata") then return true end
	local cm, ce = 0, 0
	local pickName, pick
	if m.replace then pickName, pick = CAI_ModulePick(m) end
	for _, a in ipairs(m.actions) do
		if a.DeviceSaveName then
			local ok, c = pcall(GetDeviceCost, a.Socket == pickName and pick or a.DeviceSaveName)
			if ok and c then cm, ce = cm + (c.metal or 0), ce + (c.energy or 0) end
		end
	end
	-- Reserve: its whole price and this much metal over, for the shots of what stands
	local reserve = m.trigger and m.trigger.Reserve
	if reserve then return (res.metal or 0) >= cm + reserve and (res.energy or 0) >= ce end
	return (res.metal or 0) >= 0.8 * cm and (res.energy or 0) >= 0.8 * ce
end

-- own heavy weapons standing (SocketVolley.EnergyShot's types); builtOnly: fully built
function CAI_HeavyCount(builtOnly)
	if type(GetDeviceCountSide) ~= "function" then return 0 end
	local side, n = CAI_Side(teamId), 0
	for i = 0, GetDeviceCountSide(side) - 1 do
		local id = GetDeviceIdSide(side, i)
		if CAI_Defaults.SocketVolley.EnergyShot[GetDeviceType(id)] and CAI_IsOwnDevice(id)
			and (not builtOnly or type(IsDeviceFullyBuilt) ~= "function" or IsDeviceFullyBuilt(id)) then
			n = n + 1
		end
	end
	return n
end

-- the storage full for that many seconds: nothing is short, what waits may come (test 12: 1500 metal / 9000 energy from 480 s to the end)
function CAI_AtCap(elapsed, seconds)
	local st = data.CAI
	local cfg = (Strategy.Socket or CAI_Defaults.Socket).Upgrade or CAI_Defaults.Socket.Upgrade
	local v = CAI_Defaults.SocketVolley
	local own = CAI_OwnDevices(true)
	local res = GetTeamResources(teamId)
	local share = cfg.CapShare or 0.95
	local full = (type(res) == "table" or type(res) == "userdata")
		and (res.metal or 0) >= share * (v.BaseMetal + v.Store * (own.store or 0))
		and (res.energy or 0) >= share * (v.BaseStorage + v.Battery * (own.battery or 0))
	st.capSince = full and (st.capSince or elapsed) or nil
	return st.capSince ~= nil and elapsed - st.capSince >= seconds
end

-- the first heavy weapons are done: what waits for them may come. Two built, or the first built for HeavyWait seconds
function CAI_HeavyDone(elapsed)
	local st = data.CAI
	local cfg = (Strategy.Socket or CAI_Defaults.Socket).Upgrade or CAI_Defaults.Socket.Upgrade
	local built = CAI_HeavyCount(true)
	if built >= 1 then st.firstHeavyAt = st.firstHeavyAt or elapsed end
	return built >= 2 or (st.firstHeavyAt ~= nil and elapsed - st.firstHeavyAt >= (cfg.HeavyWait or 300))
end

-- the heavy weapons' shots together cost more than the storage holds
function CAI_StorageShort()
	local v = CAI_Defaults.SocketVolley
	if type(GetDeviceCountSide) ~= "function" then return false end
	local side = CAI_Side(teamId)
	local need, batteries = 0, 0
	for i = 0, GetDeviceCountSide(side) - 1 do
		local id = GetDeviceIdSide(side, i)
		if CAI_IsOwnDevice(id) then
			local t = GetDeviceType(id)
			need = need + (v.EnergyShot[t] or 0)
			if t == "battery" then batteries = batteries + 1 end
		end
	end
	return need > 0 and need + v.Margin > v.BaseStorage + v.Battery * batteries
end

function CAI_UpdateModules()
	local mods = data.CAIModules
	if mods == nil or type(data.fortIndex) ~= "number" or Fort == nil then return end
	local elapsed = data.CAI and data.CAI.ticks * Strategy.ThinkInterval or 0
	local seen, progress
	local fired = {}
	for _, m in ipairs(mods.list) do
		if m.fired then fired[m.name] = true end
	end
	local ready = {}
	for _, m in ipairs(mods.list) do
		local tr = m.trigger
		-- Repeat = n, Cooldown = s (Bastion): a module may go in up to n more times, each Cooldown seconds after the
		-- last, while its trigger still holds (e.g. a zone's reinforcement while that zone keeps being hit)
		local again = m.fired and (m.done or 0) < m.repeats and elapsed - (m.firedAt or 0) >= m.cooldown
		if (not m.fired or again) and (tr.After == nil or fired[tr.After]) then
			seen = seen or CAI_EnemyDevices()
			local hits, total = {}, 0
			for _, t in ipairs(tr.Types or {}) do
				if seen[t] then
					hits[#hits + 1] = t .. ":" .. seen[t]
					total = total + seen[t]
				end
			end
			local why
			-- Branch: the module of the other branch only from a surplus, once the first branch's is in
			local otherBranch = tr.Branch and data.CAI and data.CAI.techBranch and tr.Branch ~= data.CAI.techBranch
			local zoneSum = tr.Zone and data.CAI and data.CAI.zoneTotal and data.CAI.zoneTotal[tr.Zone] or 0
			if otherBranch then
				local first = false
				for _, o in ipairs(mods.list) do
					if o.trigger.Branch == data.CAI.techBranch and o.fired then first = true end
				end
				-- and only after the first heavy weapons (test 11: at 460 s, with the first plant still under construction)
				why = first and CAI_HeavyDone(elapsed) and CAI_SurplusReason(m, elapsed) or nil
			elseif #hits > 0 and total >= (tr.Count or 1) then
				why = table.concat(hits, ",")
			elseif tr.Postures and data.CAI and data.CAI.posture and CAI_ListHas(tr.Postures, data.CAI.posture) then
				-- Postures = { ... } (Bastion): while the AI holds one of them
				why = "posture:" .. data.CAI.posture
			elseif tr.Zone and zoneSum - (m.zoneMark or 0) >= (tr.Damage or 300) then
				-- Zone = <name>, Damage = n: that much damage in the zone since the module last went in
				why = "zone:" .. tr.Zone .. "=" .. CAI_Round(zoneSum - (m.zoneMark or 0))
			elseif tr.Time and elapsed >= tr.Time then
				why = "time:" .. tr.Time
			elseif tr.Storage and CAI_StorageShort() then
				why = "storage"
			elseif tr.Heavy and CAI_HeavyCount() >= tr.Heavy then
				why = "heavy:" .. tr.Heavy
			elseif tr.HeavyBuilt and CAI_HeavyCount(true) >= tr.HeavyBuilt then
				why = "heavybuilt:" .. tr.HeavyBuilt
			else
				why = CAI_SurplusReason(m, elapsed)
			end
			-- Built (Bastion): not before that own device stands (the upgrade centre comes late, its upgrades must not overtake it)
			if tr.Tech then
				local own = CAI_OwnDevices(true)
				why = (own.munitions or own.factory) and (why or "tech") or nil
			end
			if why and tr.Built and not CAI_OwnDevices(true)[tr.Built] then why = nil end
			-- NoTech (buzzsaw): only while no plant for heavy weapons stands; after it the socket is the heavy weapon's
			if why and tr.NoTech then
				local own = CAI_OwnDevices(true)
				if own.munitions or own.factory then why = nil end
			end
			-- EnergyAbove: what can wait leaves the energy to the heavy weapons' shots (tests 20, 22: guns silent at 500-850 energy)
			if why and tr.EnergyAbove then
				local res = GetTeamResources(teamId)
				if not ((type(res) == "table" or type(res) == "userdata") and (res.energy or 0) >= tr.EnergyAbove) then why = nil end
			end
			if why and tr.Drawn and not (data.CAI and data.CAI.techBranch == tr.Drawn) then why = nil end
			-- a full storage opens it too: nothing is short
			if why and tr.HeavyDone and not CAI_HeavyDone(elapsed) then
				local capCfg = (Strategy.Socket or CAI_Defaults.Socket).Upgrade or CAI_Defaults.Socket.Upgrade
				if not CAI_AtCap(elapsed, capCfg.CapSeconds or 60) then why = nil end
			end
			-- Afford (Bastion): waits until 80 % of its devices' cost is there, so a dear device does not hold up the
			-- plan behind it (test 7: the munitions plant stood first in line at 177 energy, turbines waited, skipped at last)
			if why and tr.Afford and not CAI_ModuleAffordable(m) then
				if not m.affordWait then
					m.affordWait = true
					CAI_Log("MODULE_AFFORD " .. m.name .. " trigger=" .. why)
				end
				why = nil
			end
			if why then
				progress = progress or CAI_PlanProgress()
				if progress >= m.requires then
					if m.fired then m.done = (m.done or 0) + 1 end
					m.fired = true
					m.firedAt = elapsed
					if tr.Zone then m.zoneMark = zoneSum end
					fired[m.name] = true
					m.why = why
					ready[#ready + 1] = m
				elseif not m.waiting then
					m.waiting = true
					CAI_Log("MODULE_WAIT " .. m.name .. " trigger=" .. why .. " requires=" .. m.requires .. " now=" .. progress)
				end
			end
		end
	end
	if #ready == 0 then return end
	local fi = data.fortIndex
	local all = {}
	for _, m in ipairs(ready) do
		CAI_Log("MODULE " .. m.name .. " trigger=" .. m.why .. " at=" .. (fi + #all) .. " actions=" .. #m.actions
			.. ((m.done or 0) > 0 and (" repeat=" .. m.done) or ""))
		for _, name in ipairs(m.retire or {}) do pcall(CAI_SocketRetire, name) end
		if m.replace then pcall(CAI_ModuleReplace, m) end
		-- copies: the same module may go in again (Repeat), and the built-in AI keeps state per action
		for _, a in ipairs(m.actions) do
			local c = CAI_CopyAction(a)
			-- a socket that has moved on: a pending upgrade must not bring its old weapon back (test 7: B1 sold for a 20mm,
			-- then module sniper2 built the sniper as its precursor on the empty strut)
			local sk = c.Socket and data.CAI and data.CAI.sockets and data.CAI.sockets[c.Socket]
			if sk and sk.current and CAI_UpgradeOf[c.DeviceSaveName] ~= sk.current then c.DeviceSaveName = sk.current end
			all[#all + 1] = c
		end
	end
	CAI_InsertActions(fi, all)
end

-- Fire.AntiAirFirst: while the enemy has a device its anti-air should shoot down, these weapons only fire anti-air
-- (no offensive fire, like NoOffence); otherwise they also fire at the enemy fort. Log on every change:
-- FLAK_HOLD on threats=<type:n,...> | FLAK_HOLD off
function CAI_UpdateAntiAirFirst()
	local f = Strategy.Fire
	local st = data.CAI
	if type(f) ~= "table" or not f.Enabled or st == nil or st.noOffence == nil then return end
	local aa = f.AntiAirFirst or CAI_Defaults.Fire.AntiAirFirst
	if type(aa) ~= "table" then return end
	local seen = CAI_EnemyDevices()
	local hits = {}
	for t in pairs(aa.Threats or {}) do
		if seen[t] then hits[#hits + 1] = t .. ":" .. seen[t] end
	end
	table.sort(hits)
	local hold = #hits > 0
	if hold == (st.aaHold or false) then return end
	st.aaHold = hold
	for k in pairs(aa.Types or {}) do
		if hold then
			st.noOffence[k] = true
			if data.OffensiveFireProbability[k] ~= nil then data.OffensiveFireProbability[k] = 0 end
			if type(data.FireDuringRebuildProbability) == "table" and data.FireDuringRebuildProbability[k] ~= nil then
				data.FireDuringRebuildProbability[k] = 0
			end
		else
			st.noOffence[k] = nil
			if st.baseOff[k] ~= nil then data.OffensiveFireProbability[k] = st.baseOff[k] end
			local r = st.baseFire and st.baseFire.Rebuild and st.baseFire.Rebuild[k]
			if r ~= nil and type(data.FireDuringRebuildProbability) == "table" then
				data.FireDuringRebuildProbability[k] = CAI_Clamp(r * (f.RebuildFireFactor or 1), 0, 1)
			end
		end
	end
	CAI_Log("FLAK_HOLD " .. (hold and ("on threats=" .. table.concat(hits, ",")) or "off"))
end

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

	-- Build progress and safety valve: the built-in AI builds nothing new while a queued
	-- rebuild action keeps failing. If one hangs for too long, it is given up.
	local rebuildCount = 0
	st.rebuildSince = st.rebuildSince or {}
	-- If the AI is only waiting for metal, the clock stops: such actions are not
	-- "broken", they will be built as soon as there is enough metal again.
	local okRes, resNow = pcall(GetTeamResources, teamId)
	local metalNow = (okRes and resNow and resNow.metal) or 0
	-- "insufficient resources" only counts as waiting while metal is still rising: if it stays flat
	-- at a high level (e.g. at the storage cap, the action costs more than can ever be stored),
	-- waiting does not help and the clocks must run (otherwise the AI stalls for the rest of the match)
	if st.lastMetal ~= nil and metalNow <= st.lastMetal + 1 and metalNow >= Strategy.BuildSkipMinMetal then
		st.metalFlatTicks = (st.metalFlatTicks or 0) + 1
	else
		st.metalFlatTicks = 0
	end
	st.lastMetal = metalNow
	local capped = st.metalFlatTicks >= (Strategy.StarvedFlatTicks or 4)
	local starved = (data.ResourceStarved and not capped) or metalNow < Strategy.BuildSkipMinMetal
	local okH, errH = pcall(CAI_UpdateRebuildHold, elapsed)
	if not okH then CAI_Log("ERROR rebuild hold: " .. tostring(errH)) end
	if type(data.Rebuild) == "table" then
		for k in pairs(data.Rebuild) do
			rebuildCount = rebuildCount + 1
			local since = st.rebuildSince[k]
			if since ~= nil and (starved or CAI_RebuildClockStopped(Fort and Fort[k], resNow)) then
				st.rebuildSince[k] = since + Strategy.ThinkInterval
			elseif since == nil then
				st.rebuildSince[k] = elapsed
			elseif elapsed - since >= Strategy.RebuildGiveUpSeconds then
				data.Rebuild[k] = nil
				st.rebuildSince[k] = nil
				local a = Fort and Fort[k]
				-- the upgrade centre holds all upgrades back: it gets a new try later (test 11: given up, none in the whole match)
				if a and a.DeviceSaveName == "upgrade" then st.techRetry = { k = k, at = elapsed + (Strategy.TechRetrySeconds or 60) } end
				CAI_Log("GAVE_UP action " .. tostring(k) .. " type=" .. tostring(a and a.Type)
					.. " " .. tostring(a and (a.DeviceSaveName or a.MaterialSaveName)) .. " after " .. Strategy.RebuildGiveUpSeconds .. "s")
			end
		end
		for k in pairs(st.rebuildSince) do
			if not data.Rebuild[k] then st.rebuildSince[k] = nil end
		end
		if st.techRetry and elapsed >= st.techRetry.at and rebuildCount == 0 then
			if not CAI_OwnDevices().upgrade then
				data.Rebuild[st.techRetry.k] = true
				CAI_Log("RETRY action " .. st.techRetry.k .. " upgrade t=" .. elapsed)
			end
			st.techRetry = nil
		end
	end

	-- Second safety valve: if normal construction hangs on the same action although there is metal,
	-- the action is skipped (the built-in AI would otherwise wait forever).
	local fi = data.fortIndex
	if type(fi) == "number" and Fort and fi <= #Fort and CAI_Probe == nil then
		if st.buildIndex ~= fi or rebuildCount > 0 then
			-- new action, or construction is currently waiting for a rebuild: restart the clock
			if st.buildIndex ~= fi then st.buildHadRes = false end
			st.buildIndex = fi
			st.buildSince = elapsed
		else
			local okR, res = pcall(GetTeamResources, teamId)
			if okR and res and (res.metal or 0) >= Strategy.BuildSkipMinMetal then
				st.buildHadRes = true
			end
			-- (Bastion) a device waiting for energy is no hang (test 7: the munitions plant skipped after 90 s at 177 energy)
			local waitEnergy = false
			if CAI_Plan.sockets and okR and res and Fort[fi] and Fort[fi].DeviceSaveName and type(GetDeviceCost) == "function" then
				local okC, c = pcall(GetDeviceCost, Fort[fi].DeviceSaveName)
				waitEnergy = okC and c and (res.energy or 0) < (c.energy or 0)
			end
			if waitEnergy then
				st.buildSince = elapsed
			elseif st.buildHadRes and elapsed - st.buildSince >= Strategy.BuildSkipSeconds then
				local a = Fort[fi]
				CAI_Log("SKIPPED action " .. fi .. " type=" .. tostring(a and a.Type) .. " "
					.. tostring(a and (a.DeviceSaveName or a.MaterialSaveName)) .. " after " .. (elapsed - st.buildSince) .. "s")
				data.fortIndex = fi + 1
				st.buildIndex = fi + 1
				st.buildSince = elapsed
				st.buildHadRes = false
			end
		end
	end

	-- the devices waiting in the rebuild queue, in the order the built-in AI tries them (Vanilla-8 test 4: lost turbines
	-- not rebuilt for 80 s with 12 actions queued)
	local queued = {}
	if rebuildCount > 0 and Fort then
		for k = 1, #Fort do
			if data.Rebuild[k] and Fort[k].Type == CREATE_DEVICE and #queued < 8 then
				queued[#queued + 1] = tostring(Fort[k].DeviceSaveName)
			end
		end
	end
	local parts = { "THINK t=" .. elapsed .. " build=" .. tostring(data.fortIndex) .. "/" .. tostring(Fort and #Fort) .. " rebuild=" .. rebuildCount
		.. (#queued > 0 and ("[" .. table.concat(queued, ",") .. "]") or "") }
	local okP, errP = pcall(CAI_UpdatePosture, elapsed)
	if not okP then CAI_Log("ERROR posture: " .. tostring(errP)) end
	if data.CAI then pcall(CAI_NotePeaks, data.CAI) end
	okP, errP = pcall(CAI_SocketUpgrade, elapsed)
	if not okP then CAI_Log("ERROR socket upgrade: " .. tostring(errP)) end
	okP, errP = pcall(CAI_SocketRefill, elapsed)
	if not okP then CAI_Log("ERROR socket refill: " .. tostring(errP)) end
	okP, errP = pcall(CAI_FrontStrip, elapsed)
	if not okP then CAI_Log("ERROR front strip: " .. tostring(errP)) end
	okP, errP = pcall(CAI_LogCombat, elapsed)
	if not okP then CAI_Log("ERROR combat log: " .. tostring(errP)) end
	local ok, res = pcall(CAI_UpdateTargets)
	parts[#parts + 1] = ok and res or ("ERROR targets: " .. tostring(res))
	ok, res = pcall(CAI_UpdateAggression, elapsed)
	parts[#parts + 1] = ok and res or ("ERROR aggression: " .. tostring(res))
	ok, res = pcall(CAI_UpdateAntiAir)
	parts[#parts + 1] = ok and res or ("ERROR anti-air: " .. tostring(res))
	parts[#parts + 1] = "fire=" .. tostring(st.fireAttempts or 0)
	st.fireAttempts = 0
	CAI_Log(table.concat(parts, " "))

	local okA, errA = pcall(CAI_UpdateAntiAirFirst)
	if not okA then CAI_Log("ERROR anti-air first: " .. tostring(errA)) end

	local okZ, errZ = pcall(CAI_UpdateZones, elapsed)
	if not okZ then CAI_Log("ERROR zones: " .. tostring(errZ)) end

	if CAI_Probe == nil then
		local okM, errM = pcall(CAI_UpdateModules)
		if not okM then CAI_Log("ERROR modules: " .. tostring(errM)) end
	end

	local okE, errE = pcall(CAI_EngineProbeTick, elapsed)
	if not okE then CAI_Log("ERROR engine probe: " .. tostring(errE)) end

	-- shape snapshot once per game minute (see CAI_LogShape)
	if elapsed >= (st.nextShape or 60) then
		st.nextShape = elapsed + 60
		local okS, errS = pcall(CAI_LogShape, "minute")
		if not okS then CAI_Log("ERROR shape diagnostics: " .. tostring(errS)) end
	end

	-- CS_UNSTABLE probe (testing only): once the plan is finished, or after Probe.At seconds
	local probe = FortPlanConfig and FortPlanConfig.Probe
	-- AtOnly: not before At even if the plan is done (Vanilla-8's plan ends before its plant stands)
	if probe and CAI_Probe == nil and (elapsed >= (probe.At or math.huge)
			or (not probe.AtOnly and Fort and type(fi) == "number" and fi > #Fort)) then
		local okP, errP = pcall(CAI_ProbeStart, elapsed)
		if not okP then
			CAI_Log("ERROR probe: " .. tostring(errP))
			if CAI_Probe and CAI_Probe.wasDisabled ~= nil then data.Disable = CAI_Probe.wasDisabled end
			CAI_Probe = { done = true }
		end
	end

	ScheduleCall(Strategy.ThinkInterval, CAI_Think)
end

--------------------------------------------------------------------------------
-- Hooking into the events of the built-in AI

local CAI_BaseLoad = Load
function Load(gameStart)
	local okSwap, errSwap = pcall(CAI_TrySwapPlan, "Load")
	if not okSwap then Log("[CAI] PLAN-ERROR " .. tostring(errSwap)) end
	CAI_BaseLoad(gameStart)
	local okX, errX = pcall(CAI_ExtractModules)
	if not okX then Log("[CAI] ERROR modules: " .. tostring(errX)) end
	-- Assist AI on the side of a human player (e.g. anti-air assistant): do not touch
	if data.HumanAssist then
		CAI_PlanNote("ASSIST FORT 9000 AI inactive (assist AI of a player)")
		return
	end
	local ok, err = pcall(CAI_Init)
	if not ok then
		Log("[CAI] ERROR in init: " .. tostring(err))
		return
	end
	local okT, tempo = pcall(CAI_ApplyTempo)
	CAI_Log("TEMPO " .. tostring(tempo))
	local okF, fire = pcall(CAI_ApplyFire)
	CAI_Log("FIRE " .. tostring(fire))
	local okL, logging = pcall(CAI_InstallBuildLogging)
	CAI_Log("DEBUG-HOOKS " .. tostring(logging))
	if ScheduledCallCountOfFunc(CAI_Think) == 0 then
		ScheduleCall(Strategy.ThinkInterval, CAI_Think)
	end
end

-- The game only turns an AI into a player's assist AI (anti-air assistant) AFTER Load().
-- Then switch off the FORT 9000 AI and reset the changed values.
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
	CAI_PlanNote("ASSIST FORT 9000 AI inactive (assist AI of a player)")
end

local CAI_BaseOnWeaponFired = OnWeaponFired
function OnWeaponFired(weaponTeamId, saveName, weaponId, projectileNodeId, projectileNodeIdFrom)
	CAI_BaseOnWeaponFired(weaponTeamId, saveName, weaponId, projectileNodeId, projectileNodeIdFrom)
	local st = data.CAI
	if st == nil then
		return
	end
	-- own smoke shell: rockets may follow (Fire.SmokeCover)
	if CAI_Side(weaponTeamId) == CAI_Side(teamId) and st.smokeCover and st.smokeCover.Smoke[saveName] and st.fireClock then
		st.lastSmoke = st.fireClock
		st.rocketHoldSince = nil
		st.smokeShots = (st.smokeShots or 0) + 1
		return
	end
	if weaponTeamId == teamId then
		local v = st.volley
		if v and v.Classes and v.Classes[saveName] then
			st.volleyClass, st.volleyClassAt = v.Classes[saveName], st.fireClock or 0
			st.volleyFired = st.volleyFired or {}
			st.volleyFired[weaponId] = true
		end
		st.ownShots = st.ownShots or {}
		st.ownShots[saveName] = (st.ownShots[saveName] or 0) + 1
		if st.buzzsaw and st.buzzsaw.types[saveName] then
			st.buzzsaw.blades[weaponId] = (st.buzzsaw.blades[weaponId] or 0) + 1
		end
		if type(projectileNodeId) == "number" and projectileNodeId > 0 then
			if (st.ownProjCount or 0) > 400 then
				st.ownProj, st.ownProjCount = {}, 0
			end
			st.ownProj = st.ownProj or {}
			st.ownProj[projectileNodeId] = saveName
			st.ownProjCount = (st.ownProjCount or 0) + 1
		end
	end
	if CAI_Side(weaponTeamId) ~= enemyTeamId then
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
	if st and projectileTeamId == teamId and CAI_Side(deviceTeamId) == enemyTeamId then
		pcall(CAI_NoteDealt, "dev", st.ownProj and st.ownProj[projectileNodeId] or "?", saveName, pos)
	end
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

--------------------------------------------------------------------------------
-- Zones (Bastion, .dev/docs/bastion-plan.md): FortZones are boxes in plan coordinates (team 1). At the plan swap,
-- before any transform, every node the plan names gets its zone by its planned position (CAI_Plan.nodeZone, by
-- original id); a hit node's zone is found through the reverse of data.OriginalToActual.

local function CAI_InBox(p, b)
	return p and type(p.x) == "number" and p.x >= b.x0 and p.x <= b.x1 and p.y >= b.y0 and p.y <= b.y1
end

function CAI_MapZones(plan)
	local zones = type(plan.FortZones) == "table" and plan.FortZones or nil
	CAI_Plan.nodeZone = nil
	if zones == nil then return end
	local map, n = {}, 0
	local function Note(id, p)
		if type(id) ~= "number" or map[id] then return end
		for _, z in ipairs(zones) do
			if CAI_InBox(p, z.Box) then map[id] = z.Name; n = n + 1; return end
		end
	end
	local function Scan(actions)
		for _, a in ipairs(actions or {}) do
			Note(a.OriginalNodeAId, a.PosA)
			Note(a.OriginalNodeBId, a.NewNodePos or a.PosB)
		end
	end
	Scan(plan.Fort)
	for _, m in ipairs(type(plan.FortModules) == "table" and plan.FortModules or {}) do Scan(m.Actions) end
	CAI_Plan.nodeZone = map
	CAI_PlanNote("ZONES-MAP zones=" .. #zones .. " nodes=" .. n)
end

-- the zone of an actual node id (nil if none)
function CAI_ZoneOfNode(actual)
	local st, map = data.CAI, CAI_Plan.nodeZone
	if st == nil or map == nil or type(actual) ~= "number" then return nil end
	local orig = st.a2o and st.a2o[actual]
	if orig == nil and st.a2oTick ~= st.ticks then
		st.a2oTick = st.ticks
		st.a2o = {}
		for o, a in pairs(data.OriginalToActual or {}) do st.a2o[a] = o end
		orig = st.a2o[actual]
	end
	return orig and map[orig]
end

function CAI_ZoneDamage(nodeA, nodeB, amount)
	local st = data.CAI
	if st == nil or CAI_Plan.nodeZone == nil then return end
	local z = CAI_ZoneOfNode(nodeA) or CAI_ZoneOfNode(nodeB)
	if z == nil then return end
	st.zoneDmg = st.zoneDmg or {}
	st.zoneTotal = st.zoneTotal or {}
	st.zoneDmg[z] = (st.zoneDmg[z] or 0) + amount
	st.zoneTotal[z] = (st.zoneTotal[z] or 0) + amount
end

-- each think step: decay the pressure, log it now and then
function CAI_UpdateZones(elapsed)
	local st = data.CAI
	if st == nil or st.zoneDmg == nil then return end
	local cfg = Strategy.Zone or CAI_Defaults.Zone
	local keys = {}
	for z, v in pairs(st.zoneDmg) do
		st.zoneDmg[z] = v * (cfg.Decay or 0.9)
		keys[#keys + 1] = z
	end
	if elapsed >= (st.nextZoneLog or 0) and #keys > 0 then
		st.nextZoneLog = elapsed + (cfg.LogEvery or 30)
		table.sort(keys)
		local parts = {}
		for _, z in ipairs(keys) do
			parts[#parts + 1] = z .. ":" .. CAI_Round(st.zoneDmg[z]) .. "/" .. CAI_Round(st.zoneTotal[z])
		end
		CAI_Log("ZONES t=" .. elapsed .. " " .. table.concat(parts, " ") .. " (pressure/total)")
	end
end

--------------------------------------------------------------------------------
-- Sockets (Bastion, .dev/docs/bastion-plan.md): the plan's FortSockets name its weapon places; every device action in
-- one carries Socket = "<name>" (gen_fort.py tag_sockets). A socket that keeps losing its weapon gets the next of its
-- Loadouts (checked by rules.py in that place) whose tech stands: the rebuild action's device is swapped, so the
-- empty socket is rebuilt with the other weapon (no reclaim: a reclaim refunds only half and empties the socket ~5 s).

CAI_UpgradeOf = { sniper2 = "sniper", minigun = "machinegun", mortar2 = "mortar",
	shotgun = "flak", rocket = "rocketemp", missile2 = "missile", missile2inv = "missileinv" }

function CAI_InitSockets()
	local list = CAI_Plan.sockets
	if type(list) ~= "table" or data.CAI == nil then return end
	local st = data.CAI
	st.sockets = {}
	local names = {}
	for _, s in ipairs(list) do
		st.sockets[s.Name] = { kind = s.Kind, loadouts = s.Loadouts or { s.Default }, needs = s.Needs or {}, losses = {}, swaps = 0,
			upgrade = s.Upgrade, rank = s.Rank or 1, default = s.Default }
		names[#names + 1] = s.Name .. ":" .. table.concat(s.Loadouts or { tostring(s.Default) }, "/")
	end
	CAI_Log("SOCKETS " .. table.concat(names, " "))
	-- the match's first tech branch: chance (the player, 05.11.2026). Guns: munitions plant, 20mm and cannon. Beams: factory
	st.techBranch = GetRandomInteger(1, 2, "CAI techBranch") == 1 and "guns" or "beams"
	CAI_Log("TECH first=" .. st.techBranch)
	CAI_InitSniperSight()
end

-- Sniper sight: see CAI_Defaults.SniperSight. The built-in AI's first search accepts any enemy strut in the line
-- (needLineToStructure), so a sniper fires at a closed door in front of its target. WeaponFireBlockedByStructure drops
-- that; CAI_SniperTarget (WeaponFindTargetFunction) looks first, also above the device's centre. A shot is worth
-- taking when it comes, so the fire chance is 1. Nothing visible: no shot and no own door opened.
function CAI_InitSniperSight()
	local cfg = Strategy.SniperSight or CAI_Defaults.SniperSight
	local st = data.CAI
	if not (cfg and cfg.Enabled) or type(CastRayFromDevice) ~= "function" then return end
	st.sniperSight = { seen = 0, pierced = 0, hold = 0 }
	for w, hp in pairs(cfg.Hitpoints) do
		WeaponFireBlockedByStructure[w] = true
		WeaponFindTargetFunction[w] = "CAI_SniperTarget"
		data.ProjectileHitpoints[w] = hp
		data.OffensiveFireProbability[w] = 1
		st.baseOff[w] = 1
	end
end

function CAI_SniperTarget(weaponId, weaponPos, sideDevices)
	local st = data.CAI
	local cfg = Strategy.SniperSight or CAI_Defaults.SniperSight
	local w = GetDeviceType(weaponId)
	local hp = cfg.Hitpoints[w] or 0
	local flags = RAY_EXCLUDE_CONSTRUCTION + RAY_ALLIED_BG_BLOCKS + RAY_EXCLUDE_DYNAMIC_TERRAIN   -- separate bits
	local function hits(pos, through)
		local hit = CastRayFromDevice(weaponId, pos, through, flags, 0)
		if not (GetRayHitSideId() == enemyTeamId and (hit == RAY_HIT_WEAPON or hit == RAY_HIT_DEVICE)) then return false end
		local at = GetRayHitPosition()
		local dx, dy = at.x - pos.x, at.y - pos.y
		return dx * dx + dy * dy <= cfg.Near * cfg.Near
	end
	local prio = data.CustomWeaponPriorities[w] or data.SmallArmsPrioritiesOverride or SmallArmsPriorities
	for _, kind in ipairs(prio) do
		for _, id in ipairs(kind ~= "sandbags" and sideDevices[kind] or {}) do
			if not IsCloaked(id) then
				local c = GetDeviceCentrePosition(id)
				for _, up in ipairs(cfg.AimUp) do
					local pos = Vec3()
					pos.x, pos.y = c.x, c.y - up
					if hits(pos, 0) then
						st.sniperSight.seen = st.sniperSight.seen + 1
						return pos
					elseif hp > 0 and hits(pos, hp) then
						st.sniperSight.pierced = st.sniperSight.pierced + 1
						return pos
					end
				end
			end
		end
	end
	st.sniperSight.hold = st.sniperSight.hold + 1
	return nil
end

-- Buzzsaw: see CAI_Defaults.Buzzsaw. WeaponFireBlockedByStructure and an empty priority list with no structure attempts
-- leave CAI_BuzzsawTarget the only way to a target: nothing worth its three volleys, no shot.
--   BUZZSAW sight <type> <id> near|far material=<m> at=<x>,<y>     (once per target device)
--   BUZZSAW lost <id> action=<k> blades=<n> volleys=<v> spent=<0|1> rearm=<r>/<max> tech=<0|1> -> rebuild|drop
function CAI_InitBuzzsaw()
	local cfg = Strategy.Buzzsaw or CAI_Defaults.Buzzsaw
	local st = data.CAI
	if not (cfg and cfg.Enabled) or st == nil then return end
	st.buzzsaw = { types = cfg.Types, blades = {}, rearms = {}, seen = {}, found = 0, hold = 0 }
	if type(CastRayFromDevice) ~= "function" then return end
	for w in pairs(cfg.Types) do
		WeaponFireBlockedByStructure[w] = true
		WeaponFindTargetFunction[w] = "CAI_BuzzsawTarget"
		data.CustomWeaponPriorities[w] = {}
		if data.WeaponTargetStructureAttempts then data.WeaponTargetStructureAttempts[w] = 0 end
	end
end

function CAI_BuzzsawTarget(weaponId, weaponPos, sideDevices)
	local st = data.CAI
	local cfg = Strategy.Buzzsaw or CAI_Defaults.Buzzsaw
	local b = st and st.buzzsaw
	if b == nil then return nil end
	local flags = RAY_EXCLUDE_CONSTRUCTION + RAY_ALLIED_BG_BLOCKS + RAY_EXCLUDE_DYNAMIC_TERRAIN   -- separate bits
	-- the ray's first hit: enemy wood, and how far from the point aimed at
	local function wood(pos)
		local hit = CastRayFromDevice(weaponId, pos, 0, flags, 0)
		if hit ~= RAY_HIT_STRUCTURE or GetRayHitSideId() ~= enemyTeamId then return nil end
		local mat = GetRayHitMaterialSaveName and GetRayHitMaterialSaveName()
		if not (mat and cfg.Wood[mat]) then return nil end
		local at = GetRayHitPosition()
		local dx, dy = at.x - pos.x, at.y - pos.y
		return math.sqrt(dx * dx + dy * dy), mat, at
	end
	local function sight(kind, id, how, mat, at)
		b.found = b.found + 1
		if not b.seen[id] then
			b.seen[id] = true
			CAI_Log("BUZZSAW sight " .. kind .. " " .. id .. " " .. how .. " material=" .. mat .. " at=" .. CAI_Round(at.x) .. "," .. CAI_Round(at.y))
		end
	end
	local far
	for _, kind in ipairs(cfg.Targets) do
		for _, id in ipairs(sideDevices[kind] or {}) do
			if not IsCloaked(id) then
				-- the platform point first (the strut the device stands on), then its centre
				for _, pos in ipairs({ GetDevicePosition(id), GetDeviceCentrePosition(id) }) do
					local d, mat, at = wood(pos)
					if d and d <= cfg.Near then
						sight(kind, id, "near", mat, at)
						return pos
					elseif d and d <= cfg.Far and far == nil then
						far = { pos = pos, kind = kind, id = id, mat = mat, at = at }
					end
				end
			end
		end
	end
	if far then
		sight(far.kind, far.id, "far", far.mat, far.at)
		return far.pos
	end
	b.hold = b.hold + 1
	return nil
end

-- QueueDeviceRebuild of a buzzsaw: "rearm" (rebuild it), "drop" (not again) or nil (not a buzzsaw)
function CAI_BuzzsawLost(deviceId)
	local st = data.CAI
	local b = st and st.buzzsaw
	local k = data.Devices and data.Devices[deviceId]
	local a = k and Fort and Fort[k]
	if b == nil or a == nil or not b.types[a.DeviceSaveName] then return nil end
	local cfg = Strategy.Buzzsaw or CAI_Defaults.Buzzsaw
	local blades = b.blades[deviceId] or 0
	b.blades[deviceId] = nil
	local per = 3
	if type(GetWeaponTypeRoundsEachBurst) == "function" then
		local ok, n = pcall(GetWeaponTypeRoundsEachBurst, a.DeviceSaveName, teamId)
		if ok and type(n) == "number" and n >= 1 then per = n end
	end
	local volleys = math.ceil(blades / per)
	local own = CAI_OwnDevices(true)
	local tech = (own.munitions or own.factory) and true or false
	local done = b.rearms[k] or 0
	local rearm = done < (cfg.Rearm or 0) and not (cfg.RearmNoTech and tech)
	CAI_Log("BUZZSAW lost " .. deviceId .. " action=" .. k .. " blades=" .. blades .. " volleys=" .. volleys
		.. " spent=" .. (volleys >= (cfg.Volleys or 3) and 1 or 0) .. " rearm=" .. done .. "/" .. tostring(cfg.Rearm or 0)
		.. " tech=" .. (tech and 1 or 0) .. " -> " .. (rearm and "rebuild" or "drop"))
	if rearm then
		b.rearms[k] = done + 1
		return "rearm"
	end
	-- out of the socket: a refill or a swap must not build another weapon in its place (the buzzsaw's LinkT)
	local s = a.Socket and st.sockets and st.sockets[a.Socket]
	if s and s.current == a.DeviceSaveName then s.current = nil end
	a.Socket = nil
	if data.Rebuild then data.Rebuild[k] = nil end
	return "drop"
end

-- A device of this AI's own team, not an ally's: the side's list holds all its teams, and the game asks each team for its own
-- plant (2v6, 06.11.2026: T502 drew beams, took T302's munitions plant for its own, was refused the cannon and the 20mm with
-- CS_PREQUISITENOTMET and never got a heavy weapon)
function CAI_IsOwnDevice(id)
	return type(GetDeviceTeamIdActual) ~= "function" or GetDeviceTeamIdActual(id) == teamId
end

-- own devices by type (game state, deterministic); builtOnly: only those fully built (a factory under construction does
-- not allow a laser yet: the rebuild would wait for it with the socket empty)
function CAI_OwnDevices(builtOnly)
	local count, side = {}, CAI_Side(teamId)
	for i = 0, GetDeviceCountSide(side) - 1 do
		local id = GetDeviceIdSide(side, i)
		local t = GetDeviceType(id)
		if t and CAI_IsOwnDevice(id) and (not builtOnly or type(IsDeviceFullyBuilt) ~= "function" or IsDeviceFullyBuilt(id)) then
			count[t] = (count[t] or 0) + 1
		end
	end
	return count
end

-- the socket's weapon from now on: every action of the socket names it (an upgrade action left over would build its
-- precursor on the empty strut), and modules not yet in follow (CAI_UpdateModules)
function CAI_SocketSet(name, w)
	local s = data.CAI.sockets[name]
	s.current = w
	for _, a in ipairs(Fort) do
		if a.Socket == name and a.Type == CREATE_DEVICE then a.DeviceSaveName = w end
	end
end

-- called when the built-in AI queues a lost device for rebuilding: true if the socket's action was swapped
function CAI_SocketLost(deviceId)
	local st = data.CAI
	local k = data.Devices and data.Devices[deviceId]
	local a = k and Fort and Fort[k]
	if st == nil or st.sockets == nil or a == nil or a.Socket == nil then return false end
	local s = st.sockets[a.Socket]
	if s == nil then return false end
	-- the socket's own sale (CAI_SocketUpgrade): the action already names the new weapon
	if s.selling ~= nil and s.selling == deviceId then
		s.selling = nil
		s.losses = {}
		if st.rebuilds then st.rebuilds[k] = nil end
		CAI_Log("SOCKET " .. a.Socket .. " sold, rebuild as " .. tostring(a.DeviceSaveName) .. " action=" .. k)
		return true
	end
	local cfg = Strategy.Socket or CAI_Defaults.Socket
	local now = st.ticks * Strategy.ThinkInterval
	local last = s.losses[#s.losses]
	if last ~= nil and now - last > (cfg.Window or 180) then s.losses = {} end
	s.losses[#s.losses + 1] = now
	local old = a.DeviceSaveName
	if #s.losses < (cfg.SwapAfter or 2) then
		CAI_Log("SOCKET " .. a.Socket .. " lost " .. tostring(old) .. " losses=" .. #s.losses)
		return false
	end
	-- the next loadout after the current one (its base type for an upgrade), whose tech stands
	local base = CAI_UpgradeOf[old] or old
	local n, at = #s.loadouts, 0
	for i, d in ipairs(s.loadouts) do
		if d == base then at = i end
	end
	local own = CAI_OwnDevices(true)
	-- the posture's preferred loadouts first (Bastion), then the socket's own order
	local order = {}
	local pcfg = Strategy.Posture or CAI_Defaults.Posture
	local pref = st.posture and pcfg.Prefer and pcfg.Prefer[st.posture] and pcfg.Prefer[st.posture][s.kind] or {}
	for _, d in ipairs(pref) do
		for _, l in ipairs(s.loadouts) do
			if l == d then order[#order + 1] = d end
		end
	end
	-- a socket with Upgrade: its order of worth first (test 9: the loadout order made every swap a 20mm)
	for _, d in ipairs(s.upgrade or {}) do order[#order + 1] = d end
	for j = 1, n - 1 do order[#order + 1] = s.loadouts[(at + j - 1) % n + 1] end
	for _, d in ipairs(order) do
		local need = s.needs[d]
		-- a weapon that never fires at the enemy fort (Fire.NoOffence: the machine gun) only replaces a weapon that
		-- does while the AI holds AntiAir (test 2, 03.11.2026: B1's sniper became a machine gun and its offence was gone)
		local passive = st.noOffence and st.noOffence[d] and not (st.noOffence[base]) and st.posture ~= "AntiAir"
		-- a heavy weapon lost does not fall back to the small default (test 8: B1 cannon20mm->sniper): it is rebuilt
		local downgrade = s.upgrade and CAI_ListHas(s.upgrade, base) and (d == "sniper" or d == "sniper2")
		if d ~= base and not passive and not downgrade and (need == nil or (own[need] or 0) > 0) and CAI_Affordable(st, d) then
			CAI_SocketSet(a.Socket, d)
			s.losses = {}
			s.swaps = s.swaps + 1
			if st.rebuilds then st.rebuilds[k] = nil end
			CAI_Log("SOCKET " .. a.Socket .. " " .. tostring(old) .. "->" .. d .. " action=" .. k .. " swaps=" .. s.swaps
				.. " posture=" .. tostring(st.posture))
			return true
		end
	end
	CAI_Log("SOCKET " .. a.Socket .. " lost " .. tostring(old) .. " losses=" .. #s.losses .. " no other loadout ready")
	return false
end

-- can the AI ever pay for a weapon? The game takes the whole cost when a device is placed, so a weapon dearer than
-- the storage (the highest metal / energy seen this match, ~900-990 metal on Vanilla) never gets built (Vanilla-8
-- test 4, 03.11.2026: two sold snipers and a lost AP sniper became lasers, 1000 metal, and the sockets stayed empty;
-- the game's "not enough resources" is logged as CS_OCCUPIED). Margin: a little below the peak.
function CAI_Affordable(st, w)
	if type(GetDeviceCost) ~= "function" then return true end
	local ok, c = pcall(GetDeviceCost, w)
	if not ok or c == nil then return true end
	local cm, ce = c.metal or 0, c.energy or 0
	-- the storage: what stands, or the most seen (a second store holds 1200 long before the metal gets there: a cannon,
	-- 900 metal, would stay out of reach)
	local own = CAI_OwnDevices(true)
	local v = CAI_Defaults.SocketVolley
	local capM = math.max(st.metalPeak or 0, v.BaseMetal + v.Store * (own.store or 0))
	local capE = math.max(st.energyPeak or 0, v.BaseStorage + v.Battery * (own.battery or 0))
	return cm <= capM - 20 and ce <= capE - 100, cm, ce
end

-- highest metal and energy seen this match: the storage the AI can save up to
function CAI_NotePeaks(st)
	local res = GetTeamResources(teamId)
	if not (type(res) == "table" or type(res) == "userdata") then return 0, 0 end
	local m, e = res.metal or 0, res.energy or 0
	st.metalPeak = math.max(st.metalPeak or 0, m)
	st.energyPeak = math.max(st.energyPeak or 0, e)
	return m, e
end

-- the socket's weapons in the order to try: the posture's Prefer first, then the list's own order
function CAI_SocketOrder(s, list)
	local st = data.CAI
	local pcfg = Strategy.Posture or CAI_Defaults.Posture
	local pref = st.posture and pcfg.Prefer and pcfg.Prefer[st.posture] and pcfg.Prefer[st.posture][s.kind] or {}
	local order, seen = {}, {}
	for _, d in ipairs(pref) do
		for _, l in ipairs(list) do
			if l == d and not seen[d] then order[#order + 1] = d; seen[d] = true end
		end
	end
	for _, l in ipairs(list) do
		if not seen[l] then order[#order + 1] = l; seen[l] = true end
	end
	return order
end

-- An empty socket whose rebuild was given up gets a new try (CAI_Defaults.Socket: RefillAfter, RefillEvery).
-- Logs SOCKET <name> refill <weapon> action=<k> tries=<n>.
function CAI_SocketRefill(elapsed)
	local st = data.CAI
	if st == nil or st.sockets == nil or Fort == nil or data.Devices == nil or data.Rebuild == nil then return end
	local cfg = Strategy.Socket or CAI_Defaults.Socket
	local alive = {}
	for id, k in pairs(data.Devices) do
		local a = Fort[k]
		if a and a.Socket and GetDeviceType(id) then alive[a.Socket] = true end
	end
	local queued, last = {}, {}
	for k = 1, math.min(#Fort, (data.fortIndex or 1) - 1) do
		local a = Fort[k]
		if a.Socket and a.Type == CREATE_DEVICE then
			last[a.Socket] = k
			if data.Rebuild[k] then queued[a.Socket] = true end
		end
	end
	local names = {}
	for name, s in pairs(st.sockets) do
		if s.upgrade then names[#names + 1] = name end
	end
	table.sort(names)
	local m, e = CAI_NotePeaks(st)
	local own
	for _, name in ipairs(names) do
		local s, k = st.sockets[name], last[name]
		if alive[name] or queued[name] or s.selling or k == nil then
			s.emptySince = nil
		else
			s.emptySince = s.emptySince or elapsed
			if elapsed - s.emptySince >= (cfg.RefillAfter or 45) and elapsed - (s.refillAt or -1e9) >= (cfg.RefillEvery or 130) then
				own = own or CAI_OwnDevices(true)
				local list = {}
				for _, w in ipairs(s.upgrade) do list[#list + 1] = w end
				if s.default then list[#list + 1] = s.default end
				local ready = {}
				for _, w in ipairs(CAI_SocketOrder(s, list)) do
					local need = s.needs[w]
					local can, cm, ce = CAI_Affordable(st, w)
					if (need == nil or (own[need] or 0) > 0) and can and m >= (cm or 0) * 0.8 and e >= (ce or 0) * 0.8 then
						ready[#ready + 1] = w
					end
				end
				if #ready > 0 then
					s.refills = (s.refills or 0) + 1
					s.refillAt = elapsed
					local w = ready[(s.refills - 1) % #ready + 1]
					CAI_SocketSet(name, w)
					data.Rebuild[k] = true
					if data.Frustration then data.Frustration[k] = nil end
					if st.rebuilds then st.rebuilds[k] = nil end
					CAI_Log("SOCKET " .. name .. " refill " .. w .. " action=" .. k .. " tries=" .. s.refills)
				end
			end
		end
	end
end

-- RebuildHold: see CAI_Defaults.RebuildHold. st.rebuildHold is the second the hold began; logs REBUILD_HOLD on, free, off.
function CAI_UpdateRebuildHold(elapsed)
	local st = data.CAI
	if st == nil or Fort == nil or not CAI_Plan.sockets then return end
	local waiting
	for k in pairs(data.Rebuild or {}) do
		local a = Fort[k]
		if a and a.Socket and CAI_Defaults.SocketVolley.EnergyShot[a.DeviceSaveName] then waiting = a.DeviceSaveName; break end
	end
	local cfg = CAI_Defaults.RebuildHold
	local function note(what)
		local res = GetTeamResources(teamId)
		CAI_Log("REBUILD_HOLD " .. what .. " t=" .. elapsed .. " m=" .. math.floor(res.metal or 0) .. " e=" .. math.floor(res.energy or 0)
			.. " for=" .. tostring(waiting))
	end
	if not waiting then
		if st.rebuildHold then st.rebuildHold = nil; note("off") end
		st.rebuildHoldFree = nil
	elseif st.rebuildHold then
		if elapsed - st.rebuildHold >= cfg.MaxSeconds then
			st.rebuildHold = nil
			st.rebuildHoldFree = elapsed + cfg.FreeSeconds
			note("free")
		end
	elseif not st.rebuildHoldFree or elapsed >= st.rebuildHoldFree then
		st.rebuildHold = elapsed
		st.rebuildHoldFree = nil
		note("on")
	end
end

-- During a hold no give-up clock runs for what waits by order, nor for a heavy weapon short of resources; one that could be paid for
-- and is not placed hangs for another reason, its clock runs
function CAI_RebuildClockStopped(a, res)
	if a == nil or not data.CAI.rebuildHold then return false end
	if CAI_Defaults.RebuildHold.Types[a.DeviceSaveName] then return true end
	if not (a.Socket and CAI_Defaults.SocketVolley.EnergyShot[a.DeviceSaveName]) or type(GetDeviceCost) ~= "function" or not res then return false end
	local ok, c = pcall(GetDeviceCost, a.DeviceSaveName)
	return ok and c and ((res.metal or 0) < (c.metal or 0) or (res.energy or 0) < (c.energy or 0)) or false
end

-- A heavy weapon refused (CS_UNSTABLE) for RefusedWait seconds: its queued rebuild is taken out, the built-in AI builds nothing new
-- while one hangs (test 11: 120 s at a time; C1 refused in tests 10-12). It comes back after ParkFor seconds (CAI_SocketRefill).
function CAI_ParkRefused(elapsed)
	local st = data.CAI
	local cfg = (Strategy.Socket or CAI_Defaults.Socket).Upgrade or CAI_Defaults.Socket.Upgrade
	if st.heavyRefused == nil or elapsed - st.heavyRefused < (cfg.RefusedWait or 30) then return end
	st.heavyRefused = nil
	for k in pairs(data.Rebuild or {}) do
		local q = Fort[k]
		local qs = q and q.Socket and st.sockets[q.Socket]
		if qs and qs.upgrade and CAI_Defaults.SocketVolley.EnergyShot[q.DeviceSaveName] then
			data.Rebuild[k] = nil
			qs.refillAt = elapsed + (cfg.ParkFor or 300) - ((Strategy.Socket or CAI_Defaults.Socket).RefillEvery or 130)
			CAI_Log("SOCKET " .. q.Socket .. " parked " .. tostring(q.DeviceSaveName) .. " t=" .. elapsed)
		elseif q and q.DeviceSaveName == "upgrade" then
			-- test 17: refused, it hung in the queue for 300 s and held new building back
			data.Rebuild[k] = nil
			st.techRetry = { k = k, at = elapsed + (cfg.ParkFor or 300) }
			CAI_Log("PARKED action " .. k .. " upgrade t=" .. elapsed)
		end
	end
end

-- Front strip: see CAI_Defaults.FrontStrip. FortStrip holds plan positions, not node ids: the game renumbers only the
-- ids in the plan's actions, and a starting-fort node is mapped only once an action has used it (first version, ids:
-- nothing happened, 04.11.2026). The nodes are found by position, x mirrored for a mirrored fort. Logs
-- STRIP <x>,<y>-<x>,<y> <old>-><new> result=<CreateLink> m=<before>-><after> t=<s>: what the swap really pays back, and
-- STRIP_SKIP once per reason when a strut cannot be swapped.
function CAI_StripNode(x, y)
	local px = CAI_FortMirrored and -x or x
	local f = CAI_Plan.stripFrame
	if f then
		px = f.real.x + (f.mirrored and -1 or 1) * (x - f.plan.x)
		y = f.real.y + y - f.plan.y
	end
	local best, bestD = nil, 25 * 25
	for i = 0, NodeCount(teamId) - 1 do
		local id = GetNodeId(teamId, i)
		local q = NodePosition(id)
		local d = (q.x - px) * (q.x - px) + (q.y - y) * (q.y - y)
		if d < bestD then best, bestD = id, d end
	end
	return best
end

-- See CAI_Defaults.BuildEnergyHold. Log: BUILD_HOLD on/off
function CAI_BuildHoldsFire(id)
	local st, cfg = data.CAI, Strategy.BuildEnergyHold or CAI_Defaults.BuildEnergyHold
	if st == nil or not (cfg and cfg.Enabled) or not cfg.Types[GetDeviceType(id)] or type(GetDeviceCost) ~= "function" then return false end
	local a = Fort and type(data.fortIndex) == "number" and Fort[data.fortIndex]
	local res = GetTeamResources(teamId)
	local short = false
	if a and a.DeviceSaveName and (type(res) == "table" or type(res) == "userdata") then
		local ok, c = pcall(GetDeviceCost, a.DeviceSaveName)
		short = ok and c and (res.energy or 0) < (c.energy or 0) and (res.metal or 0) >= 0.8 * (c.metal or 0)
	end
	local now = st.fireClock or 0
	if not short then
		if st.buildHoldSince then CAI_Log("BUILD_HOLD off") end
		st.buildHoldSince = nil
		return false
	end
	if st.buildHoldSince == nil then
		st.buildHoldSince = now
		CAI_Log("BUILD_HOLD on for=" .. tostring(a.DeviceSaveName) .. " m=" .. CAI_Round(res.metal or 0) .. " e=" .. CAI_Round(res.energy or 0))
	end
	local held = now - st.buildHoldSince
	if held >= cfg.MaxHold + cfg.Free then
		st.buildHoldSince = now
		held = 0
	end
	return held < cfg.MaxHold
end

-- RestoreHeavy, but no more heavy weapons than a plan without sockets ever builds: a rocket plan would stay wood for good
function CAI_StripRestoreHeavy(st, cfg)
	if st.sockets ~= nil then return cfg.RestoreHeavy end
	if st.stripHeavy == nil then
		local n = 0
		for _, a in ipairs(Fort or {}) do
			if CAI_Defaults.SocketVolley.EnergyShot[a.DeviceSaveName] then n = n + 1 end
		end
		st.stripHeavy = math.min(cfg.RestoreHeavy, n)
	end
	return st.stripHeavy
end

function CAI_FrontStrip(elapsed)
	local st = data.CAI
	local cfg = Strategy.FrontStrip or CAI_Defaults.FrontStrip
	if st == nil or CAI_Plan.strip == nil or not (cfg and cfg.Enabled) or type(CreateLink) ~= "function" then return end
	st.strip = st.strip or {}
	st.stripSkip = st.stripSkip or {}
	local function metal()
		local res = GetTeamResources(teamId)
		return (type(res) == "table" or type(res) == "userdata") and res.metal or 0
	end
	local function skip(i, why)
		if st.stripSkip[i .. why] then return end
		st.stripSkip[i .. why] = true
		CAI_Log("STRIP_SKIP " .. i .. " " .. why .. " t=" .. elapsed)
	end
	local lastResult
	local function swap(i, new)
		local q = CAI_Plan.strip[i]
		local a, b = CAI_StripNode(q[1], q[2]), CAI_StripNode(q[3], q[4])
		if a == nil or b == nil then skip(i, "no node"); return false end
		if not IsNodeLinkedTo(a, b) then skip(i, "no link"); return false end
		local old = GetLinkMaterialSaveName(a, b)
		if old ~= (new == "armour" and "bracing" or "armour") then skip(i, "material " .. tostring(old)); return false end
		local before = metal()
		local r = CreateLink(teamId, new, a, b)
		lastResult = r
		CAI_Log("STRIP " .. q[1] .. "," .. q[2] .. "-" .. q[3] .. "," .. q[4] .. " " .. tostring(old) .. "->" .. new .. " result=" .. tostring(r)
			.. " m=" .. CAI_Round(before) .. "->" .. CAI_Round(metal()) .. " t=" .. elapsed)
		return true
	end
	if elapsed <= cfg.Until and metal() < cfg.Below then
		-- as many as it takes this step: the metal is needed now
		for i = 1, #CAI_Plan.strip do
			if st.strip[i] == nil and metal() < cfg.Below and swap(i, "bracing") then st.strip[i] = "wood" end
		end
	elseif metal() >= cfg.RestoreAbove and CAI_HeavyCount(true) >= CAI_StripRestoreHeavy(st, cfg) then
		for i = 1, #CAI_Plan.strip do
			if st.strip[i] == "wood" then
				-- refused (test 7: result -4, that strut stayed wood): again next step
				local did = swap(i, "armour")
				if not did or lastResult == (CS_SUCCESS or -15) then st.strip[i] = "done" end
				if did then return end
			end
		end
	end
end

-- own hits, for the log (CAI_Defaults.CombatLog): by weapon on enemy devices and struts, and at which height
function CAI_NoteDealt(what, weapon, target, pos)
	local st = data.CAI
	if st == nil or st.sockets == nil then return end
	local cfg = Strategy.CombatLog or CAI_Defaults.CombatLog
	st.dealt = st.dealt or { dev = {}, link = {}, band = {} }
	local key = tostring(weapon) .. ">" .. tostring(target)
	st.dealt[what][key] = (st.dealt[what][key] or 0) + 1
	if type(pos) == "table" or type(pos) == "userdata" then
		local band = pos.y < cfg.TopY and "top" or pos.y < cfg.LowY and "mid" or "low"
		local b = tostring(weapon) .. ":" .. band
		st.dealt.band[b] = (st.dealt.band[b] or 0) + 1
	end
end

local function CAI_CountText(t)
	local keys = {}
	for k in pairs(t or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	for i, k in ipairs(keys) do keys[i] = k .. ":" .. t[k] end
	return table.concat(keys, ",")
end

function CAI_LogCombat(elapsed)
	local st = data.CAI
	if not CAI_Logging or st == nil or st.sockets == nil then return end
	local cfg = Strategy.CombatLog or CAI_Defaults.CombatLog
	if elapsed < (st.nextCombatLog or cfg.Every) then return end
	st.nextCombatLog = elapsed + cfg.Every
	local function reactors(side)
		local out = {}
		for i = 0, GetDeviceCountSide(side) - 1 do
			local id = GetDeviceIdSide(side, i)
			if GetDeviceType(id) == "reactor" and type(GetDeviceHealth) == "function" then
				out[#out + 1] = string.format("%.2f", GetDeviceHealth(id))
			end
		end
		return table.concat(out, "/")
	end
	local ss = st.sniperSight or {}
	CAI_Log("COMBAT t=" .. elapsed .. " reactor=" .. reactors(CAI_Side(teamId)) .. " enemy=" .. reactors(enemyTeamId)
		.. " sniper=seen:" .. (ss.seen or 0) .. ",pierced:" .. (ss.pierced or 0) .. ",hold:" .. (ss.hold or 0)
		.. " shots=" .. CAI_CountText(st.ownShots))
	local d = st.dealt or {}
	CAI_Log("DEALT t=" .. elapsed .. " dev=" .. CAI_CountText(d.dev))
	CAI_Log("DEALT t=" .. elapsed .. " link=" .. CAI_CountText(d.link))
	CAI_Log("DEALT t=" .. elapsed .. " band=" .. CAI_CountText(d.band))
end

-- Socket upgrade (Bastion): once the AI is rich, sell a socket's small weapon (a sniper) and rebuild the place with a
-- heavy one (laser, 20mm, cannon, firebeam) whose tech stands. The device is marked DeviceDeleteToRebuild, so the
-- built-in AI queues its plan action for rebuilding when it is gone; the action already names the new weapon
-- (CAI_SocketLost sees s.selling). Logs SOCKET <name> sell <old>-><new> action=<k> result=<DestroyDeviceById>.
function CAI_SocketUpgrade(elapsed)
	local st = data.CAI
	if st == nil or st.sockets == nil or Fort == nil or data.Devices == nil or type(DestroyDeviceById) ~= "function" then return end
	local cfg = (Strategy.Socket or CAI_Defaults.Socket).Upgrade or CAI_Defaults.Socket.Upgrade
	if not cfg then return end
	CAI_ParkRefused(elapsed)
	for name, s in pairs(st.sockets) do
		if s.selling ~= nil then
			if elapsed - (st.upgradeAt or 0) <= (cfg.Timeout or 60) then return end
			CAI_Log("SOCKET " .. name .. " sale of " .. tostring(s.selling) .. " not seen, given up")
			s.selling = nil
		end
	end
	local m, e = CAI_NotePeaks(st)
	if (m or 0) >= (cfg.Metal or 450) and (e or 0) >= (cfg.Energy or 3000) then
		st.richFor = (st.richFor or 0) + Strategy.ThinkInterval
	else
		st.richFor = 0
	end
	if st.richFor < (cfg.Seconds or 15) or elapsed - (st.upgradeAt or -1e9) < (cfg.Hold or 60) then return end
	-- the living device of each socket (the highest id if the plan lists more than one)
	local dev = {}
	for id, k in pairs(data.Devices) do
		local a = Fort[k]
		local t = a and a.Socket and GetDeviceType(id)
		if t and (type(IsDeviceFullyBuilt) ~= "function" or IsDeviceFullyBuilt(id)) and (dev[a.Socket] == nil or id > dev[a.Socket].id) then
			dev[a.Socket] = { id = id, k = k, type = t }
		end
	end
	local names = {}
	for name, s in pairs(st.sockets) do
		if s.upgrade then names[#names + 1] = name end
	end
	table.sort(names, function(x, y)
		local rx, ry = st.sockets[x].rank or 1, st.sockets[y].rank or 1
		if rx ~= ry then return rx < ry end
		return x < y
	end)
	local own = CAI_OwnDevices(true)
	for _, name in ipairs(names) do
		local s, d = st.sockets[name], dev[name]
		if d and cfg.From and cfg.From[d.type] then
			-- a mix: weapons no other socket holds first (B2 a laser, then B1 a 20mm or a firebeam)
			local held, order = {}, {}
			for other, od in pairs(dev) do
				if other ~= name then held[od.type] = true end
			end
			for pass = 1, 2 do
				for _, w in ipairs(CAI_SocketOrder(s, s.upgrade)) do
					if (pass == 1) == (not held[w]) then order[#order + 1] = w end
				end
			end
			for _, w in ipairs(order) do
				local need = s.needs[w]
				-- payable at all (storage), and nearly at hand now (the sale refunds half the old weapon)
				local can, cm, ce = CAI_Affordable(st, w)
				local athand = m >= (cm or 0) * (cfg.AtHand or 0.8) and e >= (ce or 0) * (cfg.AtHand or 0.8)
				if w ~= d.type and (need == nil or (own[need] or 0) > 0) and can and not athand then
					-- worth more than the next one: save for it, for a while
					s.wantSince = s.wantSince or elapsed
					if elapsed - s.wantSince < (cfg.WantWait or 120) then
						if s.wantFor ~= w then
							s.wantFor = w
							CAI_Log("SOCKET " .. name .. " saving for " .. w .. " m=" .. CAI_Round(m) .. " e=" .. CAI_Round(e))
						end
						return
					end
				end
				if w ~= d.type and (need == nil or (own[need] or 0) > 0) and can and athand then
					s.wantSince, s.wantFor = nil, nil
					local a = Fort[d.k]
					local old = a.DeviceSaveName
					local before = s.current
					CAI_SocketSet(name, w)
					s.selling = d.id
					data.DeviceDeleteToRebuild = data.DeviceDeleteToRebuild or {}
					data.DeviceDeleteToRebuild[d.id] = true
					local r = DestroyDeviceById(d.id)
					st.upgradeAt = elapsed
					st.richFor = 0
					if DD_SUCCESS ~= nil and r ~= DD_SUCCESS then
						CAI_SocketSet(name, old)
						s.current = before
						s.selling = nil
						data.DeviceDeleteToRebuild[d.id] = nil
					else
						s.swaps = s.swaps + 1
					end
					CAI_Log("SOCKET " .. name .. " sell " .. tostring(d.type) .. "->" .. w .. " action=" .. d.k .. " result="
						.. tostring(r) .. " m=" .. CAI_Round(m) .. " e=" .. CAI_Round(e) .. " posture=" .. tostring(st.posture))
					return
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Posture (Bastion, .dev/docs/bastion-plan.md): one of Pressure (default), AntiArtillery, AntiSniper, AntiAir, Siege,
-- Punish, chosen every think step from the enemy's devices, their weapons' threat (st.threat), the zone pressure and
-- the economy. Only for plans with FortSockets.

CAI_Postures = { "Pressure", "AntiArtillery", "AntiSniper", "AntiAir", "Siege", "Punish" }

-- enemy devices by type (game state, deterministic)
function CAI_EnemyDevicesAll()
	local count = {}
	for i = 0, GetDeviceCountSide(enemyTeamId) - 1 do
		local t = GetDeviceType(GetDeviceIdSide(enemyTeamId, i))
		if t then count[t] = (count[t] or 0) + 1 end
	end
	return count
end

function CAI_PostureScores()
	local st, cfg = data.CAI, Strategy.Posture or CAI_Defaults.Posture
	local enemy = CAI_EnemyDevicesAll()
	local score = { Pressure = cfg.Base or 3 }
	for name, types in pairs(cfg.Threats or {}) do
		local v = 0
		for t in pairs(types) do v = v + (st.threat[t] or 0) + (cfg.DeviceWeight or 2) * (enemy[t] or 0) end
		score[name] = v
	end
	local zmax = 0
	for _, v in pairs(st.zoneDmg or {}) do zmax = math.max(zmax, v) end
	score.Siege = zmax / (cfg.SiegeScale or 50)
	-- the enemy builds economy rather than weapons, or the AI piles up metal: hit the economy
	local eco, weapons = 0, 0
	for t, n in pairs(enemy) do
		if cfg.Eco and cfg.Eco[t] then eco = eco + n elseif cfg.Weapons and cfg.Weapons[t] then weapons = weapons + n end
	end
	local res = GetTeamResources(teamId)
	local metal = (type(res) == "table" or type(res) == "userdata") and res.metal or 0
	score.Punish = 0.5 * math.max(0, eco - 2 * weapons) + ((metal or 0) >= Strategy.RichMetal and (cfg.PunishRich or 4) or 0)
	return score
end

function CAI_UpdatePosture(elapsed)
	local st = data.CAI
	if st == nil or CAI_Plan.sockets == nil then return end
	local cfg = Strategy.Posture or CAI_Defaults.Posture
	local score = CAI_PostureScores()
	local cur = st.posture or "Pressure"
	local best, bestScore = cur, score[cur] or 0
	for _, p in ipairs(CAI_Postures) do
		if (score[p] or 0) > bestScore then best, bestScore = p, score[p] end
	end
	local held = elapsed - (st.postureSince or -1e9)
	if st.posture == nil or (best ~= cur and held >= (cfg.MinHold or 30) and bestScore >= (score[cur] or 0) * (cfg.Switch or 1.25)) then
		local parts = {}
		for _, p in ipairs(CAI_Postures) do
			if (score[p] or 0) > 0 then parts[#parts + 1] = p .. ":" .. CAI_Round(score[p]) end
		end
		CAI_Log("POSTURE " .. tostring(st.posture or "-") .. "->" .. best .. " t=" .. elapsed .. " scores=" .. table.concat(parts, ","))
		st.posture = best
		st.postureSince = elapsed
		st.postureBoost = cfg.Boost and cfg.Boost[best] or nil
	end
end

-- Rebuild cap: the built-in AI queues every lost device for rebuilding (CheckDeviceForRebuild schedules
-- QueueDeviceRebuild). A device that keeps dying at one place only eats metal; past Strategy.RebuildCap it stays lost.
function CAI_RebuildCapped(deviceId)
	local st = data.CAI
	local k = data.Devices and data.Devices[deviceId]
	local cap = Strategy.RebuildCap
	if st == nil or k == nil or Fort == nil or Fort[k] == nil or type(cap) ~= "table" then return false end
	local dev = Fort[k].DeviceSaveName
	local max = cap.Max and cap.Max[dev]
	if max == nil then return false end
	local now = st.ticks * Strategy.ThinkInterval
	st.rebuilds = st.rebuilds or {}
	local r = st.rebuilds[k]
	local n = 1
	if r and now - r.last <= (cap.Window or 180) then n = r.n + 1 end
	st.rebuilds[k] = { n = n, last = now }
	if n <= max then return false end
	CAI_Log("REBUILD_CAP action " .. k .. " " .. tostring(dev) .. " losses=" .. n .. " window=" .. tostring(cap.Window or 180) .. "s")
	return true
end

local CAI_BaseQueueDeviceRebuild = QueueDeviceRebuild
if CAI_BaseQueueDeviceRebuild then
	function QueueDeviceRebuild(deviceId)
		-- a buzzsaw first: it is used up, not lost to the enemy; never a socket loss, never for the rebuild cap
		local okB, verdict = pcall(CAI_BuzzsawLost, deviceId)
		if not okB then CAI_Log("ERROR buzzsaw lost: " .. tostring(verdict)) end
		if okB and verdict == "drop" then
			data.Devices[deviceId] = nil
			return
		elseif okB and verdict == "rearm" then
			return CAI_BaseQueueDeviceRebuild(deviceId)
		end
		local okS, swapped = pcall(CAI_SocketLost, deviceId)
		if not okS then CAI_Log("ERROR socket: " .. tostring(swapped)) end
		if okS and swapped then
			return CAI_BaseQueueDeviceRebuild(deviceId)
		end
		local ok, capped = pcall(CAI_RebuildCapped, deviceId)
		if not ok then
			CAI_Log("ERROR rebuild cap: " .. tostring(capped))
		elseif capped then
			data.Devices[deviceId] = nil
			return
		end
		return CAI_BaseQueueDeviceRebuild(deviceId)
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
		-- a destroyed weapon no longer threatens us as much
		if st.threat[saveName] then
			st.threat[saveName] = st.threat[saveName] * 0.7
		end
	end
end

--------------------------------------------------------------------------------
-- Engine probe (Bastion step 0, testing only; FortPlanConfig.EngineProbe in ai/fortplans.lua, off by default).
-- Answers three questions in a normal match, only by logging ([CAI] T<team> EPROBE ...):
--   1. At Material seconds: CreateLink with "armour" over a bracing strut of the starting fort. Logs the result code,
--      the strut's material right after and one think step later, and the metal before and after.
--   2. At Reclaim seconds: DestroyDeviceById on the first own device of Devices. Logs its cost (GetDeviceCost), then the
--      metal change every frame (Frame seconds) for Window seconds and the frame of OnDeviceDeleted; the refund is the jump.
--   3. OnLinkHit on own struts: the first hit at once, then every Report seconds hits/damage by projectile type, and
--      own struts lost by break type (OnLinkDestroyed) to compare with.
-- EngineProbe = { Material = 30, Reclaim = 45, Devices = { "machinegun", "sniper", "mortar" }, Window = 8, Frame = 0.04, Report = 30 }

local function CAI_EP_Metal()
	local ok, res = pcall(GetTeamResources, teamId)
	return (ok and res and res.metal) or -1
end

local function CAI_EP_Text(v)
	if type(v) == "table" or type(v) == "userdata" then
		local ok, m, e = pcall(function() return v.metal, v.energy end)
		if ok and (m ~= nil or e ~= nil) then return "m=" .. tostring(m) .. ",e=" .. tostring(e) end
	end
	return tostring(v)
end

-- a bracing strut of the starting fort (its ExistingFort actions), both nodes existing
local function CAI_EP_Bracing()
	for _, a in ipairs(Fort or {}) do
		if a.ExistingFort and a.Type == CREATE_LINK and a.MaterialSaveName == "bracing" then
			local na = data.OriginalToActual and data.OriginalToActual[a.OriginalNodeAId]
			local nb = data.OriginalToActual and data.OriginalToActual[a.OriginalNodeBId]
			if na and nb and IsNodeLinkedTo(na, nb) and GetLinkMaterialSaveName(na, nb) == "bracing" then
				return na, nb
			end
		end
	end
end

local function CAI_EP_OwnDevice(saveName)
	local side = CAI_Side(teamId)
	for i = 0, GetDeviceCountSide(side) - 1 do
		local id = GetDeviceIdSide(side, i)
		if GetDeviceType(id) == saveName and GetDeviceTeamIdActual(id) == teamId then return id end
	end
end

function CAI_EP_Frame()
	local r = CAI_EngineProbe and CAI_EngineProbe.reclaim
	if r == nil or r.done then return end
	local m = CAI_EP_Metal()
	r.series[#r.series + 1] = CAI_Round(m - r.last)
	r.last = m
	r.frames = r.frames + 1
	if r.frames * r.dt >= r.window then
		r.done = true
		CAI_Log("EPROBE RECLAIM series m0=" .. CAI_Round(r.m0) .. " end=" .. CAI_Round(m) .. " deleted@" .. tostring(r.deletedFrame)
			.. " deltas=" .. table.concat(r.series, ","))
		return
	end
	ScheduleCall(r.dt, CAI_EP_Frame)
end

function CAI_EngineProbeTick(elapsed)
	local cfg = FortPlanConfig and FortPlanConfig.EngineProbe
	if type(cfg) ~= "table" or data.HumanAssist then return end
	if CAI_EngineProbe == nil then
		CAI_EngineProbe = { hits = {}, damage = {}, broken = {}, nextReport = cfg.Report or 30 }
		CAI_Log("EPROBE ON material@" .. tostring(cfg.Material) .. " reclaim@" .. tostring(cfg.Reclaim))
	end
	local p = CAI_EngineProbe
	local devices = cfg.Devices or { "machinegun" }
	-- 1. another material over an existing strut
	if p.material == nil and cfg.Material and elapsed >= cfg.Material then
		local a, b = CAI_EP_Bracing()
		if a == nil then
			p.material = { done = true }
			CAI_Log("EPROBE MATERIAL none (no bracing strut of the starting fort)")
		else
			local m0 = CAI_EP_Metal()
			local r = CreateLink(teamId, "armour", a, b)
			p.material = { a = a, b = b }
			CAI_Log("EPROBE MATERIAL " .. a .. "-" .. b .. " bracing->armour result=" .. tostring(r) .. ":"
				.. tostring(type(CS) == "table" and CS[r]) .. " now=" .. tostring(GetLinkMaterialSaveName(a, b))
				.. " linked=" .. tostring(IsNodeLinkedTo(a, b)) .. " m=" .. CAI_Round(m0) .. "->" .. CAI_Round(CAI_EP_Metal()))
		end
	elseif p.material and not p.material.done then
		p.material.done = true
		local a, b = p.material.a, p.material.b
		CAI_Log("EPROBE MATERIAL later " .. a .. "-" .. b .. " now=" .. tostring(GetLinkMaterialSaveName(a, b))
			.. " linked=" .. tostring(IsNodeLinkedTo(a, b)))
	end
	-- 2. what a reclaim gives back
	if p.reclaim == nil and cfg.Reclaim and elapsed >= cfg.Reclaim then
		local id, device
		for _, d in ipairs(devices) do
			if id == nil then id, device = CAI_EP_OwnDevice(d), d end
		end
		if id == nil then
			p.reclaim = { done = true }
			CAI_Log("EPROBE RECLAIM none (no own " .. table.concat(devices, "/") .. ")")
		else
			local m0 = CAI_EP_Metal()
			local okC, cost = pcall(GetDeviceCost, device)
			local okR, rate = pcall(GetTeamResourceRate, teamId)
			local res = DestroyDeviceById(id)
			p.reclaim = { id = id, m0 = m0, last = m0, series = {}, frames = 0, dt = cfg.Frame or 0.04, window = cfg.Window or 8 }
			CAI_Log("EPROBE RECLAIM " .. device .. " id=" .. id .. " result=" .. tostring(res)
				.. " success=" .. tostring(res == DD_SUCCESS) .. " cost=" .. CAI_EP_Text(okC and cost or "?")
				.. " rate=" .. CAI_EP_Text(okR and rate or "?") .. " m=" .. CAI_Round(m0))
			ScheduleCall(p.reclaim.dt, CAI_EP_Frame)
		end
	end
	-- 3. strut hits so far
	if elapsed >= p.nextReport then
		p.nextReport = elapsed + (cfg.Report or 30)
		local function Dump(t, f)
			local keys, parts = {}, {}
			for k in pairs(t) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			for _, k in ipairs(keys) do parts[#parts + 1] = k .. ":" .. f(k) end
			return table.concat(parts, ",")
		end
		CAI_Log("EPROBE LINKHIT t=" .. elapsed
			.. " hits=" .. Dump(p.hits, function(k) return p.hits[k] .. "/" .. CAI_Round(p.damage[k]) end)
			.. " broken=" .. Dump(p.broken, function(k) return p.broken[tonumber(k) or k] end))
	end
end

local CAI_BaseOnLinkHit = OnLinkHit
function OnLinkHit(nodeIdA, nodeIdB, objectId, objectTeamId, objectSaveName, damage, pos, reflectedByEnemy)
	if CAI_BaseOnLinkHit then
		CAI_BaseOnLinkHit(nodeIdA, nodeIdB, objectId, objectTeamId, objectSaveName, damage, pos, reflectedByEnemy)
	end
	if objectTeamId == teamId and CAI_Side(NodeTeam(nodeIdA)) == enemyTeamId then
		pcall(CAI_NoteDealt, "link", objectSaveName, GetLinkMaterialSaveName(nodeIdA, nodeIdB), pos)
	end
	if CAI_Plan.nodeZone and CAI_Side(objectTeamId) == enemyTeamId and NodeTeam(nodeIdA) == teamId then
		local ok, err = pcall(CAI_ZoneDamage, nodeIdA, nodeIdB, tonumber(damage) or 0)
		if not ok then CAI_Log("ERROR zone hit: " .. tostring(err)) end
	end
	local p = CAI_EngineProbe
	if p == nil or NodeTeam(nodeIdA) ~= teamId then return end
	local k = tostring(objectSaveName)
	if next(p.hits) == nil then
		CAI_Log("EPROBE LINKHIT first " .. nodeIdA .. "-" .. nodeIdB .. " by=" .. k .. " team=" .. tostring(objectTeamId)
			.. " damage=" .. tostring(damage) .. " material=" .. tostring(GetLinkMaterialSaveName(nodeIdA, nodeIdB)))
	end
	p.hits[k] = (p.hits[k] or 0) + 1
	p.damage[k] = (p.damage[k] or 0) + (tonumber(damage) or 0)
end

local CAI_BaseOnLinkDestroyed = OnLinkDestroyed
function OnLinkDestroyed(linkTeamId, saveName, nodeA, nodeB, breakType)
	if CAI_BaseOnLinkDestroyed then
		CAI_BaseOnLinkDestroyed(linkTeamId, saveName, nodeA, nodeB, breakType)
	end
	if CAI_Plan.nodeZone and linkTeamId == teamId and (LINKBREAK_DELETE == nil or breakType ~= LINKBREAK_DELETE) then
		local cfg = Strategy.Zone or CAI_Defaults.Zone
		local ok, err = pcall(CAI_ZoneDamage, nodeA, nodeB, cfg.BreakDamage or 100)
		if not ok then CAI_Log("ERROR zone break: " .. tostring(err)) end
	end
	local p = CAI_EngineProbe
	if p == nil or linkTeamId ~= teamId then return end
	p.broken[breakType] = (p.broken[breakType] or 0) + 1
end

local CAI_BaseOnDeviceDeleted = OnDeviceDeleted
function OnDeviceDeleted(deviceTeamId, deviceId, saveName, nodeA, nodeB, t)
	if CAI_BaseOnDeviceDeleted then
		CAI_BaseOnDeviceDeleted(deviceTeamId, deviceId, saveName, nodeA, nodeB, t)
	end
	local r = CAI_EngineProbe and CAI_EngineProbe.reclaim
	if r and r.id == deviceId and r.deletedFrame == nil then
		r.deletedFrame = r.frames
		CAI_Log("EPROBE RECLAIM deleted " .. tostring(saveName) .. " frame=" .. r.frames .. " m=" .. CAI_Round(CAI_EP_Metal()))
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
