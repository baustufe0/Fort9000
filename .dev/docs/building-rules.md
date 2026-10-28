# FORT 9000 – Fort building rules (lessons learned)

Learned from the game files and from test matches against the AI (Vanilla, weapon_pack, difficulty 0.5–1, October
2026). The generator follows these rules and `.dev/tools/fortgen/rules.py` checks them (see "Validation"). When a rule
changes, update this file, the generator and `rules.py` together. Map-specific facts (coordinates, slots, plans) are in
[maps/](maps/); the test matches behind the rules in [history/](history/).

## Game mechanics (facts)

### Materials (`data/materials/building_materials.lua`)

| Material | Stiffness | Mass/length | Breaks below / above | Hit points | Notes |
|---|---|---|---|---|---|
| `bracing` (foreground wood) | 200000 | 0.25 | 0.90 / 1.10 | 150 | stops most shots and the wind; a device built on it turns it into background bracing |
| `backbracing` (background wood) | 200000 | 0.25 | 0.92 / 1.08 | 100 | `SupportsDevices = false`, yet devices stand on it: the game's own plans put 937 devices on background bracing (507 turbines), a player ~40 (no material swap is logged); most projectiles and the wind pass through it (not laser, buzzsaw, howitzer); burns |
| `armour` / `door` | 250000 | 0.5 | 0.90 / 1.10 | 400 | armour in a weapon's way is turned into a door when the weapon is placed |

- Minimum strut length 37.5 (doors 49), so woodspam layers are at least ~40 apart. A new node may be at most 150 from
  the node it is built from (`StandardMaxLength`); struts between existing nodes up to 218 (`StandardMaxLinkLength`;
  the generator uses 205, so a 155-wide cell may be at most 130 high). A strut anchored to the ground may be as long
  as a strut between nodes: a player built new foundations 181-212 away from their source node (26.10.2026).
- Background bracing is as stiff and heavy as foreground bracing; it only breaks sooner, so in a sagging cell its
  diagonal is the first link near its limit.

### Devices (game files)

A device's box reaches **2 × `SelectionHeight` above its strut** (`rules.BOX_TOP`; the game gives half-extents around
`SelectionOffset`): machine gun 81, sniper 91, mortar 61, laser 101, 20mm cannon 111, rocket/EMP rocket 112,
flak/shotgun 118, cannon 121, turbine 127, munitions plant/armoury 170 (smoke bomb: packed, assumed 127). The overlap
checks use the table values as full widths, and the generator keeps eco devices out of a tall box above their row.

**weapon_pack tech:** the armoury (400 m / 2000 e, 60 s) opens the munitions plant and the factory just as the workshop
does (`PrerequisiteAlt = "armoury"`; with weapon_pack the factory costs 5000 energy and takes 90 s); firebeam and laser
need the factory, cannons the munitions plant. A player reached cannons, firebeams and flak without a workshop
(26.10.2026, Vanilla-7).

| Device | Width × height (game values) | Mass |
|---|---|---|
| machine gun, minigun | 40 × 40 | 40 |
| sniper, AP sniper | 70 × 45 | 40 |
| mortar, heavy mortar | 40 × 30 | 60 |
| cannon | 95 × 60 | 120 |
| 20mm cannon (weapon_pack) | 90 × 55 | 100 |
| laser | 50 × 50 | 100 |
| turbine | 40 × 63 (needs ~100 spacing) | 70 |
| battery / store | 40 × 40 | 40 / 60 |
| workshop / factory / upgrade centre | 90 × 45 | 100 |
| munitions plant / armoury (weapon_pack) | 45 × 85 | 120 |
| sandbags | 40 × 25 (box 51 high) | 45 |
| flak, shotgun (weapon_pack) | 40 × 58.75 | |
| EMP rocket, rocket (weapon_pack) | 40 × 55.75 | |

- `weapon_pack` is always installed: cannon and 20mm cannon need the **munitions plant** (needs workshop or armoury;
  800 metal / 5000 energy); laser and firebeam need the factory.
