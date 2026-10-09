"""Mask builders (spec 3.6): accent, windows, outline, shadow, gray, ghost. All masks have the size of `base`."""
from PIL import Image, ImageChops, ImageFilter

MASK_NAMES = ["accent", "windows", "outline", "shadow", "gray", "ghost"]


def _gt(band, v):
    return band.point(lambda x: 255 if x > v else 0)


def _lt(band, v):
    return band.point(lambda x: 255 if x < v else 0)


def _and(*ms):
    out = ms[0]
    for m in ms[1:]:
        out = ImageChops.multiply(out, m)
    return out


def _accent_test(r, g, b, cls, m):
    if cls == "cyan":
        return _and(_gt(b, m["b_min"]), _gt(g, m["g_min"]), _lt(r, m["r_max"]), _gt(ImageChops.subtract(b, r), m["b_minus_r_min"]))
    if cls == "amber":
        return _and(_gt(r, m["r_min"]), _gt(g, m["g_min"]), _lt(g, m["g_max"]), _lt(b, m["b_max"]),
                    _gt(ImageChops.subtract(r, b), m["r_minus_b_min"]))
    if cls == "violet":
        light = _and(_gt(r, m["r_min"] - 1), _lt(r, m["r_max"] + 1), _gt(b, m["b_min"]), _lt(g, m["g_max"]))
        d = m["dark"]   # the dark violet trim: low red, blue clearly above green and red
        dark = _and(_gt(b, d["b_min"] - 1), _lt(r, d["r_max"] + 1), _gt(ImageChops.subtract(b, g), d["b_minus_g_min"] - 1),
                    _gt(ImageChops.subtract(b, r), d["b_minus_r_min"] - 1))
        return ImageChops.lighter(light, dark)
    if cls == "pink":
        return _and(_gt(r, m["r_min"]), _lt(g, m["g_max"]), _gt(b, m["b_min"]), _lt(b, m["b_max"]),
                    _gt(ImageChops.subtract(r, g), m["r_minus_g_min"]))
    raise ValueError("unknown accent class " + cls)


def _windows_test(r, g, b, m):
    return _and(_gt(b, m["b_min"]), _lt(r, m["r_max"]), _gt(g, m["g_min"]), _lt(g, m["g_max"]),
                _gt(ImageChops.subtract(b, g), m["b_minus_g_min"]))


def _denoise(test, alpha, neighbor_min):
    """Keep a passing pixel when at least neighbor_min of its 3x3 neighbourhood pass (itself included)."""
    w, h = test.size
    one = test.point(lambda v: 1 if v else 0)
    pad = Image.new("L", (w + 2, h + 2), 0)
    pad.paste(one, (1, 1))
    cnt = pad.filter(ImageFilter.Kernel((3, 3), [1] * 9, scale=1)).crop((1, 1, w + 1, h + 1))
    ok = cnt.point(lambda v: 255 if v >= neighbor_min else 0)
    return _and(test, ok, alpha.point(lambda v: 255 if v > 0 else 0))


def _colored(mask, color):
    out = Image.new("RGBA", mask.size, tuple(color) + (0,))
    out.putalpha(mask)
    return out


def empty_mask(size):
    return Image.new("RGBA", size, (0, 0, 0, 0))


def accent_mask(base, cls, art):
    if cls == "none":
        return empty_mask(base.size)
    p = art["pipeline"]["masks"]
    r, g, b, a = base.split()
    m = p["accent_" + cls]
    t = _accent_test(r, g, b, cls, m)
    return _colored(_denoise(t, a, p["neighbor_min"]), m["color"])


def windows_mask(base, art):
    p = art["pipeline"]["masks"]
    r, g, b, a = base.split()
    t = _windows_test(r, g, b, p["windows"])
    return _colored(_denoise(t, a, p["neighbor_min"]), p["windows"]["color"])


def disc_offsets(radius):
    import math
    r = int(math.floor(radius))
    return [(dx, dy) for dy in range(-r, r + 1) for dx in range(-r, r + 1) if dx * dx + dy * dy <= radius * radius + 1e-9]


def outline_mask(base, art):
    """Pixels with alpha < alpha_min within a disc of radius round(radius_px * width / ref_width) of a pixel with
    alpha >= alpha_min, written opaque in the outline colour."""
    o = art["pipeline"]["masks"]["outline"]
    w, h = base.size
    radius = int(round(o["radius_px"] * w / float(o["radius_ref_width_px"])))
    alpha = base.getchannel("A")
    solid = alpha.point(lambda v: 255 if v >= o["alpha_min"] else 0)
    pad = radius
    big = Image.new("L", (w + 2 * pad, h + 2 * pad), 0)
    big.paste(solid, (pad, pad))
    acc = Image.new("L", big.size, 0)
    for dx, dy in disc_offsets(radius):
        acc = ImageChops.lighter(acc, ImageChops.offset(big, dx, dy))
    near = acc.crop((pad, pad, pad + w, pad + h))
    ring = ImageChops.subtract(near, solid)
    return _colored(ring, o["color"])


def shadow_mask(base, art):
    out = Image.new("RGBA", base.size, tuple(art["pipeline"]["masks"]["shadow_rgb"]) + (255,))
    out.putalpha(base.getchannel("A"))
    return out


def _luma(base, art):
    w = art["pipeline"]["masks"]["luma_weights"]
    return base.convert("RGB").convert("L", (w[0], w[1], w[2], 0))


def gray_mask(base, art):
    g = art["pipeline"]["masks"]["gray"]
    l = _luma(base, art)
    r = l.point(lambda v: min(255, int(round(g["r_mul"] * v + g["r_add"]))))
    gg = l.point(lambda v: min(255, int(round(g["g_mul"] * v + g["g_add"]))))
    b = l.point(lambda v: min(255, int(round(g["b_mul"] * v + g["b_add"]))))
    out = Image.merge("RGB", (r, gg, b)).convert("RGBA")
    out.putalpha(base.getchannel("A"))
    return out


def ghost_mask(base, art):
    gh = art["pipeline"]["masks"]["ghost"]
    l = _luma(base, art)
    la = l.point(lambda v: min(255, int(round(v * gh["alpha_scale"]))))
    a = ImageChops.darker(base.getchannel("A"), la)
    out = Image.new("RGBA", base.size, tuple(gh["color"]) + (0,))
    out.putalpha(a)
    return out


def build_exterior_masks(base, accent_cls, art):
    return {"accent": accent_mask(base, accent_cls, art), "windows": windows_mask(base, art),
            "outline": outline_mask(base, art), "shadow": shadow_mask(base, art),
            "gray": gray_mask(base, art), "ghost": ghost_mask(base, art)}
