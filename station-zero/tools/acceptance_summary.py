#!/usr/bin/env python3
"""Task 7 acceptance (docs/specs/influence-powers.md rev 2 section 5): reads the 15 raw runs in
docs/balance/task-7-acceptance-data/{UN,C1,C2}_<seed>.txt and prints every criterion per seed, then PASS/FAIL.
Usage: python3 tools/acceptance_summary.py [data_dir]   (markdown to stdout)"""
import re, sys, os

D = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "docs/balance/task-7-acceptance-data")
SEEDS = [42, 7, 99, 1234, 2026]
RUNS = ["UN", "C1", "C2"]


def load(name, seed):
    path = os.path.join(D, f"{name}_{seed}.txt")
    text = open(path).read()
    head = re.search(r"# station zero balance run: (.*)", text)
    rows = []
    for l in text.split("\n"):
        f = l.split()
        if len(f) > 6 and f[0].isdigit() and re.fullmatch(r"\d+/\d+/\d+/\d+/\d+", f[4]):
            d = [int(x) for x in f[4].split("/")]
            rows.append({"sol": int(f[0]), "pop": int(f[1]), "dead": d})
    m = {}
    for l in text.split("\n"):
        if l.startswith("PLAYER"):
            if " uses guide=" in l:  # "uses guide=N fortune=M per100 guide=X fortune=Y": counts first, then per 100 sols
                a, b = l.split("per100")
                m["uses_guide"], m["uses_fortune"] = re.findall(r"guide=(\d+) fortune=(\d+)", a)[0]
                l = "PLAYER" + b + " " + re.sub(r"uses guide=\d+ fortune=\d+", "", a)
            for k, v in re.findall(r"(\w+)=([\w.\-]+)", l):
                m[k] = v
    g = lambda k: None if m.get(k) in (None, "none") else float(m[k])
    return {"head": head.group(1) if head else "?", "rows": rows, "m": m, "g": g,
            "err": len(re.findall("SCRIPT ERROR", text)), "result": re.search(r"RESULT.*", text)}


def summarise(r):
    rows = r["rows"]
    pops = {x["sol"]: x["pop"] for x in rows}
    last = rows[-1] if rows else {"sol": 0, "pop": 0, "dead": [0] * 5}
    peak = max([x["pop"] for x in rows] or [0])
    fl = r["g"]("first_low_sol")
    ft = r["g"]("first_thirst_sol")
    worst = 0.0
    sols = sorted(pops)
    for s in sols:
        if pops[s] >= 10 and s + 50 in pops:
            worst = max(worst, 1.0 - pops[s + 50] / pops[s])
    half = None
    if ft is not None:
        for s in sols:
            if s >= ft and pops[s] <= peak / 2:
                half = s - ft
                break
    return {"pop_sols": sum(x["pop"] for x in rows), "alive": last["pop"] > 0 and last["sol"] >= 1500, "final": last["pop"],
            "last_sol": last["sol"], "peak": peak, "low": fl, "thirst": ft, "lead": None if (fl is None or ft is None) else ft - fl,
            "worst50": worst, "half": half, "eva": last["dead"][4], "air": r["g"]("air_deaths"), "tb": r["g"]("turn_backs_air"),
            "ice": r["g"]("mean_ice_over_target"), "lowshare": r["g"]("low_share"), "gper": r["g"]("guide"), "fper": r["g"]("fortune")}


def fmt(x, p=0):
    return "none" if x is None else (f"{x:.{p}f}" if isinstance(x, float) else str(x))


