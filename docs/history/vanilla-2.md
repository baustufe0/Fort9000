# Vanilla-2 – test history

Current state: [maps/vanilla.md](../maps/vanilla.md#vanilla-2--sniper-and-mortar-rush). Tests 1-8 (25.10.2026), then 13-15 (9-12 were not written up separately).
First test match (25.10.2026, difficulty 1, the version with the sniper in the first prow storey): workshop placed at 5 s, the mortars at 65 and 71 s (built 90 and 96 s, firing before 110 s, faster than the model); the sniper was refused (`CS_UNSTABLE` at 5 s, `CS_OCCUPIED` later) on the prow's roof strut (first blamed on the starting fort's machine gun, which in fact stands on the lower front). The refused sniper cost no time, the AI moved on and waited for the workshop. Second test (same day, the sniper in a second prow storey with a mortar on its roof): mortars placed at 65 and 66 s, the sniper refused again (`CS_OCCUPIED`, then `CS_UNSTABLE` on the second storey's floor). Both refusals were on the prow, which hangs over the cliff, as was the early sniper on the starting fort's front post in Vanilla-3/-4; the sniper now stands behind the prow, on the roof beam over the reactor. Third test (same day, sniper on the roof beam, mortars on the open deck roof): sniper placed at 9 s (built 29 s), mortars at 65 and 66 s (built 90 and 91 s), both fired; no build errors. Energy then dropped to 130-300 (each mortar shot 200 energy, the first turbine needs the whole tower). The sniper rarely fired: its ray mostly ended on the armour of the enemy's front (`FIRETRY ... RAY_HIT_STRUCTURE`), so the built-in AI held fire. The open-roof mortars could be seen and sniped by the player, hence the hidden, sandbagged nest. Fourth test (same day, sandbags planned on the mortars' own struts at LinkT 0.8, mortars at 0.3): the sandbags were placed at 15-16 s and took both struts, no mortar was placed (the game allows one device per strut); now each device has its own strut. Fifth test (same day, 100-high nest, sandbags before the mortars): the lower sandbags were placed at 22 s, the upper ones (strut at y 55) refused with `CS_OBSTRUCTION`, then `CS_UNSTABLE` (a sandbag's box is 51 high, each half of the cell 50); the first mortar was placed at 71 s, the second (its strut sharing a node with the sandbags' and the first mortar's) refused with `CS_UNSTABLE`, while the prow's nest leaned ~25 forward. Now the nest is 125 high and the mortars come before the sandbags. Sixth test (same day): both sandbags placed (87 and 89 s, the upper one after one `CS_OBSTRUCTION`), the first mortar at 65 s (fired regularly through the nest), the second again refused (`CS_UNSTABLE`, later `CS_OCCUPIED`). The two mortars stood 77 apart (LinkT 0.5 on each half); the game's own plans space mortars 91-122 apart, and 127 apart both were placed in the third test. Now 116 apart. Seventh test (same day): sniper at 11 s, both mortars at 65 and 66 s (built 90 and 91 s), both sandbags at 76 and 77 s, no build errors; both mortars fired regularly through the nest (the AI's ray sometimes ended on the own sandbags or the other mortar, the next try fired). Energy then ran down to 2-20 between shots (each 200 energy, one roof turbine by 210 s): energy is now the limit, hence the turbine gallery. Eighth test (same day, difficulty 1, against the player): the AI won at 390 s without losing a device (it destroyed 7 machine guns, the reactor, a turbine, a battery, a store, a repair station and sandbags). Sniper 11 s, mortars 65-66 s, nest sandbags 76-77 s, first gallery turbine 141 s, the other two 199-202 s; energy stayed at 1500-7500 from 100 s on and the mortars fired 41 times without waiting for energy (metal became the limit, 17-100 late in the match). The gallery's lower sandbags, 70 from the first mortar at the same height, were refused (`CS_OBSTRUCTION`, then `CS_UNSTABLE`); the upper ones (y 40) were placed. Now at x -3170 (90 from the mortar), the gallery turbines at LinkT 0.35 (`turbine_floor_t`; x -3465, -3365, -3265). The `UNSTABLE` line's `sag` and `strain` values are not usable for these team-2 matches: every node, also untouched starting-fort nodes, showed 80-120 off its plan position.

    Thirteenth test (25.10.2026, against a player who built a sniper, machine guns (504 shots), an
    armoury, a factory and a laser at ~355 s): **the player won at 453 s**. The AI's sniper was destroyed at 50 s
    (rebuilt 63 s); both mortars were destroyed 3-5 s after they were placed (65-66 s), before their sandbags (78-80 s):
    the hidden nest does not stop machine-gun fire (background bracing lets projectiles through), only sandbags do,
    so the sandbags must come before the mortars (the spacing that once refused the second mortar is fixed, 89-90
    apart worked). Rebuilt at 82-83 s behind the sandbags they survived and fired 63 times, upgrades and miniguns as
    planned; kills: a machine gun, a turbine, sandbags. The end: one laser beam at ~451 s cut through the starting
    fort's lower front (first strut lost: the armour at x -2900, y 512..606 of the starting fort) and the whole
    starting fort with the reactor collapsed within 2 s; nothing protected the lower front. Now: the nest's sandbags
    before the mortars, and early (right after the gallery's sandbags, ~145 struts) a second woodspam region: two
    layers (x -2852/-2812) hanging in front of the starting fort's lower face (y 411..700; the rock ends at the face),
    foreground bracing except the band 411..505 in front of the starting machine gun (`woodspam` takes a list of
    regions, plan step `woodspam:<k>`; `outside` takes a material per band; wall nodes outside the grid are found
    among the starting fort's nodes). Fourteenth test (25.10.2026, against a player with rockets (34 shots, 4 uranium
    rockets), a shotgun (80), machine guns (315)): **the player won at 338 s**. The nest's sandbags stood at 24-26 s,
    the mortars (65-66 s) survived until 324-338 s and fired 43 times; the lower woodspam was built (~185 s). From
    270 s the player's rockets took the front apart (75 struts in ~70 s): the lower woodspam at 315 s, the inner layer
    in front of the reactor at 320 s (the struts `rebrace` had turned from armour into wood for the rush), the outer
    armour at 337 s, the reactor at 338 s. The AI's sniper was destroyed three times, five machine guns lost; kills:
    three machine guns, a rocket launcher, two turbines. In both lost matches the end came through the reactor's
    front. Now Vanilla-2 keeps that inner armour (no `rebrace`; the rush loses ~195 metal, mortars ~74/89 s instead
    of ~63/77 s in the model) and builds both woodspam regions early, right after the gallery's sandbags (~143
    struts): the prow band in front of the reactor (y 205..310) and the lower front (y 411..700). Fifteenth test
    (25.10.2026, that version, AI at difficulty 1, against a player with machine guns (534 shots), six mines after
    55 s, eight turbines, a laser placed at 413 s (finished 580 s) and a firebeam (finished 578 s)): **the player won
    at 634 s**. The defence held: the nest's sandbags stood at 31 s, the mortars (63-64 s) survived and fired 101
    times, the miniguns 195; the AI lost no device until 560 s and almost no strut until 596 s; kills: four machine
    guns, three turbines, a sandbag; it never hit the laser or the firebeam while they were being built. The end
    came through the reactor's front again: the firebeam took the gallery's bracing at 596 s, one laser beam at
    ~632 s cut the starting fort's front (door and armour at the prow) and 79 struts and the reactor fell within 2 s.
    The cause was metal: the first extra mine came only after the upgrade centre (347 s, the others at 490 and
    526 s), metal stayed below 150 in 62% of the snapshots (average 198, player 643) and the plan stalled from 285
    to 525 s (actions 316-333), while energy stood at 2400-5000 and at its cap from 260 s. Now all three mines
    come right after the mortars, before the first turbine and the gallery. Not yet tested.

