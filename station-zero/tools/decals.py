"""Optional raws: terrain decals (2x2) and sleeping poses (2x2) (spec 3.10)."""
from PIL import Image

import common
import sheets


def build_decals(rgb, art):
    """{name: RGBA} in optional.decals.order, keyed, content-cropped, Lanczos to decals.width_px."""
    d = art["optional"]["decals"]
    pieces = sheets.slice_grid(rgb, art, d["grid"][0], d["grid"][1])
    out = {}
    for name, im in zip(d["order"], pieces):
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
