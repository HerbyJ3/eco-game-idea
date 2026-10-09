# Review of emotions.md rev 1: designer-clarity (Korppoo lens)

Read emotions.md fully and HANDOFF selection/log lines only; relationships.md, council.md and the scoping note not read. Cities: Skylines analogies from memory.

**Good:** one number + baseline + rate is legible; bands read from deviation d, not raw mood; panel as a pure function with digit/percent audit; no colony mood word; hysteresis 0.03 and 1-per-sol cap; dormant proof of the old hashes.

**Blocking**
- B1. Selection is unspecified. Tap a colonist (outside, or in an opened roof) shows the silhouette outline plus the panel; tap empty ground, another building or Esc closes it; tapping the colonist's own building does not toggle the roof while a colonist is selected; colonist hit wins over building only if roof open or colonist outside (stated, tested). Pull minimal click-to-focus into 6a: names in log lines carrying being_id are tap targets. At 1000x the panel updates at most 2/s from cached lines and holds the displayed band at least ~1 s real time; freeze on the selected being. If the selected being dies: one beat of "{name} has died." then close.
- B2. The "why" rule can mislead: (a) grief and lapse_close whys are sticky until abs(d) < show_dev; only a same-sign push may replace a why; (b) show a why only if its push sign equals sign(d); (c) the hard why reads present tense after supplies recover: use past tense ("The hard days have weighed on them.").
- B3. A being in "low" (not heavy) gets no log line; narrow the 7.4 success claim to heavy cases (recommended), or add a rare line for entering low with a grief why and half-life >= 8.
- B4. Reset record: also report pop at 300 and births on the five seeds; run-twice cmp for every intermediate run, not only the final config; per-seed C1/C4 with old values.

**Should-fix**
- S1. Panel at most 4 sentences at 720p: name + description as a title; drop the nature line when a why is shown.
- S2. Judge the combined relationship/Council/mood log share: target <= 0.25, with drop order (mood_relief first) if it fails; state that after a long absence the panel is the only mood context.
- S3. Keep mood_relief; do not cut it before the nature sentence.
- S4. Positive-only company why is fine but must never replace a grief why.
- S5. Bug: the 'slow to shake off' nature sentence is unreachable (half-life >= 10.0 only for mutable water, already caught by base <= -0.17); reorder or change thresholds.
- S6. Wording: "{name} counts {other} as a friend."
- S7. Cost trigger: add boundary-step p95, and measure seed 1234 five times, not three.

**Ideas:** no in-play notice of the reset (repo changelog only); no tutorial; hard clause could read "the hard days" without naming the resource.

**Owner questions:** Q1 (a) with the S5 fix, at most one sentence, dropped when a why shows; Q2 (a) report and accept, but a failing C1/C4 opens a named recalibration sub-task; watch Council entry sols, the 1234 quorum margin, pledge count and the R3 margins; Q3 (a).
