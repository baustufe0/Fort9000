# FORT 9000 – Physics check of build plans

`tools/fortgen/physics.py` predicts before a match whether a plan's fort stands: how far it sags and leans, how
close each strut comes to breaking, which struts the game will refuse because the fort has moved, and what breaks.
Pure Python (no numpy), about 3 s for a 250-action plan.

```
python tools/fortgen/physics.py check fortplans/Vanilla/*.lua [--png out.png] [--trace] [--no-modules]
python tools/fortgen/physics.py calibrate --log <probe log> --plan <plan of that match> [-v]
python tools/fortgen/physics.py selftest
```

`check` exits with 1 if a plan `FALLS`. The map is taken from the plan's folder (`--map` overrides it).

## Model (the game's own, `db/constants.lua` and the material and device files)

- **Nodes** are hinges with mass: half the mass of every strut at them (`Mass` per length × rest length), the devices
  on their struts split by `LinkT`, at least `MinimumMass` 15. Gravity 981 (y points down). Foundations are
  fixed: the starting fort's from its `.spr` flag, a plan's new nodes when they lie on the rock (within 5 of the
  terrain of the map's `.fwe`).
- **Struts** are springs: force = `Stiffness` × (length − rest length), wood 200000, armour and doors 250000.
  Struts take no bending, so a cell without a diagonal folds (a *mechanism*).
- **Stress** as the game reports it (`GetLinkStress`, `PROBE LINK`, the `STRESS` lines): strain divided by the
  break limit (`MaxExpansion` − 1 stretched, 1 − `MaxCompression` squeezed); at 1.0 the strut breaks. Background
  bracing breaks at 0.92 / 1.08, so at the same strain its stress is 25 % higher.
- **Solver:** nonlinear static equilibrium (Newton-Raphson with the geometric stiffness, so leaning and the
  redistribution of load are included), banded LDLᵀ factorisation in reverse Cuthill-McKee order. A pivot without
  stiffness marks an unbraced node. A strut at stress ≥ 1 breaks: it is removed (the worst first) and the fort is
  solved again, until nothing more breaks (`BREAKS`) or no equilibrium is found (`NO EQUILIBRIUM`: it falls). After
  8 broken struts in all or no equilibrium the replay stops (`COLLAPSE at action k`).

## Build order (why a plan can fail although the finished drawing is fine)

The plan is replayed action by action, the way the AI builds it ([building-rules.md](building-rules.md), "Node
placement"):
- a new node goes to the **current** position of its source node plus the planned offset; a node on the ground goes
  to its absolute position; a node within 20 of an existing node snaps to it;
- a strut between existing nodes takes their current distance as its rest length (the lean is locked in);
- a strut longer than 218 (`StandardMaxLinkLength`) or shorter than 37.5 at that moment is **refused**
  (`REFUSED`, the game's `CS_NODESTOOFAR` / `CS_NODESTOOCLOSE`), and so are the struts and devices that need it;
- a material swap keeps the rest length; devices add their mass; `DESTROY_*` remove parts;
- a node hanging on one strut is not solved until it is braced (the AI braces it a second or two later; letting it
  swing down statically put the whole Vanilla-3 replay 200 off). A node unbraced for more than 8 actions is
  reported (`UNBRACED`) and then held in place while the rest is solved; one unbraced at the end is `LOOSE`.

Plan modules (`FortModules`) are added after the plan unless `--no-modules` is given (the worst case: everything
built).

**Verdict:** `FALLS` (a strut breaks or no equilibrium), `WEAK` (stress > 0.8, sag > 60, loose nodes at the end or more
than 3 refused struts), else `STANDS`. The five highest stress peaks during the build are listed with their action.
`--png` draws the final fort over the plan (grey) with every strut coloured by its stress; `--trace` prints the worst
strut and the largest sag after every action.

## Starting fort

Plans do not contain the starting fort. `load_startfort` reads it from the map's `.spr` file (`spr.py`,
[map-files.md](map-files.md)): team 1's nodes at the positions the map stores, its foundations, every strut with its
material and **its own rest length**, and the devices on struts. The map stores the fort settled, in equilibrium with
those rest lengths (solving it does not move it). Node ids become the plan's by position: nearest first, within 20, to
the starting-fort nodes of the base plan (`gen_fort.MAPS[map]["base_plan"]`) and of the plan being checked (Vanilla's
base plan was recorded from a settled fort: up to 6.5 off the map's nodes; Vanilla's file ids are the plan's − 1); a
node no plan names keeps its file id + 90000. The replay measures a new node's offset from the plan's position of its
source node, as the game does. Any map with a readable `.spr` works; team-2 plans such as VanillaLong are skipped.
Until 27.10.2026 the starting forts came from probe dumps (`startforts/<map>.json`, rest lengths assumed); the map's
own rest lengths fit the engine better (Abyss: correlation 0.92 → 0.99).
`MAP_NOTES` in `physics.py` holds a note per map that `check` prints (`NOTE`).

## Calibration and validation (26.10.2026)

- **Engine stress:** `calibrate` replays the plan of a probe match (Vanilla-3 as of commit d98ba24, 243 actions) and
  compares every strut with the stress the engine logged (`PROBE LINK`): 220 struts, correlation **0.89**, engine
  stress = **0.95 ×** model (0.97 with the earlier probe-extracted starting fort), with the game's constants and no
  fitted factor. A spring law per unit strain (force = `Stiffness` × strain × 100) fits worse (0.88, 0.90 ×), so
  `SPRING_LAW = "abs"`. The worst struts are the starting fort's ground posts (armour 40-41: engine 0.62, model
  0.50) and the back of the starting fort.
- **Positions:** median node 6 off the engine's; the top of the Vanilla-3 tower sags 93 (engine 103). A handful of
  back-block nodes appear ~100-400 off because the probe's plan ids there are shifted by one (an id-mapping quirk
  of the log, not of the model).
- **Refused struts:** Vanilla-5's brace from the starting fort's node (-2996, 504) to the front ground node
  (-2900, 700), 217-218 long in the plan, comes out at 219 after the fort's lean; the game refused exactly this strut
  with `CS_NODESTOOFAR` in three matches on 26.10.2026 (runtime nodes 65-58 = plan 47-40).
- **Collapse:** the recorded Vanilla-7 of test 2 (781 actions, rebuilt with `rec_fort.py` from
  `log_20261026-195816`; it fell at ~460 s while the player built nothing, ~15 struts `CS_NODESTOOFAR` from plan
  action 60 on, the first cannon `CS_UNSTABLE` at action 129, 17 struts broken at ~275 s) comes out `FALLS`: struts
  refused at actions 61, 67, 69, 124, 145, 158 (game: 60, 66, 160, 181, ...), the loose prow node 57 (its struts were
  removed) pulled in at 133 (sag 287), then the background-bracing posts of the starting fort break at action 161
  and the replay stops (`COLLAPSE`). The model falls earlier than the game, which leaves the sagging frame standing
  for a while (no time in a static model). The generated Vanilla-7 `STANDS` (max stress 0.68, sag 34).
- **Current plans:** all Vanilla plans stand. Vanilla-2, -3, -5, -6 are `WEAK` only by stress 0.83-0.92 on the
  starting fort's front ground armour (40-41, 41-46) and Vanilla-3's front armour column under the prow
  (10018-10068); the engine showed the starting fort's ground posts ~25 % above the model. The woodspam nodes in
  front of the starting fort hang unbraced for 8+ actions (`UNBRACED`): the generator builds a layer's nodes before
  its braces.

- **Abyss (not validated):** the bare starting fort matches the engine (71 struts at 5 s into the match, correlation
  0.99, engine = 1.05 × model, with the map's rest lengths). The plans do not: the only in-game shape record (Abyss-5, 24.10.2026, an older plan version, stuck at
  plan action ~60) shows the tower's front sagging 13-48 by 60 s, the model sags its front cantilever (x −1800..−1700
  over the starting fort's edge) by 100-160 by action 30 and swings it down at action 36 (no strut over its limit:
  the base struts of the tower at −0.72..−0.75 tilt the cantilever, and its cells are braced only after it has
  sagged). The base nodes match (10000: model 1, 8 / game 1, 11; 10001: −3, 19 / 2, 20). With 3 × the stiffness the
  front matches and the base is too stiff, so no single stiffness fits. `check` therefore says Abyss-3 and
  -5 `FALLS`, -4 `WEAK` (sag 164), but these verdicts are not reliable (the `NOTE` says so). What would settle it: a
  probe at the end of an Abyss plan (engine stress and positions of a loaded Abyss tower, like the Vanilla calibration).
  The rebuilt Abyss-2 (27.10.2026) keeps its cantilever short (the nest over the starting fort's roof, its front node
  braced down, a one-cell tower against the cliff) and `STANDS` (stress 0.54, sag 51).

## Limits

- Statics only: no shots, explosions, wind, swinging or the dynamics of a collapse; what the check says is that a fort
  is (or is not) able to carry its own weight in the order it is built.
- Recession (a weapon turning struts in its way into background bracing or doors) is not applied: only the break
  limits differ; mass and stiffness are the same.
- Struts under construction count as finished; time between actions is not modelled.
- `CS_UNSTABLE` (the game refusing a device) is not predicted: the probe showed it does not follow the strut stress
  alone ([building-rules.md](building-rules.md)); the sag and stress of a device's strut from this tool are inputs
  for a future model of it.