- **One device per strut**, however short the devices are; the game's Abyss-1 sells its sandbags (`DESTROY_DEVICE`)
  before putting a laser on their strut. `split_edges` builds a strut in two halves for two devices.
- **Devices side by side must not overlap:** the widths in the table are half-widths (`SelectionWidth`), and a
  weapon's body sits `SelectionOffset` forward (sniper 40, cannons 18). Two devices at the same height need the sum
  of their half-widths between their centres: 80 for two mortars, turbines, sandbags or machine guns, 130 for an
  upgrade centre beside a battery, 180 for two tech buildings. This explains every refusal so far: mortars 77 apart,
  sandbags 70 from a mortar, turbines 46-54 apart, Vanilla-5's upgrade centre 155 from the factory (`CS_OCCUPIED`,
  later `CS_UNSTABLE`); 89-127 apart mortars and sandbags were placed (the game's plans: mortars 91-122, turbines ~100).
  A munitions plant (45) fits on the slot where an upgrade centre (90) does not.
- **A device's body turns the solid struts it overlaps into background bracing**, on which nothing can then be placed
  (a heavy weapon's box reaching the floor above; a sniper's body over the post in front of it, which it then fires
  through). A heavy weapon's body sits 18 in front of its LinkT point (`SelectionOffset` -18 in the weapon's frame,
  facing left, mirrored for team 1); the laser is centred.
- The AI upgrades whatever device stands on the planned strut (`GetDeviceIdOnPlatform`), also one of the starting fort.
  Upgrades need the upgrade centre *finished*; the AI waits on a planned upgrade without moving on.

### Economy (`devices/device_list.lua`, weapon_pack, `SNAP` lines)

- Every further mine +4 metal/s and -5 energy/s; a turbine up to +45 energy/s, upgraded 67.5 (upgrade 200 m / 1000 e).
- Storage: 600 metal + 300 per store, 3000 energy + 2000 per battery.
- Costs (metal / energy / build time): mine 300 / 2000 / 30 s, turbine 200 / 800 / 20 s, battery 150 / 625 / 16 s,
  store 200 / 500 / 16 s, workshop 400 / 2000 / 60 s, munitions plant 800 / 5000 / 90 s, factory 800 / 6000 / 60 s,
  20mm 600 / 4000 / 70 s (a burst 40 / 2000, reload 28.8 s), laser 1000 / 6000 / 120 s (a beam 5000 e, reload 24 s),
  sandbags 0 / 300 / 30 s; a mortar shot 200 energy (reload 9 s).
- Struts per unit length: wood 0.1 metal / 0.5 energy, armour 1.8 / 1.5, door 2 / 2; selling refunds wood 0.025,
  armour 0.9, door 1.0 metal. Building a tower uses ~60 energy per second.
- Costs are paid when a device is placed and the build times hold exactly. The AI moves on once a device is
  placed, not when it is finished, but it **waits on a device until its tech is finished** (no error).

### Lines of fire

- Every direct-fire weapon needs a clear line straight ahead (`MinFireClearance` 500–1000): foreground struts in it
  stop the AI from firing (woodspam built after a cannon: 0 cannon shots).
- When a weapon is placed, the game **recesses** foreground struts already in its way within its `RecessionBox`:
  bracing becomes background bracing, armour a door. The box (weapon files: `Size`, `Offset`, centred on the offset)
  does **not start at the weapon**; ahead of its LinkT point it covers: machine gun 42.5-62.5, minigun, laser and
  firebeam 130-330, sniper, AP sniper, cannon and 20mm 200-400, flak 60-140, rocket, EMP rocket and shotgun 70-170.
- A strut closer than the box is only cleared if the weapon's **body** overlaps it: `SelectionWidth` (a half-width) to
  both sides of a centre moved forward by `SelectionOffset` (sniper 40, cannon and 20mm 18, laser and machine guns 0),
  2 × `SelectionHeight` high. So the sniper's body reaches 110 ahead, the 20mm's 108, but the laser's only 50: the
  Vanilla-5 laser never fired through the wood post 50 in front of it (every try `RAY_HIT_STRUCTURE` on its own
  bracing), while the 20mm in the same cell fired 126 shots. Struts built after the weapon, between its body and its
  box, or beyond the box block it (`rules.recessed`).
