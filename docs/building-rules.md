# FORT 9000 – Fort building rules (lessons learned)

Everything below was learned from the game files and from test matches against the AI (Vanilla, weapon_pack,
difficulty 0.5–1, October 2026). The generator follows these rules; `tools/fortgen/rules.py` checks them
(see "Validation"). When a rule changes, update this section, the generator and `rules.py` together.

## Game mechanics (facts)

**Materials** (`data/materials/building_materials.lua`)

| Material | Stiffness | Mass/length | Breaks below / above | Hit points | Notes |
|---|---|---|---|---|---|
| `bracing` (foreground wood) | 200000 | 0.25 | 0.90 / 1.10 | 150 | stops most shots and the wind; a device built on it turns it into background bracing |
| `backbracing` (background wood) | 200000 | 0.25 | 0.92 / 1.08 | 100 | **cannot carry devices** (`SupportsDevices = false`); most projectiles pass through it (not laser, buzzsaw, howitzer); burns |
| `armour` / `door` | 250000 | 0.5 | 0.90 / 1.10 | 400 | armour in a weapon's way is turned into a door when the weapon is placed |

- Minimum strut length 37.5 (doors 49). A new node may be at most 150 from the node it is built from
  (`StandardMaxLength`); struts between existing nodes may be up to 218 (`StandardMaxLinkLength`; the
  generator uses up to 205).
- Woodspam struts therefore cannot be closer than about 40.

**Devices** (selection box from the game files, weight). The game files give `SelectionWidth`/`SelectionHeight`
as half-extents around a centre `SelectionOffset` = (0, -SelectionHeight - 0.5): a device's box reaches
**2 × SelectionHeight above its strut** (`rules.BOX_TOP`): machine gun 81, sniper 91, mortar 61, laser 101,
20mm cannon 111, rocket/EMP rocket 112, flak/shotgun 118, cannon 121, turbine 127, munitions plant/armoury 170
(smoke bomb: packed, assumed 127). The overlap checks below still use the values as full widths.

| Device | Width × height (game values) | Mass |
|---|---|---|
| machine gun, minigun | 40 × 40 | 40 |
| sniper, AP sniper | 70 × 45 | 40 |
| mortar, heavy mortar | 40 × 30 | 60 |
| cannon | 95 × 60 | 120 |
| 20mm cannon (weapon_pack) | 90 × 55 | 100 |
| laser | 50 × 50 | 100 |
| turbine | 40 × 63 (but needs ~100 spacing) | 70 |
| battery / store | 40 × 40 | 40 / 60 |
| workshop / factory / upgrade centre | 90 × 45 | 100 |
| munitions plant / armoury (weapon_pack) | 45 × 85 | 120 |
| sandbags | 40 × 25 | 45 |
| flak, shotgun (weapon_pack) | 40 × 58.75 | |
| EMP rocket, rocket (weapon_pack) | 40 × 55.75 | |

- `weapon_pack` is always installed: cannon and 20mm cannon need the **munitions plant** (needs workshop or
  armoury; costs 800 metal and **5000 energy**); laser and firebeam need the factory. The laser also needs an
  extra store and battery and a lot of energy per shot.
- **One device per strut**: the game (and the player) cannot place a second device on a strut that carries one,
  however short the devices are (test match 25.10.2026: sandbags at LinkT 0.8 beside a mortar planned at 0.3 took
  the strut, the mortar was never placed). The game's own Abyss-1 sells its sandbags (`DESTROY_DEVICE`) before it
  puts a laser on their strut. `split_edges` builds a strut in two halves for two devices.
- **Mortar spacing**: two mortars 77 apart (on the two halves of a split strut) - the second was refused in two
  test matches (`CS_UNSTABLE`, later `CS_OCCUPIED`); the game's own plans space them 91-122 apart. Sandbags 70 from
  a mortar at the same height were refused too (`CS_OBSTRUCTION`), 89 away they were placed: devices at the same
  height need about 90 between them.

**Economy** (`devices/device_list.lua`, weapon_pack, the `SNAP` lines of test matches 24.10.2026)
- Start: 601 metal, 3004 energy. Reactor and the two starting mines: +13 metal/s (reactor 5, mine 4 each) and
  about +100 energy/s; every further mine +4 metal/s and -5 energy/s; a roof turbine up to +45 energy/s.
