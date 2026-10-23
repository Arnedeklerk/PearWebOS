/*
 * PearWebOS: Settings, on the TV. Changes are saved through peard and show
 * at once; what needs a computer (the TV's address, photos, where the
 * weather is) says so. Mounted over Main/PromotionBG.qml, which LG Home never
 * loads; Pear uses it as PromotionBG { }.
 */

import QtQuick 2.12

EditTile {

    id: settings

    title: page === "apps" ? "Apps on Home" : "Settings"

    property string page: "main"     // "main" or "apps"
    property bool confirmLg: false   // "Use LG's Home" asks for a second OK

    readonly property var c: home.config
    readonly property var w: c.weather || {}

    function onOff(v) { return v ? "On" : "Off"; }

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
        { key: "weather", label: "Weather by the date", value: w.lat === null || w.lat === undefined ? "" : onOff(w.on),
          note: w.place ? w.place : "Set your town with ./pear setup on a computer",
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
        { key: "apply", label: "Restart Pear", note: "Re-applies Pear, as setup does. Home blinks for a moment." },
        { key: "lg", label: confirmLg ? "Press OK again to switch" : "Use LG's own Home",
          note: "Pear can be turned back on from a computer: ./pear on" }
    ]

    // every app the TV has, with whether it's on Home
    property var appRows: []

    function buildApps() {
        var rows = [{ key: "back", label: "‹  Settings" }, { header: true, label: "OK shows or hides" }];
        var src = home.source;
        for (var i = 0; src && i < src.count; i++) {
            var e = src.get(i).entry;
            if (!e || !e.id) continue;
            var hidden = home.hiddenApps.indexOf(e.id) > -1;
            rows.push({ key: "app", id: e.id, label: e.title || e.id, value: hidden ? "Hidden" : "Shown", dim: hidden });
        }
        appRows = rows;
    }

    readonly property var rows: page === "apps" ? appRows : mainRows

    function show() {
        page = "main";
        confirmLg = false;
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
        case "name": nameEditor.start(); break;
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
            var list = home.hiddenApps.slice();
            var at = list.indexOf(r.id);
            if (at > -1) list.splice(at, 1); else list.push(r.id);
            home.save({ hidden: list });
            break;
        case "guard": home.save({ guard: c.guard === false }); break;
        case "boot_to_home": home.save({ boot_to_home: c.boot_to_home === false }); break;
        case "quick_start": home.save({ quick_start: c.quick_start === false }); break;
        case "no_update_prompt": home.save({ no_update_prompt: c.no_update_prompt === false }); break;
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
        visible: !nameEditor.visible

        Keys.onPressed: {
            // Back on the apps page goes back to Settings, not out
            if (event.key === webOS.Key_webOS_Back && settings.page === "apps") {
                settings.page = "main";
                settings.first(rowList);
                event.accepted = true;
                return;
            }
            settings.keys(rowList, event);
        }
    }

    // the greeting name, typed with the TV's on-screen keyboard
    Item {
        id: nameEditor

        anchors.fill: parent
        visible: false

        function start() {
            field.text = home.config.name || "";
            visible = true;
            field.forceActiveFocus();
            Qt.inputMethod.show();
        }

        function finish(keep) {
            if (keep) home.save({ name: field.text.trim() });
            Qt.inputMethod.hide();
            visible = false;
            rowList.forceActiveFocus();
        }

        Text {
            x: home.r(28)
            text: "Greeting name"
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
                Keys.onReturnPressed: nameEditor.finish(true)
                Keys.onEnterPressed: nameEditor.finish(true)
                Keys.onPressed: {
                    if (event.key === webOS.Key_webOS_Back) { nameEditor.finish(false); event.accepted = true; }
                }
            }
        }

        Text {
            y: home.r(160)
            x: home.r(28)
            width: parent.width - home.r(56)
            wrapMode: Text.WordWrap
            text: "OK saves, Back cancels. Leave it empty for just \"Good evening\"."
            color: Qt.rgba(1, 1, 1, 0.5)
            font.family: fontManager.smart_Regular.family
            font.pixelSize: home.r(24)
        }
    }
}
