-- Rockets hold fire while the plan's next device is short of energy only (2v6-3, match 07.11.2026: build stood at 188 of 342)
rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
MAX_SIDES = 100; teamId = 102; enemyTeamId = 1
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local res = { metal = 900, energy = 500 }
function GetTeamResources() return res end
function Load() end
function MirrorFort() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local types = { [1] = "rocketemp", [2] = "sniper" }
function GetDeviceType(id) return types[id] end
function GetDeviceCost(name) return { metal = 600, energy = 3000 } end
dofile("mods/fort9000dev/ai/ai.lua")
Fort = { { DeviceSaveName = "upgrade" } }
data.fortIndex = 1
data.CAI = { fireClock = 100 }
print("rocket short: " .. tostring(CAI_BuildHoldsFire(1)))
print("sniper short: " .. tostring(CAI_BuildHoldsFire(2)))
data.CAI.fireClock = 189
local mid = CAI_BuildHoldsFire(1)
data.CAI.fireClock = 190
print("after 90 s: " .. tostring(CAI_BuildHoldsFire(1)))
data.CAI.fireClock = 220
print("after 120 s: " .. tostring(CAI_BuildHoldsFire(1)))
res = { metal = 100, energy = 500 }
print("both short: " .. tostring(CAI_BuildHoldsFire(1)))
res = { metal = 900, energy = 3000 }
print("energy there: " .. tostring(CAI_BuildHoldsFire(1)))