## Notes moved from the current-state docs (condensed 25.10.2026)

- Before the rush layout (24.10.2026) Vanilla-2 put its mortars in the top cells of the five-storey tower and waited for
  the whole storey-by-storey tower: sniper after 165 struts, mortars after 175-183. The low deck brought the sniper to
  14 struts, both mortars to 19 and the sandbags to 33.
- The roof turbines of the five-storey tower had waited for the whole back block (first turbine after 163 struts,
  ~9,700 energy in struts); the gallery's first turbine came after 92 struts (~5,500 energy). A turbine in the
  gallery's front cell itself (hanging on the starting fort's back posts) would have come after 63 struts, with only
  the nest's sandbags in front of it.
- Economy model of the rush before the armour was kept: sniper ~12 s, mortars ~63/70 s, sandbags ~99 s (metal-limited;
  mortar cells under door roofs would have cost ~700 metal more for doors and armour).
- Until 25.10.2026 the starting fort's machine gun was assumed on the prow's roof strut (-2945,206)-(-2846,204), from a
  probe log whose machine gun there had been built by the Vanilla-3 plan; that moved devices off the prow storey and
  led to a planned sale of it, which failed three times (`DD_NOTFOUND`). A failed sale listed the own devices at match
  start: `machinegun@64-65:2949,503` for the mirrored team 2. Both changes were reverted.
- The sniper's split door (first try): test match 25.10.2026, the sniper placed at its new position (LinkT 0.7)
  without errors, 124 shots, no clearance failures; the armour above the door did not get in the way.
- Late-game upgrade order: in a test match the heavy mortars came 52 s after the upgrade centre was placed, with only a
  battery in between (every upgrade waits for the finished upgrade centre).
