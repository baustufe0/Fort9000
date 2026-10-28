-- Fire.SmokeCover: the smoke launcher fires only if the ready rockets can fire right after it (energy for all of them)
MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={rocket=0.8,smokebomb=0.8},AntiAirFireProbability={},
  HardThreshold=0.75, FireDuringRebuildProbability={rocket=0.3}, offencePoints=100000000, ActionQueue={}}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local energy = 400
function GetTeamResources() return energy end      -- resources as plain energy numbers (the game uses a vector)
function GetWeaponFireCost(id) return id == 22 and 200 or 300 end
function CanAfford(r) return r >= 0 end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local weapons={21,22}
local kinds={[21]="rocket",[22]="smokebomb"}
local ready={[21]=true,[22]=true}
function GetWeaponCount() return #weapons end
function GetWeaponId(t,i) return weapons[i+1] end
function GetDeviceType(id) return kinds[id] end
function IsDummy() return false end
function IsAIDeviceAvailable() return true end
function IsWeaponReadyToFire(id) return ready[id] end
local fired={}
function TryFireGun(id)
  fired[#fired+1]=id
  if kinds[id] == "smokebomb" then ready[id]=false; OnWeaponFired(teamId, "smokebomb", id, 900, nil) end
end
dofile("mods/fort-9000/ai/ai.lua")
Load(true)
local function tick(label) fired={}; CAI_FireTick(); print(label, table.concat(fired,",")) end
tick("400 energy:")        -- smoke 200 + rocket 300 > 400: no smoke, the rocket waits
energy = 600
tick("600 energy:")        -- enough for both: the smoke fires, the rocket waits for it
ready[21] = false; ready[22] = true; data.CAI.lastSmoke = nil
fired={}; print("rocket reloading:", tostring(CAI_FireSmokeFirst()))   -- no ready rocket: no smoke
