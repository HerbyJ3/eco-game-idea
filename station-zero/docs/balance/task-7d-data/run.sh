#!/bin/bash
# usage: run.sh <runname> <param args...>   (params as separate --param pairs); runs 5 seeds, 2 parallel chains
export PATH=$HOME/.local/bin:$PATH
cd /home/claude/eco-game-idea
N=$1; shift
D=station-zero/docs/balance/task-7d-data/$N
mkdir -p $D
run(){ s=$1; shift; godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed $s --sols 1500 --every 10 --player watcher "$@" > $D/UN_$s.txt 2>&1; echo "done $s $?" >> $D/done.log; }
(run 42 "$@"; run 99 "$@"; run 2026 "$@") &
(run 7 "$@"; run 1234 "$@") &
wait
