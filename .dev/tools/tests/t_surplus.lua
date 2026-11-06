rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Surplus modules: hand-written modules on the Vanilla-3 plan (team 102) that go in once the plan is built, no rebuild
-- is queued and metal and energy stay at their thresholds for Seconds; a second one only after the first (After).
MAX_SIDES = 100
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc)
  if string.find(tostring(desc), "CAI plan", 1, true) then
    for _, m in pairs(CAI_Plan.maps) do for i, f in ipairs(m.list) do if f == "fort-t1f1-Vanilla-3.lua" then return i end end end
  end
  return 2
end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local res = { metal = 0, energy = 0 }
function GetTeamResources() return res end
function GetDeviceCountSide(side) return side == 1 and 0 or 1 end
function GetDeviceIdSide(side, i) return 1 end
function GetDeviceType(id) return "reactor" end
function Load(g)
  for i = 1, 5 do table.insert(Fort, i, { Type = 3, MaterialSaveName = "bracing", ExistingFort = true }) end
  data.fortIndex = 6
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
FortPlanConfig.Force = nil
local plan = CAI_Plan.maps.Vanilla.plans["fort-t1f1-Vanilla-3.lua"]
plan.FortModules = {
  { Name = "firebeam", Trigger = { Surplus = { Metal = 500, Energy = 3500, Seconds = 20 } }, Requires = 0, Actions = {
    { Type = 5, OriginalNodeAId = 55, PosA = { x = -2945.11, y = 206.49 }, OriginalNodeBId = 58, PosB = { x = -2846.18, y = 203.99 }, LinkT = 0.5, DeviceSaveName = "firebeam" } } },
  { Name = "laser", Trigger = { After = "firebeam", Surplus = { Metal = 1000, Energy = 6000, Seconds = 20 } }, Requires = 0, Actions = {
    { Type = 5, OriginalNodeAId = 55, PosA = { x = -2945.11, y = 206.49 }, OriginalNodeBId = 58, PosB = { x = -2846.18, y = 203.99 }, LinkT = 0.3, DeviceSaveName = "laser" } } },
}
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)
local mods = data.CAIModules.list
local function Think(n) for i = 1, n do CAI_Think() end end
local function Fired() return tostring(mods[1].fired) .. "," .. tostring(mods[2].fired) end

-- full storage while the plan is still being built: nothing
res = { metal = 1200, energy = 9000 }
data.fortIndex = 50
Think(6)
print("building: " .. Fired())
-- plan built, but a rebuild is queued: nothing
data.fortIndex = #Fort + 1
data.Rebuild = { [40] = true }
Think(6)
print("rebuilding: " .. Fired())
-- no rebuild, energy below the threshold: nothing
data.Rebuild = {}
res = { metal = 1200, energy = 3000 }
Think(6)
print("short of energy: " .. Fired())
-- both at the thresholds: not before Seconds (20 s = four think steps of 5 s), then the firebeam
res = { metal = 1200, energy = 9000 }
Think(4)
print("after 15 s: " .. Fired())
Think(1)
print("after 20 s: " .. Fired())
-- the laser waits while the firebeam's actions are built
Think(6)
print("firebeam building: " .. Fired())
-- built again; a dip in metal restarts the laser's clock
data.fortIndex = #Fort + 1
Think(3)
res = { metal = 400, energy = 9000 }
Think(1)
res = { metal = 1200, energy = 9000 }
Think(4)
print("after the dip: " .. Fired())
Think(1)
print("laser: " .. Fired() .. " " .. Fort[#Fort].DeviceSaveName)
