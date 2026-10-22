rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- ORDER: "before" = Spielplan vor Mod geladen, "after" = danach
local ORDER, ENGINE, TEAM, MODE = arg[1], arg[2], tonumber(arg[3]), arg[4]
MAX_SIDES = 100
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b) return 2 end   -- -> fort-t1f1-Abyss-2.lua
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 0, energy = 0 } end
function GetDeviceCountSide() return 3 end
function GetDeviceIdSide(s, i) return i end
function GetDeviceType(id) return id == 1 and "reactor" or "mine" end
function Load(g) end
function OnWeaponFired() end
function OnDeviceDestroyed() end
-- vereinfachte Spiel-Transformationen (nur Positionen)
function MirrorFort(pivot, offset)
  for _, a in ipairs(Fort) do for _, k in ipairs({"PosA","PosB","NewNodePos","GroundPosition"}) do
    local p = a[k]; if p then p.x = 2*pivot - p.x + offset.x; p.y = p.y + offset.y end end end
end
function OffsetFort(offset)
  for _, a in ipairs(Fort) do for _, k in ipairs({"PosA","PosB","NewNodePos","GroundPosition"}) do
    local p = a[k]; if p then p.x = p.x + offset.x; p.y = p.y + offset.y end end end
end
local engineFile = "maps/Abyss/" .. ENGINE
if ORDER == "before" then dofile(engineFile) end
dofile("mods/fort-9000/ai/ai.lua")
if ORDER == "after" then dofile(engineFile) end
teamId = TEAM
-- Spiel: echte Festung von Team 1 bei x=-1995, Team 2 gespiegelt bei +1995
local E = FortPos
if TEAM % 100 == 2 then
  MirrorFort(0, { x = 1995.335815 + E.x, y = 106.206329 - E.y })
elseif math.abs(E.x + 1995.335815) > 1 then
  OffsetFort({ x = -1995.335815 - E.x, y = 106.206329 - E.y })
end
Load(true)
-- Erwartung: erste Aktion unseres Plans an der richtigen Stelle
local a = Fort[1]; local p = a.PosA
print(string.format("Ergebnis: Aktionen=%d  PosA erste Aktion = %.1f, %.1f", #Fort, p.x, p.y))
