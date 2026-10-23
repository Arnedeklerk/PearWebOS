// peard: PearWebOS's helper on the TV.
//
// Pear's Home is QML inside LG Home and can't write files or run commands,
// so it asks this instead, over HTTP on 127.0.0.1 only:
//
//   GET  /config              settings (config.json, with defaults)
//   POST /config              change some; writes config.json and pear.conf,
//                             and re-applies the TV settings when those change
//   GET  /wallpapers          {count, accents} for wallpapers/0..count.jpg
//   GET  /weather             cached; refetched from Open-Meteo after 30 min
//   GET  /places?name=...     towns by that name, for the weather (Open-Meteo)
//   GET  /inputs              Live TV and the HDMI ports, from the TV, with
//                             what's plugged in where it says (devices.js)
//   POST /launch {id}         open an app or input
//   POST /apply               restart Home with Pear (picks up new QML)
//   POST /lg-home             back to LG's own Home (`pearwebos off`)
//
// Node 8 (what webOS 6 has): no optional chaining, no fetch.
'use strict';

var http = require('http');
var https = require('https');
var fs = require('fs');
var path = require('path');
var child = require('child_process');
var devices = require('./devices');

var DIR = '/var/lib/pearwebos';
var PORT = 47321;
var LS = DIR + '/luna-send-n';
var CONFIG = DIR + '/config.json';
var VERSION = (function () { try { return fs.readFileSync(DIR + '/VERSION', 'utf8').trim(); } catch (e) { return '?'; } })();

var DEFAULTS = {
    name: '', clock: '24', date: 'intl',
    entrance: true, quiet: true, drift: false,
    hidden: null,                // null: Pear's own list of LG promo apps
    inputs: [],                  // inputs shown as tiles (off unless picked)
    weather: { on: false, place: '', lat: null, lon: null, units: 'c' },
    guard: true, boot_to_home: true, quick_start: true, no_update_prompt: true
};
// settings the TV itself applies, through pear.conf and `pearwebos settings`
var TV_KEYS = ['guard', 'boot_to_home', 'quick_start', 'no_update_prompt'];

function readJson(file, fallback) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { return fallback; }
}

function config() {
    var c = readJson(CONFIG, {});
    var out = JSON.parse(JSON.stringify(DEFAULTS));
    Object.keys(c).forEach(function (k) { out[k] = c[k]; });
    out.version = VERSION;
    return out;
}

function writeConfig(c) {
    delete c.version;
    // `pear sync` on the PC keeps settings changed here since its last sync
    c.changed_at = Date.now();
    fs.writeFileSync(CONFIG + '.tmp', JSON.stringify(c, null, 2));
    fs.renameSync(CONFIG + '.tmp', CONFIG);
    fs.writeFileSync(DIR + '/pear.conf', TV_KEYS.map(function (k) {
        return k.toUpperCase() + '=' + (c[k] ? 1 : 0);
    }).join('\n') + '\n');
}

function luna(uri, payload, cb) {
    child.execFile(LS, ['-n', '1', uri, JSON.stringify(payload || {})], { timeout: 15000 }, function (err, out) {
        var reply = null;
        try { reply = JSON.parse(out); } catch (e) { /* not JSON */ }
        cb(reply);
    });
}

// in the background: these restart Home, which is who is asking
function detached(args) {
    child.spawn(DIR + '/pearwebos', args, { detached: true, stdio: 'ignore' }).unref();
}

// ---- weather ----

var weather = { at: 0, data: null };
var WEATHER_WORDS = [
    [[0], 'Clear'], [[1], 'Mostly clear'], [[2], 'Partly cloudy'], [[3], 'Cloudy'],
    [[45, 48], 'Fog'], [[51, 53, 55, 56, 57], 'Drizzle'], [[61, 63, 66, 80, 81], 'Rain'],
    [[65, 67, 82], 'Heavy rain'], [[71, 73, 75, 77, 85, 86], 'Snow'], [[95, 96, 99], 'Thunder']
];

function words(code) {
    for (var i = 0; i < WEATHER_WORDS.length; i++)
        if (WEATHER_WORDS[i][0].indexOf(code) > -1) return WEATHER_WORDS[i][1];
    return '';
}

