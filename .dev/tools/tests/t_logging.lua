-- The logging switch: arg[1] = "recorder", "ai" or "publish"
MAX_SIDES = 100
local lines = 0
function Log(s) lines = lines + 1; print("LOG " .. s) end
function Notice(s) print("NOTICE " .. s) end
local client = 0
function GetLocalClientIndex() return client end
function IsConsoleActive() return false end

local function chord(alsoDown)
	OnKey("left control", true); OnKey("left shift", true); OnKey("l", true, alsoDown); OnKey("l", false)
	OnKey("left shift", false); OnKey("left control", false)
end

if arg[1] == "recorder" then
	function GetDeviceCountSide() return 0 end
	function GetTeamResources() return { metal = 1, energy = 2 } end
	dofile("mods/fort9000dev/script.lua")
	-- the key press only sends the event, with the new state and this player's index
	function SendScriptEvent(name, params, file, toSelf)
		print("EVENT " .. name .. " " .. params .. " file=[" .. file .. "] self=" .. tostring(toSelf))
		loadstring(name .. "(" .. params .. ")")()
	end
	Load(true)
	Fort9000SetLogging(false, 0)
	lines = 0
	OnDeviceCompleted(1, 5, "cannon"); Update(1000)
	print("off lines=" .. lines)
	client = 1
	Fort9000SetLogging(true, 0)     -- another player's key press
	client = 0
	OnDeviceCompleted(1, 5, "cannon")
	print("other player lines=" .. lines)
	OnKey("l", true); OnKey("l", false)
	print("plain l lines=" .. lines)
	chord(true)                     -- a key press recorded in a replay
	print("replay key lines=" .. lines)
	chord()                         -- on
	OnDeviceCompleted(1, 5, "cannon")
	chord()                         -- off again
	lines = 0
	OnDeviceCompleted(1, 5, "cannon")
	print("off again lines=" .. lines)
elseif arg[1] == "recorder_start" then
	-- a match that begins with logging off writes START when it is switched on
	function GetDeviceCountSide() return 0 end
	function GetTeamResources() return { metal = 1, energy = 2 } end
	local f = assert(io.open("mods/fort9000dev/script.lua", "rb")); local src = f:read("*a"); f:close()
	assert(loadstring((src:gsub("%-%-%[%[LOGGING%]%] true", "--[[LOGGING]] false"))))()
	Load(true); Update(100)
	print("published lines=" .. lines)
	Fort9000SetLogging(true, 0)
	Fort9000SetLogging(false, 0); Fort9000SetLogging(true, 0)
elseif arg[1] == "ai" then
	teamId = 102; enemyTeamId = 1
	CS_SUCCESS = 0; CS_INSUFFICIENTRESOURCES = -3; CS_UNSTABLE = -14; CS = { [0] = "CS_SUCCESS", [-3] = "CS_INSUFFICIENTRESOURCES", [-14] = "CS_UNSTABLE" }
	data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 }, fortIndex = 12 }
	HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
	function ScheduleCall() end
	function ScheduledCallCountOfFunc() return 0 end
	function GetTeamResources() return { metal = 0, energy = 0 } end
	function Load() end
	function MirrorFort() end
	function OnWeaponFired() end
	function OnDeviceDestroyed() end
	dofile("mods/fort9000dev/ai/ai.lua")
	CAI_Log("visible by default")
	Fort9000SetLogging(false, 0)
	lines = 0
	-- the arguments still run: a sale inside a log call must happen with logging off
	local sold = false
	local function sell() sold = true; return "ok" end
	CAI_Log("SOCKET result=" .. tostring(sell()))
	CAI_LogShape("minute")
	print("ai off lines=" .. lines .. " sold=" .. tostring(sold) .. " shapes=" .. CAI_ShapeCount)
	client = 1
	Fort9000SetLogging(true, 0)
	client = 0
	print("ai other player=" .. tostring(CAI_Logging))
	Fort9000SetLogging(true, 0)
	CAI_Log("visible again")
end
