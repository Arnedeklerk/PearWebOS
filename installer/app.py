"""App mode: Pear as an app of its own, for TVs whose LG Home isn't QML
(webOS 10's is Flutter). The app is web/, packed as an .ipk the way
ares-package packs one, and installed through the TV's own app installer
(as Homebrew Channel does); tv/homeguard opens it whenever LG's Home comes up.
"""
import gzip
import io
import json
import os
import tarfile
import time

APP_ID = "org.pearwebos.home"
WEB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web")


def home_kind(ssh, conf):
    """"qml" where LG Home can be patched, "app" where Pear needs its own app.
    PEAR_MODE=app forces app mode (to try it on a webOS 6 TV)."""
    if os.environ.get("PEAR_MODE") in ("app", "qml"):
        return os.environ["PEAR_MODE"]
    out = ssh(conf, "h=/usr/palm/applications/com.webos.app.home; "
                    "[ -d $h/qml ] && echo qml || { [ -f $h/appinfo.json ] && echo app; }", check=False).strip()
    return out or "qml"


def _tgz(entries):
    """entries: (path, bytes or None for a directory). A .tar.gz as bytes."""
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for name, data in entries:
            info = tarfile.TarInfo(name)
            info.mtime = int(time.time())
            if data is None:
                info.type, info.mode = tarfile.DIRTYPE, 0o755
                tar.addfile(info)
            else:
                info.size, info.mode = len(data), 0o644
                tar.addfile(info, io.BytesIO(data))
    return gzip.compress(raw.getvalue(), mtime=0)


def _ar(members):
    out = [b"!<arch>\n"]
    for name, data in members:
        head = f"{name:<16}{int(time.time()):<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n"
        out += [head.encode(), data, b"\n" if len(data) % 2 else b""]
    return b"".join(out)


def ipk(version):
    """web/ as an installable package, carrying this version."""
    root = f"./usr/palm/applications/{APP_ID}"
    files, size = [], 0
    for d, _, names in os.walk(WEB):
        for n in sorted(names):
            p = os.path.join(d, n)
            rel = os.path.relpath(p, WEB).replace(os.sep, "/")
            with open(p, "rb") as f:
                data = f.read()
            if rel == "appinfo.json":
                info = json.loads(data)
                info["version"] = version
                data = json.dumps(info, indent=4).encode()
            files.append((f"{root}/{rel}", data))
            size += len(data)
    dirs = sorted({os.path.dirname(f) for f, _ in files} | {"./usr", "./usr/palm", "./usr/palm/applications", root})
    control = (f"Package: {APP_ID}\nVersion: {version}\nSection: misc\nPriority: optional\nArchitecture: all\n"
               f"Installed-Size: {size // 1024 + 1}\nMaintainer: PearWebOS\n"
               "Description: Pear, an Apple TV style Home\nwebOS-Package-Format-Version: 2\n"
               "webOS-Packager-Version: x.y.x\n").encode()
    return _ar([("debian-binary", b"2.0\n"),
                ("control.tar.gz", _tgz([("./control", control)])),
                ("data.tar.gz", _tgz([(d, None) for d in dirs] + files))])
