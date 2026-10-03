"""Shared helpers of the Station Zero asset pipeline: art.json, raw lookup, keying, erosion, de-fringe, crop, scale.

Pillow only (no numpy). Everything is deterministic: no random numbers, no timestamps.
Spec: docs/specs/sprite-view.md section 3.
"""
import hashlib
import json
import re
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

TOOLS_DIR = Path(__file__).resolve().parent
ROOT = TOOLS_DIR.parent                      # station-zero/
ART_PATH = ROOT / "data" / "art.json"


def load_art(root=None):
    p = (Path(root) if root else ROOT) / "data" / "art.json"
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_file(p):
    return sha256_bytes(Path(p).read_bytes())


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def luma(r, g, b, w):
    return w[0] * r + w[1] * g + w[2] * b


# ------------------------------------------------------------------------------------------------ raw lookup
class RawFinder:
    """Spec 3.4: search pipeline.raw_dirs in order, first match wins, raw_ignore names are never read."""

    def __init__(self, root, art):
        self.root = Path(root)
        self.dirs = list(art["pipeline"]["raw_dirs"])
        self.ignore = set(art["pipeline"]["raw_ignore"])

    def find(self, name):
        if name in self.ignore:
            return None
        for d in self.dirs:
            p = self.root / d / name
            if p.is_file():
                return p
        return None

    def rel(self, path):
        """Manifest `raw` value: the path relative to the project root, posix separators (may start with ../)."""
        import os
        return Path(os.path.relpath(str(path), str(self.root))).as_posix()


def save_png(im, path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, format="PNG", optimize=False, compress_level=6)


def load_rgb(path):
    im = Image.open(path)
    im.load()
    return im.convert("RGB")


# ------------------------------------------------------------------------------------------------ run-based components
def _threshold_bytes(im, conds):
    """conds: list of (channel index, 'gt'|'lt', value). Returns bytes with 255 where all hold."""
    bands = im.split()
    out = None
    for ch, op, v in conds:
        if op == "gt":
            m = bands[ch].point(lambda x, v=v: 255 if x > v else 0)
        else:
            m = bands[ch].point(lambda x, v=v: 255 if x < v else 0)
        out = m if out is None else ImageChops.multiply(out, m)
    return out


def key_mask(im, r_min, b_min, g_max):
    """L image, 255 where R > r_min, B > b_min and G < g_max."""
    return _threshold_bytes(im, [(0, "gt", r_min), (2, "gt", b_min), (1, "lt", g_max)])


_RUN = re.compile(rb"\xff+")