- Doors never block: the AI opens all doors in the way before firing (`OpenWeaponDoors`). Every direct-fire weapon
  gets a metal door in front of it. A wood post that was meant to become a door blocks (the 20mm did not fire for 2-3
  minutes until its post became a door).
- The built-in AI only fires when the ray from the weapon reaches an enemy device or structure (`FindTarget` ->
  `TargetObstructed`, flag `RAY_ALLIED_BG_BLOCKS`); otherwise `TryFireGun` declines without an error
  (`FIRETRY ... fired=0`, [ai.md](ai.md#fire-control)). The 20mm may fire alone (grouping affinity `alone` = 1).
- **Doors cut to the shot:** a door opens at `DoorSpeed` 50 per second (`MinLength` 49), so a 100-long door stands
  open ~2 s per shot, long enough to be sniped through. Only the part the shot passes must be a door: the game wants a
  corridor ~20 to each side at the muzzle widening to 40 at 1000 (`FireClearanceOffsetInner/Outer`). Barrel height
  above the strut (`RecessionBox` offset): machine gun 40, sniper 50, 20mm cannon, laser and firebeam 60, cannon 70;
  barrel length 60 (machine gun), 100 (sniper, cannons), 58 (laser, firebeam). Where the barrel exactly is, is not certain, so
  `split_doors` covers both that height and `rules.py`'s muzzle (0.6 of the device's height), ±12.5 plus ~5 degrees of
  aim beyond a muzzle 44 behind the door. A door cut this way worked (Vanilla-2 sniper: 124 shots; Vanilla-3 20mm: 126).
  The new nodes need a brace that does not pass through a device's box (a brace through the sniper's spot got it
  refused); without one the door is not split. Machine guns keep full doors (anti-air at steep angles).
- Mortars fire steeply up and forward: the roof above them must be a door or open and no other part of the fort may
  stand in that arc (`rules.MORTAR_ARC`).

### Wind

The game tests the wind with rays from each turbine to both sides, 25 to 600 away, within ±10° (`devices/windturbine.lua`).
Every material except background bracing, shields, rope and fuse blocks the wind (`CollidesWithWind`); with wind from
one side only the turbine falls back to a lower minimum efficiency (0.3 vs. 0.35; exact formula unknown). So a turbine
needs open air 600 to both sides at its own height: a turbine beside a taller solid tower, inside a storey with solid
posts, or behind woodspam at its hub height gets (almost) no wind from that side.

### `CS_UNSTABLE` (the game refuses a device; no flag skips the check)

- Deterministic and independent of the device's weight (probe: sniper and 20mm cannon got the same result on 51 of 54
  struts, [history/probe-runs.md](history/probe-runs.md)).
- Weak support causes it: a wall mid-span on a straight beam, storeys on an open storey of background posts, the long
  floor beam of a high narrow top storey, a floor above a weapon cell (its diagonals are background bracing, so the
  floor sags), cells squeezed by a leaning tower. The `UNSTABLE` line ([debugging.md](debugging.md)) showed struts
  stretched 4–7 % with the structure sagging 13–27, or moving under fire.
