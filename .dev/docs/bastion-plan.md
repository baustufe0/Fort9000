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
forced Vanilla-8 on Vanilla until 06.11.2026 (`Force`, now empty).

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

- `ai/fortplans.lua`: `Force` is empty since 06.11.2026, so Vanilla-8 is drawn at random like the other plans; to test it alone, set `Force = { Vanilla = "fort-t1f1-Vanilla-8.lua" }` again (publish.py refuses that).
- Matches against mortar, sniper/laser, missile and turtle styles; evaluate with `train.py` and the log
  (`POSTURE`, `SOCKET`, `ZONE`, first-shot time).
- Afterwards: Vanilla-8 in the normal draw with the other plans, then other maps. Done 06.11.2026 (not played): VanillaLong-8, Vanilla2v6-5 and Vanilla2v6Long-5 ([2v6-vanilla.md](maps/2v6-vanilla.md)).
- Vanilla 2v2, not checked by the generator: Vanilla-8's back nodes come 98 from the upper fort's (plan), 65 with module turbine5; on 2v6 the game refused nodes 92-138 from another team's. Vanilla-5 is at 132, Vanilla-3 at 193, Vanilla-6 at 243.

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

**After test 9, the player's changes (05.11.2026):** turbine earlier: 3 mines with the start's two, then B2's cell and a turbine (plan action 63,
was ~160), then the other mines; sandbags stay later, so the turbine stands without them for a while. B1's weapon at LinkT 0.16: the cannon fits
there as well, `physics.py` 0.67 and 0.69 with the modules (plan alone 0.77 before). First tech branch by chance (`TECH first=`), both plants on
their own cells at action 171, the other from 900 metal / 6000 energy. Second store from 420 s without either. heavy4 takes the weapon the tech allows. 257 checks pass.

**Test 10 (05.11.2026, Vanilla, AI vs AI, both on Vanilla-8, T101 guns against T102 beams, T101 won at 1034 s):**
- First turbine 123 / 126 s (300-336 s in test 9). Energy stood at its 5000 cap around 300-400 s on T101, so energy no longer limits the
  opening; metal does: mostly below 200 until ~600 s. Third mine 172 s (129 s).
- Plants: modules fired 465 s (factory) and 525 s (munitions) because `Afford` waited for 640 metal; built 563 and 646 s.
- Heavy weapons later than test 9 (603 s): laser 787 and 952 s, cannon 885 and 1000 s. A heavy weapon takes 110-120 s from placing to built
  (cannon placed 775 s, built 885 s); T101 sold B2's sniper at 720 s, so that socket did not fire for 165 s.
- T102's factory first worked (the draw gave one of each). 9 laser shots against 7 cannon shots, 3 `uraniumcannon`; T102 at 10400 energy
  at 1000 s, so energy was not what held the lasers back.
- T102 lost 74 struts from 1000 s on, its reactor read 1.00 at 1020 s and fell by 1034 s. T101's cannons hit low: 15 + 12 low, 7 mid. Whether the
  fort's collapse killed the reactor is not measured.
- Armour back at 580-630 s (T102) and 735-765 s (T101), about 580 metal each, while heavy weapons were waiting for metal.
- Mine upgrades only at 670-685 s on T101, after the three turbine upgrades at 635-655 s, with energy to spare.
- Mortar sold at 900 s (T101) and 975 s (T102), so `Replace` works. T101's 20mm in its place: refused to the end (`CS_UNSTABLE`, strain up to 1.048 on the
  nest floor), at 1200 metal and 9000 energy. T102's laser had no time. The third weapon never fired.
- Sag at 900 s (-14,25) / (-18,23), test 5 had (-60,76). T102's third turbine still refused for ~300 s (`CS_UNSTABLE`, floor at 0.893), the second
  store given up on both sides.

**After test 10, the player's changes (05.11.2026):**
- One sniper (B1). B2 and the new socket C1 stand empty for the first two heavy weapons (modules `heavy1`, `heavy2`: `Trigger.Tech`, `Replace` picks
  by tech, a kind not yet standing first); nothing is sold for them. B1's sniper goes only once two heavy weapons stand (`UpgradeHeavy`).
