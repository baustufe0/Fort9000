-- Simulates a player building on the Vanilla starting fort (side arg[1]: 1 or 2, mirrored) with a mistake,
-- scaffolding, an upgrade and a material change, while the AI on the other side builds too.
-- The output is a log for .dev/tools/fortgen/rec_fort.py; both sides must give the same plan.
local side = tonumber(arg[1]) or 1
local team = (side == 2) and 102 or 1
local other = (side == 2) and 1 or 102
local sx = (side == 2) and -1 or 1
MAX_SIDES = 100
function Log(s) print(s) end
print("ActivateAI team " .. other .. " team members 0 fort fort-t1f1-Template-1.lua")
-- runtime ids of the starting fort nodes 56, 55, 58 of Template-1
local P = { [7] = { -3093.19, 205.21 }, [8] = { -2945.11, 206.49 }, [9] = { -2846.18, 203.99 } }
local function V(x, y) return { x = sx * x, y = y } end
function NodePosition(id) local p = P[id] return p and V(p[1], p[2]) end
dofile("mods/fort9000dev/script.lua")
Load(true)
local function node(id, x, y) P[id] = { x, y }; OnNodeCreated(id, team, V(x, y), false, true) end
local function link(a, b, m) OnLinkCreated(team, m, a, b, NodePosition(a), NodePosition(b)) end
local function dev(i, d, a, b, t, u)
	-- the game places a team-1 plan for team 2 with the device nodes swapped and LinkT mirrored
	if side == 2 then a, b, t = b, a, 1 - t end
	OnDeviceCreated(team, i, d, a, b, t, u)
end
node(500, -3100, 105); link(7, 500, "bracing")
link(8, 501, "bracing"); node(501, -2945, 105)              -- link reported before its new node
link(500, 501, "bracing")
link(500, 8, "backbracing"); OnLinkDestroyed(team, "backbracing", 500, 8, 0)     -- mistake, removed
OnLinkCreated(other, "bracing", 3, 4, V(100, 100), V(200, 100))                   -- the AI builds too
dev(900, "machinegun", 8, 9, 0.4)
node(502, -3000, 30); link(500, 502, "bracing"); link(501, 502, "bracing")       -- scaffolding ...
OnLinkDestroyed(team, "bracing", 500, 502, 0); OnLinkDestroyed(team, "bracing", 501, 502, 0); OnNodeDestroyed(502, true)
dev(901, "sniper", 500, 501, 0.3); OnDeviceDeleted(team, 901, "sniper", 500, 501, 0.3)
dev(904, "turbine", 500, 501, 0.5); dev(905, "turbine2", 500, 501, 0.5, 904)              -- upgraded, then scrapped:
OnDeviceDeleted(team, 904, "turbine", 500, 501, 0.5); OnDeviceDeleted(team, 905, "turbine2", 500, 501, 0.5)   -- both left out
dev(902, "mine", 90, 91, 0.5); OnGroundDeviceCreated(team, 902, "mine", V(-3029.41, 700))
dev(903, "minigun", 8, 9, 0.4, 900); OnDeviceDeleted(team, 900, "machinegun", 8, 9, 0.4)   -- upgrade
OnLinkDestroyed(team, "bracing", 7, 8, 0); link(7, 8, "armour")                   -- material change
node(503, -3100, 5); link(500, 503, "bracing")
dev(906, "sandbags", 7, 8, 0.5); OnDeviceDestroyed(team, 906, "sandbags", 7, 8, 0.5)  -- shot away: kept
node(504, -3200, 5); link(500, 504, "bracing"); OnNodeDestroyed(504, true)       -- strut not reported: left out
OnGameResult(team)
