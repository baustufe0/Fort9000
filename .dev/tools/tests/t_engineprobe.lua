rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Engine probe (FortPlanConfig.EngineProbe, Bastion step 0): material over an existing strut, reclaim refund by frame,
-- strut hits by projectile type. Vanilla-2 plan, team 102, mirrored; the game is mocked.
MAX_SIDES = 100
CREATE_LINK = 3; DD_SUCCESS = 0; CS_SUCCESS = 0; CS = { [0] = "CS_SUCCESS", [7] = "CS_OBSTRUCTION" }
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc)
  if string.find(tostring(desc), "CAI plan", 1, true) then
    for _, m in pairs(CAI_Plan.maps) do for i, f in ipairs(m.list) do if f == "fort-t1f1-Vanilla-2.lua" then return i end end end
  end
  return 2
end
local scheduled = {}
function ScheduleCall(t, f) if f == CAI_EP_Frame then scheduled[#scheduled + 1] = f end end   -- only the probe frames
function ScheduledCallCountOfFunc() return 0 end
local metal = 500
function GetTeamResources() return { metal = metal, energy = 1000 } end
function GetTeamResourceRate() return { metal = 2.5, energy = 30 } end
function GetDeviceCost(n) return { metal = 50, energy = 300 } end
-- own side 2: reactor (1) and a machine gun (2) of team 102
function GetDeviceCountSide(side) return side == 2 and 2 or 0 end
function GetDeviceIdSide(side, i) return i + 1 end
function GetDeviceType(id) return id == 1 and "reactor" or "machinegun" end
function GetDeviceTeamIdActual(id) return 102 end
local reclaimed
function DestroyDeviceById(id) reclaimed = id return DD_SUCCESS end
local links = { ["11-12"] = "bracing" }
function IsNodeLinkedTo(a, b) return links[a .. "-" .. b] ~= nil end
function GetLinkMaterialSaveName(a, b) return links[a .. "-" .. b] end
function CreateLink(team, mat, a, b) links[a .. "-" .. b] = mat return 0 end
function NodeTeam(n) return n < 100 and 102 or 1 end
function Load(g)
  table.insert(Fort, 1, { Type = 3, MaterialSaveName = "bracing", ExistingFort = true, OriginalNodeAId = 1, OriginalNodeBId = 2 })
  data.OriginalToActual = { [1] = 11, [2] = 12 }
  data.fortIndex = 2
  enemyTeamId = 1
end
function OnWeaponFired() end
function OnDeviceDestroyed() end
function OnLinkDestroyed() end
function MirrorFort(pivot, offset)
  for _, a in ipairs(Fort) do for _, k in ipairs({"PosA","PosB","NewNodePos","GroundPosition"}) do
    local p = a[k]; if p then p.x = 2*pivot - p.x + offset.x; p.y = p.y + offset.y end end end
end
dofile("ai/forts/vanilla/mid/fort-t1f1-Template-1.lua")
dofile("mods/fort9000dev/ai/ai.lua")
FortPlanConfig.Force = nil
FortPlanConfig.EngineProbe = { Material = 10, Reclaim = 15, Devices = { "sniper", "machinegun" }, Window = 0.2, Frame = 0.04, Report = 20 }
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)

CAI_Think()                                   -- 5 s: on
OnLinkHit(11, 12, 900, 1, "cannon", 120, nil, false)
OnLinkHit(11, 12, 901, 1, "cannon", 80, nil, false)
OnLinkHit(150, 151, 902, 102, "sniper", 30, nil, false)   -- an enemy strut: not counted
OnLinkHit(11, 12, 903, 1, "mortar", 40, nil, false)
OnLinkDestroyed(102, "bracing", 11, 13, 1)
OnLinkDestroyed(1, "bracing", 150, 151, 1)                -- an enemy strut: not counted
CAI_Think()                                   -- 10 s: material
CAI_Think()                                   -- 15 s: material later, reclaim
-- the frames: income 0, 0, refund 25 at the third frame (deleted there), 0, 0
local deltas = { 0, 0, 25, 0, 0 }
for i = 1, 5 do
  metal = metal + deltas[i]
  if i == 3 then OnDeviceDeleted(102, 2, "machinegun", 0, 0, 0) end
  local f = table.remove(scheduled, 1)
  if f then f() end
end
print("reclaimed=" .. tostring(reclaimed) .. " left=" .. #scheduled)
CAI_Think()                                   -- 20 s: hit report
