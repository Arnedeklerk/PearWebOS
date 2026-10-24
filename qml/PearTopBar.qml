/*
 * PearWebOS: the two buttons at the top right of Home, above the clock:
 * Inputs and Settings. Up from the dock reaches them. Mounted over
 * Main/AIBoardIntro.qml, which LG Home never loads; PearHome uses it as
 * AIBoardIntro { }.
 */

import QtQuick 2.12

FocusScope {
    id: topBar

    property Item home
    // a button was pressed ("inputs" or "settings"), and Down was
    signal open(string key)
    signal down()

    property int index: 0
    readonly property var buttons: [
        { key: "inputs", label: "Inputs" },
        { key: "settings", label: "Settings" }
    ]

    function press(i) {
        index = i;
        open(buttons[i].key);
    }

    width: barRow.width
    height: home.r(72)
    opacity: home.drawer || home.quiet ? 0 : 1
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: home.quiet ? 900 : 250 } }

    onActiveFocusChanged: if (activeFocus) home.poke()
    Keys.onLeftPressed: { if (index > 0) index--; home.poke(); }
    Keys.onRightPressed: { if (index < buttons.length - 1) index++; home.poke(); }
    Keys.onDownPressed: down()
    Keys.onUpPressed: event.accepted = true
    Keys.onReturnPressed: press(index)
    Keys.onEnterPressed: press(index)

    // the focused button's name, to its left (below, it would sit on the clock)
    Text {
        anchors.right: barRow.left
        anchors.rightMargin: home.r(20)
        anchors.verticalCenter: barRow.verticalCenter
        text: topBar.buttons[topBar.index].label
        color: "#ffffff"
        opacity: topBar.activeFocus ? 1 : 0
        font.family: fontManager.smart_SemiBold.family
        font.weight: fontManager.smart_SemiBold.weight
        font.pixelSize: home.r(26)
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    Row {
        id: barRow
        spacing: home.r(22)

        Repeater {
            model: topBar.buttons

            Item {
                id: button

                readonly property bool focused: topBar.activeFocus && topBar.index === index

                width: home.r(72)
                height: home.r(72)
                // faint until the bar is reached, so they don't compete with the photo
                opacity: button.focused ? 1 : topBar.activeFocus ? 0.75 : 0.4
                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

                Rectangle {
                    id: disc
                    anchors.fill: parent
                    radius: width / 2
                    color: button.focused ? "#ffffff" : Qt.rgba(1, 1, 1, 0.16)
                    border.color: Qt.rgba(1, 1, 1, button.focused ? 0 : 0.18)
                    border.width: Math.max(1, home.r(1))
                    scale: button.focused ? 1.12 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // the icons, drawn: a screen with an arrow in, and a cog
                    Canvas {
                        id: icon
                        anchors.centerIn: parent
                        width: home.r(40)
                        height: home.r(40)
                        property color ink: button.focused ? "#14141c" : "#ffffff"
                        onInkChanged: requestPaint()
                        onPaint: {
                            var g = getContext("2d"), w = width, h = height;
                            g.reset();
                            g.strokeStyle = ink;
                            g.fillStyle = ink;
                            g.lineWidth = Math.max(2, w * 0.08);
                            g.lineCap = "round";
                            g.lineJoin = "round";
                            if (modelData.key === "inputs") {
                                g.strokeRect(w * 0.30, h * 0.18, w * 0.62, h * 0.50);
                                g.beginPath();
                                g.moveTo(w * 0.40, h * 0.86); g.lineTo(w * 0.82, h * 0.86);
                                g.moveTo(w * 0.04, h * 0.43); g.lineTo(w * 0.50, h * 0.43);
                                g.moveTo(w * 0.38, h * 0.31); g.lineTo(w * 0.50, h * 0.43); g.lineTo(w * 0.38, h * 0.55);
                                g.stroke();
                            } else {
                                g.translate(w / 2, h / 2);
                                for (var t = 0; t < 8; t++) {
                                    g.rotate(Math.PI / 4);
                                    g.fillRect(-w * 0.07, -w * 0.47, w * 0.14, w * 0.16);
                                }
                                g.beginPath();
                                g.arc(0, 0, w * 0.30, 0, Math.PI * 2);
                                g.stroke();
                                g.beginPath();
                                g.arc(0, 0, w * 0.11, 0, Math.PI * 2);
                                g.stroke();
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: { topBar.index = index; topBar.forceActiveFocus(); }
                    onClicked: topBar.press(index)
                }
            }
        }
    }
}
