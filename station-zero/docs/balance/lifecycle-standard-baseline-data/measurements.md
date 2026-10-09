# Standard baseline measurement appendix

Exact values from the unchanged observer exports. Interpret with the [baseline report](../lifecycle-standard-baseline.md); legacy/vacuous verdicts are retained, not endorsed.

## Seed 42

| Target | Verdict | Value | Limit | Definition / note |
|---|---|---|---|---|
| L1 | FAIL | min adults 0 (first at sol 583) | >= 4 every sol |  |
| T1r | FAIL | min adults 0, final pop 0 | min adults >= 4 and final pop >= 7 |  |
| T2r | FAIL | unexplained 0, founder deaths 7 of 7, total deaths 17 | unexplained 0, founder deaths <= 2 | by cause {"thirst":17}; by stage/cause {"adult/thirst":7,"baby/thirst":10} |
| T3a | PASS | at_capacity 0, cooldown_violations 0 | both 0 |  |
| T3b | PASS | first birth sol 280 | 265..320 |  |
| T3c | PASS | pop@300 12 | >= 9 |  |
| T3d | FAIL | pop@1500 0 | 25..80 at the end |  |
| T3e | FAIL | births per complete window: c1[280,550)=7 c2[550,820)=3 c3[820,1090)=0 c4[1090,1360)=0 c5[1360,1630)=0 incomplete | >= 3 per complete 270-sol window | def: windows of 270 sols anchored on the first birth sol, window 1 included; incomplete tail not judged |
| T3f | REPORT | saturated sols (capacity - (pop+pending) <= 0) 27 of 1501 = 1.8%, longest saturated run 14 sols (ending sol 13) | reported |  |
| T4r | PASS | min O2 261.465000000022, min food 203.091499999978; min ice/being 0.00 (sol 371); thirst deaths 17 = 3.680 per 1000 being-sols; ice-dry sols per cohort window c1=6 c2=244 c3=270 c4=270 c5=141 | O2 and food never 0 (ice reported) |  |
| T5 | PASS | demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 5 (<=15) | kept as written |  |
| T6a | PASS | longest saturated-housing run 14 sols | <= 60 sols | def: housing 'waits' = consecutive sols with capacity - (pop+pending) <= 0; the spec text does not say whether free adults must exist, so it is the plain saturation run |
| T6b | FAIL | buildings finished per 270-sol window from sol 0: 13,3,0,0,0 | >= 1 each |  |
| T6c | REPORT | crew-limited share 87.36% | reported |  |
| T7r | PASS | trips 387 over 3449 adult-sols = 0.1122 per adult-sol; exhausted 128 = 0.0371 per adult-sol; turn_backs_air 0; reachable>=2 100.0% | 0.05..0.30 trips per adult-sol; turn_backs_air 0; reachable >= 95% |  |
| T8r | FAIL | adult row avg energy 0.0..58.3, adult row asleep 0.0..11.4%, max sleep (all beings, run) 8.8 h | energy 40..90, asleep 5..30%, max sleep <= 18 h | def: adults only, sampled once per sim hour (not every step), rows every 30 sols as the table; max sleep is the run-wide all-beings figure (not split by stage) |
| T10r | PASS | Settlement sol 290, projected age changes 1, fall-backs [] | Settlement 265..700 (4 of 5 seeds), changes <= 4 |  |
| T11r | PASS | final pop 0; adults with friend_count 0 over last 50 readings: max 0 mean 0.00; module lonely share last 50 mean 0.000; toddler-and-up with 0 friends: mean 0.00, share of those who can bond 0.000 | pop < 20: <= 2 such adults on the last 50 readings; pop >= 20: lonely share <= 0.35 | def: 'no more than 2 on the last 50 readings' read as the max over those readings; module share is over all beings incl. babies |
| T11b | FAIL | friends_mean 0.00, first_friendship_sol 83, lines_dropped 0 | friends_mean 1.0..15.0, first friendship not null |  |
| T12r | PASS | council entries []; max adult voices over run 7 (voices_min 12) | structure ok; no entry with voices < voices_min |  |
| Circ | PASS | circles lines 2 (circles_few 2), at sols 340,440 | >= 1 circles_few and <= 2 circles per term | def: circles_max read from data/council.json (lines.circles_max if present, else 2); 'per term' applied to the whole run (no Council term exists) |
| L2 | PASS | max (pop-adults)/adults 3.00 (sol 581); ice/being c3 0.00 -> c4 0.00; food/being c3 900.00 -> c4 900.00 | ratio <= 6 every sol; ice and food per being not falling over the last 2 complete cohort windows | def: 'not falling' = mean of the later window >= mean of the earlier, no tolerance |
| L3 | FAIL | first-cohort conception span 269 sols (sols 13..282), births c1 7, c2 3 | span <= 60 sols; c2 births >= 40% of c1 |  |
| L4 | PASS | capacity >= pop+pending on 1501 of 1501 sols = 100.0% | >= 90% of sols |  |
| L5 | PASS | stage counts summed to pop on 1501 sols, 466 being-age checks (every 10th sol), 0 violations | 0 violations |  |