function getWeather(cb) {
    var w = config().weather || {};
    if (!w.on || w.lat === null || w.lon === null) return cb(null);
    if (weather.data && Date.now() - weather.at < 30 * 60 * 1000) return cb(weather.data);
    var url = 'https://api.open-meteo.com/v1/forecast?latitude=' + w.lat + '&longitude=' + w.lon +
              '&current_weather=true' + (w.units === 'f' ? '&temperature_unit=fahrenheit' : '');
    https.get(url, function (res) {
        var body = '';
        res.on('data', function (d) { body += d; });
        res.on('end', function () {
            try {
                var cw = JSON.parse(body).current_weather;
                weather = { at: Date.now(), data: {
                    temp: Math.round(cw.temperature), units: w.units === 'f' ? 'F' : 'C',
                    words: words(cw.weathercode), day: cw.is_day === 1, place: w.place
                } };
            } catch (e) { /* keep the last reading */ }
            cb(weather.data);
        });
    }).on('error', function () { cb(weather.data); });
}

function places(name, cb) {
    var url = 'https://geocoding-api.open-meteo.com/v1/search?count=6&name=' + encodeURIComponent(name);
    https.get(url, function (res) {
        var body = '';
        res.on('data', function (d) { body += d; });
        res.on('end', function () {
            var out = [];
            try {
                (JSON.parse(body).results || []).forEach(function (r) {
                    out.push({
                        place: [r.name, r.country].filter(Boolean).join(', '),
                        // the county or state, to tell the Cambridges apart
                        region: r.admin1 || '',
                        lat: Math.round(r.latitude * 1000) / 1000,
                        lon: Math.round(r.longitude * 1000) / 1000
                    });
                });
            } catch (e) { /* none */ }
            cb(out);
        });
    }).on('error', function () { cb(null); });
}

// ---- inputs ----

function inputs(cb) {
    luna('luna://com.webos.service.eim/getAllInputStatus', {}, function (r) {
        var list = [{ id: 'com.webos.app.livetv', label: 'Live TV', plugged: true }];
        ((r && r.devices) || []).forEach(function (d) {
            if (!/^HDMI|^AV|^COMP/.test(d.id || '')) return;
            var what = devices.describe(d);
            var port = d.id.replace(/_.*/, '') + ' ' + d.port;
            list.push({
                id: d.appId, port: port, plugged: !!d.hdmiPlugIn, kind: what.kind,
                // a name you gave it in the TV's settings, else what the device says
                label: (d.modified && d.label) || what.name || d.label || port
            });
        });
        cb(list);
    });
}

// ---- HTTP ----

function send(res, code, obj) {
    res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(obj));
}

function body(req, cb) {
    var b = '';
    req.on('data', function (d) { b += d; if (b.length > 65536) req.destroy(); });
    req.on('end', function () { try { cb(JSON.parse(b || '{}')); } catch (e) { cb(null); } });
}

http.createServer(function (req, res) {
    var url = req.url.split('?')[0];
    if (req.method === 'GET' && url === '/config') return send(res, 200, config());
    if (req.method === 'GET' && url === '/wallpapers')
        return send(res, 200, readJson(DIR + '/wallpapers/index.json', { count: 0, accents: ['#e9a77f'] }));
    if (req.method === 'GET' && url === '/weather') return getWeather(function (w) { send(res, 200, w || {}); });
    if (req.method === 'GET' && url === '/inputs') return inputs(function (l) { send(res, 200, l); });
    if (req.method === 'GET' && url === '/places') {
        var name = decodeURIComponent((req.url.split('name=')[1] || '').split('&')[0]).trim();
        return places(name, function (l) { send(res, l ? 200 : 502, l || { error: 'offline' }); });
    }
    if (req.method !== 'POST') return send(res, 404, { error: 'not found' });

    body(req, function (b) {
        if (b === null) return send(res, 400, { error: 'bad JSON' });
        if (url === '/config') {
            var c = config(), tvChanged = false;
            Object.keys(b).forEach(function (k) {
                if (!(k in DEFAULTS)) return;
                if (TV_KEYS.indexOf(k) > -1 && c[k] !== b[k]) tvChanged = true;
                c[k] = b[k];
            });
            if ('weather' in b) weather = { at: 0, data: null };
            writeConfig(c);
            if (tvChanged) detached(['settings']);
            return send(res, 200, config());
        }
        if (url === '/launch' && typeof b.id === 'string')
            return luna('luna://com.webos.applicationManager/launch', { id: b.id }, function (r) {
                send(res, 200, { ok: !!(r && r.returnValue) });
            });
        if (url === '/apply') { send(res, 200, { ok: true }); return detached(['on']); }
        if (url === '/lg-home') { send(res, 200, { ok: true }); return detached(['off']); }
        send(res, 404, { error: 'not found' });
    });
}).listen(PORT, '127.0.0.1');