- Front strip: only the two outer struts. Each of the two storeys keeps its inner armour strut (y 306-405, y 206-306), else a buzzsaw cuts through.
  Back only with two heavy weapons standing and 800 metal (`RestoreHeavy`, was 480 s).
- Mortars at the back of the top storey (x -3300..-3100), A1 behind them (x -3400..-3300), C1 in the front cell with its second door. No mortar is
  sold. `heavy2` brings two more background ties for the post that was pulled forward in test 10; whether that ends the `CS_UNSTABLE` shows only in a match:
  `physics.py` puts these struts below 0.2 and did not foresee that refusal.
- Upgrade centre out of the plan (the player, same day): module `upgrade` after two heavy weapons, or from 850 metal / 5000 energy in case the second is
  refused; mine and turbine upgrades (`upgrades`), heavy mortars, AP sniper and the fifth turbine only once it stands (`Trigger.Built`). The sniper goes at the
  latest 300 s after the first heavy weapon (`HeavyWait`).
- Check in the next match: `SOCKET` / `MODULE heavy1`, `heavy2`, time of the first heavy weapon, `UNSTABLE`, mortars hitting, wind of the turbine at -3465.

**Test 11 (05.11.2026, Vanilla, the player against T102, guns drawn, `RESULT w=2` at 648 s):**
- T102 lost no device; 22 struts in the whole match. The player's fort lost 71 struts from 630 s on, the reactor at 648 s. Whether T102's fire did that or the player
  ended the match is not in the log: its one cannon was built at 614 s, the player's three turbines fell at 618 s, `FIRETRY cannon fired=1` is logged once.
- First heavy weapon much earlier: munitions placed 409 s, built 499 s; cannon in the empty B2 placed 504 s, built 614 s (test 10: 787 s, 885 s). Nothing sold for it.
- Against the player's wish: at ~460 s, with 1370 metal, `factory` and `upgrade` fired from their surplus, before the first heavy weapon (munitions still under
  construction, nothing else to spend on). Factory built 565 s, unused.
- Upgrade centre refused: `CS_UNSTABLE` at 475 s (strain 0.897..1.005), `CS_OCCUPIED`, `GAVE_UP` at ~640 s. So no mine or turbine upgrade in the whole match.
- C1 refused again: cannon `CS_OCCUPIED` 535 s, `CS_UNSTABLE` from 565 s to the end (strain 0.925..1.034, sag 29/30). The two extra ties did not cure it.
  `heavy2` also took a second cannon: `CAI_ModulePick` counts built devices only, B2's stood under construction.
- From 600 s T102 sat on 1360-1500 metal and 9000 energy with one heavy weapon: B1's sniper waits for two heavy weapons or `HeavyWait` (300 s).
- Metal: below 200 until ~360 s, strip at 15 s (+90, +80). Armour not back, as intended (one heavy weapon).
- Mortars: of 50 logged tries 42 declined (`RAY_HIT_STRUCTURE` on own bracing, y ~-159); test 10: 33 of 48 and 23 of 37. The storey's floor, already before the move;
  28 shots by 600 s, 3 struts hit.

**After test 11 (05.11.2026):** second plant and upgrade centre only after the heavy weapons (`Trigger.HeavyDone`, `CAI_HeavyDone`: two built, or the first built for 300 s),
no surplus trigger for the centre. Centre on the rock (x -3200..-3100, y 700), retried after a `GAVE_UP` (`RETRY`). C1 refused for 30 s with one heavy weapon built: B1's
sniper is sold for the second, C1's rebuild parked for 300 s (`SOCKET C1 parked`). The mix counts weapons under construction. Why C1 is refused is still open.

