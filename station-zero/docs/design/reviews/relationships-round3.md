# Round 3 reviews of relationships.md revision 5 (narrow questions, section 16)

## Emergence (Wright lens): agree with change
- Dropping the lonely_share lower bound: agree (a floor forces a hidden script; loneliness should come from personality). Keep 0.35 upper bound as a hard bound. Do not let the dropped floor hide a dead lonely signal (seed 1234 friend run, 0.000).
- friends_mean_max 12 to 15: agree for now, but a raw count means different things at different populations (seed 7 about 19% of the colony, seed 42 about 1%). Add two diagnostics: (1) selectivity ratio warm-third mean / cold-third mean >= 2.0 on seeds with friends_mean above 8 (current 6.6, 4.9, 2.5, 2.5, 2.3); (2) friend share of ever-co-present pairs <= about 0.35.
- room_rate 0.008 to 0.010: agree with a stop rule. Personality gap compresses (typical vs warm at 4 h: 93 vs 25 sols, 3.7x, to 45 vs 17, 2.6x). Stop rule: if warm/cold ratio < 2.0 on any seed, or seed 7's cold third passes about 10 friends, revert to 0.008 and fix the early-friendship target by the birth-relative restatement instead. Report friend count as a share of population as well.

## Feel (Barone lens): agree with change
- 0.010 pace is right for the first friend line (a childhood, not a day). Target: first friends/found_friend line by sol 55 on every seed, none before sol 25.
- Gate the late tail: probe check that found_friend lines per 5 sols over sols 150 to 299 do not exceed the sols 20 to 299 mean (else raise the 'new' bar, do not lower the rate).
- Count lines_dropped per kind; require 0 for found_friend on all five seeds.
- Optional idea, cut first: place sentence varying by hour of day.

## Clarity (Korppoo lens): acceptable to defer the packed-mirror change
- Cost is periodic, the speed readout reports the dip honestly, mirror saves only about 1.2 ms of about 6 ms.
- Additions: the view-step re-measure reports frame p95 and max split by 'frame contains a tick step', at pop above 120, while the camera moves, at fast speed and during long-absence catch-up; add a second trigger: any single frame over about 33 ms attributable to a tick step.
- Idea: if a remedy is needed, schedule the tick at the start of an advance slice (behaviour-identical); check against ages.md section 11.
