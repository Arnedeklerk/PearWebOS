/*
 * PearWebOS: an Apple TV style Home for LG webOS.
 *
 * A welcome page (greeting, clock, the first six apps in a frosted dock) and,
 * one press down, a drawer with every other app. Apps, their order and their
 * launching all come from LG Home underneath (interfaces.launchPoints), so
 * Edit Home still decides the order; hold OK on a tile to open it.
 *
 * Mounted over Main/GradationBG.qml, which LG Home never loads, and loaded
 * by MainView.qml on top of LG's own views. Words in @CAPS@ are filled in by
 * the installer from your setup.
 */

import QtQuick 2.12
import QtGraphicalEffects 1.12

FocusScope {

    id: home

    focus: true

    readonly property real s: width / 1920
    function r(v) { return Math.round(v * s); }

    readonly property int columns: 6
    readonly property int tileW: r(262)
    readonly property int tileH: r(158)
    readonly property int gapX: r(38)
    // date colour for each background: [the dusk landscape, photo 1, 2, ...]
    readonly property var accents: @ACCENTS@
    readonly property string accent: accents[wallpaper] || accents[0]

    // LG promotions and homebrew background tools; never shown as tiles
    readonly property var hiddenApps: [
        "lgchannels.uk", "com.webos.app.lgchannels", "com.webos.app.homeconnect",
        "com.webos.app.sportsteamsettings", "com.lgshop.app35", "com.lgtravel.app",
        "epoxyaisports", "com.lgtvod.app", "webos.day", "com.twin.app.audiochannel",
        "com.twin.app.gamingportal", "amazon.alexa.view", "com.pirate.refresh",
        "org.webosbrew.inputhook", "org.aabytt.webos.custom-screensaver-aerial",
        "com.amazoff.patcher"
    ]

    // your photos, /var/lib/pearwebos/wallpapers/1.jpg .. N.jpg (0.jpg is the
    // dusk landscape); a new one each time Home comes back after a while
    readonly property int wallpaperCount: @WALLPAPERS@
    readonly property int wallpaperAfter: 15 * 60 * 1000
    property int wallpaper: 0
    property double hiddenAt: 0

    readonly property string name: "@NAME@"
    readonly property string clockFormat: "@CLOCK@"
    readonly property bool twelveHour: clockFormat === "h:mm"
    readonly property string dateFormat: "@DATE@"
    readonly property bool dateOrdinal: @DATE_ORDINAL@

    property var dockApps: []
    property var drawerApps: []
    property bool drawer: false
    property var now: new Date()

    readonly property var source: interfaces.launchPoints ? interfaces.launchPoints.launchPointsModel : null

    function rebuild() {
        var dock = [], rest = [];
        if (source) {
            for (var i = 0; i < source.count; i++) {
                var e = source.get(i).entry;
                if (!e || !e.id || hiddenApps.indexOf(e.id) > -1) continue;
                if (dock.length < columns) dock.push(e); else rest.push(e);
            }
        }
        var d = dockList.currentIndex, g = grid.currentIndex;
        dockApps = dock;
        drawerApps = rest;
        dockList.currentIndex = Math.max(0, Math.min(d, dock.length - 1));
        grid.currentIndex = Math.max(0, Math.min(g, rest.length - 1));
    }

    function launch(e) {
        if (e) interfaces.launchPoints.doLaunch(e);
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
        forceActiveFocus();
        (drawer ? grid : dockList).forceActiveFocus();
    }

    function pickWallpaper() {
        if (wallpaperCount < 1) return;
        // Date.now() in the mix: a restored snapshot replays Math.random()
        var n;
        do {
            n = 1 + (Math.floor(Math.random() * 1000003) + Date.now()) % wallpaperCount;
        } while (wallpaperCount > 1 && n === wallpaper);
        wallpaper = n;
    }

    // the date line; "20th" style when asked, which Qt formats can't do
    function dateText() {
        var t = Qt.formatDateTime(now, dateFormat);
        if (!dateOrdinal) return t;
        var d = now.getDate(), m = d % 100;
        return t + (m >= 11 && m <= 13 ? "th" : ["th", "st", "nd", "rd"][d % 10] || "th");
    }

    function greeting() {
        var h = now.getHours();
        var part = h < 5 ? "evening" : h < 12 ? "morning" : h < 18 ? "afternoon" : "evening";
        return "Good " + part + (name ? ", " + name : "");
    }

    Component.onCompleted: {
        rebuild();
        pickWallpaper();
    }

    Connections {
        target: uiController
        ignoreUnknownSignals: true
        onHomeShownChanged: {
            if (!uiController.homeShown) home.hiddenAt = Date.now();
            else if (home.hiddenAt && Date.now() - home.hiddenAt > home.wallpaperAfter) home.pickWallpaper();
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

    Timer {
        interval: 5000
        running: home.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: home.now = new Date()
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

    Keys.onPressed: {
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

    Rectangle {
        anchors.fill: parent
        color: "#0c0c1a"
    }

    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1920
        source: "file:///var/lib/pearwebos/wallpapers/" + home.wallpaper + ".jpg"
        asynchronous: true
        // a missing photo falls back to the dusk landscape (0.jpg)
        onStatusChanged: if (status === Image.Error && home.wallpaper > 0) home.wallpaper = 0
    }

    // keeps the greeting readable over bright photos
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.45
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.02, 0.02, 0.05, 0.55) }
            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.02, 0.05, 0.0) }
        }
    }

    // darkens the lower half so tiles and titles read
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.03, 0.07, 0.0) }
            GradientStop { position: 0.45; color: Qt.rgba(0.03, 0.03, 0.07, 0.10) }
            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.02, 0.05, 0.78) }
        }
    }

    // and the whole page while the drawer is open
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.03, 0.03, 0.07, 0.82)
        opacity: home.drawer ? 1 : 0
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
        onWheel: {
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
                text: home.dateText()
                color: home.accent
                font.family: fontManager.smart_Regular.family
                font.weight: fontManager.smart_Regular.weight
                font.pixelSize: r(36)
            }

            // LG Smart UI Light, measured from the font: cap height 0.672 em,
            // digits 0.682 em (Qt's FontMetrics on the TV disagree with the glyphs)
            readonly property real capRatio: 0.672
            readonly property real digitRatio: 0.682

            // AM / PM in 12-hour mode: small, beside the digits, on the
            // date's baseline (full size it would crowd the greeting)
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
                // Qt's "h" is 0-23 unless the format has AP, so do 12-hour by hand
                text: home.twelveHour
                      ? ((home.now.getHours() % 12) || 12) + Qt.formatDateTime(home.now, ":mm")
                      : Qt.formatDateTime(home.now, home.clockFormat)
                color: "#ffffff"
                font.family: fontManager.smart_Light.family
                font.weight: fontManager.smart_Light.weight
                font.pixelSize: Math.round(span / header.digitRatio)
            }
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

                Keys.onDownPressed: home.openDrawer()
                Keys.onUpPressed: event.accepted = true
            }
        }

        // "All apps" with a drawn chevron (LG's font has no glyph for one)
        Row {
            id: allApps

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: dock.bottom
            anchors.topMargin: r(80)
            spacing: r(14)
            opacity: home.drawer || !home.drawerApps.length ? 0 : 0.55
            Behavior on opacity { NumberAnimation { duration: 250 } }

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

            Keys.onUpPressed: {
                if (currentIndex < home.columns) home.closeDrawer();
                else event.accepted = false;
            }

            // a short last row: Down from a column it doesn't reach lands on its last app
            Keys.onDownPressed: {
                if (currentIndex + home.columns < count) event.accepted = false;
                else if (Math.floor(currentIndex / home.columns) < Math.floor((count - 1) / home.columns)) currentIndex = count - 1;
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

    // ---- one tile: the app's colour, its icon, a lift and a title when focused ----

    Component {
        id: tile

        Item {
            id: t

            property Item view: ListView.view ? ListView.view : GridView.view
            property var app: modelData
            property bool focused: view !== null && view.activeFocus && view.currentIndex === index

            width: home.tileW
            height: home.tileH
            z: focused ? 2 : 1

            // the pointer: hover picks the tile, a click opens it, a long
            // press opens Edit App List (as holding OK does)
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                // the drawer's tiles only while it is open; with it open, the
                // dock still takes clicks but not hover (that would close it)
                enabled: t.view === dockList || home.drawer
                onEntered: {
                    if (t.view === dockList && home.drawer) return;
                    t.view.currentIndex = index;
                    t.view.forceActiveFocus();
                }
                onClicked: home.launch(t.app)
                onPressAndHold: uiController.startEdit("app")
            }

            RectangularGlow {
                anchors.fill: card
                anchors.topMargin: home.r(14)
                glowRadius: home.r(26)
                spread: 0.15
                cornerRadius: card.radius + glowRadius
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: t.focused ? 1 : 0
                scale: card.scale
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Rectangle {
                id: card

                anchors.fill: parent
                radius: home.r(26)
                color: t.app && t.app.iconColor ? t.app.iconColor : "#2b2a40"
                scale: t.focused ? 1.14 : 1
                antialiasing: true
                Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                // decoded at its own size and never drawn larger: a 130 px icon
                // shows pixel for pixel, a 192 px one scales down crisply
                Image {
                    anchors.centerIn: parent
                    height: Math.min(parent.height * 0.94, implicitHeight > 0 ? implicitHeight * home.s : parent.height * 0.94)
                    width: height
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    source: !t.app ? "" : (t.app.extraLargeIcon || t.app.largeIcon || t.app.icon || "")
                }

                // a soft sheen, brighter on the focused tile
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, t.focused ? 0.20 : 0.07) }
                        GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
                    }
                    border.color: Qt.rgba(1, 1, 1, t.focused ? 0.0 : 0.10)
                    border.width: Math.max(1, home.r(1))
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: t.view === dockList ? home.r(34 + 16) : home.r(24)
                width: parent.width * 1.3
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: t.app ? t.app.title : ""
                color: "#ffffff"
                opacity: t.focused ? 1 : 0
                font.family: fontManager.smart_SemiBold.family
                font.weight: fontManager.smart_SemiBold.weight
                font.pixelSize: home.r(26)
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
        }
    }
}
