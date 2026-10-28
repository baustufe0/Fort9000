-- A match ends, the player restarts it: the game rewinds to frame 2 without reloading the mod script.
-- The recorder must start a new match (START restart=1) and take snapshots again.
MAX_SIDES = 100
local devs = { [1] = { [1] = "reactor" }, [2] = { [2] = "reactor" } }
function Log(s) print(s) end
function GetDeviceCountSide(s) local n = 0 for _ in pairs(devs[s]) do n = n + 1 end return n end
function GetDeviceIdSide(s, i) local ids = {} for id in pairs(devs[s]) do ids[#ids + 1] = id end table.sort(ids) return ids[i + 1] end
function GetDeviceType(id) return devs[1][id] or devs[2][id] end
function GetTeamResources(s) return { metal = 500, energy = 3000 } end
dofile("mods/fort9000/script.lua")
Load(true)
for frame = 0, 3000, 25 do Update(frame) end
OnGameResult(2)
print("-- restart")
for frame = 2, 400, 25 do Update(frame) end
OnGameResult(1)
