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
-- a device on 58->55 is found that way round; the starting machine gun (id 9, platform 76/73) only by its id;
-- nothing stands on 1-2
local calls, byid = {}, {}
function DestroyDevice(t, a, b)
  calls[#calls + 1] = a .. "-" .. b
  if a == 58 and b == 55 then return DD_SUCCESS end
  return DD_NOTFOUND
end
function GetDeviceCountSide(t) return 2 end
function GetDeviceIdSide(t, i) return ({ 7, 9 })[i + 1] end
function GetDevicePlatformA(id) return ({ [7] = 40, [9] = 76 })[id] end
function GetDevicePlatformB(id) return ({ [7] = 41, [9] = 73 })[id] end
function DestroyDeviceById(id) byid[#byid + 1] = id; return DD_SUCCESS end
Load(true)
print("sold " .. tostring(DestroyDevice(102, 55, 58)) .. " tried " .. table.concat(calls, ","))
calls = {}
print("sold by id " .. tostring(DestroyDevice(102, 73, 76)) .. " tried " .. table.concat(calls, ",") .. " id " .. table.concat(byid, ","))
print("missing " .. tostring(DestroyDevice(102, 1, 2)))