- Storage: 600 metal + 300 per store, 3000 energy + 2000 per battery (900 / 5000 at the start).
- Costs (metal / energy / build time): mine 300 / 2000 / 30 s, turbine 200 / 800 / 20 s, battery 150 / 625 / 16 s,
  store 200 / 500 / 16 s, workshop 400 / 2000 / 60 s, munitions plant 800 / 5000 / 90 s, 20mm 600 / 4000 / 70 s,
  one 20mm burst 40 / 2000 (reload 28.8 s). Struts per unit length: wood 0.1 metal / 0.5 energy, armour
  1.8 / 1.5, door 2 / 2; selling refunds wood 0.025, armour 0.9, door 1.0 metal per length.
- Costs are paid when a device is placed, and the build times hold exactly (munitions plant placed at 65 s,
  built at 155 s; 20mm placed at 158 s, built at 228 s). The AI moves on to its next action once a device is
  placed, not when it is finished.
- The tech chain workshop -> munitions plant -> 20mm takes 60 + 90 + 70 s; the starting economy pays for it on
  time if nothing else comes first (the munitions plant needs the whole 5000 energy cap). A mine at the start
  delays the workshop (its 2000 energy); with both near mines first, metal was plentiful but energy stayed at
  200-600, so the tower (and the first roof turbine) came no earlier.

**Lines of fire**
- Every direct-fire weapon needs a clear line straight ahead (`MinFireClearance` 500–1000). Foreground struts
  in that line stop the AI from firing (test match: woodspam built after the cannon → 0 cannon shots, sniper
  shots dropped to 0 once the woodspam stood).
- When a weapon is placed, the game **recesses** foreground struts that already stand in its way within its
  `RecessionBox` (a band 200 long and only 25 high at barrel height, ahead of the weapon; machine gun only 20): bracing becomes background bracing, armour becomes a
  door. Struts built **after** the weapon, or further away, are not recessed and block it.
- Doors never block: the AI opens all doors in the way before firing (`OpenWeaponDoors`) and closes them
  afterwards. Every direct-fire weapon gets a metal door in front of it.
- **Small doors**: a door opens and closes at `DoorSpeed` 50 per second (`building_materials.lua`), so a 100-long door
  stands open ~2 s per shot, long enough for the player to snipe through it; `MinLength` 49. Only the part the shot
  passes needs to be a door: the game wants a clear corridor around the shot, ~20 to each side at the muzzle widening
  to 40 at 1000 (`FireClearanceOffsetInner/Outer`); the sniper's barrel is ~50 above its strut and 100 long, and its
  `RecessionBox` (200 x 25) starts 200 ahead, so a door closer than that must be planned. Vanilla-2 (first try):
  the sniper's door post is split (`split_edges` with `materials`): door from the strut up to y 142.5 (61.5 long,
  ~1.2 s), armour above it (37.5); the sniper moved forward on its strut (LinkT 0.7, `weapon_cells` takes a LinkT) so
  its muzzle is ~44 instead of ~74 behind the door. Test match 25.10.2026: the sniper was placed at its new
  position without errors and fired 124 shots, no clearance failures (`FIREWAIT`/`FIRETRY`): the armour above the
  door did not get in the way. Vanilla-3/-4/-5 (`split_doors`, a final pass over the plan): the front post of a
  sniper, cannon, 20mm cannon or laser is rebuilt in up to three pieces (armour, door, armour) through new nodes,
  braced with background bracing to the cell's back corners; the door is the shortest that covers the shot. Where the
  barrel is, is not certain: the door covers both the weapon file's `RecessionBox` height (machine gun 40, sniper 50,
  20mm cannon and laser 60, cannon 70 above the strut) and `rules.py`'s muzzle (0.6 of the device's height), +-12.5
  (the Vanilla-2 margin) plus ~5 degrees of aim per unit of distance beyond a muzzle 44 behind the door. Result:
  Vanilla-3 20mm doors 78 instead of 125, its sniper's door 62.5 instead of 125; the cannons (Vanilla-4) and the laser
  (Vanilla-5) keep their full doors, no split is shorter for both estimates. A new node needs a brace that does not
  pass through the box of a device in that cell (test match 25.10.2026, Vanilla-3: a brace through the sniper's spot,
  the sniper was refused, `CS_OCCUPIED` then `CS_UNSTABLE`, until the AI gave up); without one the door is not split
  (a lone node would be a hinge in a post that carries the storeys above). So Vanilla-3's sniper stands at LinkT 0.28
  (`sniper_t`), where the brace to the cell's top corner clears it; in the 100-high storeys of Vanilla-4/-5 no brace
  clears the sniper and its door stays full. Test match 25.10.2026 (Vanilla-3, aborted at 680 s): the 20mm cannons
  fired 126 shots through their 78-long doors. Machine guns
  keep full doors: they only fire anti-air here, at steep angles. Not yet tested in a match.
