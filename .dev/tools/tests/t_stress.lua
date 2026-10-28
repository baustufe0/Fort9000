MAX_SIDES=100; teamId=102; enemyTeamId=1
CS_SUCCESS=0; CS_INSUFFICIENTRESOURCES=-3; CS_UNSTABLE=-14; CS={[0]="CS_SUCCESS",[-3]="CS_INSUFFICIENTRESOURCES",[-14]="CS_UNSTABLE"}
data={OffensiveFireProbability={cannon=0.8},AntiAirFireProbability={machinegun=0.7}, fortIndex=12}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return {metal=0,energy=0} end
function Load() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
dofile("mods/fort9000dev/ai/ai.lua")
Fort = {
	{ Type = 1, OriginalNodeAId = 1, PosA = { x = 0, y = 0 }, OriginalNodeBId = 10000, NewNodePos = { x = 100, y = 0 }, MaterialSaveName = "bracing" },
}
function NodePosition(id) return { x = 0, y = 0 } end
function NodeVelocity() return { x = 0, y = 0 } end
function NodeLinkCount() return 0 end
function NodeLinkedNodeId() return 0 end
function CreateDeviceWithFlags() return CS_UNSTABLE end
-- the engine's link enumeration: (nodeA, nodeB, saveName, relativeHealth, stress, segmentsOnFire, deviceId)
local links = {
	{ 501, 503, "bracing", 1, 0.12 },        -- at the device (nodes 501, 503)
	{ 503, 504, "backbracing", 1, -0.31 },   -- at the device, compressed
	{ 504, 505, "bracing", 1, 0.95 },        -- most stressed of the fort, not at the device
	{ 505, 506, "door", 1, 0.02 },
}
enumerated = 0
function EnumerateLinks(team, callback, h1, h2, exclude, flag)
	for _, l in ipairs(links) do
		enumerated = enumerated + 1
		if not _G[callback](l[1], l[2], l[3], l[4], l[5], 0, 0) then break end
	end
end
Load(true)
data.OriginalToActual = { [1] = 501, [10000] = 503 }
CAI_STRESS_TOP = 2
CreateDeviceWithFlags(102, "cannon", 501, 503, 0.2)    -- first CS_UNSTABLE: STRESS line
CreateDeviceWithFlags(102, "cannon", 501, 503, 0.2)    -- same device and place: no second scan
CAI_STRESS_MAX = CAI_StressCount
CreateDeviceWithFlags(102, "laser", 504, 505, 0.5)     -- other place, but the cap is reached
print("stress=" .. CAI_StressCount .. " enumerated=" .. enumerated)
