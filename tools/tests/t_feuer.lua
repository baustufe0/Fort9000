MAX_SIDES=100; teamId=102; enemyTeamId=1
data={OffensiveFireProbability={mortar=1,sniper=0.8},AntiAirFireProbability={machinegun=0.7}, HardThreshold=0.75,
  FireDuringRebuildProbability={mortar=0.27, sniper=0.6, machinegun=0.05}, offencePoints=100000000, ActionQueue={}}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
local sched={}
function ScheduleCall(t,f) sched[#sched+1]=f end
function ScheduledCallCountOfFunc(f) local n=0 for _,g in ipairs(sched) do if g==f then n=n+1 end end return n end
function GetTeamResources() return {metal=600,energy=3000} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
function EnableHumanAssist() data.HumanAssist=true end
local weapons={11,12,13,14,15}
function GetWeaponCount() return #weapons end
function GetWeaponId(t,i) return weapons[i+1] end
function IsDummy() return false end
function IsAIDeviceAvailable() return true end
function IsWeaponReadyToFire(id) return id ~= 13 end   -- 13 laedt gerade nach
local fired={}
function TryFireGun(id) fired[#fired+1]=id end
dofile("mods/fort-9000/ai/ai.lua")
Load(true)
print("HardThreshold", data.HardThreshold, "Moerser beim Bauen", data.FireDuringRebuildProbability.mortar, "MG", data.FireDuringRebuildProbability.machinegun)
print("FireTick geplant:", ScheduledCallCountOfFunc(CAI_FireTick))
for i=1,4 do CAI_FireTick() end
print("gefeuert:", table.concat(fired,","))
CAI_Think()
EnableHumanAssist()
print("nach Hilfs-KI: HardThreshold", data.HardThreshold, "Moerser", data.FireDuringRebuildProbability.mortar)
local before=#fired; CAI_FireTick(); print("Hilfs-KI feuert nicht:", #fired==before)
