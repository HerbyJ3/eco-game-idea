"""Exterior building builder (spec 3.2 to 3.6): key, crop, scale, measure the door, fill it, cut the leaves, build masks."""
from PIL import Image

import common
import doors
import masks as masks_mod


class ExteriorSet:
    """All images of one kind's exterior set, one transform for all (identical pixel size)."""

    def __init__(self, base, door, masks, rect_px, rect_norm, door_mode, measured, prefill):
        self.base, self.door, self.masks = base, door, masks
        self.rect_px, self.rect_norm = rect_px, rect_norm
        self.door_mode, self.measured = door_mode, measured
        self.prefill = prefill


def key_exterior(rgb, art):
    """Magenta keying, crop to the alpha bbox, Lanczos to building_width_px. Returns the pre-fill RGBA base."""
    return common.key_and_fit(rgb, art, art["pipeline"]["building_width_px"])


def assemble(prefill, kind, art, accent_cls, rect_px=None, log=None):
    """Door (measure with fallback unless rect_px is given), fill, leaves, masks."""
    spec = art["kinds"][kind]
    size = prefill.size
    measured = False
    fixed = rect_px is not None            # a given pixel rect (placeholders reuse the habitat rect)
    if rect_px is None:
        r = doors.measure_door(prefill, spec["door_rect"], art)
        if r is None:
            rect_px = doors.rect_from_norm(spec["door_rect"], size)
            if log:
                log("warn: door measurement failed for %s, using the art.json rect %s" % (kind, spec["door_rect"]))
        else:
            rect_px = doors.clamp_rect(r, size)
            measured = True
    base = doors.fill_door(prefill, rect_px, art)
    leaf = doors.cut_leaf(prefill, rect_px)
    ms = masks_mod.build_exterior_masks(base, accent_cls, art)
    rect_norm = doors.norm_rect(rect_px, size) if (measured or fixed) else [float(v) for v in spec["door_rect"]]
    return ExteriorSet(base, leaf, ms, rect_px, rect_norm, spec["door_mode"], measured, prefill)