Legacy relationships probe targets (not the restated Standard targets):

| Target | Raw result | Measurement |
|---|---|---|
| R10_selectivity_ratio_stop | False | ratio 1.00 = warm -1.00 / cold -1.00 (min 2.0) |
| R11_coldest_third_mean_stop | True | coldest-third mean -1.00 (max 10.0) |
| R12_first_newcomer_line_lower_bound | True | first newcomer line sol 83 (judged: at or after 25; reported: by 55, OVER), first birth 280 |
| R13_found_friend_late_tail_ceiling | True | tail (150..299) 0.03 per 5 sols (7 lines; max 3.0); reported: mean (20..299) 0.02 (7 lines), ratio 1.10, births in 150..299 10, found_friend lines per birth 0.70 |
| R14_no_dropped_friend_events | True | lines_dropped 0 (total; lines_dropped_by_type not built) |
| R1_kin_newborn_median_wait | True | kin newborns median birth-to-first-friend 6.0 sols (max 30), resolved 9, unresolved 1 (left out); colony-first gap reported only: first birth 280, first_friendship_sol 83, gap -197 |
| R2_first_line_lt_30 | True | first relationship line sol 24 (first non-grief 24) |
| R3_lonely_window_mean_le_max | True | mean of last 50 readings 0.000 (max 0.35); D3 DEAD |
| R4_friends_mean_300_in_band | False | friends_mean -1.00 (band 1.0 to 15.0) |
| R5_dropped_lt_5pct | True | dropped 0 of 19 capped-kind events (logged 19 + dropped 0) = 0.00% |
| R6_lines_ge_1_per_5_sols_20_300 | False | 0.06 lines per 5 sols (19 lines in sols 20 to 299); zero-line 5-sol blocks 280 of 296 |
| R7_warmest_third_more_friends | False | warm -1.00 vs cold -1.00 |

## Seed 7

