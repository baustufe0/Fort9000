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

## Step 3: AI – zone hit map

- `OnLinkHit` / `OnLinkDestroyed` for own links: damage per zone (`FortZones`), decayed like `st.threat`.
- Zone above a threshold → its reinforcement module (repeatable, cooldown). `Z0` gone → rebuild `Z0`.
- Log: `ZONE Z1 dmg=<n> -> reinforce`.

Test: `t_zones.lua`.

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

## Risks

- Up-front metal for the skeleton slows the first shot → only B1/B2 skeleton first, rest as modules.
- Many repeated inserts shift indices often → step 0.4 and the repeat tests.
- Posture flapping → hysteresis, logged.
- Determinism: only game state and `GetRandomInteger`, no wall-clock or `math.random` (replays, multiplayer).
