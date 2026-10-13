#!/usr/bin/env python3
"""Scores one run dir (UN_<seed>.txt) with the 7c method. usage: score.py <dir>"""
import sys, re, os
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../tools/acceptance_summary.py")).read().rsplit("\nmain()", 1)[0]
g = {"__name__": "x"}; exec(src, g)
D = sys.argv[1]; g["D"] = D
SEEDS = g["SEEDS"]
alive = 0; u2ok = True; u3ok = True
print("| seed | header | alive@1500 | final pop (last sol) | peak | dry sols | low_sol | first thirst | lead | worst 50-sol | errs |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
for s in SEEDS:
    r = g["load"]("UN", s); x = g["summarise"](r)
    text = open(os.path.join(D, f"UN_{s}.txt")).read()
    dry = 0
    for l in text.split("\n"):
        f = l.split()
        if len(f) > 6 and f[0].isdigit() and re.fullmatch(r"\d+/\d+/\d+/\d+/\d+", f[4]) and int(f[1]) > 0 and float(f[7]) == 0.0:
            dry += 10
    errs = {k: len(re.findall(k, text)) for k in ("PARAM ERROR", "SCRIPT ERROR", "ABORTED")}
    alive += x["alive"]
    if x["low"] is None or x["low"] <= 0 or (x["thirst"] is not None and x["lead"] < 10): u2ok = False
    if x["worst50"] > 0.35: u3ok = False
    print(f"| {s} | `{r['head'].split('overrides=')[1][:120]}` | {'yes' if x['alive'] else 'no'} | {x['final']} ({x['last_sol']}) | {x['peak']} | {dry} | {g['fmt'](x['low'])} | {g['fmt'](x['thirst'])} | {g['fmt'](x['lead'])} | {x['worst50']*100:.0f}% | {errs} rows={len(r['rows'])} |")
print(f"\nalive {alive}/5 guard {'PASS' if alive<=3 else 'FAIL'}; U2 {'PASS' if u2ok else 'FAIL'}; U3 {'PASS' if u3ok else 'FAIL'}")
