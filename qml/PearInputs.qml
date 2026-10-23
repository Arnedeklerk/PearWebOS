/*
 * PearWebOS: Inputs. Live TV and the HDMI ports, from the TV through peard;
 * OK switches to one. Mounted over Main/RecentTitle.qml, which LG Home never
 * loads; Pear uses it as RecentTitle { }.
 */

import QtQuick 2.12

EditTile {

    id: inputs

    title: "Inputs"

    property var list: []

    // the rows, built from what peard reported
    readonly property var rows: list.length ? list.map(function (i) {
        return { label: i.label, value: i.plugged ? "" : "Nothing connected", dim: !i.plugged, id: i.id };
    }) : [{ label: "Looking for inputs...", dim: true, id: "" }]

    onActivated: {
        var r = rows[index];
        if (!r || !r.id) return;
        home.api("POST", "/launch", { id: r.id }, null);
        close();
    }

    function show() {
        open();
        rowList.forceActiveFocus();
        home.api("GET", "/inputs", null, function (l) {
            inputs.list = l || [];
            inputs.first(rowList);
        });
    }

    ListView {
        id: rowList

        anchors.fill: parent
        model: inputs.rows
        delegate: inputs.row
        keyNavigationEnabled: false
        highlightMoveDuration: 0
        clip: true

        Keys.onPressed: inputs.keys(rowList, event)
    }
}