| Target | Verdict | Value | Limit | Definition / note |
|---|---|---|---|---|
| L1 | FAIL | min adults 0 (first at sol 307) | >= 4 every sol |  |
| T1r | FAIL | min adults 0, final pop 0 | min adults >= 4 and final pop >= 7 |  |
| T2r | FAIL | unexplained 0, founder deaths 7 of 7, total deaths 12 | unexplained 0, founder deaths <= 2 | by cause {"thirst":12}; by stage/cause {"adult/thirst":7,"baby/thirst":5} |
| T3a | PASS | at_capacity 0, cooldown_violations 0 | both 0 |  |
| T3b | PASS | first birth sol 286 | 265..320 |  |
| T3c | PASS | pop@300 9 | >= 9 |  |
| T3d | FAIL | pop@1500 0 | 25..80 at the end |  |
| T3e | FAIL | births per complete window: c1[286,556)=5 c2[556,826)=0 c3[826,1096)=0 c4[1096,1366)=0 c5[1366,1636)=0 incomplete | >= 3 per complete 270-sol window | def: windows of 270 sols anchored on the first birth sol, window 1 included; incomplete tail not judged |
| T3f | REPORT | saturated sols (capacity - (pop+pending) <= 0) 193 of 1501 = 12.9%, longest saturated run 173 sols (ending sol 200) | reported |  |
| T4r | PASS | min O2 261.465000000022, min food 203.091499999978; min ice/being 0.00 (sol 299); thirst deaths 12 = 5.474 per 1000 being-sols; ice-dry sols per cohort window c1=256 c2=270 c3=270 c4=270 c5=135 | O2 and food never 0 (ice reported) |  |
| T5 | PASS | demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 10 (<=15) | kept as written |  |
| T6a | FAIL | longest saturated-housing run 173 sols | <= 60 sols | def: housing 'waits' = consecutive sols with capacity - (pop+pending) <= 0; the spec text does not say whether free adults must exist, so it is the plain saturation run |
| T6b | FAIL | buildings finished per 270-sol window from sol 0: 12,0,0,0,0 | >= 1 each |  |
| T6c | REPORT | crew-limited share 91.38% | reported |  |
| T7r | PASS | trips 203 over 2131 adult-sols = 0.0953 per adult-sol; exhausted 108 = 0.0507 per adult-sol; turn_backs_air 0; reachable>=2 100.0% | 0.05..0.30 trips per adult-sol; turn_backs_air 0; reachable >= 95% |  |
| T8r | FAIL | adult row avg energy 0.0..57.2, adult row asleep 0.0..11.7%, max sleep (all beings, run) 8.8 h | energy 40..90, asleep 5..30%, max sleep <= 18 h | def: adults only, sampled once per sim hour (not every step), rows every 30 sols as the table; max sleep is the run-wide all-beings figure (not split by stage) |
| T10r | FAIL | Settlement sol <null>, projected age changes 0, fall-backs [] | Settlement 265..700 (4 of 5 seeds), changes <= 4 |  |
| T11r | PASS | final pop 0; adults with friend_count 0 over last 50 readings: max 0 mean 0.00; module lonely share last 50 mean 0.000; toddler-and-up with 0 friends: mean 0.00, share of those who can bond 0.000 | pop < 20: <= 2 such adults on the last 50 readings; pop >= 20: lonely share <= 0.35 | def: 'no more than 2 on the last 50 readings' read as the max over those readings; module share is over all beings incl. babies |
| T11b | FAIL | friends_mean 0.00, first_friendship_sol 99, lines_dropped 0 | friends_mean 1.0..15.0, first friendship not null |  |
| T12r | PASS | council entries []; max adult voices over run 0 (voices_min 12) | structure ok; no entry with voices < voices_min |  |
| Circ | NYJ | circles lines 0 (circles_few 0), at sols  | no Settlement reached |  |
| L2 | PASS | max (pop-adults)/adults 0.75 (sol 303); ice/being c3 0.00 -> c4 0.00; food/being c3 660.00 -> c4 660.00 | ratio <= 6 every sol; ice and food per being not falling over the last 2 complete cohort windows | def: 'not falling' = mean of the later window >= mean of the earlier, no tolerance |
| L3 | FAIL | first-cohort conception span 8 sols (sols 19..27), births c1 5, c2 0 | span <= 60 sols; c2 births >= 40% of c1 |  |
| L4 | PASS | capacity >= pop+pending on 1501 of 1501 sols = 100.0% | >= 90% of sols |  |
| L5 | PASS | stage counts summed to pop on 1501 sols, 221 being-age checks (every 10th sol), 0 violations | 0 violations |  |

Legacy relationships probe targets (not the restated Standard targets):

| Target | Raw result | Measurement |
|---|---|---|
| R10_selectivity_ratio_stop | False | ratio 1.00 = warm -1.00 / cold -1.00 (min 2.0) |
| R11_coldest_third_mean_stop | True | coldest-third mean -1.00 (max 10.0) |
| R12_first_newcomer_line_lower_bound | True | first newcomer line sol 99 (judged: at or after 25; reported: by 55, OVER), first birth 286 |
| R13_found_friend_late_tail_ceiling | True | tail (150..299) 0.01 per 5 sols (3 lines; max 3.0); reported: mean (20..299) 0.01 (4 lines), ratio 0.82, births in 150..299 5, found_friend lines per birth 0.60 |
| R14_no_dropped_friend_events | True | lines_dropped 0 (total; lines_dropped_by_type not built) |
| R1_kin_newborn_median_wait | True | kin newborns median birth-to-first-friend 5.0 sols (max 30), resolved 5, unresolved 0 (left out); colony-first gap reported only: first birth 286, first_friendship_sol 99, gap -187 |
| R2_first_line_lt_30 | True | first relationship line sol 16 (first non-grief 16) |
| R3_lonely_window_mean_le_max | True | mean of last 50 readings 0.000 (max 0.35); D3 DEAD |
| R4_friends_mean_300_in_band | False | friends_mean -1.00 (band 1.0 to 15.0) |
| R5_dropped_lt_5pct | True | dropped 0 of 11 capped-kind events (logged 11 + dropped 0) = 0.00% |
| R6_lines_ge_1_per_5_sols_20_300 | False | 0.03 lines per 5 sols (10 lines in sols 20 to 299); zero-line 5-sol blocks 288 of 296 |
| R7_warmest_third_more_friends | False | warm -1.00 vs cold -1.00 |

