/*
 * PearWebOS: the glass panel that slides in from the right, for Inputs and
 * Settings. Mounted over Main/EditTile.qml, which LG Home never loads; Pear
 * uses it as EditTile { }.
 *
 * What's inside comes from the panel that uses it (its children go in the
 * sheet), usually a PanelList: rows from a model of
 *   {label, value, note, header, dim}
 * where a header row is a section title the focus skips. Back closes it.
 */

import QtQuick 2.12
import QtGraphicalEffects 1.12

FocusScope {

    id: panel

    property Item home
    property string title: ""
    property bool shown: false
    default property alias content: body.data

    signal closed()
    // OK or a click on a row (not a section title)
    signal activated(int index)

    // what a panel's list does with the remote: up and down skip section
    // titles, OK activates, Left closes
    function keys(list, event) {
        if (event.key === Qt.Key_Up) step(list, -1);
        else if (event.key === Qt.Key_Down) step(list, 1);
        else if (event.key === Qt.Key_Left) close();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) activated(list.currentIndex);
        else return;
        event.accepted = true;
    }

    // one row of a panel list; focused rows fill white, as on Apple TV
    readonly property Component row: Component {
        Item {
            id: rowItem

            property var d: modelData
            property bool focused: ListView.isCurrentItem && ListView.view.activeFocus

            width: ListView.view.width
            height: d.header ? home.r(64) : home.r(86)

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: !rowItem.d.header
                onEntered: { rowItem.ListView.view.currentIndex = index; rowItem.ListView.view.forceActiveFocus(); }
                onClicked: panel.activated(index)
            }

            Text {
                visible: !!rowItem.d.header
                anchors.left: parent.left
                anchors.leftMargin: home.r(28)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: home.r(10)
                text: rowItem.d.label || ""
                color: Qt.rgba(1, 1, 1, 0.5)
                font.family: fontManager.smart_SemiBold.family
                font.weight: fontManager.smart_SemiBold.weight
                font.pixelSize: home.r(24)
                font.capitalization: Font.AllUppercase
                font.letterSpacing: home.r(2)
            }

            Rectangle {
                visible: !rowItem.d.header
                anchors.fill: parent
                anchors.topMargin: home.r(4)
                anchors.bottomMargin: home.r(4)
                radius: home.r(22)
                color: rowItem.focused ? "#ffffff" : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: home.r(28)
                    anchors.right: valueText.left
                    anchors.rightMargin: home.r(16)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: rowItem.d.label || ""
                        color: rowItem.focused ? "#14141c" : (rowItem.d.dim ? Qt.rgba(1, 1, 1, 0.45) : "#ffffff")
                        font.family: fontManager.smart_Regular.family
                        font.weight: fontManager.smart_Regular.weight
                        font.pixelSize: home.r(32)
                    }

                    Text {
                        visible: !!rowItem.d.note
                        width: parent.width
                        elide: Text.ElideRight
                        text: rowItem.d.note || ""
                        color: rowItem.focused ? "#5a5a66" : Qt.rgba(1, 1, 1, 0.5)
                        font.family: fontManager.smart_Regular.family
                        font.weight: fontManager.smart_Regular.weight
                        font.pixelSize: home.r(22)
                    }
                }

                Text {
                    id: valueText
                    anchors.right: parent.right
                    anchors.rightMargin: home.r(28)
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowItem.d.value || ""
                    color: rowItem.focused ? "#5a5a66" : Qt.rgba(1, 1, 1, 0.6)
                    font.family: fontManager.smart_Regular.family
                    font.weight: fontManager.smart_Regular.weight
                    font.pixelSize: home.r(30)
                }
            }
        }
    }

    // move to the next row that isn't a section title
    function step(list, dir) {
        var i = list.currentIndex + dir;
        while (i >= 0 && i < list.count && list.model[i].header) i += dir;
        if (i >= 0 && i < list.count) list.currentIndex = i;
    }

    function first(list) {
        list.currentIndex = -1;
        step(list, 1);
    }

    function open() { shown = true; forceActiveFocus(); }
    function close() { if (!shown) return; shown = false; closed(); }

    anchors.fill: parent
    visible: dim.opacity > 0

    Keys.onPressed: {
        // Back closes; nothing else gets through to Home underneath
        if (event.key === webOS.Key_webOS_Back) close();
        event.accepted = true;
    }
    Keys.onReleased: event.accepted = true

    Rectangle {
        id: dim
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.02, 0.05, 0.55)
        opacity: panel.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    RectangularGlow {
        anchors.fill: sheet
        glowRadius: home.r(40)
        spread: 0.1
        cornerRadius: sheet.radius + glowRadius
        color: Qt.rgba(0, 0, 0, 0.5)
        cached: true
        opacity: dim.opacity
    }

    Rectangle {
        id: sheet

        width: home.r(780)
        height: parent.height - home.r(2 * 60)
        y: home.r(60)
        x: panel.shown ? parent.width - width - home.r(60) : parent.width + home.r(40)
        radius: home.r(44)
        color: Qt.rgba(0.11, 0.11, 0.16, 0.94)
        border.color: Qt.rgba(1, 1, 1, 0.10)
        border.width: Math.max(1, home.r(1))
        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        // takes pointer input over the sheet, so it can't fall through to Home
        MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: wheel.accepted = true }

        Text {
            id: heading
            x: home.r(48)
            y: home.r(40)
            text: panel.title
            color: "#ffffff"
            font.family: fontManager.smart_SemiBold.family
            font.weight: fontManager.smart_SemiBold.weight
            font.pixelSize: home.r(44)
        }

        Item {
            id: body
            anchors.top: heading.bottom
            anchors.topMargin: home.r(28)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: home.r(24)
            anchors.rightMargin: home.r(24)
            anchors.bottomMargin: home.r(28)
            clip: true
        }
    }
}
