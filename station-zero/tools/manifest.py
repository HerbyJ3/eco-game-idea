"""Manifest assembly (spec 3.9): entries sorted by id, keys sorted, no timestamps."""
import PIL

import common


class Manifest:
    def __init__(self, art_path):
        self.entries = {}
        self.art_sha = common.sha256_file(art_path)

    def add(self, eid, rel, im, sha, etype, placeholder, raw, raw_sha, **extra):
        e = {"file": rel, "w": im.size[0] if im is not None else 0, "h": im.size[1] if im is not None else 0,
             "type": etype, "placeholder": bool(placeholder), "raw": raw, "raw_sha256": raw_sha, "sha256": sha}
        e.update({k: v for k, v in extra.items() if v is not None})
        self.entries[eid] = e

    def to_dict(self):
        return {"schema": 1, "pillow_version": PIL.__version__, "art_json_sha256": self.art_sha,
                "entries": {k: self.entries[k] for k in sorted(self.entries)}}

    def texture_mb(self, art):
        """Decimal MB of the real (non-placeholder) PNG entries x mipmap overhead (the P-1 formula)."""
        total = sum(e["w"] * e["h"] * 4 for e in self.entries.values() if e["file"] is not None and not e["placeholder"])
        return total * art["perf"]["mipmap_overhead"] / 1_000_000, total