- The built-in AI only fires at a target whose ray from the weapon reaches an enemy device or structure
  (`FindTarget` -> `TargetObstructed`, flag `RAY_ALLIED_BG_BLOCKS`); otherwise `TryFireGun` declines without an
  error (`FIRETRY ... fired=0`, [ai.md](ai.md#fire-control)). A door that is still a wood post blocks: in two rush tests the finished 20mm
  did not fire for 2-3 minutes and fired 11 s after the post in front of it became a door. The 20mm may fire
  alone (grouping affinity `alone` = 1).
- Mortars fire steeply up and forward: the roof above them must be a door (or open) and no other part of the
  fort may stand in that arc (test match: a mortar beside the weapon tower).

**Wind:** the game tests the wind with rays from each turbine to both sides, from 25 to 600 away and within ±10°
(`devices/windturbine.lua`: `MinTestDistance`, `MaxTestDistance`, `MinWindAngle`/`MaxWindAngle`). Every material
except background bracing, shields, rope and fuse collides with the wind (`CollidesWithWind = false`); with wind
from one side only the turbine falls back to a lower minimum efficiency (`MinWindNoCrossFlow` 0.3 vs.
`MinWindCrossFlow` 0.35; the exact formula is not known). Consequence: a turbine needs open air 600 to both sides
at its own height, so a turbine beside a taller solid tower gets no wind from that side, however far back it
stands (test match: turbines inside a storey with solid posts produced almost nothing, energy stayed at
170–300; the player noticed little energy from the turbines on the back block's roof beside the tower).
Two turbines 46–54 apart on one strut failed with `CS_OCCUPIED`; the game's own plan spaces them ~100 apart.

**`CS_UNSTABLE`** (the game refuses a device; there is no flag to skip the check)
- Light devices (machine gun, turbine) usually succeed on a later try; heavy ones (laser, cannon, 20mm cannon,
  store) failed persistently. The `UNSTABLE` log line ([debugging.md](debugging.md)) showed: struts at the device stretched 4–7 %
  (still below their breaking limit) with the structure sagging 13–27, or the structure moving (speed 5–18)
  while under fire. The game seems to refuse heavy devices where the support is weak, well before anything
  breaks.
- Weak support that caused it: a wall standing mid-span on a straight beam (the starting fort's roof beam over
  the reactor); storeys resting on an open storey of background posts; the long floor beam of a high, narrow
  top storey.
- What worked: weapon column on the starting fort's own posts (like the game's Template-1, one 155-wide cell,
  no node mid-span), solid X-braced storeys below heavy weapons, heavy weapons near the back post
  (`LinkT` ~0.2, Template-1 uses 0.16). The cannon was then placed and fired; the 20mm cannon in the high top
  storey still failed.
- A heavy weapon on top of another weapon cell fails: a weapon cell's diagonals are background bracing (lines of
  fire), so the floor above it sags (test match, Vanilla-3: 20mm cannon in the top storey sagged 24–38, most
  stretched link the background diagonal of the 20mm cell below; the 20mm one storey lower was placed and
  fired 63 shots). Heavy weapons therefore stay out of the top storey. In a second match the 20mm one storey
  lower, again directly on the other 20mm's cell, failed the same way under fire (sag 38–49, moving).
- Background bracing is exactly as stiff and heavy as foreground bracing (it inherits `Bracing`); it only breaks
  sooner (0.92 / 1.08 instead of 0.90 / 1.10), so in a sagging weapon cell its diagonal is the first link near
  its limit (1.06 in the first match). Inside a weapon cell no solid strut is possible: the weapons aim over a
  wide range (cannon -20..30 degrees, 20mm -40..40). Putting the upper heavy weapon on solid cells one column
  back (stepped tower) did not help: there even a sniper and a correctly shaped cannon cell got `CS_UNSTABLE`
  (see "Approaches that failed").
- Probe runs ([debugging.md](debugging.md), [history/probe-runs.md](history/probe-runs.md), three runs on the finished Vanilla-3 fort, identical results): the check is deterministic and
  does not depend on the device's weight (sniper and 20mm cannon got the same result on 51 of 54 struts).
  Adding a device to the finished, loaded fort: refused on 80 of 84 attempts on a strut sharing a node with a
  strut that carries a device, against 38 of 144 without; the rest on sagging or tilted struts (best single
  split: sag > 40, 85 %). This is not a rule for plans: built together in plan order, devices on struts sharing
  a node are fine (the game's own plans; two turbines on one node in that match).
- Late devices in a finished tower fail where early ones on a light structure worked: the sniper on the tower's
  top front cell was placed at once on the lone front column, but refused (strain only up to 1.02) once the
  whole tower stood below it (storey-by-storey order); the roof turbine on the seam column x -3300..-3200 was
  refused in every test; the munitions plant on the bottom floor right behind the starting fort, beside the
  workshop, was refused with no stress and no sag.
- A heavy weapon's body sits 18 in front of its LinkT point (`SelectionOffset` -18 in the weapon's own frame,
  which faces left, mirrored for team 1); the laser is centred. At the generator's LinkT values the body stays
  inside its own cell, so the cell behind it needs no background bracing.

**Other build errors:** `CS_OCCUPIED` (spot taken: starting fort devices, debris, devices too close; on the first
attempt of a device it is common and harmless, the next attempt places it), `CS_OBSTRUCTION` (something in the
way; a roof turbine got it once and was placed shortly after), `CS_NODESTOOFAR` / `CS_NODESTOOCLOSE` (length
limits; for a device, `CS_NODESTOOCLOSE` meant in every probe attempt that the strut already carries a device),
`CS_INVALIDNODES` (a device on a strut of 30 degrees or more), `CS_PREQUISITENOTMET` (tech missing, e.g. cannon
without munitions plant).

**Changing a strut's material:** a `CREATE_LINK` with another material on an existing strut swaps it (selling the
old one: armour -> wood brings back 0.9 metal per length), but only once the strut is finished. On a strut still
under construction (5 s and more) it has no effect and the AI moves on without an error; its rebuild pass
corrects the material only after the plan is finished. In a Vanilla-3 test, no door and only 2 armour struts
planned right after their posts were built before the plan was done (422 s); the swaps of the old
starting-fort armour at the start worked within 5 s.