**Test 12 (05.11.2026, Vanilla, AI vs AI, both on Vanilla-8, both drew guns, T102 won at 697 s, the shortest match so far):**
- Plant placed 401 s, built 491 s; cannon in B2 placed 495 s, built 605 s on both sides. T102's cannon fired at 609 s and hit T101's cannon (`cannon>cannon:1`): T101's cannon,
  sniper, mortars, turbines, sandbags and machine gun fell within 4 s, 51 struts in that minute, starting at f=15225. One hit took down the storeys above and around B2.
  T101's cannon had not fired yet. T101's reactor 0.56 at 660 s (`uraniumcannon>reactor:1`), gone at 697 s. T102 lost no strut.
- From ~480 s both sat at 1500 metal / 9000 energy: plan finished at build=368, the cannon under construction, C1 refused, upgrade centre and B1 waiting for heavy weapons.
- C1 refused again on both sides (20mm, `CS_UNSTABLE` 520 / 525 s, strain 0.937..1.038). Seven refusals of seven in three matches, 20mm and cannon, with and without the ties.
- The new path worked: T102 at 610 s `SOCKET C1 parked`, B1's sniper sold for a 20mm, placed 625 s, built 695 s. It waited for the first cannon to be built (605 s), 85 s after the refusal.
- Factory and upgrade centre did not come before the heavy weapons, as wanted; neither came in this match.
- Mortars: 89 of 99 logged tries declined on own bracing, 29 and 32 shots by 660 s.

**After test 12 (05.11.2026):** the tower's fall was no overload. `physics.py` with the first frame's struts cut: the tower stands (stress 0.65), armour posts or more diagonals
change nothing (0.67-0.69). A destroyed weapon explodes, from the game's files:

| Weapon | Hit points | Devices (radius 400) | Struts (radius 150) |
|---|---|---|---|
| cannon | 550 | 150 | 200 |
| 20mm | 200 | 100 | 160 |
| laser | 250 | - | - |
| firebeam | 180 | - | - |
| mortar | 70 | - | 60 |

A cannon shell does 700 and passes armour and doors (`Penetrate = 4000`); background bracing has 100 hit points. B2 stands in the middle of the devices: mortars ~270-320, turbines from ~165.
So the chain in test 12: cannon gone, then what it took with it. `Trigger.HeavyDone` and B1's sniper now also open on a full storage (`CAI_AtCap`, B1 after 30 s, the centre after 60 s).
`Probe.AtOnly` for a probe of C1 at 520 s.

**After test 12, the player's choice (05.11.2026):** first heavy weapon in B1, away from the tower (socket upgrade: sells the sniper once a plant stands, 450 metal / 3000 energy for 15 s and 80 % of the price; B1 is silent
while it is built). Second in B2 (`heavy2`), third in C1 (`heavy4`). No AP sniper any more (module `sniper2` gone). B1's waiting rules (`UpgradeHeavy`) gone. A refused heavy weapon's rebuild is parked
after 30 s for 300 s (`CAI_ParkRefused`). The centre opens at two heavy weapons built, the first for 300 s, or a full storage for 60 s. Check: reactor damage from a cannon lost in B1 (estimated ~200 away, not measured).

**Test 13 (06.11.2026, Vanilla, AI vs AI, probe at 520 s, both drew beams):** factory built ~495 s, laser in B1 placed ~510 s. Probe, laser only (no plant for guns, ended before the firebeam), T101, LinkT
from the back node: C1's floor 0.10 and 0.18 refused, 0.30 and 0.50 placed, 0.70 refused. B2's floor: 0.10-0.50 placed, 0.70 refused. T102 shows the same with LinkT counted from the front node.
So C1 is no question of the storey's stability but of the place on the strut: 0.18 was what tests 10-12 used. Why is not known; `rules.py` passes a laser at 0.18. 20mm and cannon reach the door from 0.24 / 0.22, so they have no measured
place there. C1 now takes beams only, at 0.40 (`heavy4`, waits for the factory, so with guns drawn it comes after the surplus plant). Beams have no blast either. In this match `heavy3` (B3, laser) came first, at ~510 s, from the surplus.

