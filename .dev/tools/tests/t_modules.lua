rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Reactive build modules: a hand-written module on the Vanilla-2 plan (team 102, mirrored by the game).
-- Loaded with the plan, moved by the transform, cut out after Load, inserted once the enemy builds its trigger.
MAX_SIDES = 100
data = { OffensiveFireProbability = { cannon = 0.8 }, AntiAirFireProbability = { machinegun = 0.7 } }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
-- the plan pick returns the index of fort-t1f1-Vanilla-2.lua in its plan list (the list order may change), all else 2
function GetRandomInteger(a, b, desc)
  if string.find(tostring(desc), "CAI plan", 1, true) then
    for _, m in pairs(CAI_Plan.maps) do for i, f in ipairs(m.list) do if f == "fort-t1f1-Vanilla-2.lua" then return i end end end
  end
  return 2
end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 0, energy = 0 } end
local enemy = {}                                -- enemy devices (side 1)
function GetDeviceCountSide(side) return side == 1 and #enemy or 1 end
function GetDeviceIdSide(side, i) return side == 1 and 100 + i or 1 end
function GetDeviceType(id) if id == 1 then return "reactor" end return enemy[id - 99] end
-- base Load: the starting fort is inserted in front of the plan (EnumerateLinks)
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
local plan = CAI_Plan.maps.Vanilla.plans["fort-t1f1-Vanilla-2.lua"]
local nPlan = #plan.Fort
plan.FortModules = {
  { Name = "counterbattery", Trigger = { Types = { "mortar", "mortar2" }, Count = 2 }, Requires = 50, Actions = {
    { Type = 1, OriginalNodeAId = 48, PosA = { x = -3096.14, y = 502.53 }, OriginalNodeBId = 20000, NewNodePos = { x = -3000, y = 400 }, MaterialSaveName = "bracing" },
    { Type = 3, OriginalNodeAId = 47, PosA = { x = -2996.23, y = 503.57 }, OriginalNodeBId = 20000, PosB = { x = -3000, y = 400 }, MaterialSaveName = "armour" },
    { Type = 5, OriginalNodeAId = 47, PosA = { x = -2996.23, y = 503.57 }, OriginalNodeBId = 20000, PosB = { x = -3000, y = 400 }, LinkT = 0.5, DeviceSaveName = "mortar" } } },
  { Name = "antiair", Trigger = { Types = { "missile", "missile2" } }, Requires = 0, Actions = {
    { Type = 5, OriginalNodeAId = 55, PosA = { x = -2945.11, y = 206.49 }, OriginalNodeBId = 58, PosB = { x = -2846.18, y = 203.99 }, LinkT = 0.5, DeviceSaveName = "machinegun" } } },
  -- the plan's goal: comes by time even if the enemy builds nothing, but only after the anti-air module
  { Name = "goal", Trigger = { Time = 100, After = "antiair" }, Requires = 0, Actions = {
    { Type = 5, OriginalNodeAId = 55, PosA = { x = -2945.11, y = 206.49 }, OriginalNodeBId = 58, PosB = { x = -2846.18, y = 203.99 }, LinkT = 0.3, DeviceSaveName = "sniper" } } },
}
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)

local tagged = 0
for _, a in ipairs(Fort) do if a.CAI_Module then tagged = tagged + 1 end end
print(string.format("after load: actions=%d expected=%d tagged=%d", #Fort, nPlan + 5, tagged))
local cb = data.CAIModules.list[1].actions
print(string.format("module mirrored: %.1f, %.1f", cb[1].NewNodePos.x, cb[1].NewNodePos.y))

local function IndexOf(k) for i, a in ipairs(Fort) do if a.CAI_K == k then return i end end end
-- the AI is at plan action 10; the enemy builds one mortar, then a second one
data.fortIndex = IndexOf(10)
enemy = { "mortar" }
CAI_Think()
enemy = { "mortar", "mortar2", "sandbags" }
CAI_Think(); CAI_Think()   -- waits for plan action 50, logged once
-- the AI reaches plan action 60 with a rebuild, a frustrated action and devices queued by index
local fi = IndexOf(60)
data.fortIndex = fi
data.Rebuild = { [3] = true, [fi + 2] = true }
data.Frustration = { [fi] = 2 }
data.Devices = { [77] = fi + 1, [78] = 2 }
data.CAI.rebuildSince[fi + 2] = 40
CAI_Think()
print(string.format("inserted: %s %s %s next=%s",
  Fort[fi].DeviceSaveName or Fort[fi].MaterialSaveName, Fort[fi + 1].MaterialSaveName, Fort[fi + 2].DeviceSaveName, tostring(Fort[fi + 3].CAI_K)))
print(string.format("shifted: rebuild=%s,%s frustration=%s devices=%d,%d since=%s",
  tostring(data.Rebuild[3]), tostring(data.Rebuild[fi + 5]), tostring(data.Frustration[fi + 3]),
  data.Devices[77] - fi, data.Devices[78], tostring(data.CAI.rebuildSince[fi + 5])))
CAI_Think()
-- past the goal's time: it still waits for the anti-air module
for i = 1, 16 do CAI_Think() end
print("goal before anti-air: " .. tostring(data.CAIModules.list[3].fired))
-- a missile: the anti-air module goes in front of what is left, the goal right after it, each module once only
enemy = { "mortar", "mortar2", "missile" }
data.fortIndex = fi + 3
CAI_Think(); CAI_Think()
print(string.format("anti-air at %d: %s, then %s, total=%d", data.fortIndex - fi, Fort[fi + 3].DeviceSaveName, Fort[fi + 4].DeviceSaveName, #Fort))