**Defence: hiding, sandbags, doors, spacing** (test matches 25.10.2026 against a player, Vanilla-2 rush; game files)
- **Background bracing hides**: the player cannot see devices behind or inside it, and projectiles, mortar shells and
  the wind pass through it; it cannot carry a device. The built-in AI checks only the terrain before firing a lobbed
  weapon (`TargetObstructed`), so mortars fire from inside a nest of background bracing (41 shots in one match).
  Direct-fire weapons fire through their own background diagonals too (sniper: 124 shots).
- **Sandbags** (0 metal / 300 energy, 30 s, box 51 high) shield what cannot shoot back (mortars, turbines) from
  sniper fire. Two stacked ones need a cell split at half height (`split_cell`) with at least 51 per half: in a
  100-high cell the upper ones were refused (`CS_OBSTRUCTION`, then `CS_UNSTABLE`), in 125-130-high cells both were
  placed. A 155-wide cell can be at most 130 high (its diagonal must stay within `MAX_LINK` 205; at 135 the cell
  was dropped).
- **One device per strut**, and **~90 between devices at the same height**: a mortar 77 from another mortar and
  sandbags 70 from a mortar were refused (`CS_UNSTABLE`/`CS_OBSTRUCTION`, later `CS_OCCUPIED`); 89-127 apart they were
  placed (the game's own plans: mortars 91-122 apart). `rules.py` checks both (mortars and turbines). Two devices
  on one 155-wide cell floor need a split floor (`split_edges`, braced to the cell below).
- **A device's body turns the solid struts it overlaps into background bracing**: the sniper's body over the post in
  front of it made that post background, so it fired through it.
- **Doors**: open and close at `DoorSpeed` 50 per second (a 125-long door ~2.5 s), the player snipes in meanwhile;
  `MinLength` 49. Barrel heights above the strut (`RecessionBox` offset of the weapon files): machine gun/minigun 40,
  sniper 50, 20mm cannon and laser 60, cannon 70; barrel length 60 (machine gun), 100 (sniper, cannons), 58
  (laser). The game wants a clear corridor around the shot (`FireClearanceOffsetInner` 20 at the muzzle to
  `FireClearanceOffsetOuter` 40 at 1000); the `RecessionBox` (200 x 25) starts 200 ahead (sniper, cannons), so a
  door closer than that must be planned. A door cut to the shot works: the Vanilla-2 sniper's 61.5-long door (instead
  of 99, muzzle 44 behind it) fired 124 shots without clearance failures (`split_doors`, [generator.md](generator.md)).
