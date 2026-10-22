-- Simuliert 6 Partien: wer frueh die gegnerischen Kanonen zerstoert, gewinnt.
local game = tonumber(arg[1])
MAX_SIDES = 100
local devs = { [1] = {}, [2] = {} }
local nextId = 1
local function add(side, t) devs[side][nextId] = t; nextId = nextId + 1 end
for side = 1, 2 do for _, t in ipairs({"reactor","cannon","cannon","mortar","machinegun","mine","mine"}) do add(side, t) end end
function Log(s) print(s) end
function GetDeviceCountSide(s) local n=0 for _ in pairs(devs[s]) do n=n+1 end return n end
function GetDeviceIdSide(s, i) local ids={} for id in pairs(devs[s]) do ids[#ids+1]=id end table.sort(ids) return ids[i+1] end
function GetDeviceType(id) return devs[1][id] or devs[2][id] end
function GetTeamResources(s) return { metal = 500 + 10*s, energy = 3000 } end
dofile("mods/fort-9000/script.lua")
local winner = (game % 3 == 0) and 2 or 1
local loser = 3 - winner
Load(true)
for frame = 0, 6000, 25 do
  Update(frame)
  for side = 1, 2 do
    for id, t in pairs(devs[side]) do
      if (t == "cannon" or t == "mortar") and frame % 100 == 0 then OnWeaponFired(side + 100, t, id, 1, nil) end
    end
  end
  if frame == 1500 or frame == 1800 then -- Sieger zerstoert gegnerische Kanone
    for id, t in pairs(devs[loser]) do if t == "cannon" then devs[loser][id] = nil; OnDeviceDestroyed(loser, id, t); break end end
  end
  if frame == 2500 then -- Verlierer zerstoert eine Mine
    for id, t in pairs(devs[winner]) do if t == "mine" then devs[winner][id] = nil; OnDeviceDestroyed(winner, id, t); break end end
  end
  if frame == 3000 then OnDeviceCompleted(winner, 99, "mortar") end
end
OnGameResult(winner)
