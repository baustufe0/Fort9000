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
	BuildSkipSeconds = 90, BuildSkipMinMetal = 300, StarvedFlatTicks = 4,
	-- NoOffence: weapon types that never fire at the enemy fort (machine guns do little damage there; they stay
	-- anti-air), their turns in the fire control go to the other weapons (snipers)
	Fire = { Enabled = true, Interval = 1.0, WeaponsPerTick = 3, AlwaysOffensive = true, RebuildFireFactor = 2.5,
		NoOffence = { machinegun = true } },
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
-- Custom build plans from the mod folder (mods/fort-9000/fortplans/<map>/)
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
	Log("[CAI] T" .. tostring(teamId) .. " " .. msg)
end

-- Direct access to the plan variables (rawget/rawset do not exist in Forts)
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
	return nil, (ok and "no fort" or tostring(err))
end

FortPlanConfig = nil
pcall(dofile, "mods/fort-9000/ai/fortplans.lua")
if type(FortPlanConfig) ~= "table" then FortPlanConfig = {} end

local function CAI_PreloadPlans()
	local summary = {}
	for mapName, m in pairs(FortPlanConfig.Maps or {}) do
		local entry = { sigs = {}, plans = {}, list = m.Plans or {}, reactors = m.ReactorsPerSide }
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
				local t, err = CAI_LoadPlanFile("mods/fort-9000/fortplans/" .. mapName .. "/" .. f)
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
	Log("[CAI] PLAN-PRELOAD " .. table.concat(summary, " ") .. " (custom/original)")
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

local function CAI_IdentifyMap(engineFort, E)
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

function CAI_TrySwapPlan(where)
	if CAI_Plan.done then return end
	CAI_Plan.done = true
	local engineFort, E = Fort, FortPos
	if type(engineFort) ~= "table" or #engineFort == 0 or type(E) ~= "table" then
		CAI_PlanNote("PLAN file=original reason=no-game-plan at=" .. where)
		return
	end
	local mapName, how, engineFile = CAI_IdentifyMap(engineFort, E)
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
	-- shift into the coordinates of the game's plan
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
	CAI_PlanNote("PLAN map=" .. mapName .. " file=" .. choice .. " actions=" .. #ours.Fort .. " instead=" .. tostring(engineFile)
		.. " choice=" .. why .. " detected=" .. how .. " at=" .. where .. " shift=" .. math.floor(dx + 0.5) .. "," .. math.floor(dy + 0.5))
end

local CAI_BaseOffsetFort = OffsetFort
function OffsetFort(offset, structureId)
	local ok, err = pcall(CAI_TrySwapPlan, "OffsetFort")
	if not ok then Log("[CAI] PLAN-ERROR " .. tostring(err)) end
	CAI_PlanNote("TRANSFORM OffsetFort " .. tostring(offset and offset.x) .. "," .. tostring(offset and offset.y))
	return CAI_BaseOffsetFort(offset, structureId)
end

local CAI_BaseMirrorFort = MirrorFort
function MirrorFort(pivot, offset, structureId)
	local ok, err = pcall(CAI_TrySwapPlan, "MirrorFort")
	if not ok then Log("[CAI] PLAN-ERROR " .. tostring(err)) end
	CAI_PlanNote("TRANSFORM MirrorFort pivot=" .. tostring(pivot) .. " " .. tostring(offset and offset.x) .. "," .. tostring(offset and offset.y))
	CAI_FortMirrored = true       -- SHAPE diagnostics report offsets in the plan's own frame
	return CAI_BaseMirrorFort(pivot, offset, structureId)
end

--------------------------------------------------------------------------------
-- Helper functions

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
	local no = f.NoOffence or CAI_Defaults.Fire.NoOffence or {}
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
	if ScheduledCallCountOfFunc(CAI_FireTick) == 0 then
		ScheduleCall(f.Interval or 1, CAI_FireTick)
	end
	return "period=" .. tostring(f.Interval) .. "s weapons=" .. tostring(f.WeaponsPerTick) .. " always=" .. tostring(f.AlwaysOffensive)
		.. " duringRebuild=x" .. tostring(f.RebuildFireFactor) .. " noOffence=" .. table.concat(noList, ",")
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
		local no = st.noOffence or {}
		local checked = 0
		-- round robin over the weapons; NoOffence types are skipped without using up a turn
		for step = 1, n do
			if checked >= tries then break end
			if st.firePtr >= n then st.firePtr = 0 end
			local id = GetWeaponId(teamId, st.firePtr)
			st.firePtr = st.firePtr + 1
			local kind = (type(GetDeviceType) == "function" and id and id > 0) and GetDeviceType(id) or nil
			if not (kind and no[kind]) then
				checked = checked + 1
				if id and id > 0 and not IsDummy(id) and IsAIDeviceAvailable(id) and IsWeaponReadyToFire(id)
					and (data.ActionQueue == nil or data.ActionQueue[id] == nil) then
					st.fireAttempts = st.fireAttempts + 1
					TryFireGun(id)
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

