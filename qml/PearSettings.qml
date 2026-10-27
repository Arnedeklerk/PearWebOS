/*
 * PearWebOS: Settings, on the TV. Changes are saved through peard and show
 * at once; what needs a computer (the TV's address, photos, where the
 * weather is) says so. Mounted over Main/PromotionBG.qml, which LG Home never
 * loads; Pear uses it as PromotionBG { }.
 */

import QtQuick 2.12

EditTile {

    id: settings

    title: page === "apps" ? "Apps on Home" : page === "places" ? "Town" : "Settings"

    property string page: "main"     // "main", "apps" or "places"
    property bool confirmLg: false   // "Use LG's Home" asks for a second OK

    readonly property var c: home.config
    readonly property var w: c.weather || {}

    function onOff(v) { return v ? "On" : "Off"; }

    // a newer Pear, from peard (GET /update): asked when Settings opens
    property var upd: null
    readonly property bool canUpdate: !!upd && !!upd.available && upd.state !== "updating"

    function updateValue() {
        if (!upd) return "Checking...";
        if (upd.state === "updating") return upd.message || "Updating...";
        if (canUpdate) return "";
        if (upd.error) return "Couldn't check";
        return "Up to date";
    }

    function checkUpdate() {
        home.api("GET", "/update", null, function (u) { settings.upd = u || { error: "offline" }; });
    }

    // while one runs, follow it (Home restarts when it's done)
    Timer {
        interval: 2000
        repeat: true
        running: settings.shown && !!settings.upd && settings.upd.state === "updating"
        onTriggered: settings.checkUpdate()
    }

    readonly property var mainRows: [
        { header: true, label: "Home" },
        { key: "name", label: "Greeting name", value: c.name || "None" },
        { key: "clock", label: "Clock", value: String(c.clock) === "12" ? "12-hour" : "24-hour" },
        { key: "date", label: "Date", value: home.dateStyle.example },
        { key: "photo", label: "Show another photo", value: home.wallpaperCount ? "" : "Add photos on a computer",
          dim: !home.wallpaperCount },
        { key: "entrance", label: "Rise in when Home appears", value: onOff(c.entrance !== false) },
        { key: "quiet", label: "Quiet after 45 seconds", value: onOff(c.quiet !== false),
          note: "The dock fades, leaving the photo and clock. Kinder to OLEDs." },
        { key: "drift", label: "Slow photo zoom", value: onOff(c.drift === true),
          note: "Redraws the whole screen all the time; can stutter on some TVs" },
        { header: true, label: "Weather" },
        { key: "town", label: "Town", value: w.place ? w.place.split(",")[0] : "Not set" },
        { key: "weather", label: "Weather by the date", value: w.lat === null || w.lat === undefined ? "" : onOff(w.on),
          note: w.lat === null || w.lat === undefined ? "Pick a town first" : "",
          dim: w.lat === null || w.lat === undefined },
        { key: "units", label: "Units", value: w.units === "f" ? "°F" : "°C" },
        { header: true, label: "Apps" },
        { key: "apps", label: "Apps on Home", value: (home.hiddenApps.length) + " hidden  ›" },
        { header: true, label: "TV" },
        { key: "guard", label: "Never sit on an empty Live TV", value: onOff(c.guard !== false),
          note: "Opens Home instead. Turn off if you watch Live TV." },
        { key: "boot_to_home", label: "Power on to Home", value: onOff(c.boot_to_home !== false) },
        { key: "quick_start", label: "Quick Start+", value: onOff(c.quick_start !== false),
          note: "Power-off sleeps, so power-on resumes Pear at once" },
        { key: "no_update_prompt", label: "Hide LG's update prompt", value: onOff(c.no_update_prompt !== false),
          note: "An LG update can remove root, and Pear with it" },
        { header: true, label: "PearWebOS " + (c.version || "") },
        { key: "update", label: canUpdate ? "Update to " + upd.latest : "Update Pear", value: updateValue(),
          note: canUpdate ? "Downloads it and restarts Home, in about a minute" :
                upd && upd.state === "failed" ? "Last try didn't work: " + upd.message : "",
          dim: !canUpdate },
        { key: "apply", label: "Restart Pear", note: "Re-applies Pear, as setup does. Home blinks for a moment." },
        { key: "lg", label: confirmLg ? "Press OK again to switch" : "Use LG's own Home",
          note: "Pear can be turned back on from a computer: ./pear on" }
    ]

    // every app the TV has, with whether it's on Home
    property var appRows: []

    function buildApps() {
        var rows = [{ key: "back", label: "‹  Settings" }, { header: true, label: "OK shows or hides" }];
        var all = home.apps();
        for (var i = 0; i < all.length; i++) {
            var e = all[i];
            var hidden = home.hiddenApps.indexOf(e.id) > -1;
            rows.push({ key: "app", id: e.id, input: !!e.input, label: e.title || e.id, value: hidden ? "Hidden" : "Shown", dim: hidden });
        }
        // a toggle rebuilds the list; stay on the row that was toggled
        var at = rowList.currentIndex;
        appRows = rows;
        rowList.currentIndex = Math.max(0, Math.min(at, rows.length - 1));
    }

    // towns matching what was typed, for the weather
    property var placeRows: []

    function findPlaces(name) {
        page = "places";
        placeRows = [{ key: "back", label: "‹  Settings" }, { label: "Looking for " + name + "...", dim: true }];
        first(rowList);
        home.api("GET", "/places?name=" + encodeURIComponent(name), null, function (list) {
            var rows = [{ key: "back", label: "‹  Settings" }];
            if (list === null) rows.push({ label: "Couldn't look that up (is the TV online?)", dim: true });
            else if (!list.length) rows.push({ label: "No town called " + name, dim: true });
            else {
                rows.push({ header: true, label: "Which one?" });
                list.forEach(function (p) {
                    rows.push({ key: "place", label: p.place, note: p.region, place: p.place, lat: p.lat, lon: p.lon });
                });
            }
            placeRows = rows;
            first(rowList);
        });
    }

    readonly property var rows: page === "apps" ? appRows : page === "places" ? placeRows : mainRows

    function show() {
        page = "main";
        confirmLg = false;
        checkUpdate();
        open();
        rowList.forceActiveFocus();
        first(rowList);
    }

    function setWeather(changes) {
        var nw = {};
        for (var k in w) nw[k] = w[k];
        for (k in changes) nw[k] = changes[k];
        home.save({ weather: nw });
    }

    onClosed: page = "main"

    onActivated: {
        var r = rows[index];
        if (!r) return;
        if (r.key !== "lg") confirmLg = false;
        switch (r.key) {
        case "name":
            editor.start("Greeting name", home.config.name || "",
                         "OK saves, Back cancels. Leave it empty for just \"Good evening\".",
                         function (text) { home.save({ name: text }); });
            break;
        case "town":
            editor.start("Town for the weather", "",
                         "Type the town, then OK to look it up.",
                         function (text) { if (text) settings.findPlaces(text); });
            break;
        case "place":
            setWeather({ place: r.place, lat: r.lat, lon: r.lon, on: true });
            page = "main";
            first(rowList);
            break;
        case "clock": home.save({ clock: String(c.clock) === "12" ? "24" : "12" }); break;
        case "date":
            var ks = home.dateStyles.map(function (d) { return d.key; });
            home.save({ date: ks[(ks.indexOf(home.dateStyle.key) + 1) % ks.length] });
            break;
        case "photo": if (home.wallpaperCount) home.pickWallpaper(); break;
        case "entrance": home.save({ entrance: c.entrance === false }); break;
        case "quiet": home.save({ quiet: c.quiet === false }); break;
        case "drift": home.save({ drift: c.drift !== true }); break;
        case "weather": if (w.lat !== null && w.lat !== undefined) setWeather({ on: !w.on }); break;
        case "units": setWeather({ units: w.units === "f" ? "c" : "f" }); break;
        case "apps": page = "apps"; buildApps(); first(rowList); break;
        case "back": page = "main"; first(rowList); break;
        case "app":
            if (r.input) {
                // inputs are off Home by default, so what's kept is the shown ones
                var shown = (home.config.inputs || []).slice();
                var was = shown.indexOf(r.id);
                if (was > -1) shown.splice(was, 1); else shown.push(r.id);
                home.save({ inputs: shown });
                break;
            }
            // inputs are kept apart (config.inputs), so not saved as hidden
            var list = home.hiddenApps.filter(function (id) {
                return !home.inputTiles.some(function (t) { return t.id === id; });
            });
            var at = list.indexOf(r.id);
            if (at > -1) list.splice(at, 1); else list.push(r.id);
            home.save({ hidden: list });
            break;
        case "guard": home.save({ guard: c.guard === false }); break;
        case "boot_to_home": home.save({ boot_to_home: c.boot_to_home === false }); break;
        case "quick_start": home.save({ quick_start: c.quick_start === false }); break;
        case "no_update_prompt": home.save({ no_update_prompt: c.no_update_prompt === false }); break;
        case "update":
            if (!canUpdate) break;
            home.api("POST", "/update", {}, null);
            upd = { current: upd.current, latest: upd.latest, state: "updating", message: "Starting..." };
            break;
        case "apply": home.api("POST", "/apply", {}, null); close(); break;
        case "lg":
            if (!confirmLg) { confirmLg = true; break; }
            home.api("POST", "/lg-home", {}, null);
            close();
            break;
        }
    }

    // the app list follows what's saved
    Connections {
        target: home
        onHiddenAppsChanged: if (settings.page === "apps") settings.buildApps()
        onInputTilesChanged: if (settings.page === "apps") settings.buildApps()
    }

    ListView {
        id: rowList

        anchors.fill: parent
        model: settings.rows
        delegate: settings.row
        keyNavigationEnabled: false
        highlightMoveDuration: 120
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: home.r(120)
        preferredHighlightEnd: height - home.r(120)
        highlight: Item {}
        visible: !editor.visible

        Keys.onPressed: {
            // Back on a sub-page goes back to Settings, not out
            if (event.key === webOS.Key_webOS_Back && settings.page !== "main") {
                settings.page = "main";
                settings.first(rowList);
                event.accepted = true;
                return;
            }
            settings.keys(rowList, event);
        }
    }

    // a line of text, typed with the TV's on-screen keyboard: the greeting
    // name, or a town to look up
    Item {
        id: editor

        property var done: null

        anchors.fill: parent
        visible: false

        function start(label, text, hint, onDone) {
            heading.text = label;
            note.text = hint;
            field.text = text;
            done = onDone;
            visible = true;
            field.forceActiveFocus();
            Qt.inputMethod.show();
        }

        function finish(keep) {
            Qt.inputMethod.hide();
            visible = false;
            rowList.forceActiveFocus();
            if (keep && done) done(field.text.trim());
        }

        Text {
            id: heading
            x: home.r(28)
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: fontManager.smart_Regular.family
            font.pixelSize: home.r(26)
        }

        Rectangle {
            y: home.r(48)
            width: parent.width
            height: home.r(86)
            radius: home.r(22)
            color: "#ffffff"

            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: home.r(28)
                anchors.rightMargin: home.r(28)
                verticalAlignment: TextInput.AlignVCenter
                color: "#14141c"
                font.family: fontManager.smart_Regular.family
                font.pixelSize: home.r(32)
                maximumLength: 40
                Keys.onReturnPressed: editor.finish(true)
                Keys.onEnterPressed: editor.finish(true)
                Keys.onPressed: {
                    if (event.key === webOS.Key_webOS_Back) { editor.finish(false); event.accepted = true; }
                }
            }
        }

        Text {
            id: note
            y: home.r(160)
            x: home.r(28)
            width: parent.width - home.r(56)
            wrapMode: Text.WordWrap
            color: Qt.rgba(1, 1, 1, 0.5)
            font.family: fontManager.smart_Regular.family
            font.pixelSize: home.r(24)
        }
    }
}
