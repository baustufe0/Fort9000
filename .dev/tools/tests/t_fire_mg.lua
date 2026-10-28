MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={sniper=0.8,machinegun=0.6,minigun=0.7},AntiAirFireProbability={machinegun=0.7}, HardThreshold=0.75,
  FireDuringRebuildProbability={sniper=0.3, machinegun=0.05}, offencePoints=100000000, ActionQueue={}}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
local sched={}
function ScheduleCall(t,f) sched[#sched+1]=f end
function ScheduledCallCountOfFunc(f) local n=0 for _,g in ipairs(sched) do if g==f then n=n+1 end end return n end
function GetTeamResources() return {metal=600,energy=3000} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local weapons={11,12,13,14,15}
local kinds={[11]="sniper",[12]="machinegun",[13]="sniper",[14]="mortar",[15]="minigun"}   -- 15: upgraded machine gun
function GetWeaponCount() return #weapons end
function GetWeaponId(t,i) return weapons[i+1] end
function GetDeviceType(id) return kinds[id] end
function IsDummy() return false end
function IsAIDeviceAvailable() return true end
function IsWeaponReadyToFire() return true end
local fired={}
function TryFireGun(id) fired[#fired+1]=id end
dofile("mods/fort9000/ai/ai.lua")
Load(true)
for i=1,2 do CAI_FireTick() end
print("fired:", table.concat(fired,","))                     -- machine gun 12 skipped, its turn used by others
print("MG offensive", data.OffensiveFireProbability.machinegun, "MG during rebuild", data.FireDuringRebuildProbability.machinegun,
  "MG anti-air", data.AntiAirFireProbability.machinegun, "sniper offensive", data.OffensiveFireProbability.sniper)
CAI_Think()
print("after think: MG offensive", data.OffensiveFireProbability.machinegun)
print("minigun offensive", data.OffensiveFireProbability.minigun > 0)   -- the upgraded machine gun still fires
