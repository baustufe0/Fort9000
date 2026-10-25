MAX_SIDES=100; teamId=102; enemyTeamId=1
CS_SUCCESS=0; CS_INSUFFICIENTRESOURCES=-3; DD_SUCCESS=0; DD_NOTFOUND=-1; DD_FIRING=-2
data={OffensiveFireProbability={cannon=0.8},AntiAirFireProbability={machinegun=0.7}, fortIndex=3}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return {metal=0,energy=0} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
dofile("mods/fort-9000/ai/ai.lua")
-- the starting machine gun stands on 58->55 (the plan names 55-58); nothing stands on 1-2
local calls = {}
function DestroyDevice(t, a, b)
  calls[#calls + 1] = a .. "-" .. b
  if a == 58 and b == 55 then return DD_SUCCESS end
  return DD_NOTFOUND
end
Load(true)
print("sold " .. tostring(DestroyDevice(102, 55, 58)) .. " tried " .. table.concat(calls, ","))
print("missing " .. tostring(DestroyDevice(102, 1, 2)))
