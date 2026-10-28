MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={cannon20mm=0.8,sniper=0.8},AntiAirFireProbability={machinegun=0.7}, HardThreshold=0.75,
  FireDuringRebuildProbability={cannon20mm=0.5, sniper=0.6, machinegun=0.05}, offencePoints=100000000, ActionQueue={},
  Devices={[31]=7, [32]=8, [33]=9}}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
local energy = 500
function GetTeamResources() return {metal=120,energy=energy} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
-- 31: sniper the built-in AI always declines (no target); 32: a 20mm that declines (not in FortRetire);
-- 33: sniper that fires on every try; 34: sniper that declines the mod's tries but the built-in AI fires every 5 s
local weapons={31,32,33,34}
local kind={[31]="sniper",[32]="cannon20mm",[33]="sniper",[34]="sniper"}
local ready={[31]=true,[32]=true,[33]=true,[34]=true}
function GetWeaponCount() return #weapons end
function GetWeaponId(t,i) return weapons[i+1] end
function GetDeviceType(id) return kind[id] or "reactor" end
function IsDummy() return false end
function IsAIDeviceAvailable(id) return true end
function IsWeaponReadyToFire(id) return ready[id] end
function GetWeaponFireFailureCode() return 0 end
local builtin = false
function TryFireGun(id) if id == 33 or (id == 34 and builtin) then ready[id] = false end end
local tick, sold = 0, {}
function DestroyDeviceById(id)
	sold[#sold + 1] = id .. "@" .. tick
	for i, w in ipairs(weapons) do if w == id then table.remove(weapons, i) break end end
	return 0
end
dofile("mods/fort-9000/ai/ai.lua")
Load(true)
CAI_Plan.retire = { sniper = 20 }
Strategy.Fire.WeaponsPerTick = 5
-- 30 s short of energy (idle does not count), then 40 s with energy: the idle sniper is sold after 20 s of it
for i = 1, 70 do
	tick = i
	if i == 31 then energy = 1500 end
	ready[33] = true
	if i % 5 == 2 then ready[34] = true end
	if i % 5 == 0 then builtin = true; TryFireGun(34); builtin = false end
	CAI_FireTick()
end
print("sold: " .. table.concat(sold, ",") .. " devices31=" .. tostring(data.Devices[31]) .. " devices33=" .. tostring(data.Devices[33]))
