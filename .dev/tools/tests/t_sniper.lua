rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion after test 5: sniper sight. A sniper's target is only a device a ray reaches: not behind a closed door; an AP
-- sniper through one door (hitpoints 600), not two. The ray is mocked: what stands in front of the target.
MAX_SIDES = 100
RAY_EXCLUDE_CONSTRUCTION, RAY_ALLIED_BG_BLOCKS, RAY_EXCLUDE_DYNAMIC_TERRAIN = 1, 2, 4
RAY_HIT_WEAPON, RAY_HIT_DEVICE, RAY_HIT_STRUCTURE, RAY_HIT_NOTHING = 11, 12, 13, 14
data = { OffensiveFireProbability = { cannon = 0.8, sniper = 0.6, sniper2 = 0.4 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper2", "sniper", "mortar", "reactor" }
WeaponFireBlockedByStructure = {}; WeaponFindTargetFunction = {}
data.ProjectileHitpoints = { sniper = 0, sniper2 = 810 }; data.CustomWeaponPriorities = {}
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 0, energy = 0 } end
function GetDeviceCountSide(side) return 0 end
function GetDeviceIdSide(side, i) return 0 end
local types = { [1] = "sniper", [2] = "sniper2", [50] = "mortar" }
function GetDeviceType(id) return types[id] end
function IsDeviceFullyBuilt(id) return true end
function IsCloaked(id) return false end
function GetDeviceCentrePosition(id) return { x = 3000, y = 200 } end
function Vec3() return { x = 0, y = 0 } end
function Load(g)
  for i = 1, 5 do table.insert(Fort, i, { Type = 3, MaterialSaveName = "bracing", ExistingFort = true }) end
  data.fortIndex = 6
  data.Rebuild = {}
  data.Devices = {}
  enemyTeamId = 1
end
function OnWeaponFired() end
function OnDeviceDestroyed() end
function MirrorFort(pivot, offset)
  for _, a in ipairs(Fort) do for _, k in ipairs({"PosA","PosB","NewNodePos","GroundPosition"}) do
    local p = a[k]; if p then p.x = 2*pivot - p.x + offset.x; p.y = p.y + offset.y end end end
end
local blockers = {}        -- hitpoints of the struts in the line, in order
local lowDoor = false      -- the door is open only over y 185 (15 above the centre): the centre itself is behind armour
local side = 0
function CastRayFromDevice(id, pos, hitpoints, flags, fieldFlags)
  local left = hitpoints
  if lowDoor and pos.y > 190 then side = enemyTeamId; return RAY_HIT_STRUCTURE end
  for _, hp in ipairs(blockers) do
    if left < hp then side = enemyTeamId; return RAY_HIT_STRUCTURE end
    left = left - hp
  end
  side = enemyTeamId
  return RAY_HIT_WEAPON
end
function GetRayHitSideId() return side end
dofile("ai/forts/vanilla/mid/fort-t1f1-Template-1.lua")
dofile("mods/fort9000dev/ai/ai.lua")
FortPlanConfig.Force = { Vanilla = "fort-t1f1-Vanilla-8.lua" }
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)
print("blocked by structure: " .. tostring(WeaponFireBlockedByStructure.sniper) .. " " .. tostring(WeaponFireBlockedByStructure.sniper2)
  .. " ap hitpoints=" .. data.ProjectileHitpoints.sniper2 .. " chance=" .. data.OffensiveFireProbability.sniper)
local devices = { mortar = { 50 } }
local function try(id)
  local t = CAI_SniperTarget(id, { x = -3000, y = 200 }, devices)
  return t and ("y" .. t.y) or "hold"
end
blockers = {}
print("open: sniper " .. try(1) .. " ap " .. try(2))
blockers = { 400 }
print("one door: sniper " .. try(1) .. " ap " .. try(2))
blockers = { 400, 400 }
print("two doors: sniper " .. try(1) .. " ap " .. try(2))
blockers = {}; lowDoor = true
print("door over the centre: sniper " .. try(1))
lowDoor = false
local ss = data.CAI.sniperSight
print("counts: seen=" .. ss.seen .. " pierced=" .. ss.pierced .. " hold=" .. ss.hold)
