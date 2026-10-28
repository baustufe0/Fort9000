# FORT 9000 AI - Workshop changelog

One entry per Workshop upload (`ItemVersion` in `workshop/content/410900/3829000413/itemversion.lua`). Each version
has a git tag `workshop-v<N>` on the commit that was published; the next entry covers `workshop-v<N-1>..workshop-v<N>`.

## Version 3 (28.10.2026, workshop-v3 = 30ac174)

Fort plans
- The AP sniper (sniper2) shoots through one door. Direct-fire weapons now get a second short door 40-50 in front
  of their weapon door:
  - Vanilla-3 / VanillaLong-3: both 20mm cannons and the sniper
  - Vanilla-5 / VanillaLong-5: the lower EMP rocket (the upper one keeps a single door, a second one made the fort
    topple)
  - Vanilla-2 / VanillaLong-2 and Vanilla-6 / VanillaLong-6: the sniper on the roof of the starting fort

Strategy
- Retrained from 58 matches (version 2: 33), including the first 2v2 matches. Main shifts: mines and reactors are
  valued higher as targets (mine 79 -> 84, reactor 91 -> 94), turbines and snipers a little lower; aggression
  about unchanged (early 0.69, mid 1.11, late 1.43).

Recorder (training data only, no effect on play)
- In 2v2 the snapshot sums metal and energy over both teams of a side and lists each team; it used to read only
  the first team.

## Version 2 (28.10.2026, workshop-v2 = 83d82bb)

- The AI loads its strategy, fort plans and map settings from the Workshop folder first, which fixes desyncs in
  multiplayer when the host and a subscriber had different files.

## Version 1 (28.10.2026)

- First upload.