**Test 14 (06.11.2026, Vanilla, AI vs AI, both on Vanilla-8, both drew guns, T102 won at 984 s):** munitions built 517 / 520 s. Cannon in B1 placed 534 / 536 s, built 644 / 646 s; 20mm in B2 placed 546 / 550 s, built 616 / 620 s:
two heavy weapons within ~125 s of the plant, nothing idle at the cap for long. T102's 20mm lost at 788 s, rebuilt by 875 s, no fall of the tower this time (T101 lost 137 struts over the match, T102 76). C1 stayed empty (beams only in that version).
Upgrade centre refused on the rock as well: `CS_UNSTABLE` at 650 / 660 s, sag 0, strain 0.96..1.00, `GAVE_UP`, `RETRY`, `GAVE_UP`. So no upgrade in the match, third match without. Not a matter of load, cause unknown.

**After test 14, the player's finding (06.11.2026):** the screenshot shows a cannon's body reaching ~60 behind its post, so C1 had no room with a mortar in the next cell; `rules.py`'s body sizes are too small at the back (laser: 38-57 by the probe). Mortars one cell further back
(x -3400..-3200), A1 behind them (x -3500..-3400), cell x -3200..-3100 empty. C1 again for every heavy weapon at 0.18. Not yet played.

**Test 15 (06.11.2026, Vanilla, AI vs AI, both on Vanilla-8, both drew guns, T101 won at 651 s, the shortest match so far):**
- C1 accepted for the first time, on both sides: cannon placed 588 / 598 s, no `CS_UNSTABLE`. Not built when the match ended, so it never fired.
- Munitions built 495 / 505 s, 20mm in B2 605 / 616 s, cannon in B1 632 / 630 s. No refused heavy weapon at all.
- T101's first volley (cannon + 20mm, `fired=2`) ~643 s; T102's reactor gone at 651.7 s, 1.00 at 600 s. The last `COMBAT` line is from 600 s, so what hit the reactor is not in the log. T102's armour struts 68-75 and 68-71 broke at 642.7-643.0 s.
- T102 did not answer: `VOLLEY_HOLD ready=2/2 energy=0` at ~648 s with 9000 energy and 45 metal (a shot costs 40-50 metal), the third cannon under construction and 3 rebuilds queued. T101 held 322-454 metal.
- Metal again at 1500 at 500 s, the plant under construction since 405 s (module waited for 640 metal from 300 s to 390 s).
- Mortars from further back: 28 and 29 shots by 600 s, hits mid and top, as before. Of 105 logged tries 90 declined on own bracing, as before.
- No cannon was destroyed, so the blast from B1 is not tested. Upgrade centre: `MODULE_AFFORD` at 635 s, not placed in this match.

**After test 15 (06.11.2026):** third heavy weapon only with the first two built and its whole price plus 300 metal (`Trigger.HeavyBuilt`, `Trigger.Reserve`). Battery and store before turbines 2 and 3; the drawn plant goes in as soon as the store stands (`Built`, no `Afford`):
first in line, the plan waits behind it for the metal. A plant does not fit before the store: 800 metal / 5000 energy against 600 / 3000. Rebuilds are not held back for shots.

**Test 16 (06.11.2026, Vanilla, AI vs AI, both on Vanilla-8, T101 guns against T102 beams, T102 won at 681 s):**
- Plant placed 307 / 310 s (405-415 s in test 15), built 397 / 400 s, no `SKIPPED`. First heavy weapon only placed 466 / 473 s, built 586 / 583 s (630 s): B1 is sold at 445 / 455 s, after the rich rule; T102 at 106 metal, 2901 energy at 400 s.
- T102's one laser decided it. Built 586 s. T101 lost its two mortars and the machine gun at 589-590 s, all four turbines and sandbags at 619-620 s, reactor at 681.2 s (armour 49-56 at 680.8 s, 1.00 at 660 s). Laser shots 3 by 660 s. That timing fits one beam per
  row of devices, not measured per shot. T101 restored its armour at 585-590 s, so the strip was not the cause.
