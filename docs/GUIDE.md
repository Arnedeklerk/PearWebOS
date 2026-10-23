# The PearWebOS guide

Everything beyond [the README](../README.md).

- [Tested on](#tested-on)
- [Install](#install)
- [What setup asks](#what-setup-asks)
- [Your photos](#your-photos)
- [Using it](#using-it)
- [Settings on the TV](#settings-on-the-tv)
- [Commands](#commands)
- [How it works](#how-it-works)
- [Good to know](#good-to-know)
- [Changing Pear](#changing-pear)
- [Pairs well with](#pairs-well-with)

## Tested on

| TV | webOS | Firmware | Works |
|---|---|---|---|
| LG 65NANO886PB (2021 NanoCell) | 6.4.0 | 03.41.05 | Yes |
| LG OLED65A1PTA (2021 OLED) | 6.5.0 | 03.51.16 | Yes |
| LG 86UP80009LA (2021 UHD) | 6.5.3 | 03.53.45 | Yes |
| LG OLED55B13LA (2021 OLED) | 6.5.3 | ? | Yes |
| LG OLED77C1AUB (2021 OLED) | 6.5.3 | 03.53.45 | Yes |
| LG OLED77C44LA (2024 OLED) | 10.3.1 | 33.31.68 | No: Home is a Flutter app there |

Tried it on another TV? Please [open an issue](https://github.com/Arnedeklerk/PearWebOS/issues/new) with the model, webOS version and firmware (Settings → General → About This TV), and whether it worked.

**Which webOS versions?**

- **webOS 6 (2021 TVs): yes.** That's what Pear is built for, and every report so far has worked.
- **webOS 5 (2020): untested.** It might work. Setup checks before it changes anything, so trying is safe; please report back either way.
- **webOS 4 and older: unlikely.** LG Home was built differently then.
- **webOS 22 and newer, including 10: no.** LG Home there isn't QML any more (on webOS 10 it's a Flutter app), so Pear's approach can't apply. A separate launcher app might work one day; see [#9](https://github.com/Arnedeklerk/PearWebOS/issues/9).

## Install

You need:

- An LG TV on **webOS 6**, **rooted** with [Homebrew Channel](https://www.webosbrew.org/), and **SSH turned on** in Homebrew Channel's settings. On a firmware whose Home differs, setup stops before installing anything.
- A computer on the same network, with Python 3, Pillow and numpy.

**Mac or Linux**

```bash
git clone https://github.com/Arnedeklerk/PearWebOS.git && cd PearWebOS
python3 -m pip install --user pillow numpy
ssh-copy-id root@<your-tv-ip>    # once; Homebrew Channel's password is alpine
./pear setup
```

**Windows**, in PowerShell. Put `python3` in front of `pear` wherever these docs say `./pear` (or `py pear`). Windows has no `ssh-copy-id`, so copy your key with `ssh`:

```powershell
git clone https://github.com/Arnedeklerk/PearWebOS.git; cd PearWebOS
python3 -m pip install --user pillow numpy
ssh-keygen -t ed25519            # once, if you have no SSH key yet
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@<your-tv-ip> "mkdir -p /home/root/.ssh && cat >> /home/root/.ssh/authorized_keys"
python3 pear setup
```

A key with a passphrase needs the SSH agent holding it, since `pear` can't stop to ask. A Mac does this through the keychain. On Windows, start the agent once in an administrator PowerShell with `Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent`, then run `ssh-add`.

**Android**, with [Termux](https://termux.dev): `pkg install python python-pillow python-numpy git openssh`, then as for Linux.

## What setup asks

Run `./pear setup` again any time to change an answer: it offers your current answers as the defaults.

| Question | Default | What it changes |
|---|---|---|
| Name for the greeting | blank | "Good evening, ___". Blank leaves "Good evening". |
| Clock | 24 | 12 hour adds a small AM/PM beside the time. |
| Date style | 1 | 1 "Tuesday 20 October", 2 "Tuesday, October 20", 3 "Tue, Oct 20", 4 "Tue, Oct 20th". |
| Weather | no | Your town (looked up on Open-Meteo), and °C or °F. The TV fetches it every 30 minutes; nothing else goes online. |
| Photo quality | light | Light is 1600×900; high is 1920×1080, the most LG's Home shows. |
| Rise in when Home appears | yes | A short fade and rise. |
| Quiet after 45 seconds | yes | The dock fades away, leaving the photo, greeting and clock; the first press only wakes it. Kinder to OLEDs. |
| Photo slowly zooms | no | A slow drift. It keeps the TV redrawing the whole screen, so it can stutter on some sets. |
| Watch Live TV through an aerial? | no | No turns on `homeguard`, which opens Home rather than leave an empty Live TV. |
| Power on straight to Home | yes | Instead of LG's "Today" wallpapers or the last input. |
| Quick Start+ | yes | Power-off sleeps, so power-on resumes Pear at once. |
| Hide the "update now?" prompt | yes | An update can remove root, and Pear with it. |

Your answers live in `.pear.json` (ignored by git). You can edit it and run `./pear sync` to skip the questions. Most of these can also be changed [on the TV](#settings-on-the-tv); what you change there sticks, because the next `./pear sync` keeps it.

## Your photos

Put photos in `photos/` and run `./pear photos`. They show within a minute, without restarting Home.

- **Crop:** each one is cropped to 16:9 at the photo quality you chose. High is the most the TV can show, since LG's Home draws at 1080p even on a 4K panel.
- **Date colour:** each photo gets one picked from the photo itself.
- **When it changes:** a new photo is picked at random whenever Home comes back after 15 minutes away, which covers every time you turn the TV on.
- **Starter photo:** until you add your own, Pear uses one: a rainy evening in Shibuya.
- **Privacy:** your photos only go to your TV; the folder is ignored by git.
- **Room:** `pear photos` checks the TV has space first, and refuses rather than leave it under 150 MB free (webOS keeps its settings in the same place and misbehaves when it's full). For lots of photos, choose light quality.

To nudge a crop or a colour, see [photos/README.md](../photos/README.md).

## Using it

| Remote | On Home |
|---|---|
| ← → | move along the dock |
| ↓ | open the drawer of all apps |
| ↑ / Back | back to the dock, from the drawer |
| ↑ from the dock | Inputs and Settings, top right |
| OK | open the app |
| hold OK | LG's Edit App List, to reorder or remove apps |
| any button | wake Home from quiet |

The Magic Remote's pointer and wheel work too: point at a tile and click, or scroll down into All apps.

LG's promo apps (LG Channels, Shop Time, Sports Alert and the like) are left off the tiles. To show or hide any app, use **Apps on Home** in Settings.

**Live TV** has its own tile, first in the dock. It's shown if you said you watch Live TV through an aerial, and hidden otherwise (it would only say "Not Programmed"); Apps on Home shows or hides it like any other.

**Your inputs** (HDMI and AV) can have tiles too, named and drawn for what's plugged in: a Switch, PlayStation, Xbox, Apple TV, streaming stick, soundbar, PC and so on. Pear reads what the device tells the TV (its HDMI-CEC name, which needs SIMPLINK on, and the maker and model it sends with its picture); a name you give the input in the TV's settings wins. They're off Home until you turn one on in **Apps on Home**. Inputs are also always one press away, in **Inputs** at the top right.

## Settings on the TV

Press up from the dock and pick the cog.

| Setting | |
|---|---|
| Greeting name | typed with the TV's own keyboard |
| Clock, date style | 24 or 12 hour, and the four date styles |
| Show another photo | right now |
| Rise in, quiet, slow zoom | the touches from setup |
| Town, weather, units | type your town with the TV's keyboard and pick the match; weather on or off; °C or °F |
| Apps on Home | every app and input, shown or hidden |
| TV | never sit on an empty Live TV, power on to Home (off: the TV powers on to its last input), Quick Start+, hide LG's update prompt |
| Restart Pear | re-applies Pear, as setup does |
| Use LG's own Home | turns Pear off; `./pear on` from a computer brings it back |

## Commands

```
./pear setup       find the TV, ask, install
./pear sync        push changed photos, settings and code (restarts Home only for code)
./pear photos      push the photos in photos/, no restart
./pear update      get the latest PearWebOS and put it on the TV
./pear status      what's running on the TV, and which version
./pear on | off    Pear Home, or LG's own
./pear shot        screenshot the TV to docs/screenshot.jpg
./pear uninstall   remove PearWebOS from the TV
```

## How it works

LG Home is written in QML. Pear's own Home is [qml/PearHome.qml](../qml/PearHome.qml), with its parts beside it in [qml/](../qml): the photo, the tiles, the top bar, and the Inputs and Settings panels. It's loaded on top of LG's, which stays running underneath, so launching apps, the app order and Edit App List are still LG's own.

**LG's files stay on your TV.** LG Home is proprietary, so this repository contains none of it. Setup copies the LG files it needs off your TV, applies [small exact edits](../installer/patch_home.py) on your computer, and sends the results back. Each edit must match exactly once, so a firmware that differs fails safely before anything is installed. Pear's own files are mounted over LG files that Home never loads.

On the TV everything lives in `/var/lib/pearwebos`, and a Homebrew Channel startup hook re-applies it at each boot:

- [`pearwebos`](../tv/pearwebos) mounts the files and restarts Home. LG Home is restored from memory snapshots with its QML preloaded, so it has to be cold-started to pick Pear up.
- [`peard`](../tv/peard.js) answers Pear's Home on `127.0.0.1` only: settings, the photo list, inputs, weather, town lookups, and restarting Home. QML inside LG Home can't write files or run commands, so it asks this.
- [`homeguard`](../tv/homeguard) watches what's on screen and opens Home when the TV would otherwise sit on an empty Live TV. It's off if you said you watch Live TV. It logs to `homeguard.log`; touch `/var/lib/pearwebos/debug` to log every change too.
- [`luna-send-n`](../tv/luna-send-n) works around webOS 6.4 firmware whose `luna-send -n` prints nothing.

## Good to know

- **Firmware updates.** An LG update can remove root, and Pear with it. Setup can hide LG's "update now?" prompt. If it ever appears anyway, answer No unless you mean it.
- **A full reboot**, such as after a power cut, starts with LG's stock Home for a few seconds before Pear takes over: LG's boot image holds its own Home, so Pear has to restart it. With Quick Start+ on, ordinary power-ons resume straight into Pear.
- **If Pear's Home fails to load**, LG's Home shows instead, with the reason in small text in the bottom-left corner.
- **Undoing it.** `./pear off` switches back to LG's Home, and `./pear uninstall` removes Pear from the TV. Settings Pear changed on the TV itself (power-on screen, Quick Start+, update prompt) stay as they are; change them back in the TV's own Settings if you want.

## Changing Pear

`python3 installer/check.py` checks everything that can be checked without a TV:
- the Python files,
- the TV's scripts,
- Pear's QML, compiled in Qt 5 the way the TV loads it,
- and that a dock tile actually draws.

It needs `pip install PyQt5`, and it runs on every push and pull request.

## Pairs well with

- [lg-lockout](https://github.com/HunterAP23/lg-lockout): blocks LG's telemetry, ads and ACR on a rooted TV.
- [webos-debloat](https://gist.github.com/lucataco/7c303b443934008a9031a55cfca552ec): stops LG preloading apps you don't use, which frees memory.

## License

MIT; see [LICENSE](../LICENSE). PearWebOS is not affiliated with LG Electronics or Apple. webOS is a trademark of LG Electronics; Apple TV is a trademark of Apple Inc. Rooting your TV may void its warranty; use at your own risk.
