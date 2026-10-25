# Abyss

- Abyss variants: the game's own plan, Abyss-2 mortars, Abyss-3 snipers, Abyss-4 two cannons, Abyss-5 rockets with smoke
  (armoury, two EMP rockets upgraded to rockets, two smoke bombs, two flak upgraded to shotguns; see Abyss-5 below).

Abyss map rules for the cliff ledge left of the tower (y=-750), following the game's Abyss-1: `found_from_below` builds a foundation from the storey below first, else diagonally from above, never straight down (the front ledge node (-2199,-746) is 154 from the node below, beyond the 150 limit, so it comes diagonally from the roof node (-2100,-846), as Abyss-1 builds its other ledge foundations); `no_build_from_found` builds nodes above the ground from other nodes rather than from foundations, so the roof nodes go along the roof; `rock_clear` (30) keeps every other new node at least that far from the rock (closer grid points become foundations or are dropped; `validate()` reports violations). Abyss-2..5 were regenerated with these rules (devices unchanged).
Abyss-5 (rockets): the Abyss-4 shape; the EMP rockets/rockets in the two tall front storeys (x -1800..-1700 floor -250, 142 high; x -2000..-1900 floor -95, 155 high), one smoke bomb and one flak/shotgun on the top roof next to the three turbines, the other two on the roof at y=-502. The Abyss rows are fixed by the starting fort (storeys 100-155 high), so only these two front storeys are tall enough. Not yet tested in a match.

## Approaches that failed (Abyss)

| Approach | What happened |
|---|---|
| Cannons with factory as prerequisite | `CS_PREQUISITENOTMET` with weapon_pack (Abyss-4 never placed its cannons; it now builds the munitions plant on weapon_pack's ToGA1 armoury slot) |
| Foundation on the Abyss cliff ledge built straight down from the roof node above, roof node built diagonally up from that foundation (all Abyss plans since the short-chain change, 23.10.2026) | test match 24.10.2026 (Abyss-5): both refused with `CS_OBSTRUCTION`, the AI stalled for 5 minutes with full resources and never reached the armoury. The tower had sagged 15-35 by then; a node is placed at its source's current position plus the offset, so the foundation (4 above the rock) landed in the rock. Now built like the game's Abyss-1 (`found_from_below`, `no_build_from_found`, `rock_clear`, see above) |

## Results

Wins of the AI per plan (`train.py report`, 25.10.2026): Abyss-ToGA1 (the game's weapon_pack plan) 2/5, Abyss-3
(snipers) 1/1 (the player barely fired), Abyss-2 (mortars) 0/3, Abyss-4 (cannons) 0/2, Abyss-5 (rockets) 0/1. Abyss-4
never placed its cannon, laser or upgrade in those matches (before the munitions-plant fix). Open suggestion: take
Abyss-2 and -4 out of the plan list. `rules.py` (half-widths, 25.10.2026) flags Abyss-4's workshop (x -1996) and
munitions plant (x -2070) at y 305 as overlapping (74 apart, need 135); the installed Abyss plans also differ from what
the generator now produces (older generator changes), so they are left as they are until Abyss is worked on. In the first 11 Abyss matches the AI averaged 100-260 metal (player ~510) and
~3.8 mines (player ~6), and rebuilt lost machine guns 9-18 times per match; the player used miniguns, machine guns,
buzzsaws and snipers at difficulty 0.5.
