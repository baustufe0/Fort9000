# Bastion – implementation plan (branch `bastion`)

A new Vanilla fort (`fort-t1f1-Vanilla-8.lua`; the number 7 belonged to a removed recorded fort) that puts pressure on the player early and reacts to what they do:
a fixed skeleton with independent weapon **sockets**, reinforcement **zones** and a sacrificial **crumple zone** in
front, driven by a **posture engine** that keeps re-deciding which socket variant and which zone reinforcement goes in.
Everything stays pre-generated and checked by `rules.py` (free placement at runtime stays rejected, [ai.md](ai.md#reactive-build-modules)).

Testing happens with the DEV mod (`mods/fort9000dev/`, this branch). `mods/fort9000/` and `main` stay unchanged until
the branch is merged and published.

## Goals and acceptance

| Goal | Measured by |
|---|---|
| First shot early | first own `sniper` shot in the log ≤ 45 s (Vanilla, normal tempo) |
| Pressure | enemy devices destroyed in the first 180 s ≥ Vanilla-6's average over the archived matches |
| Stable | no CS_UNSTABLE, `physics.py check` passes the plan and every module after its `Requires` |
| Protected | every weapon in a closed cell with doors, tech hidden, turbines in their own storey (existing rules) |
| Reactive | each posture shows up in the log against a player who uses that weapon (`POSTURE ...`) |
| Better | at least 10 Vanilla matches; win rate and survival time ≥ Vanilla-6 |

## Step 0: verify open engine questions (before building on them)

1. `CREATE_LINK` on a link that already exists: success, error code, or a duplicate? (modules shared struts)
2. `DestroyDeviceById` on an own device: does it refund metal like selling? Otherwise swaps use `DESTROY_DEVICE`
   plan actions (the sell the plans already use for the starting MG) or only refill empty sockets.
3. `OnLinkHit` arguments and how often it fires per projectile (cost of the zone hit map per think step).
4. Repeated `CAI_InsertActions` at the same `data.fortIndex` keeps `data.Rebuild`, `data.Devices` consistent.

Done when: each answer is written into [forts-api.md](forts-api.md) "Notes for this mod" and a Lua test covers 4.

**Results (03.11.2026, from the game's AI source and the API reference; details in forts-api.md):**

1. Same material: the action passes without cost, modules may share plan struts. Different material on an existing
   strut: open, needs a match. Until then zone reinforcements add new struts instead of changing materials.
2. `DestroyDeviceById` is the reclaim (salvage), already used by `DESTROY_DEVICE`. Swaps can be module actions of
   type `DESTROY_DEVICE` followed by the new device. Refund amount: open, needs a match (metal before/after in the log).
3. `OnLinkHit` only sees projectile hits on struts, no beams and no splash. The zone hit map therefore uses
   `OnLinkHit` (damage) **plus** `OnLinkDestroyed` (any cause) **plus** `OnDeviceHit`. Whether `OnLinkHit` reaches
   the AI environment: open, needs a match.
4. `t_insert_repeat.lua`: five modules inserted on five think steps, three at the same build index, then two more two
   actions further: `data.Rebuild`, `data.Frustration`, `data.Devices` and the rebuild clocks all stay on their actions.
   Finding: a module that fires while another is still being built goes **in front of the rest of it** (later modules
   first, the earlier one is split). Harmless while every socket module only uses its own cell; step 2 decides
   whether inserts should wait for the end of the module being built.

**Probe match (03.11.2026, Vanilla, AI on Vanilla-5, `FortPlanConfig.EngineProbe`):**

1. Different material: `CreateLink` replaces it at once (`CS_SUCCESS`, armour, 199 metal in the same frame). Zone
   reinforcements may upgrade existing struts (bracing → armour) as plain `CREATE_LINK` actions, no new struts needed.
2. Reclaim: 50 % refund (37.5 of 75 for a machine gun), arriving after about 5 s. A swap costs half the old weapon
   plus the new one and leaves the socket empty for about 5 s. So swaps only when a socket keeps losing its weapon
   or the posture holds a long time, never for short threat spikes.
3. `OnLinkHit` reaches the AI, including the AI's own projectiles (its EMP rocket hit its own door): filter on the
   enemy team. Enemy hits are still untested (the player did not fire); the first real Bastion match will show them.

Side finding: on Vanilla-5 an own EMP rocket hit an own door (struts 92-95), a line-of-fire problem of that plan.

Step 0 is done; the probe switch in `ai/fortplans.lua` comes out before the merge.

## Step 1: generator – sockets and zones

In `gen_fort.py`, a new variant `Vanilla-8` (`VANILLA_VARIANTS["bastion"]`), its own layout, not derived from Vanilla-2/6:

- **Skeleton:** wide, low; front-weight hub with background spokes in the lower front storeys
  ([[front-weight-fortification]]); tech hidden at the back, turbine storey of its own.
- **Sockets:** named closed cells (`A1..A3`, `B1..B3` direct, `M1`, `M2` lobbed under door roofs), each with 2–3
  doors in series toward the enemy. Built empty with the existing `("build", [(x, y)])` slot step.
- **Socket variants:** for each socket one module per loadout (e.g. `B2.sniper`, `B2.mg`, `B2.cannon`, `B2.armour`).
  Each touches only its own cell, so it is checked once against the plan after its `Requires`, no combinations.
- **Zones:** `Z0` crumple zone (wood lattice with its own foundations, a gap to the core, no load on the core),
  `Z1..Z3` core sections with a reinforcement module each (extra bracing, second armour/door layer, sandbags).
- **Opening order:** skeleton of B1/B2 → two snipers → economy → M1 mortar (~60–90 s) → the rest of the skeleton
  as time-triggered modules.
- Module metadata for the AI: `Socket = "B2"`, `Zone = "Z1"`, `Repeat = true`, `Cooldown = s`,
  `Variant = "sniper"`. Zone membership of each plan link (by position) written as `FortZones` in the plan file.

Done when: `gen_fort.py` writes Vanilla-8, `rules.py` and `physics.py check` pass, `render_all.py` image reviewed.

**Result (03.11.2026):** `fortplans/Vanilla/fort-t1f1-Vanilla-8.lua`, picture `maps/vanilla-8-bastion.png`
([maps/vanilla.md](maps/vanilla.md#vanilla-8--bastion)). 230 actions, `rules.py` 0 errors / 0 warnings (plan and
modules), `physics.py` WEAK (stands; max stress 0.46, the lowest of the Vanilla plans, sag 93). Deviations from the
sketch above, forced by the rules and the physics:
- One direct socket per storey (B1, B2), no A sockets behind them: a weapon behind another in its row is blocked
  ([[weapons-block-weapons]]), and the turbines need their own storey, so the stack is sockets, turbines, nest.
- The crumple zone Z0 is the existing woodspam (prow, lower face, mine row); the AI rebuilds shot-away struts anyway.
- Mortars come at plan action ~83 (not ~60-90 s): the nest is four storeys up and needs the back column x -3200..-3100
  from the ground (`build` step); built on the starting fort's back post alone it fell in `physics.py` (45-48 broke).
- Snipers stand at LinkT 0.18: a sniper's body with the barrel reaches ~120 ahead of its strut point, so 0.18 is the
  barrel at the front door. Their doors are split (~63 long) with one more door in front (`door_layers` 2).
Order: B1 sniper (action 21), workshop 28, three mines 29-31, B2 sniper 43, nest + back column, sandbags 90-91, first
turbine 92, woodspam, turbines, upgrade centre, eco. Modules: artillery (M1+M2, enemy mortars or 75 s), heavy
artillery (330 s), AP sniper in B1 (enemy AP sniper/laser/firebeam or 420 s). On this branch `ai/fortplans.lua`
forces Vanilla-8 on Vanilla (`Force`, remove before merge; publish.py refuses to publish with it).

## Step 2: AI – repeatable modules

In `ai/ai.lua`:

- `Repeat`/`Cooldown`: a module may fire again after its cooldown when its trigger still holds (today: once per match).
- Socket state: which variant a socket holds, which device id, losses in a window (from `OnDeviceDestroyed`).
- Swap: after N losses of a socket's weapon within the window, the next variant of that socket instead of the rebuild
  (extends `CAI_RebuildCapped`); a swap away from a live device only if step 0.2 allows a refund.
- Log: `MODULE <name> repeat=<n>`, `SOCKET <s> <old>-><new> why=<...>`.

Tests: `t_modules_repeat.lua`, `t_socket_swap.lua`.

**Result (03.11.2026):** done as described ([ai.md](ai.md#sockets-and-repeatable-modules-bastion)); one test file,
`t_sockets.lua` (199 checks pass). The generator checks each socket's loadouts with `rules.py` and tags every socket
device. Not yet in the game. As Vanilla-8 stands, a B socket can only swap to the machine gun: cannon20mm, laser and
firebeam need a munitions plant or factory the plan does not build; the posture engine (step 4) decides that tech.

## Step 3: AI – zone hit map

- `OnLinkHit` / `OnLinkDestroyed` for own links: damage per zone (`FortZones`), decayed like `st.threat`.
- Zone above a threshold → its reinforcement module (repeatable, cooldown). `Z0` gone → rebuild `Z0`.
- Log: `ZONE Z1 dmg=<n> -> reinforce`.

Test: `t_zones.lua`.

**Result (03.11.2026):** done ([ai.md](ai.md#zone-hit-map)); 206 checks pass. Vanilla-8 has two zone modules, both
for Z0 and checked with `rules.py` and `physics.py` (WEAK, max stress 0.63 with them): `Z0face`, a third woodspam
layer in front of the starting fort's lower face (x -2772, y 411..602, on the mine row's first layer; 300 damage,
3 repeats, 60 s cooldown), and `Z0prow`, a third layer in front of the prow below the deck (x -2725, y 205..310; 500).
Z1-Z4 are only measured and logged so far; their reinforcements come with the posture engine (step 4), which also
uses the zone pressure. The damage numbers (mortar 20 per hit, a lost strut 100) are first guesses from test 1.

## Step 4: AI – posture engine

Each think step: from enemy devices, `st.threat`, zone damage and socket losses pick one posture and map it to socket
variants and target values:

| Posture | Trigger | Effect |
|---|---|---|
| Pressure (default) | no clear threat | offensive variants, early target override: devices under construction, mines, turbines first |
| AntiArtillery | mortar threat | M sockets counter-battery, MG in A3/B3, roof zone reinforced |
| AntiSniper | sniper2, laser, firebeam | extra door module on hit sockets, own sniper, doors closed outside volleys |
| AntiAir | missiles, rockets | MG/flak in upper sockets (`AntiAirFirst`) |
| Siege | one zone heavily hit | reinforce that zone, rebuild Z0, firepower to other zones' sockets |
| Punish | enemy surplus / turtling | heavy variants in free sockets, target economy |

- Hysteresis (minimum time in a posture) so it does not flip every step; metal reserve for one socket + Z0.
- Reverting: when the threat's devices are gone (`st.kills`), sockets go back to the Pressure variants.
- Parameters in `Strategy.Posture` so `train.py` can tune them later.
- Log: `POSTURE <old>-><new> why=<...>`.

Test: `t_posture.lua` (scripted enemy device sets and hits → expected posture and modules).

**Result (03.11.2026):** done ([ai.md](ai.md#posture)); 213 checks pass. Effects so far: target boosts, preferred
loadouts for socket swaps, posture-triggered modules. Vanilla-8 got a `factory` module (Vanilla-5's slot in the back
block, hidden when placed) on Siege or Punish, at the latest at 450 s; with it a B socket that keeps losing its sniper
is rebuilt with a laser or firebeam. Not done: a proactive swap of a living weapon (reclaim) when a posture holds long,
and reinforcements for Z1-Z4. All scores and multipliers are first guesses, to be tuned from matches (`train.py`
could learn them later).

## Step 5: test matches and tuning

- `ai/fortplans.lua` on this branch: `Force = { Vanilla = "fort-t1f1-Vanilla-8.lua" }` so every DEV match tests it.
- Matches against mortar, sniper/laser, missile and turtle styles; evaluate with `train.py` and the log
  (`POSTURE`, `SOCKET`, `ZONE`, first-shot time).
- Afterwards: Vanilla-8 in the normal draw with the other plans, convert to VanillaLong (`mid_to_long.py`),
  then other maps.

**Test 1 (03.11.2026, Vanilla 1v1 vs the player, difficulty 1, ~395 s, aborted; EngineProbe still on):**
- The fort stood, every socket was filled; refusals only at first tries (sniper, workshop, mines, mortars, sandbags
  `CS_OCCUPIED` / `CS_OBSTRUCTION` once each, then built).
- Far too slow: first sniper built at 60 s, workshop 147 s, mines 140/163/182 s, second sniper 214 s, mortars
  263/269 s, first turbine 295 s. Metal stayed below ~250 the whole time (3.8 at ~40 s). Cause: the opening spends
  ~1120 metal on struts before the first sniper (Vanilla-2: ~460), mostly B1's door layer (armour arms 98 long to the
  prow node 58, ~470 m) and door, and the footing's armour (206 m); 4574 m of struts in all (Vanilla-2: 2625).
  The probe cost some too (MG reclaimed at 45 s, armour attempt refused for lack of metal).
- The snipers fired little: 41 of 57 tries declined, the ray hit the player's front doors and bracing (nothing in
  sight behind them). The mortars fired 12 times; their straight test ray hits the own nest floor (harmless for lobbed).
- Lost: a mortar at 274 s (rebuilt 319 s), the B2 sniper at 374 s.
- `OnLinkHit` sees the player's hits: mortar 20 damage each (12 hits), buzzsaw ~42 (9 hits); 7 own struts broken.

**After test 1:** the hub stays first, the footing's armour brace comes after the first sniper, the second doors
after the first turbine (`door_layers_late`, B1's layer 50 out instead of on the prow node), EngineProbe off. Strut
metal before the first sniper 1119 -> 402 (sniper at plan action 15), workshop 694, B2 1006; all struts 4574 -> 4371.
`physics.py` max stress 0.46 -> 0.63 (B1's door, which now carries its layer alone; still WEAK, i.e. stands).

**Test 2 (03.11.2026, Vanilla 1v1 vs the player, difficulty 1, lost at 635 s, reactor destroyed):**
- Opening faster than test 1 but still short of metal all match (mostly below 300): first sniper 32 s (60), workshop
  107 s (147), mines 100/123/145 s, B2 sniper 154 s (214), mortars 205/211 s (263), first turbine 218 s (295),
  heavy mortars 457 s, factory module at 450 s, built 572 s.
- Postures plausible: Pressure, AntiArtillery at 180 s (player mortars), AntiAir at 420 s (missile), back to
  AntiArtillery 450 s, Siege at 575 s (zone pressure). Zone modules fired: Z0face at 345 s (twice more), Z0prow 420 s.
- Socket swaps: B1 sniper -> machine gun at ~300 s (no factory yet), B2 sniper -> laser at ~610 s (Siege, factory).
- The AI destroyed only three snipers. Its mortars fired 24 times in ~430 s: 28 of 34 tries declined, the nest's
  front post is armour and stands in the shells' path (rule: a lobbed weapon gets a door roof and a front door).
- The player won with mortars and heavy mortars (66 shots), a missile and machine guns (259 shots). Bastion has no
  anti-air place: only the starting machine gun and B1's swapped machine gun; AntiArtillery could only re-rank targets.
- A machine gun in a B socket does not fire at the enemy fort (`NoOffence`): the swap gave up B1's offence.

**After test 2:** the nest's front post is a door (`lobbed_front_door`); socket A1, a closed cell behind the nest on
the turbine storey with a door roof (`door_roof_cells`), gets an anti-air machine gun from module `antiair` (enemy
mortars or missiles, posture AntiArtillery or AntiAir, at the latest 240 s; plan action ~154, its support comes from
the back column x -3300); a swap to a weapon that never fires at the enemy fort (the machine gun) only under AntiAir;
a swap's tech counts only when fully built (`IsDeviceFullyBuilt`). `physics.py` max stress 0.60; 216 checks pass.

**Test 3 (03.11.2026, Vanilla, AI vs AI, both on Vanilla-8, ~760 s, no side could kill the other):**
- Opening as in test 2: snipers 32 s, workshop 110 s, mines 105/126/146 s, mortars 195-205 s, first turbine 340 s
  (T1), anti-air machine gun (module `antiair`, enemy mortars) ~300 s, sniper2 and heavy mortars ~515 s, factory
  built 549 s (T1) / 658 s (T2).
- **The plan runs out:** from ~565 s the build index stands at the end (369/368, at 760 s 397/396 with the zone
  modules) and both sides sit at the cap, 900 metal / 9000 energy, for minutes. Nothing spends it: only rebuilds and
  repeated zone modules.
- **No laser or cannon:** a socket swaps only after two losses of its weapon. Both B1 snipers were lost twice before
  any factory existed ("no other loadout ready"), afterwards no socket lost its weapon. Cannon and 20mm need munitions,
  which no plan builds. There is no socket for a heavy weapon (`heavy=cannon:108` stands in the priority list all
  match).
- Postures: AntiArtillery at 175/185 s (the other side's mortars), T2 AntiSniper/Siege around 565-640 s. Z0face and
  Z0prow fired four and three times on each side.
- Fire: snipers and mortars against snipers and mortars behind armour and door layers; the AI destroyed 4 snipers,
  2 mortars and an anti-air machine gun of T2, T2 two heavy mortars and two snipers of T1. Neither reached a core.
- The FIRETRY ray of a mortar (a straight line to the reactor) hits the sandbag storey's background diagonal under
  the nest (-3040,-162): not a reason, the line is no shell path; the built-in AI declines for its own reasons.
- **Sniper doors too short (the user's observation):** the snipers hit only the enemy's lower storeys. `split_doors`
  cuts the door to the barrel ± 12.5 at the inner post (y 143..206 for B1); the second layer 50 ahead copies the same
  span. The sniper shell flies at 10000 with gravity 981: ~177 drop over the 6000 to the enemy fort, so the top of a
  fort (y -500 and higher) needs ~8-10° of elevation, ~30 above the barrel at the outer door.

**After test 3:** the B doors cover every direct loadout and rise at 9° from the weapon (`door_loadouts`,
`door_aim_up`; B1 inner 112.5..206.5 and outer 112.7..206.5, B2 -17.5..75 both, the outer doors tied); the factory
module at 330 s or after 15 s at 500 metal / 3500 energy (Surplus); a new module `munitions` after it (420 s or
Surplus) on the munitions slot x -3400..-3300 at 602, its cell's diagonal and the floor strut over it background
(`bg_diag_cells`, `bg_struts`); the direct loadouts also list the cannon (B2 only: in B1 the door reaches into its
body). Socket upgrade in the AI (the player: two snipers pay only early in the match): once rich (450 metal /
3000 energy for 15 s) and the tech stands, B2's sniper is sold and rebuilt as a laser (Prefer first, a mix across
sockets), B1's 60 s later (firebeam with the factory alone, 20mm with the munitions plant). Rules 0/0, `physics.py`
max stress 0.60; 222 checks pass.

**Test 4 (03.11.2026, Vanilla, AI vs AI, both on Vanilla-8, ~810 s):**
- Tech on time: factory 605 s (T1) / 609 s (T2), munitions plant 640 s / 494 s.
- T2 sold B2's sniper at ~530 s for a 20mm: the first try failed, it stood at 692 s. T2 sold B1's AP sniper at
  ~710 s for a laser, T1 sold B2's sniper at ~690 s for a laser, and T1's lost AP sniper in B1 was swapped to a laser:
  **no laser was ever built**, those sockets stayed empty to the end (T1 had no direct weapon left).
- Cause: the game takes the whole cost when a device is placed. A laser costs 1000 metal, the storage held 900 (T1)
  / 990 (T2). The game's "not enough resources" comes back as a code the mod logs as `CS_OCCUPIED` (62 times in the
  logs, never `INSUFFICIENTRESOURCES`): the 20mm (600) failed at 475 metal and went in when the metal was there.
- T1 lost two upgraded turbines at ~731 s, not rebuilt by 810 s: 12 actions in the rebuild queue at 50-600 metal
  (econ=poor), the empty lasers among them; energy stood at 9000 all the while.

**After test 4:** a weapon dearer than the storage (the highest metal / energy seen this match, less a margin;
`GetDeviceCost`) is never chosen, neither by an upgrade nor by a swap after losses; an upgrade also needs 80 % of the
cost at hand. The munitions module adds a second metal store (+300: 1200, a laser fits). THINK lists the queued
rebuild devices (`rebuild=12[turbine2,laser,...]`). 223 checks pass.

**Test 5 (04.11.2026, Vanilla, AI vs AI, both on Vanilla-8, ~1045 s, both reactors still standing in the last snapshot):**
- The second store works: T2 held 1200 metal from ~920 s. Payable weapons get built: firebeams at 793 s and 895 s (T1)
  and 840 s (T2). No laser, cannon or 20mm: three of the four B changes were swaps after losses (Siege prefers the
  firebeam once the laser is too dear); a firebeam is not in `Upgrade.From`, so it is never replaced later.
- Tech late: factory module at 330 s, built 602/614 s; munitions module ~640 s, built 869/894 s, so no 20mm was possible
  before the sockets had their firebeams.
- T2's B2 stayed empty from ~590 s to the end: the firebeam was refused (`CS_UNSTABLE`, floor strut strain 1.125,
  sag 29/46; node 10009 displaced -61,75 at 710 s), the rebuild was given up after 120 s (`GAVE_UP action 149`), and
  `CAI_SocketUpgrade` only looks at living devices. T2 sat on 1200 metal meanwhile.
- T1's third turbine was never lost: it was refused for ~490 s (`CS_OBSTRUCTION`, then `CS_UNSTABLE`, floor strut
  337-182 compressed to 0.873, sag 33) and built at 932 s. Its turbine2 upgrade was given up. T1 ended at 238 energy
  with two firebeams drawing on it. Sag, not metal, stopped this one.
- Not measured: reactor health, and whether the taller doors let the snipers hit the top storeys (the log has no hit
  positions; the FIRETRY ray is a straight line to the reactor).
- Found afterwards: a011454 worsened the plan, `physics.py` max stress 0.69 instead of 0.60 (earlier notes of 0.60 for
  it were wrong, read off a list of single struts). The armour tying the outer doors was 37.7 long: refused in
  `physics.py` and in the game (`CS_NODESTOOCLOSE`, `GAVE_UP action 287`), so the door layers hung free.

**After test 5:** empty B sockets are queued again (`CAI_SocketRefill`, 45 s empty, every 130 s, the next ready weapon each
try); a firebeam may be sold for a better weapon; Siege prefers the 20mm over the firebeam. The munitions plant comes
before the factory (330 s, Siege/Punish or Surplus), factory and second store after it (`store2`). Sniper sight
(`CAI_SniperTarget`, the player: snipers fired all match at closed doors): a shot only when a ray reaches a device, the
AP sniper's ray may pass 600 hitpoints (one door of 400, not two). COMBAT and DEALT log lines every 60 s. B2's outer door
ends at 66.5, 8.5 above its floor, so the tie is 46 long and gets built; `physics.py` max stress 0.68, max sag 93 as
before. Open: the sag itself, whether rays stop at closed and pass open doors as assumed, and the reaction time at an
opening door (fire tick 1 s, own door opening about 2 s). 232 checks pass.

**Test 6 (04.11.2026, Vanilla, AI vs AI, both on Vanilla-8, T101 won at 1190 s: first decided AI-vs-AI match of Bastion;
the log file also holds test 5, this match starts at its third PLAN pair):**
- The 20mm decided it. Built: T2 850 and 951 s, T1 903 and 976 s. T2 lost both at 1023 and 1032 s and did not get them
  back; T1 fired 128 rounds (T2 72 + 8). T2's reactor stood at 1.00 at 1020 s and 0.54 at 1080 s; struts lost by T2 per
  50 s from 1000 s: 43, 3, 41, 58. T1's 20mm hits: 99 low (below y 300), 19 mid, 14 top at 1140 s. No direct reactor hit
  appears in DEALT, so the reactor damage came some other way (not identified).
- Tech: munitions plant 661 s (T2), 700 s (T1); factory 590 s, 757 s: both modules fire when plan action 217 is reached
  (~420-480 s), so the order changed little. Firebeam only once (T2 B2, 782 s), sold for a 20mm. No laser. No refill fired.
- Door tie: no more `GAVE_UP` on the armour (tie 46 long). Sag at 900 s about (-24,20) / (-30,19); test 5 had (-60,76) on T2.
  `UNSTABLE` lines 6 instead of 12 (one match each). All turbines built and upgraded on both sides.
- Sniper sight: rays do stop at closed doors: `hold` 173 of 184 tries (T1) and 166 of 181 (T2) in the first 180 s. But
  `hold` freezes from ~360 s on (178 / 262) while `seen` climbs to 325 / 277. Sandbags stand behind no door, and a ray
  towards a target behind them counts as seen, since any enemy device hit passes: `sniper>sandbags` 20 (T1), 21 + 6 (T2).
  Sniper shots did not fall much: 128 + 16 (T1), 114 + 17 (T2), against 128 + 25 and 169 + 7 in test 5. Their hits on
  struts: T1 door 40, armour 18, bracing 13, against 32 on devices; T2 door 27, armour 16, bracing 9, against 44 on
  devices. So blind fire is reduced early and not solved.
- Doors: snipers reach the top now, hits at top / mid / low: T1 67 / 36 / 0, T2 64 / 29 / 1 (top means above y 75).
- Storage again idle late: T1 at the metal cap in 27 of the last 50 snapshots, at the energy cap in 13.

**After test 6:**
- Sniper sight: the ray must end within 60 of the point aimed at, so sandbags on the way are no target.
- First mine before the workshop (the player). Two more hubs like `_V_HUB`, one and two cells further left (`_V8_HUB2`
  at (-3049,532) after the first shot, `_V8_HUB3` at (-3149,532) after the workshop; the player: much stiffer upwards).
  `physics.py`: the main post's old peak (45-48, 0.60) is gone from the top list, next 54-56 0.53; the headline is now
  0.73, the short armour arm 10002-10075 of B2's outer door. Max sag 93 unchanged (a back node). The hubs were not
  tried with the arm's load alone.
- Munitions module on its own cells at plan action 171 instead of 229 (trigger 300 s, Siege/Punish or Surplus).
  Energy is the likely limit now: 5000 are needed and test 6 had 500-2000 until about 420 s.
- Module `heavy3`, socket B3: a laser on the starting fort's strut at y 404 under the reactor, through the two slanted
  armour struts in front of it, made doors (a 20mm does not fit there: box against the plan's battery and that door). From
  a full storage: 1000 metal / 6000 energy for 20 s, after `store2`. Plan 246 actions.
- Front strip (`FortStrip`, `CAI_FrontStrip`, the player): below 120 metal in the first 300 s the armour struts 57-50,
  58-57, 50-53 in front of the reactor become wood, one per think step; at 800 metal armour again, once per strut. Post
  53-55 stays armour: it carries the tower's front. By the material table that is about 100 metal per strut less 10 for
  the wood; whether `CreateLink` really pays that back is not known, the `STRIP` log line shows it. `physics.py` with
  the three as wood: 0.72. 240 checks pass.

**First try of the front strip (04.11.2026, aborted match):** no `STRIP` line at all, though metal stood at 24 at 15 s. The
list held node ids, `data.OriginalToActual` knows a node only after an action used it, the game renumbers ids anyway, and a
failed swap was marked as tried without a word. Now by position, with `STRIP_SKIP` lines, retried, below 150 metal, as many
per step as the metal needs.

**Test 7 (04.11.2026, Vanilla, AI vs AI, both on Vanilla-8, T101 won at 1517 s):**
- Front strip works: +90, +80, +89 metal per strut, 260 by 35 s on both sides (the game pays the material table's refund).
  Armour again at 285-385 s, about -200 each; one refused (result -4) stayed wood.
- Opening: first mine 60 s (105 before), workshop 119 s (111), third mine 129 s (146).
- T2: munitions plant 486 s (661), first 20mm 646 s (850). T1's munitions plant was skipped by the safety valve after 90 s,
  waiting at 177 energy, and never built, so T1 went firebeam 844/933 s, then laser 1101/1169 s.
- The player's sniper sold and placed again: T2 sold B1's sniper at ~660 s for a 20mm; module sniper2's action built its
  precursor, a sniper, on the empty strut at 665 s and the 20mm found the strut occupied. T2 never had a second heavy weapon.
- T1 won slowly: 17 laser shots in 400 s, one laser at a time, at 254-295 energy and the metal cap of 1500. A laser shot
  costs 5000 energy: two are 10000, three batteries hold 9000. Module heavy3 never fired (6000 energy for 20 s).
- Sniper sight: `hold` goes on rising (444 / 319); `seen` 94 / 131, `pierced` 41 / 182. Still 26 and 23 hits on sandbags.

**After test 7:** `CAI_SocketSet`: all actions of a socket follow its weapon, and modules going in later too. `SocketVolley`:
heavy weapons fire together at one spot, up to 90 s of waiting, other offensive weapons but the sniper hold while only the
energy is missing, after that as many together as can be paid (`VOLLEY_PART`). Modules battery4-6 with Trigger `Storage`: when
the shots of the standing heavy weapons cost more than the storage (+1000). Trigger `Afford` on munitions and factory, and a
device waiting for energy is no hang for the safety valve. Armour back only from 480 s, retried when refused. Snipers do not
choose sandbags as a target (sandbags hit on the way can still happen). 246 checks pass.

More wind (the player, 04.11.2026: storage gives no energy per second): module turbine4 with the first heavy weapon, at x -3465 on
the turbine storey's floor, its cell's outer post and diagonal in the background; module turbine5 with the second, at x -3465 on
the storey below (floor 75, four struts to the background; the nest's roof the generator first chose holds A1's door and would be
an open roof). New step `device_on`, trigger key `Heavy`. `rules.py`: turbine4 no wind warning; turbine5 clear on the left (100 %), blocked on the right (0 %), so it may give less than the others. `physics.py` max stress 0.69, without the modules: it checks the plan only. 247 checks pass.

**Test 8 (04.11.2026, Vanilla, AI vs AI, both on Vanilla-8, T102 won at 1527 s, no faster than test 7):**
- Munitions plant 623 / 629 s, both sides now (`Afford` held it from 300 s to ~550 s), first 20mm 789 / 853 s (646 s in test 7).
- Both sides had two heavy weapons; the sold sniper did not come back. T101 B1 fell back `cannon20mm->sniper` after two losses.
- `VOLLEY` 11 and 26 times, one `VOLLEY_TIMEOUT`. Module heavy3 fired on T101 at ~1100 s, the laser stayed in the queue.
- Energy 73-116 at 250 s, first turbines only at 349-359 s. T102 stood at 1500 metal and 9000 energy at the end.
- The player: a beam destroys the shells of a 20mm or cannon fired with it; turbine 5 on the storey below had too little wind; still
  too long; the starting machine gun has no line of fire once the woodspam stands in front of it.

**After test 8:** `Classes` and `Gap` in `SocketVolley`. Module turbine5 one cell behind the turbine storey (x -3590..-3500, hung on the
storey's end). Module heavy4: a 20mm in the front mortar's place, LinkT 0.18, behind a second door at x -2895, the mortar sold
(`Replace`), once two heavy weapons stand. The starting machine gun is sold with the first woodspam (socket A0 gone). A heavy weapon
is rebuilt after losses, not swapped to the sniper. `physics.py` with heavy3, heavy4 and both turbines: peak 0.82 at the arm of B2's
door, no strut breaks. Open: first turbine still late, energy low around 250-375 s. 252 checks pass.

**Test 9 (05.11.2026, Vanilla, AI vs AI, both on Vanilla-8, T101 won at 993 s, the fastest so far: 1527 s in test 8):**
- 20mm T101 603 and 685 s, T102 ~600 and ~700 s, T102 lost one at 785 s and its fort from about 850 s. `VOLLEY` 27 times on T101.
- Both plants before any heavy weapon: munitions 509 / 651 s, factory 952 / 573 s (T102 built its factory first, 80 s before its
  plant). 800 metal each.
- Never a cannon: the swap after losses took the loadout order (sniper, then 20mm), the upgrade took whatever was at hand.
- heavy4 fired on T101 at ~855 s but the mortar was neither sold nor replaced: `CAI_ExtractModules` dropped `Replace`, so the 20mm's
  action found the strut occupied and passed. My bug. The mortar was rebuilt there later.

**After test 9:** `Replace` reaches the AI. One branch first: the guns; factory only from a surplus of 900 metal / 6000 energy, heavy3
after it. The socket's `Upgrade` order is its order of worth (cannon, 20mm, laser, firebeam; B1 has no cannon, its door reaches into
the body), used on swaps as well, and the AI saves up to 120 s for its first choice. Second store from 420 s, for the cannon's 900.
Not done: the howitzer, from the packed DLC, whose size and costs are not readable here. 254 checks pass.

## Risks

- Up-front metal for the skeleton slows the first shot → only B1/B2 skeleton first, rest as modules.
- Many repeated inserts shift indices often → step 0.4 and the repeat tests.
- Posture flapping → hysteresis, logged.
- Determinism: only game state and `GetRandomInteger`, no wall-clock or `math.random` (replays, multiplayer).
