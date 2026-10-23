"""Reaching the TV: SSH and scp as root, finding it on the network, and the
checks that run before anything is installed."""
import os
import socket
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

TV_DIR = "/var/lib/pearwebos"
# early in the startup hooks, so a full boot shows stock Home as briefly as can be
HOOK = "/var/lib/webosbrew/init.d/05-pearwebos"
OLD_HOOKS = ["/var/lib/webosbrew/init.d/60-pearwebos"]

# Windows runs pear as `python3 pear`; messages say so
WINDOWS = os.name == "nt"
PEAR = "python3 pear" if WINDOWS else "./pear"


def ssh(conf, cmd, check=True, stdin=None):
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", f"root@{conf['tv']}", cmd],
                       input=stdin, capture_output=True, check=False)
    if check and r.returncode != 0:
        err = (r.stderr or b"").decode(errors="replace").strip()
        sys.exit(f"On the TV, `{cmd.splitlines()[0][:60]}` failed: {err or r.returncode}")
    return (r.stdout or b"").decode(errors="replace")


def pull(conf, remote, local):
    os.makedirs(os.path.dirname(local), exist_ok=True)
    r = subprocess.run(["scp", "-q", "-o", "BatchMode=yes", f"root@{conf['tv']}:{remote}", local])
    if r.returncode != 0:
        sys.exit(f"Could not copy {remote} from the TV.")


def find_tvs():
    """webOS TVs on this machine's /24: they answer on port 3000."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("192.0.2.1", 80))
        me = s.getsockname()[0]
        s.close()
    except OSError:
        return []
    base = me.rsplit(".", 1)[0]

    def probe(i):
        ip = f"{base}.{i}"
        if ip == me:
            return None
        try:
            with socket.create_connection((ip, 3000), timeout=0.6):
                pass
        except OSError:
            return None
        try:
            with socket.create_connection((ip, 22), timeout=0.6):
                return (ip, True)
        except OSError:
            return (ip, False)

    with ThreadPoolExecutor(64) as ex:
        return [r for r in ex.map(probe, range(1, 255)) if r]


def copy_key_command(tv):
    """Putting this computer's SSH key on the TV; Windows has no ssh-copy-id."""
    if not WINDOWS:
        return f"ssh-copy-id root@{tv}"
    return (f"type $env:USERPROFILE\\.ssh\\id_ed25519.pub | ssh root@{tv} "
            '"mkdir -p /home/root/.ssh && cat >> /home/root/.ssh/authorized_keys"')


def preflight(conf):
    if not conf["tv"]:
        sys.exit(f"No TV yet: run {PEAR} setup")
    try:
        socket.create_connection((conf["tv"], 22), timeout=5).close()
    except OSError:
        sys.exit(f"Can't reach the TV at {conf['tv']}. Is it on, and is SSH on in Homebrew Channel?")
    if subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", f"root@{conf['tv']}", "true"],
                      capture_output=True).returncode != 0:
        sys.exit(f"Can't log into root@{conf['tv']} with an SSH key.\n"
                 "  1. In Homebrew Channel, open Settings and turn on SSH Server.\n"
                 "  2. Copy your key to the TV (the default password is alpine):\n"
                 f"       {copy_key_command(conf['tv'])}\n"
                 f"  Then run {PEAR} setup again.")
    if ssh(conf, "[ -d /var/lib/webosbrew/init.d ] && echo ok", check=False).strip() != "ok":
        sys.exit("This TV has no Homebrew Channel startup hooks (/var/lib/webosbrew/init.d). Is it rooted?")