def main():
    R = {n: {s: load(n, s) for s in SEEDS} for n in RUNS}
    S = {n: {s: summarise(R[n][s]) for s in SEEDS} for n in RUNS}
    out = []
    P = out.append
    P("### Run headers")
    for n in RUNS:
        for s in SEEDS:
            P(f"- {n} {s}: `{R[n][s]['head']}`; rows {len(R[n][s]['rows'])}; SCRIPT ERROR lines {R[n][s]['err']}")
    P("\n### Per-seed numbers")
    P("| run | seed | pop_sols | alive@1500 | final pop (last sol) | peak | low_sol | first thirst | lead | worst 50-sol loss | sols thirst->half peak | EVA deaths | air deaths | air turn-backs | mean ice/target | low share |")
    P("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for n in RUNS:
        for s in SEEDS:
            x = S[n][s]
            P(f"| {n} | {s} | {x['pop_sols']} | {'yes' if x['alive'] else 'no'} | {x['final']} ({x['last_sol']}) | {x['peak']} | {fmt(x['low'])} | {fmt(x['thirst'])} | {fmt(x['lead'])} | {x['worst50']*100:.0f}% | {fmt(x['half'])} | {x['eva']} | {fmt(x['air'])} | {fmt(x['tb'])} | {fmt(x['ice'],3)} | {fmt(x['lowshare'],3)} |")
    P("\n### Power use")
    P("| run | seed | checks | guide uses | fortune uses | guide /100 sols | fortune /100 sols | guide uses while low/dry | guide_trips / ice_trips_in_guided_window | guide_trips / ice_trips_total |")
    P("|---|---|---|---|---|---|---|---|---|---|")
    for n in ["C1", "C2"]:
        for s in SEEDS:
            m = R[n][s]["m"]
            P(f"| {n} | {s} | {m.get('checks')} | {m.get('uses_guide')} | {m.get('uses_fortune')} | {m.get('guide')} | {m.get('fortune')} | {m.get('guide_in_trouble')} | {m.get('guide_share_of_window')} | {float(m.get('guide_trips', 0))/max(1.0, float(m.get('ice_trips_total', 1))):.3f} |")
    V = []
    def add(cid, ok, note):
        V.append((cid, ok, note))
    # U2
    u2 = []
    for s in SEEDS:
        x = S["UN"][s]
        if x["low"] is None or x["low"] <= 0:
            u2.append(f"{s}: low_sol {fmt(x['low'])}")
        elif x["thirst"] is not None and x["lead"] < 10:
            u2.append(f"{s}: lead {x['lead']}")
    add("U2 warned early (lead >= 10, low_sol > 0)", not u2, "; ".join(u2) or "all seeds", )
    u3 = [f"{s}: {S['UN'][s]['worst50']*100:.0f}%" for s in SEEDS if S["UN"][s]["worst50"] > 0.35]
    add("U3 no 50-sol window loses > 35%", not u3, "; ".join(u3) or "max " + ", ".join(f"{s}:{S['UN'][s]['worst50']*100:.0f}%" for s in SEEDS))
    ps = lambda n, s: S[n][s]["pop_sols"]
    gt = sum(ps("C1", s) > ps("UN", s) for s in SEEDS); ge = all(ps("C1", s) >= ps("UN", s) for s in SEEDS)
    later = sum((S["C1"][s]["thirst"] is None) or (S["UN"][s]["thirst"] is not None and S["C1"][s]["thirst"] > S["UN"][s]["thirst"]) for s in SEEDS)
    add("A1 C1 >= UN everywhere, > on >= 4; first thirst later/never on >= 4", ge and gt >= 4 and later >= 4, f">= on all: {ge}; strictly greater on {gt}/5; thirst later or never on {later}/5")
    ordered = sum(ps("C1", s) >= ps("C2", s) >= ps("UN", s) for s in SEEDS)
    sums = {n: sum(ps(n, s) for s in SEEDS) for n in RUNS}
    add("A2 C1 >= C2 >= UN on >= 4 seeds and sums strictly ordered", ordered >= 4 and sums["C1"] > sums["C2"] > sums["UN"], f"ordered on {ordered}/5; sums C1 {sums['C1']}, C2 {sums['C2']}, UN {sums['UN']}")
    al = sum(S["C1"][s]["alive"] for s in SEEDS)
    add("A3 C1 alive at 1500 on >= 3 seeds", al >= 3, f"{al}/5")
    ice = sum((S["C1"][s]["ice"] or 9) < 1.0 for s in SEEDS); lows = sum(S["C1"][s]["low"] is not None for s in SEEDS)
    add("P1 C1 mean ice < 1.0 on >= 2 seeds and a low episode on >= 3", ice >= 2 and lows >= 3, f"ice<1.0 on {ice}/5; low episode on {lows}/5")
    ls = sum((S["C1"][s]["lowshare"] or 0) <= 0.30 for s in SEEDS)
    add("P2 C1 low share <= 30% on >= 4 seeds", ls >= 4, f"{ls}/5")
    def mean(n, k): return sum(S[n][s][k] or 0 for s in SEEDS) / 5
    p3 = {n: (mean(n, "gper"), mean(n, "fper")) for n in ["C1", "C2"]}
    add("P3 mean uses/100 sols: Guide <= 16.5, Fortune <= 12.5 (C1 and C2)", all(g <= 16.5 and f <= 12.5 for g, f in p3.values()), "; ".join(f"{n}: guide {g:.1f}, fortune {f:.1f}" for n, (g, f) in p3.items()))
    g1 = []
    for n in ["C1", "C2"]:
        for s in SEEDS:
            x = S[n][s]
            if (x["air"] or 0) > 0 or x["eva"] > 0 or (x["tb"] or 0) > (S["UN"][s]["tb"] or 0):
                g1.append(f"{n} {s}: air {fmt(x['air'])}, eva {x['eva']}, tb {fmt(x['tb'])} vs UN {fmt(S['UN'][s]['tb'])}")
    add("G1 no air/EVA deaths, turn-backs <= UN (C1, C2)", not g1, "; ".join(g1) or "clean on all 10 runs")
    P("\n### Criteria")
    P("| criterion | verdict | numbers |")
    P("|---|---|---|")
    for c, ok, note in V:
        P(f"| {c} | {'PASS' if ok else 'FAIL'} | {note} |")
    print("\n".join(out))


main()
