-- Nachbau der Spielumgebung fuer die eingebaute KI
MAX_SIDES = 100; teamId = 2; enemyTeamId = 1
data = { difficulty = 0.5,
  OffensiveFireProbability = { machinegun = 0.05, cannon = 0.8, mortar = 1, laser = 0.8 },
  AntiAirFireProbability = { machinegun = 0.7, minigun = 0.5 } }
HeavyArmsPriorities = { "cannon","laser","barreltemp","reactor","turbine2","mine2","turbine","mine","factory","workshop","upgrade","machinegun","mortar2","battery","missile2","missile2inv","missile","missileinv","store","sniper2","sniper","minigun","newmoddevice" }
SmallArmsPriorities = { "sniper2","barreltemp","sniper","minigun","mortar2","mortar","machinegun","cannon","laser","reactor" }
function Log(s) print(s) end
local sched = {}
function ScheduleCall(t, f, ...) table.insert(sched, f) end
function ScheduledCallCountOfFunc(f) local n=0 for _,g in ipairs(sched) do if g==f then n=n+1 end end return n end
local metal = 100
function GetTeamResources(t) return { metal = metal, energy = 2000 } end
baseLoaded = 0
function Load(g) baseLoaded = baseLoaded + 1 end
function OnWeaponFired() end
function OnDeviceDestroyed() end
function OnGameResult() end
dofile("mods/fort-9000/ai/ai.lua")
Load(true); Load(false)
assert(baseLoaded == 2, "base Load nicht aufgerufen")
assert(ScheduledCallCountOfFunc(CAI_Think) == 1, "Think doppelt geplant")
CAI_Think()
-- Gegner beschiesst uns 20x mit Moerser, trifft 5x den Reaktor
for i=1,20 do OnWeaponFired(1, "mortar", 50, 1000+i, nil) end
for i=1,5 do OnDeviceHit(2, 7, "reactor", 0.5, 1000+i, 1, nil, false) end
metal = 2000
for i=1,30 do CAI_Think() end  -- bis in die spaete Phase
assert(data.HeavyArmsPrioritiesOverride[1] ~= nil)
print("HEAVY TOP3:", data.HeavyArmsPrioritiesOverride[1], data.HeavyArmsPrioritiesOverride[2], data.HeavyArmsPrioritiesOverride[3])
print("cannon offensiv:", data.OffensiveFireProbability.cannon, "mg:", data.OffensiveFireProbability.machinegun)
assert(#data.HeavyArmsPrioritiesOverride == #HeavyArmsPriorities, "Liste hat Eintraege verloren")
OnDeviceDestroyed(1, 9, "mortar"); OnDeviceDestroyed(2, 8, "cannon")
EnableHumanAssist(); CAI_Think(); OnWeaponFired(1,"mortar",5,77,nil); OnGameResult(2)
print("MOCK OK")
