// update.js: PearWebOS updating itself, on the TV (Settings → Update).
//
// What `./pear update` does from a computer, minus the photos (which don't
// change with a release): get the latest release from GitHub, make LG Home's
// edits from its patches.json (as installer/patch_home.py does), or pack the
// app (as installer/app.py does), put the new files in place and restart Home.
// Nothing is touched until everything is built, so a failed update changes
// nothing.
//
//   node update.js check              {current, latest} as JSON
//   node update.js install [vX.Y.Z]   the latest release (or that one)
//
// Progress is in update.json, which peard serves to Settings. Node 8: no
// optional chaining, no fs.mkdirSync recursive.
'use strict';

var fs = require('fs');
var https = require('https');
var zlib = require('zlib');
var child = require('child_process');

var DIR = process.env.PEAR_DIR || '/var/lib/pearwebos';
var REPO = 'Arnedeklerk/PearWebOS';
var STATE = DIR + '/update.json';
var STAGE = DIR + '/update.new';
var APP_ID = 'org.pearwebos.home';

function version() {
    try { return fs.readFileSync(DIR + '/VERSION', 'utf8').trim(); } catch (e) { return '0'; }
}

// 0.5.10 is newer than 0.5.9
function newer(a, b) {
    var x = String(a).replace(/^v/, '').split('.').map(Number), y = String(b).replace(/^v/, '').split('.').map(Number);
    for (var i = 0; i < Math.max(x.length, y.length); i++) {
        if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0);
    }
    return false;
}

function state(s, message) {
    var out = { state: s, message: message || '', at: Date.now() };
    fs.writeFileSync(STATE, JSON.stringify(out));
    console.log(s + (message ? ': ' + message : ''));
}

// ---- fetching ----

// (Node 8 takes one options object, not a URL and options)
function get(url, cb, hops) {
    var o = require('url').parse(url);
    o.headers = { 'User-Agent': 'PearWebOS', Accept: 'application/vnd.github+json' };
    https.get(o, function (res) {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && (hops || 0) < 5) {
            res.resume();
            return get(res.headers.location, cb, (hops || 0) + 1);
        }
        var chunks = [];
        res.on('data', function (d) { chunks.push(d); });
        res.on('end', function () {
            if (res.statusCode !== 200) return cb(new Error(url.split('?')[0] + ' answered ' + res.statusCode));
            cb(null, Buffer.concat(chunks));
        });
    }).on('error', cb);
}

function latest(cb) {
    get('https://api.github.com/repos/' + REPO + '/releases/latest', function (err, body) {
        if (err) return cb(err);
        try { cb(null, JSON.parse(body).tag_name); } catch (e) { cb(e); }
    });
}

