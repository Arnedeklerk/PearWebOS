"""Icons for tiles LG has no launch point for: Live TV, and the inputs by
what's plugged in (the kinds tv/devices.js finds).

They're Tabler Icons (MIT, icons/tabler/), white on clear; the tile behind
gives the colour (kindColours in PearHome.qml). The PNGs the TV gets are in
icons/, made from the SVGs by `python3 installer/icons.py` (needs PyQt5).
"""
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(HERE, "icons")

# icon name on the TV: the Tabler icon it is
ICONS = {
    "livetv": "device-tv", "input": "plug-connected",
    "switch": "device-gamepad", "playstation": "device-gamepad-2", "xbox": "brand-xbox",
    "gamepad": "device-gamepad-2", "appletv": "brand-apple", "stick": "usb", "streamer": "cast",
    "settop": "antenna", "pc": "device-desktop", "soundbar": "volume", "disc": "disc",
}
DEVICES = [k for k in ICONS if k not in ("livetv", "input")]

SIZE = 192
GLYPH = 0.48  # of the image; the tile shows it at most 94% of its height


def files():
    """(name on the TV, png bytes) for every icon."""
    out = []
    for name in ICONS:
        with open(os.path.join(DIR, name + ".png"), "rb") as f:
            out.append((name, f.read()))
    return out


def render():
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PyQt5.QtCore import QByteArray, QRectF, Qt
    from PyQt5.QtGui import QGuiApplication, QImage, QPainter
    from PyQt5.QtSvg import QSvgRenderer
    app = QGuiApplication(sys.argv)  # noqa: F841 (Qt wants one)
    for name, tabler in ICONS.items():
        with open(os.path.join(DIR, "tabler", tabler + ".svg")) as f:
            svg = f.read().replace("currentColor", "#ffffff")
        im = QImage(SIZE, SIZE, QImage.Format_ARGB32)
        im.fill(Qt.transparent)
        p = QPainter(im)
        p.setRenderHint(QPainter.Antialiasing)
        g = SIZE * GLYPH
        QSvgRenderer(QByteArray(svg.encode())).render(p, QRectF((SIZE - g) / 2, (SIZE - g) / 2, g, g))
        p.end()
        im.save(os.path.join(DIR, name + ".png"))
    print(f"{len(ICONS)} icons in {DIR}")


if __name__ == "__main__":
    render()