- **Energy**: a strut costs 0.5 energy per unit length, so building the tower uses ~60 energy per second; a mortar
  shot costs 200 (reload 9 s: two mortars up to ~44 per second); a mine costs 2000. A turbine yields up to 45, an
  upgraded one 67.5 (upgrade 200 metal / 1000 energy). The roof turbines of a five-storey storey-by-storey tower
  came after ~160 struts (the storeys above the second wait for the first two over the full width, which pulls in
  the whole back block) and energy ran down to 2-20 between mortar shots; turbines on the floor of the second storey
  (Vanilla-2's gallery) came after ~92 struts and energy then stayed at 1500-7500.
- **Upgrades** need the upgrade centre *finished*; the AI waits on a planned upgrade (a test match: 52 s with only a
  battery in between). It upgrades whatever device stands on the planned strut (`GetDeviceIdOnPlatform`), also one of
  the starting fort.
- **Selling** (`DESTROY_DEVICE`, as the game's Abyss-1 sells sandbags before putting a laser on their strut; plan
  step `sell:<device>` for `orig_devices`): the mod's `DestroyDevice` wrapper tries both node orders, then the own
  device on that platform, then the one closest to the strut ([debugging.md](debugging.md)). The starting fort's machine gun stands on its
  lower front (-2996,504)-(-2895,505), not on the prow (a planned sale from the wrong position failed three times).
- **Woodspam is foreground wood**: within a turbine's wind rays (+-10 degrees, 600) it blocks them (in front of the
  Vanilla-2 gallery: 0% of the front-side rays clear), so it stays out of the turbines' height band.
- **Background bracing does not stop projectiles**: hidden devices are still hit by fire that passes through it
  (two mortars destroyed by machine-gun fire before their sandbags stood); sandbags (or solid struts) must stand
  before the device they shield.
- **A laser beam cuts through an unprotected wall in seconds**: the starting fort's lower front (x -2900, y
  411..700) is the AI's weak spot (lost at 451-453 s to one beam); layers of woodspam in front of it buy time.

## Design rules (enforced by the generator for Vanilla)

1. **No overhang:** every cell needs support (both bottom corners on the starting fort, a foundation or a
   supported cell, or a short bridge). Nothing beyond the cliff except the starting fort's prow.
2. **Supports first:** a cell's supports are built before the cell (a battery cell hung sideways off the
   starting fort before its column existed and the fort collapsed after 2 minutes).
3. **Bottom up, X-braced:** cells are built from the bottom up and crossbraced; the lower storeys and the weapon
   column at once, the rest in a final pass so weapons are not delayed. The tower rises **storey by storey**
   (`tower_connect`): its back part (on the back block) and front part (on the starting fort) are joined over two
   storeys before anything higher is built, and neither rises more than two storeys above the joined part.
4. **Opening by the economy numbers** (above): Vanilla-3 rushes the 20mm (armour layer in front of the reactor
   sold, workshop, munitions plant, a mine and a battery while it builds, the 20mm; first shot ~230 s instead of
   445-480 s); Vanilla-2 rushes the sniper and two mortars (workshop, the sniper, the deck and the nest's sandbags while
   it builds, then the mortars in the hidden nest, then all three mines; it keeps the inner armour in front of the reactor); Vanilla-5 rushes the laser (workshop, a battery, the factory, a
   store and a mine while it builds, the laser; the factory and the laser each cost 6000 energy, more than the starting
   cap, the laser 1000 metal, more than the metal cap). Vanilla-4 opens with the mine under the starting fort, the workshop (on the
   starting fort), the first roof turbine, the anti-air machine gun, then the second mine (both mines first left
   energy short). Roof turbines need the tower below them, so they cannot come first; no mine before a rush's
   workshop.
   **Tech early, then something else:** the AI waits on a device until its tech is *finished* (workshop,
   upgrade centre, factory 60 s; munitions plant ~90 s), without an error. Build the tech early and put devices
   that do not need it (store, battery, machine gun, sniper, woodspam) between the tech and the devices that
   do (test matches 24.10.2026: with the cannon right after the munitions plant the AI waited ~1.5 min, part
   of it with metal and energy at the storage cap; Vanilla-4 now has 26 plan actions in between). The rush in Vanilla-3 is the exception: there the munitions plant follows the workshop directly, since the starting economy affords nothing else before it, and the cannon's cell, a mine and a battery fill its 90 s.
