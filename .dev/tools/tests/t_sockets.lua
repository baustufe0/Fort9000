rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion step 2: socket state and swaps (FortSockets, Socket = on device actions) and repeatable modules
-- (Repeat / Cooldown). Vanilla-8 plan, team 102, mirrored; the built-in AI's rebuild queue is mocked.
MAX_SIDES = 100
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 0, energy = 0 } end
local own = { "reactor" }                       -- own devices (side 2)
function GetDeviceCountSide(side) return side == 2 and #own or 0 end
function GetDeviceIdSide(side, i) return 100 + i end
function GetDeviceType(id) return own[id - 99] end
function Load(g)
  for i = 1, 5 do table.insert(Fort, i, { Type = 3, MaterialSaveName = "bracing", ExistingFort = true }) end
  data.fortIndex = 6
  data.Rebuild = {}
  data.Devices = {}
  enemyTeamId = 1
end
function OnWeaponFired() end
function OnDeviceDestroyed() end
function QueueDeviceRebuild(deviceId)           -- the built-in AI's: queue the device's action
  data.Rebuild[data.Devices[deviceId]] = true
  data.Devices[deviceId] = nil
end
function MirrorFort(pivot, offset)
  for _, a in ipairs(Fort) do for _, k in ipairs({"PosA","PosB","NewNodePos","GroundPosition"}) do
    local p = a[k]; if p then p.x = 2*pivot - p.x + offset.x; p.y = p.y + offset.y end end end
end
dofile("ai/forts/vanilla/mid/fort-t1f1-Template-1.lua")
dofile("mods/fort9000dev/ai/ai.lua")
FortPlanConfig.Force = { Vanilla = "fort-t1f1-Vanilla-8.lua" }
local plan = CAI_Plan.maps.Vanilla.plans["fort-t1f1-Vanilla-8.lua"]
-- a repeatable module (twice more, 10 s apart), by time
table.insert(plan.FortModules, { Name = "again", Trigger = { Time = 5 }, Requires = 0, Repeat = 2, Cooldown = 10, Actions = {
  { Type = 3, OriginalNodeAId = 47, PosA = { x = -2996.23, y = 503.57 }, OriginalNodeBId = 48, PosB = { x = -3096.14, y = 502.53 }, MaterialSaveName = "bracing" } } })
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)

local function Find(socket, dev)
  for k, a in ipairs(Fort) do if a.Socket == socket and a.DeviceSaveName == dev then return k end end
end
local k = Find("B1", "sniper")
data.fortIndex = #Fort + 1                    -- the plan is built: modules go in at its end, k stays
print("B1 action: " .. tostring(k ~= nil))
-- the B1 sniper is lost twice within the window: the second loss swaps it for the first loadout whose tech stands
data.Devices[501] = k; CAI_Think(); QueueDeviceRebuild(501)
data.Devices[502] = k; CAI_Think(); QueueDeviceRebuild(502)
print("after two losses: " .. Fort[k].DeviceSaveName .. " rebuild=" .. tostring(data.Rebuild[k]))
-- with a munitions plant standing, two more losses: from the machine gun on to the next ready loadout, the sniper
own = { "reactor", "munitions" }
data.Devices[503] = k; CAI_Think(); QueueDeviceRebuild(503)
data.Devices[504] = k; CAI_Think(); QueueDeviceRebuild(504)
print("after four losses: " .. Fort[k].DeviceSaveName)
-- a loss long after the last one starts a new count
for i = 1, 40 do CAI_Think() end
data.Devices[505] = k; QueueDeviceRebuild(505)
print("late loss: " .. Fort[k].DeviceSaveName .. " losses=" .. #data.CAI.sockets.B1.losses)
-- the repeatable module: at 5 s, then twice more 10 s apart, then no more
local n = 0
for _, a in ipairs(Fort) do if a.OriginalNodeAId == 47 and a.OriginalNodeBId == 48 and a.MaterialSaveName == "bracing" and not a.CAI_K then n = n + 1 end end
print("again inserted " .. n .. " times")
