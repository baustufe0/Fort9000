METAL=0; MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={cannon=0.8},AntiAirFireProbability={machinegun=0.7}, fortIndex=60, Rebuild={[59]=true}}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return {metal=METAL,energy=3000} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
Fort = {} for i=1,132 do Fort[i]={Type=5, DeviceSaveName="mine"} end FortPos={x=0,y=0}
dofile("mods/fort9000dev/ai/ai.lua")
Load(true)
for i=1,40 do CAI_Think() end
print("Rebuild[59] =", tostring(data.Rebuild[59]))