5. **Turbines on an open roof or in a hidden cage** with nothing resting on them and ~100 apart, at least as high as every solid part
   of the fort within 600 to both sides (Vanilla: the tower roof; the cage of rule 13 is background bracing, which the wind passes); never inside a storey with solid posts, and never as the floor that carries the weapons (an open turbine storey under the weapon tower was
   the breaking point: one hit dropped the whole upper block).
6. **Weapons:** direct-fire weapons at the front behind a door; struts in their line of fire are background
   bracing (or built before the weapon within its recession box); heavy weapons in solid, X-braced storeys on
   strong posts, never in the top storey of the tower; mortars on top with a door roof and an open arc (Vanilla-2:
   in a low nest of background bracing with sandbags in front of each mortar, hidden from the enemy, for its rush).
   Two heavy weapons: behind open front cells (fire lanes, as in weapon_pack's ToGWM2), one above the other in
   x -3200..-3100 at LinkT 0.5, in 125-high storeys so the lower one does not reach the floor above (the game
   turns struts a device overlaps into background bracing, which cannot carry a device); built and fired in
   both test matches (Vanilla-3, -4; Vanilla-3's rush puts them on floors 105 and -20, Vanilla-4's on -20 and
   -145). Stacked in the weapon column with 100-high storeys, the upper one failed. Cells where a device type
   failed in every test are left to other devices (`weapon_avoid`, `turbine_avoid`).
7. **Woodspam:** cheap wooden layers in front of the weapons; background bracing where it is in a line of fire
   or next to turbines, foreground bracing only where it just protects (e.g. in front of a mortar storey); never
   within a turbine's wind rays (Vanilla-2: below the deck, in front of the reactor).
8. **Devices only on solid bracing** (never on background bracing); batteries and stores on proven slots, not
   on the ground row; no strut lying on a mine site.
9. **No metal roof** (heavy); armour only where something must be protected.
10. **Keep the AI busy:** the plan ends with a late-game block (more anti-air, weapons, upgrades, storage), so
    the AI does not sit idle at the storage cap.
11. **Short node chains:** every new node is built from the built neighbour with the shortest chain to an
    anchor (a starting fort node or a foundation on the ground), then from the node directly below (a vertical
    post), then the nearest one, within 150 (`ensure_node`, `chain`). This keeps the AI's relative node
    placement from copying a lean sideways through the fort. Vanilla chains went from max 16-17 / avg 6.4-7.9
    to max 10 / avg 3.6-3.8 (10 = a column from the ground to the tower roof), Abyss from max 10 / avg 3.9-4.8
    to max 5-6 / avg 2.4-2.9; in the (failed) stepped tower the cannon cells then hung 2-3 creations from the
    starting fort's roof post instead of 15-17 from the back column, and kept their shape. `gen_fort.py` prints the chain lengths of every plan
    (`rules.node_chains`). With `support_cheapest` (Vanilla-3) a cell rests on the support with the fewest cells
    below it, so a column right behind the starting fort hangs on its back posts instead of pulling in the
    whole back block.
12. **Final material at once:** a strut is placed with its final material (door, armour, background bracing)
    when the plan would change it within `SWAP_WINDOW` (20) actions; a swap on a strut under construction has
    no effect (see "Changing a strut's material").
13. **Hide and shield what cannot shoot back** (facts above): mortars and turbines stand in a storey of background
    bracing (`hidden_box`; Vanilla-2: the mortar nest and the turbine gallery on the deck; Vanilla-3/-4/-5: a turbine
    cage on the tower roof), 130 high, each row with two stacked sandbags in its front cell (`split_cell`,
    `sandbag_slots`), right after its first device; every device on its own strut, ~90 from its neighbours at the same
    height; the cage storey is left out of `tower_connect` (`skip_floors`), so the first turbine is not delayed.
    Weapon doors only as long as the shot needs (`split_doors`; machine guns keep full doors, they fire anti-air at
    steep angles). Upgrades after the upgrade centre with devices that need no tech in between.

## Validation (`tools/fortgen/rules.py`)

`python tools/fortgen/rules.py <plan.lua> ...` checks any plan file; `gen_fort.py` runs the same checks on every
plan it writes (`RULE ERROR` / `RULE WARN`) in addition to `validate()` (rock, lengths, build order, supports,
prerequisites). Checked:
- strut length (37.5, doors 49);
- device on background bracing (warning: the game's Template-1 records one);
- line of fire of direct-fire weapons and the arc of mortars: no foreground strut that is built after the
  weapon or lies beyond its recession box (doors are fine);
- turbine wind with the game's ray test (`wind_rays`: a side is open when at least half of its rays are clear;
  error if both sides are blocked, warning if one is) and turbine spacing (≥ 90);
- two devices on one strut (one device per strut; a `DESTROY_DEVICE` frees the strut), or devices side by side on
  neighbouring struts at the same height that overlap (a wide device near a strut end reaches over the shared node;
  widths from the table above);
- mortars at the same height closer than 90 (`MORTAR_SPACING`);
- struts lying on a mine site;
- a solid strut inside a device's box above its strut (`BOX_TOP`, the posts at the ends of its own strut excluded):
  error for tall devices (rockets, flak, shotgun, smoke bomb), warning for the others (the munitions plant, 170
  high, stood in 100-high storeys in test matches). Warnings on the current plans: the tech slots of the game's
  own plans (upgrade, factory, munitions), Abyss-4's top cannon
  (121 high in the 100-high top storey, the armour roof at y=-846 crosses its box).

The generator fixes lines of fire itself (`clear_fire_lines`: blocking struts become background bracing,
armour becomes a door) and only places mortars where the arc is open (`mortar_open_arc`). All current Abyss,
Vanilla and VanillaLong plans pass without errors (warnings: only the box heights above). On the command line `rules.py` takes the enemy side
from the plan header (team 2 plans such as VanillaLong face the enemy on the left) and ignores the terrain;
`check_plan(..., terrain=...)` also lets rock block the wind rays. With terrain, every turbine on Abyss's top roof
(next to the cliff wall) gets no wind from the left; the game's own Abyss-1 puts its turbines on the same spots,
weapon_pack's ToGA1 puts some far out on the right instead (open on both sides).

## Approaches that failed (do not repeat)

| Approach | What happened |
|---|---|
| Cells hanging sideways before their support existed | collapse after 2 min |
| Laser plan with 2–3 turbines | laser never placed or never fired (energy 170–1500) |
| Turbines in a storey with solid posts | almost no energy |
| Open turbine storey (background posts) carrying the weapon tower | heavy weapons `CS_UNSTABLE`; one hit dropped the whole upper block |
| Lighter upper block (fewer storeys, single diagonals) on that storey | heavy weapons still `CS_UNSTABLE` |
| Sandbags on a background-bracing strut | always refused (background bracing cannot carry devices) |
| Solid woodspam in front of weapons | the AI stopped firing them |
| Dropping a grid column for the whole map | the starting fort's lower nodes no longer snapped, plans broke |
| Two turbines per 100-wide roof cell | the second one `CS_OCCUPIED` |
| Heavy weapon directly on another weapon cell (top storey, and one storey lower under fire) | floor sagged 24–49, `CS_UNSTABLE`, given up |
| Rule check "no device on a strut that shares a node with a strut carrying a device" (from the probe, 24.10.2026) | flagged the game's own plans (Template-1/-2, Abyss-1) and devices that were built in the test match; only true for devices added to the finished, loaded fort. Not in `rules.py` |
| Door or armour planned a few actions after its strut (all plans until 24.10.2026) | the swap had no effect while the strut was under construction; the post in front of the rush 20mm stayed wood until the plan was finished and kept it from firing. Now `SWAP_WINDOW` |

## Open problems

  - What exactly makes the game refuse a device with `CS_UNSTABLE` is still not known. Known so far (facts
    above): deterministic, independent of the device's weight, more likely for a device added late next to
    loaded devices or on a sagging or tilted strut; neither shape, movement nor strut stress alone explains it.
