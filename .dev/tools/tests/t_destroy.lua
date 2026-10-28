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
dofile("mods/fort9000/ai/ai.lua")
-- a device on 58->55 is found that way round; device 9 only by its platform (76/73); the machine gun 11 only by
-- its position (platform 90/91, standing at 2885,206 on the strut 80-81); nothing stands on 1-2
local calls, byid = {}, {}
function DestroyDevice(t, a, b)
  calls[#calls + 1] = a .. "-" .. b
  if a == 58 and b == 55 then return DD_SUCCESS end
  return DD_NOTFOUND
end
local devs = { 7, 9, 11 }
local plat = { [7] = { 40, 41 }, [9] = { 76, 73 }, [11] = { 90, 91 } }
local where = { [7] = { x = 3000, y = 600 }, [9] = { x = 2900, y = 300 }, [11] = { x = 2885, y = 206 } }
local nodes = { [80] = { x = 2935, y = 206 }, [81] = { x = 2836, y = 205 }, [1] = { x = 0, y = 0 }, [2] = { x = 100, y = 0 },
  [73] = { x = 2935, y = 224 }, [76] = { x = 2836, y = 219 } }
function GetDeviceCountSide(t) return #devs end
function GetDeviceIdSide(t, i) return devs[i + 1] end
function GetDevicePlatformA(id) return plat[id][1] end
function GetDevicePlatformB(id) return plat[id][2] end
function GetDevicePosition(id) return where[id] end
function GetDeviceType(id) return ({ [7] = "store", [9] = "battery", [11] = "machinegun" })[id] end
function NodePosition(id) return nodes[id] end
function DestroyDeviceById(id) byid[#byid + 1] = id; return DD_SUCCESS end
Load(true)
print("sold " .. tostring(DestroyDevice(102, 55, 58)) .. " tried " .. table.concat(calls, ","))
calls = {}
print("sold by id " .. tostring(DestroyDevice(102, 73, 76)) .. " tried " .. table.concat(calls, ",") .. " id " .. table.concat(byid, ","))
byid = {}
print("sold by position " .. tostring(DestroyDevice(102, 80, 81)) .. " id " .. table.concat(byid, ","))
print("missing " .. tostring(DestroyDevice(102, 1, 2)))
