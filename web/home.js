/*
 * PearWebOS's app: Home. The greeting, clock and photo, the first six apps
 * in a dock and the rest one press down, as qml/PearHome.qml does inside LG
 * Home. Apps, settings, photos and inputs come from peard; panels.js has the
 * Inputs and Settings panels.
 *
 * Chromium 79 and up (webOS 6), so no optional chaining.
 */
'use strict';

// ?peard=http://host:port, to try it in a desktop browser against a peard
// started with PEARD_DEV=1
var PEARD = (/[?&]peard=([^&]+)/.exec(location.search) || [0, 'http://127.0.0.1:47321'])[1].replace(/%3A/gi, ':');

var KEY = { left: 37, up: 38, right: 39, down: 40, ok: 13, back: 461, backspace: 8, escape: 27 };

var COLUMNS = 6, TILE_W = 262, GAP = 38, CELL_W = TILE_W + GAP, CELL_H = 158 + 96;
var QUIET_AFTER = 45 * 1000, WALLPAPER_AFTER = 15 * 60 * 1000;

var $ = function (id) { return document.getElementById(id); };
var stage = $('stage');

var home = {
    config: {},
    photos: { count: 0, accents: ['#e9a77f'] },
    weather: null,
    apps: [],          // LG's, from peard, in Home's order
    inputTiles: [],
    dock: [],
    drawer: [],
    focus: 'dock',     // dock, grid, top, panel or asleep
    dockIndex: 0,
    gridIndex: 0,
    topIndex: 0,
    quiet: false,
    wokeAt: 0,
    hiddenAt: 0,
    wallpaper: 0
};

// ---- peard ----

function api(method, path, data, done) {
    var x = new XMLHttpRequest();
    x.onreadystatechange = function () {
        if (x.readyState !== 4) return;
        var reply = null;
        try { reply = JSON.parse(x.responseText); } catch (e) { /* not JSON */ }
        if (done) done(x.status === 200 ? reply : null);
    };
    x.open(method, PEARD + path);
    if (data) { x.setRequestHeader('Content-Type', 'application/json'); x.setRequestHeader('X-Pear', '1'); }
    x.send(data ? JSON.stringify(data) : null);
}

function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

// settings, photos, weather, apps and inputs; whatever changed is redrawn.
// A failed request keeps what's shown: peard may not be up yet (at boot, or
// just after Restart Pear), so it tries again shortly
var retry = null;

function again() {
    clearTimeout(retry);
    retry = setTimeout(refresh, 3000);
}

function refresh() {
    api('GET', '/config', null, function (c) {
        if (!c) return again();
        if (!same(c, home.config)) { home.config = c; changed(); }
    });
    api('GET', '/wallpapers', null, function (w) {
        if (!w || !w.accents || same(w, home.photos)) return;
        home.photos = w;
        if (home.wallpaper === 0 || home.wallpaper > w.count) pickWallpaper(); else showHeader();
    });
    api('GET', '/weather', null, function (w) {
        if (!w) return;
        w = w.temp !== undefined ? w : null;
        if (!same(w, home.weather)) { home.weather = w; showHeader(); }
    });
    api('GET', '/apps', null, function (l) { if (l && !same(l, home.apps)) { home.apps = l; rebuild(); } });
    api('GET', '/inputs', null, function (l) {
        if (!l) return;
        var tiles = [];
        for (var i = 1; i < l.length; i++)   // [0] is Live TV, already a tile
            tiles.push({ id: l[i].id, title: l[i].label, iconColor: KIND_COLOURS[l[i].kind] || '#1d2433',
                         input: true, icon: '/icons/' + (l[i].kind || 'input') + '.png' });
        if (!same(tiles, home.inputTiles)) { home.inputTiles = tiles; rebuild(); }
    });
}

function save(changes) {
    api('POST', '/config', changes, function (c) { if (c) { home.config = c; changed(); } });
}

function launch(e) {
    if (e) api('POST', '/launch', { id: e.id }, null);
}

// ---- what's on Home ----

