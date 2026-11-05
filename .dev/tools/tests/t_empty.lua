rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion after test 10: one sniper. Sockets B2 and C1 stand empty for the first two heavy weapons (modules heavy1, heavy2:
-- what the tech allows, nothing sold); the one sniper in B1 is sold only once two heavy weapons stand. Vanilla-8, team 102.
MAX_SIDES = 100
DD_SUCCESS = -8
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local res = { metal = 900, energy = 9000 }
function GetTeamResources() return res end
local own = { [100] = "reactor" }
local function ids() local t = {} for id in pairs(own) do t[#t + 1] = id end table.sort(t) return t end
function IsDeviceFullyBuilt(id) return true end
function GetDeviceCountSide(side) return side == 2 and #ids() or 0 end
function GetDeviceIdSide(side, i) return ids()[i + 1] end
function GetDeviceType(id) return own[id] end
function GetDeviceCost(w) return { metal = 500, energy = 3000 } end
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
local sold = 0
function DestroyDeviceById(id)
  own[id] = nil
  sold = sold + 1
  if data.DeviceDeleteToRebuild[id] then data.Rebuild[data.Devices[id]] = true; data.Devices[id] = nil end
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
local function dev(socket)
  local d = {}
  for _, a in ipairs(Fort) do if a.Socket == socket and a.Type == CREATE_DEVICE then d[#d + 1] = a.DeviceSaveName end end
  return #d > 0 and table.concat(d, ",") or "-"
end
print("plan: B1=" .. dev("B1") .. " B2=" .. dev("B2") .. " C1=" .. dev("C1"))
local k1
for k, a in ipairs(Fort) do if a.Socket == "B1" and a.DeviceSaveName == "sniper" then k1 = k end end
own[201] = "sniper"; data.Devices[201] = k1
local function think(n)
  for i = 1, n do data.Rebuild = {}; CAI_Think(); data.fortIndex = #Fort + 1 end
end
data.fortIndex = #Fort + 1
think(3)
print("no plant: B2=" .. dev("B2") .. " sold=" .. sold)
own[300] = "munitions"
think(3)
print("plant: B2=" .. dev("B2") .. " C1=" .. dev("C1") .. " sold=" .. sold)
own[301] = "cannon"
think(1)
print("one heavy: C1=" .. dev("C1") .. " B1 sold=" .. sold)
think(13)
print("still one heavy: sold=" .. sold)
own[302] = "cannon20mm"
think(14)
print("two heavy: sold=" .. sold .. " wanted=" .. tostring(data.CAI.sockets.B1.current))
-- the second heavy weapon refused: the sniper goes HeavyWait seconds after the first
own[302] = nil
own[401] = "sniper"; data.Devices[401] = k1
CAI_SocketSet("B1", "sniper")
data.CAI.sockets.B1.selling = nil; data.CAI.upgradeAt = -1000; data.CAI.richFor = 100; data.CAI.firstHeavyAt = 0
sold = 0
CAI_SocketUpgrade(299)
print("refused, waiting: sold=" .. sold)
CAI_SocketUpgrade(301)
print("refused, waited: sold=" .. sold)
-- refused: the sniper goes after RefusedWait seconds, the refused weapon's rebuild is parked
own[401] = "sniper"; data.Devices[401] = k1
CAI_SocketSet("B1", "sniper")
data.CAI.sockets.B1.selling = nil; data.CAI.upgradeAt = -1000; data.CAI.richFor = 100; data.CAI.firstHeavyAt = 4000
local kc
for k, a in ipairs(Fort) do if a.Socket == "C1" and a.Type == CREATE_DEVICE then kc = k end end
data.Rebuild = { [kc] = true }
data.CAI.heavyRefused = 4000
sold = 0
CAI_SocketUpgrade(4010)
print("refused 10 s: sold=" .. sold .. " queued=" .. tostring(data.Rebuild[kc]))
data.CAI.richFor = 100
CAI_SocketUpgrade(4031)
print("refused 31 s: sold=" .. sold .. " queued=" .. tostring(data.Rebuild[kc]))
