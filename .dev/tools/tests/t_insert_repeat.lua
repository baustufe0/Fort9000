rawget = nil; rawset = nil; setmetatable = nil; getmetatable = nil
-- Bastion step 0.4: many module inserts in a row, some at the same build index, keep every index-keyed table
-- (data.Rebuild, data.Frustration, data.Devices, st.rebuildSince) pointing at the same plan actions.
-- Five time-triggered modules on the Vanilla-3 plan (team 102, mirrored), one per think step.
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
function GetTeamResources() return { metal = 0, energy = 0 } end
function GetDeviceCountSide(side) return 1 end
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
local function Dev(name, t)
  return { Type = 5, OriginalNodeAId = 55, PosA = { x = -2945.11, y = 206.49 }, OriginalNodeBId = 58,
    PosB = { x = -2846.18, y = 203.99 }, LinkT = t, DeviceSaveName = name }
end
plan.FortModules = {}
for i, name in ipairs({ "m1", "m2", "m3", "m4", "m5" }) do
  -- module i has i actions, so every insert shifts by a different amount
  local actions = {}
  for j = 1, i do actions[j] = Dev(name, 0.1 * j) end
  plan.FortModules[i] = { Name = name, Trigger = { Time = 5 * i }, Requires = 0, Actions = actions }
end
teamId = 102
local E = FortPos
MirrorFort(0, { x = 2900 + E.x, y = 700 - E.y })
Load(true)

local function IndexOf(k) for i, a in ipairs(Fort) do if a.CAI_K == k then return i end end end
local fi = IndexOf(60)
data.fortIndex = fi
-- index-keyed state before, at and after the build index; remember the actions they point at
data.Rebuild = { [3] = true, [fi] = true, [fi + 4] = true }
data.Frustration = { [fi + 1] = 2, [2] = 1 }
data.Devices = { [77] = fi + 2, [78] = 2, [79] = fi }
data.CAI.rebuildSince = { [fi + 4] = 0 }
local want = { rebuild = {}, frustration = {}, devices = {} }
for k in pairs(data.Rebuild) do want.rebuild[Fort[k]] = true end
for k in pairs(data.Frustration) do want.frustration[Fort[k]] = true end
for id, k in pairs(data.Devices) do want.devices[id] = Fort[k] end
local total0 = #Fort

-- m1, m2, m3 at the same build index (the AI is stuck), then it moves on by 2 and m4, m5 go in there
CAI_Think(); CAI_Think(); CAI_Think()
data.fortIndex = data.fortIndex + 2
CAI_Think(); CAI_Think()

local function Check(name, keys, objs)
  local n, bad = 0, 0
  for k in pairs(keys) do
    n = n + 1
    if not objs[Fort[k]] then bad = bad + 1 end
  end
  local m = 0
  for _ in pairs(objs) do m = m + 1 end
  print(string.format("%s: %d of %d, %d wrong", name, n, m, bad))
end
Check("rebuild", data.Rebuild, want.rebuild)
Check("frustration", data.Frustration, want.frustration)
-- the think step adds a clock for every queued rebuild, so each must point at a queued action
Check("since", data.CAI.rebuildSince, want.rebuild)
local dn, dbad = 0, 0
for id, obj in pairs(want.devices) do
  dn = dn + 1
  if Fort[data.Devices[id]] ~= obj then dbad = dbad + 1 end
end
print(string.format("devices: %d, %d wrong", dn, dbad))
print(string.format("total: %d (+%d)", #Fort, #Fort - total0))
-- the build order in front of plan action 60: m3 m2 m1 (stacked at fi), then m5 m4 two actions later
local order = {}
for i = fi, fi + 16 do order[#order + 1] = Fort[i].DeviceSaveName or ("k" .. tostring(Fort[i].CAI_K)) end
print("order: " .. table.concat(order, " "))
print("plan 60 at: +" .. (IndexOf(60) - fi))
