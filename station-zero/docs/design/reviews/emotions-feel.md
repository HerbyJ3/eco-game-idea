# Review of emotions.md rev 1: designer-feel (Barone lens)

**Good:** one number/baseline/rate, no meter; temperament read through how long moods last; grief -> quiet -> relief arc ("has gone quiet since ... died" / "is smiling again"); the K1 sentence; positive-only company and no loneliness term; hard seasons where slow Deimos go low first.

**Blocking**
1. Nature sentences: really 3 of 12 signs, and "slow to shake off a mood" is unreachable (mutable water is caught first). Re-threshold so each sentence has its own signs (e.g. slow at half-life >= 7.0 and not base_lo: mutable earth, air, fire); avoid float-equality traps (0.145 / -0.165, or compare sign indices); add a reachability test.
2. A quiet line dropped by the cap sets mood_down_t, so "smiling again" can appear without a logged quiet (breaks T13(3), test 19). A dropped quiet changes no state and is offered again next tick; order candidates by highest bond to the dead, then lowest id (not id alone).
3. Some whys can't appear: lapse -0.05 vs min_push 0.05 (set lapse -0.06 or min_push 0.04); state that hard_sol, company and age pushes are exempt from min_push and set only when no why exists and abs(d) >= 0.10.

**Should-fix**
4. Joy is starved: raise birth_parent to ~+0.20 (light band alone); close to +0.18 if "lit up" never occurs; bright stays rare by design.
5. Energy effect is invisible and the only part that moves the ages' calm/rested clauses: move it from cut 7 to cut 2; ship without it unless the probe shows it harmless.
6. Omit the "much as usual" line when even with no why.
7. 2-3 deterministic wording variants (by id modulo count) for relief and quiet lines; "They are mourning" in the first sol, "still" later.
8. Heavy band wording step down ("{name} is struggling."); cut age_up/age_down whys first.

**Answers:** rhythm watchable (1.6 sols ~13 min, 10 sols ~80 min); lower the slow half-life ceiling to ~6.5 sols; one mood line per sol is right. Company worth it narrowly (cut 2). Protect grief -> quiet -> relief, then K1. If time runs out, pushes = friend, close, grief, hard_sol, birth_parent.

**Owner questions:** Q1 (a) after fix 1 (idea: show the nature sentence only after a recorded quiet episode); (b) acceptable if fix 1 is costly. Q2 (a). Q3 (a).
