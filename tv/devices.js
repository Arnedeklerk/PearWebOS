// What's plugged into an input, from what the TV already knows about it:
// the name the device gives over HDMI-CEC (SIMPLINK), the maker and model it
// sends in its HDMI picture info (SPD), and the TV's own guess at its icon.
//
// describe(d) takes one device from eim's getAllInputStatus and returns
// { name, kind }: name '' when nothing says, kind one of KINDS or ''.
// Pear draws an icon for each kind (installer/icons.py).
'use strict';

// first match wins, so the specific before the general
var MATCH = [
    ['switch', /nintendo|\bswitch\b/],
    ['playstation', /playstation|\bps ?[2-5]\b|^sie\b|sony interactive/],
    ['xbox', /xbox/],
    ['appletv', /apple/],
    ['stick', /fire ?tv|amazon|chromecast|google tv|roku/],
    ['streamer', /shield|nvidia|streaming|media player|sky ?q|now ?tv/],
    ['pc', /\bpc\b|computer|windows|steam ?deck|valve|mac ?mini|laptop/],
    ['soundbar', /sound ?bar|sonos|denon|yamaha|onkyo|marantz|bose|receiver|\brx-|\bavr\b|home theat/],
    ['disc', /blu-?ray|\bdvd\b|\bbd\b|\budp\b|oppo|panasonic dp/],
    ['settop', /\bstb\b|set ?top|tivo|virgin|freesat|freeview|youview|satellite|cable box/],
    ['gamepad', /\bgame\b|console/]
];
var KINDS = MATCH.map(function (m) { return m[0]; });

// names are terse ("SIE" "PS5" over SPD, "NintendoSwitch" over CEC's 14
// characters), so the known ones are spelled out
var NAMES = {
    switch: function (p) { return /\b2\b|switch ?2/i.test(p) ? 'Nintendo Switch 2' : 'Nintendo Switch'; },
    playstation: function (p) { var n = /ps ?([2-5])|station ?([2-5])/i.exec(p); return 'PlayStation' + (n ? ' ' + (n[1] || n[2]) : ''); },
    xbox: function (p) { var x = /xbox.*/i.exec(p); return x ? x[0].replace(/^xbox/i, 'Xbox') : 'Xbox'; },
    appletv: function () { return 'Apple TV'; }
};

// the TV's icons, for when it (or you, in its input settings) picked one;
// these are broad, so a name that says more wins
var TV_ICONS = {
    'gameconsole.png': 'gamepad', 'ps3.png': 'playstation', 'xbox.png': 'xbox', 'wii.png': 'switch',
    'appletv.png': 'appletv', 'roku.png': 'stick', 'streamingbox.png': 'streamer',
    'settopbox.png': 'settop', 'satellite.png': 'settop', 'tivo.png': 'settop',
    'bluray.png': 'disc', 'dvd.png': 'disc', 'pc.png': 'pc',
    'hometheater.png': 'soundbar', 'sound.png': 'soundbar'
};

function kindOf(text) {
    text = text.toLowerCase();
    for (var i = 0; i < MATCH.length; i++) if (MATCH[i][1].test(text)) return MATCH[i][0];
    return '';
}

function describe(d) {
    var cec = '', audio = '', brand = '';
    (d.subList || []).forEach(function (s) {
        // CEC logical address 5 is the audio system: a soundbar on ARC, which
        // usually isn't what the input is for, so anything else comes first
        if (s.id === 'SIMPLINK' && s.osdName) {
            if (s.uniqueId === 5) audio = audio || s.osdName; else cec = cec || s.osdName;
        }
        if (s.id === 'URCU' && s.brandName) brand = s.brandName;
    });
    var spd = [d.spdVendorName, d.spdProductDescription].map(function (x) { return (x || '').trim(); })
        .filter(Boolean).join(' ');
    var said = cec || spd || audio;
    var kind = kindOf(said) || kindOf([cec, spd, audio, brand, d.spdSourceDeviceInfo || ''].join(' | '));
    var tvKind = TV_ICONS[d.icon] || '';
    if (tvKind && (!kind || kind === 'gamepad')) kind = tvKind;
    var named = NAMES[kindOf(said)];
    return { name: named ? named(said) : said, kind: kind };
}

module.exports = { describe: describe, KINDS: KINDS };
