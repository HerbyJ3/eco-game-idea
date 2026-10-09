"""Sheet slicing (spec 3.4 rule 4, 3.5, 3.10, plan A1): grid detection, per-cell keying, shared scale, feet pivot, lamp anchors."""
from PIL import Image, ImageChops, ImageFilter

import common


# ------------------------------------------------------------------------------------------------ grid detection
def _profile(rgb, axis, art):
    """Fraction (0..255) of 'dark and not magenta' pixels per column (axis 0) or per row (axis 1)."""
    s = art["pipeline"]["sheet"]
    k = art["pipeline"]["key"]
    luma = rgb.convert("L")
    dark = luma.point(lambda v: 255 if v < s["separator_luma_max"] else 0)
    notmag = ImageChops.invert(common.key_mask(rgb, k["r_min"], k["b_min"], k["g_max"]))
    d = ImageChops.multiply(dark, notmag)
    w, h = d.size
    prof = d.resize((w, 1), Image.BOX) if axis == 0 else d.resize((1, h), Image.BOX)
    return list(prof.getdata())


def _lines(prof, min_frac):
    thr = min_frac * 255
    out, start = [], None
    for i, v in enumerate(prof):
        if v >= thr:
            if start is None:
                start = i
        elif start is not None:
            out.append((start, i - 1))
            start = None
    if start is not None:
        out.append((start, len(prof) - 1))
    return out


def detect_segments(rgb, axis, n, art):
    """Return n (start, end_exclusive) segments of cell content along an axis, separator lines excluded.
    Separators found from the dark-line profile; if the line count does not match, snap to equal multiples (grid_snap_px)."""
    s = art["pipeline"]["sheet"]
    size = rgb.size[axis]
    lines = _lines(_profile(rgb, axis, art), s["separator_min_run_frac"])
    inner = [ln for ln in lines if ln[0] > 3 and ln[1] < size - 4]
    segs = None
    if len(inner) == n - 1:
        bounds = []
        prev_end = 0
        for ln in inner:
            bounds.append((prev_end, ln[0]))
            prev_end = ln[1] + 1
        bounds.append((prev_end, size))
        segs = bounds          # border lines (a frame at the very edge) are trimmed by the inset anyway
    if segs is None:
        step = s["grid_snap_px"] if size % s["grid_snap_px"] == 0 and size // s["grid_snap_px"] == n else size / float(n)
        segs = [(int(round(i * step)), int(round((i + 1) * step))) for i in range(n)]
    return segs


def cell_boxes(rgb, art, cols, rows):
    inset = art["pipeline"]["sheet"]["cell_inset_px"]
    xs = detect_segments(rgb, 0, cols, art)
    ys = detect_segments(rgb, 1, rows, art)
    boxes = {}
    for r, (y0, y1) in enumerate(ys):
        for c, (x0, x1) in enumerate(xs):
            boxes[(c, r)] = (x0 + inset, y0 + inset, x1 - inset, y1 - inset)
    return boxes, xs, ys


def key_cell(rgb, box, art):
    """Key one cell crop; opaque pieces that touch the crop border (separator leftovers) are removed."""
    cell = rgb.crop(box)
    rgba = common.key_magenta(cell, art)
    a = rgba.getchannel("A")
    w, h = a.size
    mask = a.point(lambda v: 255 if v > 0 else 0)
    comps = [c for c in common.components(mask, w, h) if c["border"]]
    if comps:
        data = bytearray(a.tobytes())
        common.clear_runs(data, w, comps)
        rgba.putalpha(Image.frombytes("L", (w, h), bytes(data)))
    return rgba


