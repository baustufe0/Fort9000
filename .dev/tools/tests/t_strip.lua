rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion after test 6: front strip. While metal is short early, the two outer armour struts in front of the reactor become
-- wood; with two heavy weapons standing and plenty of metal they become armour again, once per strut. CreateLink is mocked.
MAX_SIDES = 100
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function GetRandomInteger(a, b, desc) return 1 end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local res = { metal = 50, energy = 1000 }
function GetTeamResources() return res end
local heavy = 0
function GetDeviceCountSide(side) return side == 2 and heavy or 0 end
function GetDeviceIdSide(side, i) return 1000 + i end
function GetDeviceType(id) return "cannon" end
-- starting fort nodes in the world; team 102 is mirrored
local nodes = { 501, 502, 503, 504 }
local where = { [501] = { x = 2894, y = 405 }, [502] = { x = 2943, y = 306 }, [503] = { x = 2845, y = 304 }, [504] = { x = 2844, y = 204 } }
function NodeCount(team) return #nodes end
function GetNodeId(team, i) return nodes[i + 1] end
function NodePosition(id) return where[id] end
local mats = {}
local function key(a, b) if a > b then a, b = b, a end return a .. "-" .. b end
function IsNodeLinkedTo(a, b) return mats[key(a, b)] ~= nil end
function GetLinkMaterialSaveName(a, b) return mats[key(a, b)] end
function CreateLink(team, mat, a, b) mats[key(a, b)] = mat; res.metal = res.metal + (mat == "bracing" and 80 or -180); return -15 end
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
-- the inner strut of the storey (501-502) is not in the list: it stays armour, a buzzsaw must not cut through
mats[key(503, 501)] = "armour"; mats[key(504, 503)] = "armour"; mats[key(501, 502)] = "armour"
local function state() return mats[key(503, 501)] .. " " .. mats[key(504, 503)] .. " " .. mats[key(501, 502)] end
data.fortIndex = #Fort + 1
print("list: " .. #CAI_Plan.strip)
res.metal = 500
CAI_FrontStrip(10)
print("metal there: " .. state())
res.metal = 50
CAI_FrontStrip(15)
print("one step: " .. state() .. " m=" .. res.metal)
res.metal = 20
CAI_FrontStrip(20)
print("short: " .. state())
res.metal = 500
CAI_FrontStrip(35)
print("not yet back: " .. state())
mats[key(504, 503)] = "door"                -- a module made it a door meanwhile: it stays one
res.metal = 900
heavy = 1
CAI_FrontStrip(800)
print("one heavy weapon: " .. state())
heavy = 2
CAI_FrontStrip(805); res.metal = 900; CAI_FrontStrip(810); res.metal = 900; CAI_FrontStrip(815)
print("plenty: " .. state())
res.metal = 50
CAI_FrontStrip(495); CAI_FrontStrip(500)
print("once per strut: " .. state())