// LG promotions and homebrew background tools: off the tiles unless the
// settings say otherwise
var DEFAULT_HIDDEN = [
    'lgchannels.uk', 'com.webos.app.lgchannels', 'com.webos.app.homeconnect',
    'com.webos.app.sportsteamsettings', 'com.lgshop.app35', 'com.lgtravel.app',
    'epoxyaisports', 'com.lgtvod.app', 'webos.day', 'com.twin.app.audiochannel',
    'com.twin.app.gamingportal', 'amazon.alexa.view', 'com.pirate.refresh',
    'org.webosbrew.inputhook', 'org.aabytt.webos.custom-screensaver-aerial',
    'com.amazoff.patcher'
];
var LIVE_TV = { id: 'com.webos.app.livetv', title: 'Live TV', iconColor: '#1d2433', icon: '/icons/livetv.png' };
// an input tile's colour, by what's plugged in (tv/devices.js)
var KIND_COLOURS = {
    switch: '#e60012', playstation: '#0058c7', xbox: '#107c10', appletv: '#2c2c2e',
    stick: '#6f2da8', streamer: '#0f766e', pc: '#374151', soundbar: '#b45309',
    disc: '#0e7490', settop: '#9d174d', gamepad: '#4b5563'
};

function hiddenApps() {
    var c = home.config;
    var hidden = (c.hidden || DEFAULT_HIDDEN.concat(c.guard !== false ? [LIVE_TV.id] : [])).slice();
    var shown = c.inputs || [];
    home.inputTiles.forEach(function (t) { if (shown.indexOf(t.id) < 0) hidden.push(t.id); });
    return hidden;
}

function isHidden(e, hidden) { return hidden.indexOf(e.id) > -1; }

// every app Home can show, in order: Live TV, the inputs, then LG's
function allApps() {
    return [LIVE_TV].concat(home.inputTiles, home.apps);
}

function tileEl(e, i) {
    var t = document.createElement('div');
    t.className = 'tile';
    t.style.left = (i % COLUMNS) * CELL_W + 'px';
    t.style.top = Math.floor(i / COLUMNS) * CELL_H + 'px';
    var card = document.createElement('div');
    card.className = 'card';
    card.style.background = e.iconColor || '#2b2a40';
    var img = document.createElement('img');
    img.src = PEARD + e.icon;
    card.appendChild(img);
    var name = document.createElement('div');
    name.className = 'name';
    name.textContent = e.title || '';
    t.appendChild(card);
    t.appendChild(name);
    return t;
}

function rebuild() {
    var hidden = hiddenApps(), dock = [], rest = [];
    allApps().forEach(function (e) {
        if (isHidden(e, hidden)) return;
        if (dock.length < COLUMNS) dock.push(e); else rest.push(e);
    });
    home.dock = dock;
    home.drawer = rest;
    home.dockIndex = Math.max(0, Math.min(home.dockIndex, dock.length - 1));
    home.gridIndex = Math.max(0, Math.min(home.gridIndex, rest.length - 1));
    [['dockRow', dock], ['gridRows', rest]].forEach(function (p) {
        var row = $(p[0]);
        row.innerHTML = '';
        p[1].forEach(function (e, i) {
            var t = tileEl(e, i);
            hover(t, p[0] === 'dockRow' ? 'dock' : 'grid', i, e);
            row.appendChild(t);
        });
    });
    stage.classList.toggle('noDrawer', !rest.length);
    if (home.drawerOpen && !rest.length) closeDrawer();
    showFocus();
    if (window.panels) panels.appsChanged();
}

// the pointer: hover picks a tile, a click opens it
function hover(el, where, i, e) {
    el.addEventListener('mouseenter', function () {
        poke();
        if (home.focus === 'panel' || (where === 'dock' && home.drawerOpen) || (where === 'grid' && !home.drawerOpen)) return;
        home.focus = where;
        if (where === 'dock') home.dockIndex = i; else home.gridIndex = i;
        showFocus();
    });
    el.addEventListener('click', function () {
        if (home.focus !== 'panel') launch(e);
    });
}

function showFocus() {
    var f = home.focus;
    [['dockRow', 'dock', home.dockIndex], ['gridRows', 'grid', home.gridIndex]].forEach(function (p) {
        var kids = $(p[0]).children;
        for (var i = 0; i < kids.length; i++) kids[i].classList.toggle('focused', f === p[1] && i === p[2]);
    });
    stage.classList.toggle('top', f === 'top');
    var buttons = document.querySelectorAll('#topbar .button');
    for (var i = 0; i < buttons.length; i++) buttons[i].classList.toggle('focused', f === 'top' && i === home.topIndex);
    $('topLabel').textContent = home.topIndex ? 'Settings' : 'Inputs';
    // keep the focused row of the drawer in view
    var row = Math.floor(home.gridIndex / COLUMNS), rows = Math.ceil(home.drawer.length / COLUMNS);
    var visible = Math.floor((734 - 36) / CELL_H);
    var first = Math.max(0, Math.min(row - visible + 1, rows - visible));
    if (row < first) first = row;
    $('gridRows').style.transform = 'translate(20px, ' + (36 - Math.max(0, first) * CELL_H) + 'px)';
}

