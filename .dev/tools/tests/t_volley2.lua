-- SocketVolley (Bastion): beams fire together, guns fire together, and one class waits Gap seconds after the other (a beam
-- burns the shells in its way, the player's test 8)
MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={firebeam=0.8,laser=0.8,cannon20mm=0.8},AntiAirFireProbability={},
  HardThreshold=0.75, FireDuringRebuildProbability={}, offencePoints=100000000, ActionQueue={}}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local mt = {}
local function vec(e) return setmetatable({energy=e}, mt) end
mt.__add = function(a, b) return vec(a.energy + b.energy) end
mt.__sub = function(a, b) return vec(a.energy - b.energy) end
function GetTeamResources() return vec(20000) end
function GetWeaponFireCost(id) return vec(1500) end
function CanAfford(r) return r.energy >= 0 end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local weapons={41,42,43,44}
local kinds={[41]="laser",[42]="firebeam",[43]="cannon20mm",[44]="cannon20mm"}
local ready={[41]=true,[42]=true,[43]=true,[44]=true}
function GetWeaponCount() return #weapons end
function GetWeaponId(t,i) return weapons[i+1] end
function GetDeviceType(id) return kinds[id] end
function IsDummy() return false end
function IsDeviceFullyBuilt(id) return true end
function IsAIDeviceAvailable() return true end
function IsWeaponReadyToFire(id) return ready[id] end
local fired={}
function TryFireGun(id, group)
  if group then fired[#fired+1]=id .. ":" .. table.concat(group, "+") else fired[#fired+1]=tostring(id) end
  ready[id]=false
  if group then for _, g in ipairs(group) do ready[g]=false end end
end
dofile("mods/fort9000dev/ai/ai.lua")
Load(true)
data.CAI.volley = { Enabled = true, Types = { firebeam = true, laser = true, cannon20mm = true, cannon = true }, MaxHold = 90,
  Classes = { firebeam = "beam", laser = "beam", cannon20mm = "gun", cannon = "gun" }, Gap = 6, SaveEnergy = true }
data.CAI.fireClock = 100
TryFireGun(41)
print("beams:", table.concat(fired,","))
OnWeaponFired(102, "laser", 41, 1, 0)
fired={}
TryFireGun(43)
print("guns right after:", #fired)
data.CAI.fireClock = 107
TryFireGun(43)
print("guns after the gap:", table.concat(fired,","))
