MAX_SIDES=100; teamId=102; enemyTeamId=1
CS_SUCCESS=0; CS_INSUFFICIENTRESOURCES=-3; CS_UNSTABLE=-14; CS={[0]="CS_SUCCESS",[-3]="CS_INSUFFICIENTRESOURCES",[-14]="CS_UNSTABLE"}
data={OffensiveFireProbability={cannon=0.8},AntiAirFireProbability={machinegun=0.7}, fortIndex=12}
HeavyArmsPriorities={"cannon"}; SmallArmsPriorities={"sniper"}
function Log(s) print(s) end
function ScheduleCall() end
function ScheduledCallCountOfFunc() return 0 end
function GetTeamResources() return {metal=0,energy=0} end
function Load() end
function MirrorFort() end
function OnWeaponFired() end
function OnDeviceDestroyed() end
dofile("mods/fort9000dev/ai/ai.lua")
-- plan (already in world coordinates): nodes 1, 2 and 10000; node 3 is not in the plan
Fort = {
	{ Type = 1, OriginalNodeAId = 1, PosA = { x = 0, y = 0 }, OriginalNodeBId = 10000, NewNodePos = { x = 100, y = 0 }, MaterialSaveName = "bracing" },
	{ Type = 3, OriginalNodeAId = 2, PosA = { x = 0, y = 100 }, OriginalNodeBId = 10000, PosB = { x = 100, y = 0 }, MaterialSaveName = "bracing" },
}
-- actual nodes: 10000 moved 30 to the right and 12 down, node 2 moved 4 up
local actual = { [501] = { x = 0, y = 0 }, [502] = { x = 0, y = 96 }, [503] = { x = 130, y = 12 }, [504] = { x = 7, y = 7 } }
function NodePosition(id) return actual[id] end
function NodeVelocity() return { x = 0, y = 0 } end
function NodeLinkCount() return 0 end
function NodeLinkedNodeId() return 0 end
function CreateDeviceWithFlags() return CS_UNSTABLE end
Load(true)
data.OriginalToActual = { [1] = 501, [2] = 502, [10000] = 503, [3] = 504 }
CAI_SHAPE_PER_LINE = 2
CreateDeviceWithFlags(102, "cannon", 501, 503, 0.2)    -- first CS_UNSTABLE: UNSTABLE + SHAPE (2 parts)
CreateDeviceWithFlags(102, "cannon", 501, 503, 0.2)    -- same device and place again: no new SHAPE
MirrorFort()                                             -- the game mirrored the plan: dx is reported mirrored back
CAI_LogShape("minute")
CAI_SHAPE_MAX = CAI_ShapeCount                           -- cap reached: nothing more
CAI_LogShape("minute")
print("shapes=" .. CAI_ShapeCount)
