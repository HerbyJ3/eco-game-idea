"""Role recolor of the gray jumpsuit sheet and the sleeping poses (spec 3.7, plan A2). Pre-baked atlases, no shader."""
import colorsys

from PIL import Image

import common


def suit_gray_flags(im, art):
    """Per-pixel list: True when the pixel is suit gray (HSV sat < sat_max, value in [value_min, value_max], not outline)."""
    rc = art["pipeline"]["recolor"]
    sat_max, vmin, vmax, omax = rc["sat_max"], rc["value_min"], rc["value_max"], rc["outline_value_max"]
    cache = {}
    flags = []
    for r, g, b, a in im.getdata():
        if a == 0:
            flags.append(False)
            continue
        key = (r, g, b)
        f = cache.get(key)
        if f is None:
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            f = s < sat_max and vmin <= v <= vmax and not v < omax
            cache[key] = f
        flags.append(f)
    return drop_specks(im, flags, rc["min_component_px"])


def drop_specks(im, flags, min_px):
    """Suit-gray pieces smaller than min_px are not suit: gray highlight streaks inside the black hair would otherwise turn
    into role-coloured streaks. (A 4-connected piece analysis; the large torso, arm and leg pieces are untouched.)"""
    w, h = im.size
    m = Image.new("L", im.size)
    m.putdata([255 if f else 0 for f in flags])
    data = bytearray(m.tobytes())
    small = [c for c in common.components(m, w, h) if c["size"] < min_px]
    common.clear_runs(data, w, small)
    return [v != 0 for v in data]


def mean_suit_luma(images_flags, art):
    """Mean luma of all opaque suit-gray pixels over several (image, flags) pairs."""
    w = art["pipeline"]["masks"]["luma_weights"]
    tot, n = 0.0, 0
    for im, flags in images_flags:
        for (r, g, b, a), f in zip(im.getdata(), flags):
            if f and a >= 250:
                tot += w[0] * r + w[1] * g + w[2] * b
                n += 1
    if n == 0:
        raise ValueError("no suit-gray pixels found to recolor")
    return tot / n


def recolor(im, flags, mean_luma, color, art):
    """out = clamp(color x (pixel luma / mean luma)) on suit-gray pixels, alpha and every other pixel kept."""
    w = art["pipeline"]["masks"]["luma_weights"]
    out = []
    for (r, g, b, a), f in zip(im.getdata(), flags):
        if not f:
            out.append((r, g, b, a))
            continue
        k = (w[0] * r + w[1] * g + w[2] * b) / mean_luma
        out.append((min(255, int(round(color[0] * k))), min(255, int(round(color[1] * k))),
                    min(255, int(round(color[2] * k))), a))
    res = Image.new("RGBA", im.size)
    res.putdata(out)
    return res


def role_colors(art):
    return {role: common.hex_rgb(h) for role, h in art["pipeline"]["recolor"]["roles"].items()}
