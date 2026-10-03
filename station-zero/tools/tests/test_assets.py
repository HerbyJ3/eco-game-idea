"""Tests for the Station Zero asset pipeline (spec docs/specs/sprite-view.md section 3, tests P-0 to P-15).

Written BEFORE the pipeline (Task 2 step 4), so every test that needs processed outputs fails cleanly with
"build_all.py not found" until tools/build_all.py exists.  Pillow only, no numpy, no pytest needed.

Run:  python3 -m unittest discover station-zero/tools/tests -v      (from the repo root)
      python3 -m unittest discover tools/tests -v                    (from station-zero/)
See tools/tests/README.md.

Layout assumed by the temp-copy tests (P-0, P-6 forced fail, P-10 magenta fixture, P-11, P-13..P-15):
build_all.py derives the project root from its own location (<root>/tools/build_all.py), reads <root>/data/art.json,
and resolves pipeline.raw_dirs relative to <root>.  A temp project is  <tmp>/station-zero/{tools,data,assets/raw}
plus a sibling <tmp>/station-zero-handoff/assets/raw, so "../station-zero-handoff/assets/raw" resolves as in the repo.
"""
import atexit
import colorsys
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import traceback
import unittest
from collections import OrderedDict
from pathlib import Path

import PIL
from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent                      # station-zero/
TOOLS = ROOT / "tools"
PROCESSED = ROOT / "assets" / "processed"
BUILD_TIMEOUT_S = 900

with open(ROOT / "data" / "art.json", encoding="utf-8") as _f:
    ART = json.load(_f)

PIPE = ART["pipeline"]
KINDS = list(ART["kinds"])
ROLES = list(PIPE["recolor"]["roles"])
MASKS = ["accent", "windows", "outline", "shadow", "gray", "ghost"]
SHEETS = ["jumpsuit", "eva", "construction"]
SHEET_RAW = {"jumpsuit": "sheet_colonist_jumpsuit.png", "eva": "sheet_eva_suit.png",
             "construction": "sheet_construction_suit.png"}
SHEET_ATLAS = {"jumpsuit": ["jumpsuit_" + r for r in ROLES], "eva": ["eva"], "construction": ["construction"]}
DECALS = list(ART["optional"]["decals"]["order"])
SLEEP_N = range(ART["optional"]["sleeping"]["poses"])
MB = 1_000_000  # spec 10: 15.7 MB for 42 images of 384x244x4 means decimal MB

_TMP_DIRS = []


def _cleanup():
    for d in _TMP_DIRS:
        shutil.rmtree(d, ignore_errors=True)


atexit.register(_cleanup)


# --------------------------------------------------------------------------------------------- build plumbing
class BuildResult:
    def __init__(self, ok, message, output=""):
        self.ok, self.message, self.output = ok, message, output


