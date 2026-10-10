# Task 6a view shots (dormant build: mood gains 0.0)

Made with `PATH=/tmp/claude-0/bin:$PATH OUT_DIR=$PWD/docs/shots/task-6a SHOT_LIST=$PWD/tools/shots_task6a.txt tools/shots.sh` (xvfb, OpenGL), 1280x720. Read by eye: all three non-blank.

- `m01_panel_heavy_grief.png`: staged state (setup `mood_panel` writes the mood fields and two log lines by hand; the shipped data never produces this while dormant). Vana-3 selected: outline built from her own sprite alpha (warm off-white), panel at bottom left with the who, spirits-with-why ("struggling. They are mourning Lena-2.") and company sentences. The log shows the two mood lines.
- `m02_panel_real_dormant.png`: a real seed-42 world at sol 7, first colonist selected through the `being=first` shot option. The colonist is inside a closed building, so no outline and the panel stays open (spec 7.1 rule 2). Panel: the who sentence ("Vora-16 is driven and steady.", the persona description) and the company sentence ("counts Quone-44 as a friend"); the band is even and no nature threshold applies, so there is no spirits or nature sentence.
- `m03_no_selection_hud.png`: same world, nothing selected: no panel, no outline, no meter, no colony-wide mood word.

## What is visible while dormant (measured, seeds 42 and 7, 300 sols, sampled every 20th step)
- The mood state still moves (pushes and decay run; only the two behaviour gains are 0.0). Band samples seed 42: even 52850, light 927; seed 7: even 50502, light 2785, bright 12. Heavy and low never occur; every non-even sample carries a why.
- So a real panel shows: the who line always; a spirits sentence ("is in good spirits." with its why) for the minority of beings and times in the light band; a nature sentence when the temperament crosses a threshold and no why shows; the company sentence always.
- Neither mood log line (`mood_quiet`, `mood_relief`) appeared in 300 sols on either seed (0 of 289 and 193 log entries), because both need heavy or low. Their wiring (tap a log line with a `being_id` to open that being's panel) is tested and shown by the staged shot m01 only.
