rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion step 4: posture engine (scores, hysteresis, target boost, posture-triggered module, preferred loadout).
-- Vanilla-8 plan, team 102, mirrored; enemy and own devices mocked.
MAX_SIDES = 100
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon", "mortar", "mine" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 100, energy = 1000 } end
function NodePosition() return nil end
local enemy, own = { "reactor" }, { "reactor", "workshop" }
function GetDeviceCountSide(side) return side == 1 and #enemy or #own end
function GetDeviceIdSide(side, i) return side == 1 and 100 + i or 200 + i end
function GetDeviceType(id) if id >= 200 then return own[id - 199] end return enemy[id - 99] end
function Load(g)
  for i = 1, 5 do table.insert(Fort, i, { Type = 3, MaterialSaveName = "bracing", ExistingFort = true }) end
  data.fortIndex = 6
  data.Rebuild, data.Devices = {}, {}
  enemyTeamId = 1
end
function OnWeaponFired() end
function OnDeviceDestroyed() end
function QueueDeviceRebuild(deviceId)
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
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)
data.fortIndex = #Fort + 1

CAI_Think()                                     -- 5 s: Pressure
-- the enemy builds two mortars and fires: AntiArtillery, but only once Pressure has held 30 s
enemy = { "reactor", "mortar", "mortar" }
for i = 1, 4 do OnWeaponFired(1, "mortar", 300 + i, 0, 0) end
CAI_Think()                                     -- 10 s
print("at 10 s: " .. data.CAI.posture)
for i = 1, 5 do OnWeaponFired(1, "mortar", 310 + i, 0, 0); CAI_Think() end
print("at 35 s: " .. data.CAI.posture .. " boost mortar=" .. tostring(data.CAI.postureBoost and data.CAI.postureBoost.mortar))
print("heavy targets: " .. table.concat(data.HeavyArmsPrioritiesOverride, ","))
-- the socket zone takes heavy damage: Siege after the hold, the factory module goes in
data.CAI.zoneDmg = { Z1 = 3000 }; data.CAI.zoneTotal = { Z1 = 3000 }
for i = 1, 7 do data.CAI.zoneDmg.Z1 = 3000; CAI_Think() end
print("under siege: " .. data.CAI.posture)
-- with the factory standing, B1 loses its sniper twice: Siege prefers the laser
own = { "reactor", "workshop", "factory" }
local k
for i, a in ipairs(Fort) do if a.Socket == "B1" and a.DeviceSaveName == "sniper" then k = i end end
data.Devices[501] = k; QueueDeviceRebuild(501)
data.Devices[502] = k; QueueDeviceRebuild(502)
print("B1 now: " .. Fort[k].DeviceSaveName)