- Devices added late to a finished, loaded fort fail where early ones on a light structure worked: on the finished fort
  the probe was refused on 80 of 84 attempts on a strut sharing a node with a strut that carries a device (38 of 144
  without; best other split sag > 40). Built together in plan order, devices on struts sharing a node are fine (the
  game's own plans), so this is not a plan rule.
- What works: heavy weapons in solid X-braced storeys on strong posts (the starting fort's own posts), near the back
  post or at LinkT 0.5 inside their cell, in storeys high enough that their box does not reach the floor above; never
  in the top storey or directly on another weapon cell. Light devices (machine gun, turbine) usually succeed on a
  later try; heavy ones fail persistently.

### Other build errors

`CS_OCCUPIED` (spot taken: starting-fort devices, debris, devices too close; common and harmless on a device's first
attempt), `CS_OBSTRUCTION` (something in the way; a roof turbine once, placed shortly after), `CS_NODESTOOFAR` /
`CS_NODESTOOCLOSE` (length limits; for a device: the strut already carries one), `CS_INVALIDNODES` (a device on a strut
of 30 degrees or more), `CS_PREQUISITENOTMET` (tech missing or not finished).

### Changing a strut's material

A `CREATE_LINK` with another material on an existing strut swaps it (armour -> wood refunds 0.9 metal per length), but
only once the strut is finished; on a strut still under construction (5 s and more) it has no effect, without an
error, and only the AI's rebuild pass after the plan corrects it.

### Node placement

The AI places a new node at the **current position of its source node plus the planned offset**
(`GetAdjustedNodePosition` in `data/ai/ai.lua`), and a node landing within 20 of an existing one snaps to it
(`SnapToNode`). A lean or sag while building is therefore copied into every node built from it, and a strut built
later between nodes from different paths takes their current distance as its rest length (locked-in deformation; the
`UNSTABLE` strain values far outside 0.90..1.10 come from this). Long node chains up one column made a tower lean ~200
forward and squeezed its cells ([history/vanilla-3-5.md](history/vanilla-3-5.md)).

### Defence: hiding, sandbags, woodspam

- **Background bracing hides** devices from the player and lets projectiles, mortar shells and the wind through; devices
  can stand on it, so turbines stacked in a lattice of background bracing all get wind (Vanilla-7's turbine block). The built-in AI checks only the terrain before firing a lobbed weapon, so mortars fire from
  inside a nest of background bracing; direct-fire weapons fire through their own background diagonals.
- **It does not stop projectiles:** hidden devices are still hit. Sandbags (or solid struts) must stand *before* the
  device they shield (mortars placed first were destroyed 3-5 s later).
- **Sandbags** (0 metal / 300 energy, 30 s, box 51 high) shield what cannot shoot back (mortars, turbines). Two stacked
  need a cell split at half height (`split_cell`) with at least 51 per half (a 100-high cell refused the upper ones).
- **Woodspam is foreground wood:** within a turbine's wind rays it blocks them, so it stays out of the turbines' height
  band; in a line of fire it must be background bracing.
- **Players brace the starting fort:** in every recorded match the player built a background brace from the
  starting fort's node at (-2996, 504) down to its front ground node (-2900, 700), 217-218 long (the game's limit is
  218), within the first 16-74 s. The starting fort has nothing across those two storeys (Vanilla-5 tests it).
- **A player's long-build fort sags:** a 1280-s player fort on Vanilla (26.10.2026) leaned back by ~65 at the starting
  fort's roof and ~150 at the top of its cannon tower while it grew (a background-bracing frame on the starting fort,
  the prow removed). Positions logged late are therefore not the positions the parts were built at.
- **Beams cut unprotected walls in seconds:** one laser beam through a starting fort's bare face brought down the
  reactor within 2 s; layers of woodspam in front of it buy time.

## Design rules (enforced by the generator for Vanilla)

1. **No overhang:** every cell needs support (both bottom corners on the starting fort, a foundation or a supported
   cell, or a short bridge). Nothing beyond a cliff except the starting fort's own prow.
2. **Supports first:** a cell's supports are built before the cell (a cell hung sideways before its column existed
   collapsed the fort after 2 minutes).
3. **Bottom up, X-braced:** cells built from the bottom up and crossbraced, the lower storeys and the weapon column at
   once, the rest in a final pass so weapons are not delayed. A tower on two foundations rises **storey by storey**
   (`tower_connect`): both parts are joined over two storeys before anything higher is built.