// a .tar as {path: Buffer}, without the top folder GitHub puts it all in
function untar(buf) {
    var files = {}, at = 0, longName = null;
    while (at + 512 <= buf.length) {
        var h = buf.slice(at, at + 512);
        if (h[0] === 0) break;
        var field = function (o, n) { return h.slice(o, o + n).toString('utf8').replace(/\0[\s\S]*$/, ''); };
        var size = parseInt(field(124, 12).trim() || '0', 8);
        var type = field(156, 1) || '0';
        var name = longName || ((field(345, 155) ? field(345, 155) + '/' : '') + field(0, 100));
        longName = null;
        var data = buf.slice(at + 512, at + 512 + size);
        at += 512 + Math.ceil(size / 512) * 512;
        if (type === 'x') {   // pax: a long path for the next entry
            var m = /\d+ path=([^\n]*)\n/.exec(data.toString('utf8'));
            if (m) longName = m[1];
        } else if (type === 'L') {
            longName = data.toString('utf8').replace(/\0+$/, '');
        } else if (type === '0') {
            files[name.replace(/^[^/]*\//, '')] = data;
        }
    }
    return files;
}

// ---- building ----

function mkdirs(path) {
    var parts = path.split('/'), p = '';
    for (var i = 1; i < parts.length; i++) {
        p += '/' + parts[i];
        try { fs.mkdirSync(p); } catch (e) { if (e.code !== 'EEXIST') throw e; }
    }
}

function put(path, data, mode) {
    mkdirs(path.replace(/\/[^/]*$/, ''));
    fs.writeFileSync(path, data, mode ? { mode: mode } : undefined);
    if (mode) fs.chmodSync(path, mode);
}

// LG Home's files with Pear's edits, from patches.json: every edit matches
// exactly once, an optional one may be absent, and `end` goes before the
// file's final closing brace (as installer/patch_home.py)
function patch(spec, rel, text) {
    spec.patches[rel].forEach(function (edit) {
        if (edit.end) {
            var cut = text.replace(/\s+$/, '').lastIndexOf('}');
            if (cut < 0) throw new Error(rel + ': no closing brace to insert before');
            text = text.slice(0, cut) + edit.new + text.slice(cut);
            return;
        }
        var n = text.split(edit.old).length - 1;
        if (n === 0 && edit.optional) return;
        if (n !== 1) throw new Error(rel + ": this firmware's Home differs from the one Pear knows (" + n + ' matches)');
        text = text.replace(edit.old, function () { return edit.new; });
    });
    return text;
}

function qmlFiles(src, out) {
    var spec = JSON.parse(src['installer/patches.json'].toString('utf8'));
    var config = fs.readFileSync(DIR + '/config.json', 'utf8');
    var photos = '{"count": 0, "accents": ["#e9a77f"]}';
    try {
        var w = JSON.parse(fs.readFileSync(DIR + '/wallpapers/index.json', 'utf8'));
        photos = JSON.stringify({ count: w.count, accents: w.accents });
    } catch (e) { /* the landscape alone */ }
    // LG's own files, from under Pear's mounts
    child.execFileSync(DIR + '/pearwebos', ['unmount']);
    Object.keys(spec.patches).forEach(function (rel) {
        put(out + '/files/' + rel, patch(spec, rel, fs.readFileSync(spec.app + '/' + rel, 'utf8')));
    });
    Object.keys(spec.pear_files).forEach(function (slot) {
        if (!fs.existsSync(spec.app + '/' + slot)) throw new Error(slot + ': not on this TV');
        var text = src['qml/' + spec.pear_files[slot]].toString('utf8')
            .split('@CONFIG@').join(config.trim()).split('@PHOTOS@').join(photos);
        put(out + '/files/' + slot, text);
    });
}

// ---- Pear's app (app mode): web/ as an .ipk, as installer/app.py packs it ----

function tarEntry(name, data) {
    var h = Buffer.alloc(512);
    var w = function (s, o, n) { h.write(s, o, n, 'utf8'); };
    var octal = function (v, n) { return ('00000000000' + v.toString(8)).slice(-(n - 1)) + '\0'; };
    w(name, 0, 100);
    w(octal(data ? 0x1a4 : 0x1ed, 8), 100);   // 644 or 755
    w(octal(0, 8), 108);
    w(octal(0, 8), 116);
    w(octal(data ? data.length : 0, 12), 124);
    w(octal(Math.floor(Date.now() / 1000), 12), 136);
    w('        ', 148);
    w(data ? '0' : '5', 156);
    w('ustar\0', 257);
    w('00', 263);
    var sum = 0;
    for (var i = 0; i < 512; i++) sum += h[i];
    w(('000000' + sum.toString(8)).slice(-6) + '\0 ', 148);
    if (!data) return h;
    return Buffer.concat([h, data, Buffer.alloc((512 - data.length % 512) % 512)]);
}

function tgz(entries) {
    return zlib.gzipSync(Buffer.concat(entries.map(function (e) { return tarEntry(e[0], e[1]); })
        .concat([Buffer.alloc(1024)])));
}

function ar(members) {
    var out = [Buffer.from('!<arch>\n')];
    members.forEach(function (m) {
        var pad = function (s, n) { s = String(s); while (s.length < n) s += ' '; return s; };
        out.push(Buffer.from(pad(m[0], 16) + pad(Math.floor(Date.now() / 1000), 12) + pad(0, 6) + pad(0, 6) +
                             pad('100644', 8) + pad(m[1].length, 10) + '`\n'));
        out.push(m[1]);
        if (m[1].length % 2) out.push(Buffer.from('\n'));
    });
    return Buffer.concat(out);
}

function ipk(src, ver) {
    var root = './usr/palm/applications/' + APP_ID, files = [], dirs = {}, size = 0;
    Object.keys(src).sort().forEach(function (p) {
        if (p.indexOf('web/') !== 0 || /\/\./.test(p)) return;
        var data = src[p], rel = p.slice(4);
        if (rel === 'appinfo.json') {
            var info = JSON.parse(data.toString('utf8'));
            info.version = ver;
            data = Buffer.from(JSON.stringify(info, null, 4));
        }
        files.push([root + '/' + rel, data]);
        size += data.length;
        for (var d = (root + '/' + rel).replace(/\/[^/]*$/, ''); d && d !== '.'; d = d.replace(/\/[^/]*$/, '')) dirs[d] = true;
    });
    var control = 'Package: ' + APP_ID + '\nVersion: ' + ver + '\nSection: misc\nPriority: optional\nArchitecture: all\n' +
                  'Installed-Size: ' + (Math.floor(size / 1024) + 1) + '\nMaintainer: PearWebOS\n' +
                  'Description: Pear, an Apple TV style Home\nwebOS-Package-Format-Version: 2\nwebOS-Packager-Version: x.y.x\n';
    return ar([['debian-binary', Buffer.from('2.0\n')],
               ['control.tar.gz', tgz([['./control', Buffer.from(control)]])],
               ['data.tar.gz', tgz(Object.keys(dirs).sort().map(function (d) { return [d, null]; }).concat(files))]]);
}

// ---- the update ----

function swap(from, to) {
    fs.readdirSync(from).forEach(function (n) {
        var a = from + '/' + n, b = to + '/' + n;
        if (fs.statSync(a).isDirectory() && fs.existsSync(b)) swap(a, b);
        else fs.renameSync(a, b);
    });
}

function install(tag) {
    state('updating', 'Downloading ' + tag.replace(/^v/, ''));
    get('https://codeload.github.com/' + REPO + '/tar.gz/refs/tags/' + tag, function (err, gz) {
        if (err) return state('failed', "Couldn't download it (" + err.message + ')');
        try {
            var src = untar(zlib.gunzipSync(gz));
            ['VERSION', 'tv/pearwebos', 'installer/patches.json', 'qml/PearHome.qml'].forEach(function (f) {
                if (!src[f]) throw new Error('the download has no ' + f);
            });
            var ver = src.VERSION.toString('utf8').trim();
            var mode = fs.existsSync(DIR + '/mode') ? fs.readFileSync(DIR + '/mode', 'utf8').trim() : 'qml';
            state('updating', 'Installing ' + ver);

            // everything built in update.new first
            child.execFileSync('rm', ['-rf', STAGE]);
            Object.keys(src).forEach(function (p) {
                if (/^tv\/[^/]+$/.test(p)) put(STAGE + '/' + p.slice(3), src[p], 0x1ed);
                else if (/^icons\/[^/]+\.png$/.test(p)) put(STAGE + '/' + p, src[p]);
            });
            if (mode === 'app') put('/tmp/pearwebos.ipk', ipk(src, ver));
            else qmlFiles(src, STAGE);

            // then in place, each by a rename: a script that's running (this
            // one, homeguard, peard) keeps reading its old copy
            child.execFileSync('rm', ['-rf', DIR + '/files', DIR + '/icons']);
            swap(STAGE, DIR);
            child.execFileSync('rm', ['-rf', STAGE]);
            if (mode === 'app') {
                var out = child.execFileSync(DIR + '/pearwebos', ['install-app', '/tmp/pearwebos.ipk']).toString();
                fs.unlinkSync('/tmp/pearwebos.ipk');
                if (!/installed/.test(out)) throw new Error("the app didn't install");
            }
            // last, so a failed update isn't taken for this version: and what
            // a computer's `pear sync` of this same release takes as current
            fs.writeFileSync(DIR + '/VERSION', ver + '\n');
            fs.writeFileSync(DIR + '/code.sha', 'release-' + ver + '\n');
            state('done', 'Updated to ' + ver);
        } catch (e) {
            child.spawnSync('rm', ['-rf', STAGE]);
            console.error(e.stack || e.message);
            // one line for Settings; the whole of it is in update.log
            var line = String(e.message).split('\n')[0];
            return state('failed', /^Command failed/.test(line) ? "A step didn't work (update.log has it)" : line.slice(0, 120));
        }
        // Home restarts with the new Pear (peard with it)
        child.spawn(DIR + '/pearwebos', ['on'], { detached: true, stdio: 'ignore' }).unref();
    });
}

var cmd = require.main === module ? process.argv[2] : 'none';
if (cmd === 'none') {
    // required by check.py, to test the pieces
} else if (cmd === 'check') {
    latest(function (err, tag) {
        var cur = version();
        console.log(JSON.stringify(err ? { current: cur, error: err.message }
                                       : { current: cur, latest: tag.replace(/^v/, ''), available: newer(tag, cur) }));
    });
} else if (cmd === 'install') {
    if (process.argv[3]) install(process.argv[3]);
    else latest(function (err, tag) {
        if (err) return state('failed', "Couldn't reach GitHub (" + err.message + ')');
        if (!newer(tag, version())) return state('done', 'Already up to date');
        install(tag);
    });
} else {
    console.error('usage: node update.js check | install [vX.Y.Z]');
    process.exit(2);
}

module.exports = { untar: untar, patch: patch, ipk: ipk, newer: newer };