- T101's guns: 1 cannon and 18 20mm shots by 660 s, `VOLLEY_HOLD energy=0` after the turbines fell.
- T102 wasted B2: `heavy2` chose a firebeam (mix, laser already placed), built 552 s; `SOCKET B2 sell firebeam->laser` at 550 s; the laser placed 575 s was not built at 681 s. B2 never fired.
- C1: T101 `heavy4` at 585 s, `CS_OCCUPIED` at 595 s, no `CS_UNSTABLE`, not built. T102 never (B2 not built). `heavy3` (B3 laser) `CS_UNSTABLE` at 560 s, strain 0.947..1.017.
- Upgrade centre on the rock refused again (T101, 585 s, sag 0, strain 0.962..1.000).
- Mortars: 90 of 99 logged tries declined on own bracing, 25 and 33 shots by 660 s.

**After test 16 (06.11.2026):** with no heavy weapon yet, B1 (`FirstHeavy`) sells its sniper as soon as a plant stands, without the rich rule; if the storage cannot hold the first choice it waits for it up to 120 s. Second store at 380 s (420 s). A firebeam is no longer sold for
something better (`Upgrade.From`): the mix stays. Probe for the upgrade centre not wanted for now (the player).

**Test 17 (06.11.2026, Vanilla, AI vs AI, both on Vanilla-8, both drew guns, T102 won at 1063 s):**
- First match with all three heavy weapons: cannon in B1 568 / 581 s, 20mm in B2 576 / 586 s, cannon in C1 placed 646 / 630 s, built 756 / 740 s, `VOLLEY 3` fired. C1's second door and the mortars one cell back work.
- Plant built 409 / 403 s, sniper sold ~405 s at once. But cannon placed 458 / 471 s: at the sale 137 / 288 metal, so 50-65 s without placing anything; B1 silent 163 / 176 s; the weapon 15 s earlier than test 16.
- Shots by 1020 s: T101 cannon 17, 20mm 108; T102 cannon 11, 20mm 99. Struts lost 144 / 205. Reactor 0.75 / 0.55 at 1020 s, T101's gone at 1063 s.
- Blast from C1: T102's cannon in C1 destroyed at 1051 s with both mortars and the machine gun in the same second, 20mm in B2 at 1054 s. T102 still won with what stood. The tower survived hits in between: T102 lost 4 turbines at 973 s, T101 none of its weapons.
- Upgrade centre refused on the rock on both sides (`CS_UNSTABLE` 580 / 590 s, sag 0), `GAVE_UP` only at 910 / 900 s, `RETRY` 980 / 965 s. In between `rebuild=[upgrade]` and build stuck at 429/428 on T102: the hanging centre probably held new building back for 300 s. No upgrade in 1063 s.
- Mortars: 186 of 217 logged tries declined on own bracing, 62 and 61 shots by 1020 s; hits mid and top.

**After test 17 (06.11.2026):** upgrade centre on the place of the plant not drawn (`upgrade` x -3500..-3400 y 405 with guns, `upgrade_b` x -3400..-3300 y 602 with beams, `Trigger.Drawn`); so no second plant any more, no mix of guns and beams. Refused: out of the queue after 30 s, again after 300 s (`PARKED`, `RETRY`). B1 sells
its sniper from 70 % of the first weapon's price (`FirstShare`). Mortars: `RAY_HIT_STRUCTURE` in `FIRETRY` is a hint in the log, a straight line to the reactor, no cause: `fired=0` is mostly the fire chance, nothing changed (~60 shots in ~770 s against ~170 possible at 9 s reload).