## Seed 99

| Target | Verdict | Value | Limit | Definition / note |
|---|---|---|---|---|
| L1 | FAIL | min adults 0 (first at sol 631) | >= 4 every sol |  |
| T1r | FAIL | min adults 0, final pop 0 | min adults >= 4 and final pop >= 7 |  |
| T2r | FAIL | unexplained 0, founder deaths 7 of 7, total deaths 15 | unexplained 0, founder deaths <= 2 | by cause {"thirst":15}; by stage/cause {"adult/thirst":7,"baby/thirst":8} |
| T3a | PASS | at_capacity 0, cooldown_violations 0 | both 0 |  |
| T3b | PASS | first birth sol 292 | 265..320 |  |
| T3c | PASS | pop@300 11 | >= 9 |  |
| T3d | FAIL | pop@1500 0 | 25..80 at the end |  |
| T3e | FAIL | births per complete window: c1[292,562)=6 c2[562,832)=2 c3[832,1102)=0 c4[1102,1372)=0 c5[1372,1642)=0 incomplete | >= 3 per complete 270-sol window | def: windows of 270 sols anchored on the first birth sol, window 1 included; incomplete tail not judged |
| T3f | REPORT | saturated sols (capacity - (pop+pending) <= 0) 136 of 1501 = 9.1%, longest saturated run 96 sols (ending sol 132) | reported |  |
| T4r | PASS | min O2 262.465000000022, min food 203.091499999978; min ice/being 0.00 (sol 328); thirst deaths 15 = 3.429 per 1000 being-sols; ice-dry sols per cohort window c1=5 c2=205 c3=270 c4=270 c5=129 | O2 and food never 0 (ice reported) |  |
| T5 | PASS | demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 11 (<=15) | kept as written |  |
| T6a | FAIL | longest saturated-housing run 96 sols | <= 60 sols | def: housing 'waits' = consecutive sols with capacity - (pop+pending) <= 0; the spec text does not say whether free adults must exist, so it is the plain saturation run |
| T6b | FAIL | buildings finished per 270-sol window from sol 0: 13,0,0,0,0 | >= 1 each |  |
| T6c | REPORT | crew-limited share 95.24% | reported |  |
| T7r | PASS | trips 356 over 3259 adult-sols = 0.1092 per adult-sol; exhausted 118 = 0.0362 per adult-sol; turn_backs_air 0; reachable>=2 100.0% | 0.05..0.30 trips per adult-sol; turn_backs_air 0; reachable >= 95% |  |
| T8r | FAIL | adult row avg energy 0.0..57.1, adult row asleep 0.0..11.3%, max sleep (all beings, run) 8.8 h | energy 40..90, asleep 5..30%, max sleep <= 18 h | def: adults only, sampled once per sim hour (not every step), rows every 30 sols as the table; max sleep is the run-wide all-beings figure (not split by stage) |
| T10r | PASS | Settlement sol 309, projected age changes 2, fall-backs [sol 342 (ice)] | Settlement 265..700 (4 of 5 seeds), changes <= 4 |  |
| T11r | PASS | final pop 0; adults with friend_count 0 over last 50 readings: max 0 mean 0.00; module lonely share last 50 mean 0.000; toddler-and-up with 0 friends: mean 0.00, share of those who can bond 0.000 | pop < 20: <= 2 such adults on the last 50 readings; pop >= 20: lonely share <= 0.35 | def: 'no more than 2 on the last 50 readings' read as the max over those readings; module share is over all beings incl. babies |
| T11b | FAIL | friends_mean 0.00, first_friendship_sol 137, lines_dropped 0 | friends_mean 1.0..15.0, first friendship not null |  |
| T12r | PASS | council entries []; max adult voices over run 7 (voices_min 12) | structure ok; no entry with voices < voices_min |  |
| Circ | FAIL | circles lines 0 (circles_few 0), at sols  | >= 1 circles_few and <= 2 circles per term | def: circles_max read from data/council.json (lines.circles_max if present, else 2); 'per term' applied to the whole run (no Council term exists) |
| L2 | PASS | max (pop-adults)/adults 3.00 (sol 629); ice/being c3 0.00 -> c4 0.00; food/being c3 900.00 -> c4 900.00 | ratio <= 6 every sol; ice and food per being not falling over the last 2 complete cohort windows | def: 'not falling' = mean of the later window >= mean of the earlier, no tolerance |
| L3 | FAIL | first-cohort conception span 110 sols (sols 26..136), births c1 6, c2 2 | span <= 60 sols; c2 births >= 40% of c1 |  |
| L4 | PASS | capacity >= pop+pending on 1501 of 1501 sols = 100.0% | >= 90% of sols |  |
| L5 | PASS | stage counts summed to pop on 1501 sols, 443 being-age checks (every 10th sol), 0 violations | 0 violations |  |

