MAX_SIDES=100; teamId=102; enemyTeamId=1
CS_SUCCESS=0; CS_INSUFFICIENTRESOURCES=-3; CS_OBSTRUCTED=-7; CS={[0]="CS_SUCCESS",[-3]="CS_INSUFFICIENTRESOURCES",[-7]="CS_OBSTRUCTED"}
data={OffensiveFireProbability={cannon=0.8},AntiAirFireProbability={machinegun=0.7}, fortIndex=225}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return {metal=0,energy=0} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
dofile("mods/fort9000/ai/ai.lua")
function CreateLink(t,m,a,b) if m=="armour" then return CS_OBSTRUCTED end return CS_SUCCESS end
function CreateNode(t,m,a,p) return CS_INSUFFICIENTRESOURCES end
Load(true)
print(CreateLink(102,"armour",10006,10007), CreateLink(102,"armour",10006,10007), CreateLink(102,"bracing",1,2), CreateNode(102,"bracing",1,{x=1,y=2}))
