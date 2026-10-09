# Review of relationships.md rev 1: designer-feel (Barone lens)

Verdict: approve with B1 to B4 folded in. Sound and small; the weakness is the player's emotional hook.

**Good:** bonds from shared days, personality only changes rate; four number-free lines with grief uncapped; friends-only talk pose (best idea); no numbers or HUD meter; kin as "who was there at birth"; friend pull shipped at 0.

**Blocking**
- B1. Lines name two people with nothing to remember them by. (a) Put the place in the line (room, green room, site, ice) from fixed text variants per kind and place type, no random rotation; at minimum carry the building id on the log entry. (b) Reword "drifted apart" to "{a} and {b} don't see much of each other now."
- B2. The 3-a-sol cap with no retry swallows firsts. Keep the pair's first-friend flag unset when capped, and queue at most one capped event to the next sol (queue of 3, drop oldest), or cap per kind.
- B3. Grief: use "{a} is mourning {b}." (the present tense with no end otherwise); allow up to 2 grief lines per death (the two strongest bonds at or above the friend line), never capped.
- B4. Founder crew at 0.35 means no relationship lines for the first ~20 sols. Allow one crew-only line when a crew pair first becomes close: "{a} and {b} have grown close. They came a long way together." (`text.close_crew`); this also sets up later drift. Backs O4 (a).

**Optional**
- O-1. Friends-only talk may read as a bug; strangers could glance or talk briefly if a frame exists.
- O-2. Add a floor target: at least 1 line per 5 sols on average over sols 20 to 300.
- O-3. Rare extra beat on the talk pose from the view RNG, only if a second frame exists.
- O-4. First-friend line for a lonely being: "{a} has found a friend in {b}." (one more fixed text; pair with B1).
- O-5. Keep: no chores, no HUD word (reject O3 c).

**Scope cuts, in order:** friend_pull lever and its probe/test; probe items 5 and 6 (keep tick cost under 1 ms); `first_mars_born_friendship_sol` stat; shrink `web` column and T11 to checks 1 and 4.
