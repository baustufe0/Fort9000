rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- ORDER: "before" = game plan loaded before the mod, "after" = afterwards
local ORDER, ENGINE, TEAM, MODE = arg[1], arg[2], tonumber(arg[3]), arg[4]
MAX_SIDES = 100
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b) return 2 end   -- -> fort-t1f1-Vanilla-2.lua
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
local engineFile = "ai/forts/vanilla/mid/" .. ENGINE
if ORDER == "before" then dofile(engineFile) end
dofile("mods/fort-9000/ai/ai.lua")
if ORDER == "after" then dofile(engineFile) end
teamId = TEAM
-- Game: real fort of team 1 at x=-1995, team 2 mirrored at +1995
local E = FortPos
if TEAM % 100 == 2 then
  MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
elseif math.abs(E.x + 2900) > 1 then
  OffsetFort({ x = -2900 - E.x, y = 700 - E.y })
end
Load(true)
-- Expectation: first action of our plan at the right position
local a = Fort[1]; local p = a.PosA or a.GroundPosition
print(string.format("Result: actions=%d  PosA first action = %.1f, %.1f", #Fort, p.x, p.y))