# ------------------------------------------------------------------------------------------------ lamp anchor
def find_lamp(rgba, art):
    """Centre of the brightest 3x3 block (mean luma >= lamp.luma_min, all pixels opaque) inside the top head_frac of the opaque
    height; None when there is none. Coordinates in the image of `rgba`, pixel-centre convention (x + 0.5)."""
    lp = art["pipeline"]["lamp"]
    w = art["pipeline"]["masks"]["luma_weights"]
    bb = rgba.getchannel("A").getbbox()
    x0, y0, x1, y1 = bb
    lum = rgba.convert("RGB").convert("L", (w[0], w[1], w[2], 0))
    blk = lp["block_px"]
    mean = lum.filter(ImageFilter.BoxBlur(blk // 2))
    solid = rgba.getchannel("A").point(lambda v: 255 if v >= 250 else 0).filter(ImageFilter.MinFilter(blk))
    mp, sp = mean.load(), solid.load()
    ymax = y0 + int(lp["head_frac"] * (y1 - y0))
    cx = (x0 + x1) / 2.0
    best = None
    for y in range(y0, ymax + 1):
        for x in range(x0, x1):
            if sp[x, y] != 255 or mp[x, y] < lp["luma_min"]:
                continue
            key = (mp[x, y], -abs(x + 0.5 - cx), -y)
            if best is None or key > best[0]:
                best = (key, x + 0.5, y + 0.5)
    return None if best is None else (best[1], best[2])


# ------------------------------------------------------------------------------------------------ character sheet
def frame_names(sheet, art):
    out = ["walk_front_%d" % i for i in range(4)] + ["walk_back_%d" % i for i in range(4)] + \
          ["walk_side_%d" % i for i in range(4)]
    return out + list(art["sheets"][sheet]["extras"])


def frame_cells(art):
    rows = art["sheets"]["rows"]
    return [(i, rows["walk_front"]) for i in range(4)] + [(i, rows["walk_back"]) for i in range(4)] + \
           [(i, rows["walk_side"]) for i in range(4)] + [(i, rows["extras"]) for i in range(4)]


def _centroid_x(rgba, bb):
    a = rgba.getchannel("A").crop(bb)
    w, h = a.size
    col = a.point(lambda v: 1 if v > 0 else 0).resize((w, 1), Image.BOX)
    tot = sum(col.getdata())
    if tot == 0:
        return (bb[0] + bb[2]) / 2.0
    num = sum((i + 0.5) * v for i, v in enumerate(col.getdata()))
    return bb[0] + num / tot


def build_sheet(rgb, sheet, art, log=None):
    """Returns (atlas RGBA, json dict, scale)."""
    p = art["pipeline"]
    cell = p["character_cell_px"]
    gx, gy = p["atlas_grid"]
    boxes, xs, ys = cell_boxes(rgb, art, gx, gy)
    if log:
        log("sheet %s: column segments %s row segments %s" % (sheet, xs, ys))
    frames = []
    for (c, r) in frame_cells(art):
        k = key_cell(rgb, boxes[(c, r)], art)
        bb = k.getchannel("A").getbbox()
        if bb is None:
            raise ValueError("sheet %s: cell (%d,%d) is empty after keying" % (sheet, c, r))
        frames.append((k, bb))
    max_h = max(bb[3] - bb[1] for _, bb in frames)
    max_w = max(bb[2] - bb[0] for _, bb in frames)
    scale = min(p["character_height_in_cell_px"] / float(max_h), (cell - 4) / float(max_w))
    scale = round(scale, 6)
    px, py = p["character_pivot_px"]
    atlas = Image.new("RGBA", (cell * gx, cell * gy), (0, 0, 0, 0))
    table = {}
    names = frame_names(sheet, art)
    cells = frame_cells(art)
    for name, (c, r), (k, bb) in zip(names, cells, frames):
        crop = k.crop(bb)
        nw = max(1, int(round(crop.size[0] * scale)))
        nh = max(1, int(round(crop.size[1] * scale)))
        sm = common.resize_clean(crop, (nw, nh))
        sbb = sm.getchannel("A").getbbox()
        # centre by the opaque-mass centroid (stable under swinging limbs), feet bottom on the pivot row
        cxs = (_centroid_x(k, bb) - bb[0]) * scale
        left = int(round(px - cxs))
        top = py - sbb[3]
        left = max(1 - sbb[0], min(cell - 1 - sbb[2], left))
        sub = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        sub.paste(sm, (left, top))
        atlas.paste(sub, (c * cell, r * cell))
        fb = sub.getchannel("A").getbbox()
        anchor = None
        if sheet in ("eva", "construction"):
            if name.startswith("walk_back"):
                f = art["sheets"]["lamp_anchor_back_frac"]
                anchor = [fb[0] + f[0] * (fb[2] - fb[0]), fb[1] + f[1] * (fb[3] - fb[1])]
            else:
                lamp = find_lamp(k, art)
                if lamp is None:
                    anchor = [(fb[0] + fb[2]) / 2.0, float(fb[1])]
                else:
                    anchor = [left + (lamp[0] - bb[0]) * scale,
                              top + (lamp[1] - bb[1]) * scale]
                    anchor[0] = min(max(anchor[0], fb[0]), fb[2])
                    anchor[1] = min(max(anchor[1], fb[1]), fb[1] + art["pipeline"]["lamp"]["head_frac"] * (fb[3] - fb[1]))
            anchor = [round(anchor[0], 2), round(anchor[1], 2)]
        table[name] = {"col": c, "row": r, "lamp_anchor_px": anchor}
    js = {"cell_px": cell, "pivot_px": [px, py], "scale": scale, "frames": table}
    return atlas, js, scale


# ------------------------------------------------------------------------------------------------ 2x2 grids
def slice_grid(rgb, art, cols, rows):
    """Keyed, content-cropped RGBA pieces of a cols x rows grid on magenta, in row-major order."""
    boxes, _, _ = cell_boxes(rgb, art, cols, rows)
    out = []
    for r in range(rows):
        for c in range(cols):
            k = key_cell(rgb, boxes[(c, r)], art)
            out.append(common.crop_to_alpha(k))
    return out
