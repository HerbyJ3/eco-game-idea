"""Placeholder exteriors (spec 3.8): the habitat base tinted per kind, accent pixels recolored to the placeholder accent class."""
from PIL import Image, ImageChops

import common
import masks as masks_mod

ACCENT_RECOLOR = {"amber": (255, 175, 60), "pink": (255, 110, 140), "cyan": (90, 230, 255), "violet": (190, 150, 255),
                  "none": (176, 184, 190)}


def tint(rgba, color, strength):
    rgb = rgba.convert("RGB")
    solid = Image.new("RGB", rgb.size, tuple(color))
    out = Image.blend(rgb, solid, strength).convert("RGBA")
    out.putalpha(rgba.getchannel("A"))
    return out


def recolor_accent(prefill_filled, prefill, cls_from, cls_to, art):
    """Pixels of the habitat accent mask (cls_from, computed on the filled base) get the colour of cls_to, scaled by their own
    brightness so the shading survives."""
    if cls_from == cls_to:
        return prefill
    m = masks_mod.accent_mask(prefill_filled, cls_from, art).getchannel("A")
    l = prefill.convert("RGB").convert("L")
    target = ACCENT_RECOLOR[cls_to]
    chans = []
    for c in target:
        chans.append(l.point(lambda v, c=c: int(round(c * (0.85 + 0.15 * v / 255.0)))))
    colored = Image.merge("RGB", chans).convert("RGBA")
    colored.putalpha(prefill.getchannel("A"))
    return Image.composite(colored, prefill, m)


def placeholder_prefill(kind, hab_prefill, hab_filled, art):
    """The tinted pre-fill base of a placeholder kind (same size as the habitat)."""
    spec = art["kinds"][kind]
    ph = art["pipeline"]["placeholder"]
    cls_to = spec["accent_placeholder"]
    base = recolor_accent(hab_filled, hab_prefill, art["kinds"]["habitat"]["accent"], cls_to, art)
    if kind in ph and "tint_rgb" in ph[kind]:
        t, s = ph[kind]["tint_rgb"], ph[kind]["tint_strength"]
    else:
        t, s = common.hex_rgb(spec["color"]), 0.35
    return tint(base, t, s)
