MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={cannon20mm=0.8,sniper=0.8},AntiAirFireProbability={machinegun=0.7}, HardThreshold=0.75,
  FireDuringRebuildProbability={cannon20mm=0.5, sniper=0.6, machinegun=0.05}, offencePoints=100000000, ActionQueue={}}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
FIREFAIL_RELOADING=3; FIREFAIL_NOENERGY=5; FIREFAIL={[3]="FIREFAIL_RELOADING",[5]="FIREFAIL_NOENERGY"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return {metal=120,energy=1500} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
-- 21: 20mm that fires when tried; 22: 20mm short of energy; 23: sniper with a pending door action;
-- 24: sniper not available; 25: sniper the built-in AI declines (stays ready)
local weapons={21,22,23,24,25}
local kind={[21]="cannon20mm",[22]="cannon20mm",[23]="sniper",[24]="sniper",[25]="sniper"}
local ready={[21]=true,[22]=false,[23]=true,[24]=true,[25]=true}
local code=0
function GetWeaponCount() return #weapons end
function GetWeaponId(t,i) return weapons[i+1] end
function GetDeviceType(id) return kind[id] or "reactor" end
function IsDummy() return false end
function IsAIDeviceAvailable(id) return id ~= 24 end
function IsWeaponReadyToFire(id)
	if not ready[id] then code = (id == 22) and FIREFAIL_NOENERGY or FIREFAIL_RELOADING end
	return ready[id]
end
function GetWeaponFireFailureCode() return code end
function TryFireGun(id) if id == 21 then ready[21] = false end end
-- targeting ray: blocked by our own background bracing in front of the barrel
RAY_EXCLUDE_CONSTRUCTION=1; RAY_ALLIED_BG_BLOCKS=2; RAY_EXCLUDE_DYNAMIC_TERRAIN=4; RAY_HIT={[3]="RAY_HIT_STRUCTURE"}
local rayFlags
function GetDeviceCountSide(side) return side == enemyTeamId and 1 or 0 end
function GetDeviceIdSide(side, i) return 99 end
function GetDevicePosition(id) return {x=-3000, y=300} end
function CastRayFromDevice(id, pos, hp, flags) rayFlags = flags return 3 end
function GetRayHitSideId() return 102 end
function GetRayHitMaterialSaveName() return "backbracing" end
function GetRayHitPosition() return {x=3128.4, y=70.6} end
dofile("mods/fort9000/ai/ai.lua")
Load(true)
data.ActionQueue[23] = { ProcessFunction = "x" }
CAI_FIREWAIT_EVERY = 10
Strategy.Fire.WeaponsPerTick = 5
for i=1,12 do CAI_FireTick() end         -- rate limit: one line per weapon and reason, again after 10 s
ready[22] = true                          -- reason changes: logged at once
CAI_FireTick()
print("ray flags " .. tostring(rayFlags))
