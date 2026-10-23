"""Icons Pear draws itself, for tiles LG has no launch point for.

livetv.png: a screen with a red "on air" dot, white on clear; the tile
behind it gives the colour.
input.png: an HDMI port, for the TV's inputs.
"""
import io

from PIL import Image, ImageDraw


def canvas(size):
    n = size * 4  # drawn large and scaled down, for smooth edges
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im), n


def png(im, size):
    im = im.resize((size, size), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "PNG", optimize=True)
    return out.getvalue()


def live_tv(size=192):
    im, d, n = canvas(size)
    w = int(n * 0.055)
    # the screen
    d.rounded_rectangle((n * 0.20, n * 0.26, n * 0.80, n * 0.66), radius=n * 0.06, outline="white", width=w)
    # its stand
    d.line((n * 0.40, n * 0.76, n * 0.60, n * 0.76), fill="white", width=w)
    d.line((n * 0.50, n * 0.66, n * 0.50, n * 0.76), fill="white", width=w)
    # on air
    r = n * 0.055
    d.ellipse((n * 0.50 - r, n * 0.46 - r, n * 0.50 + r, n * 0.46 + r), fill="#ff453a")
    return png(im, size)


def input(size=192):
    im, d, n = canvas(size)
    w = int(n * 0.055)
    # the port: square shoulders, the bottom corners cut in
    l, r, t, b, cut = n * 0.18, n * 0.82, n * 0.36, n * 0.62, n * 0.10
    d.line([(n * 0.5, t), (r, t), (r, b - cut), (r - cut, b), (l + cut, b), (l, b - cut), (l, t), (n * 0.5, t)],
           fill="white", width=w, joint="curve")
    # its row of pins
    d.rounded_rectangle((n * 0.30, n * 0.45, n * 0.70, n * 0.51), radius=n * 0.02, fill="white")
    return png(im, size)
