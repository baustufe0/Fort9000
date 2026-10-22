MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={cannon=0.8},AntiAirFireProbability={machinegun=0.7}, UpdatePeriod=3, UpdateAfterRebuildDelay=2, ConstructionPeriodMean=11, ConstructionPeriodMin=6, NonConstructionPeriodMean=13, NonConstructionPeriodMin=6, RepairPeriod=10}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return {metal=600,energy=3000} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
function EnableHumanAssist() data.HumanAssist = true end
dofile("mods/fort-9000/ai/ai.lua")
Load(true)
print("KI:", data.UpdatePeriod, data.ConstructionPeriodMean, data.NonConstructionPeriodMean, data.RepairPeriod)
EnableHumanAssist()
print("after assist AI:", data.UpdatePeriod, data.ConstructionPeriodMean, data.NonConstructionPeriodMean, data.RepairPeriod)