**Test 18 (06.11.2026, Vanilla, AI vs AI, both on Vanilla-8, T101 beams against T102 guns, T101 won at 621 s, the shortest match so far):**
- Upgrade centre accepted for the first time on both new places: placed 605 s (`upgrade_b`) and 595 s (`upgrade`). Not built when the match ended, so no upgrade yet.
- Plant built 390 / 393 s, but B1 sold only 460 / 465 s at 876 / 674 metal: while it waits for 70 % the plan goes on spending (m=31-112 at 390 s). Placed 481 / 483 s, built 601 / 593 s: 20-25 s later than test 17 (568 / 581 s, sold at 137-288 metal, the plan held behind the rebuild). B1 silent ~135 s (test 17: 163-176 s).
- T101's first beam volley (laser + firebeam, `fired=2`) ~617 s: T102's front door and armour gone 618.6-619.2 s, cannon in B1 619.5 s, 20mm, reactor and most of the fort 621 s. Reactor 1.00 at 600 s. Whether beam or the cannon's blast killed the reactor is not measured.
- Beams beat guns in both matches where they met (tests 16, 18); two matches, the first volley decided both.
- `heavy3` (B3 laser) refused again (`CS_UNSTABLE`, 565 s), also in test 16.
- T102's C1 cannon `CS_OCCUPIED` at 600 s, no time. Mortars 29 and 27 shots by 600 s.

**After test 18 (06.11.2026):** `FirstShare` 0.4 (70 % cost 20-25 s, the plan spent on while it waited). `FirstShot`: a heavy weapon that has not fired does not wait for the volley (`VOLLEY_FIRST`); test 18: T102's cannon built 593 s, `VOLLEY_HOLD ready=1/2`
behind the 20mm's reload, no shot logged until destroyed at 619.5 s. The gap between beams and guns stays.

**Test 19 (06.11.2026, Vanilla, AI vs AI, both on Vanilla-8, both drew guns, T102 won at 775 s):**
- Upgrade centre built 638 / 635 s, the first upgrades since the plan changed: 5 turbine upgrades by 703 s, 2 mine upgrades 692-693 s, heavy mortars 670-671 s.
- Sniper sold 435 / 440 s at 371 / 401 metal (40 %), cannon placed 459 / 464 s, built 569 / 574 s; 20mm 568 / 558 s. As test 17; B1 silent ~135 s. `VOLLEY_FIRST` seen on both.
- C1 not placed: T102 `heavy4` at 575 s, `CS_OCCUPIED` (metal) to the end, the upgrades went in front of it; T101 `MODULE_AFFORD` only.
- T101: reactor 1.00 at 720 s; 20mm lost 774.6 s, cannon in B1 774.8 s, reactor and most of the fort 775 s.

**The reactor dies of its own cannon's blast (found 06.11.2026):** the reactor stands at (-3002,305), 100 hit points (`devices/reactor.lua`; itself 400 to devices, 240 to struts when it goes). From B1 (-3069,205) it is 120 away, from B2 240, from C1 495. A cannon's blast does 150 to devices within 400. With a falloff by distance, not measured,
that is ~105 from B1 and ~60 from B2. The tests agree:
| Test | Lost | Reactor |
|---|---|---|
| 14 | cannon and 20mm in B1/B2, 983 s | gone 984 s |
| 18 | cannon in B1 619.5 s, 20mm 621 s | gone 621 s |
| 19 | 20mm and cannon in B1 774.6-774.8 s | gone 775 s |
| 12 | cannon in B2 609 s | 0.56 at 660 s, gone 697 s |
| 17 | cannon in C1 1051 s, 20mm 1054 s (T102) | stood, won |
Test 12's 0.56, which I put down to `uraniumcannon>reactor:1`, fits the blast as well. So B1 was the wrong answer to test 12: it saved the tower and cost the reactor. A single 20mm round (90) nearly kills a reactor directly too.

