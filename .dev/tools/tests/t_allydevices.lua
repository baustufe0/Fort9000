-- Team games: a side's device list holds all its teams; the AI may count only its own team's plant and weapons
-- (2v6, 06.11.2026: T502 took T302's munitions plant for its own and never got a heavy weapon).
rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
MAX_SIDES = 100; teamId = 502; enemyTeamId = 1
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 0, energy = 0 } end
function Load() end
function MirrorFort() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local devices = {
	{ type = "munitions", team = 302 }, { type = "cannon", team = 302 }, { type = "battery", team = 302 },
	{ type = "factory", team = 502 }, { type = "sniper", team = 502 }, { type = "battery", team = 502 },
}
function GetDeviceCountSide(side) return side == 2 and #devices or 0 end
function GetDeviceIdSide(side, i) return i + 1 end
function GetDeviceType(id) return devices[id].type end
function GetDeviceTeamIdActual(id) return devices[id].team end
function IsDeviceFullyBuilt() return true end
dofile("mods/fort9000dev/ai/ai.lua")
local own = CAI_OwnDevices(true)
print("own munitions=" .. tostring(own.munitions) .. " factory=" .. tostring(own.factory) .. " battery=" .. tostring(own.battery))
print("own heavy=" .. CAI_HeavyCount(true))
-- the front strip restores armour once the heavy weapons stand, but no more of them than a plan without sockets builds
local cfg = { RestoreHeavy = 2 }
local function need(devs, sockets)
  Fort = {}
  for i, d in ipairs(devs) do Fort[i] = { DeviceSaveName = d } end
  return CAI_StripRestoreHeavy({ sockets = sockets }, cfg)
end
print(string.format("restore needs: rockets %d, one 20mm %d, two lasers %d, sockets %d", need({ "rocket", "rocketemp" }), need({ "cannon20mm" }),
  need({ "laser", "laser", "laser" }), need({}, {})))
