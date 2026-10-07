# Review of council.md rev 1: designer-emergence (Wright lens)

Verdict: hidden stance, personality as selector, hardship interplay and anti-rubber-stamp rules work; three must-fixes on lean dominance, the trust gate and one-matter thinness. (Spec-only review; sim behaviour unverified.)

**Must-fix**
- M1. Lean dominated by colony terms (personal about +-0.15 vs size up to +0.3 and hard up to -0.8, undecided band +-0.1): everyone yes or everyone no; C5/C6 pass by luck. Make colony terms scale personal gains (e.g. lean_i = ambition_gain x (ambition_i - 0.5) x (1 + size) - caution_gain x (caution_i - 0.5) x (1 + hard)) and/or give each voice its own stake (own crowding, energy/hunger, recent family birth, friend lost). SIZE-DOMINANT in the probe means rewrite the formula, not retune weights.
- M2. Trust gate: probably a timer on early seeds (founders' crew) and a no-op later (giant component forms easily); split rarely fires. Add a second cut (e.g. at least 0.6 of voices have 2+ voice friends that are not crew/kin pairs, or count non-crew pairs after sol 40); replay in probe before sign-off. Check voices >= 12 is reachable by sol 83; keep the "which clause passed last" row.
- M3. One matter then silence (~170 sols after a pledge). Make proposals a topic-generic list now and ship dome only; leans to O5 (b): water rule built shipped off.

**Should-fix**
- S1. Gatherings are decorative: weight sway for attendees (e.g. x1.5 toward the speaker) and let the proposer's standing (voice friend count) weight their pull.
- S2. Carry/pledge lines name the cause from the largest positive term ("with stone in store", "the modules are full").
- S3. Flicker near ice thresholds: hysteresis for an open proposal's "no" (no_below -0.15) or require the hard window to have recovered.
- S4. Adoption rule for the lonely pull: also require improvement on at least 10 of 15 seeds or report standard error; gate on newborn median breadth not dropping; check the pull doesn't turn the trust gate into a pure timer.

**Ideas:** reneging after N hard sols (later); swing line when camps cross, naming who changed sides; bridge person line; Send a sign lever acting per temperament.

**Worst loop:** hardship -> set aside -> Landing -> same hardship on return ("too thirsty to dream"), legible, not a death spiral. Real danger: a future gathering pull (more friends -> earlier Council -> more meetings); bound it.

**Owner questions:** O1 (a) with M2's second cut probed; O2 (a); O3 (a) with S4; O4 (a); O5 (b) as machinery only (topic-generic, water rule shipped off).
