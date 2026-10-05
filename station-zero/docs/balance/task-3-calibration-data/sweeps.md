Godot Engine v4.5.stable.official.876b29033 - https://godotengine.org

# sweeps: one parameter changed per row, all else as shipped; replayed from recorded per-sol inputs; seeds [42, 7, 99, 1234, 2026]
| parameter = value | seed 42 | seed 7 | seed 99 | seed 1234 | seed 2026 |
|---|---|---|---|---|---|
| ages.sample.window_sols = 30 | settle never; 0 chg; gap -; - | settle 72; 1 chg; gap -; S@72 | settle 67; 2 chg; gap 103; S@67 L@170(ice) | settle 78; 1 chg; gap -; S@78 | settle 207; 1 chg; gap -; S@207 |
| ages.sample.window_sols = 40 (shipped) | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.sample.window_sols = 50 | settle never; 0 chg; gap -; - | settle 84; 1 chg; gap -; S@84 | settle 78; 2 chg; gap 100; S@78 L@178(ice) | settle 94; 1 chg; gap -; S@94 | settle 225; 1 chg; gap -; S@225 |
| ages.exit.ok_share_below = 0.5 | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 103; S@75 L@178(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.exit.ok_share_below = 0.6 (shipped) | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.exit.ok_share_below = 0.7 | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 95; S@75 L@170(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.min_dwell_sols = 10 | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.min_dwell_sols = 20 (shipped) | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.min_dwell_sols = 30 | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.sample.ice_min_sols = 1 | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 172; S@75 L@247(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.sample.ice_min_sols = 2 (shipped) | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.sample.ice_min_sols = 3 | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 96; S@75 L@171(ice) | settle 85; 1 chg; gap -; S@85 | settle 217; 1 chg; gap -; S@217 |
| ages.sample.rested_share_min = 0.5 | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 68; 2 chg; gap 106; S@68 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.sample.rested_share_min = 0.7 (shipped) | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.sample.rested_share_min = 0.9 | settle never; 0 chg; gap -; - | settle never; 0 chg; gap -; - | settle never; 0 chg; gap -; - | settle never; 0 chg; gap -; - | settle never; 0 chg; gap -; - |
| ages.sample.distress_share_max = 0.05 [extra] | settle never; 0 chg; gap -; - | settle 83; 1 chg; gap -; S@83 | settle 143; 2 chg; gap 31; S@143 L@174(ice) | settle 250; 1 chg; gap -; S@250 | settle 236; 2 chg; gap 60; S@236 L@296(unrest) |
| ages.sample.distress_share_max = 0.1 (shipped) [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.sample.distress_share_max = 0.2 [extra] | settle 67; 2 chg; gap 146; S@67 L@213(ice) | settle 58; 1 chg; gap -; S@58 | settle 54; 2 chg; gap 120; S@54 L@174(ice) | settle 65; 1 chg; gap -; S@65 | settle 53; 1 chg; gap -; S@53 |
| ages.entry.mars_born_homes_min = 1 [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.entry.mars_born_homes_min = 2 (shipped) [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.entry.mars_born_homes_min = 3 [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.entry.mars_born_min = 3 [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.entry.mars_born_min = 5 (shipped) [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.entry.mars_born_min = 8 [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.entry.ok_share = 0.8 [extra] | settle 92; 2 chg; gap 61; S@92 L@153(ice) | settle 70; 1 chg; gap -; S@70 | settle 62; 2 chg; gap 112; S@62 L@174(ice) | settle 77; 1 chg; gap -; S@77 | settle 70; 3 chg; gap 35; S@70 L@177(ice) S@212 |
| ages.entry.ok_share = 0.9 (shipped) [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.entry.ok_share = 0.95 [extra] | settle never; 0 chg; gap -; - | settle 83; 1 chg; gap -; S@83 | settle 81; 2 chg; gap 93; S@81 L@174(ice) | settle 94; 1 chg; gap -; S@94 | settle 218; 1 chg; gap -; S@218 |
| ages.entry.recent_ok_sols = 1 [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.entry.recent_ok_sols = 3 (shipped) [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.entry.recent_ok_sols = 5 [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.exit.recent_sols = 3 [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.exit.recent_sols = 5 (shipped) [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| ages.exit.recent_sols = 10 [extra] | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
| (control: shipped values) | settle never; 0 chg; gap -; - | settle 76; 1 chg; gap -; S@76 | settle 75; 2 chg; gap 99; S@75 L@174(ice) | settle 85; 1 chg; gap -; S@85 | settle 216; 1 chg; gap -; S@216 |
