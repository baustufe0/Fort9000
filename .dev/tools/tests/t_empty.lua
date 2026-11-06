rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion after test 19: the sniper stays in B1; C1, B2 and D1 fill in turn (heavy1, heavy2, heavy5), the mortars sold for D1. What the tech
-- allows, a kind not yet there first. Vanilla-8, team 102.
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
local own = { [100] = "reactor", [110] = "store", [111] = "store", [112] = "battery", [113] = "battery", [114] = "battery" }
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
print("plan: B1=" .. dev("B1") .. " B2=" .. dev("B2") .. " C1=" .. dev("C1") .. " D1=" .. dev("D1"))
local k1
for k, a in ipairs(Fort) do if a.Socket == "B1" and a.DeviceSaveName == "sniper" then k1 = k end end
own[201] = "sniper"; data.Devices[201] = k1
local function think(n)
  for i = 1, n do data.Rebuild = {}; CAI_Think(); data.fortIndex = #Fort + 1 end
end
local function fired(name)
  for _, m in ipairs(data.CAIModules.list) do if m.name == name then return tostring(m.fired == true) end end
end
data.fortIndex = #Fort + 1
think(3)
print("no plant: B1=" .. dev("B1") .. " B2=" .. dev("B2") .. " sold=" .. sold)
own[300] = "munitions"
res.metal = 100; res.energy = 500
think(1)
print("plant, poor: C1=" .. dev("C1"))
res.metal = 900; res.energy = 9000
think(1)
print("plant: C1=" .. dev("C1") .. " B2=" .. dev("B2") .. " sold=" .. sold)
own[301] = "cannon"
think(1)
print("one heavy: B2=" .. dev("B2") .. " D1=" .. dev("D1"))
think(13)
print("still one heavy: D1=" .. dev("D1") .. " upgrade=" .. fired("upgrade"))
local kM = {}
for k, a in ipairs(Fort) do if a.Socket == "M1" or a.Socket == "M2" then kM[#kM + 1] = k end end
own[401] = "mortar"; data.Devices[401] = kM[1]; own[402] = "mortar"; data.Devices[402] = kM[2]
own[302] = "cannon20mm"
res.metal = 700
think(1)
print("two heavy, no metal over: D1=" .. dev("D1") .. " sold=" .. sold)
res.metal = 900
think(1)
print("two heavy: D1=" .. dev("D1") .. " sold=" .. sold .. " upgrade=" .. fired("upgrade"))
own[303] = "cannon"
think(1)
print("D1 placed: sold=" .. sold .. " mortars=" .. dev("M1") .. " sniper=" .. tostring(own[201]))
-- refused: the rebuild is parked after RefusedWait seconds
local kc
for k, a in ipairs(Fort) do if a.Socket == "C1" and a.Type == CREATE_DEVICE then kc = k end end
data.Rebuild = { [kc] = true }
data.CAI.heavyRefused = 4000
CAI_ParkRefused(4010)
print("refused 10 s: queued=" .. tostring(data.Rebuild[kc]))
CAI_ParkRefused(4031)
print("refused 31 s: queued=" .. tostring(data.Rebuild[kc]))
-- the storage full for a minute
res = { metal = 1200, energy = 9000 }
data.CAI.capSince = nil
local ku
for k, a in ipairs(Fort) do if a.DeviceSaveName == "upgrade" then ku = k end end
data.Rebuild = { [ku] = true }
data.CAI.heavyRefused = 4000
CAI_ParkRefused(4031)
print("centre refused: queued=" .. tostring(data.Rebuild[ku]) .. " retry=" .. tostring(data.CAI.techRetry and data.CAI.techRetry.at))
print("full, at once: " .. tostring(CAI_AtCap(5000, 60)))
print("full for 61 s: " .. tostring(CAI_AtCap(5061, 60)))