Legacy relationships probe targets (not the restated Standard targets):

| Target | Raw result | Measurement |
|---|---|---|
| R10_selectivity_ratio_stop | False | ratio 1.00 = warm -1.00 / cold -1.00 (min 2.0) |
| R11_coldest_third_mean_stop | True | coldest-third mean -1.00 (max 10.0) |
| R12_first_newcomer_line_lower_bound | True | first newcomer line sol 137 (judged: at or after 25; reported: by 55, OVER), first birth 292 |
| R13_found_friend_late_tail_ceiling | True | tail (150..299) 0.04 per 5 sols (11 lines; max 3.0); reported: mean (20..299) 0.04 (11 lines), ratio 1.10, births in 150..299 8, found_friend lines per birth 1.38 |
| R14_no_dropped_friend_events | True | lines_dropped 0 (total; lines_dropped_by_type not built) |
| R1_kin_newborn_median_wait | True | kin newborns median birth-to-first-friend 5.0 sols (max 30), resolved 8, unresolved 0 (left out); colony-first gap reported only: first birth 292, first_friendship_sol 137, gap -155 |
| R2_first_line_lt_30 | True | first relationship line sol 19 (first non-grief 19) |
| R3_lonely_window_mean_le_max | True | mean of last 50 readings 0.000 (max 0.35); D3 DEAD |
| R4_friends_mean_300_in_band | False | friends_mean -1.00 (band 1.0 to 15.0) |
| R5_dropped_lt_5pct | True | dropped 0 of 19 capped-kind events (logged 19 + dropped 0) = 0.00% |
| R6_lines_ge_1_per_5_sols_20_300 | False | 0.06 lines per 5 sols (18 lines in sols 20 to 299); zero-line 5-sol blocks 280 of 296 |
| R7_warmest_third_more_friends | False | warm -1.00 vs cold -1.00 |

## Seed 1234

