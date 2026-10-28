-- Fire.Volley: firebeams fire together as one group (the built-in TryFireGun with useGroup, one target for all)
MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={firebeam=0.8,sniper=0.8},AntiAirFireProbability={},
  HardThreshold=0.75, FireDuringRebuildProbability={firebeam=0.3}, offencePoints=100000000, ActionQueue={}}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
-- resources as vectors like the game's: a table with + and - (a number on the left of + raised an error in the game)
local mt = {}
local function vec(e) return setmetatable({energy=e}, mt) end
mt.__add = function(a, b) return vec(a.energy + b.energy) end
mt.__sub = function(a, b) return vec(a.energy - b.energy) end
local energy = 3000
function GetTeamResources() return vec(energy) end
function GetWeaponFireCost(id) return vec(1500) end
function CanAfford(r) return r.energy >= 0 end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local weapons={31,32,33}
local kinds={[31]="firebeam",[32]="firebeam",[33]="sniper"}
local ready={[31]=true,[32]=false,[33]=true}
local built={[31]=true,[32]=true,[33]=true}
function GetWeaponCount() return #weapons end
function GetWeaponId(t,i) return weapons[i+1] end
function GetDeviceType(id) return kinds[id] end
function IsDummy() return false end
function IsDeviceFullyBuilt(id) return built[id] end
function IsAIDeviceAvailable() return true end
function IsWeaponReadyToFire(id) return ready[id] end
-- the built-in AI's TryFireGun: records single shots and groups (leader:members)
local fired={}
function TryFireGun(id, group)
  if group then fired[#fired+1]=id .. ":" .. table.concat(group, "+") else fired[#fired+1]=tostring(id) end
  ready[id]=false
  if group then for _, g in ipairs(group) do ready[g]=false end end
end
dofile("mods/fort9000dev/ai/ai.lua")
Load(true)
local function tick(label) fired={}; CAI_FireTick(); print(label, table.concat(fired,",")) end
tick("partner reloading:")                      -- 31 ready, 32 not: 31 held, the sniper fires
fired={}; TryFireGun(31)                        -- the built-in AI picks 31 on its own: held too
print("base firebeam held:", #fired == 0)
ready[32]=true; ready[33]=true
tick("both ready:")                             -- one volley, 31 leads, 32 with it; the sniper fires
ready[31]=true; ready[32]=true; energy=2000
tick("energy for one:")                         -- 3000 for both, 2000 there: held
energy=3000; ready[33]=false
local alone=0
for i=1,25 do ready[31]=true; ready[32]=false; fired={}; CAI_FireTick(); if fired[1]=="31" then alone=i end end
print("alone after hold:", alone)                -- fired alone once, MaxHold (20 s) after the wait began
built[32]=false; ready[31]=true; ready[33]=false
tick("partner under construction:")             -- only one built firebeam: it fires as usual
