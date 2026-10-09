# Pregnancy and human life stages

Owner direction: leave the simulation clock unchanged; pregnancy lasts nine months, and growth from babyhood to adulthood follows human calendar years. This supersedes instant births and the Council's forty-sol adulthood approximation.

## Timing

All durations use simulation time, so pause freezes them and speed controls advance them normally. Use Gregorian months and birthdays, not Martian years or a fixed number of thirty-day months. `data/lifecycle.json` holds the thresholds:

| State | Timing |
| --- | --- |
| Pregnancy | Due nine calendar months after conception |
| Baby | Birth to first birthday |
| Toddler | First to third birthday |
| Child | Third to thirteenth birthday |
| Teen | Thirteenth to eighteenth birthday |
| Adult | Eighteenth birthday onward |

The child stage fills the gap between toddlerhood and adolescence. Birthdays retain the birth time of day. Month-end dates clamp to the destination month's last day: May 31 plus nine months becomes February 28 or 29, and February 29 birthdays fall on February 28 in non-leap years. Fractional simulation seconds are retained. The configured civil epoch (January 1, 2000) is an internal anchor for month lengths, not a displayed date or a change to Mars time/sky.

At the unchanged 1× rate, nine months take roughly 1 hour 50 minutes of real play, and eighteen years roughly 44 hours. Faster speed settings shorten real waiting time; engine throughput can limit achieved speed. The simulation's astronomical Earth-year value remains unchanged; human stages use actual calendar anniversaries.

## Pregnancy and population

The existing resource, housing, and per-Habitat cooldown checks decide whether conception is possible. Candidates must be adults and not already pregnant. The existing single-parent selection is retained; this change does not introduce sex, marriage, or a two-parent fertility model.

Conception records the parent, Habitat, conception time, and due time. It logs that the parent is expecting a baby but does not add a colonist or increase the birth counter. Each pending pregnancy reserves a population place so later conceptions cannot overbook the current housing gate. The per-Habitat conception cooldown uses the existing cooldown duration.

Every simulation step checks due pregnancies. Delivery creates the baby's name, birth chart, energy, lineage, and birth record at the actual delivery time. It updates the existing birth counters/logs. It does not rerun the conception resource gates, so a resource shortage does not become an undocumented miscarriage rule. Existing postpartum cooldown can delay a delivery if due dates converge in one Habitat. A parent death cancels its pending scheduler record and releases the reservation. A missing birth Habitat likewise drops that record.

Housing/power loss after conception may lower capacity below existing commitments; the capacity statistic can expose that overcrowding. This is separate from the owner's requested bed-occupancy system, which is not implemented here.

## Age-dependent behavior

Founders retain their existing adult birth records. Newborns start as babies. Only adults can conceive, enable construction readiness, take mining/construction/EVA jobs, or count as Council voices. Younger colonists can rest indoors; babies do not independently travel between buildings. Older minors can use existing indoor/tunnel travel. This is a basic eligibility boundary, not a caregiver or childhood education system.

The HUD shows current babies, toddlers, children, teens, adults, and pregnancies. Stage counts are derived from birth time. Detailed age-specific artwork and animation remain deferred until the visual designs are settled.

## Development and validation

`Lifecycle` owns date calculations, stage classification, and pregnancy records. The simulation supplies the clock; no wall-clock time or random draws are used for aging. `SimWorld.add_being` is an explicit adult test fixture, while `_create_newborn` creates an actual baby. Birth-gate/newborn metadata tests use zero-month gestation in their own world to test those independent rules quickly; default gestation is always nine months and is separately covered by integration tests.

`tests/test_lifecycle.gd` checks actual default scheduling, no early/duplicate delivery, calendar month lengths, leap days, stage boundaries, capacity reservation, adult eligibility, canceled records, and pause behavior. Existing immediate-birth and forty-sol Council fixtures are updated to the new contract. Historical population/balance logs and hashes predate this change; their calibration must be reconsidered for generational growth.