4. **Opening by the economy numbers:** the tech chain (workshop, then munitions plant or factory) sets a rush's pace;
   nothing that costs energy before the workshop. **Tech early, then something else:** put devices that need no tech
   (store, battery, machine gun, sniper, woodspam, mines) between a tech building and the devices that need it, since
   the AI waits on them until the tech is finished. Metal, not energy, has been the limit in every long match: mines
   early (see [maps/vanilla.md](maps/vanilla.md) for each plan's opening).
5. **Turbines on an open roof or in a hidden cage** (background bracing) with nothing resting on them, ~100 apart, at
   least as high as every solid part within 600 to both sides; never inside a storey with solid posts, never as the
   floor that carries the weapons (one hit dropped the whole upper block).
6. **Weapons:** direct-fire weapons at the front behind a door; struts in their line of fire background bracing (or
   built before the weapon within its recession box); heavy weapons in solid X-braced storeys on strong posts, never in
   the top storey, in storeys high enough for their box; mortars with a door roof or open arc, or in a low hidden nest
   with sandbags. **No weapon in the open:** its first shot shows the player where it is, so every weapon stands in a
   closed cell with a door wherever it fires through (a lobbed one, e.g. the smoke launcher, a door roof and a door in
   front; Abyss-5, 28.10.2026). **A weapon blocks the line of fire of every weapon behind it in the same row** (rows closer than 50
   in height count as one): each weapon that fires at the enemy fort stands alone in its row or at its front. Allowed
   behind another weapon: machine guns and miniguns (anti-air only in this mod) and a lobbed weapon behind a lobbed
   one (the game's own plans put mortars side by side). **Sandbags block the line of fire too:** no sandbags ahead of
   a weapon in its row, except for mortars (their steep shells clear them: Abyss-2's and Vanilla-6's mortars fired
   57-190 shots a match from behind sandbags); the smoke launcher counts as a weapon here (its arc is not known). A rocket (EMP rocket) also needs a short door in front of it
   like a sniper (`split_doors`; barrel 65 above its strut, 60 long, from weapon_pack's rocket files). A large weapon's fire lane (the cells ahead of it, door in the front wall) is built before the
   weapon, so it never stands in an open cell. Cells where a device type failed in every test are left to others
   (`weapon_avoid`, `turbine_avoid`).
7. **Woodspam:** cheap wooden layers in front of what must be protected (the reactor's front, the starting fort's
   lower face, the weapon tower); background bracing in a line of fire, never within a turbine's wind rays.
8. **Devices only on solid bracing**; batteries and stores on proven slots, not on the ground row; no strut on a mine
   site.
9. **No metal roof** (heavy); armour only where something must be protected.
10. **Keep the AI busy:** every plan ends with a late-game block (anti-air, weapons, upgrades, storage), so the AI does
    not sit idle at the storage cap.
11. **Short node chains:** every new node is built from the built neighbour with the shortest chain to an anchor
    (starting-fort node or foundation), then from the node directly below, then the nearest, within 150 (`ensure_node`,
    `chain`). `gen_fort.py` prints the chain lengths (`rules.node_chains`; Vanilla max 10 / avg 3.6-3.8, Abyss max 5-6 /
    avg 2.4-2.9). `support_cheapest` rests a cell on the support with the fewest cells below it.
12. **Final material at once:** a strut is placed with its final material when the plan would change it within
    `SWAP_WINDOW` (20) actions (a swap on a strut under construction has no effect).
13. **Hide and shield what cannot shoot back:** mortars and turbines in a storey of background bracing (`hidden_box`),
    130 high, each mortar row with two stacked sandbags in its front cell (not in front of other weapons, rule 6) (`split_cell`, `sandbag_slots`) built before or right
    after its first device; every device on its own strut, ~90 from its neighbours at the same height. Weapon doors only
    as long as the shot needs (`split_doors`). Upgrades after the upgrade centre with devices that need no tech in
    between.

## Validation (`.dev/tools/fortgen/rules.py`)

`python .dev/tools/fortgen/rules.py <plan.lua> ...` checks any plan file; `gen_fort.py` runs the same checks on every plan it
writes (`RULE ERROR` / `RULE WARN`) besides `validate()` (rock, lengths, build order, supports, prerequisites). Checked:
- strut length (37.5, doors 49);
- line of fire of direct-fire weapons and the arc of mortars: no foreground strut built after the weapon or beyond its
  recession box (doors are fine);
- a weapon in front of another weapon in the same row (error; machine guns behind, and lobbed behind lobbed, allowed);
- sandbags in front of a weapon in the same row (error; mortars and machine guns behind them allowed);
- turbine wind with the game's ray test (`wind_rays`: a side is open when at least half its rays are clear; error if
  both sides are blocked, warning if one is) and turbine spacing (≥ 90);
- two devices on one strut (a `DESTROY_DEVICE` frees it), or overlapping devices side by side on neighbouring struts
  (half-widths plus the weapon's body shift; the game's own plans pass);
- mortars at the same height closer than 90 (`MORTAR_SPACING`);
- struts lying on a mine site;
- a solid strut inside a device's box above its strut (`BOX_TOP`, the posts at its own strut's ends excluded): error
  for tall devices (rockets, flak, shotgun, smoke bomb), warning for the others. Expected warnings: the tech slots of
  the game's own plans (upgrade, factory, munitions), Abyss-4's top cannon.

The generator fixes lines of fire itself (`clear_fire_lines`, cautious: it also clears every strut the earlier model
called blocking, so plans that fired keep their cleared struts) and places mortars only where the arc is open
(`mortar_open_arc`). All current plans pass without errors. On the command line `rules.py` takes the enemy side from
the plan header (team 2 plans such as VanillaLong face left) and ignores the terrain; `check_plan(..., terrain=...)`
also lets rock block the wind rays (then every turbine on Abyss's top roof, next to the cliff wall, gets no wind from
the left; the game's Abyss-1 uses the same spots).

Whether a plan carries its own weight in its build order (sag, strut stress, struts refused because the fort has
moved) is checked by `physics.py` ([physics.md](physics.md)), not by `rules.py`.

## Approaches that failed (do not repeat)

Map-specific ones are in [maps/vanilla.md](maps/vanilla.md) and [maps/abyss.md](maps/abyss.md).

| Approach | What happened |
|---|---|
| Cells hanging sideways before their support existed | collapse after 2 min |
| Laser plan with 2–3 turbines | laser never placed or never fired (energy 170–1500) |
| Turbines in a storey with solid posts | almost no energy |
| Open turbine storey (background posts) carrying the weapon tower, also with a lighter upper block | heavy weapons `CS_UNSTABLE`; one hit dropped the whole upper block |
| Sandbags on a background-bracing strut | always refused |
| Solid woodspam in front of weapons | the AI stopped firing them |
| Dropping a grid column for the whole map | the starting fort's lower nodes no longer snapped, plans broke |
| Two turbines per 100-wide roof cell | the second one `CS_OCCUPIED` |
| Heavy weapon directly on another weapon cell | floor sagged 24–49, `CS_UNSTABLE`, given up |
| Rule check "no device on a strut sharing a node with a strut carrying a device" (from the probe) | flagged the game's own plans and devices that were built; only true for the finished, loaded fort; not in `rules.py` |
| Door or armour planned a few actions after its strut | no effect while the strut was under construction (a 20mm could not fire); now `SWAP_WINDOW` |
| Overlap check using the table widths as full widths | passed Vanilla-5's upgrade centre 155 from the factory (they need 180); refused in the game. Now half-widths |
| Line-of-fire check assuming the recession box runs from the weapon to 200 ahead | missed the post 50 in front of the Vanilla-5 laser (outside its body, before its box); the laser never fired. Now the boxes and bodies from the weapon files |

## Open problems

- What exactly makes the game refuse a device with `CS_UNSTABLE` is not known: deterministic, independent of weight,
  more likely for a device added late next to loaded devices or on a sagging or tilted strut; neither shape, movement
  nor strut stress alone explains it.
