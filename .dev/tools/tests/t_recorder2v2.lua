-- 2v2: two AI teams (102, 202) on side 2. The snapshot sums their resources and lists both teams.
MAX_SIDES = 100
local devs = { [1] = { [1] = "reactor" }, [2] = { [2] = "reactor", [3] = "mine", [4] = "reactor" } }
local teamOf = { [1] = 1, [2] = 102, [3] = 102, [4] = 202 }
function Log(s) print(s) end
function GetDeviceCountSide(s) local n=0 for _ in pairs(devs[s]) do n=n+1 end return n end
function GetDeviceIdSide(s, i) local ids={} for id in pairs(devs[s]) do ids[#ids+1]=id end table.sort(ids) return ids[i+1] end
function GetDeviceType(id) return devs[1][id] or devs[2][id] end
function GetDeviceTeamIdActual(id) return teamOf[id] end
function GetTeamResources(t) return { metal = (t == 202) and 700 or 600, energy = 3000 } end
dofile("mods/fort9000dev/script.lua")
Load(true)
Update(0)
