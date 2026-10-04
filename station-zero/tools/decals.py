"""Optional raws: terrain decals (2x2) and sleeping poses (2x2) (spec 3.10)."""
from PIL import Image

import common
import sheets


def remove_magenta_cast(im, art):
    """The generated decal blobs carry a soft magenta/pink glow inside their dark outline (the key colour bled into the
    feathered rim, far wider than the 2 px defringe reaches). Where blue exceeds decals.cast_knee x green (earth is R > G > B, so that is
    the pink cast) blue is pulled toward decals.cast_blue_over_green x G, weighted by (B - knee x G) / decals.cast_ramp so
    there is no step at the knee. Pixels below the knee (terracotta, grey stones) are untouched, and so is anything blue-dominant (ice, R < B)."""
    d = art["optional"]["decals"]
    ratio, ramp, knee = d["cast_blue_over_green"], float(d["cast_ramp"]), d["cast_knee"]
    r, g, b, a = im.split()
    rb, gb, bb = r.tobytes(), g.tobytes(), b.tobytes()
    nb = bytearray(bb)
    for i, (rv, gv, bv) in enumerate(zip(rb, gb, bb)):
        if rv >= bv and bv > gv * knee:
            w = min(1.0, (bv - gv * knee) / ramp)
            nb[i] = int(round(bv - (bv - gv * ratio) * w))
    return Image.merge("RGBA", (r, g, Image.frombytes("L", im.size, bytes(nb)), a))


def build_decals(rgb, art):
    """{name: RGBA} in optional.decals.order, keyed, content-cropped, Lanczos to decals.width_px."""
    d = art["optional"]["decals"]
    pieces = sheets.slice_grid(rgb, art, d["grid"][0], d["grid"][1])
    out = {}
    for name, im in zip(d["order"], pieces):
        im = remove_magenta_cast(im, art)
        out[name] = common.recrop(common.scale_to_width(im, d["width_px"]))
    return out


def build_sleeping(rgb, art, jumpsuit_scale):
    """Four gray poses (n = 0..3, TL TR BL BR), scaled with the jumpsuit scale, centred in a cell_px cell at pivot_px.
    Returns (poses, scales used)."""
    s = art["optional"]["sleeping"]
    pieces = sheets.slice_grid(rgb, art, s["grid"][0], s["grid"][1])
    cell = s["cell_px"]
    px, py = s["pivot_px"]
    out, used = [], []
    for im in pieces[:s["poses"]]:
        sc = jumpsuit_scale
        fit = (cell - 4) / float(max(im.size))
        if max(im.size) * sc > cell - 4:
            sc = round(fit, 6)          # a pose wider than the cell: shrink (reported by the caller)
        used.append(sc)
        nw = max(1, int(round(im.size[0] * sc)))
        nh = max(1, int(round(im.size[1] * sc)))
        sm = common.resize_clean(im, (nw, nh))
        bb = sm.getchannel("A").getbbox()
        cx, cy = (bb[0] + bb[2]) / 2.0, (bb[1] + bb[3]) / 2.0
        left = int(round(px - cx))
        top = int(round(py - cy))
        left = max(1 - bb[0], min(cell - 1 - bb[2], left))
        top = max(1 - bb[1], min(cell - 1 - bb[3], top))
        canvas = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        canvas.paste(sm, (left, top))
        out.append(canvas)
    return out, used