**After test 19, the player's idea (06.11.2026):** heavy weapons up, away from the reactor. B1 keeps the sniper for good. C1 first (no sale), B2 second (no cannon: 240 from the reactor), then D1 on a new storey over C1 (y -315..-438, x -3200..-2945, second door at -2895); once it is placed the mortars are sold (`mortars_off`, `Retire`), so a refusal does not cost them. `physics.py` 0.84 with it on the armour above B2's door (0.77 without D1's second door).
`heavyartillery`, the first-heavy rules gone. To check in a match: D1 accepted, what the taller tower does to the sag, blast from C1 and D1 over each other.

**Test 20 (06.11.2026, Vanilla, AI vs AI, both on Vanilla-8, T101 guns against T102 beams, T102 won at 871 s; beams 3 of 3 against guns):**
- The move up works for the reactor: T101's 20mm in B2 lost 735 s, cannon in C1 737 s, with mortar, batteries, turbines, workshop. Reactor 1.00 at 720 s, 0.43 at 780 s, gone only at 871 s. So 57 damage (estimate ~40 from B2); it did not die with its guns.
- Order: T101 cannon in C1 placed 476 s, built 586 s, 20mm in B2 579 s. T102 laser in C1 placed 523 s (waits for its 6000 energy), built 643 s, firebeam in B2 615 s. Sniper in B1 stayed and kept firing (103 and 93 shots), lost and rebuilt 5 times each.
- D1 and mortars: T102 `heavy5` 730 s, laser placed 854 s without `CS_UNSTABLE`, not built; mortars retired 855 s. T101 `heavy5` 645 s, weapon never placed. T102 waited for 6000 energy with 1500 metal from ~750 s.
- What decided it: T101 had T102's reactor at 0.56 by 660 s with 3 cannon and 18 20mm shots. T102's beams took T101's four turbines at 646 s, and again at 675 s and 705 s, 9 turbines rebuilt by 727 s. After ~650 s T101 fired no heavy shot: `VOLLEY_HOLD energy=0`. At the same moment `turbine5`, `upgrades` and `turbine4up` went in at 655 s, e 6152 at 640 s, 2360 at 670 s. T102 lost 13 struts, T101 109.
- Upgrade centre: T101 built 650 s, T102 735 s; T102 5 turbine and 2 mine upgrades by 826 s, T101 none finished.

**After test 20, the player's idea (06.11.2026):** module `shield1`: an energy shield at x -3100, y -185..-55, between the sandbags and the first turbine, when the enemy has a laser or firebeam. To check: is it placed over the background post, do beams reflect, does the first turbine keep its wind, 26 energy/s.

**Test 21 (06.11.2026, Vanilla, AI vs AI, both on Vanilla-8, both drew guns, T101 won at 1587 s; no beams, so the shield did not come):**
- Reactor safe from the blasts: T102 lost C1's cannon at 729 s (mortars with it) and 20mm, D1's cannon, turbines and mortars at 989-995 s, and its reactor stood until 1587 s. T101's stood at 0.86 at the end.
- D1 works with guns on T101: `heavy5` 600 s, cannon placed 849 s, no `CS_UNSTABLE`, built 959 s; mortars retired 850 s. T102 never got `heavy5` in (`MODULE_AFFORD` only); its cannon placed 852 s, built 962 s, was C1's rebuild, lost again 994 s. T101 fired cannon 45, 20mm 207 shots by 1560 s.
- Order: cannon in C1 placed 486 / 496 s, built 596 / 606 s, 20mm in B2 586 / 607 s. Upgrade centre 666 / 684 s.
- T102 did not recover: from 1000 s `rebuild=37-128`, heavy weapons queued for 590 s and never placed, cannon 3 shots in the whole match, while its mortars were rebuilt and shot away again and again (1154-1324 s, 82 mortar shots). The hanging queue held everything else back. Struts lost 23 / 494.

**Test 22 (06.11.2026, Vanilla, AI vs AI, sides fixed for the test: T101 guns, T102 beams, aborted by the player at ~815 s, reactors 1.00 and 0.98 at 780 s):**
- Shield works: `MODULE shield1` at 485 s, placed at once (485 s) over the background post, seen by the player. It held until 809 s, 324 s, with 6 laser and 6 firebeam shots by 780 s. T101 lost no turbine until 809 s (one, with shield, cannon and mortar); test 20: four at 646 s and again at 675 and 705 s.
- Energy still short on T101: 8663 at 610 s, 5568 at 650 s, 849 at 690 s, 479-854 until the end, `VOLLEY_HOLD ready=2/2 energy=0`. T102 too at 1211 at 815 s. Turbine upgrades placed 707-741 s, 26 energy/s for the shield; what takes how much is not measured.
- Whether the first turbine keeps its wind is not measured either.

**After test 22 (06.11.2026):** `Trigger.EnergyAbove` 6000 on `upgrades`, `turbine4up`, `turbine5` and `heavy5`: they leave the energy to the shots. Rebuilds are not held back.

**Test 21 again, why T102 never recovered (06.11.2026):** not refusals (cannon and 20mm: one `CS_OCCUPIED`, one `CS_INVALIDNODES` each) but metal: 1134 at 1000 s, 54 at 1050 s, at most 457 until 1587 s, never the cannon's 900. The built-in queue spends in plan order on whatever it can pay. From 1000 s: 10 mortars, 8 turbines, 7 turbine upgrades, 5 snipers, 3 machine guns (about 5700 metal) and 456 struts, among them 20 armour and 14 doors.

**After test 21, rebuild hold (06.11.2026):** `CAI_Defaults.RebuildHold`: while a lost heavy weapon is queued, mortars, snipers, machine guns, turbine and mine upgrades and the upgrade centre wait (about 4100 metal in test 21). Struts, turbines, mines, stores, batteries and plants go on, since the weapon needs them. After 180 s the waiting ones get 45 s, in case the metal never comes. Logged as `REBUILD_HOLD on/free/off`. Armour and doors are not held: if the struts still eat the metal, they are next.

**Mortar nest without doors above (the player, 06.11.2026, not played yet):** the roofs over M1, M2, A1 and the cell in front of M2 are background bracing, three doors fewer; the storey's front door stops the snipers. New socket A2 in front of the mortars, a machine gun at x -3190 (LinkT 0.1), module `antiair_front`: only when the enemy has mortars. A1 (`antiair`) loses its 240 s limit: enemy mortars or missiles, or the posture. To make room the mortars slid back on their struts: M1 -3370, M2 -3275 (95 apart). To watch: A2 stands before the heavy weapon in C1 (modelled 136 from a 20mm's centre, 6 more than it needs): `CS_OCCUPIED` on heavy1 means it stands too close; do mortar shells land on the mortars now?

