#!/bin/bash
export PATH=$HOME/.local/bin:$PATH
cd /home/claude/eco-game-idea
D=station-zero/docs/balance/task-7c-data/run2
run(){ godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed $1 --sols 1500 --every 10 --player watcher --param 'colony.death.thirst_mode="per_being"' --param colony.death.thirst_being_chance=0.0028 > $D/UN_$1.txt 2>&1; echo "done $1 $?" >> $D/done.log; }
(run 42; run 99; run 2026) &
(run 7; run 1234) &
wait
