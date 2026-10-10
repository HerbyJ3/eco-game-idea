# Station Zero — standing instructions for every Claude Code session

Owner: Herby. These rules apply to every session in this repository. They exist to keep usage low and the work on track.

## 1. The main session coordinates; the team does the work

- **Start every task with the `project-manager` agent.** It reads `station-zero-handoff/HANDOFF.md` section 8, picks the one task in progress, splits it into small steps, and names the agent for each step.
- **Delegate each step to the named agent.** Do not write specs, game code, tests, balance runs or art prompts in the main session. All team agents run on Sonnet or Haiku, which cost less than the main session.

| Work | Agent |
| --- | --- |
| Task queue, step plan, definition of done | `project-manager` |
| Specs and design decisions | `game-designer` (consults `designer-emergence`, `designer-feel`, `designer-clarity`) |
| GDScript in `sim/` and `view/` | `godot-engineer` |
| Personality, emotions, relationships, council, AI minds | `ai-minds-engineer` |
| Tests, balance runs, re-baselines, hash proofs | `sim-test-engineer` |
| Review of every change before it is checked off | `code-reviewer` |
| Higgsfield prompts and asset lists | `art-director` |
| Keying, slicing, masks, imports | `asset-pipeline` |
| Poses and indoor movement (after designs are settled) | `animator` |

- The main session may answer the owner's questions, read files to route work, run git (commit, push, PR, merge), and update HANDOFF.md at the end of a task.
- If a step truly needs the main session (for example, a delegated agent failed twice), say so to the owner in one line before doing it.

## 2. Keep sessions small

- **One task per session.** At the end of a task: code-reviewer passes, HANDOFF.md is updated, the branch is merged, then stop and suggest a fresh session for the next task.
- Long-running jobs (balance runs) go to the background; check back with one short command, not repeated full-output reads.
- Read only the lines you need from large files and run outputs.
- Owner's usage rule: at 95% usage, finish the current step, update HANDOFF.md, merge, and stop.

## 3. Project rules that still apply

`station-zero-handoff/HANDOFF.md` section 10 (spec before code, one balance change per run, three failed attempts means stop and split the task). Owner direction (2026-10-09): the colony is not meant to survive unattended; the player's influence keeps it alive.

## 4. Experiments

Check the `overrides=[...]` header of every balance output before trusting a result. `tests/balance_lib.gd` rejects type-mismatched overrides, but read the header anyway.
