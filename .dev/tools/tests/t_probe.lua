MAX_SIDES=100; teamId=102; enemyTeamId=1
CS_SUCCESS=0; CS_INSUFFICIENTRESOURCES=-3; CS_UNSTABLE=-14; CS_OCCUPIED=-5; DD_SUCCESS=0
CS={[0]="CS_SUCCESS",[-3]="CS_INSUFFICIENTRESOURCES",[-5]="CS_OCCUPIED",[-14]="CS_UNSTABLE"}
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
-- plan (world coordinates): node 1 and 10000; node 503 has sagged 5 below its plan position
Fort = {
	{ Type = 1, OriginalNodeAId = 1, PosA = { x = 0, y = 0 }, OriginalNodeBId = 10000, NewNodePos = { x = 100, y = -5 }, MaterialSaveName = "bracing" },
}
local pos = { [501] = { x = 0, y = 0 }, [503] = { x = 100, y = 0 }, [504] = { x = 100, y = -100 }, [505] = { x = 0, y = -100 } }
function NodePosition(id) return pos[id] end
function NodeVelocity() return { x = 0, y = 0 } end
function NodeLinkCount() return 0 end
function NodeLinkedNodeId() return 0 end
local links = {
	{ 503, 501, "bracing", 1, 0.12 },
	{ 503, 504, "backbracing", 1, -0.31 },   -- not a probe material
	{ 504, 505, "bracing", 1, 0.40 },        -- the cannon is refused here
	{ 505, 501, "armour", 1, 0.02, 77 },     -- carries a battery and a store: enumerated once per device
	{ 505, 501, "armour", 1, 0.02, 78 },
}
local devType = { [77] = "battery", [78] = "store" }
local devT = { [77] = 0.5, [78] = 0.3 }
function GetDeviceType(id) return devType[id] or "sniper" end
function GetDeviceLinkPosition(id) return devT[id] end
function EnumerateLinks(team, callback)
	for _, l in ipairs(links) do
		if not _G[callback](l[1], l[2], l[3], l[4], l[5], 0, l[6] or 0) then break end
	end
end
starve = 1            -- the first attempt is short of resources once
nextId, removed = 900, {}
function CreateDeviceWithFlags(team, saveName, a, b, t)
	if starve > 0 then starve = starve - 1; return CS_INSUFFICIENTRESOURCES end
	if saveName == "cannon" and a == 504 then return CS_UNSTABLE end
	if saveName == "cannon" and a == 505 and t > 0.5 then return CS_OCCUPIED end
	nextId = nextId + 1
	return nextId
end
function DestroyDeviceById(id) removed[#removed + 1] = id; return DD_SUCCESS end
Load(true)
data.OriginalToActual = { [1] = 501, [10000] = 503 }
CAI_PROBE_PER_LINE = 3
FortPlanConfig.Probe = { Devices = { "sniper", "cannon" }, LinkT = { 0.2, 0.8 }, Max = 11, Hold = 0 }
data.Disable = false
CAI_ProbeStart(480)
print("disabled while probing=" .. tostring(data.Disable))
for i = 1, 40 do CAI_ProbeTick() end
-- a second run with Hold: the cannon stands, its load is measured, then it is removed
CAI_Probe = nil
FortPlanConfig.Probe = { Devices = { "cannon" }, LinkT = { 0.5 }, Hold = 2, Box = { -10, -10, 110, 10 } }
CAI_ProbeStart(500)
CAI_ProbeTick()
links[1][5] = 0.3
pos[503] = { x = 100, y = 4 }
for i = 1, 10 do CAI_ProbeTick() end
print("removed=" .. table.concat(removed, ",") .. " disabled after=" .. tostring(data.Disable))