local function CAI_NoteBuildError(kind, what, a, b, r)
	if data.CAI == nil or data.HumanAssist then return end
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
		if a.OriginalNodeAId and a.PosA then CAI_PlanPos[a.OriginalNodeAId] = a.PosA end
		if a.OriginalNodeBId and a.PosB then CAI_PlanPos[a.OriginalNodeBId] = a.PosB end
		if a.OriginalNodeBId and a.NewNodePos then CAI_PlanPos[a.OriginalNodeBId] = a.NewNodePos end
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
-- over the plan file (tools/fortgen/shape.py). New nodes are placed relative to the current position of
-- their source node, so a lean while building is copied into everything built from it.
CAI_SHAPE_MAX = 40
CAI_SHAPE_PER_LINE = 25
CAI_ShapeCount = 0

function CAI_LogShape(why)
	if data.CAI == nil or data.HumanAssist or CAI_ShapeCount >= CAI_SHAPE_MAX then return end
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
	if type(EnumerateLinks) ~= "function" or CAI_StressCount >= CAI_STRESS_MAX then return end
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
	if data.CAI == nil or data.HumanAssist then return end
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
		CreateDeviceWithFlags = function(team, saveName, nodeA, nodeB, t, ...)
			local r = CAI_BaseCreateDeviceWithFlags(team, saveName, nodeA, nodeB, t, ...)
			if type(r) == "number" and r < 0 and r ~= CS_INSUFFICIENTRESOURCES then
				pcall(CAI_NoteBuildError, "device", saveName, nodeA, nodeB, r)
				if r == CS_UNSTABLE then
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
	return (#hooked > 0) and table.concat(hooked, ",") or "no build functions found"
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
		table.insert(entries, { name = saveName, score = base + bonus, idx = i })
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
				CAI_Log("GAVE_UP action " .. tostring(k) .. " type=" .. tostring(a and a.Type)
					.. " " .. tostring(a and (a.DeviceSaveName or a.MaterialSaveName)) .. " after " .. Strategy.RebuildGiveUpSeconds .. "s")
			end
		end
		for k in pairs(st.rebuildSince) do
			if not data.Rebuild[k] then st.rebuildSince[k] = nil end
		end
	end

	-- Second safety valve: if normal construction hangs on the same action although there is metal,
	-- the action is skipped (the built-in AI would otherwise wait forever).
	local fi = data.fortIndex
	if type(fi) == "number" and Fort and fi <= #Fort then
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
			if st.buildHadRes and elapsed - st.buildSince >= Strategy.BuildSkipSeconds then
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

	local parts = { "THINK t=" .. elapsed .. " build=" .. tostring(data.fortIndex) .. "/" .. tostring(Fort and #Fort) .. " rebuild=" .. rebuildCount }
	local ok, res = pcall(CAI_UpdateTargets)
	parts[#parts + 1] = ok and res or ("ERROR targets: " .. tostring(res))
	ok, res = pcall(CAI_UpdateAggression, elapsed)
	parts[#parts + 1] = ok and res or ("ERROR aggression: " .. tostring(res))
	ok, res = pcall(CAI_UpdateAntiAir)
	parts[#parts + 1] = ok and res or ("ERROR anti-air: " .. tostring(res))
	parts[#parts + 1] = "fire=" .. tostring(st.fireAttempts or 0)
	st.fireAttempts = 0
	CAI_Log(table.concat(parts, " "))

	-- shape snapshot once per game minute (see CAI_LogShape)
	if elapsed >= (st.nextShape or 60) then
		st.nextShape = elapsed + 60
		local okS, errS = pcall(CAI_LogShape, "minute")
		if not okS then CAI_Log("ERROR shape diagnostics: " .. tostring(errS)) end
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
	-- Assist AI on the side of a human player (e.g. anti-air assistant): do not touch
	if data.HumanAssist then
		Log("[CAI] T" .. tostring(teamId) .. " ASSIST FORT 9000 AI inactive (assist AI of a player)")
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
	Log("[CAI] T" .. tostring(teamId) .. " ASSIST FORT 9000 AI inactive (assist AI of a player)")
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
		-- a destroyed weapon no longer threatens us as much
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