// ---- the greeting, date and clock ----

var DATE_STYLES = [
    { key: 'intl', example: 'Tuesday 20 October' },
    { key: 'us', example: 'Tuesday, October 20' },
    { key: 'short', example: 'Tue, Oct 20' },
    { key: 'ordinal', example: 'Tue, Oct 20th' }
];
var DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
              'October', 'November', 'December'];

function dateStyle() {
    for (var i = 0; i < DATE_STYLES.length; i++) if (DATE_STYLES[i].key === home.config.date) return DATE_STYLES[i];
    return DATE_STYLES[0];
}

function dateText(now) {
    var day = DAYS[now.getDay()], month = MONTHS[now.getMonth()], d = now.getDate();
    switch (dateStyle().key) {
    case 'us': return day + ', ' + month + ' ' + d;
    case 'short': return day.slice(0, 3) + ', ' + month.slice(0, 3) + ' ' + d;
    case 'ordinal':
        return day.slice(0, 3) + ', ' + month.slice(0, 3) + ' ' + d +
               (d >= 11 && d <= 13 ? 'th' : ['th', 'st', 'nd', 'rd'][d % 10] || 'th');
    default: return day + ' ' + d + ' ' + month;
    }
}

function twelveHour() { return String(home.config.clock) === '12'; }

