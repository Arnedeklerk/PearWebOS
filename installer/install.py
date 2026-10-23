"""Building Pear and putting it on the TV.

Three things go across, and only what changed:
- Pear's code: the patched LG files and Pear's own QML, plus the TV scripts.
  Changing these restarts Home, so it happens only when they changed.
- Settings: config.json, which Pear's Home and peard read while running.
- Photos: wallpapers/ and their index, read while running too.
"""
import hashlib
import io
import json
import os
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request

from remote import HOOK, OLD_HOOKS, PEAR, TV_DIR, pull, ssh

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(HERE, ".cache")
SCRIPTS = ("pearwebos", "homeguard", "luna-send-n", "tvkey.js", "peard.js", "devices.js")
# what can be changed on the TV itself; the rest (the TV's address, photo
# quality, where the weather is) only from here
TV_SETTINGS = ("name", "clock", "date", "entrance", "quiet", "drift", "hidden", "inputs", "weather",
               "guard", "boot_to_home", "quick_start", "no_update_prompt")


def version():
    with open(os.path.join(HERE, "VERSION")) as f:
        return f.read().strip()


def need_imaging():
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        sys.exit("PearWebOS needs Pillow and numpy on this computer:\n"
                 "  python3 -m pip install --user pillow numpy")


def tar_of(entries):
    """entries: (name in the tar, bytes, mode). A tar as bytes, LF and all."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        for name, data, mode in entries:
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data), mode, int(time.time())
            tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def tree(root, prefix):
    """(prefix/relative path, bytes, 0o644) for every file under root."""
    out = []
    for d, _, files in os.walk(root):
        for f in sorted(files):
            p = os.path.join(d, f)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            with open(p, "rb") as fh:
                out.append((f"{prefix}/{rel}", fh.read(), 0o644))
    return out


# ---- settings ----

def merge_from_tv(conf):
    """Take settings changed on the TV since this computer last synced."""
    raw = ssh(conf, f"cat {TV_DIR}/config.json 2>/dev/null", check=False)
    try:
        tv = json.loads(raw)
    except ValueError:
        return
    if tv.get("changed_at", 0) <= conf.get("synced_at", 0):
        return
    taken = [k for k in TV_SETTINGS if k in tv and tv[k] != conf.get(k)]
    for k in taken:
        conf[k] = tv[k]
    if taken:
        print(f"  Kept what was changed on the TV: {', '.join(taken)}")


def tv_config(conf):
    c = {k: conf.get(k) for k in TV_SETTINGS}
    c["changed_at"] = conf["synced_at"]
    return c


def push_settings(conf):
    conf["synced_at"] = int(time.time() * 1000)
    data = json.dumps(tv_config(conf), indent=2).encode()
    conf_sh = "".join(f"{k.upper()}={1 if conf[k] else 0}\n"
                      for k in ("guard", "boot_to_home", "quick_start", "no_update_prompt")).encode()
    ssh(conf, f"mkdir -p {TV_DIR} && cd {TV_DIR} && tar xf -",
        stdin=tar_of([("config.json", data, 0o644), ("pear.conf", conf_sh, 0o644)]))


def find_place(name):
    """A town name to a place with coordinates, through Open-Meteo's geocoder."""
    url = "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + urllib.parse.quote(name)
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            hit = (json.load(r).get("results") or [None])[0]
    except OSError:
        return None
    if not hit:
        return None
    where = ", ".join(x for x in (hit.get("name"), hit.get("country")) if x)
    return {"place": where, "lat": round(hit["latitude"], 3), "lon": round(hit["longitude"], 3)}


# ---- photos ----

# what /var must keep free: webOS keeps its settings and app data there, and
# misbehaves badly when it fills up
KEEP_FREE_MB = 150


def check_room(conf, size):
    """Refuse photos that would leave the TV's /var short of space."""
    out = ssh(conf, f"df -k /var | tail -1; du -sk {TV_DIR}/wallpapers 2>/dev/null", check=False).split()
    try:
        free_kb = int(out[3]) + (int(out[6]) if len(out) > 6 else 0)   # plus the photos being replaced
    except (IndexError, ValueError):
        return
    after_mb = (free_kb * 1024 - size) // (1024 * 1024)
    if after_mb < KEEP_FREE_MB:
        sys.exit(f"Those photos ({size // (1024 * 1024)} MB) would leave the TV only {max(after_mb, 0)} MB free "
                 f"(it needs {KEEP_FREE_MB} MB to run well). Use fewer photos, or light quality. Nothing was sent.")

def push_photos(conf):
    need_imaging()
    import wallpapers
    with tempfile.TemporaryDirectory() as tmp:
        print("Building wallpapers from photos/ ...")
        accents = wallpapers.build(os.path.join(HERE, "photos"), tmp, conf.get("wallpaper_quality", "light"))
        index = json.dumps({"count": len(accents) - 1, "accents": accents}).encode()
        entries = tree(tmp, "wallpapers") + [("wallpapers/index.json", index, 0o644)]
    check_room(conf, sum(len(e[1]) for e in entries))
    ssh(conf, f"mkdir -p {TV_DIR} && cd {TV_DIR} && rm -rf wallpapers && tar xf -", stdin=tar_of(entries))
    return accents


