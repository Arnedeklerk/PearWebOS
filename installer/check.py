"""Check PearWebOS without a TV: every Python file compiles, the TV scripts
parse, and Pear's QML compiles in Qt 5 the way the TV will load it.

    python3 installer/check.py

Runs in CI on every push and pull request. The QML needs PyQt5
(`pip install PyQt5`); LG's own files aren't needed, as Pear's files are
compiled side by side under the names they're mounted as.
"""
import json
import os
import py_compile
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "installer"))
import patch_home  # noqa: E402

failed = []


def check(name, ok, detail=""):
    print(("ok    " if ok else "FAIL  ") + name + (f"\n      {detail}" if detail and not ok else ""))
    if not ok:
        failed.append(name)


# Python
for f in ["pear"] + [os.path.join("installer", n) for n in sorted(os.listdir(os.path.join(HERE, "installer"))) if n.endswith(".py")]:
    try:
        py_compile.compile(os.path.join(HERE, f), doraise=True)
        check(f, True)
    except py_compile.PyCompileError as e:
        check(f, False, str(e))

# the TV's scripts: busybox sh and node 8
for f in ("pearwebos", "homeguard", "luna-send-n"):
    r = subprocess.run(["sh", "-n", os.path.join(HERE, "tv", f)], capture_output=True, text=True)
    check(f"tv/{f}", r.returncode == 0, r.stderr.strip())
for f in ("tv/peard.js", "tv/tvkey.js", "tv/devices.js", "tv/update.js", "web/home.js", "web/panels.js"):
    r = subprocess.run(["node", "--check", os.path.join(HERE, f)], capture_output=True, text=True)
    check(f, r.returncode == 0, r.stderr.strip())

# the TV updating itself (tv/update.js) makes LG Home's edits as the installer
# does: both, on a stand-in for each LG file holding what the edits look for
stand_ins = {rel: "Item {\n" + "\n".join(e["old"] for e in edits if "old" in e) + "\n}\n"
             for rel, edits in patch_home.PATCHES.items()}
r = subprocess.run(["node", "-e", "var u = require(process.argv[1]), s = JSON.parse(process.argv[2]), o = {};"
                    "var spec = require(process.argv[3]);"
                    "Object.keys(s).forEach(function (k) { o[k] = u.patch(spec, k, s[k]); });"
                    "process.stdout.write(JSON.stringify(o))",
                    os.path.join(HERE, "tv", "update.js"), json.dumps(stand_ins),
                    os.path.join(HERE, "installer", "patches.json")], capture_output=True, text=True)
try:
    js = json.loads(r.stdout)
    differ = [rel for rel, text in stand_ins.items() if js.get(rel) != patch_home.patch(rel, text)]
    check("tv/update.js patches LG Home as the installer does", not differ, ", ".join(differ))
except ValueError:
    check("tv/update.js patches LG Home as the installer does", False, r.stderr.strip())

# Pear's own app (app mode, webOS 10): it packs, with its files where the TV looks
try:
    import app
    pkg = app.ipk("9.9.9")
    import tarfile as _t, gzip as _g, io as _io
    assert pkg.startswith(b"!<arch>\n")
    at, members = 8, {}
    while at < len(pkg):
        name, size = pkg[at:at + 16].decode().strip(), int(pkg[at + 48:at + 58])
        members[name] = pkg[at + 60:at + 60 + size]
        at += 60 + size + size % 2
    names = _t.open(fileobj=_io.BytesIO(_g.decompress(members["data.tar.gz"]))).getnames()
    root = f"./usr/palm/applications/{app.APP_ID}/"
    missing = [f for f in ("appinfo.json", "index.html", "home.js", "panels.js", "pear.css", "icon.png") if root + f not in names]
    check("web/ packs as an app", list(members) == ["debian-binary", "control.tar.gz", "data.tar.gz"] and not missing,
          ", ".join(missing))
except Exception as e:  # noqa: BLE001 (any of it failing is the finding)
    check("web/ packs as an app", False, repr(e))

# what's plugged in: inputs shaped as eim's getAllInputStatus reports them
DEVICE_CASES = [
    ({"icon": "HDMI_1.png"}, {"name": "", "kind": ""}),
    ({"icon": "hometheater.png", "subList": [{"id": "SIMPLINK", "uniqueId": 5, "osdName": "LG SOUND BAR"},
                                             {"id": "URCU", "brandName": "LG"}]},
     {"name": "LG SOUND BAR", "kind": "soundbar"}),
    ({"spdVendorName": "SIE", "spdProductDescription": "PS5", "spdSourceDeviceInfo": "Game"},
     {"name": "PlayStation 5", "kind": "playstation"}),
    ({"spdVendorName": "Nintendo", "spdProductDescription": "Switch 2"}, {"name": "Nintendo Switch 2", "kind": "switch"}),
    # a console through a receiver: the console, not the receiver
    ({"subList": [{"id": "SIMPLINK", "uniqueId": 5, "osdName": "RX-V6A"},
                  {"id": "SIMPLINK", "uniqueId": 4, "depth": 2, "osdName": "NintendoSwitch"}]},
     {"name": "Nintendo Switch", "kind": "switch"}),
    # the TV's broad icon doesn't beat a name that says more
    ({"icon": "gameconsole.png", "forceIcon": True, "subList": [{"id": "SIMPLINK", "uniqueId": 4, "osdName": "PS5"}]},
     {"name": "PlayStation 5", "kind": "playstation"}),
    ({"spdVendorName": "Microsoft", "spdProductDescription": "Xbox Series X"}, {"name": "Xbox Series X", "kind": "xbox"}),
    ({"spdVendorName": "OPPO UDP", "spdProductDescription": "-203", "spdSourceDeviceInfo": "Blu-Ray Disc"},
     {"name": "OPPO UDP -203", "kind": "disc"}),
    ({"icon": "roku.png"}, {"name": "", "kind": "stick"}),
]
r = subprocess.run(["node", "-e", "var d = require(process.argv[1]); process.stdout.write(JSON.stringify("
                    "{got: JSON.parse(process.argv[2]).map(d.describe), kinds: d.KINDS}))",
                    os.path.join(HERE, "tv", "devices.js"), json.dumps([c[0] for c in DEVICE_CASES])],
                   capture_output=True, text=True)
