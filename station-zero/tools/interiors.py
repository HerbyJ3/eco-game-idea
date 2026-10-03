"""Interior keying/crop/scale and the placeholder interior (spec 3.4 rule 3, 3.8)."""
from PIL import Image, ImageChops, ImageDraw, ImageFont

import common
import masks as masks_mod


def key_interior(rgb, art):
    """Gray (any flat) background: flood fill from the corners. A magenta corner switches to the magenta keying path
    (rules 1, 1b). Then 1 px alpha erosion, crop, Lanczos to interior_width_px."""
    width = art["pipeline"]["interior_width_px"]
    if common.is_magenta_corner(rgb, art):
        rgba = common.key_magenta(rgb, art)
    else:
        alpha = common.flood_background(rgb, art)
        rgba = common.finish_alpha(rgb, alpha, art["pipeline"]["key"])
    rgba = common.crop_to_alpha(rgba)
    return round_corners(common.recrop(common.scale_to_width(rgba, width)), art["pipeline"]["key"]["interior_corner_radius_px"])


def round_corners(im, radius):
    """Rounded silhouette (the interior is shown inside a rounded frame, and the selection outline hugs it): the four image
    corners become transparent even for full-bleed art such as the comms interior."""
    w, h = im.size
    mask = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=radius * 4, fill=255)
    mask = mask.resize((w, h), Image.BOX)
    out = im.copy()
    out.putalpha(ImageChops.multiply(im.getchannel("A"), mask))
    return out


def interior_pivot(kind, art):
    spec = art["interiors"].get(kind, art["interiors"]["default"])
    return [spec["door"][0], 1.0]


def placeholder_interior(kind, art, size):
    """Dark floor, 48 px tile pattern at alpha 0.03, a top bar of the kind colour, the kind label, rounded silhouette."""
    ph = art["pipeline"]["placeholder"]["interior"]
    w, h = size
    floor = common.hex_rgb(ph["floor_color"])
    im = Image.new("RGBA", (w, h), floor + (255,))
    d = ImageDraw.Draw(im)
    t = ph["tile_px"]
    line = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(line)
    a = int(round(255 * ph["tile_alpha"]))
    for x in range(0, w, t):
        ld.line([(x, 0), (x, h - 1)], fill=(255, 255, 255, a))
    for y in range(0, h, t):
        ld.line([(0, y), (w - 1, y)], fill=(255, 255, 255, a))
    im.alpha_composite(line)
    rim = 8
    bar = common.hex_rgb(art["kinds"][kind]["color"])
    d = ImageDraw.Draw(im)
    d.rectangle([rim + 4, rim, w - rim - 5, rim + ph["bar_h_px"] - 1], fill=bar + (255,))
    label = kind.replace("_", " ").upper()
    font = ImageFont.load_default(size=ph["label_font_px"])
    box = d.textbbox((0, 0), label, font=font)
    tx = (w - (box[2] - box[0])) // 2 - box[0]
    ty = (h - (box[3] - box[1])) // 2 - box[1]
    d.text((tx, ty), label, font=font, fill=(200, 196, 190, 255))
    mask = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=24 * 4, fill=255)
    mask = mask.resize((w, h), Image.BOX)
    alpha = ImageChops.multiply(im.getchannel("A"), mask)
    # keep the silhouette hard enough that alpha has a true 0 and 255 and soft edge pixels only on the rim
    im.putalpha(alpha)
    return im
