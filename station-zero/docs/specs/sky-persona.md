# Spec: Mars calendar, birth charts, persona (Task 0)

Source formulas: HANDOFF.md section 3. Tiebreaker: prototype `station-zero-wip.html` (marsLs, marsChart, earthChart, personaFrom, roleOf, describe).
Every number lives in `data/calendar.json`, `data/signs.json` and `data/persona.json`.

## Code map
| File | Owns |
| --- | --- |
| sim/clock.gd (`Clock`) | mod360, sign_of, mars_ls, mars_hour, earth_hour, sol/year index, season, lon_of_tile |
| sim/sky.gd (`MarsSky`) | mars_chart, earth_chart, earth_direction, founder_birth. Named `MarsSky` because `Sky` is a built-in Godot class |
| sim/persona.gd (`Persona`) | raw_traits, traits, role_of, describe, persona_from (never exposes the chart) |
| sim/rng.gd (`SimRng`) | the one seeded RNG |
| sim/world.gd (`SimWorld`) | fixed-step clock (0.05 h steps), owns the above |

## Resolved ambiguities
- **Rising at dawn.** The comment "at dawn rising = sun sign" holds only at lon 0. At dawn rise = sign(Ls + lon). Jezero (lon 77.5) shifts it by about 2.6 signs. We implement the formula as coded.
- **Boosts.** v = element + 0.6 × modality, then one boost per dimension: inner applies to care and sociability, outer to restless and steady, the drive boost to drive and the curiosity boost to curiosity. Then sum weight × v.
- **Earth direction.** Mars sits at heliocentric angle Ls − 180 at 1.524 AU. Earth sits at 40 + 360t/EARTH_YEAR_H at 1 AU. The direction is atan2 of the vector from Mars to Earth.
- **Earth-born rise.** Uses the Earth hour (t mod 24). Founder longitude is uniform in [−120, 140]. Birth is 24 to 45 Earth years before START_HOUR. The prototype's retry loop for a wanted role is colony logic (Task 1+).
- **Numbering.** sol = floor(t/SOL_H) + 1 and year = floor(t/YEAR_H) + 1. Founding (t = START_HOUR) is year 1, sol 1.
- **Ties.** The role tie-break keeps the first dimension in order drive, curiosity, sociability, care. describe() is stable, so equal traits keep dims order. restless and steady are never paired.
- **Edge case.** fposmod of a tiny negative can round to 360, so sign_of wraps the result with % 12. The prototype would return 12 there.

## Measured facts (seed 42, tests/test_population.gd)
- 20,000 Mars births (t uniform over 2 Mars years, lon uniform 0..360): **15,481 unique charts** (HANDOFF: ~15,700). The count depends on the lon range sampled.
- Role shares: builder 0.315, social 0.281, tender 0.204, curious 0.200. These are balanced within tolerance, but builder is above 25%. Tune the weights later only with a balance run.
- Trait ranges over all 12^5 Mars charts: the lower clamp is never reached. sociability peaks at 0.681 and care at 0.887. Drive, curiosity and steady hit 1.0.
- Sun signs last 46.2 sols (The Far Arrow, near perihelion) to 66.6 sols (The Twin Signal).
