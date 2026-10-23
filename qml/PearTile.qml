/*
 * PearWebOS: one app tile, for the dock and the drawer. The app's colour and
 * icon, a lift and its name when focused, and the Magic Remote pointer.
 * Mounted over Main/AdLoadingImage.qml, which LG Home never loads; PearHome
 * uses it as AdLoadingImage { }.
 */

import QtQuick 2.12
import QtGraphicalEffects 1.12

Item {
    id: t

    property Item home
    property var app
    property int idx: -1
    property Item view: ListView.view ? ListView.view : GridView.view
    property bool focused: view !== null && view.activeFocus && view.currentIndex === idx

    width: home.tileW
    height: home.tileH
    z: focused ? 2 : 1
    // a bump moves the focused tile, its glow and its name together
    transform: Translate {
        x: t.focused ? home.bumpX : 0
        y: t.focused ? home.bumpY : 0
    }

    // the pointer: hover picks the tile, a click opens it, a long
    // press opens Edit App List (as holding OK does)
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        // the drawer's tiles only while it is open; with it open, the
        // dock still takes clicks but not hover (that would close it)
        enabled: t.view === home.dockView || home.drawer
        onEntered: {
            home.poke();
            if (t.view === home.dockView && home.drawer) return;
            t.view.currentIndex = idx;
            t.view.forceActiveFocus();
        }
        onClicked: home.launch(t.app)
        onPressAndHold: uiController.startEdit("app")
    }

    RectangularGlow {
        // drawn once and reused: scale and opacity don't redraw it
        cached: true
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
        anchors.topMargin: t.view === home.dockView ? home.r(34 + 16) : home.r(24)
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
        // rises into place as it fades in
        transform: Translate {
            y: t.focused ? 0 : home.r(8)
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
    }
}