| Target | Verdict | Value | Limit | Definition / note |
|---|---|---|---|---|
| L1 | FAIL | min adults 0 (first at sol 704) | >= 4 every sol |  |
| T1r | FAIL | min adults 0, final pop 0 | min adults >= 4 and final pop >= 7 |  |
| T2r | FAIL | unexplained 0, founder deaths 7 of 7, total deaths 17 | unexplained 0, founder deaths <= 2 | by cause {"thirst":17}; by stage/cause {"adult/thirst":7,"baby/thirst":8,"toddler/thirst":2} |
| T3a | PASS | at_capacity 0, cooldown_violations 0 | both 0 |  |
| T3b | PASS | first birth sol 288 | 265..320 |  |
| T3c | PASS | pop@300 10 | >= 9 |  |
| T3d | FAIL | pop@1500 0 | 25..80 at the end |  |
| T3e | FAIL | births per complete window: c1[288,558)=6 c2[558,828)=4 c3[828,1098)=0 c4[1098,1368)=0 c5[1368,1638)=0 incomplete | >= 3 per complete 270-sol window | def: windows of 270 sols anchored on the first birth sol, window 1 included; incomplete tail not judged |
| T3f | REPORT | saturated sols (capacity - (pop+pending) <= 0) 83 of 1501 = 5.5%, longest saturated run 63 sols (ending sol 108) | reported |  |
| T4r | PASS | min O2 262.465000000022, min food 203.091499999978; min ice/being 0.00 (sol 521); thirst deaths 17 = 2.646 per 1000 being-sols; ice-dry sols per cohort window c1=4 c2=129 c3=270 c4=270 c5=133 | O2 and food never 0 (ice reported) |  |
| T5 | PASS | demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 11 (<=15) | kept as written |  |
| T6a | FAIL | longest saturated-housing run 63 sols | <= 60 sols | def: housing 'waits' = consecutive sols with capacity - (pop+pending) <= 0; the spec text does not say whether free adults must exist, so it is the plain saturation run |
| T6b | FAIL | buildings finished per 270-sol window from sol 0: 12,6,0,0,0 | >= 1 each |  |
| T6c | REPORT | crew-limited share 74.54% | reported |  |
| T7r | PASS | trips 523 over 4340 adult-sols = 0.1205 per adult-sol; exhausted 206 = 0.0475 per adult-sol; turn_backs_air 0; reachable>=2 100.0% | 0.05..0.30 trips per adult-sol; turn_backs_air 0; reachable >= 95% |  |
| T8r | FAIL | adult row avg energy 0.0..57.9, adult row asleep 0.0..11.6%, max sleep (all beings, run) 8.8 h | energy 40..90, asleep 5..30%, max sleep <= 18 h | def: adults only, sampled once per sim hour (not every step), rows every 30 sols as the table; max sleep is the run-wide all-beings figure (not split by stage) |
| T10r | PASS | Settlement sol 312, projected age changes 1, fall-backs [] | Settlement 265..700 (4 of 5 seeds), changes <= 4 |  |
| T11r | PASS | final pop 0; adults with friend_count 0 over last 50 readings: max 0 mean 0.00; module lonely share last 50 mean 0.000; toddler-and-up with 0 friends: mean 0.00, share of those who can bond 0.000 | pop < 20: <= 2 such adults on the last 50 readings; pop >= 20: lonely share <= 0.35 | def: 'no more than 2 on the last 50 readings' read as the max over those readings; module share is over all beings incl. babies |
| T11b | FAIL | friends_mean 0.00, first_friendship_sol 250, lines_dropped 0 | friends_mean 1.0..15.0, first friendship not null |  |
| T12r | PASS | council entries []; max adult voices over run 7 (voices_min 12) | structure ok; no entry with voices < voices_min |  |
| Circ | PASS | circles lines 2 (circles_few 2), at sols 362,462 | >= 1 circles_few and <= 2 circles per term | def: circles_max read from data/council.json (lines.circles_max if present, else 2); 'per term' applied to the whole run (no Council term exists) |
| L2 | PASS | max (pop-adults)/adults 2.00 (sol 690); ice/being c3 0.00 -> c4 0.00; food/being c3 1260.00 -> c4 1260.00 | ratio <= 6 every sol; ice and food per being not falling over the last 2 complete cohort windows | def: 'not falling' = mean of the later window >= mean of the earlier, no tolerance |
| L3 | FAIL | first-cohort conception span 89 sols (sols 21..110), births c1 6, c2 4 | span <= 60 sols; c2 births >= 40% of c1 |  |
| L4 | PASS | capacity >= pop+pending on 1501 of 1501 sols = 100.0% | >= 90% of sols |  |
| L5 | PASS | stage counts summed to pop on 1501 sols, 645 being-age checks (every 10th sol), 0 violations | 0 violations |  |

Legacy relationships probe targets (not the restated Standard targets):