def components(mask, w, h):
    """4-connected components of the 255 pixels of an L mask image, via horizontal runs and union-find.
    Returns a list of dicts {size, border, runs:[(y, x0, x1)]} in deterministic order."""
    data = mask.tobytes()
    runs = []                    # (y, x0, x1) inclusive
    by_row = []
    for y in range(h):
        row = data[y * w:(y + 1) * w]
        rr = []
        for m in _RUN.finditer(row):
            rr.append(len(runs))
            runs.append((y, m.start(), m.end() - 1))
        by_row.append(rr)
    parent = list(range(len(runs)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for y in range(1, h):
        a, b = by_row[y - 1], by_row[y]
        if not a or not b:
            continue
        i = 0
        for jb in b:
            _, bx0, bx1 = runs[jb]
            while i < len(a) and runs[a[i]][2] < bx0:
                i += 1
            k = i
            while k < len(a) and runs[a[k]][1] <= bx1:
                ra, rb = find(a[k]), find(jb)
                if ra != rb:
                    parent[max(ra, rb)] = min(ra, rb)
                k += 1
    groups = {}
    order = []
    for idx in range(len(runs)):
        r = find(idx)
        if r not in groups:
            groups[r] = []
            order.append(r)
        groups[r].append(idx)
    out = []
    for r in order:
        rl = [runs[i] for i in groups[r]]
        size = sum(x1 - x0 + 1 for _, x0, x1 in rl)
        border = any(y in (0, h - 1) or x0 == 0 or x1 == w - 1 for y, x0, x1 in rl)
        out.append({"size": size, "border": border, "runs": rl})
    return out


def clear_runs(alpha_bytes, w, comps):
    for c in comps:
        for y, x0, x1 in c["runs"]:
            o = y * w
            alpha_bytes[o + x0:o + x1 + 1] = bytes(x1 - x0 + 1)


# ------------------------------------------------------------------------------------------------ keying
def key_magenta(rgb, art):
    """Spec 3.4 rules 1, 1b and 2 (erosion). Returns RGBA at raw size with the alpha edge eroded and pink fringe
    removed. Colours of transparent pixels are left as they are (premultiplied resizing ignores them)."""
    k = art["pipeline"]["key"]
    w, h = rgb.size
    thr = key_mask(rgb, k["r_min"], k["b_min"], k["g_max"])
    alpha = bytearray(b"\xff" * (w * h))
    comps = components(thr, w, h)
    pure = key_mask(rgb, k["pure_r_min"], k["pure_b_min"], k["pure_g_max"])
    pure_bytes = pure.tobytes()

    rb, gb, bb = (x.tobytes() for x in rgb.split())

    def has_pure(c):
        """Background pocket: it holds near-pure magenta, or its mean colour is magenta-like (a gap whose pixels are all blended)."""
        if any(b"\xff" in pure_bytes[y * w + x0:y * w + x1 + 1] for y, x0, x1 in c["runs"]):
            return True
        n = c["size"]
        mr = sum(sum(rb[y * w + x0:y * w + x1 + 1]) for y, x0, x1 in c["runs"]) / n
        mg = sum(sum(gb[y * w + x0:y * w + x1 + 1]) for y, x0, x1 in c["runs"]) / n
        mb = sum(sum(bb[y * w + x0:y * w + x1 + 1]) for y, x0, x1 in c["runs"]) / n
        return mr > k["pocket_mean_r_min"] and mb > k["pocket_mean_b_min"] and mg < k["pocket_mean_g_max"]

    # rule 1 (border-connected) and the enclosed_min_px extension; rule 1b: a pocket that holds near-pure magenta is background
    # seen through a gap, so its whole threshold region goes (its non-pure rim would otherwise survive as a pink speck)
    remove = [c for c in comps if c["border"] or c["size"] >= k["enclosed_min_px"] or has_pure(c)]
    clear_runs(alpha, w, remove)
    for i, v in enumerate(pure_bytes):
        if v:
            alpha[i] = 0
    a = Image.frombytes("L", (w, h), bytes(alpha))
    return finish_alpha(rgb, a, k)


def finish_alpha(rgb, alpha, k):
    """Erode the alpha edge k.erode_px, then replace pink rim pixels with the colours of the nearest clean pixels."""
    a = alpha
    for _ in range(k["erode_px"]):
        a = a.filter(ImageFilter.MinFilter(3))
    rgb = defringe(rgb, a)
    out = rgb.copy()
    out.putalpha(a)
    return out


def _shift(im, dx, dy):
    return ImageChops.offset(im, dx, dy)


def defringe(rgb, alpha, rim_px=2, pink_min=30):
    """Pixels within rim_px of a transparent pixel whose colour is pinkish (min(R,B) - G >= pink_min) get the colour of the
    nearest non-pink pixel, found by iterative neighbour propagation."""
    r, g, b = rgb.split()
    pink = ImageChops.subtract(ImageChops.darker(r, b), g).point(lambda v: 255 if v >= pink_min else 0)
    size = 2 * rim_px + 1
    deep = alpha.filter(ImageFilter.MinFilter(size)).point(lambda v: 255 if v > 0 else 0)
    opaque = alpha.point(lambda v: 255 if v > 0 else 0)
    rim = ImageChops.subtract(opaque, deep)
    target = ImageChops.multiply(rim, pink)
    if not target.getbbox():
        return rgb
    valid = ImageChops.subtract(opaque, target)       # opaque and not marked for replacement
    col = rgb
    offs = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
    remaining = target
    for _ in range(rim_px + 3):
        new_valid = valid
        new_col = col
        for dx, dy in offs:
            vs = _shift(valid, dx, dy)
            take = ImageChops.multiply(ImageChops.multiply(vs, remaining), ImageChops.invert(new_valid))
            if not take.getbbox():
                continue
            new_col = Image.composite(_shift(col, dx, dy), new_col, take)
            new_valid = ImageChops.lighter(new_valid, take)
        remaining = ImageChops.subtract(remaining, new_valid)
        col, valid = new_col, new_valid
        if not remaining.getbbox():
            break
    # anything still pink (no clean neighbour found) is made transparent by the caller's alpha? keep colour: darken to avoid a pink pixel
    return col


def flood_background(rgb, art):
    """Spec 3.4 rule 3: gray (or any flat) background, flood fill from the four corners with colour distance <= tolerance
    from the corner pixel colour (the comms art has a gray wall frame that is NOT background, so a flat-gray reference
    would eat the wall). Opaque fragments under 1% of the image
    (an edge line the flood did not reach) are dropped; the door corridor of the comms art stays as its own piece. Returns the alpha L image (0 where background)."""
    tol = art["pipeline"]["key"]["gray_bg_tolerance"]
    w, h = rgb.size
    rb, gb, bb = (x.tobytes() for x in rgb.split())
    alpha = bytearray(b"\xff" * (w * h))
    t2 = tol * tol
    for cx, cy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        cr, cg, cb = rgb.getpixel((cx, cy))
        m = bytes(255 if (a - cr) * (a - cr) + (b - cg) * (b - cg) + (c - cb) * (c - cb) <= t2 else 0
                  for a, b, c in zip(rb, gb, bb))
        mimg = Image.frombytes("L", (w, h), m)
        for comp in components(mimg, w, h):
            if any(y == cy and x0 <= cx <= x1 for y, x0, x1 in comp["runs"]):
                clear_runs(alpha, w, [comp])
    a = Image.frombytes("L", (w, h), bytes(alpha))
    comps = components(a.point(lambda v: 255 if v else 0), w, h)
    if len(comps) > 1:
        keep_min = 0.01 * w * h          # fragments below 1% of the image (an edge line the flood missed) are dropped
        drop = [c for c in comps if c["size"] < keep_min]
        data = bytearray(a.tobytes())
        clear_runs(data, w, drop)
        a = Image.frombytes("L", (w, h), bytes(data))
    return a


def is_magenta_corner(rgb, art):
    k = art["pipeline"]["key"]
    w, h = rgb.size
    for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        r, g, b = rgb.getpixel(p)
        if r > k["r_min"] and b > k["b_min"] and g < k["g_max"]:
            return True
    return False


# ------------------------------------------------------------------------------------------------ crop and scale
def crop_to_alpha(im):
    bb = im.getchannel("A").getbbox()
    if bb is None:
        raise ValueError("image is fully transparent after keying")
    return im.crop(bb)


_OFFS8 = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]


def bleed_colors(im, iterations):
    """Fill the RGB of transparent pixels with the colours of the nearest opaque pixels (one pixel per iteration), so a
    resize never mixes in the keyed-out background colour. Alpha is untouched."""
    a = im.getchannel("A")
    valid = a.point(lambda v: 255 if v > 0 else 0)
    col = im.convert("RGB")
    w, h = im.size
    for _ in range(iterations):
        if valid.getextrema()[0] == 255:
            break
        new_valid, new_col = valid, col
        for dx, dy in _OFFS8:
            # a pixel left empty (valid == 0) takes the colour of its neighbour at (-dx, -dy) when that one was valid
            vs = ImageChops.offset(valid, dx, dy)
            take = ImageChops.multiply(vs, ImageChops.invert(new_valid))
            if not take.getbbox():
                continue
            new_col = Image.composite(ImageChops.offset(col, dx, dy), new_col, take)
            new_valid = ImageChops.lighter(new_valid, take)
        col, valid = new_col, new_valid
    return col


def resize_clean(im, size):
    """Lanczos resize of an RGBA image: colour (bled into the transparent area first) and alpha are resampled separately,
    so no pixel inherits the key colour."""
    if tuple(size) == im.size:
        return im.copy()
    scale = min(size[0] / float(im.size[0]), size[1] / float(im.size[1]))
    n = int(3.0 / min(scale, 1.0)) + 2
    rgb = bleed_colors(im, n).resize(size, Image.LANCZOS)
    a = im.getchannel("A").resize(size, Image.LANCZOS)
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def scale_to_width(im, width):
    h = int(round(width * im.size[1] / float(im.size[0])))
    return resize_clean(im, (width, max(1, h)))


def key_and_fit(rgb, art, width):
    """Magenta keying (or gray flood for interiors elsewhere), crop to the alpha bbox, Lanczos to `width`."""
    rgba = crop_to_alpha(key_magenta(rgb, art))
    out = scale_to_width(rgba, width)
    return recrop(out)


def recrop(im):
    """Lanczos can leave an all-zero edge row/column; keep the image tight."""
    bb = im.getchannel("A").getbbox()
    if bb and bb != (0, 0) + im.size:
        im = im.crop(bb)
    return im


# ------------------------------------------------------------------------------------------------ output set
class OutputSet:
    """Collects every file the build produces (relative path -> bytes), writes only files whose bytes changed (so Godot
    does not reimport on a no-op rebuild) and removes stale .png/.json files the build did not produce."""

    def __init__(self, base):
        self.base = Path(base)
        self.files = {}

    def add_png(self, rel, im):
        import io
        buf = io.BytesIO()
        im.save(buf, format="PNG", optimize=False, compress_level=6)
        data = buf.getvalue()
        self.files[rel] = data
        return sha256_bytes(data)

    def add_json(self, rel, obj):
        data = (json.dumps(obj, indent=1, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
        self.files[rel] = data
        return sha256_bytes(data)

    def get_png(self, rel):
        import io
        return Image.open(io.BytesIO(self.files[rel])).convert("RGBA")

    def write(self):
        self.base.mkdir(parents=True, exist_ok=True)
        for rel, data in sorted(self.files.items()):
            p = self.base / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            if p.is_file() and p.read_bytes() == data:
                continue
            p.write_bytes(data)
        keep = set(self.files)
        for p in sorted(self.base.rglob("*")):
            if p.is_file() and p.suffix in (".png", ".json") and p.relative_to(self.base).as_posix() not in keep:
                p.unlink()
        for d in sorted((q for q in self.base.rglob("*") if q.is_dir()), reverse=True):
            try:
                d.rmdir()
            except OSError:
                pass
