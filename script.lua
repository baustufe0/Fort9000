-- FORT 9000 - Recorder
-- Runs as a mod script in every match and also when a replay is played.
-- Writes game state and events of both sides to the log with [CREC] (users/<id>/log.txt).
-- tools/train.py learns from it. The recorder only reads and changes nothing in the game.
--
-- Line format (f = game frame):
--   [CREC] f=0 START v=1
--   [CREC] f=250 SNAP s=1 m=1200 e=3400 dev=cannon:2,mortar:1 shots=cannon:3
--   [CREC] f=260 BUILT s=2 d=sniper
--   [CREC] f=300 LOST s=1 i=17 d=mortar
--   [CREC] f=900 RESULT w=1
-- Build events of both sides (tools/fortgen/rec_fort.py turns them into an AI build plan; t = team, p = x,y):
--   [CREC] f=40 NODE s=1 t=1 n=1203 p=-3100.00,105.00 g=0
--   [CREC] f=41 LINK s=1 t=1 a=56 b=1203 m=bracing pa=-3093.19,205.21 pb=-3100.00,105.00
--   [CREC] f=42 UNLINK s=1 t=1 a=56 b=1203 m=bracing
--   [CREC] f=43 UNNODE n=1203
--   [CREC] f=50 DEV s=1 t=1 i=17 d=mortar a=55 b=58 lt=0.50 pa=-2945.11,206.49 pb=-2846.18,203.99 u=-1
--   [CREC] f=51 GDEV s=1 t=1 i=18 d=mine p=-3029.41,700.00
--   [CREC] f=60 DEL s=1 i=17 d=mortar a=55 b=58 pa=-2945.11,206.49 pb=-2846.18,203.99

local REC_VERSION = 3
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
		local team = nil
		for i = 0, count - 1 do
			local id = GetDeviceIdSide(side, i)
			local saveName = GetDeviceType(id)
			if saveName then
				devices[saveName] = (devices[saveName] or 0) + 1
			end
			-- real team number (e.g. 102) instead of side number, otherwise GetTeamResources returns starting values
			if team == nil and saveName == "reactor" and type(GetDeviceTeamIdActual) == "function" then
				team = GetDeviceTeamIdActual(id)
			end
		end
		local metal, energy = -1, -1
		local ok, res = pcall(GetTeamResources, team or side)
		if ok and res then
			metal, energy = res.metal, res.energy
		end
		RecLog("SNAP s=" .. side .. " t=" .. tostring(team or side) .. " m=" .. RecNum(metal) .. " e=" .. RecNum(energy)
			.. " dev=" .. RecDump(devices) .. " shots=" .. RecDump(recShots[side]))
		recShots[side] = {}
	end
end

local function RecStart()
	if recStarted then return end
	recStarted = true
	RecLog("START v=" .. REC_VERSION)
end

local recPrevLoad = Load
function Load(gameStart)
	if recPrevLoad then recPrevLoad(gameStart) end
	RecStart()
end

local recPrevUpdate = Update
function Update(frame)
	if recPrevUpdate then recPrevUpdate(frame) end
	if type(frame) == "number" then recFrame = frame end
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

-- Build events, so a fort built by a player can be turned into an AI plan (tools/fortgen/rec_fort.py)
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
