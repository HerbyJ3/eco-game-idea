# Influence powers (Task 7) — spec revision 1

Date: 2026-10-09. Owner direction (Herby): the colony is not meant to survive unattended. It declines gradually on its own, and the player's influence is what keeps it alive. Influence only: a power changes conditions or probabilities, never gives an order to a colonist.

## 1. Purpose

Give the player five influence powers in the simulation (headless, tested) and on the HUD. They exist in the HTML prototype; in Godot only the Good fortune supply hook exists (`sim/powers.gd`).

## 2. API (sim)

- `SimWorld.use_power(name: String, target: int = -1) -> Dictionary` returns `{ok: bool, reason: String}`. On success it logs one `power_<name>` line with readable text and starts the power's recharge.
- `SimWorld.power_ready_in(name) -> float`: hours until the power can be used again (0 = ready).
- All numbers in `data/powers.json`. Recharge is measured on the sim clock.
- **Hash-neutral when unused:** a run that never calls `use_power` draws exactly the same random numbers and produces the same tables as before. Powers draw from the sim RNG only when used.

## 3. The powers

| Name | Target | Effect | Duration | Recharge |
| --- | --- | --- | --- | --- |
| `fortune` (Good fortune) | none | Reactor supply × 1.5 (existing hook, `buildings.fortune`), and the 3 h re-online hold is cleared so a dark building may return at once. | 1 sol | 3 sols |
| `inspire` (Inspire) | a finished building | When builders next choose what to build, after the reactor and green-room survival checks, they choose the target's kind with chance 0.75. Ends when a site of that kind starts or the duration ends. | 2 sols | 2 sols |
| `grace` (Grace) | a finished, online habitat | Conception checks in that habitat add 0.35 to the chance. | 1.5 sols | 2 sols |
| `sign` (Send a sign) | none | A light crosses the sky. Each awake colonist indoors (not a baby) rolls `pull = curiosity + 0.5 restless − 0.6 steady + U(−0.15, 0.15)`. If `pull > 0.35` and the colonist is idle, it walks to a neighbouring comms or archive room if there is one, otherwise to any neighbour. The log reports how many went to look and how many stayed. | instant | 1 sol |
| `guide` (Guide) | an ice field or pit (index into `resources.ice_fields` then `resources.pits`) | The colony feels drawn to that site. While active, `choose_site` returns it when it is live (ice left, round trip within the suit limit) instead of choosing, and each mining attempt treats need as at least 0.6, so more colonists volunteer. | 1 sol | 2 sols |

Personality is untouched: who mines is still `mine_will`, who looks up at a sign is curiosity and restlessness, who builds is still the builders.

Failure reasons (no recharge spent): `recharging`, `bad_target`, `unknown_power`. A dry or unreachable guide target is `bad_target`.

## 4. HUD

Five buttons with recharge countdowns, plus keys F1 (fortune), F2 (inspire), F3 (grace), F4 (sign), F5 (guide) (F and S were already camera keys). Inspire and Grace use the selected building. Guide uses the ice field or pit nearest to the selected building, or the richest reachable ice field when nothing is selected. A failed use shows its reason in the HUD for a few seconds.

## 5. Acceptance (declared before running)

A scripted **attentive player** (`tools/attentive_player.gd`) checks the colony every 6 sim hours, like a player glancing in:
- if stored ice < 50% of the ice target and Guide is ready: guide the richest reachable ice field;
- if any building is dark, or reactor margin < 0, and Good fortune is ready: use it.
Nothing else (no Grace, Inspire or Sign) so the test isolates the water and power levers.

Standard horizon, seeds 42/7/99/1234/2026, compared against the unattended water-throughput baseline (`docs/balance/water-throughput-data/E3_*`):
1. **Unattended stays unchanged:** the 300-sol tables reproduce the pinned hashes in `docs/balance/water-rebaseline.md`.
2. **Attention helps:** the attentive colony is alive at sol 1,500 on at least 4 of 5 seeds, and on every seed its first thirst death is later than unattended (or never).
3. **Guards:** no air deaths, no EVA deaths, no rise in air turn-backs.

If 2 fails: report and stop; the power numbers above are the only things to tune next, one at a time.

## 6. Out of scope

Beings sensing a god or forming beliefs (culture stage), emotions (6a), new art (buttons are text), the power reserve rule (Task 8).