| Target | Raw result | Measurement |
|---|---|---|
| R10_selectivity_ratio_stop | False | ratio 1.00 = warm -1.00 / cold -1.00 (min 2.0) |
| R11_coldest_third_mean_stop | True | coldest-third mean -1.00 (max 10.0) |
| R12_first_newcomer_line_lower_bound | True | first newcomer line sol 250 (judged: at or after 25; reported: by 55, OVER), first birth 288 |
| R13_found_friend_late_tail_ceiling | True | tail (150..299) 0.03 per 5 sols (8 lines; max 3.0); reported: mean (20..299) 0.03 (8 lines), ratio 1.10, births in 150..299 10, found_friend lines per birth 0.80 |
| R14_no_dropped_friend_events | True | lines_dropped 0 (total; lines_dropped_by_type not built) |
| R1_kin_newborn_median_wait | True | kin newborns median birth-to-first-friend 5.5 sols (max 30), resolved 10, unresolved 0 (left out); colony-first gap reported only: first birth 288, first_friendship_sol 250, gap -38 |
| R2_first_line_lt_30 | True | first relationship line sol 21 (first non-grief 21) |
| R3_lonely_window_mean_le_max | True | mean of last 50 readings 0.000 (max 0.35); D3 DEAD |
| R4_friends_mean_300_in_band | False | friends_mean -1.00 (band 1.0 to 15.0) |
| R5_dropped_lt_5pct | True | dropped 0 of 18 capped-kind events (logged 18 + dropped 0) = 0.00% |
| R6_lines_ge_1_per_5_sols_20_300 | False | 0.06 lines per 5 sols (18 lines in sols 20 to 299); zero-line 5-sol blocks 281 of 296 |
| R7_warmest_third_more_friends | False | warm -1.00 vs cold -1.00 |

## Seed 2026

| Target | Verdict | Value | Limit | Definition / note |
|---|---|---|---|---|
| L1 | FAIL | min adults 0 (first at sol 658) | >= 4 every sol |  |
| T1r | FAIL | min adults 0, final pop 0 | min adults >= 4 and final pop >= 7 |  |
| T2r | FAIL | unexplained 0, founder deaths 7 of 7, total deaths 15 | unexplained 0, founder deaths <= 2 | by cause {"thirst":15}; by stage/cause {"adult/thirst":7,"baby/thirst":8} |
| T3a | PASS | at_capacity 0, cooldown_violations 0 | both 0 |  |
| T3b | PASS | first birth sol 285 | 265..320 |  |
| T3c | PASS | pop@300 12 | >= 9 |  |
| T3d | FAIL | pop@1500 0 | 25..80 at the end |  |
| T3e | FAIL | births per complete window: c1[285,555)=5 c2[555,825)=3 c3[825,1095)=0 c4[1095,1365)=0 c5[1365,1635)=0 incomplete | >= 3 per complete 270-sol window | def: windows of 270 sols anchored on the first birth sol, window 1 included; incomplete tail not judged |
| T3f | REPORT | saturated sols (capacity - (pop+pending) <= 0) 375 of 1501 = 25.0%, longest saturated run 314 sols (ending sol 337) | reported |  |
| T4r | PASS | min O2 261.465000000022, min food 203.091499999978; min ice/being 0.00 (sol 391); thirst deaths 15 = 3.165 per 1000 being-sols; ice-dry sols per cohort window c1=5 c2=171 c3=270 c4=270 c5=136 | O2 and food never 0 (ice reported) |  |
| T5 | FAIL | demand>supply 0.69% of steps (<=10), max shorts/sol 1 (<=2), max offline 254.4 h (<=24.7), first new reactor sol 13 (<=15) | kept as written |  |
| T6a | FAIL | longest saturated-housing run 314 sols | <= 60 sols | def: housing 'waits' = consecutive sols with capacity - (pop+pending) <= 0; the spec text does not say whether free adults must exist, so it is the plain saturation run |
| T6b | FAIL | buildings finished per 270-sol window from sol 0: 11,3,1,0,0 | >= 1 each |  |
| T6c | REPORT | crew-limited share 76.07% | reported |  |
| T7r | PASS | trips 435 over 4065 adult-sols = 0.1070 per adult-sol; exhausted 224 = 0.0551 per adult-sol; turn_backs_air 0; reachable>=2 100.0% | 0.05..0.30 trips per adult-sol; turn_backs_air 0; reachable >= 95% |  |
| T8r | FAIL | adult row avg energy 0.0..57.2, adult row asleep 0.0..11.3%, max sleep (all beings, run) 8.8 h | energy 40..90, asleep 5..30%, max sleep <= 18 h | def: adults only, sampled once per sim hour (not every step), rows every 30 sols as the table; max sleep is the run-wide all-beings figure (not split by stage) |
| T10r | PASS | Settlement sol 328, projected age changes 2, fall-backs [sol 399 (ice)] | Settlement 265..700 (4 of 5 seeds), changes <= 4 |  |
| T11r | PASS | final pop 0; adults with friend_count 0 over last 50 readings: max 0 mean 0.00; module lonely share last 50 mean 0.000; toddler-and-up with 0 friends: mean 0.00, share of those who can bond 0.000 | pop < 20: <= 2 such adults on the last 50 readings; pop >= 20: lonely share <= 0.35 | def: 'no more than 2 on the last 50 readings' read as the max over those readings; module share is over all beings incl. babies |
| T11b | FAIL | friends_mean 0.00, first_friendship_sol 160, lines_dropped 0 | friends_mean 1.0..15.0, first friendship not null |  |
| T12r | PASS | council entries []; max adult voices over run 7 (voices_min 12) | structure ok; no entry with voices < voices_min |  |
| Circ | PASS | circles lines 1 (circles_few 1), at sols 378 | >= 1 circles_few and <= 2 circles per term | def: circles_max read from data/council.json (lines.circles_max if present, else 2); 'per term' applied to the whole run (no Council term exists) |
| L2 | PASS | max (pop-adults)/adults 1.00 (sol 653); ice/being c3 0.00 -> c4 0.00; food/being c3 1020.00 -> c4 1020.00 | ratio <= 6 every sol; ice and food per being not falling over the last 2 complete cohort windows | def: 'not falling' = mean of the later window >= mean of the earlier, no tolerance |
| L3 | PASS | first-cohort conception span 5 sols (sols 18..23), births c1 5, c2 3 | span <= 60 sols; c2 births >= 40% of c1 |  |
| L4 | PASS | capacity >= pop+pending on 1501 of 1501 sols = 100.0% | >= 90% of sols |  |
| L5 | PASS | stage counts summed to pop on 1501 sols, 477 being-age checks (every 10th sol), 0 violations | 0 violations |  |

