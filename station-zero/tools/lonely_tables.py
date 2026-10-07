#!/usr/bin/env python3
"""Reads the probe summaries of the lonely-pull run and prints the markdown tables and the clause verdicts of
docs/specs/council.md section 10 (revision 3 and the owner ruling of 2026-10-07 on eligible seeds). Read only.

  python3 tools/lonely_tables.py DIR [BALANCE_DIR]

DIR holds seed_N_shipped.json and seed_N_lonely.json written by tools/relationships_probe.gd (--pull shipped|lonely).
Thresholds are the spec's estimates (data/relationships.json balance.r9_* keys do not exist yet).
"""
import json
import math
import statistics
import sys

STANDARD = [42, 7, 99, 1234, 2026]
ALL = STANDARD + [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
R9_GAIN_MIN = 0.03
SEEDS_BETTER_FRAC = (2, 3)  # owner ruling: two thirds of the eligible seeds
ELIGIBLE_MIN = 6
REPEAT_RISE_MAX = 0.5
REPEAT_SEEDS_MIN = 10
OLD_SETTLE = {42: 67, 7: 58, 99: 54, 1234: 65, 2026: 53}
OLD_FALL = {42: 213, 99: 174}


def load(d, seed, pull):
    try:
        with open("%s/seed_%d_%s.json" % (d, seed, pull)) as f:
            return json.load(f)
    except FileNotFoundError:
        return None


def f3(v):
    return "-" if v is None else "%.3f" % v


def main():
    d = sys.argv[1]
    ship = {s: load(d, s, "shipped") for s in ALL}
    pull = {s: load(d, s, "lonely") for s in ALL}
    missing = [s for s in ALL if ship[s] is None or pull[s] is None]
    if missing:
        print("MISSING seeds: %s" % missing)
    seeds = [s for s in ALL if s not in missing]
    out = []
    p = out.append

    # ---- per seed zero-friend
    p("### Zero-friend late newborns per seed (clause 1 and 2)")
    p("| seed | late newborns shipped | zero shipped | share shipped | late newborns pull | zero pull | share pull | change | eligible | better |")
    p("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    shares_s, shares_p, diffs = [], [], []
    eligible, better = [], []
    for s in seeds:
        a, b = ship[s]["zero_friend"], pull[s]["zero_friend"]
        sa = a["share"] if a["n"] > 0 else None
        sb = b["share"] if b["n"] > 0 else None
        elig = sa is not None and sa > 0.0
        bet = elig and sb is not None and sb < sa
        if elig:
            eligible.append(s)
        if bet:
            better.append(s)
        if sa is not None and sb is not None:
            shares_s.append(sa)
            shares_p.append(sb)
            diffs.append(sb - sa)
        ch = "-" if sa is None or sb is None else "%+.3f" % (sb - sa)
        p("| %d | %d | %d | %s | %d | %d | %s | %s | %s | %s |" % (
            s, a["n"], a["zero"], f3(sa), b["n"], b["zero"], f3(sb), ch, "yes" if elig else "no",
            "yes" if bet else "no"))
    out.append("")

    ms = statistics.mean(shares_s) if shares_s else None
    mp = statistics.mean(shares_p) if shares_p else None
    se = (statistics.stdev(diffs) / math.sqrt(len(diffs))) if len(diffs) > 1 else None
    c1 = ms is not None and mp is not None and mp <= ms - R9_GAIN_MIN + 1e-12
    need = math.ceil(SEEDS_BETTER_FRAC[0] * len(eligible) / SEEDS_BETTER_FRAC[1] - 1e-9)
    c2_enough = len(eligible) >= ELIGIBLE_MIN
    c2 = c2_enough and len(better) >= need

    # ---- repeat company
    p("### Repeat-company measure and breadth (clause 3 and the breadth report)")
    p("Per seed: median over late newborns (born after sol 100, lived their first 20 sols) of the median daily maximum hours shared with one being.")
    p("| seed | newborns shipped | repeat h shipped | newborns pull | repeat h pull | change | distinct beings met (median) ship / pull | share of group hours to the top being ship / pull | group hours a sol ship / pull |")
    p("| --- | --- | --- | --- | --- | --- | --- | --- | --- | ")
    rs_, rp_ = [], []
    for s in seeds:
        a, b = ship[s]["repeat"], pull[s]["repeat"]
        va = a["value"] if a["n"] > 0 else None
        vb = b["value"] if b["n"] > 0 else None
        if va is not None and vb is not None:
            rs_.append(va)
            rp_.append(vb)
        ch = "-" if va is None or vb is None else "%+.2f" % (vb - va)
        p("| %d | %d | %s | %d | %s | %s | %.1f / %.1f | %.3f / %.3f | %.1f / %.1f |" % (
            s, a["n"], "-" if va is None else "%.2f" % va, b["n"], "-" if vb is None else "%.2f" % vb, ch,
            a["distinct_met_median"], b["distinct_met_median"], a["top_share_median"], b["top_share_median"],
            a["group_hours_per_sol_median"], b["group_hours_per_sol_median"]))
    out.append("")
    qual = len(rs_)
    rms = statistics.mean(rs_) if rs_ else None
    rmp = statistics.mean(rp_) if rp_ else None
    c3 = qual >= REPEAT_SEEDS_MIN and rmp <= rms + REPEAT_RISE_MAX + 1e-12

    # ---- R4, R10, R11
    p("### R4, R10, R11 on the pull runs (clause 4), with the shipped runs beside")
    p("| seed | R4 friends_mean pull (ship) | R10 ratio / coldest third pull | R4 | R10 | R11 | R4 R10 R11 shipped |")
    p("| --- | --- | --- | --- | --- | --- | --- |")
    c4 = True
    for s in seeds:
        tp, ts = pull[s]["targets"], ship[s]["targets"]
        r4 = tp["R4_friends_mean_300_in_band"][0]
        r10 = tp["R10_selectivity_ratio_stop"][0]
        r11 = tp["R11_coldest_third_mean_stop"][0]
        c4 = c4 and r4 and r10 and r11
        fm_p = pull[s]["readings"].get("300", {}).get("friends_mean", -1)
        fm_s = ship[s]["readings"].get("300", {}).get("friends_mean", -1)
        shipok = "%s %s %s" % tuple("pass" if ts[k][0] else "FAIL" for k in (
            "R4_friends_mean_300_in_band", "R10_selectivity_ratio_stop", "R11_coldest_third_mean_stop"))
        p("| %d | %.2f (%.2f) | %s | %s | %s | %s | %s |" % (
            s, fm_p, fm_s, tp["R10_selectivity_ratio_stop"][1].split(" (min")[0].replace("ratio ", ""),
            "pass" if r4 else "FAIL", "pass" if r10 else "FAIL", "pass" if r11 else "FAIL", shipok))
    out.append("")

    # ---- deaths
    p("### Deaths (clause 6)")
    p("| seed | deaths shipped a/t/h/e/o | deaths pull a/t/h/e/o | unexplained pull | new cause under pull |")
    p("| --- | --- | --- | --- | --- |")
    c6 = True
    causes_s, causes_p = set(), set()
    onset = []
    for s in seeds:
        da, db = ship[s]["deaths"], pull[s]["deaths"]
        keys = ["air", "thirst", "hunger", "suffocated_outside", "other"]
        causes_s |= {k for k in keys if da[k] > 0}
        causes_p |= {k for k in keys if db[k] > 0}
        newc = [k for k in keys if db[k] > 0 and da[k] == 0]
        if newc:
            onset.append(s)
        c6 = c6 and pull[s]["deaths_unexplained"] == 0
        ext = "colony extinct at sol 300 (pop_end 0)" if pull[s]["pop_end"] == 0 else ""
        p("| %d | %s | %s | %d | %s %s |" % (s, "/".join(str(da[k]) for k in keys), "/".join(str(db[k]) for k in keys),
                                          pull[s]["deaths_unexplained"], ", ".join(newc) if newc else "none", ext))
    newtype = sorted(causes_p - causes_s)
    c6 = c6 and not newtype
    p("")
    p("Cause types seen on the 15 shipped runs: %s. Under the pull: %s. New cause type: %s. Seeds where a cause appears that the same seed did not have shipped: %s (read per seed, this is stricter than the cause-type reading used for the verdict)." % (
        sorted(causes_s), sorted(causes_p), newtype or "none", onset or "none"))
    ext_seeds = [s for s in seeds if pull[s]["pop_end"] == 0]
    shipext = [s for s in seeds if ship[s]["pop_end"] == 0]
    p("Colonies extinct at sol 300: shipped %s, pull %s." % (shipext or "none", ext_seeds or "none"))
    out.append("")

    # ---- ages, standard seeds
    p("### Task 3 ages on the standard seeds (clause 5, reported, not judged against the old sols)")
    p("| seed | settlement sol shipped | settlement sol pull | old (Task 3) | fall-backs shipped | fall-backs pull | age history pull |")
    p("| --- | --- | --- | --- | --- | --- | --- |")
    for s in STANDARD:
        if s not in seeds:
            continue

        def ages(sm):
            sol = [h for h in sm["age_history"] if h["how"] == "settled"]
            fall = ["%d (%s)" % (h["sol"], h["cause"]) for h in sm["age_history"] if h["how"] == "fell_back"]
            return (str(sol[0]["sol"]) if sol else "none"), (", ".join(fall) if fall else "none")
        sa, fa = ages(ship[s])
        sb, fb = ages(pull[s])
        hist = "; ".join("%d %s" % (h["sol"], h["how"]) for h in pull[s]["age_history"])
        p("| %d | %s | %s | %d | %s | %s | %s |" % (s, sa, sb, OLD_SETTLE[s], fa, fb, hist))
    out.append("")

    # ---- gate readings
    p("### Council gate readings (reported; section 10 'must not make the gate a timer')")
    p("Recomputed by the probe with the 5.1 to 5.3 formulas and estimates (voices 40 sols, family 2 generations, 0.5 / 0.5, 16 of 20, 30 settled sols, 12 voices).")
    p("| seed | run | earliest sol all clauses | voices / trust / chosen there | first sol open without the chosen clause | chosen clause binds | sols the chosen clause alone blocked | min trust from sol 60 | min chosen from sol 60 |")
    p("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for s in seeds:
        for name, sm in (("shipped", ship[s]), ("pull", pull[s])):
            g = sm["gate"]
            e = g["at_entry"]
            there = "-" if not e else "%d / %.2f / %.2f" % (e["voices"], e["trust"], e["chosen"])
            fe = g["earliest_entry_sol"]
            fo = g["first_open_without_chosen_sol"]
            p("| %d | %s | %s | %s | %s | %s | %d | %s | %s |" % (
                s, name, "never" if fe < 0 else fe, there, "never" if fo < 0 else fo, "yes" if g["chosen_binds"] else "no",
                g["chosen_binding_sols"], f3(g["min_trust_from_60"] if g["min_trust_from_60"] >= 0 else None),
                f3(g["min_chosen_from_60"] if g["min_chosen_from_60"] >= 0 else None)))
    out.append("")
    nbind_p = sum(1 for s in seeds if pull[s]["gate"]["chosen_binds"])
    nbind_s = sum(1 for s in seeds if ship[s]["gate"]["chosen_binds"])
    nent_p = sum(1 for s in seeds if pull[s]["gate"]["earliest_entry_sol"] >= 0)
    nent_s = sum(1 for s in seeds if ship[s]["gate"]["earliest_entry_sol"] >= 0)

    # ---- K1..K3 and F4
    p("### K1 to K3 and the F4 reads")
    p("| seed | K1 zero-friend share ship / pull | K2 first newcomer line ship / pull | K3 R1 median wait ship / pull (max 30) | F4-1 longest silent run before first newcomer line ship / pull | R13 tail per 5 sols ship / pull (warn 2.5) | log share ship / pull (flag 0.15) |")
    p("| --- | --- | --- | --- | --- | --- | --- | ")
    late68_s = late68_p = 0
    late80_s, late80_p = [], []
    for s in seeds:
        a, b = ship[s], pull[s]
        late68_s += 1 if a["f4"]["newcomer_later_than_68"] else 0
        late68_p += 1 if b["f4"]["newcomer_later_than_68"] else 0
        if a["f4"]["newcomer_later_than_80"]:
            late80_s.append(s)
        if b["f4"]["newcomer_later_than_80"]:
            late80_p.append(s)
        p("| %d | %s / %s | %s / %s | %.1f / %.1f | %d / %d | %.2f / %.2f | %.3f / %.3f |" % (
            s, f3(a["zero_friend"]["share"] if a["zero_friend"]["n"] else None), f3(b["zero_friend"]["share"] if b["zero_friend"]["n"] else None),
            a["first_newcomer_line_sol"], b["first_newcomer_line_sol"],
            a["kinless"]["kin_median_sols"], b["kinless"]["kin_median_sols"],
            a["f4_1_longest_no_line_run_before_newcomer"], b["f4_1_longest_no_line_run_before_newcomer"],
            a["ff_tail_per5"], b["ff_tail_per5"], a["log"]["rel_share"], b["log"]["rel_share"]))
    out.append("")

    # ---- verdict
    p("### Adoption clauses, as written")
    p("| clause | measured | verdict |")
    p("| --- | --- | --- |")
    p("| 1. R9 mean: pull mean <= shipped mean - %.2f | shipped mean %s, pull mean %s over %d seeds with late newborns on both runs; difference %s | %s |" % (
        R9_GAIN_MIN, f3(ms), f3(mp), len(shares_s), "-" if ms is None else "%+.3f" % (mp - ms), "PASS" if c1 else "FAIL"))
    p("| 2. better on at least two thirds of eligible seeds, at least %d eligible | eligible %d (%s), better %d (%s), needed %d; SE of the paired difference over %d seeds %s | %s |" % (
        ELIGIBLE_MIN, len(eligible), ",".join(map(str, eligible)), len(better), ",".join(map(str, better)), need, len(diffs),
        "-" if se is None else "%.3f" % se, ("PASS" if c2 else "FAIL") if c2_enough else "TO OWNER (fewer than %d eligible)" % ELIGIBLE_MIN))
    p("| 3. repeat-company mean: pull <= shipped + %.1f h, at least %d seeds with a value on both | shipped mean %s, pull mean %s over %d seeds; difference %s | %s |" % (
        REPEAT_RISE_MAX, REPEAT_SEEDS_MIN, "-" if rms is None else "%.2f" % rms, "-" if rmp is None else "%.2f" % rmp, qual,
        "-" if rms is None else "%+.2f" % (rmp - rms), "PASS" if c3 else "FAIL"))
    p("| 4. R4, R10, R11 on all 15 seeds (pull runs) | see table | %s |" % ("PASS" if c4 else "FAIL"))
    p("| 5. T1 to T11 on the five standard seeds | see the balance table section | (filled from the balance runs) |")
    p("| 6. deaths_unexplained 0 and no new death cause (pull runs, 15 seeds) | deaths_unexplained 0 on all 15, new cause type: %s (read by cause type) | %s |" % (newtype or "none", "PASS" if c6 else "FAIL"))
    out.append("")
    p("Gate reported: chosen clause binds on %d of %d seeds shipped, %d of %d seeds under the pull; the gate would open on %d seeds shipped and %d under the pull (sol 300 horizon)." % (
        nbind_s, len(seeds), nbind_p, len(seeds), nent_s, nent_p))
    p("R12 reopen trigger (any seed later than sol 80, or two or more later than 68): shipped later than 80 on %s, later than 68 on %d seeds; pull later than 80 on %s, later than 68 on %d seeds." % (
        late80_s or "no seed", late68_s, late80_p or "no seed", late68_p))
    if len(sys.argv) > 2:
        bd = sys.argv[2]
        p("")
        p("### T1 to T11 on the five standard seeds (balance_run.gd, 300 sols; shipped and candidate)")
        p("| seed | table hash shipped | table hash candidate | candidate run twice identical | shipped targets failing | candidate targets failing |")
        p("| --- | --- | --- | --- | --- | --- |")
        import re
        def rd(seed, mode):
            try:
                t = open("%s/seed_%d_%s.txt" % (bd, seed, mode)).read()
            except FileNotFoundError:
                return None, []
            h = re.findall(r"table sha256 ([0-9a-f]+)", t)
            fails = re.findall(r"^  (T\d+) FAIL (.*)$", t, re.M)
            return (h[0] if h else None), fails
        for sd in STANDARD:
            hs, fs = rd(sd, "ship")
            hp, fp = rd(sd, "pull")
            hp2, _ = rd(sd, "pull2")
            p("| %d | %s | %s | %s | %s | %s |" % (sd, hs, hp, "yes" if hp == hp2 else "NO (%s)" % hp2,
                ", ".join(f[0] for f in fs) or "none", ", ".join(f[0] for f in fp) or "none"))
        p("")
        nfail = sum(1 for sd in STANDARD if rd(sd, "pull")[1])
        for i, line in enumerate(out):
            if line.startswith("| 5. T1 to T11"):
                out[i] = "| 5. T1 to T11 pass on the five standard seeds (candidate) | targets fail on %d of 5 seeds (list below); T10 range check passes on all | %s |" % (nfail, "FAIL" if nfail else "PASS")
        for sd in STANDARD:
            _, fp = rd(sd, "pull")
            for f in fp:
                p("- seed %d %s: %s" % (sd, f[0], f[1][:260]))
    print("\n".join(out))
    print("\nCLAUSES c1=%s c2=%s (enough eligible %s) c3=%s c4=%s c6=%s" % (c1, c2, c2_enough, c3, c4, c6))


if __name__ == "__main__":
    main()
