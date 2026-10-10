# AI minds (Task 6b): owner answers

Recorded 2026-10-10 from the owner (Herby), as relayed by the main session. They answer section 18 of `docs/specs/ai-minds.md`; revision 3 of that spec cites this file. All answers were taken as recommended.

## Earlier answers that still stand
- Host: cloud API (no local model for 6b).
- The AI may change what beings do, through a validated menu and the applied-decision ledger.
- Budget: a tight cap.
- Failure: silent fallback to the rule-based path; no error text, icon or "offline" word.

## Answers of 2026-10-10
| Item | Answer | Effect in the spec |
| --- | --- | --- |
| (a) Rule-mind personality policy | Build it behind the dormant data flag `rule.policy_gain` = 0.0. No hash reset. Switching it on later is a separate owner decision with a recorded reset. | 5.8, 11, test 39 |
| Q-A Default mode | `rules` is the default; `llm` is opt-in by config. | 5.8, 15 |
| Q-B Chart in the prompt | Effect words plus the public sky; no placements in the prompt. Accepted as recommended. | 6.2 |
| Q-C "Day" and "month" in the budget | Real UTC day and month. Accepted as recommended. | 8 |
| Q-D Provider and model | **NOT yet chosen. PENDING OWNER.** Keep provider-neutral; `budget.price_*` stay 0.0 and the driver fails closed. | 8, 9, 15 |
| Q-E Who pays, key delivery | 6b is owner-only with a local key. A proxy is task 6d. | 5.8, 9 |
| Q-F Speed | Live minds only at about 1x to 5x; above that the rule minds run, silently. (The spec's worked numbers put the working range at about 1x to 2x, 8.2; the owner's range is the ceiling.) | 8.2 |
| Q-G Mode line | No mode line for players. A mode line only behind the existing debug toggle, for testers. | 7, 9 |

## Section 18 status
All items resolved except Q-D. **The one remaining PENDING OWNER item: which provider and model (and its prices).**