Legacy relationships probe targets (not the restated Standard targets):

| Target | Raw result | Measurement |
|---|---|---|
| R10_selectivity_ratio_stop | False | ratio 1.00 = warm -1.00 / cold -1.00 (min 2.0) |
| R11_coldest_third_mean_stop | True | coldest-third mean -1.00 (max 10.0) |
| R12_first_newcomer_line_lower_bound | True | first newcomer line sol 160 (judged: at or after 25; reported: by 55, OVER), first birth 285 |
| R13_found_friend_late_tail_ceiling | True | tail (150..299) 0.03 per 5 sols (7 lines; max 3.0); reported: mean (20..299) 0.02 (7 lines), ratio 1.10, births in 150..299 8, found_friend lines per birth 0.88 |
| R14_no_dropped_friend_events | True | lines_dropped 0 (total; lines_dropped_by_type not built) |
| R1_kin_newborn_median_wait | True | kin newborns median birth-to-first-friend 5.5 sols (max 30), resolved 8, unresolved 0 (left out); colony-first gap reported only: first birth 285, first_friendship_sol 160, gap -125 |
| R2_first_line_lt_30 | True | first relationship line sol 14 (first non-grief 14) |
| R3_lonely_window_mean_le_max | True | mean of last 50 readings 0.000 (max 0.35); D3 DEAD |
| R4_friends_mean_300_in_band | False | friends_mean -1.00 (band 1.0 to 15.0) |
| R5_dropped_lt_5pct | True | dropped 0 of 17 capped-kind events (logged 17 + dropped 0) = 0.00% |
| R6_lines_ge_1_per_5_sols_20_300 | False | 0.05 lines per 5 sols (16 lines in sols 20 to 299); zero-line 5-sol blocks 283 of 296 |
| R7_warmest_third_more_friends | False | warm -1.00 vs cold -1.00 |
