#!/usr/bin/env python3
"""Contact sheet of every pipeline output over a checkerboard, for eyes (docs/shots/task-2/pipeline_contact.png).

Reads assets/processed/manifest.json. Shows, per kind, the base, the six masks and the door leaves (real or placeholder, as the
manifest points), the interiors with their outlines, every character atlas with the feet pivot (green) and helmet lamp anchors
(red), the placeholder set, the optional decals and sleeping poses when present.
Usage: python3 tools/contact_sheet.py [out.png]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
PROC = ROOT / "assets" / "processed"
MASKS = ["accent", "windows", "outline", "shadow", "gray", "ghost"]
BG = (24, 24, 28, 255)


def checker(size, cell=8):
    im = Image.new("RGBA", size, (72, 72, 76, 255))
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(104, 104, 108, 255))
    return im


def over(im, width=None):
    im = im.convert("RGBA")
    if width and im.size[0] != width:
        im = im.resize((width, max(1, round(im.size[1] * width / im.size[0]))), Image.LANCZOS)
    bg = checker(im.size)
    bg.alpha_composite(im)
    return bg


def load(m, eid):
    e = m["entries"][eid]
    if e["file"] is None:
        return None, e
    return Image.open(PROC / e["file"]).convert("RGBA"), e


def main():
    out_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs" / "shots" / "task-2" / "pipeline_contact.png"
    m = json.loads((PROC / "manifest.json").read_text(encoding="utf-8"))
    art = json.loads((ROOT / "data" / "art.json").read_text(encoding="utf-8"))
    kinds = list(art["kinds"])
    font = ImageFont.load_default(size=13)
    W = 1600
    canvas = Image.new("RGBA", (W, 5200), BG)
    d = ImageDraw.Draw(canvas)
    y = 6

    def label(x, yy, text):
        d.text((x, yy), text, font=font, fill=(235, 235, 235, 255))

    # ---- exteriors: base | accent | windows | outline | shadow | gray | ghost | door leaf
    cw = 190
    label(6, y, "EXTERIORS: base (red = door rect) | accent | windows | outline | shadow | gray | ghost | door leaf     [P] = placeholder file")
    y += 18
    for k in kinds:
        base, e = load(m, "building.%s.base" % k)
        x = 4
        rowh = 0
        parts = [("base", base)] + [(n, load(m, "building.%s.mask.%s" % (k, n))[0]) for n in MASKS] + \
                [("door", load(m, "building.%s.door" % k)[0])]
        for name, im in parts:
            if name == "door":
                sc = 2
                tile = over(im.resize((im.size[0] * sc, im.size[1] * sc), Image.LANCZOS))
            else:
                tile = over(im, cw)
                if name == "base":
                    r = e["door_rect"]
                    dd = ImageDraw.Draw(tile)
                    dd.rectangle([r[0] * tile.size[0], r[1] * tile.size[1], r[2] * tile.size[0], r[3] * tile.size[1]],
                                 outline=(255, 40, 40, 255))
            canvas.paste(tile, (x, y + 14))
            x += tile.size[0] + 4
            rowh = max(rowh, tile.size[1])
        label(4, y, "%s%s  door %s mode %s" % (k, " [P]" if e["placeholder"] else "", e["door_rect"], e["door_mode"]))
        y += rowh + 20
    # ---- interiors
    y += 6
    label(6, y, "INTERIORS (top) and their outlines (bottom); pivot = door gap (green)")
    y += 18
    iw = 256
    x = 4
    rowh = 0
    for k in kinds:
        im, e = load(m, "building.%s.interior" % k)
        tile = over(im, iw)
        dd = ImageDraw.Draw(tile)
        px = e["pivot"][0] * tile.size[0]
        dd.line([px - 6, tile.size[1] - 1, px + 6, tile.size[1] - 1], fill=(40, 255, 40, 255), width=2)
        canvas.paste(tile, (x, y + 14))
        label(x, y, "%s%s" % (k, " [P]" if e["placeholder"] else ""))
        om, _ = load(m, "building.%s.interior_outline" % k)
        ot = over(om, iw)
        canvas.paste(ot, (x, y + 14 + tile.size[1] + 4))
        rowh = max(rowh, tile.size[1] * 2 + 4)
        x += iw + 4
        if x + iw > W:
            x = 4
            y += rowh + 20
            rowh = 0
    y += rowh + 24
    # ---- atlases
    label(6, y, "ATLASES (cell 128; green cross = feet pivot (64,120); red dot = helmet lamp anchor; gray lines = cell grid)")
    y += 18
    ids = ["character.jumpsuit.builder", "character.jumpsuit.curious", "character.jumpsuit.social",
           "character.jumpsuit.tender", "character.eva", "character.construction"]
    x = 4
    for i, eid in enumerate(ids):
        im, e = load(m, eid)
        tile = over(im)
        dd = ImageDraw.Draw(tile)
        cell = 128
        for g in range(1, 4):
            dd.line([g * cell, 0, g * cell, 511], fill=(160, 160, 255, 90))
            dd.line([0, g * cell, 511, g * cell], fill=(160, 160, 255, 90))
        sheet = "jumpsuit" if "jumpsuit" in eid else eid.split(".")[1]
        j = json.loads((PROC / "characters" / (sheet + ".json")).read_text(encoding="utf-8"))
        for name, f in j["frames"].items():
            cx, cy = f["col"] * cell, f["row"] * cell
            dd.line([cx + 60, cy + 120, cx + 68, cy + 120], fill=(40, 255, 40, 255))
            dd.line([cx + 64, cy + 116, cx + 64, cy + 124], fill=(40, 255, 40, 255))
            if f["lamp_anchor_px"]:
                ax, ay = f["lamp_anchor_px"]
                dd.ellipse([cx + ax - 2, cy + ay - 2, cx + ax + 2, cy + ay + 2], outline=(255, 40, 40, 255))
        canvas.paste(tile, (x, y + 14))
        label(x, y, eid)
        x += 516
        if (i + 1) % 3 == 0:
            x = 4
            y += 530
    # ---- optional
    label(6, y, "OPTIONAL: terrain decals and sleeping poses (blank = raw absent, placeholder: file null)")
    y += 18
    x = 4
    for eid in sorted(i for i in m["entries"] if i.startswith("terrain.decal.")):
        im, e = load(m, eid)
        if im is None:
            d.rectangle([x, y, x + 100, y + 60], outline=(200, 80, 80, 255))
            label(x + 4, y + 20, eid.split(".")[-1] + " (absent)")
            x += 108
        else:
            t = over(im, 160)
            canvas.paste(t, (x, y))
            x += 164
    y += 70
    x = 4
    for eid in sorted(i for i in m["entries"] if i.startswith("character.sleeping.")):
        im, e = load(m, eid)
        if im is None:
            continue
        canvas.paste(over(im), (x, y))
        x += 164
        if x + 160 > W:
            x = 4
            y += 164
    canvas = canvas.crop((0, 0, W, y + 180))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out_path)
    print("wrote %s (%dx%d)" % (out_path, canvas.size[0], canvas.size[1]))


if __name__ == "__main__":
    main()
