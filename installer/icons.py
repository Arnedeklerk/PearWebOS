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


# ---- what's plugged in, by the kind tv/devices.js finds ----
# white only: the tile behind gives the colour (kindColours in PearHome.qml)

def controller(d, n, w):
    """A game controller's outline, for the consoles that have no better shape:
    a body and two grips, filled, less the same shapes drawn a line's width in."""
    shapes = [("r", 0.20, 0.36, 0.80, 0.58), ("e", 0.13, 0.40, 0.37, 0.74), ("e", 0.63, 0.40, 0.87, 0.74)]
    for fill, inset in (("white", 0), ("#00000000", w / n)):
        for kind, x0, y0, x1, y1 in shapes:
            box = (n * (x0 + inset), n * (y0 + inset), n * (x1 - inset), n * (y1 - inset))
            if kind == "r":
                d.rounded_rectangle(box, radius=n * (0.11 - inset), fill=fill)
            else:
                d.ellipse(box, fill=fill)


def dot(d, n, x, y, r, fill="white"):
    d.ellipse((n * (x - r), n * (y - r), n * (x + r), n * (y + r)), fill=fill)


def switch(d, n, w):
    d.rounded_rectangle((n * 0.33, n * 0.32, n * 0.67, n * 0.68), radius=n * 0.03, outline="white", width=w)
    d.rounded_rectangle((n * 0.17, n * 0.32, n * 0.30, n * 0.68), radius=n * 0.065, outline="white", width=w)
    d.rounded_rectangle((n * 0.70, n * 0.32, n * 0.83, n * 0.68), radius=n * 0.065, outline="white", width=w)
    dot(d, n, 0.235, 0.43, 0.026)
    dot(d, n, 0.765, 0.56, 0.026)


def playstation(d, n, w):
    # the four face-button shapes
    d.polygon([(n * 0.36, n * 0.25), (n * 0.27, n * 0.40), (n * 0.45, n * 0.40)], outline="white", width=w)
    d.ellipse((n * 0.56, n * 0.25, n * 0.72, n * 0.41), outline="white", width=w)
    d.line((n * 0.29, n * 0.59, n * 0.43, n * 0.73), fill="white", width=w)
    d.line((n * 0.43, n * 0.59, n * 0.29, n * 0.73), fill="white", width=w)
    d.rectangle((n * 0.57, n * 0.59, n * 0.71, n * 0.73), outline="white", width=w)


def xbox(d, n, w):
    controller(d, n, w)
    for x, y in ((0.65, 0.445), (0.61, 0.485), (0.69, 0.485), (0.65, 0.525)):
        dot(d, n, x, y, 0.022)
    dot(d, n, 0.35, 0.47, 0.035)


def gamepad(d, n, w):
    controller(d, n, w)
    d.line((n * 0.30, n * 0.48, n * 0.40, n * 0.48), fill="white", width=w)
    d.line((n * 0.35, n * 0.43, n * 0.35, n * 0.53), fill="white", width=w)
    dot(d, n, 0.62, 0.50, 0.026)
    dot(d, n, 0.68, 0.455, 0.026)


def appletv(d, n, w):
    d.rounded_rectangle((n * 0.16, n * 0.44, n * 0.62, n * 0.66), radius=n * 0.06, outline="white", width=w)
    # and its remote
    d.rounded_rectangle((n * 0.70, n * 0.28, n * 0.84, n * 0.72), radius=n * 0.07, outline="white", width=w)
    dot(d, n, 0.77, 0.38, 0.035)


def stick(d, n, w):
    d.rounded_rectangle((n * 0.18, n * 0.40, n * 0.66, n * 0.60), radius=n * 0.06, outline="white", width=w)
    d.rectangle((n * 0.66, n * 0.44, n * 0.80, n * 0.56), fill="white")


def streamer(d, n, w):
    d.rounded_rectangle((n * 0.18, n * 0.34, n * 0.82, n * 0.66), radius=n * 0.07, outline="white", width=w)
    d.polygon([(n * 0.45, n * 0.42), (n * 0.45, n * 0.58), (n * 0.59, n * 0.50)], fill="white")


def settop(d, n, w):
    d.rounded_rectangle((n * 0.14, n * 0.38, n * 0.86, n * 0.64), radius=n * 0.04, outline="white", width=w)
    d.rectangle((n * 0.24, n * 0.47, n * 0.46, n * 0.55), fill="white")
    dot(d, n, 0.70, 0.51, 0.025)
    dot(d, n, 0.77, 0.51, 0.025)


def pc(d, n, w):
    d.rounded_rectangle((n * 0.26, n * 0.28, n * 0.74, n * 0.60), radius=n * 0.03, outline="white", width=w)
    d.rounded_rectangle((n * 0.16, n * 0.66, n * 0.84, n * 0.72), radius=n * 0.02, fill="white")


def soundbar(d, n, w):
    d.rounded_rectangle((n * 0.12, n * 0.52, n * 0.88, n * 0.66), radius=n * 0.07, outline="white", width=w)
    for x in (0.30, 0.42, 0.58, 0.70):
        dot(d, n, x, 0.59, 0.022)
    # sound rising from it
    for r in (0.12, 0.22):
        d.arc((n * (0.5 - r), n * (0.44 - r), n * (0.5 + r), n * (0.44 + r)), 225, 315, fill="white", width=w)


def disc(d, n, w):
    d.ellipse((n * 0.24, n * 0.24, n * 0.76, n * 0.76), outline="white", width=w)
    d.ellipse((n * 0.44, n * 0.44, n * 0.56, n * 0.56), outline="white", width=w)


DEVICES = {f.__name__: f for f in (switch, playstation, xbox, gamepad, appletv, stick, streamer, settop, pc,
                                   soundbar, disc)}


def device(kind, size=192):
    im, d, n = canvas(size)
    DEVICES[kind](d, n, int(n * 0.05))
    return png(im, size)
