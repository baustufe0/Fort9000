rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Buzzsaw (07.11.2026): its sight (fires only at enemy wood near an enemy device; the ray is mocked), its rebuild after it
-- used itself up (once, never with a plant standing, never as a socket loss) and Vanilla-8's module trigger NoTech.
-- Vanilla-8 plan, team 102, mirrored; the built-in AI's rebuild queue is mocked.
MAX_SIDES = 100
RAY_EXCLUDE_CONSTRUCTION, RAY_ALLIED_BG_BLOCKS, RAY_EXCLUDE_DYNAMIC_TERRAIN = 1, 2, 4
RAY_HIT_WEAPON, RAY_HIT_DEVICE, RAY_HIT_STRUCTURE, RAY_HIT_NOTHING = 11, 12, 13, 14
data = { OffensiveFireProbability = { cannon = 0.8, sniper = 0.6 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper", "reactor" }
WeaponFireBlockedByStructure = {}; WeaponFindTargetFunction = {}
data.ProjectileHitpoints = {}; data.CustomWeaponPriorities = {}; data.WeaponTargetStructureAttempts = {}
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local energy = 0
function GetTeamResources() return { metal = 1000, energy = energy } end
local own = { "reactor", "workshop" }           -- own devices (side 2)
function IsDeviceFullyBuilt(id) return true end
function GetDeviceCountSide(side) return side == 2 and #own or 0 end
function GetDeviceIdSide(side, i) return 100 + i end
local enemy = { [60] = "turbine", [61] = "sniper" }
function GetDeviceType(id) return own[id - 99] or enemy[id] end
function IsCloaked(id) return false end
function GetDevicePosition(id) return { x = -3000, y = 300 } end
function GetDeviceCentrePosition(id) return { x = -3000, y = 270 } end
function GetWeaponTypeRoundsEachBurst(saveName, team) return 3 end
function Load(g)
  for i = 1, 5 do table.insert(Fort, i, { Type = 3, MaterialSaveName = "bracing", ExistingFort = true }) end
  data.fortIndex = 6
  data.Rebuild = {}
  data.Devices = {}
  enemyTeamId = 1
end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local queued = 0
function QueueDeviceRebuild(deviceId)           -- the built-in AI's: queue the device's action
  queued = queued + 1
  data.Rebuild[data.Devices[deviceId]] = true
  data.Devices[deviceId] = nil
end
function MirrorFort(pivot, offset)
  for _, a in ipairs(Fort) do for _, k in ipairs({"PosA","PosB","NewNodePos","GroundPosition"}) do
    local p = a[k]; if p then p.x = 2*pivot - p.x + offset.x; p.y = p.y + offset.y end end end
end
-- the mocked ray: its first hit (side, material) and where, relative to the point aimed at
local ray = { hit = RAY_HIT_STRUCTURE, side = 1, mat = "bracing", off = 20 }
local aim
function CastRayFromDevice(id, pos, hitpoints, flags, fieldFlags) aim = pos; return ray.hit end
function GetRayHitSideId() return ray.side end
function GetRayHitMaterialSaveName() return ray.mat end
function GetRayHitPosition() return { x = aim.x + ray.off, y = aim.y } end
dofile("ai/forts/vanilla/mid/fort-t1f1-Template-1.lua")
dofile("mods/fort9000dev/ai/ai.lua")
FortPlanConfig.Force = { Vanilla = "fort-t1f1-Vanilla-8.lua" }
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)

print("init: " .. tostring(WeaponFindTargetFunction.buzzsaw) .. " blocked=" .. tostring(WeaponFireBlockedByStructure.buzzsaw)
  .. " priorities=" .. #data.CustomWeaponPriorities.buzzsaw .. " attempts=" .. data.WeaponTargetStructureAttempts.buzzsaw)
local devices = { turbine = { 60 }, sniper = { 61 } }
local function try()
  local t = CAI_BuzzsawTarget(7, { x = 3000, y = 200 }, devices)
  return t and ("y" .. t.y) or "hold"
end
print("wood at the turbine's strut: " .. try())
ray.mat = "armour"
print("armour in front: " .. try())
ray.mat = "backbracing"; ray.off = 200
print("background bracing 200 off: " .. try())
ray.off = 400
print("wood 400 off: " .. try())
ray.mat = "bracing"; ray.off = 10; ray.side = 2
print("own wood in the way: " .. try())
ray.side = 1; ray.hit = RAY_HIT_DEVICE
print("the device itself: " .. try())
ray.hit = RAY_HIT_STRUCTURE
local b = data.CAI.buzzsaw
print("counts: found=" .. b.found .. " hold=" .. b.hold)

-- the module: Vanilla-8's buzzsaw goes in only while no plant stands
local mod
for _, m in ipairs(data.CAIModules.list) do if m.name == "buzzsaw" then mod = m end end
print("module: socket=" .. tostring(mod.socket) .. " notech=" .. tostring(mod.trigger.NoTech) .. " actions=" .. #mod.actions
  .. " swap=" .. tostring(mod.actions[1].MaterialSaveName) .. " device=" .. tostring(mod.actions[2].DeviceSaveName))
-- every other module done, so only this one can go in; the plan is built
for _, m in ipairs(data.CAIModules.list) do if m ~= mod then m.fired = true end end
data.fortIndex = #Fort + 1
energy = 5000
own = { "reactor", "workshop", "factory" }
for i = 1, 60 do CAI_Think() end
print("with a factory: fired=" .. tostring(mod.fired == true))
own = { "reactor", "workshop" }
CAI_Think()
print("without a plant: fired=" .. tostring(mod.fired == true))
local k
for i, a in ipairs(Fort) do if a.DeviceSaveName == "buzzsaw" then k = i end end
print("buzzsaw action: socket=" .. tostring(k and Fort[k].Socket) .. " current=" .. tostring(data.CAI.sockets.B2.current))

-- used up: 9 blades (three volleys), then lost. Rebuilt once, never as a socket loss
data.Devices[701] = k
for i = 1, 9 do OnWeaponFired(teamId, "buzzsaw", 701, 0, 0) end
QueueDeviceRebuild(701)
print("first: queued=" .. queued .. " rebuild=" .. tostring(data.Rebuild[k]) .. " losses=" .. #data.CAI.sockets.B2.losses)
data.Rebuild[k] = nil
data.Devices[702] = k
for i = 1, 9 do OnWeaponFired(teamId, "buzzsaw", 702, 0, 0) end
QueueDeviceRebuild(702)
print("second: queued=" .. queued .. " rebuild=" .. tostring(data.Rebuild[k]) .. " socket=" .. tostring(Fort[k].Socket)
  .. " devices=" .. tostring(data.Devices[702]))
-- a fresh one with a plant standing: not rebuilt at all
data.CAI.buzzsaw.rearms = {}
Fort[k].Socket = "B2"
own = { "reactor", "workshop", "munitions" }
data.Devices[703] = k
OnWeaponFired(teamId, "buzzsaw", 703, 0, 0)
QueueDeviceRebuild(703)
print("with munitions: queued=" .. queued .. " rebuild=" .. tostring(data.Rebuild[k]))
