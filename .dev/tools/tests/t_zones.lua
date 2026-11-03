rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion step 3: zone hit map (FortZones) from enemy strut hits and own struts lost, zone-triggered modules.
-- Vanilla-8 plan, team 102, mirrored; nodes of zone Z0 mapped to made-up actual ids.
MAX_SIDES = 100
LINKBREAK_DELETE = 4
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 0, energy = 0 } end
function GetDeviceCountSide(side) return side == 2 and 1 or 0 end
function GetDeviceIdSide(side, i) return 100 end
function GetDeviceType(id) return "reactor" end
function NodePosition() return nil end
function NodeTeam(n) return n < 2000 and 102 or 1 end
function Load(g)
  for i = 1, 5 do table.insert(Fort, i, { Type = 3, MaterialSaveName = "bracing", ExistingFort = true }) end
  data.fortIndex = 6
  data.OriginalToActual = {}
  enemyTeamId = 1
end
function OnWeaponFired() end
function OnDeviceDestroyed() end
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

-- two nodes of Z0 and one of Z1, by original id, mapped to actual ids 901.. (sorted: deterministic)
local byZone = {}
for orig, z in pairs(CAI_Plan.nodeZone) do byZone[z] = byZone[z] or {}; table.insert(byZone[z], orig) end
for _, l in pairs(byZone) do table.sort(l) end
data.OriginalToActual[byZone.Z0[1]] = 901
data.OriginalToActual[byZone.Z0[2]] = 902
data.OriginalToActual[byZone.Z1[1]] = 903
print("zone of 901: " .. tostring(CAI_ZoneOfNode(901)) .. ", of 903: " .. tostring(CAI_ZoneOfNode(903)) .. ", of 950: " .. tostring(CAI_ZoneOfNode(950)))
-- 15 enemy mortar hits (20 each) on Z0, one own projectile and one hit on Z1
for i = 1, 15 do OnLinkHit(901, 902, 5000 + i, 1, "mortar", 20, nil, false) end
OnLinkHit(901, 902, 6000, 102, "mortar", 20, nil, false)
OnLinkHit(903, 902, 6001, 1, "cannon", 70, nil, false)
CAI_Think()
print(string.format("totals: Z0=%d Z1=%d", data.CAI.zoneTotal.Z0, data.CAI.zoneTotal.Z1))
-- five Z0 struts lost (100 each), one deleted by the AI itself (not counted)
for i = 1, 5 do OnLinkDestroyed(102, "bracing", 901, 902, 1) end
OnLinkDestroyed(102, "bracing", 901, 902, LINKBREAK_DELETE)
CAI_Think()
print(string.format("after breaks: Z0=%d", data.CAI.zoneTotal.Z0))
-- more damage before the cooldown: no repeat; after it: Z0face again
for i = 1, 5 do OnLinkDestroyed(102, "bracing", 901, 902, 1) end
CAI_Think()
for i = 1, 12 do CAI_Think() end