try:
    out = json.loads(r.stdout)
    wrong = [f"{c[0]} gave {g}" for c, g in zip(DEVICE_CASES, out["got"]) if g != c[1]]
    check("tv/devices.js names what's plugged in", not wrong, "; ".join(wrong))
    sys.path.insert(0, os.path.join(HERE, "installer"))
    import icons
    missing = [k for k in set(out["kinds"]) | set(icons.ICONS)
               if k not in icons.ICONS or not os.path.exists(os.path.join(icons.DIR, k + ".png"))]
    check("an icon for every kind of device", not missing, ", ".join(sorted(missing)))
except ValueError:
    check("tv/devices.js names what's plugged in", False, r.stderr.strip())

# QML: filled in as the installer would, both clock styles
try:
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PyQt5.QtCore import QUrl
    from PyQt5.QtGui import QGuiApplication
    from PyQt5.QtQml import QQmlComponent, QQmlEngine
except ImportError:
    check("QML (needs PyQt5)", False, "pip install PyQt5")
else:
    app = QGuiApplication([])
    for clock in ("24", "12"):
        config = {"name": "Test", "clock": clock, "date": "ordinal", "entrance": True, "quiet": True,
                  "drift": False, "hidden": None, "weather": {"on": False}}
        fill = {"CONFIG": json.dumps(config), "PHOTOS": json.dumps({"count": 2, "accents": ["#e9a77f"] * 3})}
        with tempfile.TemporaryDirectory() as tmp:
            for slot, name in patch_home.PEAR_FILES.items():
                with open(os.path.join(HERE, "qml", name), encoding="utf-8") as f:
                    text = f.read()
                for k, v in fill.items():
                    text = text.replace(f"@{k}@", v)
                with open(os.path.join(tmp, os.path.basename(slot)), "w", encoding="utf-8") as f:
                    f.write(text)
            for slot, name in patch_home.PEAR_FILES.items():
                c = QQmlComponent(QQmlEngine(), QUrl.fromLocalFile(os.path.join(tmp, os.path.basename(slot))))
                errors = "; ".join(e.toString().replace(tmp + "/", "") for e in c.errors())
                check(f"qml/{name} ({clock}-hour clock)", c.isReady(), errors)

    # a tile in a list, as the dock makes them: compiling isn't enough (a
    # tile once compiled fine and drew nothing, its `home` bound to itself)
    from PyQt5.QtCore import QObject, QTimer, pyqtProperty

    class Fonts(QObject):
        """LG's fontManager, as far as Pear uses it."""
        class Face(QObject):
            @pyqtProperty(str, constant=True)
            def family(self): return "Sans"
            @pyqtProperty(int, constant=True)
            def weight(self): return 50
        def __init__(self):
            super().__init__()
            self._face = Fonts.Face(self)
        smart_Light = pyqtProperty(QObject, lambda self: self._face, constant=True)
        smart_Regular = pyqtProperty(QObject, lambda self: self._face, constant=True)
        smart_SemiBold = pyqtProperty(QObject, lambda self: self._face, constant=True)

    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(HERE, "qml", "PearTile.qml"), encoding="utf-8") as f:
            tile = f.read()
        with open(os.path.join(tmp, "AdLoadingImage.qml"), "w", encoding="utf-8") as f:
            f.write(tile)
        with open(os.path.join(tmp, "test.qml"), "w", encoding="utf-8") as f:
            f.write("""import QtQuick 2.12
Item {
    id: home
    readonly property Item pearHome: home
    property int tileW: 262; property int tileH: 158; property real s: 1
    property real bumpX: 0; property real bumpY: 0; property bool drawer: false
    property Item dockView: list
    property string result: ""
    function r(v) { return v; }
    function poke() {}
    function launch(e) {}
    ListView {
        id: list
        width: 1000; height: 200; orientation: ListView.Horizontal
        model: [{ title: "A", iconColor: "#ff0000" }]
        delegate: Component { AdLoadingImage { home: pearHome; app: modelData; idx: index } }
    }
    Timer { interval: 50; running: true
            onTriggered: { var d = list.contentItem.children[0];
                           home.result = d && d.width > 0 && d.home === home ? "ok" : "width " + (d ? d.width : "none"); } }
}""")
        engine = QQmlEngine()
        fonts = Fonts()
        engine.rootContext().setContextProperty("fontManager", fonts)
        c = QQmlComponent(engine, QUrl.fromLocalFile(os.path.join(tmp, "test.qml")))
        root = c.create()
        QTimer.singleShot(300, app.quit)
        app.exec_()
        res = root.property("result") if root else "didn't load"
        check("a dock tile draws", res == "ok", res)

print(f"\n{len(failed)} failed" if failed else "\nall good")
sys.exit(1 if failed else 0)
