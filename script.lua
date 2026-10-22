-- FORT 9000 - Recorder
-- Laeuft als Mod-Script in jeder Partie und auch beim Abspielen eines Replays.
-- Schreibt Spielzustand und Ereignisse beider Seiten mit [CREC] ins Log (users/<id>/log.txt).
-- tools/train.py lernt daraus. Der Recorder liest nur und veraendert nichts am Spiel.
--
-- Zeilenformat (f = Spielframe):
--   [CREC] f=0 START v=1
--   [CREC] f=250 SNAP s=1 m=1200 e=3400 dev=cannon:2,mortar:1 shots=cannon:3
--   [CREC] f=260 BUILT s=2 d=sniper
--   [CREC] f=300 LOST s=1 d=mortar
--   [CREC] f=900 RESULT w=1

local REC_VERSION = 2
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
			-- echte Team-Nummer (z.B. 102) statt Seitennummer, sonst liefert GetTeamResources Startwerte
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
	RecLog("LOST s=" .. RecSide(teamId) .. " d=" .. tostring(saveName))
end

local recPrevOnGameResult = OnGameResult
function OnGameResult(winningTeamId, customCondition)
	if recPrevOnGameResult then recPrevOnGameResult(winningTeamId, customCondition) end
	pcall(RecSnapshot)
	RecLog("RESULT w=" .. RecSide(winningTeamId))
	recEnded = true
end
