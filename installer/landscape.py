"""The default background: a dusk landscape of layered ridges, rendered."""
import numpy as np
from PIL import Image, ImageFilter


def render(size, seed=7):
    # drawn at twice the size and scaled down, for smooth ridge edges
    W, H = size[0] * 2, size[1] * 2
    rng = np.random.default_rng(seed)

    def mix(a, b, t):
        t = np.clip(t, 0, 1)[..., None]
        return a * (1 - t) + b * t

    def ridge(n, octaves, rough):
        """1D fractal noise, length n, in [-1, 1]."""
        out = np.zeros(n)
        amp, freq = 1.0, 4
        for _ in range(octaves):
            pts = rng.uniform(-1, 1, freq + 1)
            xs = np.linspace(0, freq, n)
            i = np.floor(xs).astype(int).clip(0, freq - 1)
            f = xs - i
            f = f * f * (3 - 2 * f)
            out += amp * (pts[i] * (1 - f) + pts[i + 1] * f)
            amp *= rough
            freq *= 2
        return out / np.abs(out).max()

    y, x = np.mgrid[0:H, 0:W].astype(float)
    u, v = x / W, y / H

    # sky: deep indigo above, a warm band low down, a glow off to the right
    sky = mix(np.array([14, 16, 38.0]), np.array([58, 52, 96.0]), v / 0.55)
    sky = mix(sky, np.array([226, 150, 120.0]), np.clip((v - 0.18) / 0.5, 0, 1) ** 1.8)
    sun = np.exp(-(((u - 0.72) / 0.14) ** 2 + ((v - 0.50) / 0.20) ** 2))
    img = sky + sun[..., None] * np.array([90, 60, 30.0])

    stars = (rng.random((H, W)) > 0.9997) & (v < 0.45) & (u > 0.35)
    img[stars] += 120 * rng.random(stars.sum())[:, None]

    # ridges, far to near: each darker and rougher than the last
    for base, height, rough, colour in [
        (0.60, 0.20, 0.50, [92, 78, 116]),
        (0.70, 0.17, 0.52, [68, 56, 96]),
        (0.80, 0.14, 0.54, [46, 38, 70]),
        (0.90, 0.11, 0.56, [28, 25, 48]),
        (1.00, 0.08, 0.58, [15, 14, 28]),
    ]:
        line = base - height * (1 - np.abs(ridge(W, 8, rough))) + height * 0.5
        mask = v > line[None, :]
        edge = np.clip((v - line[None, :]) / 0.02, 0, 1)
        c = np.array(colour, float)
        img = np.where(mask[..., None], mix(c + 10, c, edge), img)

    # darker on the left, under the greeting; grain so gradients don't band
    img *= (1 - np.clip(1 - u / 0.6, 0, 1) ** 1.4 * 0.66)[..., None]
    img += rng.normal(0, 2.2, img.shape)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    return im.resize(size, Image.LANCZOS)
