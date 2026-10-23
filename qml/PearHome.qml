/*
 * PearWebOS: an Apple TV style Home for LG webOS.
 *
 * A welcome page (greeting, clock, the first six apps in a frosted dock) and,
 * one press down, a drawer with every other app. Apps, their order and their
 * launching all come from LG Home underneath (interfaces.launchPoints), so
 * Edit Home still decides the order; hold OK on a tile to open it.
 *
 * Mounted over Main/GradationBG.qml, which LG Home never loads, and loaded
 * by MainView.qml on top of LG's own views. Its settings and photo list come
 * from peard (tv/peard.js) at runtime; the installer bakes in the values it
 * had, for the moment before peard answers.
 */

import QtQuick 2.12
import QtGraphicalEffects 1.12

FocusScope {

    id: home

    focus: true

    // what Pear's other files are given as their `home` (`home: home` inside
    // one of them would bind its own, empty, property to itself)
    readonly property Item pearHome: home

    readonly property real s: width / 1920
    function r(v) { return Math.round(v * s); }

    readonly property int columns: 6
    readonly property int tileW: r(262)
    readonly property int tileH: r(158)
    readonly property int gapX: r(38)
    // ---- settings and photos, from peard (tv/peard.js) on the TV ----

    // what the installer baked in, used until (or unless) peard answers
    property var config: @CONFIG@
    property var photos: @PHOTOS@

    readonly property string peard: "http://127.0.0.1:47321"

    function api(method, path, data, done) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            var reply = null;
            try { reply = JSON.parse(x.responseText); } catch (e) { }
            if (done) done(x.status === 200 ? reply : null);
        };
        x.open(method, peard + path);
        if (data) x.setRequestHeader("Content-Type", "application/json");
        x.send(data ? JSON.stringify(data) : null);
    }

    // settings changed on the TV or pushed from a computer, and new photos,
    // without restarting Home
    function refresh() {
        api("GET", "/config", null, function (c) { if (c) config = c; });
        api("GET", "/wallpapers", null, function (w) { if (w && w.accents) photos = w; });
        api("GET", "/weather", null, function (w) { weather = w && w.temp !== undefined ? w : null; });
        api("GET", "/inputs", null, function (l) {
            var tiles = [];
            for (var i = 1; l && i < l.length; i++)   // [0] is Live TV, already a tile
                tiles.push({ id: l[i].id, title: l[i].label, iconColor: "#1d2433", input: true, pear: true,
                             // what's plugged in, where the TV can tell; else the port
                             largeIcon: "file:///var/lib/pearwebos/icons/" + (l[i].kind || "input") + ".png" });
            // only when they changed, so the dock isn't rebuilt every minute
            if (JSON.stringify(tiles) !== JSON.stringify(inputTiles)) inputTiles = tiles;
        });
    }

    function save(changes) {
        api("POST", "/config", changes, function (c) { if (c) config = c; });
    }

    // the line under the greeting: Qt formats can't say "20th", so that's added
    readonly property var dateStyles: [
        { key: "intl", format: "dddd d MMMM", ordinal: false, example: "Tuesday 20 October" },
        { key: "us", format: "dddd, MMMM d", ordinal: false, example: "Tuesday, October 20" },
        { key: "short", format: "ddd, MMM d", ordinal: false, example: "Tue, Oct 20" },
        { key: "ordinal", format: "ddd, MMM d", ordinal: true, example: "Tue, Oct 20th" }
    ]
    readonly property var dateStyle: {
        for (var i = 0; i < dateStyles.length; i++) if (dateStyles[i].key === config.date) return dateStyles[i];
        return dateStyles[0];
    }

    readonly property string name: config.name || ""
    readonly property bool twelveHour: String(config.clock) === "12"
    readonly property string dateFormat: dateStyle.format
    readonly property bool dateOrdinal: dateStyle.ordinal
    readonly property bool optEntrance: config.entrance !== false  // the page rises in when Home appears
    readonly property bool optDrift: config.drift === true         // the photo slowly zooms in and out
    readonly property bool optQuiet: config.quiet !== false        // untouched a while, the dock fades away

    // date colour for each background: [the dusk landscape, photo 1, 2, ...]
    readonly property var accents: photos.accents || ["#e9a77f"]
    readonly property string accent: accents[wallpaper] || accents[0]

    // your photos, /var/lib/pearwebos/wallpapers/1.jpg .. N.jpg (0.jpg is the
    // dusk landscape); a new one each time Home comes back after a while
    readonly property int wallpaperCount: photos.count || 0
    readonly property int wallpaperAfter: 15 * 60 * 1000
    property int wallpaper: 0
    property double hiddenAt: 0

    // LG promotions and homebrew background tools: off the tiles unless the
    // settings say otherwise
    readonly property var defaultHidden: [
        "lgchannels.uk", "com.webos.app.lgchannels", "com.webos.app.homeconnect",
        "com.webos.app.sportsteamsettings", "com.lgshop.app35", "com.lgtravel.app",
        "epoxyaisports", "com.lgtvod.app", "webos.day", "com.twin.app.audiochannel",
        "com.twin.app.gamingportal", "amazon.alexa.view", "com.pirate.refresh",
        "org.webosbrew.inputhook", "org.aabytt.webos.custom-screensaver-aerial",
        "com.amazoff.patcher"
    ]
    // Live TV isn't one of LG's launch points, so Pear adds it, first; it's
    // hidden by default where there's no aerial (it would only say "Not
    // Programmed")
    readonly property var liveTv: ({
        id: "com.webos.app.livetv", title: "Live TV", iconColor: "#1d2433",
        largeIcon: "file:///var/lib/pearwebos/icons/livetv.png", pear: true
    })
    // the TV's inputs (HDMI, AV), by the names given them in the TV's own
    // settings; off Home unless picked in Apps on Home (config.inputs)
    property var inputTiles: []
    readonly property var hiddenApps: {
        var hidden = config.hidden || defaultHidden.concat(config.guard !== false ? [liveTv.id] : []);
        var shown = config.inputs || [];
        for (var i = 0; i < inputTiles.length; i++)
            if (shown.indexOf(inputTiles[i].id) < 0) hidden = hidden.concat([inputTiles[i].id]);
        return hidden;
    }

    // every app Home can show, in order: Live TV, the inputs, then LG's in
    // Edit Home order
    function apps() {
        var list = [liveTv].concat(inputTiles);
        for (var i = 0; source && i < source.count; i++) {
            var e = source.get(i).entry;
            if (e && e.id) list.push(e);
        }
        return list;
    }
    onHiddenAppsChanged: rebuildTimer.restart()

    property var weather: null

    readonly property int quietAfter: 45 * 1000

    // Qt's "h" is still 24-hour unless AM/PM is shown, so 12-hour is made here
    function clockText() {
        if (!twelveHour) return Qt.formatDateTime(now, "HH:mm");
        var m = now.getMinutes();
        return (now.getHours() % 12 || 12) + ":" + (m < 10 ? "0" : "") + m;
    }

    // the line under the greeting; Qt formats can't say "20th", so that's added
    function dateText() {
        var t = Qt.formatDateTime(now, dateFormat);
        if (!dateOrdinal) return t;
        var d = now.getDate();
        return t + (d >= 11 && d <= 13 ? "th" : ["th", "st", "nd", "rd"][d % 10] || "th");
    }

    property var dockApps: []
    property var drawerApps: []
    property bool drawer: false
    property var now: new Date()

    readonly property var source: interfaces.launchPoints ? interfaces.launchPoints.launchPointsModel : null

    function rebuild() {
        var dock = [], rest = [], all = apps();
        for (var i = 0; i < all.length; i++) {
            var e = all[i];
            if (hiddenApps.indexOf(e.id) > -1) continue;
            if (dock.length < columns) dock.push(e); else rest.push(e);
        }
        var d = dockList.currentIndex, g = grid.currentIndex;
        dockApps = dock;
        drawerApps = rest;
        dockList.currentIndex = Math.max(0, Math.min(d, dock.length - 1));
        grid.currentIndex = Math.max(0, Math.min(g, rest.length - 1));
    }

    function launch(e) {
        if (!e) return;
        // Pear's own tiles open through peard; LG's through LG Home
        if (e.pear) api("POST", "/launch", { id: e.id }, null);
        else interfaces.launchPoints.doLaunch(e);
    }

    function openDrawer() {
        if (!drawerApps.length) return;
        drawer = true;
        grid.currentIndex = Math.min(dockList.currentIndex, drawerApps.length - 1);
        grid.contentY = -grid.topMargin;
        grid.forceActiveFocus();
    }

    function closeDrawer() {
        drawer = false;
        dockList.currentIndex = Math.min(grid.currentIndex % columns, dockApps.length - 1);
        dockList.forceActiveFocus();
    }

    // focus the tile we were on, whichever part of LG last held focus
    function takeFocus() {
        if (panelOpen) return;
        forceActiveFocus();
        (drawer ? grid : dockList).forceActiveFocus();
    }

    function pickWallpaper() {
        if (wallpaperCount < 1) { wallpaper = 0; return; }
        // Date.now() in the mix: a restored snapshot replays Math.random()
        var n;
        do {
            n = 1 + (Math.floor(Math.random() * 1000003) + Date.now()) % wallpaperCount;
        } while (wallpaperCount > 1 && n === wallpaper);
        wallpaper = n;
    }

    function greeting() {
        var h = now.getHours();
        var part = h < 5 ? "evening" : h < 12 ? "morning" : h < 18 ? "afternoon" : "evening";
        return "Good " + part + (name ? ", " + name : "");
    }

    Component.onCompleted: {
        rebuild();
        pickWallpaper();
        refresh();
    }

    // a new photo list: keep the photo if it's still there, else pick again
    onWallpaperCountChanged: if (wallpaper === 0 || wallpaper > wallpaperCount) pickWallpaper()

    Connections {
        target: uiController
        ignoreUnknownSignals: true
        onHomeShownChanged: {
            home.quiet = false;
            if (!uiController.homeShown) {
                inputsPanel.close();
                settingsPanel.close();
                home.hiddenAt = Date.now();
                return;
            }
            if (home.hiddenAt && Date.now() - home.hiddenAt > home.wallpaperAfter) home.pickWallpaper();
            home.tick();
            if (home.optEntrance) entrance.restart();
        }
    }

    Timer {
        id: rebuildTimer
        interval: 150
        onTriggered: home.rebuild()
    }

    Connections {
        target: home.source
        ignoreUnknownSignals: true
        onCountChanged: rebuildTimer.restart()
        onRowsMoved: rebuildTimer.restart()
        onDataChanged: rebuildTimer.restart()
    }

    // the clock moves on the minute, not every few seconds (and catches up
    // whenever Home comes back, in case the TV slept)
    // (and checks peard for new settings, photos and weather while it's at it)
    function tick() {
        now = new Date();
        clock.interval = 60050 - (now.getSeconds() * 1000 + now.getMilliseconds());
        refresh();
    }

    Timer {
        id: clock
        interval: 1000
        running: home.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: home.tick()
    }

    // ---- entrance: the page fades in and rises a little as Home appears ----

    property real enter: 1

    NumberAnimation {
        id: entrance
        target: home
        property: "enter"
        from: 0
        to: 1
        duration: 380
        easing.type: Easing.OutCubic
    }

    // ---- quiet: untouched a while, only the photo, greeting and clock ----

    property bool quiet: false
    property double wokeAt: 0

    Timer {
        id: idle
        interval: home.quietAfter
        running: home.optQuiet && !home.quiet && !home.drawer && !home.panelOpen && uiController.homeShown
        onTriggered: {
            home.quiet = true;
            // park focus where no list can take the next key, so the first
            // press only wakes Home (focusing Home itself would hand it back
            // to the dock, which keeps its own focus inside)
            asleep.forceActiveFocus();
        }
    }

    Item { id: asleep }

    // any sign of life: wake, and start the idle count again
    function poke() {
        if (quiet) {
            quiet = false;
            wokeAt = Date.now();
            takeFocus();
        }
        if (idle.running) idle.restart();
    }

    onDrawerChanged: poke()

    // ---- bump: the focused tile nudges when there's nowhere to go ----

    property real bumpX: 0
    property real bumpY: 0

    function bump(dx, dy) {
        poke();
        bumpAnim.dx = dx * r(12);
        bumpAnim.dy = dy * r(12);
        bumpAnim.restart();
    }

    SequentialAnimation {
        id: bumpAnim
        property real dx: 0
        property real dy: 0
        ParallelAnimation {
            NumberAnimation { target: home; property: "bumpX"; to: bumpAnim.dx; duration: 60; easing.type: Easing.OutQuad }
            NumberAnimation { target: home; property: "bumpY"; to: bumpAnim.dy; duration: 60; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: home; property: "bumpX"; to: 0; duration: 200; easing.type: Easing.OutBack }
            NumberAnimation { target: home; property: "bumpY"; to: 0; duration: 200; easing.type: Easing.OutBack }
        }
    }

    // OK launches; held for 0.7s it opens LG's Edit Home to reorder.
    // A held remote button arrives as press/release pairs that are not marked
    // as repeats, so a release only counts once no press follows it.
    property bool holding: false

    Timer {
        id: holdTimer
        interval: 700
        onTriggered: {
            home.holding = false;
            releaseTimer.stop();
            uiController.startEdit("app");
        }
    }

    Timer {
        id: releaseTimer
        interval: 150
        onTriggered: {
            home.holding = false;
            if (!holdTimer.running) return;
            holdTimer.stop();
            home.launch(home.drawer ? home.drawerApps[grid.currentIndex] : home.dockApps[dockList.currentIndex]);
        }
    }

    // the OK that woke Home from quiet is not also a launch
    function wakingOk(event) {
        return (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && Date.now() - wokeAt < 600;
    }

    Keys.onPressed: {
        if (home.quiet) {
            home.poke();
            event.accepted = true;
            return;
        }
        if (home.wakingOk(event)) { event.accepted = true; return; }
        home.poke();
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            releaseTimer.stop();
            if (!home.holding) {
                home.holding = true;
                holdTimer.restart();
            }
            event.accepted = true;
        } else if (event.key === webOS.Key_webOS_Back) {
            event.accepted = true;
        }
    }

    Keys.onReleased: {
        if (home.wakingOk(event)) { event.accepted = true; return; }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (home.holding) releaseTimer.restart();
            event.accepted = true;
        } else if (event.key === webOS.Key_webOS_Back) {
            // Home is the bottom layer, as on Apple TV: Back closes the drawer
            // and otherwise stays here (LG would drop to an untuned Live TV)
            if (home.drawer) closeDrawer();
            event.accepted = true;
        }
    }

    // ---- background ----

    // the photo, crossfading when it changes (PearBackdrop.qml, mounted over
    // Main/RecentBG.qml)
    RecentBG {
        anchors.fill: parent
        wallpaper: home.wallpaper
        drift: home.optDrift && home.visible
        // a missing photo falls back to the dusk landscape (0.jpg)
        onMissing: home.wallpaper = 0
    }

    // (the shading for the greeting and tiles is baked into the photos:
    // full-screen layers are what a TV's GPU runs short of)

    // darkens the page while the drawer is open
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.03, 0.03, 0.07, 0.82)
        opacity: home.drawer ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // ---- the Magic Remote's pointer and wheel ----

    // LG's Home is still live beneath Pear, so pointer and wheel input that
    // Pear doesn't take lands on it: the wheel scrolls its hidden shelves and
    // hovering hands focus to its hidden buttons, after which the arrows go
    // there. This takes all of it, and the wheel steps through the rows.
    property real wheelTravel: 0

    function stepDown() {
        if (!drawer) { openDrawer(); return; }
        var c = grid.currentIndex, last = drawerApps.length - 1;
        if (c + columns <= last) grid.currentIndex = c + columns;
        else if (Math.floor(c / columns) < Math.floor(last / columns)) grid.currentIndex = last;
        grid.forceActiveFocus();
    }

    function stepUp() {
        if (!drawer) return;
        if (grid.currentIndex < columns) closeDrawer();
        else grid.currentIndex -= columns;
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPositionChanged: home.poke()
        onWheel: {
            home.poke();
            // a notch is 120; a remote may send it in smaller pieces
            home.wheelTravel += wheel.angleDelta.y;
            while (home.wheelTravel <= -120) { home.wheelTravel += 120; home.stepDown(); }
            while (home.wheelTravel >= 120) { home.wheelTravel -= 120; home.stepUp(); }
            wheel.accepted = true;
        }
    }

    // ---- page: slides up to make the dock the top row of the drawer ----

    Item {
        id: page

        width: parent.width
        height: parent.height
        y: home.drawer ? -(dock.y - r(64)) : 0
        opacity: home.enter
        transform: Translate { y: (1 - home.enter) * home.r(24) }

        Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

        // greeting with the date under it; the clock on the right spans the
        // pair: its digits' top level with the greeting's capitals, their
        // foot on the date's baseline
        Item {
            id: header

            width: parent.width
            height: r(320)
            opacity: home.drawer ? 0 : 1
            layer.enabled: true
            layer.effect: textShadow
            Behavior on opacity { NumberAnimation { duration: 250 } }

            Text {
                id: greetingLine

                // room up to the clock (which is never wider than this reserve);
                // a long name shrinks the line to fit, then is cut short
                readonly property real room: header.width - r(110) - r(110) - r(480)
                                             - (home.twelveHour ? r(90) : 0)

                x: r(110)
                y: r(120)
                width: room
                elide: Text.ElideRight
                text: home.greeting()
                color: "#ffffff"
                font.family: fontManager.smart_Light.family
                font.weight: fontManager.smart_Light.weight
                font.pixelSize: Math.max(r(52), Math.min(r(78), Math.floor(r(78) * room / Math.max(1, greetingWidth.advanceWidth))))
            }

            TextMetrics {
                id: greetingWidth
                font.family: fontManager.smart_Light.family
                font.weight: fontManager.smart_Light.weight
                font.pixelSize: r(78)
                text: greetingLine.text
            }

            Text {
                id: dateLine

                x: r(110)
                anchors.top: greetingLine.bottom
                anchors.topMargin: r(10)
                // with the weather after it, when it's on
                text: home.dateText() + (home.weather ? "   ·   " + home.weather.temp + "°  " + home.weather.words : "")
                color: home.accent
                font.family: fontManager.smart_Regular.family
                font.weight: fontManager.smart_Regular.weight
                font.pixelSize: r(36)
            }

            // LG Smart UI Light, measured from the font: cap height 0.672 em,
            // digits 0.682 em (Qt's FontMetrics on the TV disagree with the glyphs)
            readonly property real capRatio: 0.672
            readonly property real digitRatio: 0.682

            // AM / PM in 12-hour mode: small, beside the digits, on the date's
            // baseline (at clock size it would crowd the greeting)
            Text {
                id: ampm

                visible: home.twelveHour
                anchors.right: parent.right
                anchors.rightMargin: r(110)
                anchors.baseline: dateLine.baseline
                text: home.now.getHours() < 12 ? "AM" : "PM"
                color: "#ffffff"
                font.family: fontManager.smart_Regular.family
                font.weight: fontManager.smart_Regular.weight
                font.pixelSize: r(36)
            }

            Text {
                readonly property real capTop: greetingLine.y + greetingLine.baselineOffset
                                               - header.capRatio * greetingLine.font.pixelSize
                readonly property real span: dateLine.y + dateLine.baselineOffset - capTop

                anchors.right: home.twelveHour ? ampm.left : parent.right
                anchors.rightMargin: home.twelveHour ? r(14) : r(110)
                anchors.baseline: dateLine.baseline
                text: home.clockText()
                color: "#ffffff"
                font.family: fontManager.smart_Light.family
                font.weight: fontManager.smart_Light.weight
                font.pixelSize: Math.round(span / header.digitRatio)
            }
        }

        // Inputs and Settings, top right above the clock: Up from the dock
        // (PearTopBar.qml, mounted over Main/AIBoardIntro.qml)
        AIBoardIntro {
            id: topBar
            home: pearHome
            anchors.right: parent.right
            anchors.rightMargin: r(110)
            y: r(36)
            onOpen: key === "inputs" ? inputsPanel.show() : settingsPanel.show()
            onDown: dockList.forceActiveFocus()
        }

        // the frosted dock with the first six apps
        Rectangle {
            id: dock

            anchors.horizontalCenter: parent.horizontalCenter
            y: r(706)
            width: dockList.width + r(2 * 34)
            height: home.tileH + r(2 * 34)
            radius: r(50)
            color: Qt.rgba(1, 1, 1, 0.11)
            border.color: Qt.rgba(1, 1, 1, 0.10)
            border.width: Math.max(1, r(1))
            opacity: home.quiet ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: home.quiet ? 900 : 200 } }

            ListView {
                id: dockList

                x: r(34)
                y: r(34)
                width: home.columns * home.tileW + (home.columns - 1) * home.gapX
                height: home.tileH
                orientation: ListView.Horizontal
                spacing: home.gapX
                interactive: false
                keyNavigationEnabled: true
                focus: true
                model: home.dockApps
                delegate: tile
                highlightFollowsCurrentItem: false

                onCurrentIndexChanged: home.poke()
                Keys.onDownPressed: {
                    if (home.drawerApps.length) home.openDrawer();
                    else home.bump(0, 1);
                }
                Keys.onUpPressed: topBar.forceActiveFocus()
                Keys.onLeftPressed: {
                    if (currentIndex > 0) event.accepted = false;
                    else home.bump(-1, 0);
                }
                Keys.onRightPressed: {
                    if (currentIndex < count - 1) event.accepted = false;
                    else home.bump(1, 0);
                }
            }
        }

        // "All apps" with a drawn chevron (LG's font has no glyph for one)
        Row {
            id: allApps

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: dock.bottom
            anchors.topMargin: r(80)
            spacing: r(14)
            opacity: home.drawer || home.quiet || !home.drawerApps.length ? 0 : 0.55
            Behavior on opacity { NumberAnimation { duration: home.quiet ? 900 : 250 } }

            Canvas {
                width: r(24)
                height: r(14)
                anchors.verticalCenter: parent.verticalCenter
                onPaint: {
                    var c = getContext("2d");
                    c.reset();
                    c.strokeStyle = "#ffffff";
                    c.lineWidth = Math.max(2, r(3));
                    c.lineCap = "round";
                    c.lineJoin = "round";
                    c.beginPath();
                    c.moveTo(c.lineWidth, c.lineWidth);
                    c.lineTo(width / 2, height - c.lineWidth);
                    c.lineTo(width - c.lineWidth, c.lineWidth);
                    c.stroke();
                }
            }

            Text {
                text: "All apps"
                color: "#ffffff"
                font.family: fontManager.smart_Regular.family
                font.weight: fontManager.smart_Regular.weight
                font.pixelSize: r(28)
            }
        }

        MouseArea {
            anchors.fill: allApps
            anchors.margins: -r(16)
            enabled: !home.drawer
            onClicked: home.openDrawer()
        }

        // every other app, in the user's order
        GridView {
            id: grid

            x: dock.x + dockList.x - r(20)
            y: dock.y + dock.height + r(56)
            width: leftMargin + home.columns * cellWidth
            height: home.height - r(64) - dock.height - r(56)
            cellWidth: home.tileW + home.gapX
            cellHeight: home.tileH + r(96)
            leftMargin: r(20)
            topMargin: r(36)
            bottomMargin: r(60)
            clip: true
            interactive: false
            keyNavigationEnabled: true
            opacity: home.drawer ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            model: home.drawerApps
            delegate: tile
            highlight: Item {}
            highlightMoveDuration: 220
            preferredHighlightBegin: r(36)
            preferredHighlightEnd: height - r(160)
            highlightRangeMode: GridView.ApplyRange
            keyNavigationWraps: false

            onCurrentIndexChanged: home.poke()

            Keys.onUpPressed: {
                if (currentIndex < home.columns) home.closeDrawer();
                else event.accepted = false;
            }

            // a short last row: Down from a column it doesn't reach lands on its last app
            Keys.onDownPressed: {
                if (currentIndex + home.columns < count) event.accepted = false;
                else if (Math.floor(currentIndex / home.columns) < Math.floor((count - 1) / home.columns)) currentIndex = count - 1;
                else home.bump(0, 1);
            }

            Keys.onLeftPressed: {
                if (currentIndex % home.columns > 0) event.accepted = false;
                else home.bump(-1, 0);
            }

            Keys.onRightPressed: {
                if (currentIndex % home.columns < home.columns - 1 && currentIndex < count - 1) event.accepted = false;
                else home.bump(1, 0);
            }
        }
    }

    // lifts the greeting and clock off bright photos
    Component {
        id: textShadow

        DropShadow {
            radius: home.r(14)
            samples: 25
            verticalOffset: home.r(2)
            color: Qt.rgba(0, 0, 0, 0.6)
        }
    }

    // ---- the panels: Inputs and Settings slide in from the right ----

    readonly property bool panelOpen: inputsPanel.shown || settingsPanel.shown
    readonly property Item dockView: dockList

    // PearInputs.qml and PearSettings.qml, mounted over Main/RecentTitle.qml and
    // Main/PromotionBG.qml
    RecentTitle {
        id: inputsPanel
        home: pearHome
        z: 10
        onClosed: topBar.forceActiveFocus()
    }

    PromotionBG {
        id: settingsPanel
        home: pearHome
        z: 10
        onClosed: topBar.forceActiveFocus()
    }

    // ---- one tile: the app's colour, its icon, a lift and a title when focused ----

    // PearTile.qml, mounted over Main/AdLoadingImage.qml
    Component {
        id: tile
        AdLoadingImage { home: pearHome; app: modelData; idx: index }
    }

}