# ---- Pear's code ----

def code_hash(mode):
    """Everything that, when changed, needs Home restarting."""
    h = hashlib.sha256(mode.encode())
    for d in ("qml", "tv", "icons", "web"):
        for f in sorted(os.listdir(os.path.join(HERE, d))):
            if not os.path.isfile(os.path.join(HERE, d, f)):
                continue
            with open(os.path.join(HERE, d, f), "rb") as fh:
                h.update(f.encode() + fh.read())
    for f in ("installer/patch_home.py", "VERSION"):
        with open(os.path.join(HERE, f), "rb") as fh:
            h.update(fh.read())
    return h.hexdigest()[:16]


def patched_home(conf, accents):
    """LG Home's files, patched to load Pear (qml mode): ("files/...", bytes, mode)."""
    import patch_home
    print("Copying LG Home's files from the TV (they stay on your machine)...")
    # with Pear installed, its own copies are mounted over LG's; take them off
    # first (Home keeps running: it read its files when it started)
    ssh(conf, f"[ -x {TV_DIR}/pearwebos ] && {TV_DIR}/pearwebos unmount; true")
    stock = os.path.join(CACHE, "stock")
    for rel in patch_home.NEEDED:
        pull(conf, f"{patch_home.APP}/{rel}", os.path.join(stock, rel))
        with open(os.path.join(stock, rel), encoding="utf-8", errors="replace") as f:
            text = f.read()
        if "skinHome" in text or "PearWebOS" in text:
            sys.exit(f"{rel} on the TV is still Pear's copy, not LG's. Run {PEAR} off, then try again.")

    with tempfile.TemporaryDirectory() as tmp:
        print("Patching LG Home...")
        patch_home.build(stock, tmp, os.path.join(HERE, "qml"), {
            "CONFIG": json.dumps(tv_config(conf)),
            "PHOTOS": json.dumps({"count": len(accents) - 1, "accents": accents}),
        })
        return tree(tmp, "files")


def push_code(conf, accents, force=False):
    """Send Pear's code and restart Home, if any of it changed: patched into LG
    Home where that's QML, else as an app of its own (installer/app.py)."""
    import app
    import icons
    mode = app.home_kind(ssh, conf)
    want = code_hash(mode)
    have = ssh(conf, f"cat {TV_DIR}/code.sha 2>/dev/null; [ -f {app.APP_DIR}/appinfo.json ] || echo no-app",
               check=False).split()
    if not force and have[:1] == [want] and not (mode == "app" and "no-app" in have):
        print("Pear's code on the TV is current; Home picks up settings and photos within a minute.")
        return False

    entries = patched_home(conf, accents) if mode == "qml" else [("mode", b"app\n", 0o644)]
    for script in SCRIPTS:
        # LF only, whatever the checkout did: "#!/bin/sh\r" is "not found"
        with open(os.path.join(HERE, "tv", script), "rb") as f:
            entries.append((script, f.read().replace(b"\r\n", b"\n"), 0o755))
    entries += [("VERSION", (version() + "\n").encode(), 0o644), ("code.sha", (want + "\n").encode(), 0o644)]
    entries += [(f"icons/{name}.png", png, 0o644) for name, png in icons.files()]

    print("Installing on the TV...")
    ssh(conf, f"mkdir -p {TV_DIR} && cd {TV_DIR} && {{ [ -x ./pearwebos ] && ./pearwebos unmount; true; }} && "
              "rm -rf files mode && tar xf -", stdin=tar_of(entries))
    if mode == "app":
        print("  LG's Home here isn't QML (webOS 10?), so Pear goes in as an app of its own.")
        ssh(conf, "cat > /tmp/pearwebos.ipk", stdin=app.ipk(version()))
        out = ssh(conf, f"{TV_DIR}/pearwebos install-app /tmp/pearwebos.ipk 2>&1; s=$?; rm -f /tmp/pearwebos.ipk; exit $s",
                  check=False)
        if "installed" not in out:
            sys.exit("Couldn't install Pear's app on the TV:\n  " + out.strip())
    # in the background, so a slow boot neither holds up nor waits on other hooks
    ssh(conf, f"rm -f {' '.join(OLD_HOOKS)}; printf '#!/bin/sh\\n# PearWebOS\\n"
              f"setsid {TV_DIR}/pearwebos boot </dev/null >/dev/null 2>&1 &\\n' > {HOOK} && chmod 755 {HOOK}")
    print("Starting Pear Home" + (" (about 15 seconds)..." if mode == "qml" else "..."))
    out = ssh(conf, f"{TV_DIR}/pearwebos on 2>&1 | tail -1; {TV_DIR}/pearwebos settings; true")
    print("  " + out.strip())
    return True


def sync(conf, force=False):
    merge_from_tv(conf)
    accents = push_photos(conf)
    push_settings(conf)
    push_code(conf, accents, force)
    ssh(conf, f"{TV_DIR}/pearwebos settings; true", check=False)
