# Indoor animation: design-dependent handoff

Animation depends on the final building artwork. Treat this as a coordination note, not an approved animation specification. Do not implement room routes, activity anchors, furniture occlusion, or new action cycles until the relevant design is settled.

## What works now

The view moves awake colonists between indoor slots and supports walking, idle, talking, and sleeping poses. Habitat and Comms have dedicated slot maps; the other buildings use generic floor points. Movement currently follows straight lines without avoiding furniture. Seat and kitchen slot labels do not create sitting or kitchen activities.

These observations describe the current images and code. If a room design changes, review its positions and poses again rather than carrying over the old coordinates.

The [owner direction notes](../design/owner-direction-notes.md) add timed pregnancies, baby/toddler/teen/adult stages, and a sleeping limit based on usable beds. The clock stays unchanged. Calendar pregnancy and life stages are implemented in [lifecycle.md](../specs/lifecycle.md); bed availability remains outstanding and cannot be enforced by an animation cap alone. Defer age-specific art and animation until the designs settle. The new city direction is strictly 2D; see [mars-colony-redesign.md](mars-colony-redesign.md).

## Team responsibilities

- **Art-director:** owns the interior/exterior design, room composition, furniture, character style, and image-generation prompts.
- **Animator:** works with the art-director to align character poses, movement, facing, scale, and timing with the approved room. The role is defined in `.claude/agents/animator.md`.
- **Godot-engineer / asset-pipeline:** integrate agreed animation assets, routes, metadata, and rendering changes while keeping the view separate from the simulation.

## Handoff after design review

Agree on the room revision, doorway, walkable floor, furniture obstacles, interaction/body anchors, and foreground layers where needed. Then audit the available character frames and identify what is missing. These details must come from the approved design, not a generic room map.

Owner preference: develop movement and room activities together once the design is settled. Review a complete approach/activity/departure sequence in the actual room. The starting room and activity set remain open.

Keep animation cosmetic unless a separate gameplay change is approved. Do not imply a staffing requirement for the Reactor or Green room, or material production at the Workshop, that the simulation does not implement. Use the [starting-building brief](starting-buildings.md) for current gameplay facts.

No new indoor routes, activity cycles, or character art have been implemented in this change. No animator agent has been launched.
