# FORT 9000 AI - Workshop changelog

One entry per Workshop upload (`ItemVersion` in `workshop/content/410900/3829000413/itemversion.lua`). Each version
has a git tag `workshop-v<N>` on the commit that was published; the next entry covers `workshop-v<N-1>..workshop-v<N>`.

## Version 5 (30.10.2026, workshop-v5 = 5313c13)

New map: 2v6 Vanilla (clean) (Workshop map 2927068191)
- The AI now plays its own forts on this map (up to six AI forts on the right). It recognises the map by where each
  fort stands, so Vanilla and Vanilla 2v2 keep their plans.
- Four low forts that stay below the next fort up on the staircase: three weapon storeys, one weapon per row at the
  front, and the wind turbines in their own storey on top, hidden in background bracing behind sandbags.
  - Sniper fort: two snipers (later AP snipers), anti-air, two mortars on top (they reach the player's front fort
    from the lower spots).
  - Cannon fort: two cannons and a sniper.
  - Rocket fort: three EMP rockets, upgraded to rockets early.
  - Laser fort: laser, sniper, anti-air, and a firebeam in front of the fort, built last.
- Tested in four matches against a player; the AI won the last ones, the latest without losing a device.

Vanilla (also VanillaLong)
- Every plan starts with a new brace: a node inside the starting fort's two lower front storeys, tied to the front
  nodes around it. The forts carry their weight much better (peak strut load about a quarter lower).
- Miniguns only where they can fire at the enemy fort: a machine gun standing behind another weapon stays an anti-air
  machine gun, and the starting fort's own machine gun is upgraded instead.
- Vanilla-5 builds its upgrade centre right after the EMP rockets, so they become rockets sooner (on 2v6 the same
  change brought the rockets about two minutes earlier).

## Version 4 (29.10.2026, workshop-v4 = dde982d)

Vanilla (also VanillaLong)
- The mine row (the ground storey the whole fort stands on) is protected: five layers of triangle woodspam in front
  of it, on every Vanilla plan. Before, one laser sweep along that storey could bring a fort down; Vanilla-3 had no
  woodspam there at all.
- A new foundation in front of the starting fort, braced up to its lower front, is built first. It takes the weight
  of the front and the woodspam off the starting fort's front post.
- Cells are braced with one diagonal (two triangles) instead of an X, except under Vanilla-3's cannons: about 18 %
  less wood, 440-490 metal saved per fort, forts finished ~30 s sooner, and stronger because they are lighter.
- In test matches the forts lasted 744 and 1054 s and took 25 beam shots, where the old plans fell to two.

Abyss
- A second anchor ties the top of the starting fort to the rock ledge beside it, so the cliff tower no longer hangs
  on a single strut.
- One diagonal per cell as on Vanilla: about 20 actions and 300 metal less per fort.
- Abyss-4 (two cannons) is removed: it never won a match and its tech buildings overlapped.

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
