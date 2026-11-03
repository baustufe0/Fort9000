rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion after test 3: socket upgrade. Once the AI is rich and the tech stands, a socket's sniper is sold
-- (DestroyDeviceById, marked DeviceDeleteToRebuild) and its plan action rebuilt with a heavy weapon; B2 first (Rank 1),
-- B1 Hold seconds later. Vanilla-8 plan, team 102, mirrored; the built-in AI's delete-to-rebuild path is mocked.
MAX_SIDES = 100
DD_SUCCESS = -8
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local rich = { metal = 900, energy = 9000 }
local res = { metal = 0, energy = 0 }
function GetTeamResources() return res end
local own = { [100] = "reactor" }               -- own devices (side 2): id -> type
local function ids() local t = {} for id in pairs(own) do t[#t + 1] = id end table.sort(t) return t end
function IsDeviceFullyBuilt(id) return true end
function GetDeviceCountSide(side) return side == 2 and #ids() or 0 end
function GetDeviceIdSide(side, i) return ids()[i + 1] end
function GetDeviceType(id) return own[id] end
function Load(g)
  for i = 1, 5 do table.insert(Fort, i, { Type = 3, MaterialSaveName = "bracing", ExistingFort = true }) end
  data.fortIndex = 6
  data.Rebuild = {}
  data.Devices = {}
  data.DeviceDeleteToRebuild = {}
  enemyTeamId = 1
end
function OnWeaponFired() end
function OnDeviceDestroyed() end
function QueueDeviceRebuild(deviceId)           -- the built-in AI's: queue the device's action
  data.Rebuild[data.Devices[deviceId]] = true
  data.Devices[deviceId] = nil
end
local sold = {}
function DestroyDeviceById(id)                  -- the reclaim; the built-in AI's OnDeviceDeleted queues a marked device
  if own[id] == nil then return -1 end
  own[id] = nil
  sold[#sold + 1] = id
  if data.DeviceDeleteToRebuild[id] then QueueDeviceRebuild(id) end
  return DD_SUCCESS
end
function MirrorFort(pivot, offset)
  for _, a in ipairs(Fort) do for _, k in ipairs({"PosA","PosB","NewNodePos","GroundPosition"}) do
    local p = a[k]; if p then p.x = 2*pivot - p.x + offset.x; p.y = p.y + offset.y end end end
end
dofile("ai/forts/vanilla/mid/fort-t1f1-Template-1.lua")
dofile("mods/fort9000dev/ai/ai.lua")
FortPlanConfig.Force = { Vanilla = "fort-t1f1-Vanilla-8.lua" }
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)

local function Find(socket, dev)
  for k, a in ipairs(Fort) do if a.Socket == socket and a.DeviceSaveName == dev then return k end end
end
local k1, k2 = Find("B1", "sniper"), Find("B2", "sniper")
data.fortIndex = #Fort + 1
own[201] = "sniper"; data.Devices[201] = k1
own[202] = "sniper"; data.Devices[202] = k2
print("sockets: " .. tostring(k1 ~= nil) .. " " .. tostring(k2 ~= nil))
-- rich, but no factory or munitions plant: nothing to upgrade to
res = rich
for i = 1, 6 do CAI_Think() end
print("no tech: " .. Fort[k2].DeviceSaveName .. " sold=" .. #sold)
-- the factory stands: B2 (rank 1) is sold and its action rebuilt as a laser; B1 waits
own[300] = "factory"
for i = 1, 4 do CAI_Think() end
print("factory: B2=" .. Fort[k2].DeviceSaveName .. " rebuild=" .. tostring(data.Rebuild[k2]) .. " B1=" .. Fort[k1].DeviceSaveName .. " sold=" .. #sold)
-- the rebuilt laser stands; poor for a while: B1 stays a sniper
own[203] = "laser"; data.Devices[203] = k2
res = { metal = 100, energy = 500 }
for i = 1, 20 do CAI_Think() end
print("poor: B1=" .. Fort[k1].DeviceSaveName)
-- rich again: B1 too (the laser in B2 is no small weapon, it stays)
res = rich
for i = 1, 6 do CAI_Think() end
print("later: B1=" .. Fort[k1].DeviceSaveName .. " B2=" .. Fort[k2].DeviceSaveName .. " sold=" .. #sold)
-- a second run: B2 already a laser, the munitions plant stands: B1 takes the 20mm (a mix), not a second laser
own[201] = "sniper"; data.Devices[201] = k1; Fort[k1].DeviceSaveName = "sniper"
own[400] = "munitions"
for i = 1, 16 do CAI_Think() end
print("mix: B1=" .. Fort[k1].DeviceSaveName)
