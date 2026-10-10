# Code review of PR #5 (water throughput) against water-throughput.md

Date: 2026-10-09. Reviewer: code-reviewer. Verdict: **CHANGES NEEDED**. No code defects found; the blocking findings are documentation.

## Blocking (doc)

1. Section 4's defaults-off neutrality check (seed 7 reproduces `12e3535f2952f04d`) is not recorded. Fact supplied by the main session: after implementing W1-W5 with every switch off, seed 7 gave exactly `12e3535f2952f04d`, before W3 was switched on.
2. The spec must say outright that E3 failed the section 4 power guard (seed 99), has more thirst deaths (89 against 76), and ships under the owner's waiver.
3. Section 4 promised an E6 combination run. E7 and E8 replaced it; say so and say why.

## Advisory (for godot-engineer, later)

- `_water_heads` should validate its data: dictionary type, clamp at 0 or above, `push_error` on bad data.
- Tests for W5 "off" and W4 "off" are missing.
- The `balance_lib` guard checks only the top-level type, and the run continues after a PARAM ERROR; it should abort.
- Comment W5's adult guard.
- The E4v row should say delays on 4 of 5 seeds (seed 7: 300 to 310); the non-adoption rests on the guard and the death count.
