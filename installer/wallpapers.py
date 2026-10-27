"""Background photos for the Pear Home.

Every image in photos/ (jpg, png, webp) becomes wallpapers/<n>.jpg: cropped
to 16:9, shaded for the text and tiles on top, and saved at 1600x900
("light") or 1920x1080 ("high"). 0.jpg is always the rendered dusk landscape.

Each photo also gets a date colour: a light tint of its own most vivid
colour, or a warm sandstone when that colour is sky blue (blue text on a blue
sky is hard to read). photos/photos.json can override either, per file:

    {"castle.webp": {"crop": 0.45, "accent": "#f2dfb5"}}

where crop says where the 16:9 band sits in a taller photo (0 top, 1 bottom).

With photos/ empty, the samples in installer/samples are used instead, so a
fresh install has something besides the landscape.

Built photos are kept in .cache/wallpapers, by what they were made from, so
adding one photo to two hundred builds one (the rest come from the cache).
"""
import colorsys
import hashlib
import json
import os
import shutil

import numpy as np
from PIL import Image

from landscape import render as render_landscape

# "light" keeps each photo small; "high" is the most LG Home can show, as it
# draws at 1920x1080 whatever the panel (a 4K photo would be scaled down)
QUALITY = {"light": ((1600, 900), 84), "high": ((1920, 1080), 92)}
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


def shade(im):
    """Bake in the shading Pear's Home used to draw over every photo: dark at
    the top under the greeting, darker towards the bottom under the tiles.
    One full-screen layer for the TV to draw instead of three."""
    w, h = im.size
    v = np.linspace(0, 1, h)[:, None, None]
    a = np.asarray(im, float)
    # top: 0.55 at the edge, gone by 45% down
    top = np.clip(1 - v / 0.45, 0, 1) * 0.55
    a = a * (1 - top) + np.array([5, 5, 13.0]) * top
    # bottom: 0 to 0.10 by 45% down, then to 0.78 at the bottom edge
    bottom = np.where(v < 0.45, v / 0.45 * 0.10, 0.10 + (v - 0.45) / 0.55 * 0.68)
    a = a * (1 - bottom) + np.array([6, 6, 15.0]) * bottom
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(HERE, "samples")
CACHE = os.path.join(os.path.dirname(HERE), ".cache", "wallpapers")


def _code():
    """What a built photo also depends on: how it's built."""
    h = hashlib.sha256()
    for f in ("wallpapers.py", "landscape.py"):
        with open(os.path.join(HERE, f), "rb") as fh:
            h.update(fh.read())
    return h.hexdigest()


def _overrides(photos):
    overrides = {}
    for name in ("photos.json", "samples.json"):
        if os.path.exists(os.path.join(photos, name)):
            with open(os.path.join(photos, name)) as f:
                overrides.update(json.load(f))
    return overrides


def source(photos, quality="light"):
    """A fingerprint of everything the wallpapers would be built from (names,
    sizes and times, overrides, quality, the code), to skip an unchanged set
    without opening a photo."""
    if not photos_in(photos):
        photos = SAMPLES
    h = hashlib.sha256(f"{quality}|{_code()}|{json.dumps(_overrides(photos), sort_keys=True)}".encode())
    for name in photos_in(photos):
        st = os.stat(os.path.join(photos, name))
        h.update(f"|{name}|{st.st_size}|{st.st_mtime_ns}".encode())
    return h.hexdigest()[:16]


def _cached(key, make):
    """(jpg path, accent) for key, built by make(path) -> accent when new."""
    os.makedirs(CACHE, exist_ok=True)
    jpg, txt = os.path.join(CACHE, key + ".jpg"), os.path.join(CACHE, key + ".accent")
    if not (os.path.exists(jpg) and os.path.exists(txt)):
        accent = make(jpg + ".tmp")
        os.replace(jpg + ".tmp", jpg)
        with open(txt, "w") as f:
            f.write(accent)
    with open(txt) as f:
        return jpg, f.read().strip()


def build(photos, out, quality="light"):
    """Write out/0.jpg .. N.jpg; returns the accents list (index = wallpaper)."""
    size, q = QUALITY.get(quality, QUALITY["light"])
    if not photos_in(photos):
        photos = SAMPLES
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".jpg"):
            os.remove(os.path.join(out, f))
    code = _code()

    def landscape(path):
        shade(render_landscape(size)).save(path, "JPEG", quality=q, optimize=True, progressive=True)
        return DEFAULT_ACCENT
    jpg, _ = _cached(hashlib.sha256(f"landscape|{quality}|{code}".encode()).hexdigest()[:24], landscape)
    shutil.copyfile(jpg, os.path.join(out, "0.jpg"))

    overrides = _overrides(photos)
    accents, built = [DEFAULT_ACCENT], 0
    for i, name in enumerate(photos_in(photos), 1):
        o = overrides.get(name, {})
        with open(os.path.join(photos, name), "rb") as f:
            key = hashlib.sha256(f.read() + f"|{quality}|{o.get('crop', 0.5)}|{code}".encode()).hexdigest()[:24]

        def make(path, name=name, o=o):
            nonlocal built
            built += 1
            im = Image.open(os.path.join(photos, name)).convert("RGB")
            im = crop_16_9(im, o.get("crop", 0.5)).resize(size, Image.LANCZOS)
            shade(im).save(path, "JPEG", quality=q, optimize=True, progressive=True)
            return accent_for(im)
        jpg, accent = _cached(key, make)
        shutil.copyfile(jpg, os.path.join(out, f"{i}.jpg"))
        accents.append(o.get("accent") or accent)
        print(f"  {i:>2}. {name}  {accents[-1]}")
    if built < len(accents) - 1:
        print(f"  ({built} built, {len(accents) - 1 - built} from the cache)")
    return accents