def run_build(root):
    """Run `python3 tools/build_all.py` with cwd = project root."""
    script = Path(root) / "tools" / "build_all.py"
    if not script.is_file():
        return BuildResult(False, "build_all.py not found at %s (pipeline not written yet, steps 5 to 8)" % script)
    try:
        p = subprocess.run([sys.executable, str(script)], cwd=str(root), capture_output=True, text=True,
                           timeout=BUILD_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        return BuildResult(False, "build_all.py timed out after %d s" % BUILD_TIMEOUT_S)
    out = (p.stdout or "") + (p.stderr or "")
    if p.returncode != 0:
        return BuildResult(False, "build_all.py exited with code %d. Last output:\n%s" % (p.returncode, out[-1500:]), out)
    return BuildResult(True, "", out)


_MAIN = {}


def main_build():
    """The once-per-session build of the real project (the session fixture)."""
    if "r" not in _MAIN:
        _MAIN["r"] = run_build(ROOT)
    return _MAIN["r"]


def sha_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha_file(p):
    return sha_bytes(Path(p).read_bytes())


def snapshot(dirpath):
    """{relative posix path: sha256} for every file under dirpath."""
    out = {}
    base = Path(dirpath)
    for p in sorted(base.rglob("*")):
        if p.is_file():
            out[p.relative_to(base).as_posix()] = sha_file(p)
    return out


def load_manifest(processed):
    p = Path(processed) / "manifest.json"
    with open(p, encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=OrderedDict)


def resolve_raw(root, name):
    """Reference implementation of the raw lookup (spec 3.4): raw_dirs in order, first match, raw_ignore never."""
    if name in PIPE["raw_ignore"]:
        return None
    for d in PIPE["raw_dirs"]:
        p = (Path(root) / d / name)
        if p.is_file():
            return p
    return None


def raw_name_for(entry_id):
    parts = entry_id.split(".")
    if parts[0] == "building":
        kind = parts[1]
        if parts[2] in ("interior", "interior_outline"):
            return ART["kinds"][kind]["raw_interior"]
        return ART["kinds"][kind]["raw_exterior"]
    if parts[0] == "character":
        if parts[1] == "jumpsuit":
            return SHEET_RAW["jumpsuit"]
        if parts[1] == "eva":
            return SHEET_RAW["eva"]
        if parts[1] == "construction":
            return SHEET_RAW["construction"]
        if parts[1] == "sleeping":
            return ART["optional"]["raw_sleeping"]
    if parts[0] == "terrain":
        return ART["optional"]["raw_decals"]
    raise AssertionError("unknown entry id " + entry_id)


def expected_ids():
    ids = []
    for k in KINDS:
        ids += ["building.%s.base" % k, "building.%s.door" % k]
        ids += ["building.%s.mask.%s" % (k, m) for m in MASKS]
        ids += ["building.%s.interior" % k, "building.%s.interior_outline" % k]
    ids += ["character.jumpsuit.%s" % r for r in ROLES] + ["character.eva", "character.construction"]
    ids += ["character.sleeping.%s.%d" % (r, n) for r in ROLES for n in SLEEP_N]
    ids += ["terrain.decal.%s" % d for d in DECALS]
    return sorted(ids)


# --------------------------------------------------------------------------------------------- image helpers
def open_rgba(path):
    im = Image.open(path)
    im.load()
    return im.convert("RGBA")


def alpha_extrema(im):
    return im.getchannel("A").getextrema()


def lum(r, g, b):
    w = PIPE["masks"]["luma_weights"]
    return w[0] * r + w[1] * g + w[2] * b


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def is_key_colour(r, g, b):
    k = PIPE["key"]
    return r > k["r_min"] and b > k["b_min"] and g < k["g_max"]


def is_pure_magenta(r, g, b):
    k = PIPE["key"]
    return r > k["pure_r_min"] and b > k["pure_b_min"] and g < k["pure_g_max"]


def count_pure_magenta(im):
    return sum(1 for r, g, b, a in im.getdata() if a > 0 and is_pure_magenta(r, g, b))


def key_survivor_components(im):
    """Components (4-connected) of alpha>0 threshold-colour pixels that are 'border-connected' (touch the image
    border or a transparent pixel) or have at least key.enclosed_min_px pixels.  Rule 1 and 1b say none may remain."""
    w, h = im.size
    pix = im.load()
    seen = bytearray(w * h)
    bad = []
    emin = PIPE["key"]["enclosed_min_px"]

    def passes(x, y):
        r, g, b, a = pix[x, y]
        return a > 0 and is_key_colour(r, g, b)

    for y in range(h):
        for x in range(w):
            if seen[y * w + x] or not passes(x, y):
                continue
            stack = [(x, y)]
            seen[y * w + x] = 1
            size, touches = 0, False
            while stack:
                cx, cy = stack.pop()
                size += 1
                if cx in (0, w - 1) or cy in (0, h - 1):
                    touches = True
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h:
                        if pix[nx, ny][3] == 0:
                            touches = True
                        elif not seen[ny * w + nx] and passes(nx, ny):
                            seen[ny * w + nx] = 1
                            stack.append((nx, ny))
            if touches or size >= emin:
                bad.append((x, y, size, touches))
    return bad


def edge_mean_r_minus_g(im):
    w, h = im.size
    pix = im.load()
    tot, n = 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if a == 0:
                continue
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h and pix[nx, ny][3] == 0:
                    tot += r - g
                    n += 1
                    break
    return (tot / n) if n else 0.0, n


def corners_transparent(im):
    w, h = im.size
    return [im.getpixel(p)[3] for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]


def raw_keyed_bbox(path):
    """Independent, approximate keying of a magenta-background raw (rule 1 border-connected + rule 1b), bbox only."""
    im = Image.open(path).convert("RGB")
    k = PIPE["key"]
    r, g, b = im.split()
    key = ImageChops.multiply(ImageChops.multiply(r.point(lambda v: 255 if v > k["r_min"] else 0),
                                                  b.point(lambda v: 255 if v > k["b_min"] else 0)),
                              g.point(lambda v: 255 if v < k["g_max"] else 0))
    w, h = im.size
    kp = key.load()
    seeds = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + \
            [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    for sx, sy in seeds:
        if kp[sx, sy] == 255:
            ImageDraw.floodfill(key, (sx, sy), 128, thresh=0)
    pure = ImageChops.multiply(ImageChops.multiply(r.point(lambda v: 255 if v > k["pure_r_min"] else 0),
                                                   b.point(lambda v: 255 if v > k["pure_b_min"] else 0)),
                               g.point(lambda v: 255 if v < k["pure_g_max"] else 0))
    solid = ImageChops.subtract(key.point(lambda v: 255 if v != 128 else 0), pure)
    return solid.getbbox()


def disc_offsets(radius):
    r = int(math.floor(radius))
    return [(dx, dy) for dy in range(-r, r + 1) for dx in range(-r, r + 1) if dx * dx + dy * dy <= radius * radius + 1e-9]


def accent_pred(cls):
    m = PIPE["masks"]["accent_" + cls]
    if cls == "cyan":
        return lambda r, g, b: b >= m["b_min"] and g >= m["g_min"] and r <= m["r_max"] and b - r >= m["b_minus_r_min"]
    if cls == "amber":
        return lambda r, g, b: (r >= m["r_min"] and m["g_min"] <= g <= m["g_max"] and b <= m["b_max"]
                                and r - b >= m["r_minus_b_min"])
    if cls == "violet":
        return lambda r, g, b: m["r_min"] <= r <= m["r_max"] and b >= m["b_min"] and g <= m["g_max"]
    if cls == "pink":
        return lambda r, g, b: (r >= m["r_min"] and g <= m["g_max"] and m["b_min"] <= b <= m["b_max"]
                                and r - g >= m["r_minus_g_min"])
    raise AssertionError(cls)


def windows_pred():
    m = PIPE["masks"]["windows"]
    return lambda r, g, b: (b >= m["b_min"] and r <= m["r_max"] and m["g_min"] <= g <= m["g_max"]
                            and b - g >= m["b_minus_g_min"])


def cell_bbox(atlas, col, row, cell):
    return atlas.crop((col * cell, row * cell, (col + 1) * cell, (row + 1) * cell)).getchannel("A").getbbox()


def is_suit_gray(r, g, b):
    rc = PIPE["recolor"]
    h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    return s < rc["sat_max"] and rc["value_min"] <= v <= rc["value_max"] and not v < rc["outline_value_max"]


def recolor_stats(imgs):
    """imgs: {role: RGBA image}, same geometry.  Everything is inferred from the outputs alone: a pixel that
    differs between role atlases was recolored; a pixel identical in all roles was not.  A not-recolored opaque pixel
    that is still suit-gray counts as a miss.  Returns fractions and per-role statistics."""
    roles = list(imgs)
    data = {r: list(imgs[r].getdata()) for r in roles}
    base = data[roles[0]]
    n = len(base)
    alpha_equal = all(all(data[r][i][3] == base[i][3] for i in range(n)) for r in roles[1:])
    changed = 0
    missed = 0
    sums = {r: [0, 0, 0, 0] for r in roles}
    ratio_ok = {r: [0, 0] for r in roles}
    cols = {r: hex_rgb(PIPE["recolor"]["roles"][r]) for r in roles}
    for i in range(n):
        p = base[i]
        if p[3] < 250:
            continue
        if all(data[r][i] == p for r in roles[1:]):
            if is_suit_gray(p[0], p[1], p[2]):
                missed += 1
            continue
        changed += 1
        for r in roles:
            q = data[r][i]
            s = sums[r]
            s[0] += q[0]; s[1] += q[1]; s[2] += q[2]; s[3] += 1
            if min(q[:3]) >= 40 and max(q[:3]) <= 250:
                rat = [q[c] / float(cols[r][c]) for c in range(3)]
                ratio_ok[r][1] += 1
                if max(rat) - min(rat) <= 0.10:
                    ratio_ok[r][0] += 1
    means = {r: ((sums[r][0] / sums[r][3], sums[r][1] / sums[r][3], sums[r][2] / sums[r][3]) if sums[r][3] else None)
             for r in roles}
    return {"alpha_equal": alpha_equal, "changed": changed, "missed": missed,
            "frac": changed / float(changed + missed) if (changed + missed) else 0.0,
            "means": means, "ratio_ok": ratio_ok, "cols": cols, "opaque": sum(1 for p in base if p[3] >= 250)}


def face_region_changes(imgs, cell, col, row, frac=0.18):
    """Pixels changed between roles inside the top `frac` of the opaque box of one cell (idle_front face region)."""
    roles = list(imgs)
    crops = {r: imgs[r].crop((col * cell, row * cell, (col + 1) * cell, (row + 1) * cell)) for r in roles}
    bb = crops[roles[0]].getchannel("A").getbbox()
    if not bb:
        return None
    x0, y0, x1, y1 = bb
    y_end = y0 + max(1, int(round((y1 - y0) * frac)))
    c0 = crops[roles[0]]
    diff = 0
    for y in range(y0, y_end):
        for x in range(x0, x1):
            p = c0.getpixel((x, y))
            if p[3] == 0:
                continue
            if any(crops[r].getpixel((x, y)) != p for r in roles[1:]):
                diff += 1
    return diff


# --------------------------------------------------------------------------------------------- synthetic fixtures
MAGENTA = (255, 0, 255)


def _gradient_rect(draw, box, lo, hi, horizontal=True):
    x0, y0, x1, y1 = box
    span = (x1 - x0) if horizontal else (y1 - y0)
    for i in range(span):
        v = int(lo + (hi - lo) * i / max(1, span - 1))
        if horizontal:
            draw.line([(x0 + i, y0), (x0 + i, y1 - 1)], fill=(v, v, v))
        else:
            draw.line([(x0, y0 + i), (x1 - 1, y0 + i)], fill=(v, v, v))


def synth_decals():
    """1024x1024 magenta, dark 4 px separators at the middle, four distinct colour ellipses (ice, pit, rocks, crater)."""
    im = Image.new("RGB", (1024, 1024), MAGENTA)
    d = ImageDraw.Draw(im)
    cols = {"ice": (90, 200, 240), "pit": (120, 70, 30), "rocks": (150, 130, 110), "crater": (200, 60, 40)}
    centres = {"ice": (256, 256), "pit": (768, 256), "rocks": (256, 768), "crater": (768, 768)}
    for name, (cx, cy) in centres.items():
        d.ellipse([cx - 150, cy - 130, cx + 150, cy + 130], fill=cols[name])
    d.rectangle([510, 0, 513, 1023], fill=(0, 0, 0))
    d.rectangle([0, 510, 1023, 513], fill=(0, 0, 0))
    return im, cols


SLEEP_PATCH = {0: (30, 160, 60), 1: (200, 40, 40), 2: (40, 60, 200), 3: (230, 200, 40)}


def synth_sleeping():
    """2x2 sleeping poses on magenta: gray suit body (shaded), skin head, dark outline, a coloured patch per pose."""
    im = Image.new("RGB", (1024, 1024), MAGENTA)
    d = ImageDraw.Draw(im)
    for n in range(4):
        cx, cy = 256 + 512 * (n % 2), 256 + 512 * (n // 2)
        d.rectangle([cx - 112, cy - 38, cx + 112, cy + 38], fill=(15, 15, 15))
        _gradient_rect(d, (cx - 108, cy - 34, cx + 109, cy + 35), 110, 200)
        d.ellipse([cx - 150, cy - 28, cx - 100, cy + 22], fill=(235, 190, 160))
        px = SLEEP_PATCH[n]
        d.rectangle([cx - 20, cy - 24, cx + 19, cy + 15], fill=px)
    d.rectangle([510, 0, 513, 1023], fill=(0, 0, 0))
    d.rectangle([0, 510, 1023, 513], fill=(0, 0, 0))
    return im


SHEET_SEP_X = [238, 497, 770]
SHEET_SEP_Y = [243, 501, 760]
SHEET_SEP_W = 5


def _hsv_marker(i):
    r, g, b = colorsys.hsv_to_rgb(i * 0.045, 0.9, 0.9)
    return (int(r * 255), int(g * 255), int(b * 255))


def synth_sheet_offgrid():
    """1024 sheet whose separator lines are NOT on multiples of 256.  Every cell holds a gray figure with a 40x40
    marker near its left edge (so a snap to 256 would cut it).  Marker colour encodes the cell index."""
    im = Image.new("RGB", (1024, 1024), MAGENTA)
    d = ImageDraw.Draw(im)
    xs = [0] + [x + SHEET_SEP_W for x in SHEET_SEP_X]
    xe = SHEET_SEP_X + [1024]
    ys = [0] + [y + SHEET_SEP_W for y in SHEET_SEP_Y]
    ye = SHEET_SEP_Y + [1024]
    markers = {}
    for r in range(4):
        for c in range(4):
            x0, y0 = xs[c], ys[r]
            d.rectangle([x0 + 8, y0 + 24, x0 + 158, ye[r] - 20], fill=(140, 140, 140))
            col = _hsv_marker(r * 4 + c)
            d.rectangle([x0 + 8, y0 + 28, x0 + 47, y0 + 67], fill=col)
            markers[(c, r)] = col
    for x in SHEET_SEP_X:
        d.rectangle([x, 0, x + SHEET_SEP_W - 1, 1023], fill=(10, 10, 10))
    for y in SHEET_SEP_Y:
        d.rectangle([0, y, 1023, y + SHEET_SEP_W - 1], fill=(10, 10, 10))
    return im, markers


INTERIOR_HOLE = (600, 400)
INTERIOR_WALL = (60, 50, 1204, 798)


def synth_interior_magenta():
    """1264x848 interior on a MAGENTA background: rounded wall, floor, and an enclosed pure-magenta hole (rule 1b)."""
    im = Image.new("RGB", (1264, 848), MAGENTA)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle(INTERIOR_WALL, radius=70, fill=(120, 110, 100))
    d.rounded_rectangle([90, 80, 1174, 768], radius=40, fill=(90, 80, 70))
    hx, hy = INTERIOR_HOLE
    d.rectangle([hx - 20, hy - 20, hx + 19, hy + 19], fill=MAGENTA)
    return im


def synth_flat_exterior():
    """A uniform gray building with no door at all: door measurement cannot succeed."""
    im = Image.new("RGB", (1024, 1024), MAGENTA)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([100, 250, 924, 800], radius=30, fill=(180, 175, 170))
    return im


# --------------------------------------------------------------------------------------------- temp projects
class Project:
    def __init__(self, base):
        self.base = Path(base)
        self.root = self.base / "station-zero"
        self.raw = self.root / "assets" / "raw"
        self.handoff = self.base / "station-zero-handoff" / "assets" / "raw"
        self.processed = self.root / "assets" / "processed"


def make_project(label, drop_from_handoff=()):
    base = Path(tempfile.mkdtemp(prefix="sz_%s_" % label))
    _TMP_DIRS.append(str(base))
    p = Project(base)
    if (TOOLS / "build_all.py").is_file():
        shutil.copytree(TOOLS, p.root / "tools", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    else:
        (p.root / "tools").mkdir(parents=True)
    shutil.copytree(ROOT / "data", p.root / "data")
    p.raw.mkdir(parents=True)
    p.handoff.mkdir(parents=True)
    for d in reversed(PIPE["raw_dirs"]):      # lower priority first, so a name in the higher one wins the copy
        src = (ROOT / d)
        if src.is_dir():
            for f in src.glob("*.png"):
                if f.name in PIPE["raw_ignore"] or f.name in drop_from_handoff:
                    continue
                shutil.copy(f, p.handoff / f.name)
    return p


class Scenario:
    def __init__(self, ok, message, **kw):
        self.ok, self.message = ok, message
        self.__dict__.update(kw)


_SCEN = {}


def get_scenario(name, builder):
    if name not in _SCEN:
        try:
            _SCEN[name] = builder()
        except Exception:
            _SCEN[name] = Scenario(False, "scenario %s crashed:\n%s" % (name, traceback.format_exc()[-1500:]))
    return _SCEN[name]


def build_syn():
    """P-0 / P-6 forced failure / P-10 magenta fixture / P-9 off-grid sheet in ONE temp build."""
    p = make_project("syn")
    garbage = b"this is not an image and must never be read"
    (p.raw / "old_pixel_habitat_test.png").write_bytes(garbage)
    (p.handoff / "old_pixel_habitat_test.png").write_bytes(garbage)
    synth_interior_magenta().save(p.raw / "habitat_interior.png")        # also present (different) in handoff
    synth_flat_exterior().save(p.raw / "archive_exterior.png")           # no door: forced measurement failure
    sheet, markers = synth_sheet_offgrid()
    sheet.save(p.raw / "sheet_construction_suit.png")
    res = run_build(p.root)
    if not res.ok:
        return Scenario(False, res.message, proj=p)
    return Scenario(True, "", proj=p, output=res.output, markers=markers,
                    manifest=load_manifest(p.processed))


def build_flip():
    """P-15: baseline (no optional raws, no green_room exterior), drop them in, remove them again."""
    p = make_project("flip", drop_from_handoff=("greenroom_exterior.png",))
    r1 = run_build(p.root)
    if not r1.ok:
        return Scenario(False, r1.message, proj=p)
    text1 = (p.processed / "manifest.json").read_text(encoding="utf-8")
    m1 = load_manifest(p.processed)
    # drop the raws into the FIRST raw_dirs entry (assets/raw)
    real_green = resolve_raw(ROOT, "greenroom_exterior.png")
    green_bytes = real_green.read_bytes() if real_green else None
    if green_bytes is None:
        return Scenario(False, "greenroom_exterior.png not found in %s" % PIPE["raw_dirs"], proj=p)
    (p.raw / "greenroom_exterior.png").write_bytes(green_bytes)
    synth_decals()[0].save(p.raw / ART["optional"]["raw_decals"])
    synth_sleeping().save(p.raw / ART["optional"]["raw_sleeping"])
    # hash the dropped raws now: they are deleted again below, so the tests cannot hash them later
    dropped_sha = {n: sha_file(p.raw / n) for n in ("greenroom_exterior.png", ART["optional"]["raw_decals"],
                                                    ART["optional"]["raw_sleeping"])}
    r2 = run_build(p.root)
    if not r2.ok:
        return Scenario(False, "after dropping raws: " + r2.message, proj=p)
    m2 = load_manifest(p.processed)
    snap_drop = p.base / "snap_drop"
    shutil.copytree(p.processed, snap_drop)
    for n in ("greenroom_exterior.png", ART["optional"]["raw_decals"], ART["optional"]["raw_sleeping"]):
        (p.raw / n).unlink()
    r3 = run_build(p.root)
    if not r3.ok:
        return Scenario(False, "after removing raws: " + r3.message, proj=p)
    text3 = (p.processed / "manifest.json").read_text(encoding="utf-8")
    m3 = load_manifest(p.processed)
    return Scenario(True, "", proj=p, m_base=m1, m_drop=m2, m_back=m3, text_base=text1, text_back=text3,
                    snap_drop=snap_drop, dropped_green_sha=sha_bytes(green_bytes), dropped_sha=dropped_sha)


# --------------------------------------------------------------------------------------------- base test classes
class PipelineCase(unittest.TestCase):
    """Tests against the real project outputs (one build_all run per session)."""
    maxDiff = None

    def setUp(self):
        res = main_build()
        if not res.ok:
            self.fail(res.message)
        self.root = ROOT
        self.processed = PROCESSED
        if not (PROCESSED / "manifest.json").is_file():
            self.fail("build_all.py ran but %s was not written" % (PROCESSED / "manifest.json"))
        self.manifest = load_manifest(PROCESSED)
        self.entries = self.manifest["entries"]

    # helpers
    def entry(self, eid):
        self.assertIn(eid, self.entries, "manifest has no entry %s" % eid)
        return self.entries[eid]

    def image(self, eid):
        e = self.entry(eid)
        self.assertIsNotNone(e.get("file"), "%s has file null" % eid)
        return open_rgba(self.processed / e["file"])

    def kind_is_placeholder(self, kind, part="base"):
        return bool(self.entry("building.%s.%s" % (kind, part))["placeholder"])

    def processed_path(self, rel):
        return self.processed / rel


class ScenarioCase(unittest.TestCase):
    scenario_name = None
    scenario_builder = None
    maxDiff = None

    def setUp(self):
        self.sc = get_scenario(self.scenario_name, self.scenario_builder)
        if not self.sc.ok:
            self.fail(self.sc.message)


# =============================================================================================== P-0 raw lookup
class TestP0RawLookup(ScenarioCase):
    scenario_name, scenario_builder = "syn", staticmethod(build_syn)

    def test_file_only_in_handoff_dir_is_found(self):
        p = self.sc.proj
        e = self.sc.manifest["entries"]["building.reactor.base"]
        self.assertFalse(e["placeholder"])
        self.assertIsNotNone(e["raw"])
        want = (p.handoff / "reactor_exterior.png").resolve()
        self.assertEqual((p.root / e["raw"]).resolve(), want)
        self.assertEqual(e["raw_sha256"], sha_file(want))

    def test_assets_raw_wins_over_handoff(self):
        p = self.sc.proj
        self.assertTrue((p.handoff / "habitat_interior.png").is_file())
        self.assertNotEqual(sha_file(p.handoff / "habitat_interior.png"), sha_file(p.raw / "habitat_interior.png"))
        e = self.sc.manifest["entries"]["building.habitat.interior"]
        self.assertEqual((p.root / e["raw"]).resolve(), (p.raw / "habitat_interior.png").resolve())
        self.assertEqual(e["raw_sha256"], sha_file(p.raw / "habitat_interior.png"))

    def test_ignored_raw_is_never_read(self):
        # garbage bytes named old_pixel_habitat_test.png sit in both raw dirs; reading would crash the build.
        for eid, e in self.sc.manifest["entries"].items():
            raw = e.get("raw") or ""
            self.assertNotIn("old_pixel_habitat_test", raw, "%s references the ignored raw" % eid)
        self.assertNotIn("old_pixel_habitat_test", self.sc.output.replace("raw_ignore", ""))

    def test_reference_lookup_matches_art_json(self):
        self.assertEqual(PIPE["raw_dirs"], ["assets/raw", "../station-zero-handoff/assets/raw"])
        self.assertEqual(PIPE["raw_ignore"], ["old_pixel_habitat_test.png"])


# =============================================================================================== P-1 manifest
class TestP1Manifest(PipelineCase):
    def test_header(self):
        m = self.manifest
        self.assertEqual(list(m.keys()), sorted(m.keys()), "manifest keys must be sorted")
        for k in ("schema", "pillow_version", "art_json_sha256", "entries"):
            self.assertIn(k, m)
        self.assertEqual(m["schema"], 1)
        self.assertEqual(ART.get("schema"), 1)
        self.assertEqual(m["pillow_version"], PIL.__version__)
        self.assertEqual(m["art_json_sha256"], sha_file(ROOT / "data" / "art.json"))

    def test_ids_sorted_keys_sorted_no_timestamps(self):
        ids = list(self.entries.keys())
        self.assertEqual(ids, sorted(ids), "entries must be sorted by id")
        for eid, e in self.entries.items():
            self.assertEqual(list(e.keys()), sorted(e.keys()), "%s: keys must be sorted" % eid)
            for key in e:
                self.assertFalse("time" in key.lower() or "date" in key.lower(), "%s has timestamp-like key %s" % (eid, key))
        for key in self.manifest:
            self.assertFalse("time" in key.lower() or "date" in key.lower())

    def test_entry_ids_are_exactly_the_expected_set(self):
        self.assertEqual(sorted(self.entries.keys()), expected_ids())

    def test_every_kind_has_exterior_and_interior(self):
        for k in KINDS:
            with self.subTest(kind=k):
                for part in ("base", "interior"):
                    e = self.entry("building.%s.%s" % (k, part))
                    self.assertIsNotNone(e["file"], "%s.%s has no file (kinds always get a placeholder file)" % (k, part))

    def test_files_exist_size_rgba_alpha_sha(self):
        for eid, e in self.entries.items():
            if e.get("file") is None:
                self.assertTrue(e["placeholder"], "%s: file null requires placeholder true" % eid)
                self.assertFalse(eid.startswith("building."), "%s: a kind entry must have a (placeholder) file" % eid)
                continue
            with self.subTest(entry=eid):
                path = self.processed / e["file"]
                self.assertTrue(path.is_file(), "missing file %s" % path)
                self.assertEqual(sha_file(path), e["sha256"], "sha256 mismatch for %s" % eid)
                im = Image.open(path)
                self.assertEqual(im.mode, "RGBA")
                self.assertEqual(im.size, (e["w"], e["h"]))
                lo, hi = alpha_extrema(im)
                kind_of_image = e.get("type")
                if kind_of_image in ("building_mask", "building_door", "interior_outline"):
                    # spec says "alpha contains both 0 and 255" for every entry, but its own rules give masks that
                    # cannot satisfy it (empty 'none' accent mask, ghost alpha <= 191, door leaves cropped to the
                    # rect).  Masks must still contain 0; non-empty ones are covered by P-7.
                    if kind_of_image != "building_door":
                        self.assertEqual(lo, 0, "%s: a mask must have transparent pixels" % eid)
                else:
                    self.assertEqual((lo, hi), (0, 255), "%s: alpha must contain both 0 and 255" % eid)

    def test_types_are_valid(self):
        want = {"base": "building_base", "door": "building_door", "interior": "interior",
                "interior_outline": "interior_outline"}
        for eid, e in self.entries.items():
            parts = eid.split(".")
            if parts[0] == "building":
                exp = "building_mask" if parts[2] == "mask" else want[parts[2]]
                self.assertEqual(e["type"], exp, eid)
                self.assertEqual(e["kind"], parts[1], eid)
                if parts[2] == "mask":
                    self.assertEqual(e["mask"], parts[3], eid)
            if eid in ("character.eva", "character.construction") or eid.startswith("character.jumpsuit."):
                self.assertEqual(e["type"], "atlas", eid)

    def test_raw_and_raw_sha256(self):
        """raw_sha256 equals the hash of the resolved raw, or null exactly when placeholder is true and no raw exists."""
        for eid, e in self.entries.items():
            with self.subTest(entry=eid):
                self.assertIn("raw", e)
                self.assertIn("raw_sha256", e)
                self.assertIn("placeholder", e)
                resolved = resolve_raw(ROOT, raw_name_for(eid))
                if resolved is None:
                    self.assertTrue(e["placeholder"], "%s: raw absent, entry must be a placeholder" % eid)
                    self.assertIsNone(e["raw"])
                    self.assertIsNone(e["raw_sha256"])
                else:
                    self.assertFalse(e["placeholder"], "%s: raw present (%s), entry must be real" % (eid, resolved))
                    self.assertIsNotNone(e["raw"])
                    self.assertEqual((ROOT / e["raw"]).resolve(), resolved.resolve())
                    self.assertEqual(e["raw_sha256"], sha_file(resolved))

    def test_texture_memory_budget(self):
        total = sum(e["w"] * e["h"] * 4 for e in self.entries.values()
                    if e.get("file") is not None and not e["placeholder"])
        mb = total * ART["perf"]["mipmap_overhead"] / MB
        print("\n[P-1] texture memory (real entries, mipmap x%.2f): %.1f MB of %d MB" %
              (ART["perf"]["mipmap_overhead"], mb, ART["perf"]["texture_memory_mb_max"]))
        self.assertLessEqual(mb, ART["perf"]["texture_memory_mb_max"])
        self.assertGreater(total, 0, "no real entries at all")

    def test_placeholder_count_is_printed(self):
        ph = sorted(i for i, e in self.entries.items() if e["placeholder"])
        print("\n[P-1] entries with placeholder: true = %d of %d" % (len(ph), len(self.entries)))
        print("[P-1] placeholder ids: " + ", ".join(ph))
        absent = [n for n in self.absent_raws()]
        print("[P-1] raws absent from raw_dirs: " + ", ".join(absent))
        self.assertEqual(len(ph) > 0, len(absent) > 0)

    def absent_raws(self):
        names = [ART["kinds"][k][t] for k in KINDS for t in ("raw_exterior", "raw_interior")]
        names += list(SHEET_RAW.values()) + [ART["optional"]["raw_decals"], ART["optional"]["raw_sleeping"]]
        return [n for n in names if resolve_raw(ROOT, n) is None]


# =============================================================================================== P-2 determinism
class TestP2Determinism(PipelineCase):
    def test_two_builds_give_identical_sha256_for_every_output(self):
        first = snapshot(PROCESSED)
        self.assertIn("manifest.json", first)
        second_run = run_build(ROOT)
        if not second_run.ok:
            self.fail("second build: " + second_run.message)
        second = snapshot(PROCESSED)
        self.assertEqual(sorted(first), sorted(second), "set of output files differs between builds")
        diff = [k for k in first if first[k] != second[k]]
        self.assertEqual(diff, [], "files differ between two builds (first 10): %s" % diff[:10])
        self.assertGreater(len(first), 10)
        # manifest hashes describe the files that exist
        m = load_manifest(PROCESSED)
        for eid, e in m["entries"].items():
            if e.get("file"):
                self.assertEqual(second[e["file"]], e["sha256"], eid)


# =============================================================================================== P-3 key
class TestP3Key(PipelineCase):
    KEYED_TYPES = ("building_base", "building_door", "interior", "atlas")

    def keyed_entries(self):
        for eid, e in self.entries.items():
            if e.get("file") is None:
                continue
            if e.get("type") in self.KEYED_TYPES or eid.startswith("character.sleeping.") or eid.startswith("terrain.decal."):
                yield eid, e

    def test_no_key_colour_pixel_in_border_connected_or_large_enclosed_regions(self):
        n = 0
        for eid, e in self.keyed_entries():
            with self.subTest(entry=eid):
                bad = key_survivor_components(open_rgba(self.processed / e["file"]))
                self.assertEqual(bad, [], "%s: threshold-colour survivors (x, y, size, border-connected): %s" % (eid, bad[:5]))
            n += 1
        self.assertGreater(n, 0)

    def test_no_near_pure_magenta_anywhere(self):
        n = 0
        for eid, e in self.keyed_entries():
            with self.subTest(entry=eid):
                self.assertEqual(count_pure_magenta(open_rgba(self.processed / e["file"])), 0, eid)
            n += 1
        self.assertGreater(n, 0)

    def test_corners_transparent(self):
        for k in KINDS:
            for part in ("base", "interior"):
                eid = "building.%s.%s" % (k, part)
                with self.subTest(entry=eid):
                    self.assertEqual(corners_transparent(self.image(eid)), [0, 0, 0, 0], eid)

    def test_no_pink_fringe_on_alpha_edge(self):
        limit = PIPE["key"]["defringe_edge_r_minus_g_max"]
        for k in KINDS:
            for part in ("base", "interior"):
                eid = "building.%s.%s" % (k, part)
                with self.subTest(entry=eid):
                    mean, n = edge_mean_r_minus_g(self.image(eid))
                    self.assertGreater(n, 0, "no alpha edge pixels")
                    self.assertLessEqual(mean, limit, "%s: mean R-G over %d edge pixels is %.1f" % (eid, n, mean))

    def test_workshop_neon_strip_survives(self):
        # enclosed threshold-colour regions are art (workshop pink neon): the pink accent mask must be non-empty,
        # for the real workshop art and, if the raw is absent, for the placeholder (accent_placeholder is pink too).
        im = self.image("building.workshop.mask.accent")
        self.assertGreater(sum(1 for p in im.getdata() if p[3] > 0), 0, "pink accent mask of the workshop is empty")


# =============================================================================================== P-4 sizes
class TestP4Sizes(PipelineCase):
    def test_exterior_images_of_a_kind_have_identical_size_and_width_384(self):
        for k in KINDS:
            with self.subTest(kind=k):
                sizes = {}
                for part in ["base"] + ["mask.%s" % m for m in MASKS]:
                    eid = "building.%s.%s" % (k, part)
                    e = self.entry(eid)
                    im = Image.open(self.processed / e["file"])
                    self.assertEqual(im.size, (e["w"], e["h"]), eid)
                    sizes[part] = im.size
                self.assertEqual(len(set(sizes.values())), 1, "sizes differ: %s" % sizes)
                self.assertEqual(sizes["base"][0], PIPE["building_width_px"])

    def test_base_height_follows_cropped_aspect(self):
        """height = round(384 x cropped aspect).  The test keys the raw independently (approximately: no erosion),
        so it allows 2 px.  Also: base is cropped tight (alpha bbox is the whole image)."""
        for k in KINDS:
            with self.subTest(kind=k):
                eid = "building.%s.base" % k
                e = self.entry(eid)
                im = self.image(eid)
                bb = im.getchannel("A").getbbox()
                self.assertEqual(bb, (0, 0, im.size[0], im.size[1]), "%s not cropped to alpha bbox" % eid)
                raw = resolve_raw(ROOT, ART["kinds"][k]["raw_exterior"])
                if raw is None:
                    hab = self.entry("building.habitat.base")
                    self.assertTrue(e["placeholder"])
                    self.assertEqual((e["w"], e["h"]), (hab["w"], hab["h"]), "placeholder %s must match the habitat size" % k)
                    continue
                x0, y0, x1, y1 = raw_keyed_bbox(raw)
                want = round(PIPE["building_width_px"] * (y1 - y0) / float(x1 - x0))
                self.assertLessEqual(abs(e["h"] - want), 2, "%s: height %d, expected about %d" % (eid, e["h"], want))

    def test_interior_width_512_and_outline_same_size(self):
        for k in KINDS:
            with self.subTest(kind=k):
                a = self.entry("building.%s.interior" % k)
                b = self.entry("building.%s.interior_outline" % k)
                self.assertEqual(a["w"], PIPE["interior_width_px"])
                self.assertEqual((a["w"], a["h"]), (b["w"], b["h"]))
                self.assertEqual(Image.open(self.processed / a["file"]).size, (a["w"], a["h"]))
                self.assertEqual(Image.open(self.processed / b["file"]).size, (b["w"], b["h"]))

    def test_real_interior_aspect_is_kept(self):
        for k in KINDS:
            raw = resolve_raw(ROOT, ART["kinds"][k]["raw_interior"])
            if raw is None:
                continue
            with self.subTest(kind=k):
                e = self.entry("building.%s.interior" % k)
                rw, rh = Image.open(raw).size
                # the cropped interior has a bbox inside the raw; its aspect cannot exceed the raw's by much
                self.assertLessEqual(e["h"], round(PIPE["interior_width_px"] * rh / rw) + 2)

    def test_atlases_512(self):
        cell, (gx, gy) = PIPE["character_cell_px"], PIPE["atlas_grid"]
        for eid in ["character.jumpsuit.%s" % r for r in ROLES] + ["character.eva", "character.construction"]:
            with self.subTest(entry=eid):
                self.assertEqual(Image.open(self.processed / self.entry(eid)["file"]).size, (cell * gx, cell * gy))
                self.assertEqual((cell * gx, cell * gy), (512, 512))

    def test_door_leaf_size_matches_door_rect(self):
        for k in KINDS:
            with self.subTest(kind=k):
                base = self.entry("building.%s.base" % k)
                door = self.entry("building.%s.door" % k)
                x0, y0, x1, y1 = base["door_rect"]
                self.assertLessEqual(abs(door["w"] - (x1 - x0) * base["w"]), 1)
                self.assertLessEqual(abs(door["h"] - (y1 - y0) * base["h"]), 1)

    def test_absent_optionals_and_real_optionals(self):
        ok_real = ok_abs = 0
        for d in DECALS:
            e = self.entry("terrain.decal.%s" % d)
            if e["placeholder"]:
                self.assertIsNone(e["file"]); ok_abs += 1
            else:
                self.assertEqual(e["w"], ART["optional"]["decals"]["width_px"]); ok_real += 1
        for r in ROLES:
            for n in SLEEP_N:
                e = self.entry("character.sleeping.%s.%d" % (r, n))
                if e["placeholder"]:
                    self.assertIsNone(e["file"]); ok_abs += 1
                else:
                    cp = ART["optional"]["sleeping"]["cell_px"]
                    self.assertEqual((e["w"], e["h"]), (cp, cp)); ok_real += 1
        self.assertEqual(ok_real + ok_abs, len(DECALS) + len(ROLES) * len(SLEEP_N))


# =============================================================================================== P-5 pivot
class TestP5Pivot(PipelineCase):
    def sheet_json(self, sheet):
        p = self.processed / "characters" / (sheet + ".json")
        self.assertTrue(p.is_file(), "missing %s" % p)
        return json.loads(p.read_text(encoding="utf-8"))

    def test_building_pivot_is_door_centre_and_bottom_edge(self):
        for k in KINDS:
            with self.subTest(kind=k):
                e = self.entry("building.%s.base" % k)
                x0, y0, x1, y1 = e["door_rect"]
                self.assertAlmostEqual(e["pivot"][1], 1.0, places=6)
                self.assertAlmostEqual(e["pivot"][0], (x0 + x1) / 2.0, delta=1e-3)

    def test_interior_pivot_is_door_x_bottom(self):
        for k in KINDS:
            with self.subTest(kind=k):
                spec = ART["interiors"].get(k, ART["interiors"]["default"])
                e = self.entry("building.%s.interior" % k)
                self.assertAlmostEqual(e["pivot"][1], 1.0, places=6)
                self.assertAlmostEqual(e["pivot"][0], spec["door"][0], delta=1e-3)

    def test_sheet_json_header_and_frame_table(self):
        names = frame_names_expected
        for sheet in SHEETS:
            with self.subTest(sheet=sheet):
                j = self.sheet_json(sheet)
                self.assertEqual(j["cell_px"], PIPE["character_cell_px"])
                self.assertEqual(list(j["pivot_px"]), PIPE["character_pivot_px"])
                self.assertGreater(j["scale"], 0)
                self.assertEqual(sorted(j["frames"]), sorted(names(sheet)))
                for name, (col, row) in zip(names(sheet), cells_expected()):
                    self.assertEqual((j["frames"][name]["col"], j["frames"][name]["row"]), (col, row), name)

    def test_all_16_cells_nonempty_same_size_content_inside_cell(self):
        cell = PIPE["character_cell_px"]
        for sheet in SHEETS:
            for atlas_name in SHEET_ATLAS[sheet]:
                eid = "character." + (atlas_name.replace("jumpsuit_", "jumpsuit.") if sheet == "jumpsuit" else atlas_name)
                im = self.image(eid)
                for r in range(4):
                    for c in range(4):
                        with self.subTest(atlas=eid, col=c, row=r):
                            bb = cell_bbox(im, c, r, cell)
                            self.assertIsNotNone(bb, "empty cell")
                            self.assertTrue(bb[0] > 0 and bb[1] > 0 and bb[2] < cell and bb[3] < cell,
                                            "content touches the cell edge (clipped?): %s" % (bb,))

    def test_feet_baseline_equal_across_walk_and_idle_frames(self):
        cell = PIPE["character_cell_px"]
        tol = PIPE["sheet"]["feet_baseline_tolerance_px"]
        for sheet in SHEETS:
            j = self.sheet_json(sheet)
            for atlas_name in SHEET_ATLAS[sheet]:
                eid = "character." + (atlas_name.replace("jumpsuit_", "jumpsuit.") if sheet == "jumpsuit" else atlas_name)
                im = self.image(eid)
                base = {}
                for name, f in j["frames"].items():
                    if name.startswith("walk_") or name.startswith("idle_"):
                        bb = cell_bbox(im, f["col"], f["row"], cell)
                        self.assertIsNotNone(bb, "%s %s empty" % (eid, name))
                        base[name] = bb[3] - 1
                with self.subTest(atlas=eid):
                    self.assertGreaterEqual(len(base), 12)
                    self.assertLessEqual(max(base.values()) - min(base.values()), tol, "feet rows differ: %s" % base)


def cells_expected():
    rows = ART["sheets"]["rows"]
    out = [(i, rows["walk_front"]) for i in range(4)] + [(i, rows["walk_back"]) for i in range(4)]
    out += [(i, rows["walk_side"]) for i in range(4)] + [(i, rows["extras"]) for i in range(4)]
    return out


def frame_names_expected(sheet):
    return (["walk_front_%d" % i for i in range(4)] + ["walk_back_%d" % i for i in range(4)] +
            ["walk_side_%d" % i for i in range(4)] + list(ART["sheets"][sheet]["extras"]))


# =============================================================================================== P-6 doors
class TestP6Doors(PipelineCase):
    def door_geometry(self, k):
        base_e = self.entry("building.%s.base" % k)
        base = self.image("building.%s.base" % k)
        W, H = base.size
        x0, y0, x1, y1 = base_e["door_rect"]
        return base_e, base, W, H, (int(round(x0 * W)), int(round(y0 * H)), int(round(x1 * W)), int(round(y1 * H)))

    def test_measured_rect_inside_opaque_area_and_centre_dark_after_fill(self):
        limit = PIPE["door"]["center_dark_luma_max"]
        for k in KINDS:
            with self.subTest(kind=k, placeholder=self.kind_is_placeholder(k)):
                e, base, W, H, (x0, y0, x1, y1) = self.door_geometry(k)
                self.assertTrue(0 <= x0 < x1 <= W and 0 <= y0 < y1 <= H)
                a = base.getchannel("A").crop((x0, y0, x1, y1))
                self.assertGreaterEqual(a.getextrema()[0], 250, "door rect not fully inside the opaque area")
                cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
                r, g, b, _ = base.getpixel((cx, cy))
                self.assertLessEqual(lum(r, g, b), limit, "door centre pixel in base is not dark after fill")

    def test_door_leaf_centre_is_not_dark(self):
        """Centre of the leaf image (rollup) or of each leaf (split: x at 25% and 75%, the seam is in the middle)."""
        # The cut leaves are the original art. The reactor leaves (dark steel, luma about 59 at the sample point) and the
        # workshop panel (luma about 62) are legitimately darker than center_dark_luma_max (90, which is the limit for the
        # dark FILL, not for art). What the check must catch is a leaf that is the dark fill gradient instead of the art,
        # so the limit is the brightest fill colour (fill_bottom_rgb) plus a margin.
        limit = lum(*PIPE["door"]["fill_bottom_rgb"]) + 5
        for k in KINDS:
            e = self.entry("building.%s.base" % k)
            mode = e["door_mode"]
            with self.subTest(kind=k, mode=mode):
                leaf = self.image("building.%s.door" % k)
                w, h = leaf.size
                xs = [w // 2] if mode == "rollup" else [w // 4, (3 * w) // 4]
                for x in xs:
                    r, g, b, a = leaf.getpixel((x, h // 2))
                    self.assertGreater(a, 0, "door leaf is transparent at its centre")
                    self.assertGreater(lum(r, g, b), limit, "door leaf centre pixel is dark")

    def test_habitat_and_reactor_rect_within_tolerance_of_art_json(self):
        tol = PIPE["door"]["rect_tolerance"]
        for k in ("habitat", "reactor"):
            with self.subTest(kind=k):
                self.assertFalse(ART["kinds"][k]["door_rect_provisional"])
                got = self.entry("building.%s.base" % k)["door_rect"]
                for g, w in zip(got, ART["kinds"][k]["door_rect"]):
                    self.assertLessEqual(abs(g - w), tol, "%s: %s vs art.json %s" % (k, got, ART["kinds"][k]["door_rect"]))

    def test_door_modes(self):
        for k in KINDS:
            with self.subTest(kind=k):
                e = self.entry("building.%s.base" % k)
                self.assertEqual(e["door_mode"], "rollup" if k == "workshop" else "split")
                self.assertEqual(e["door_mode"], ART["kinds"][k]["door_mode"])


class TestP6DoorMeasurementFailure(ScenarioCase):
    scenario_name, scenario_builder = "syn", staticmethod(build_syn)

    def test_forced_failure_uses_art_json_rect_and_warns(self):
        # archive_exterior.png in assets/raw is a flat building with no door, so measurement must fail.
        e = self.sc.manifest["entries"]["building.archive.base"]
        self.assertFalse(e["placeholder"], "fixture archive exterior was not used")
        for g, w in zip(e["door_rect"], ART["kinds"]["archive"]["door_rect"]):
            self.assertAlmostEqual(g, w, delta=1e-3, msg="fallback rect must be the art.json rect")
        out = self.sc.output.lower()
        self.assertIn("warn", out, "no warning printed when door measurement fails")
        self.assertIn("archive", out)

    def test_fallback_rect_is_still_dark_after_fill(self):
        p = self.sc.proj
        e = self.sc.manifest["entries"]["building.archive.base"]
        im = open_rgba(p.processed / e["file"])
        W, H = im.size
        x0, y0, x1, y1 = e["door_rect"]
        r, g, b, a = im.getpixel((int((x0 + x1) / 2 * W), int((y0 + y1) / 2 * H)))
        self.assertEqual(a, 255)
        self.assertLessEqual(lum(r, g, b), PIPE["door"]["center_dark_luma_max"])


# =============================================================================================== P-7 masks
class TestP7Masks(PipelineCase):
    def kind_set(self, k):
        """(accent class, is_placeholder) of the set the manifest uses for this kind."""
        ph = self.kind_is_placeholder(k)
        spec = ART["kinds"][k]
        return (spec["accent_placeholder"] if ph else spec["accent"]), ph

    def mask_img(self, k, m):
        return self.image("building.%s.mask.%s" % (k, m))

    def check_masks_for(self, base, masks, cls, door_px, label):
        W, H = base.size
        ba = list(base.getchannel("A").getdata())
        for name in ("accent", "windows", "shadow", "gray", "ghost"):
            ma = masks[name].getchannel("A")
            self.assertEqual(masks[name].size, base.size, "%s %s size" % (label, name))
            bad = sum(1 for a, b in zip(ma.getdata(), ba) if a > 0 and b == 0)
            self.assertEqual(bad, 0, "%s mask %s has %d pixels where base alpha is 0" % (label, name, bad))
        # accent non-empty unless 'none'; none gives an empty mask
        n_acc = sum(1 for p in masks["accent"].getdata() if p[3] > 0)
        if cls == "none":
            self.assertEqual(n_acc, 0, "%s: accent none must give an empty mask" % label)
        else:
            self.assertGreater(n_acc, 0, "%s: accent mask (%s) is empty" % (label, cls))
            self.check_mask_values(base, masks["accent"], accent_pred(cls), PIPE["masks"]["accent_" + cls]["color"],
                                   door_px, label + " accent")
        return n_acc

    def check_mask_values(self, base, mask, pred, color, door_px, label):
        W, H = base.size
        mp, bp = mask.load(), base.load()
        checked = 0
        pts = [(x, y) for y in range(H) for x in range(W) if mp[x, y][3] > 0]
        step = max(1, len(pts) // 300)
        dx0, dy0, dx1, dy1 = door_px
        for x, y in pts[::step]:
            if dx0 <= x < dx1 and dy0 <= y < dy1:
                continue
            r, g, b, a = mp[x, y]
            self.assertEqual(a, 255, "%s: mask alpha at %s" % (label, (x, y)))
            self.assertTrue(all(abs(c - t) <= 1 for c, t in zip((r, g, b), color)), "%s: colour %s at %s" % (label, (r, g, b), (x, y)))
            self.assertTrue(pred(*bp[x, y][:3]), "%s: base pixel %s at %s fails the colour test" % (label, bp[x, y][:3], (x, y)))
            checked += 1
        self.assertGreater(checked, 0, label)

    def door_px(self, k, W, H):
        x0, y0, x1, y1 = self.entry("building.%s.base" % k)["door_rect"]
        return (int(x0 * W), int(y0 * H), int(math.ceil(x1 * W)), int(math.ceil(y1 * H)))

    def test_masks_in_the_manifest_set_for_every_kind(self):
        for k in KINDS:
            cls, ph = self.kind_set(k)
            with self.subTest(kind=k, accent=cls, placeholder=ph):
                base = self.image("building.%s.base" % k)
                masks = {m: self.mask_img(k, m) for m in MASKS}
                self.check_masks_for(base, masks, cls, self.door_px(k, *base.size), k)

    def test_accent_mask_nonempty_for_every_real_art_kind_with_accent(self):
        seen = []
        for k in KINDS:
            spec = ART["kinds"][k]
            if resolve_raw(ROOT, spec["raw_exterior"]) is None:
                print("\n[P-7] note: real %s exterior raw absent, real-set accent check skipped (placeholder set is tested)" % k)
                self.assertTrue(self.kind_is_placeholder(k), k)
                continue
            with self.subTest(kind=k, accent=spec["accent"]):
                self.assertFalse(self.kind_is_placeholder(k))
                n = sum(1 for p in self.mask_img(k, "accent").getdata() if p[3] > 0)
                if spec["accent"] == "none":
                    self.assertEqual(n, 0)
                else:
                    self.assertGreater(n, 0)
                seen.append(k)
        self.assertGreater(len(seen), 0)

    def test_placeholder_set_accent_classes(self):
        """The placeholder set under assets/processed/placeholder/ for every kind: comms amber, archive cyan, others as real."""
        base_dir = self.processed / "placeholder"
        self.assertTrue(base_dir.is_dir(), "assets/processed/placeholder/ does not exist")
        for k in KINDS:
            with self.subTest(kind=k):
                cls = ART["kinds"][k]["accent_placeholder"]
                base = open_rgba(placeholder_file(base_dir, "%s_base.png" % k))
                masks = {m: open_rgba(placeholder_file(base_dir, "%s_mask_%s.png" % (k, m))) for m in MASKS}
                x0, y0, x1, y1 = ART["kinds"][k]["door_rect"]
                W, H = base.size
                door_px = (int(x0 * W) - 2, int(y0 * H) - 2, int(x1 * W) + 2, int(y1 * H) + 2)
                self.check_masks_for(base, masks, cls, door_px, "placeholder " + k)

    def test_windows_nonempty_for_habitat(self):
        n = sum(1 for p in self.mask_img("habitat", "windows").getdata() if p[3] > 0)
        self.assertGreater(n, 0)
        base = self.image("building.habitat.base")
        self.check_mask_values(base, self.mask_img("habitat", "windows"), windows_pred(),
                               PIPE["masks"]["windows"]["color"], self.door_px("habitat", *base.size), "habitat windows")

    def test_outline_exterior_and_interior(self):
        for k in KINDS:
            for what, base_id, out_id, step in (("exterior", "building.%s.base", "building.%s.mask.outline", 3),
                                                ("interior", "building.%s.interior", "building.%s.interior_outline", 5)):
                with self.subTest(kind=k, what=what):
                    base = self.image(base_id % k)
                    out = self.image(out_id % k)
                    self.assertEqual(out.size, base.size)
                    W, H = base.size
                    radius = int(round(PIPE["masks"]["outline"]["radius_px"] * W / PIPE["masks"]["outline"]["radius_ref_width_px"]))
                    self.assertEqual(radius, 5 if what == "exterior" else 7)
                    amin = PIPE["masks"]["outline"]["alpha_min"]
                    offs = disc_offsets(radius)
                    ba, oa = base.load(), out.load()
                    n = 0
                    for y in range(H):
                        for x in range(W):
                            r, g, b, a = oa[x, y]
                            if a > 0:
                                n += 1
                                self.assertEqual((r, g, b, a), tuple(PIPE["masks"]["outline"]["color"]) + (255,), (x, y))
                                self.assertLess(ba[x, y][3], amin, "outline pixel %s on the sprite" % ((x, y),))
                                near = any(0 <= x + dx < W and 0 <= y + dy < H and ba[x + dx, y + dy][3] >= amin for dx, dy in offs)
                                self.assertTrue(near, "outline pixel %s farther than %d px from the sprite" % ((x, y), radius))
                    self.assertGreater(n, 0, "outline is empty")
                    # completeness on a sparse grid: every alpha<100 pixel within the disc must be in the outline
                    for y in range(0, H, step):
                        for x in range(0, W, step):
                            if ba[x, y][3] >= amin:
                                continue
                            near = any(0 <= x + dx < W and 0 <= y + dy < H and ba[x + dx, y + dy][3] >= amin for dx, dy in offs)
                            self.assertEqual(oa[x, y][3] > 0, near, "outline completeness at %s" % ((x, y),))

    def test_shadow_equals_base_alpha(self):
        for k in KINDS:
            with self.subTest(kind=k):
                base = self.image("building.%s.base" % k)
                sh = self.image("building.%s.mask.shadow" % k)
                self.assertEqual(list(sh.getchannel("A").getdata()), list(base.getchannel("A").getdata()))
                col = tuple(PIPE["masks"]["shadow_rgb"])
                bad = [p for p in sh.getdata() if p[3] > 0 and p[:3] != col]
                self.assertEqual(bad[:3], [])

    def test_gray_and_ghost_match_formulas_on_100_samples(self):
        g = PIPE["masks"]["gray"]
        for k in KINDS:
            with self.subTest(kind=k):
                base = self.image("building.%s.base" % k)
                gray = self.image("building.%s.mask.gray" % k)
                ghost = self.image("building.%s.mask.ghost" % k)
                W, H = base.size
                dx0, dy0, dx1, dy1 = self.door_px(k, W, H)
                pts = [(x, y) for y in range(H) for x in range(W)
                       if base.getpixel((x, y))[3] == 255 and not (dx0 - 2 <= x < dx1 + 2 and dy0 - 2 <= y < dy1 + 2)]
                self.assertGreaterEqual(len(pts), 100)
                step = len(pts) // 100
                for x, y in pts[::step][:100]:
                    r, gg, b, a = base.getpixel((x, y))
                    l = lum(r, gg, b)
                    exp = (min(255, g["r_mul"] * l + g["r_add"]), min(255, g["g_mul"] * l + g["g_add"]),
                           min(255, g["b_mul"] * l + g["b_add"]))
                    got = gray.getpixel((x, y))
                    for c in range(3):
                        self.assertLessEqual(abs(got[c] - exp[c]), 2, "gray %s at %s: %s vs %s" % ("rgb"[c], (x, y), got, exp))
                    self.assertLessEqual(abs(got[3] - a), 1)
                    gh = ghost.getpixel((x, y))
                    ea = min(a, l * PIPE["masks"]["ghost"]["alpha_scale"])
                    self.assertLessEqual(abs(gh[3] - ea), 2, "ghost alpha at %s: %s vs %.1f" % ((x, y), gh[3], ea))
                    if gh[3] > 5:
                        for c in range(3):
                            self.assertLessEqual(abs(gh[c] - PIPE["masks"]["ghost"]["color"][c]), 1)


def placeholder_file(base_dir, name):
    hits = sorted(Path(base_dir).rglob(name))
    if not hits:
        raise AssertionError("placeholder file %s not found under %s" % (name, base_dir))
    return hits[0]


# =============================================================================================== P-8 recolor
class TestP8Recolor(PipelineCase):
    def atlases(self):
        return {r: self.image("character.jumpsuit.%s" % r) for r in ROLES}

    def test_recolor_rules_on_the_four_jumpsuit_atlases(self):
        imgs = self.atlases()
        st = recolor_stats(imgs)
        print("\n[P-8] suit pixels changed %d, still suit-gray %d, fraction %.3f" % (st["changed"], st["missed"], st["frac"]))
        self.assertTrue(st["alpha_equal"], "alpha must be kept: alpha differs between role atlases")
        self.assertGreater(st["changed"], 500, "almost nothing was recolored")
        self.assertGreaterEqual(st["frac"], PIPE["recolor"]["min_changed_fraction"])
        for r in ROLES:
            C = st["cols"][r]
            mean = st["means"][r]
            self.assertIsNotNone(mean)
            want = lum(*C)
            got = lum(*mean)
            self.assertLessEqual(abs(got - want) / want, 0.05, "%s: mean suit luma %.1f vs role colour luma %.1f" % (r, got, want))
            ok, total = st["ratio_ok"][r]
            self.assertGreater(total, 100)
            self.assertGreaterEqual(ok / float(total), 0.9, "%s: out/C is not a single scale factor on %d%% of pixels" % (r, 100 - 100 * ok // total))

    def test_idle_front_face_region_unchanged(self):
        cell = PIPE["character_cell_px"]
        j = json.loads((self.processed / "characters" / "jumpsuit.json").read_text(encoding="utf-8"))
        f = j["frames"]["idle_front"]
        d = face_region_changes(self.atlases(), cell, f["col"], f["row"])
        self.assertIsNotNone(d, "idle_front is empty")
        self.assertEqual(d, 0, "%d pixels changed in the face region (top 18%% of idle_front)" % d)

    def test_four_atlases_differ_pairwise(self):
        imgs = self.atlases()
        for i, a in enumerate(ROLES):
            for b in ROLES[i + 1:]:
                with self.subTest(pair=(a, b)):
                    self.assertNotEqual(list(imgs[a].getdata()), list(imgs[b].getdata()))

    def test_eva_and_construction_are_not_recolored_jumpsuits(self):
        # sanity: the recolor is only for the jumpsuit; the eva atlas is a different image
        self.assertNotEqual(list(self.image("character.eva").getdata()), list(self.atlases()["builder"].getdata()))


# =============================================================================================== P-9 slices
class TestP9Slices(PipelineCase):
    def test_16_cells_and_widest_frame_fits_in_cell(self):
        cell = PIPE["character_cell_px"]
        for sheet in SHEETS:
            j = json.loads((self.processed / "characters" / (sheet + ".json")).read_text(encoding="utf-8"))
            self.assertEqual(len(j["frames"]), 16, sheet)
            self.assertEqual(len({(f["col"], f["row"]) for f in j["frames"].values()}), 16, sheet)
            for atlas_name in SHEET_ATLAS[sheet]:
                eid = "character." + (atlas_name.replace("jumpsuit_", "jumpsuit.") if sheet == "jumpsuit" else atlas_name)
                im = self.image(eid)
                widest = 0
                for name, f in j["frames"].items():
                    bb = cell_bbox(im, f["col"], f["row"], cell)
                    with self.subTest(atlas=eid, frame=name):
                        self.assertIsNotNone(bb)
                        widest = max(widest, bb[2] - bb[0])
                        self.assertLess(bb[2] - bb[0], cell)
                print("\n[P-9] %s widest frame %d px of %d" % (eid, widest, cell))


class TestP9SliceGridDetection(ScenarioCase):
    scenario_name, scenario_builder = "syn", staticmethod(build_syn)

    def test_offgrid_separators_are_detected_and_cells_not_cut(self):
        """Fixture: construction sheet with separator lines at x=238/497/770, y=243/501/760 (not multiples of 256).
        Each cell's marker colour must appear in the same atlas cell, whole (equal pixel count in all 16 cells), and
        no other marker colour may leak into it."""
        p = self.sc.proj
        e = self.sc.manifest["entries"]["character.construction"]
        self.assertFalse(e["placeholder"])
        atlas = open_rgba(p.processed / e["file"])
        cell = PIPE["character_cell_px"]
        counts = {}
        for (c, r), col in self.sc.markers.items():
            crop = atlas.crop((c * cell, r * cell, (c + 1) * cell, (r + 1) * cell))
            data = list(crop.getdata())
            own = sum(1 for q in data if q[3] == 255 and all(abs(q[i] - col[i]) <= 16 for i in range(3)))
            counts[(c, r)] = own
            for (c2, r2), col2 in self.sc.markers.items():
                if (c2, r2) == (c, r):
                    continue
                leak = sum(1 for q in data if q[3] == 255 and all(abs(q[i] - col2[i]) <= 16 for i in range(3)))
                self.assertEqual(leak, 0, "cell %s contains the marker of cell %s" % ((c, r), (c2, r2)))
        self.assertTrue(all(v > 0 for v in counts.values()), "markers missing: %s" % counts)
        lo, hi = min(counts.values()), max(counts.values())
        self.assertLessEqual(hi - lo, 0.15 * hi, "marker pixel counts differ across cells (cut off?): %s" % counts)


# =============================================================================================== P-10 interiors
class TestP10Interiors(PipelineCase):
    def test_corners_transparent_and_wall_probes_opaque(self):
        n_probe = PIPE["key"]["wall_probe_points"]
        self.assertEqual(n_probe, 3)
        for k in KINDS:
            with self.subTest(kind=k, placeholder=self.kind_is_placeholder(k, "interior")):
                im = self.image("building.%s.interior" % k)
                W, H = im.size
                self.assertEqual(corners_transparent(im), [0, 0, 0, 0])
                if self.kind_is_placeholder(k, "interior"):
                    continue
                probes = [(W // 2, 3), (3, H // 2), (W - 4, H // 2)]    # top middle, left middle, right middle of the wall
                for x, y in probes:
                    self.assertEqual(im.getpixel((x, y))[3], 255, "wall probe %s not opaque" % ((x, y),))

    def test_interior_outline_nonempty(self):
        for k in KINDS:
            with self.subTest(kind=k):
                im = self.image("building.%s.interior_outline" % k)
                self.assertGreater(sum(1 for p in im.getdata() if p[3] > 0), 0)


class TestP10MagentaInteriorFixture(ScenarioCase):
    scenario_name, scenario_builder = "syn", staticmethod(build_syn)

    def test_magenta_background_takes_the_magenta_keying_path(self):
        p = self.sc.proj
        e = self.sc.manifest["entries"]["building.habitat.interior"]
        self.assertFalse(e["placeholder"])
        im = open_rgba(p.processed / e["file"])
        W, H = im.size
        self.assertEqual(W, PIPE["interior_width_px"])
        self.assertEqual(corners_transparent(im), [0, 0, 0, 0], "magenta corners must be keyed")
        for x, y in ((W // 2, 3), (3, H // 2), (W - 4, H // 2)):
            self.assertEqual(im.getpixel((x, y))[3], 255, "wall probe %s not opaque" % ((x, y),))
        # rule 1b path: the enclosed pure-magenta hole is removed (the gray flood fill would leave it)
        x0, y0, x1, y1 = INTERIOR_WALL
        s = W / float(x1 - x0)
        hx = int((INTERIOR_HOLE[0] - x0) * s)
        hy = int((INTERIOR_HOLE[1] - y0) * s)
        self.assertEqual(im.getpixel((hx, hy))[3], 0, "enclosed magenta hole at %s survived" % ((hx, hy),))
        self.assertEqual(count_pure_magenta(im), 0)


# =============================================================================================== P-11 placeholders
class TestP11Placeholders(PipelineCase):
    NEEDED = ["base", "door"] + ["mask_%s" % m for m in MASKS] + ["interior", "interior_outline"]

    def test_every_kind_has_a_placeholder_set_with_enough_colours(self):
        d = self.processed / "placeholder"
        self.assertTrue(d.is_dir(), "assets/processed/placeholder/ missing")
        need = PIPE["placeholder"]["min_unique_colors"]
        for k in KINDS:
            for part in self.NEEDED:
                with self.subTest(kind=k, part=part):
                    f = placeholder_file(d, "%s_%s.png" % (k, part))
                    self.assertEqual(Image.open(f).mode, "RGBA")
            for part in ("base", "interior"):
                with self.subTest(kind=k, part=part, check="unique colours"):
                    im = open_rgba(placeholder_file(d, "%s_%s.png" % (k, part)))
                    colours = {p[:3] for p in im.getdata() if p[3] > 0}
                    self.assertGreaterEqual(len(colours), need, "%s %s placeholder is nearly blank (%d colours)" % (k, part, len(colours)))

    def test_placeholder_rules_for_comms_and_archive(self):
        d = self.processed / "placeholder"
        hab = open_rgba(placeholder_file(d, "habitat_base.png"))
        for k, tint in (("comms", PIPE["placeholder"]["comms"]), ("archive", PIPE["placeholder"]["archive"])):
            with self.subTest(kind=k):
                im = open_rgba(placeholder_file(d, "%s_base.png" % k))
                self.assertEqual(im.size, hab.size, "%s placeholder must be the habitat size" % k)
                self.assertNotEqual(list(im.getdata()), list(hab.getdata()), "%s placeholder is not tinted" % k)
                x0, y0, x1, y1 = ART["kinds"][k]["door_rect"]
                real_hab_rect = ART["kinds"]["habitat"]["door_rect"]
                self.assertEqual([x0, y0, x1, y1], real_hab_rect, "art.json: %s keeps the habitat door rect" % k)

    def test_manifest_points_at_placeholder_only_when_raw_is_missing(self):
        n_ph = 0
        for k in KINDS:
            for part_set, raw_key in ((("base", "door") + tuple("mask.%s" % m for m in MASKS), "raw_exterior"),
                                      (("interior", "interior_outline"), "raw_interior")):
                absent = resolve_raw(ROOT, ART["kinds"][k][raw_key]) is None
                for part in part_set:
                    eid = "building.%s.%s" % (k, part)
                    with self.subTest(entry=eid, raw_absent=absent):
                        e = self.entry(eid)
                        self.assertEqual(e["placeholder"], absent)
                        if absent:
                            n_ph += 1
                            self.assertTrue(e["file"].startswith("placeholder/"), "%s file %s" % (eid, e["file"]))
                            self.assertTrue((self.processed / e["file"]).is_file())
                        else:
                            self.assertFalse(e["file"].startswith("placeholder/"))
        print("\n[P-11] building entries served by placeholder files: %d" % n_ph)


class TestP11SubstitutionFlag(ScenarioCase):
    """Temp copy without greenroom_exterior.png (baseline of P-15): the substitution must be flagged."""
    scenario_name, scenario_builder = "flip", staticmethod(build_flip)

    def test_removed_raw_is_flagged_and_served_from_placeholder(self):
        m = self.sc.m_base["entries"]
        for part in ("base", "door") + tuple("mask.%s" % x for x in MASKS):
            eid = "building.green_room.%s" % part
            with self.subTest(entry=eid):
                self.assertTrue(m[eid]["placeholder"])
                self.assertTrue(m[eid]["file"].startswith("placeholder/"))
                self.assertIsNone(m[eid]["raw"])
                self.assertIsNone(m[eid]["raw_sha256"])
                self.assertTrue((self.sc.proj.processed / m[eid]["file"]).is_file())
        for k in ("habitat", "reactor", "workshop"):
            self.assertFalse(m["building.%s.base" % k]["placeholder"], k)


# =============================================================================================== P-12 lamp anchors
class TestP12LampAnchors(PipelineCase):
    def test_eva_and_construction_anchors(self):
        cell = PIPE["character_cell_px"]
        head = PIPE["lamp"]["head_frac"]
        back_frac = ART["sheets"]["lamp_anchor_back_frac"]
        for sheet in ("eva", "construction"):
            j = json.loads((self.processed / "characters" / (sheet + ".json")).read_text(encoding="utf-8"))
            im = self.image("character." + sheet)
            for name, f in j["frames"].items():
                with self.subTest(sheet=sheet, frame=name):
                    a = f["lamp_anchor_px"]
                    self.assertIsNotNone(a, "anchor must not be null")
                    x0, y0, x1, y1 = cell_bbox(im, f["col"], f["row"], cell)
                    ax, ay = a
                    if name.startswith("walk_back"):
                        self.assertAlmostEqual(ax, x0 + back_frac[0] * (x1 - x0), delta=1.5)
                        self.assertAlmostEqual(ay, y0 + back_frac[1] * (y1 - y0), delta=1.5)
                    else:
                        self.assertTrue(x0 - 1 <= ax <= x1 + 1, "anchor x %s outside the opaque box %s" % (ax, (x0, x1)))
                        self.assertTrue(y0 - 1 <= ay <= y0 + head * (y1 - y0) + 1.5,
                                        "anchor y %s not in the upper %d%% of the box %s" % (ay, int(head * 100), (y0, y1)))

    def test_jumpsuit_anchors_are_null(self):
        j = json.loads((self.processed / "characters" / "jumpsuit.json").read_text(encoding="utf-8"))
        for name, f in j["frames"].items():
            self.assertIsNone(f["lamp_anchor_px"], name)


# =============================================================================================== P-13 decals
class TestP13Decals(PipelineCase):
    def test_decals_real_or_placeholder_path(self):
        raw = resolve_raw(ROOT, ART["optional"]["raw_decals"])
        for i, d in enumerate(DECALS):
            eid = "terrain.decal.%s" % d
            with self.subTest(entry=eid, raw_present=raw is not None):
                e = self.entry(eid)
                if raw is None:
                    self.assertTrue(e["placeholder"])
                    self.assertIsNone(e["file"])
                    self.assertIsNone(e["raw"])
                    self.assertIsNone(e["raw_sha256"])
                else:
                    self.assertFalse(e["placeholder"])
                    check_decal(self, self.processed, e, d)


def check_decal(tc, processed, e, name):
    path = Path(processed) / e["file"]
    tc.assertEqual(path.name, "decal_%s.png" % name)
    im = open_rgba(path)
    tc.assertEqual(im.size[0], ART["optional"]["decals"]["width_px"])
    tc.assertEqual(Image.open(path).mode, "RGBA")
    tc.assertEqual(corners_transparent(im), [0, 0, 0, 0])
    tc.assertEqual(count_pure_magenta(im), 0)
    tc.assertGreater(sum(1 for p in im.getdata() if p[3] > 0), 100, "decal is (nearly) empty")
    return im


class TestP13DecalsFixture(ScenarioCase):
    scenario_name, scenario_builder = "flip", staticmethod(build_flip)

    def test_absent_decals_are_placeholders_with_null_file(self):
        for d in DECALS:
            e = self.sc.m_base["entries"]["terrain.decal.%s" % d]
            with self.subTest(decal=d):
                self.assertTrue(e["placeholder"])
                self.assertIsNone(e["file"])

    def test_synthetic_2x2_quadrants_ice_pit_rocks_crater(self):
        _, cols = synth_decals()
        for d in DECALS:
            with self.subTest(decal=d):
                e = self.sc.m_drop["entries"]["terrain.decal.%s" % d]
                self.assertFalse(e["placeholder"])
                self.assertIsNotNone(e["raw_sha256"])
                im = check_decal(self, self.sc.snap_drop, e, d)
                W, H = im.size
                got = im.getpixel((W // 2, H // 2))
                self.assertTrue(all(abs(got[i] - cols[d][i]) <= 14 for i in range(3)),
                                "%s centre colour %s, expected the colour of its quadrant %s" % (d, got[:3], cols[d]))
                for other, oc in cols.items():
                    if other != d:
                        self.assertFalse(all(abs(got[i] - oc[i]) <= 14 for i in range(3)), "%s shows %s's colour" % (d, other))


# =============================================================================================== P-14 sleeping
class TestP14Sleeping(PipelineCase):
    def test_sleeping_real_or_placeholder_path(self):
        raw = resolve_raw(ROOT, ART["optional"]["raw_sleeping"])
        for r in ROLES:
            for n in SLEEP_N:
                eid = "character.sleeping.%s.%d" % (r, n)
                with self.subTest(entry=eid, raw_present=raw is not None):
                    e = self.entry(eid)
                    if raw is None:
                        self.assertTrue(e["placeholder"])
                        self.assertIsNone(e["file"])
                        self.assertIsNone(e["raw_sha256"])
                    else:
                        self.assertFalse(e["placeholder"])
                        cp = ART["optional"]["sleeping"]["cell_px"]
                        self.assertEqual((e["w"], e["h"]), (cp, cp))
                        self.assertEqual(list(e["pivot"]), ART["optional"]["sleeping"]["pivot_px"])


class TestP14SleepingFixture(ScenarioCase):
    scenario_name, scenario_builder = "flip", staticmethod(build_flip)

    def path(self, r, n):
        e = self.sc.m_drop["entries"]["character.sleeping.%s.%d" % (r, n)]
        return e, self.sc.snap_drop / e["file"]

    def test_absent_sleeping_poses_are_placeholders_with_null_file(self):
        for r in ROLES:
            for n in SLEEP_N:
                e = self.sc.m_base["entries"]["character.sleeping.%s.%d" % (r, n)]
                self.assertTrue(e["placeholder"], (r, n))
                self.assertIsNone(e["file"], (r, n))

    def test_sixteen_files_160px_pivot_and_content_inside_cell(self):
        cp = ART["optional"]["sleeping"]["cell_px"]
        count = 0
        for r in ROLES:
            for n in SLEEP_N:
                with self.subTest(role=r, n=n):
                    e, p = self.path(r, n)
                    self.assertEqual(p.name, "sleeping_%s_%d.png" % (r, n))
                    self.assertFalse(e["placeholder"])
                    im = open_rgba(p)
                    self.assertEqual(im.size, (cp, cp))
                    self.assertEqual(list(e["pivot"]), ART["optional"]["sleeping"]["pivot_px"])
                    bb = im.getchannel("A").getbbox()
                    self.assertIsNotNone(bb)
                    self.assertTrue(bb[0] > 0 and bb[1] > 0 and bb[2] < cp and bb[3] < cp, "content touches the cell edge %s" % (bb,))
                    cx, cy = (bb[0] + bb[2]) / 2.0, (bb[1] + bb[3]) / 2.0
                    self.assertLessEqual(abs(cx - 80), 8)
                    self.assertLessEqual(abs(cy - 80), 8)
                    count += 1
        self.assertEqual(count, 16)

    def test_drawn_at_the_jumpsuit_sheet_scale(self):
        pj = self.sc.snap_drop / "characters" / "jumpsuit.json"
        self.assertTrue(pj.is_file())
        js = json.loads(pj.read_text(encoding="utf-8"))["scale"]
        found = []
        sj = self.sc.snap_drop / "characters" / "sleeping.json"
        if sj.is_file():
            found.append(json.loads(sj.read_text(encoding="utf-8")).get("scale"))
        for r in ROLES:
            for n in SLEEP_N:
                s = self.sc.m_drop["entries"]["character.sleeping.%s.%d" % (r, n)].get("scale")
                if s is not None:
                    found.append(s)
        self.assertTrue(found, "sleeping scale is not recorded (manifest entry key 'scale' or characters/sleeping.json)")
        for s in found:
            self.assertAlmostEqual(s, js, places=6)
        # independent check from pixels: the 224 px wide fixture body is ~ 224 x scale x (1024/1024) px wide
        e, p = self.path("builder", 0)
        bb = open_rgba(p).getchannel("A").getbbox()
        self.assertAlmostEqual(bb[2] - bb[0], (224 + 50) * js, delta=max(6.0, 0.08 * (224 + 50) * js))

    def test_slice_order_n_is_tl_tr_bl_br(self):
        for r in ROLES:
            for n in SLEEP_N:
                with self.subTest(role=r, n=n):
                    e, p = self.path(r, n)
                    data = list(open_rgba(p).getdata())
                    for m, col in SLEEP_PATCH.items():
                        hit = sum(1 for q in data if q[3] == 255 and all(abs(q[i] - col[i]) <= 14 for i in range(3)))
                        if m == n:
                            self.assertGreater(hit, 20, "pose %d patch missing from sleeping_%s_%d" % (n, r, n))
                        else:
                            self.assertEqual(hit, 0, "pose %d patch found in sleeping_%s_%d" % (m, r, n))

    def test_recolor_obeys_p8_on_sleeping_poses(self):
        for n in SLEEP_N:
            with self.subTest(n=n):
                imgs = {r: open_rgba(self.path(r, n)[1]) for r in ROLES}
                st = recolor_stats(imgs)
                self.assertTrue(st["alpha_equal"])
                self.assertGreater(st["changed"], 200)
                self.assertGreaterEqual(st["frac"], PIPE["recolor"]["min_changed_fraction"],
                                        "changed %d, still suit-gray %d" % (st["changed"], st["missed"]))
                for r in ROLES:
                    want = lum(*st["cols"][r])
                    got = lum(*st["means"][r])
                    self.assertLessEqual(abs(got - want) / want, 0.05, r)
                # skin head and the pose patch keep their colours in all four roles
                patch = SLEEP_PATCH[n]
                for r in ROLES:
                    self.assertTrue(any(q[3] == 255 and all(abs(q[i] - patch[i]) <= 14 for i in range(3))
                                        for q in imgs[r].getdata()))


# =============================================================================================== P-15 presence flip
class TestP15PresenceFlip(ScenarioCase):
    scenario_name, scenario_builder = "flip", staticmethod(build_flip)

    def flipped_ids(self):
        ids = ["building.green_room.%s" % p for p in ("base", "door") + tuple("mask.%s" % m for m in MASKS)]
        ids += ["terrain.decal.%s" % d for d in DECALS]
        ids += ["character.sleeping.%s.%d" % (r, n) for r in ROLES for n in SLEEP_N]
        return sorted(ids)

    def test_baseline_entries_are_placeholders(self):
        m = self.sc.m_base["entries"]
        for eid in self.flipped_ids():
            with self.subTest(entry=eid):
                self.assertTrue(m[eid]["placeholder"])
                self.assertIsNone(m[eid]["raw_sha256"])
                if eid.startswith("building."):
                    self.assertTrue(m[eid]["file"].startswith("placeholder/"))
                else:
                    self.assertIsNone(m[eid]["file"])

    def test_dropping_the_raws_flips_exactly_those_entries_to_real(self):
        base, drop = self.sc.m_base["entries"], self.sc.m_drop["entries"]
        first_dir = (self.sc.proj.root / PIPE["raw_dirs"][0]).resolve()
        for eid in self.flipped_ids():
            with self.subTest(entry=eid):
                e = drop[eid]
                self.assertFalse(e["placeholder"])
                self.assertIsNotNone(e["file"])
                self.assertFalse(e["file"].startswith("placeholder/"))
                self.assertIsNotNone(e["raw"])
                self.assertIsNotNone(e["raw_sha256"])
                self.assertEqual((self.sc.proj.root / e["raw"]).resolve().parent, first_dir)
                self.assertEqual(e["raw_sha256"], self.sc.dropped_sha[Path(e["raw"]).name])
        flipped = sorted(i for i in drop if drop[i]["placeholder"] != base[i]["placeholder"])
        self.assertEqual(flipped, self.flipped_ids(), "exactly the dropped raws' entries must flip")
        self.assertEqual(drop["building.green_room.base"]["raw_sha256"], self.sc.dropped_green_sha)

    def test_all_other_entries_are_unchanged(self):
        base, drop = self.sc.m_base["entries"], self.sc.m_drop["entries"]
        self.assertEqual(sorted(base), sorted(drop))
        flipped = set(self.flipped_ids())
        n = 0
        for eid in base:
            if eid in flipped:
                continue
            with self.subTest(entry=eid):
                self.assertEqual(dict(base[eid]), dict(drop[eid]), "entry changed although its raw did not")
                n += 1
        self.assertGreater(n, 50)

    def test_removing_the_raws_flips_back_to_the_baseline_manifest(self):
        self.assertEqual(self.sc.text_back, self.sc.text_base, "manifest after removing the raws differs from the baseline")
        for eid in self.flipped_ids():
            self.assertTrue(self.sc.m_back["entries"][eid]["placeholder"], eid)


# =============================================================================================== absent raws, placeholder path
class TestAbsentRawsUsePlaceholderPath(PipelineCase):
    """Absent raws are never skipped silently: every absent raw named in art.json is listed, and its entries are
    checked on the placeholder path (kinds: placeholder file; optionals: file null)."""

    def test_each_absent_kind_raw_is_served_by_the_placeholder_set(self):
        absent = []
        for k in KINDS:
            for raw_key, parts in (("raw_exterior", ["base", "door"] + ["mask.%s" % m for m in MASKS]),
                                   ("raw_interior", ["interior", "interior_outline"])):
                name = ART["kinds"][k][raw_key]
                if resolve_raw(ROOT, name) is not None:
                    continue
                absent.append(name)
                for part in parts:
                    eid = "building.%s.%s" % (k, part)
                    with self.subTest(absent=name, entry=eid):
                        e = self.entry(eid)
                        self.assertTrue(e["placeholder"])
                        self.assertTrue(e["file"].startswith("placeholder/"))
                        self.assertTrue((self.processed / e["file"]).is_file())
                        self.assertIsNone(e["raw_sha256"])
                        if part in ("base", "interior"):
                            im = open_rgba(self.processed / e["file"])
                            self.assertGreaterEqual(len({p[:3] for p in im.getdata() if p[3] > 0}),
                                                    PIPE["placeholder"]["min_unique_colors"])
        print("\n[absent] kind raws served by placeholders: " + (", ".join(absent) or "none"))

    def test_absent_optionals_are_flagged_with_null_file(self):
        absent = []
        for name, ids in ((ART["optional"]["raw_decals"], ["terrain.decal.%s" % d for d in DECALS]),
                          (ART["optional"]["raw_sleeping"], ["character.sleeping.%s.%d" % (r, n) for r in ROLES for n in SLEEP_N])):
            if resolve_raw(ROOT, name) is not None:
                continue
            absent.append(name)
            for eid in ids:
                with self.subTest(absent=name, entry=eid):
                    e = self.entry(eid)
                    self.assertTrue(e["placeholder"])
                    self.assertIsNone(e["file"])
        print("\n[absent] optional raws absent: " + (", ".join(absent) or "none"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
