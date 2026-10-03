#!/usr/bin/env bash
# Runs every shot in tools/shots.txt (name | args) through xvfb-run + real OpenGL rendering.
# Output: docs/shots/task-2/<name>.png (override dir with OUT_DIR). Usage: tools/shots.sh [name ...]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(dirname "$HERE")"
LIST="${SHOT_LIST:-$HERE/shots.txt}"
OUT_DIR="${OUT_DIR:-$PROJ/docs/shots/task-2}"
mkdir -p "$OUT_DIR"
ok=0; bad=0; summary=""
while IFS= read -r line; do
	[[ -z "${line// }" || "$line" =~ ^[[:space:]]*# ]] && continue
	name="$(echo "${line%%|*}" | xargs)"
	args="$(echo "${line#*|}" | xargs)"
	if [ $# -gt 0 ] && [[ " $* " != *" $name "* ]]; then continue; fi
	out="$OUT_DIR/$name.png"
	rm -f "$out"
	start=$(date +%s.%N)
	# shellcheck disable=SC2086
	xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path "$PROJ" \
		--script res://tools/shot.gd -- $args --out "$out" >"$OUT_DIR/.$name.log" 2>&1
	rc=$?
	secs=$(printf '%.1f' "$(echo "$(date +%s.%N) - $start" | bc)")
	if [ $rc -eq 0 ] && [ -s "$out" ]; then
		ok=$((ok+1)); summary+="  ok    $name  ${secs}s  $out"$'\n'
	else
		bad=$((bad+1)); summary+="  FAIL  $name  ${secs}s  (see $OUT_DIR/.$name.log)"$'\n'
	fi
done < "$LIST"
echo "shots: $ok ok, $bad failed"
printf '%s' "$summary"
[ $bad -eq 0 ]
