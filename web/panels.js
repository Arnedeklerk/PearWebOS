/*
 * PearWebOS's app: the glass panel that slides in from the right, for Inputs
 * and Settings, as qml/PearInputs.qml and qml/PearSettings.qml are in LG Home.
 * Rows are {label, value, note, header, dim, ...}; a header row is a section
 * title the focus skips. Back closes, or goes back to Settings from a sub-page.
 */
'use strict';

var panels = (function () {
    var which = '';        // inputs or settings
    var page = 'main';     // settings: main, apps or places
    var rows = [];
    var index = 0;
    var inputs = null;     // what peard last said, for the Inputs panel
    var placeRows = [];
    var confirmLg = false;
    var editing = null;    // what the editor saves to, while it's up

    function onOff(v) { return v ? 'On' : 'Off'; }

    // a newer Pear, from peard (GET /update): asked when Settings opens, and
    // followed while one runs (Home restarts when it's done)
    var upd = null, updTimer = null;

    function canUpdate() { return !!upd && !!upd.available && upd.state !== 'updating'; }

    function updateValue() {
        if (!upd) return 'Checking...';
        if (upd.state === 'updating') return upd.message || 'Updating...';
        if (canUpdate()) return '';
        if (upd.error) return "Couldn't check";
        return 'Up to date';
    }

    function checkUpdate() {
        api('GET', '/update', null, function (u) {
            upd = u || { error: 'offline' };
            clearTimeout(updTimer);
            if (upd.state === 'updating' && which) updTimer = setTimeout(checkUpdate, 2000);
            if (which === 'settings' && page === 'main') build();
        });
    }

    // ---- the rows ----

    function inputRows() {
        if (!inputs) return [{ label: 'Looking for inputs...', dim: true }];
        return inputs.map(function (i) {
            // the port beside a device's name, so you know where it is
            var port = i.port && i.port !== i.label ? i.port : '';
            return { key: 'input', id: i.id, label: i.label, value: i.plugged ? port : 'Nothing connected', dim: !i.plugged };
        });
    }

    function mainRows() {
        var c = home.config, w = c.weather || {}, noTown = w.lat === null || w.lat === undefined;
        var count = home.photos.count || 0;
        return [
            { header: true, label: 'Home' },
            { key: 'name', label: 'Greeting name', value: c.name || 'None' },
            { key: 'clock', label: 'Clock', value: String(c.clock) === '12' ? '12-hour' : '24-hour' },
            { key: 'date', label: 'Date', value: dateStyle().example },
            { key: 'photo', label: 'Show another photo', value: count ? '' : 'Add photos on a computer', dim: !count },
            { key: 'entrance', label: 'Rise in when Home appears', value: onOff(c.entrance !== false) },
            { key: 'quiet', label: 'Quiet after 45 seconds', value: onOff(c.quiet !== false),
              note: 'The dock fades, leaving the photo and clock. Kinder to OLEDs.' },
            { key: 'drift', label: 'Slow photo zoom', value: onOff(c.drift === true),
              note: 'Redraws the whole screen all the time; can stutter on some TVs' },
            { header: true, label: 'Weather' },
            { key: 'town', label: 'Town', value: w.place ? w.place.split(',')[0] : 'Not set' },
            { key: 'weather', label: 'Weather by the date', value: noTown ? '' : onOff(w.on),
              note: noTown ? 'Pick a town first' : '', dim: noTown },
            { key: 'units', label: 'Units', value: w.units === 'f' ? '°F' : '°C' },
            { header: true, label: 'Apps' },
            { key: 'apps', label: 'Apps on Home', value: hiddenApps().length + ' hidden  ›' },
            { header: true, label: 'TV' },
            { key: 'guard', label: 'Never sit on an empty Live TV', value: onOff(c.guard !== false),
              note: 'Opens Home instead. Turn off if you watch Live TV.' },
            { key: 'boot_to_home', label: 'Power on to Home', value: onOff(c.boot_to_home !== false) },
            { key: 'quick_start', label: 'Quick Start+', value: onOff(c.quick_start !== false),
              note: 'Power-off sleeps, so power-on resumes Pear at once' },
            { key: 'no_update_prompt', label: "Hide LG's update prompt", value: onOff(c.no_update_prompt !== false),
              note: 'An LG update can remove root, and Pear with it' },
            { header: true, label: 'PearWebOS ' + (c.version || '') },
            { key: 'update', label: canUpdate() ? 'Update to ' + upd.latest : 'Update Pear', value: updateValue(),
              note: canUpdate() ? 'Downloads it and restarts Home, in about a minute' :
                    upd && upd.state === 'failed' ? "Last try didn't work: " + upd.message : '',
              dim: !canUpdate() },
            { key: 'apply', label: 'Restart Pear', note: 'Re-applies Pear, as setup does.' },
            { key: 'lg', label: confirmLg ? 'Press OK again to switch' : "Use LG's own Home",
              note: 'Pear can be turned back on from a computer: ./pear on' }
        ];
    }

    // every app the TV has, with whether it's on Home
    function appRows() {
        var hidden = hiddenApps(), out = [{ key: 'back', label: '‹  Settings' }, { header: true, label: 'OK shows or hides' }];
        allApps().forEach(function (e) {
            var h = isHidden(e, hidden);
            out.push({ key: 'app', id: e.id, input: !!e.input, label: e.title || e.id, value: h ? 'Hidden' : 'Shown', dim: h });
        });
        return out;
    }

    function build() {
        rows = which === 'inputs' ? inputRows() : page === 'apps' ? appRows() : page === 'places' ? placeRows : mainRows();
        $('heading').textContent = which === 'inputs' ? 'Inputs' : page === 'apps' ? 'Apps on Home' : page === 'places' ? 'Town' : 'Settings';
        var box = $('rows');
        box.innerHTML = '';
        rows.forEach(function (r, i) {
            var el = document.createElement('div');
            el.className = 'prow' + (r.header ? ' header' : '') + (r.dim ? ' dim' : '');
            if (r.header) {
                el.innerHTML = '<div class="plabel"></div>';
                el.firstChild.textContent = r.label;
            } else {
                el.innerHTML = '<div class="pill"><div class="text"><div class="plabel"></div><div class="pnote"></div></div>' +
                               '<div class="pvalue"></div></div>';
                el.querySelector('.plabel').textContent = r.label || '';
                el.querySelector('.pnote').textContent = r.note || '';
                el.querySelector('.pnote').style.display = r.note ? '' : 'none';
                el.querySelector('.pvalue').textContent = r.value || '';
                el.addEventListener('mouseenter', function () { index = i; show(); });
                el.addEventListener('click', function () { index = i; activate(); });
            }
            box.appendChild(el);
        });
        index = Math.max(0, Math.min(index, rows.length - 1));
        if (rows[index] && rows[index].header) step(1);
        show();
    }

    function show() {
        var kids = $('rows').children;
        for (var i = 0; i < kids.length; i++) kids[i].classList.toggle('focused', i === index);
        // keep the focused row in view
        var el = kids[index], body = $('body');
        if (!el) return;
        var top = el.offsetTop, h = body.clientHeight, shift = 0;
        if (top + el.offsetHeight > h - 120) shift = top + el.offsetHeight - (h - 120);
        shift = Math.max(0, Math.min(shift, $('rows').scrollHeight - h));
        $('rows').style.transform = 'translateY(' + -shift + 'px)';
    }

    function step(dir) {
        var i = index + dir;
        while (i >= 0 && i < rows.length && rows[i].header) i += dir;
        if (i >= 0 && i < rows.length) index = i;
    }

    function first() { index = 0; if (rows[0] && rows[0].header) step(1); }

    // ---- open and close ----

    function open(what) {
        which = what;
        page = 'main';
        confirmLg = false;
        stage.classList.add('panel');
        home.focus = 'panel';
        clearTimeout(idleTimer);
        index = 0;
        build();
        first();
        show();
        if (what === 'settings') checkUpdate();
        if (what === 'inputs') api('GET', '/inputs', null, function (l) {
            inputs = l || [];
            if (which === 'inputs') { build(); first(); show(); }
        });
    }

    function close() {
        if (!which) return;
        if (editing) finish(false);
        which = '';
        stage.classList.remove('panel');
        home.focus = 'top';
        showFocus();
        poke();
    }

    // ---- what OK does ----

    function setWeather(changes) {
        var w = {}, k, old = home.config.weather || {};
        for (k in old) w[k] = old[k];
        for (k in changes) w[k] = changes[k];
        save({ weather: w });
    }

    function findPlaces(name) {
        page = 'places';
        placeRows = [{ key: 'back', label: '‹  Settings' }, { label: 'Looking for ' + name + '...', dim: true }];
        build();
        first();
        show();
        api('GET', '/places?name=' + encodeURIComponent(name), null, function (list) {
            var out = [{ key: 'back', label: '‹  Settings' }];
            if (list === null) out.push({ label: "Couldn't look that up (is the TV online?)", dim: true });
            else if (!list.length) out.push({ label: 'No town called ' + name, dim: true });
            else {
                out.push({ header: true, label: 'Which one?' });
                list.forEach(function (p) {
                    out.push({ key: 'place', label: p.place, note: p.region, place: p.place, lat: p.lat, lon: p.lon });
                });
            }
            placeRows = out;
            if (page === 'places') { build(); first(); show(); }
        });
    }

    function activate() {
        var r = rows[index], c = home.config, w = c.weather || {};
        if (!r) return;
        if (r.key !== 'lg') confirmLg = false;
        switch (r.key) {
        case 'input': api('POST', '/launch', { id: r.id }, null); close(); return;
        case 'name':
            edit('Greeting name', c.name || '', 'OK saves, Back cancels. Leave it empty for just "Good evening".',
                 function (text) { save({ name: text }); });
            return;
        case 'town':
            edit('Town for the weather', '', 'Type the town, then OK to look it up.',
                 function (text) { if (text) findPlaces(text); });
            return;
        case 'place': setWeather({ place: r.place, lat: r.lat, lon: r.lon, on: true }); page = 'main'; first(); break;
        case 'clock': save({ clock: String(c.clock) === '12' ? '24' : '12' }); break;
        case 'date':
            var ks = DATE_STYLES.map(function (d) { return d.key; });
            save({ date: ks[(ks.indexOf(dateStyle().key) + 1) % ks.length] });
            break;
        case 'photo': if (home.photos.count) pickWallpaper(); break;
        case 'entrance': save({ entrance: c.entrance === false }); break;
        case 'quiet': save({ quiet: c.quiet === false }); break;
        case 'drift': save({ drift: c.drift !== true }); break;
        case 'weather': if (w.lat !== null && w.lat !== undefined) setWeather({ on: !w.on }); break;
        case 'units': setWeather({ units: w.units === 'f' ? 'c' : 'f' }); break;
        case 'apps': page = 'apps'; build(); first(); break;
        case 'back': page = 'main'; build(); first(); break;
        case 'app':
            if (r.input) {
                // inputs are off Home by default, so what's kept is the shown ones
                var shown = (c.inputs || []).slice(), was = shown.indexOf(r.id);
                if (was > -1) shown.splice(was, 1); else shown.push(r.id);
                save({ inputs: shown });
                break;
            }
            var list = hiddenApps().filter(function (id) {
                return home.inputTiles.every(function (t) { return t.id !== id; });
            });
            var at = list.indexOf(r.id);
            if (at > -1) list.splice(at, 1); else list.push(r.id);
            save({ hidden: list });
            break;
        case 'guard': save({ guard: c.guard === false }); break;
        case 'boot_to_home': save({ boot_to_home: c.boot_to_home === false }); break;
        case 'quick_start': save({ quick_start: c.quick_start === false }); break;
        case 'no_update_prompt': save({ no_update_prompt: c.no_update_prompt === false }); break;
        case 'update':
            if (!canUpdate()) break;
            api('POST', '/update', {}, null);
            upd = { current: upd.current, latest: upd.latest, state: 'updating', message: 'Starting...' };
            clearTimeout(updTimer);
            updTimer = setTimeout(checkUpdate, 2000);
            break;
        case 'apply': api('POST', '/apply', {}, null); close(); return;
        case 'lg':
            if (!confirmLg) { confirmLg = true; break; }
            api('POST', '/lg-home', {}, null);
            close();
            return;
        }
        build();
        show();
    }

    // ---- a line of text, typed with the TV's on-screen keyboard ----

    function edit(label, text, note, done) {
        editing = done;
        $('editorLabel').textContent = label;
        $('editorNote').textContent = note;
        var f = $('field');
        f.value = text;
        stage.classList.add('editing');
        f.focus();
    }

    function finish(keep) {
        var done = editing, f = $('field');
        editing = null;
        f.blur();
        stage.classList.remove('editing');
        if (keep && done) done(f.value.trim());
    }

    // ---- the remote ----

    function key(ev) {
        var k = ev.keyCode;
        if (editing) {
            if (k === KEY.ok) { ev.preventDefault(); finish(true); }
            else if (k === KEY.back || k === KEY.escape) { ev.preventDefault(); finish(false); }
            return;
        }
        ev.preventDefault();
        if (k === KEY.back || k === KEY.escape) {
            // Back on a sub-page goes back to Settings, not out
            if (which === 'settings' && page !== 'main') { page = 'main'; build(); first(); show(); }
            else close();
            return;
        }
        if (k === KEY.up) step(-1);
        else if (k === KEY.down) step(1);
        else if (k === KEY.left) return close();
        else if (k === KEY.ok) return activate();
        show();
    }

    $('dim').addEventListener('click', close);

    return {
        open: open,
        close: close,
        key: key,
        // the lists follow what's saved
        configChanged: function () { if (which === 'settings' && page !== 'places') build(); },
        appsChanged: function () { if (which === 'settings' && page === 'apps') build(); }
    };
})();