function clockText(now) {
    var m = now.getMinutes(), h = now.getHours();
    if (!twelveHour()) return (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
    return (h % 12 || 12) + ':' + (m < 10 ? '0' : '') + m;
}

function greeting(now) {
    var h = now.getHours(), name = home.config.name || '';
    var part = h < 5 ? 'evening' : h < 12 ? 'morning' : h < 18 ? 'afternoon' : 'evening';
    return 'Good ' + part + (name ? ', ' + name : '');
}

// where a line's baseline is, from the zero-size mark on it
function baseline(el) {
    var mark = el.querySelector('.base');
    return el.offsetTop + mark.offsetTop;
}

// LG Smart UI Light: cap height 0.672 em, digits 0.682 em (measured on the TV)
var CAP = 0.672, DIGIT = 0.682;

function showHeader() {
    var now = new Date(), w = home.weather;
    var accents = home.photos.accents || ['#e9a77f'];
    stage.classList.toggle('twelve', twelveHour());

    var g = $('greeting');
    g.textContent = greeting(now);
    // room up to the clock; a long name shrinks the line to fit, then is cut short
    var room = 1920 - 110 - 110 - 480 - (twelveHour() ? 90 : 0);
    g.style.width = 'auto';
    g.style.fontSize = '78px';
    var size = Math.max(52, Math.min(78, Math.floor(78 * room / Math.max(1, g.scrollWidth))));
    g.style.fontSize = size + 'px';
    g.style.width = room + 'px';

    var date = $('date');
    $('dateText').textContent = dateText(now) + (w ? '   ·   ' + w.temp + '°  ' + w.words : '');
    $('dateText').style.whiteSpace = 'pre';
    date.style.color = accents[home.wallpaper] || accents[0];
    date.style.top = (g.offsetTop + g.offsetHeight + 10) + 'px';

    // the clock spans the pair: its digits' top level with the greeting's
    // capitals, their foot on the date's baseline
    var dateBase = baseline(date);
    var capTop = baselineOf(g, size) - CAP * size;
    var clock = $('clock'), ampm = $('ampm');
    $('clockText').textContent = clockText(now);
    clock.style.fontSize = Math.round((dateBase - capTop) / DIGIT) + 'px';
    clock.style.right = twelveHour() ? (110 + ampm.offsetWidth + 14) + 'px' : '110px';
    clock.style.top = '0px';
    clock.style.top = (dateBase - baseline(clock)) + 'px';
    ampm.textContent = now.getHours() < 12 ? 'AM' : 'PM';
    ampm.style.top = (dateBase - ampm.offsetHeight * 0.8) + 'px';
}

// the greeting's baseline (it clips, so it measures with a copy)
function baselineOf(el, size) {
    var probe = document.createElement('div');
    probe.style.cssText = 'position:absolute;visibility:hidden;font-weight:300;white-space:nowrap;font-size:' +
                          size + 'px;left:0;top:' + el.offsetTop + 'px';
    probe.innerHTML = 'Hg<i class="base"></i>';
    el.parentNode.appendChild(probe);
    var b = probe.offsetTop + probe.lastChild.offsetTop;
    probe.parentNode.removeChild(probe);
    return b;
}

// ---- the photo ----

var front = null;

function showPhoto() {
    var src = PEARD + '/wallpapers/' + home.wallpaper + '.jpg';
    var a = $('photoA'), b = $('photoB');
    if (front && front.getAttribute('src') === src) return;
    var next = front === a ? b : a, old = front;
    next.onload = function () {
        next.classList.add('front');
        if (old) old.classList.remove('front');
        front = next;
    };
    // a missing photo falls back to the dusk landscape (0.jpg)
    next.onerror = function () { if (home.wallpaper > 0) { home.wallpaper = 0; showPhoto(); showHeader(); } };
    next.src = src;
}

function pickWallpaper() {
    var count = home.photos.count || 0, n;
    if (count < 1) n = 0;
    else do { n = 1 + Math.floor(Math.random() * count); } while (count > 1 && n === home.wallpaper);
    home.wallpaper = n;
    showPhoto();
    showHeader();
}

// ---- settings changed ----

function changed() {
    $('backdrop').classList.toggle('drift', home.config.drift === true);
    rebuild();
    showHeader();
    if (window.panels) panels.configChanged();
}

// ---- the drawer ----

function openDrawer() {
    if (!home.drawer.length) return;
    home.drawerOpen = true;
    stage.classList.add('drawer');
    home.focus = 'grid';
    home.gridIndex = Math.min(home.dockIndex, home.drawer.length - 1);
    showFocus();
    poke();
}

function closeDrawer() {
    home.drawerOpen = false;
    stage.classList.remove('drawer');
    home.focus = 'dock';
    home.dockIndex = Math.min(home.gridIndex % COLUMNS, home.dock.length - 1);
    showFocus();
    poke();
}

// ---- bump: the focused tile nudges when there's nowhere to go ----

function bump(dx, dy) {
    poke();
    var t = document.querySelector('.tile.focused .card');
    if (!t) return;
    t.style.transition = 'transform 60ms ease-out';
    t.style.transform = 'translate(' + dx * 12 + 'px,' + dy * 12 + 'px) scale(1.14)';
    setTimeout(function () {
        t.style.transition = 'transform 200ms cubic-bezier(0.34, 1.56, 0.64, 1)';
        t.style.transform = '';
        setTimeout(function () { t.style.transition = ''; }, 220);
    }, 60);
}

// ---- quiet: untouched a while, only the photo, greeting and clock ----

var idleTimer = null;

function poke() {
    if (home.quiet) {
        home.quiet = false;
        home.wokeAt = Date.now();
        stage.classList.remove('quiet');
        home.focus = home.drawerOpen ? 'grid' : 'dock';
        showFocus();
    }
    clearTimeout(idleTimer);
    if (home.config.quiet !== false && !home.drawerOpen && home.focus !== 'panel' && !document.hidden)
        idleTimer = setTimeout(function () {
            home.quiet = true;
            stage.classList.add('quiet');
            // the first press only wakes Home
            home.focus = 'asleep';
            showFocus();
        }, QUIET_AFTER);
}

// ---- the remote ----

function onKey(ev) {
    var k = ev.keyCode;
    if (home.focus === 'panel') return panels.key(ev);
    ev.preventDefault();
    if (home.quiet || home.focus === 'asleep') { poke(); return; }
    // the OK that woke Home from quiet is not also a launch
    if (k === KEY.ok && Date.now() - home.wokeAt < 600) return;
    poke();
    var f = home.focus;
    if (f === 'top') {
        if (k === KEY.left && home.topIndex > 0) home.topIndex--;
        else if (k === KEY.right && home.topIndex < 1) home.topIndex++;
        else if (k === KEY.down) home.focus = 'dock';
        else if (k === KEY.ok) panels.open(home.topIndex ? 'settings' : 'inputs');
    } else if (f === 'dock') {
        if (k === KEY.left) { if (home.dockIndex > 0) home.dockIndex--; else bump(-1, 0); }
        else if (k === KEY.right) { if (home.dockIndex < home.dock.length - 1) home.dockIndex++; else bump(1, 0); }
        else if (k === KEY.down) { if (home.drawer.length) openDrawer(); else bump(0, 1); }
        else if (k === KEY.up) home.focus = 'top';
        else if (k === KEY.ok) launch(home.dock[home.dockIndex]);
    } else if (f === 'grid') {
        var i = home.gridIndex, n = home.drawer.length;
        if (k === KEY.left) { if (i % COLUMNS > 0) home.gridIndex--; else bump(-1, 0); }
        else if (k === KEY.right) { if (i % COLUMNS < COLUMNS - 1 && i < n - 1) home.gridIndex++; else bump(1, 0); }
        else if (k === KEY.up) { if (i < COLUMNS) return closeDrawer(); home.gridIndex -= COLUMNS; }
        else if (k === KEY.down) {
            // a short last row: Down from a column it doesn't reach lands on its last app
            if (i + COLUMNS < n) home.gridIndex += COLUMNS;
            else if (Math.floor(i / COLUMNS) < Math.floor((n - 1) / COLUMNS)) home.gridIndex = n - 1;
            else bump(0, 1);
        }
        else if (k === KEY.back) return closeDrawer();
        else if (k === KEY.ok) launch(home.drawer[home.gridIndex]);
    }
    showFocus();
}

document.addEventListener('keydown', onKey);

// the Magic Remote's wheel steps through the rows
var wheelTravel = 0;
document.addEventListener('wheel', function (ev) {
    poke();
    if (home.focus === 'panel') return;
    wheelTravel += ev.deltaY;
    while (wheelTravel >= 100) {
        wheelTravel -= 100;
        if (!home.drawerOpen) openDrawer();
        else if (home.gridIndex + COLUMNS < home.drawer.length) home.gridIndex += COLUMNS;
        showFocus();
    }
    while (wheelTravel <= -100) {
        wheelTravel += 100;
        if (home.drawerOpen && home.gridIndex < COLUMNS) closeDrawer();
        else if (home.drawerOpen) home.gridIndex -= COLUMNS;
        showFocus();
    }
});
document.addEventListener('mousemove', poke);
$('allApps').addEventListener('click', openDrawer);
Array.prototype.forEach.call(document.querySelectorAll('#topbar .button'), function (b, i) {
    b.addEventListener('mouseenter', function () { if (home.focus !== 'panel') { home.focus = 'top'; home.topIndex = i; showFocus(); } });
    b.addEventListener('click', function () { panels.open(b.getAttribute('data-key')); });
});

// the cog's teeth
(function () {
    var g = document.querySelector('.teeth'), svg = '';
    for (var t = 0; t < 8; t++) svg += '<rect x="-2.8" y="-18.8" width="5.6" height="6.4" transform="rotate(' + (t * 45 + 45) + ')"/>';
    g.innerHTML = svg;
})();

// ---- coming and going ----

// the clock moves on the minute (and checks peard for new settings, photos
// and weather while it's at it)
var clockTimer = null;

function tick() {
    var now = new Date();
    showHeader();
    refresh();
    clearTimeout(clockTimer);
    clockTimer = setTimeout(tick, 60050 - (now.getSeconds() * 1000 + now.getMilliseconds()));
}

// Home came to the front: catch up, maybe a new photo, and rise in
function shown() {
    if (home.hiddenAt && Date.now() - home.hiddenAt > WALLPAPER_AFTER) pickWallpaper();
    home.hiddenAt = 0;
    tick();
    if (home.config.entrance !== false) {
        stage.classList.remove('entered');
        stage.classList.add('entering');
        void stage.offsetWidth;
        stage.classList.remove('entering');
        stage.classList.add('entered');
    }
    poke();
}

function hidden() {
    home.hiddenAt = Date.now();
    clearTimeout(clockTimer);
    clearTimeout(idleTimer);
    if (window.panels) panels.close();
    home.quiet = false;
    stage.classList.remove('quiet');
    if (home.drawerOpen) closeDrawer();
    home.focus = 'dock';
    showFocus();
}

document.addEventListener('visibilitychange', function () { if (document.hidden) hidden(); else shown(); });
// launched again while running: homeguard bringing Pear back over LG's Home.
// The system brings it forward (appinfo has no handlesRelaunch); asking too
// does no harm where it already has
document.addEventListener('webOSRelaunch', function () {
    var sys = window.webOSSystem || window.PalmSystem;
    if (sys && sys.activate) sys.activate();
    shown();
});

function fit() {
    stage.style.transform = 'scale(' + Math.min(innerWidth / 1920, innerHeight / 1080) + ')';
}

window.addEventListener('resize', fit);
fit();
pickWallpaper();
rebuild();
shown();
