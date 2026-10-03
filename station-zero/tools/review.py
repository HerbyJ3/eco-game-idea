"""Review contact sheets for humans (assets/processed/_review/*.png, not in the manifest)."""
from PIL import Image, ImageDraw

import common


def _checker(size, cell=8):
    im = Image.new("RGBA", size, (70, 70, 74, 255))
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(96, 96, 100, 255))
    return im


def _over(im, size=None):
    bg = _checker(im.size)
    bg.alpha_composite(im)
    return bg


def write_reviews(build, ext):
    art = build.art
    # buildings: base with the door rect, accent + windows overlay, outline
    cols = 3
    tw = 384
    th = max(e.base.size[1] for e in ext.values())
    kinds = build.kinds
    sheet = Image.new("RGBA", (cols * tw, len(kinds) * th), (30, 30, 34, 255))
    for row, kind in enumerate(kinds):
        es = ext[kind]
        base = _over(es.base)
        d = ImageDraw.Draw(base)
        d.rectangle([es.rect_px[0], es.rect_px[1], es.rect_px[2] - 1, es.rect_px[3] - 1], outline=(255, 0, 0, 255))
        sheet.paste(base, (0, row * th))
        lit = _over(es.base)
        lit.alpha_composite(es.masks["accent"])
        lit.alpha_composite(es.masks["windows"])
        sheet.paste(lit, (tw, row * th))
        ol = _over(es.base)
        ol.alpha_composite(es.masks["outline"])
        sheet.paste(ol, (2 * tw, row * th))
    build.out.add_png("_review/buildings.png", sheet.convert("RGB").convert("RGBA"))
    # sheets: every atlas as stored
    names = ["characters/jumpsuit_builder.png", "characters/eva.png", "characters/construction.png"]
    s2 = Image.new("RGBA", (512 * 3, 512), (30, 30, 34, 255))
    for i, rel in enumerate(names):
        if rel in build.out.files:
            s2.paste(_over(build.out.get_png(rel)), (i * 512, 0))
    build.out.add_png("_review/sheets.png", s2)
