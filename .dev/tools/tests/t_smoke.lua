-- Smoke before rockets (Fire.SmokeCover): rockets wait for an own smoke shell, a ready smoke launcher fires first
MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={rocket=0.8,rocketemp=0.8,smokebomb=0.8,sniper=0.8},AntiAirFireProbability={},
  HardThreshold=0.75, FireDuringRebuildProbability={rocket=0.3}, offencePoints=100000000, ActionQueue={}}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
local sched={}
function ScheduleCall(t,f) sched[#sched+1]=f end
function ScheduledCallCountOfFunc(f) local n=0 for _,g in ipairs(sched) do if g==f then n=n+1 end end return n end
function GetTeamResources() return {metal=600,energy=3000} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local weapons={21,22,23,24}
local kinds={[21]="rocket",[22]="smokebomb",[23]="rocketemp",[24]="sniper"}
local ready={[21]=true,[22]=true,[23]=true,[24]=true}
function GetWeaponCount() return #weapons end
function GetWeaponId(t,i) return weapons[i+1] end
function GetDeviceType(id) return kinds[id] end
function IsDummy() return false end
function IsAIDeviceAvailable() return true end
function IsWeaponReadyToFire(id) return ready[id] end
local fired={}
-- the built-in AI's TryFireGun: a smoke launcher that fires reports its shell (OnWeaponFired) and reloads
function TryFireGun(id)
  fired[#fired+1]=id
  if kinds[id] == "smokebomb" then ready[id]=false; OnWeaponFired(teamId, "smokebomb", id, 900, nil) end
end
dofile("mods/fort9000dev/ai/ai.lua")
Load(true)
local function tick(label) fired={}; CAI_FireTick(); print(label, table.concat(fired,",")) end
tick("t1:")      -- rockets ready, no smoke yet: the smoke launcher fires, rockets held, the sniper fires
TryFireGun(21)   -- the built-in AI tries a rocket on its own right after the smoke: held (MinDelay)
print("base rocket held:", #fired == 0 or fired[#fired] ~= 21)
tick("t2:")      -- 1 s after the smoke: still held
tick("t3:")      -- 2 s after the smoke: both rockets fire first
for i=4,13 do tick("t"..i..":") end
-- no smoke for MaxHold seconds (launcher never reloads): the rockets fire anyway
local released=false
for i=14,60 do fired={}; CAI_FireTick(); for _,id in ipairs(fired) do if id==21 then released=true end end end
print("released after hold:", released)
-- without a smoke launcher the rockets fire at once
weapons={21,23,24}; fired={}; CAI_FireTick()
print("no smoke launcher:", table.concat(fired,","))
