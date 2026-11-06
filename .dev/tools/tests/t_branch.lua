rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion: chance draws the first tech branch. Drawn beams: the factory comes at its time, the munitions plant only from a
-- surplus after that. Vanilla-8 plan, team 102, mirrored.
MAX_SIDES = 100
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return desc == "CAI techBranch" and 2 or 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local res = { metal = 100, energy = 100 }
function GetTeamResources() return res end
local heavy = 0
local store = 0
function GetDeviceCountSide(side) return side == 2 and heavy + store or 0 end
function GetDeviceIdSide(side, i) return 1000 + i end
function GetDeviceType(id) return id - 1000 < store and "store" or "laser" end
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
dofile("ai/forts/vanilla/mid/fort-t1f1-Template-1.lua")
dofile("mods/fort9000dev/ai/ai.lua")
FortPlanConfig.Force = { Vanilla = "fort-t1f1-Vanilla-8.lua" }
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)
data.fortIndex = #Fort + 1
local function fired(name)
  for _, m in ipairs(data.CAIModules.list) do if m.name == name then return tostring(m.fired == true) end end
end
for i = 1, 62 do CAI_Think(); data.fortIndex = #Fort + 1 end
print("no store: factory=" .. fired("factory"))
store = 1
CAI_Think(); data.fortIndex = #Fort + 1
print("at 315 s: factory=" .. fired("factory") .. " munitions=" .. fired("munitions"))
res = { metal = 1000, energy = 7000 }
for i = 1, 8 do data.Rebuild = {}; CAI_Think(); data.fortIndex = #Fort + 1 end
print("surplus, no heavy weapon: factory=" .. fired("factory") .. " munitions=" .. fired("munitions") .. " upgrade=" .. fired("upgrade"))
heavy = 2
for i = 1, 8 do data.Rebuild = {}; CAI_Think(); data.fortIndex = #Fort + 1 end
print("with a surplus: factory=" .. fired("factory") .. " munitions=" .. fired("munitions"))
