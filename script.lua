-- FORT 9000 - Recorder
-- Runs as a mod script in every match and also when a replay is played.
-- Writes game state and events of both sides to the log with [CREC] (users/<id>/log.txt).
-- .dev/tools/train.py learns from it. The recorder only reads and changes nothing in the game.
--
-- Line format (f = game frame):
--   [CREC] f=0 START v=4            (restart=1 when the player restarts the match: the game rewinds to frame 2
--                                    and keeps the mod script's state, so the recorder starts over itself)
--   [CREC] f=250 SNAP s=1 t=1 m=1200 e=3400 dev=cannon:2,mortar:1 shots=cannon:3
--   [CREC] f=250 SNAP s=2 t=102,202 m=1500 e=6000 dev=... shots=... tm=102:700:3500,202:800:2500
--                                    (2v2: m/e summed over the side's teams, tm = per team)
--   [CREC] f=260 BUILT s=2 d=sniper
--   [CREC] f=300 LOST s=1 i=17 d=mortar
--   [CREC] f=900 RESULT w=1
-- Build events of both sides (.dev/tools/fortgen/rec_fort.py turns them into an AI build plan; t = team, p = x,y):
--   [CREC] f=40 NODE s=1 t=1 n=1203 p=-3100.00,105.00 g=0
--   [CREC] f=41 LINK s=1 t=1 a=56 b=1203 m=bracing pa=-3093.19,205.21 pb=-3100.00,105.00
--   [CREC] f=42 UNLINK s=1 t=1 a=56 b=1203 m=bracing
--   [CREC] f=43 UNNODE n=1203
--   [CREC] f=50 DEV s=1 t=1 i=17 d=mortar a=55 b=58 lt=0.50 pa=-2945.11,206.49 pb=-2846.18,203.99 u=-1
--   [CREC] f=51 GDEV s=1 t=1 i=18 d=mine p=-3029.41,700.00
--   [CREC] f=60 DEL s=1 i=17 d=mortar a=55 b=58 pa=-2945.11,206.49 pb=-2846.18,203.99

local REC_VERSION = 4
local REC_SNAP_FRAMES = 125
local REC_SIDES = (type(MAX_SIDES) == "number") and MAX_SIDES or 100

local recFrame = 0
local recStarted = false
local recLastSnap = -100000
local recShots = { [1] = {}, [2] = {} }
local recEnded = false

local function RecLog(msg)
	Log("[CREC] f=" .. tostring(recFrame) .. " " .. msg)
end

local function RecSide(id)
	if type(id) ~= "number" then return -1 end
	return id % REC_SIDES
end

local function RecDump(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. ":" .. tostring(t[k]) end
	return table.concat(parts, ",")
end

local function RecNum(v)
	if type(v) ~= "number" then return "-1" end
	return tostring(math.floor(v + 0.5))
end

local function RecPos(p)
	if p == nil or type(p.x) ~= "number" or type(p.y) ~= "number" then return "-" end
	return string.format("%.2f,%.2f", p.x, p.y)
end

local function RecNodePos(id)
	if type(NodePosition) ~= "function" or type(id) ~= "number" then return "-" end
	local ok, p = pcall(NodePosition, id)
	if not ok then return "-" end
	return RecPos(p)
end

local function RecBuildSide(teamId)
	local side = RecSide(teamId)
	return side == 1 or side == 2
end

local function RecSnapshot()
	for side = 1, 2 do
		local devices = {}
		local count = GetDeviceCountSide(side) or 0
		local teamSeen, teams = {}, {}
		for i = 0, count - 1 do
			local id = GetDeviceIdSide(side, i)
			local saveName = GetDeviceType(id)
			if saveName then
				devices[saveName] = (devices[saveName] or 0) + 1
			end
			-- real team numbers (e.g. 102 and 202 in 2v2) instead of the side number, otherwise GetTeamResources
			-- returns starting values
			if saveName == "reactor" and type(GetDeviceTeamIdActual) == "function" then
				local team = GetDeviceTeamIdActual(id)
				if type(team) == "number" and not teamSeen[team] then
					teamSeen[team] = true
					teams[#teams + 1] = team
				end
			end
		end
		if #teams == 0 then teams[1] = side end
		table.sort(teams)
		-- m/e = sum over all teams of the side, tm = per team (only with several teams)
		local metal, energy, perTeam = -1, -1, {}
		for _, team in ipairs(teams) do
			local ok, res = pcall(GetTeamResources, team)
			local m, e = -1, -1
			if ok and res then m, e = res.metal, res.energy end
			if type(m) == "number" and m >= 0 then metal = math.max(metal, 0) + m end
			if type(e) == "number" and e >= 0 then energy = math.max(energy, 0) + e end
			perTeam[#perTeam + 1] = tostring(team) .. ":" .. RecNum(m) .. ":" .. RecNum(e)
		end
		RecLog("SNAP s=" .. side .. " t=" .. table.concat(teams, ",") .. " m=" .. RecNum(metal) .. " e=" .. RecNum(energy)
			.. " dev=" .. RecDump(devices) .. " shots=" .. RecDump(recShots[side])
			.. (#teams > 1 and (" tm=" .. table.concat(perTeam, ",")) or ""))
		recShots[side] = {}
	end
end

local function RecStart(restart)
	if recStarted then return end
	recStarted = true
	RecLog("START v=" .. REC_VERSION .. (restart and " restart=1" or ""))
end

-- A restart ("RevertMap" in the log) rewinds the game to frame 2 without reloading this script: the frame jumps back
-- to the beginning. Start a new match then (an instant replay scrubbed back to its start looks the same; train.py
-- ignores what is logged during an instant replay).
local REC_RESTART_FRAMES = 2 * REC_SNAP_FRAMES
local function RecCheckRestart(frame)
	if recStarted and frame < recFrame and frame < REC_RESTART_FRAMES then
		recStarted = false
		recEnded = false
		recLastSnap = -100000
		recShots = { [1] = {}, [2] = {} }
		recFrame = frame
		RecStart(true)
	end
end

local recPrevLoad = Load
function Load(gameStart)
	if recPrevLoad then recPrevLoad(gameStart) end
	RecStart()
end

local recPrevUpdate = Update
function Update(frame)
	if recPrevUpdate then recPrevUpdate(frame) end
	if type(frame) == "number" then
		RecCheckRestart(frame)
		recFrame = frame
	end
	RecStart()
	if not recEnded and recFrame - recLastSnap >= REC_SNAP_FRAMES then
		recLastSnap = recFrame
		local ok, err = pcall(RecSnapshot)
		if not ok then RecLog("ERROR snapshot " .. tostring(err)) end
	end
end

local recPrevOnWeaponFired = OnWeaponFired
function OnWeaponFired(weaponTeamId, saveName, weaponId, projectileNodeId, projectileNodeIdFrom)
	if recPrevOnWeaponFired then recPrevOnWeaponFired(weaponTeamId, saveName, weaponId, projectileNodeId, projectileNodeIdFrom) end
	local side = RecSide(weaponTeamId)
	if recShots[side] and saveName then
		recShots[side][saveName] = (recShots[side][saveName] or 0) + 1
	end
end

local recPrevOnDeviceCompleted = OnDeviceCompleted
function OnDeviceCompleted(teamId, deviceId, saveName)
	if recPrevOnDeviceCompleted then recPrevOnDeviceCompleted(teamId, deviceId, saveName) end
	RecLog("BUILT s=" .. RecSide(teamId) .. " d=" .. tostring(saveName))
end

local recPrevOnDeviceDestroyed = OnDeviceDestroyed
function OnDeviceDestroyed(teamId, deviceId, saveName, nodeA, nodeB, t)
	if recPrevOnDeviceDestroyed then recPrevOnDeviceDestroyed(teamId, deviceId, saveName, nodeA, nodeB, t) end
	RecLog("LOST s=" .. RecSide(teamId) .. " i=" .. tostring(deviceId) .. " d=" .. tostring(saveName))
end

-- Build events, so a fort built by a player can be turned into an AI plan (.dev/tools/fortgen/rec_fort.py)
local recPrevOnNodeCreated = OnNodeCreated
function OnNodeCreated(nodeId, nodeTeamId, pos, isFoundation, selectable, extrusion)
	if recPrevOnNodeCreated then recPrevOnNodeCreated(nodeId, nodeTeamId, pos, isFoundation, selectable, extrusion) end
	if selectable == false or not RecBuildSide(nodeTeamId) then return end
	local ok, err = pcall(function()
		RecLog("NODE s=" .. RecSide(nodeTeamId) .. " t=" .. tostring(nodeTeamId) .. " n=" .. tostring(nodeId)
			.. " p=" .. RecPos(pos) .. " g=" .. (isFoundation and "1" or "0"))
	end)
	if not ok then RecLog("ERROR node " .. tostring(err)) end
end

local recPrevOnNodeDestroyed = OnNodeDestroyed
function OnNodeDestroyed(nodeId, selectable)
	if recPrevOnNodeDestroyed then recPrevOnNodeDestroyed(nodeId, selectable) end
	if selectable == false then return end
	RecLog("UNNODE n=" .. tostring(nodeId))
end

local recPrevOnLinkCreated = OnLinkCreated
function OnLinkCreated(teamId, saveName, nodeA, nodeB, pos1, pos2, extrusion)
	if recPrevOnLinkCreated then recPrevOnLinkCreated(teamId, saveName, nodeA, nodeB, pos1, pos2, extrusion) end
	if not RecBuildSide(teamId) then return end
	local ok, err = pcall(function()
		RecLog("LINK s=" .. RecSide(teamId) .. " t=" .. tostring(teamId) .. " a=" .. tostring(nodeA) .. " b=" .. tostring(nodeB)
			.. " m=" .. tostring(saveName) .. " pa=" .. RecPos(pos1) .. " pb=" .. RecPos(pos2))
	end)
	if not ok then RecLog("ERROR link " .. tostring(err)) end
end

local recPrevOnLinkDestroyed = OnLinkDestroyed
function OnLinkDestroyed(teamId, saveName, nodeA, nodeB, breakType)
	if recPrevOnLinkDestroyed then recPrevOnLinkDestroyed(teamId, saveName, nodeA, nodeB, breakType) end
	if not RecBuildSide(teamId) then return end
	RecLog("UNLINK s=" .. RecSide(teamId) .. " t=" .. tostring(teamId) .. " a=" .. tostring(nodeA) .. " b=" .. tostring(nodeB)
		.. " m=" .. tostring(saveName))
end

local recPrevOnDeviceCreated = OnDeviceCreated
function OnDeviceCreated(teamId, deviceId, saveName, nodeA, nodeB, t, upgradedId)
	if recPrevOnDeviceCreated then recPrevOnDeviceCreated(teamId, deviceId, saveName, nodeA, nodeB, t, upgradedId) end
	if not RecBuildSide(teamId) then return end
	local ok, err = pcall(function()
		local lt = (type(t) == "number") and string.format("%.2f", t) or "-"
		RecLog("DEV s=" .. RecSide(teamId) .. " t=" .. tostring(teamId) .. " i=" .. tostring(deviceId) .. " d=" .. tostring(saveName)
			.. " a=" .. tostring(nodeA) .. " b=" .. tostring(nodeB) .. " lt=" .. lt
			.. " pa=" .. RecNodePos(nodeA) .. " pb=" .. RecNodePos(nodeB) .. " u=" .. tostring(upgradedId or -1))
	end)
	if not ok then RecLog("ERROR device " .. tostring(err)) end
end

local recPrevOnGroundDeviceCreated = OnGroundDeviceCreated
function OnGroundDeviceCreated(teamId, deviceId, saveName, pos, upgrade)
	if recPrevOnGroundDeviceCreated then recPrevOnGroundDeviceCreated(teamId, deviceId, saveName, pos, upgrade) end
	if not RecBuildSide(teamId) then return end
	local ok, err = pcall(function()
		RecLog("GDEV s=" .. RecSide(teamId) .. " t=" .. tostring(teamId) .. " i=" .. tostring(deviceId) .. " d=" .. tostring(saveName)
			.. " p=" .. RecPos(pos))
	end)
	if not ok then RecLog("ERROR ground device " .. tostring(err)) end
end

local recPrevOnDeviceDeleted = OnDeviceDeleted
function OnDeviceDeleted(teamId, deviceId, saveName, nodeA, nodeB, t)
	if recPrevOnDeviceDeleted then recPrevOnDeviceDeleted(teamId, deviceId, saveName, nodeA, nodeB, t) end
	if not RecBuildSide(teamId) then return end
	RecLog("DEL s=" .. RecSide(teamId) .. " i=" .. tostring(deviceId) .. " d=" .. tostring(saveName)
		.. " a=" .. tostring(nodeA) .. " b=" .. tostring(nodeB) .. " pa=" .. RecNodePos(nodeA) .. " pb=" .. RecNodePos(nodeB))
end

local recPrevOnGameResult = OnGameResult
function OnGameResult(winningTeamId, customCondition)
	if recPrevOnGameResult then recPrevOnGameResult(winningTeamId, customCondition) end
	pcall(RecSnapshot)
	RecLog("RESULT w=" .. RecSide(winningTeamId))
	recEnded = true
end
