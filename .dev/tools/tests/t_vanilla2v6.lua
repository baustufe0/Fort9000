rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Plan swap on maps that share the game's plans, told apart by the fort's position (FortPositions, 2v6 Vanilla).
-- ORDER: "before" = game plan loaded before the mod, "after" = afterwards; ENGINE: path of the game plan;
-- TEAM: 1 (OffsetFort) or 102 (MirrorFort); FX, FY: where the game puts the plan's FortPos
local ORDER, ENGINE, TEAM, FX, FY = arg[1], arg[2], tonumber(arg[3]), tonumber(arg[4]), tonumber(arg[5])
MAX_SIDES = 100
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 0, energy = 0 } end
function GetDeviceCountSide() return 3 end
function GetDeviceIdSide(s, i) return i end
function GetDeviceType(id) return id == 1 and "reactor" or "mine" end
function Load(g) end
function OnWeaponFired() end
function OnDeviceDestroyed() end
-- simplified game transformations (positions only)
function MirrorFort(pivot, offset)
  for _, a in ipairs(Fort) do for _, k in ipairs({"PosA","PosB","NewNodePos","GroundPosition"}) do
    local p = a[k]; if p then p.x = 2*pivot - p.x + offset.x; p.y = p.y + offset.y end end end
end
function OffsetFort(offset)
  for _, a in ipairs(Fort) do for _, k in ipairs({"PosA","PosB","NewNodePos","GroundPosition"}) do
    local p = a[k]; if p then p.x = p.x + offset.x; p.y = p.y + offset.y end end end
end
if ORDER == "before" then dofile(ENGINE) end
dofile("mods/fort9000dev/ai/ai.lua")
FortPlanConfig.Force = nil
if ORDER == "after" then dofile(ENGINE) end
teamId = TEAM
local E = FortPos
local mirrored = (TEAM % 100 == 2) ~= (FortTeam == 2)
if mirrored then
  MirrorFort(0, { x = FX + E.x, y = FY - E.y })
else
  OffsetFort({ x = FX - E.x, y = FY - E.y })
end
Load(true)
-- the first action relative to the fort's position, in the mid plan's frame (team 1, enemy to the right)
local a = Fort[1]; local p = a.PosA or a.GroundPosition
local rx = (TEAM % 100 == 2) and (FX - p.x) or (p.x - FX)
print(string.format("Result: actions=%d first action rel = %.1f, %.1f", #Fort, rx, p.y - FY))
