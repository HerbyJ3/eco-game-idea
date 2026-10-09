"""Door rect measurement, door fill and door leaf cut (spec 3.6, plan A3)."""
from PIL import Image, ImageDraw


def _mean_diff_cols(L, e, y0, y1, w):
    """Mean |mean(L[e..e+1]) - mean(L[e-2..e-1])| over rows y0..y1-1 (boundary between column e-1 and e)."""
    px = L.load()
    tot = 0.0
    n = 0
    for y in range(y0, y1):
        a = (px[e, y] + px[min(w - 1, e + 1), y]) / 2.0
        b = (px[e - 1, y] + px[max(0, e - 2), y]) / 2.0
        tot += abs(a - b)
        n += 1
    return tot / n if n else 0.0


def _mean_diff_rows(L, e, x0, x1, h):
    px = L.load()
    tot = 0.0
    n = 0
    for x in range(x0, x1):
        a = (px[x, e] + px[x, min(h - 1, e + 1)]) / 2.0
        b = (px[x, e - 1] + px[x, max(0, e - 2)]) / 2.0
        tot += abs(a - b)
        n += 1
    return tot / n if n else 0.0


def _pick(scores, est, peak_frac, min_edge):
    """scores: {position: score}. Candidate edges are local maxima with score >= peak_frac x best and >= min_edge; the one
    nearest the estimate wins (ties go to the smaller position). None when even the best edge is too weak (flat wall)."""
    best = max(scores.values())
    if best < min_edge:
        return None
    cands = []
    for p, s in scores.items():
        if s < peak_frac * best or s < min_edge:
            continue
        if s < scores.get(p - 1, -1) or s < scores.get(p + 1, -1):
            continue
        cands.append(p)
    if not cands:
        return None
    return min(cands, key=lambda p: (abs(p - est), p))


def measure_door(base, est_norm, art):
    """Refine the estimated door rect against the strongest edges of the leaf block (the dark outline that bounds the leaves).
    Returns (x0, y0, x1, y1) in pixels, or None when no edge is strong enough on all four sides (flat wall, no door)."""
    cfg = art["pipeline"]["door"]["measure"]
    W, H = base.size
    L = base.convert("RGB").convert("L")
    ex0, ey0, ex1, ey1 = est_norm[0] * W, est_norm[1] * H, est_norm[2] * W, est_norm[3] * H
    sx = max(1, int(round(cfg["search_frac"] * W)))
    sy = max(1, int(round(cfg["search_frac"] * H)))
    ty = int(round((ey1 - ey0) * cfg["side_trim_frac"]))
    tx = int(round((ex1 - ex0) * cfg["side_trim_frac"]))
    iy0, iy1 = int(round(ey0)) + ty, int(round(ey1)) - ty
    ix0, ix1 = int(round(ex0)) + tx, int(round(ex1)) - tx
    if iy1 <= iy0 or ix1 <= ix0:
        return None
    inner, mn = cfg["peak_frac"], cfg["min_edge_luma"]

    def clampx(v):
        return max(2, min(W - 2, v))

    def clampy(v):
        return max(2, min(H - 2, v))

    left = {e: _mean_diff_cols(L, e, iy0, iy1, W) for e in range(clampx(int(round(ex0)) - sx), clampx(int(round(ex0)) + sx) + 1)}
    right = {e: _mean_diff_cols(L, e, iy0, iy1, W) for e in range(clampx(int(round(ex1)) - sx), clampx(int(round(ex1)) + sx) + 1)}
    top = {e: _mean_diff_rows(L, e, ix0, ix1, H) for e in range(clampy(int(round(ey0)) - sy), clampy(int(round(ey0)) + sy) + 1)}
    bottom = {e: _mean_diff_rows(L, e, ix0, ix1, H) for e in range(clampy(int(round(ey1)) - sy), clampy(int(round(ey1)) + sy) + 1)}
    x0 = _pick(left, ex0, inner, mn)
    x1 = _pick(right, ex1, inner, mn)
    y0 = _pick(top, ey0, inner, mn)
    y1 = _pick(bottom, ey1, inner, mn)
    if None in (x0, x1, y0, y1):
        return None
    if (x1 - x0) < cfg["min_size_frac"] * (ex1 - ex0) or (y1 - y0) < cfg["min_size_frac"] * (ey1 - ey0):
        return None
    return (x0, y0, x1, y1)


def clamp_rect(rect, size):
    W, H = size
    x0, y0, x1, y1 = rect
    return (max(0, x0), max(0, y0), min(W, x1), min(H, y1))


def rect_from_norm(est_norm, size):
    W, H = size
    return clamp_rect((int(round(est_norm[0] * W)), int(round(est_norm[1] * H)),
                       int(round(est_norm[2] * W)), int(round(est_norm[3] * H))), size)


def norm_rect(rect, size):
    W, H = size
    return [round(rect[0] / W, 6), round(rect[1] / H, 6), round(rect[2] / W, 6), round(rect[3] / H, 6)]


def cut_leaf(prefill, rect):
    return prefill.crop(rect)


def fill_door(prefill, rect, art):
    """Paint the vertical dark gradient into the door rect of `base` (opaque)."""
    d = art["pipeline"]["door"]
    top, bot = d["fill_top_rgb"], d["fill_bottom_rgb"]
    x0, y0, x1, y1 = rect
    out = prefill.copy()
    n = max(1, y1 - y0 - 1)
    dr = ImageDraw.Draw(out)
    for i in range(y1 - y0):
        t = i / float(n)
        c = tuple(int(round(top[k] + (bot[k] - top[k]) * t)) for k in range(3)) + (255,)
        dr.line([(x0, y0 + i), (x1 - 1, y0 + i)], fill=c)
    return out
