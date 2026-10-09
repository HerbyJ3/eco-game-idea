#!/usr/bin/env python3
"""Station Zero asset pipeline: raw PNGs (assets/raw, ../station-zero-handoff/assets/raw) to assets/processed/ plus manifest.json.

One command, rerunnable, byte-identical on a second run (no randomness, no timestamps).
Spec: docs/specs/sprite-view.md section 3. Run from anywhere:  python3 tools/build_all.py
"""
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from PIL import Image  # noqa: E402

import buildings  # noqa: E402
import common  # noqa: E402
import decals  # noqa: E402
import doors  # noqa: E402
import interiors  # noqa: E402
import masks as masks_mod  # noqa: E402
import placeholders  # noqa: E402
import recolor  # noqa: E402
import review  # noqa: E402
import sheets  # noqa: E402
from manifest import Manifest  # noqa: E402

ROOT = HERE.parent
SHEET_RAW = {"jumpsuit": "sheet_colonist_jumpsuit.png", "eva": "sheet_eva_suit.png",
             "construction": "sheet_construction_suit.png"}


def log(msg):
    print(msg, flush=True)


class Build:
    def __init__(self, root):
        self.root = Path(root)
        self.art = common.load_art(self.root)
        self.finder = common.RawFinder(self.root, self.art)
        self.out = common.OutputSet(self.root / "assets" / "processed")
        self.man = Manifest(self.root / "data" / "art.json")
        self.kinds = list(self.art["kinds"])
        self.raw_info = {}                 # name -> (rel path, sha) or None

    # ------------------------------------------------------------------ raw presence rule (3.10)
    def raw(self, name):
        if name not in self.raw_info:
            p = self.finder.find(name)
            self.raw_info[name] = None if p is None else (p, self.finder.rel(p), common.sha256_file(p))
        return self.raw_info[name]

    def raw_fields(self, name):
        r = self.raw(name)
        return (None, None) if r is None else (r[1], r[2])

    # ------------------------------------------------------------------ buildings
    def build_buildings(self):
        art = self.art
        hab_raw = self.raw(art["kinds"]["habitat"]["raw_exterior"])
        if hab_raw is None:
            raise SystemExit("error: habitat_exterior.png is missing; every placeholder is derived from it")
        real = {}
        for kind in self.kinds:
            r = self.raw(art["kinds"][kind]["raw_exterior"])
            if r is None:
                continue
            pre = buildings.key_exterior(common.load_rgb(r[0]), art)
            real[kind] = pre
        # the habitat set defines the placeholder base and door rect
        hab = buildings.assemble(real["habitat"], "habitat", art, art["kinds"]["habitat"]["accent"], log=log)
        ext = {}
        for kind in self.kinds:
            spec = art["kinds"][kind]
            ph_pre = placeholders.placeholder_prefill(kind, hab.prefill, hab.base, art)
            ph = buildings.assemble(ph_pre, kind, art, spec["accent_placeholder"], rect_px=hab.rect_px, log=log)
            self.emit_exterior(kind, ph, "placeholder", True)
            if kind in real:
                if kind == "habitat":
                    rs = hab
                else:
                    rs = buildings.assemble(real[kind], kind, art, spec["accent"], log=log)
                self.emit_exterior(kind, rs, "buildings", False)
                ext[kind] = rs
            else:
                ext[kind] = ph
        return ext

    def emit_exterior(self, kind, es, folder, is_placeholder):
        """Write the files of one exterior set under `folder`; the manifest points at the real set, or at the
        placeholder set (placeholder true) when the raw is missing. Placeholder files are always written."""
        art = self.art
        files = {}
        files["base"] = ("%s/%s_base.png" % (folder, kind), es.base, "building_base")
        files["door"] = ("%s/%s_door.png" % (folder, kind), es.door, "building_door")
        for m in masks_mod.MASK_NAMES:
            files["mask.%s" % m] = ("%s/%s_mask_%s.png" % (folder, kind, m), es.masks[m], "building_mask")
        shas = {}
        for part, (rel, im, _t) in files.items():
            shas[part] = self.out.add_png(rel, im)
        if is_placeholder and self.raw(art["kinds"][kind]["raw_exterior"]) is not None:
            return                          # real raw exists: the placeholder file is written but not referenced
        raw, raw_sha = self.raw_fields(art["kinds"][kind]["raw_exterior"])
        cx = round((es.rect_norm[0] + es.rect_norm[2]) / 2.0, 6)
        for part, (rel, im, etype) in files.items():
            extra = {"kind": kind}
            if part.startswith("mask."):
                extra["mask"] = part.split(".")[1]
            if part in ("base", "door"):
                extra["door_rect"] = es.rect_norm
                extra["door_mode"] = es.door_mode
            if part == "base":
                extra["pivot"] = [cx, 1.0]
            self.man.add("building.%s.%s" % (kind, part), rel, im, shas[part], etype, is_placeholder, raw, raw_sha, **extra)

    # ------------------------------------------------------------------ interiors
    def build_interiors(self):
        art = self.art
        w = art["pipeline"]["interior_width_px"]
        for kind in self.kinds:
            spec = art["kinds"][kind]
            # placeholder interior always written
            ph = interiors.placeholder_interior(kind, art, (w, int(round(w * 848 / 1264.0))))
            ph_out = masks_mod.outline_mask(ph, art)
            self.out.add_png("placeholder/%s_interior.png" % kind, ph)
            self.out.add_png("placeholder/%s_interior_outline.png" % kind, ph_out)
            r = self.raw(spec["raw_interior"])
            if r is None:
                im, om, folder, is_ph = ph, ph_out, "placeholder", True
            else:
                im = interiors.key_interior(common.load_rgb(r[0]), art)
                om = masks_mod.outline_mask(im, art)
                folder, is_ph = "buildings", False
                self.out.add_png("buildings/%s_interior.png" % kind, im)
                self.out.add_png("buildings/%s_interior_outline.png" % kind, om)
            raw, raw_sha = self.raw_fields(spec["raw_interior"])
            piv = interiors.interior_pivot(kind, art)
            for part, img, etype in (("interior", im, "interior"), ("interior_outline", om, "interior_outline")):
                rel = "%s/%s_%s.png" % (folder, kind, part)
                sha = common.sha256_bytes(self.out.files[rel])
                self.man.add("building.%s.%s" % (kind, part), rel, img, sha, etype, is_ph, raw, raw_sha,
                             kind=kind, pivot=piv if part == "interior" else None)

    # ------------------------------------------------------------------ characters
    def build_characters(self):
        art = self.art
        scales = {}
        gray = None
        for sheet, name in SHEET_RAW.items():
            r = self.raw(name)
            if r is None:
                raise SystemExit("error: required sheet %s is missing (no placeholder exists for sheets)" % name)
            atlas, js, scale = sheets.build_sheet(common.load_rgb(r[0]), sheet, art, log=log)
            scales[sheet] = scale
            self.out.add_json("characters/%s.json" % sheet, js)
            raw, raw_sha = self.raw_fields(name)
            if sheet == "jumpsuit":
                gray = atlas
                self.build_jumpsuit_roles(atlas, raw, raw_sha)
            else:
                sha = self.out.add_png("characters/%s.png" % sheet, atlas)
                self.man.add("character.%s" % sheet, "characters/%s.png" % sheet, atlas, sha, "atlas", False, raw, raw_sha)
        self.build_sleeping(scales["jumpsuit"])
        self.build_decals()

    def build_jumpsuit_roles(self, atlas, raw, raw_sha):
        art = self.art
        flags = recolor.suit_gray_flags(atlas, art)
        mean = recolor.mean_suit_luma([(atlas, flags)], art)
        for role, color in recolor.role_colors(art).items():
            im = recolor.recolor(atlas, flags, mean, color, art)
            rel = "characters/jumpsuit_%s.png" % role
            sha = self.out.add_png(rel, im)
            self.man.add("character.jumpsuit.%s" % role, rel, im, sha, "atlas", False, raw, raw_sha)

    def build_sleeping(self, js_scale):
        art = self.art
        s = art["optional"]["sleeping"]
        name = art["optional"]["raw_sleeping"]
        r = self.raw(name)
        roles = recolor.role_colors(art)
        poses = used = None
        if r is not None:
            poses, used = decals.build_sleeping(common.load_rgb(r[0]), art, js_scale)
            if any(abs(u - js_scale) > 1e-9 for u in used):
                log("warn: sleeping poses are wider than the %d px cell at the jumpsuit scale; shrunk (scales %s)" % (s["cell_px"], used))
            flags = [recolor.suit_gray_flags(p, art) for p in poses]
            mean = recolor.mean_suit_luma(list(zip(poses, flags)), art)
        raw, raw_sha = self.raw_fields(name)
        for role in roles:
            for n in range(s["poses"]):
                eid = "character.sleeping.%s.%d" % (role, n)
                if poses is None:
                    self.man.add(eid, None, None, None, "sleeping_pose", True, None, None)
                    continue
                im = recolor.recolor(poses[n], flags[n], mean, roles[role], art)
                rel = "characters/sleeping_%s_%d.png" % (role, n)
                sha = self.out.add_png(rel, im)
                self.man.add(eid, rel, im, sha, "sleeping_pose", False, raw, raw_sha, pivot=list(s["pivot_px"]), scale=used[n])

    def build_decals(self):
        art = self.art
        name = art["optional"]["raw_decals"]
        r = self.raw(name)
        names = art["optional"]["decals"]["order"]
        got = decals.build_decals(common.load_rgb(r[0]), art) if r is not None else None
        raw, raw_sha = self.raw_fields(name)
        for d in names:
            eid = "terrain.decal.%s" % d
            if got is None:
                self.man.add(eid, None, None, None, "decal", True, None, None)
                continue
            rel = "terrain/decal_%s.png" % d
            sha = self.out.add_png(rel, got[d])
            self.man.add(eid, rel, got[d], sha, "decal", False, raw, raw_sha)

    # ------------------------------------------------------------------ run
    def run(self):
        t0 = time.time()
        ext = self.build_buildings()
        self.build_interiors()
        self.build_characters()
        review.write_reviews(self, ext)
        self.out.add_json("manifest.json", self.man.to_dict())
        self.out.files["_review/.gdignore"] = b""      # Godot must not import the human review sheets
        self.out.write()
        mb, total = self.man.texture_mb(self.art)
        n_ph = sum(1 for e in self.man.entries.values() if e["placeholder"])
        log("build ok: %d manifest entries, %d placeholder, %d files, texture memory (real, mipmap x%.2f) %.1f MB of %d MB, %.1f s"
            % (len(self.man.entries), n_ph, len(self.out.files), self.art["perf"]["mipmap_overhead"], mb,
               self.art["perf"]["texture_memory_mb_max"], time.time() - t0))
        for kind in self.kinds:
            e = self.man.entries["building.%s.base" % kind]
            log("door %s: %s%s" % (kind, e["door_rect"], " (placeholder)" if e["placeholder"] else ""))


def main():
    Build(ROOT).run()


if __name__ == "__main__":
    main()