**Sandbags before the first turbine (the player, 06.11.2026, not played yet):** in the aborted test at ~1084 s the first turbine stood at 112 s, the sandbags only at 268 s; a player could snipe it in between. Now the sandbags come at plan actions 54-55, the turbine at 73 (was 61), the turbine storey's split front cell comes earlier with them. `physics.py`: max stress 0.82 (0.83 before these changes), still WEAK. Modules artillery, antiair and antiair_front stay behind the back column (`after` 11). 2v6-3 has them right after its first turbine (135, then 151-152).

## Risks

- Up-front metal for the skeleton slows the first shot → only B1/B2 skeleton first, rest as modules.
- Many repeated inserts shift indices often → step 0.4 and the repeat tests.
- Posture flapping → hysteresis, logged.
- Determinism: only game state and `GetRandomInteger`, no wall-clock or `math.random` (replays, multiplayer).

**Human match (06.11.2026, 22:18, Vanilla, T102 on Vanilla-8, drew beams, lost at 911 s, the player's reactor 0.98):** energy deadlock. `upgrades` waited for 6000 energy (after test 22); the upgrade centre stood at 660 s, 60 s after energy was last that high, and it stayed under 2200 to the end, with 3 plain turbines and metal at the 1500 cap. 8 laser and 7 firebeam shots, 13 `VOLLEY_HOLD`. The player had 4 upgraded turbines by 600 s and up to ~12000 energy. `turbine4` refused (`CS_UNSTABLE`), given up after 120 s. B1's sniper lost at 730 s, its rebuild refused (`CS_UNSTABLE`, sag 43). M1 and M2 both placed at the new spacing; A2 never triggered.

**After that match:** turbine upgrades in three modules of their own (`turbine2a..c`), one at a time, from 1500 energy with `Afford`; so are `turbine4up` and `turbine5`. `upgrades` keeps 6000 and now holds only the two mines. A turbine upgrade costs 200 metal and 1000 energy and gives 22.5 energy/s, back in 44 s. To check: whether the upgrades now cut into the shots, the reason for the limit in test 22.
