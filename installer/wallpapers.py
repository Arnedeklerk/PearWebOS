"""Background photos for the Pear Home.

Every image in photos/ (jpg, png, webp) becomes wallpapers/<n>.jpg: cropped
to 16:9 and saved at 1600x900, which is small on the TV and plenty for a
backdrop under a shade. 0.jpg is always the rendered dusk landscape.

Each photo also gets a date colour: a light tint of its own most vivid
colour, or a warm sandstone when that colour is sky blue (blue text on a blue
sky is hard to read). photos/photos.json can override either, per file:

    {"castle.webp": {"crop": 0.45, "accent": "#f2dfb5"}}

where crop says where the 16:9 band sits in a taller photo (0 top, 1 bottom).

With photos/ empty, the samples in installer/samples are used instead, so a
fresh install has something besides the landscape.
"""
import colorsys
import json
import os

import numpy as np
from PIL import Image

from landscape import render as render_landscape

SIZE = (1600, 900)
DEFAULT_ACCENT = "#e9a77f"
WARM_FOR_BLUE = "#f2dfb5"
EXTS = (".jpg", ".jpeg", ".png", ".webp")


def photos_in(folder):
    if not os.path.isdir(folder):
        return []
    return sorted(f for f in os.listdir(folder) if f.lower().endswith(EXTS) and not f.startswith("."))


def crop_16_9(im, pos):
    w, h = im.size
    if w * 9 > h * 16:  # wider than 16:9: trim the sides evenly
        cw = round(h * 16 / 9)
        return im.crop(((w - cw) // 2, 0, (w - cw) // 2 + cw, h))
    ch = round(w * 9 / 16)
    y0 = round((h - ch) * pos)
    return im.crop((0, y0, w, y0 + ch))


def accent_for(im):
    """A readable tint of the photo's most vivid colour."""
    a = np.asarray(im.convert("RGB").resize((240, 135)), float) / 255
    mx, mn = a.max(axis=2), a.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    score = (sat * mx).ravel()
    px = a.reshape(-1, 3)[score >= np.quantile(score, 0.97)]
    hues = np.array([colorsys.rgb_to_hsv(*p)[0] for p in px])
    ang = hues * 2 * np.pi
    h = (np.arctan2(np.sin(ang).mean(), np.cos(ang).mean()) / (2 * np.pi)) % 1
    if 0.52 < h < 0.70:  # sky blue
        return WARM_FOR_BLUE
    r, g, b = colorsys.hls_to_rgb(h, 0.78, 0.80)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


SAMPLES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples")


def build(photos, out):
    """Write out/0.jpg .. N.jpg; returns the accents list (index = wallpaper)."""
    if not photos_in(photos):
        photos = SAMPLES
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".jpg"):
            os.remove(os.path.join(out, f))
    render_landscape(SIZE).save(os.path.join(out, "0.jpg"), quality=86, optimize=True, progressive=True)

    overrides = {}
    for name in ("photos.json", "samples.json"):
        if os.path.exists(os.path.join(photos, name)):
            with open(os.path.join(photos, name)) as f:
                overrides.update(json.load(f))

    accents = [DEFAULT_ACCENT]
    for i, name in enumerate(photos_in(photos), 1):
        o = overrides.get(name, {})
        im = Image.open(os.path.join(photos, name)).convert("RGB")
        im = crop_16_9(im, o.get("crop", 0.5)).resize(SIZE, Image.LANCZOS)
        im.save(os.path.join(out, f"{i}.jpg"), quality=84, optimize=True, progressive=True)
        accents.append(o.get("accent") or accent_for(im))
        print(f"  {i:>2}. {name}  {accents[-1]}")
    return accents
