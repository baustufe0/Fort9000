-- Rebuild cap: a machine gun that keeps dying at one plan action stops being rebuilt; one that survives longer
-- between losses, and devices without a cap (turbine), are always rebuilt.
MAX_SIDES = 100; teamId = 102; enemyTeamId = 1
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 }, fortIndex = 20,
  Rebuild = {}, Devices = {} }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 600, energy = 3000 } end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local queued = {}
function QueueDeviceRebuild(id)   -- the built-in AI's version
  local k = data.Devices[id]
  queued[k] = (queued[k] or 0) + 1
  data.Rebuild[k] = true
  data.Devices[id] = nil
end
Fort = {} for i = 1, 30 do Fort[i] = { Type = 5, DeviceSaveName = "bracing" } end FortPos = { x = 0, y = 0 }
Fort[10].DeviceSaveName = "machinegun"; Fort[11].DeviceSaveName = "turbine"; Fort[12].DeviceSaveName = "machinegun"
dofile("mods/fort9000dev/ai/ai.lua")
Load(true)
local id = 100
local function Lose(k)
  id = id + 1
  data.Devices[id] = k
  QueueDeviceRebuild(id)
  data.Rebuild[k] = nil   -- rebuilt
end
local function Wait(s) for _ = 1, s / Strategy.ThinkInterval do CAI_Think() end end
for _ = 1, 6 do Lose(10); Lose(11); Wait(30) end   -- every 30 s
for _ = 1, 4 do Lose(12); Wait(200) end            -- every 200 s: survives longer than the window
print(string.format("queued: mg=%d turbine=%d mg-slow=%d devices-left=%d",
  queued[10] or 0, queued[11] or 0, queued[12] or 0, next(data.Devices) and 1 or 0))
