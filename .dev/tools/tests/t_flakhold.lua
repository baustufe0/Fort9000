-- Fire.AntiAirFirst: flak fires at the enemy fort only while the enemy has nothing it should shoot down.
MAX_SIDES = 100; teamId = 102; enemyTeamId = 1
data = { OffensiveFireProbability = { cannon = 0.8, flak = 0.6, machinegun = 0.5 },
  AntiAirFireProbability = { machinegun = 0.7, flak = 0.9 },
  FireDuringRebuildProbability = { flak = 0.2, cannon = 0.2 }, fortIndex = 20, Rebuild = {} }
HeavyArmsPriorities = { "cannon" }; SmallArmsPriorities = { "sniper" }
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return { metal = 600, energy = 3000 } end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
local enemy = {}
function GetDeviceCountSide(side) return side == 1 and #enemy or 0 end
function GetDeviceIdSide(side, i) return 100 + i end
function GetDeviceType(id) return enemy[id - 99] end
Fort = {} for i = 1, 30 do Fort[i] = { Type = 5, DeviceSaveName = "bracing" } end FortPos = { x = 0, y = 0 }
dofile("mods/fort9000dev/ai/ai.lua")
Load(true)
local function show(tag)
  print(string.format("%s: flak offensive=%s rebuild=%s anti-air=%s machinegun offensive=%s", tag,
    tostring(data.OffensiveFireProbability.flak), tostring(data.FireDuringRebuildProbability.flak),
    tostring(data.AntiAirFireProbability.flak), tostring(data.OffensiveFireProbability.machinegun)))
end
CAI_Think(); show("no threats")
enemy = { "sandbags", "mortar", "mortar" }
CAI_Think(); show("mortars")
CAI_Think()
enemy = { "sandbags" }
CAI_Think(); show("mortars gone")
print("NoOffence untouched: " .. tostring(Strategy.Fire.NoOffence.flak))
