# Vanilla-3/-4/-5 – test history

Current state: [maps/vanilla.md](../maps/vanilla.md).
Test matches 24.10.2026: the first cannon was built and fired both times; the second, one column back (x -3300..-3200) a storey higher (floor -95, as in ToGWM2) or lower (floor 105), was refused with `CS_UNSTABLE` both times (strut stress <= 0.27). That column is the seam where the back part of the tower (built up from the back block, which tips into the reactor gap) meets the front part (on the starting fort): the back part leaned 25-30 further forward, so the cells between x -3300 and -3200 were squeezed by about a quarter; the roof turbine on that column was refused in every test too. With the second heavy weapon directly above the first (x -3200..-3100, floor -95), it was refused too, and the `STRESS` line showed why there: the engine had turned its floor and the posts beside the first cannon into background bracing, although the plan built them solid. The game turns foreground struts a device overlaps into background bracing, on which nothing can be placed: at LinkT 0.75 the cannon's body (18 in front of its mount) crosses the post at x -3100, and its box (~90 high) reaches the floor 100 above once the nodes sag unevenly.

Test match 24.10.2026: the AI's own fort collapsed at 7.8 min without enemy fire: the starting fort's prow (it hangs over the cliff) carried the front, its armour chain reached 0.97 of its breaking limit (`STRESS` top) after the first cannon (120 mass, LinkT 0.75) was placed.

Test matches 24.10.2026: both heavy weapons were built and fired in Vanilla-4 (cannons) and Vanilla-3 (20mm, 54 shots), the fort stayed stable (prow stress 0.42-0.53 instead of 0.75-0.97).

Test match the same evening: the sniper was built at once, the machine gun in the low cell too; the plan finished at 445 s with every device except the roof turbine on the seam column (refused three times, the AI gave up after 120 s).

Test match 24.10.2026 (Vanilla-3): first turbine at 161 s instead of 58 s, but the plan was finished at 475 s instead of 445 s; both 20mm cannons and three turbines were built; the sniper on the top front cell (floor -270), placed easily on the lone front column before, was refused with `CS_UNSTABLE` (strain only up to 1.02) once the whole tower stood below it, and the AI gave up on it; the lower tower storeys leaned forward less (rough `SHAPE` averages, the snapshots are noisy).

A match with both mines first (`mine, mine, turbine`) had plenty of metal but ran short of energy (200-600 instead of 1200-2300 at 40-120 s), so the first turbine was no earlier (170 s); the later devices came 12-32 s earlier and the plan was finished at 400 s instead of 475 s (the wood struts in front of the reactor held; the top sniper was refused again). Test match with the current opening: workshop at 71 s (was 238 s), first turbine 174 s, machine gun 185 s, second mine 226 s; metal was short again (50-110 at 40-240 s) while energy piled up, and the plan was finished at 430 s (both 20mm cannons placed at 402-410 s; the top sniper refused again).

Test match 25.10.2026 (Vanilla-3, against a player, aborted at 680 s): workshop 5 s, munitions plant 65 s, first 20mm placed 155 s (built 225 s), cage turbines 268 and 359 s, both cage sandbags 314-316 s, upgrade centre 414 s with store, battery and a machine gun while it built, both turbines upgraded 454-455 s, second 20mm 478 s; 126 20mm shots; energy ended at ~10,500 (two upgraded turbines are enough there), metal was short until late.

Second rush test: the 20mm was built at 220 s and reported ready; every `TryFireGun` was declined although energy (up to 9000) and metal were there; the 20mm's `alone` grouping affinity is 1, so the likely reason is no target: `FindTarget` drops targets whose ray is blocked, and in the 20mm's cell on floor 105 the background diagonal runs from (-3200,-20) down to (-3100,105), right in front of its barrel (in the old cannon cells it ran the other way, behind it). The `CREC` struts of that match showed the actual cause: the post in front of the 20mm's lane (x -2945, floor 105 to -20) was placed as wood bracing at 212 s (before the cannon was finished) and only became the planned door at 422 s, when the AI had finished the plan and its final pass corrected the material; the 20mm fired 11 s later (in the first rush test: door 332 s, first shot 343 s). A material change on a strut that is still under construction does not take effect, and the AI works through its actions faster than struts are built (5 s and more), so a door or armour planned a few actions after its strut stayed wood (in that match only 2 armour struts and no door were built before the plan was finished). `gen_fort.py` therefore gives the action that places a strut its final material when the plan changes it within `SWAP_WINDOW` (20) actions, instead of adding a second action that swaps it (8-9 actions fewer per Vanilla plan; the rush 20mm now comes after 58 struts). Test match with it (24.10.2026): munitions plant 155 s, 20mm placed 158 s, built 228 s and fired at once (first shots by 230 s, against 445-480 s with the earlier plans). Added after the 20mm rush test (24.10.2026), where the finished 20mm waited ~2 minutes before its first shot although energy and its line of fire were free.

## Notes moved from the current-state docs (condensed 25.10.2026)

- **Stepped tower and node chains** (Vanilla-4, since reverted): almost every node of the tower was built through one
  chain of 14-17 nodes up a 100-wide column at the back (x -3500, built first for the first turbine); the tower top
  was ~200 forward of its plan position after 4.6 minutes, almost without enemy fire. A build-only test with `SHAPE`
  lines: the lean grew only while the tower was being built (minutes 1-3: rows above y=205 shifted +17 per storey,
  every node of a row by the same amount) and then stayed constant; nodes at row 205 were placed ~23 forward of the
  nodes below them because they were built sideways from the leaning column; the cannon cells' back edge (61-79
  forward) and front edge (+5) squeezed the 155-wide cells to 85-100, floor beams locked in at 42-55 % of their length,
  and neither cannon could be placed. Three test matches in all: with long chains the fort collapsed at 8.5 min; with
  short chains the cannon cells kept their shape (sag 14-24), but both cannons and a sniper in the top cell were still
  refused at strut stress 0.001-0.05. Short node chains then brought Vanilla from max 16-17 / avg 6.4-7.9 to max 10 /
  avg 3.6-3.8.
- **Heavy weapon on another weapon cell** (Vanilla-3): the 20mm in the top storey sagged 24-38 (most stretched link the
  background diagonal of the 20mm cell below); one storey lower it was placed and fired 63 shots; in a second match the
  20mm one storey lower, again directly on the other 20mm's cell, failed the same way under fire (sag 38-49, moving).
- **First 20mm rush test** (24.10.2026): workshop 65 s, munitions plant placed at once and built at 155 s, the 20mm
  placed 158 s and built 228 s, as modelled, but first shot only at ~343 s: from 235 s the fire control found it not
  available or not ready although energy and the line of fire were free (the wood post in front of it, see above).
- Vanilla-3 then had three roof turbines on the plain tower roof (`turbine_avoid` on the seam column), enough for the
  munitions plant and both heavy weapons; the cage (25.10.2026) has two, upgraded.
