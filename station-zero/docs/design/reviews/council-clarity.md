# Review of council.md rev 1: designer-clarity (Korppoo lens)

Verdict: legible ages-as-words design with real cause and effect; four must-fixes, mostly about silent gates and readable causes. (Reviewer read the spec only; did not check measured numbers.)

**Good:** age lines, circles line and hard set-aside variant follow ages-as-words; hardship named in the log; whole colony votes, named proposer and place, earliest pledge at the third meeting; entries carry being_id/building_id/topic; speakers chosen by most friends in the camp.

**Must-fix**
- M1. Pin the pledge chapter: strip always shows it as a fixed extra slot (or latest 2 + pledge); add a test.
- M2. Silent gates remain: add a once-per-term "meetings held but nothing raised" line ("The council meets, but talk is of the ice and the air."), a once-per-run first-meeting line, and extend the circles trigger to voices under 12 ("too few grown hands yet"); cap 1 line per 5 sols.
- M3. Pledge states a reason by the largest lean term (means / size / personal), and a variant when a divided line was logged ("Not everyone is glad of it, but Jezero will build a dome, together."). Pledge says "will build", never "is building".
- M4. Hard set-aside text uses the same clock as the lean (hard share of hard_win at least one half), and names the failing clause (ice, air, food: three keys).

**Should-fix**
- S1. Scale meeting size: max(5, a quarter of voices); add a max-trust flag for large colonies alongside FLOOR.
- S2. Divided line gives each speaker a fixed trait phrase from persona.traits (no number); consider re-firing once if a speaker dies or majority swaps.
- S3. After the pledge, Council is silent up to ~150 sols: a one-off "no new matter" line (or move the water rule up; not taking O5 b/c on this alone).
- S4. One dome state word in the strip ("the dome: spoken of / set aside / agreed"); check 720p line room.
- S5. Entry line gets a cause sentence ("People have known each other long enough to talk as one.").
- S6. At fast speed, at most one Council line per sol boundary.

**Ideas:** brief highlight/camera nudge on the meeting building (existing art); a later "Send a sign" lever should read through the same lines.

**Owner questions:** O1 (a); O2 (a) with M1 and M3, reject (b) as a lie and (c) for scope; O3 (a), not (c); O4 (a) plus the free highlight; O5 (a), S3 is the price.

First play-test confusion expected: the quiet between Council entry and the first proposal, and "what happened to the dome after the pledge".
