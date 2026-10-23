/*
 * PearWebOS: the photo behind Pear's Home.
 *
 * Two images, so a new photo fades in over the old one instead of cutting
 * through to blank while it loads. Mounted over Main/RecentBG.qml, which LG
 * Home never loads; PearHome uses it as RecentBG { }.
 */

import QtQuick 2.12

Item {

    id: backdrop

    // which photo: /var/lib/pearwebos/wallpapers/<wallpaper>.jpg (0 is the landscape)
    property int wallpaper: 0
    // a slow zoom in and out. Off by default: it redraws the whole screen every
    // frame for as long as Home is up
    property bool drift: false

    // a photo that won't load; PearHome falls back to the landscape
    signal missing()

    property Image front: null

    function path(n) { return "file:///var/lib/pearwebos/wallpapers/" + n + ".jpg"; }

    function show(n) {
        var src = path(n);
        if (front && String(front.source) === src) return;
        var next = front === photoA ? photoB : photoA;
        if (fade.running) fade.complete();
        next.opacity = 0;
        next.source = src;
        if (next.status === Image.Ready) reveal(next);
    }

    function reveal(img) {
        if (img === front) return;
        fade.old = front;
        img.z = 1;
        if (front) front.z = 0;
        front = img;
        fade.target = img;
        fade.restart();
    }

    function loaded(img) {
        if (img.status === Image.Ready && img !== front && String(img.source) !== "") reveal(img);
        // not from inside the image's own status change
        else if (img.status === Image.Error && wallpaper > 0) Qt.callLater(missing);
    }

    onWallpaperChanged: show(wallpaper)
    Component.onCompleted: show(wallpaper)

    // only seen before the first photo is in
    Rectangle {
        anchors.fill: parent
        color: "#0c0c1a"
        visible: backdrop.front === null
    }

    NumberAnimation {
        id: fade

        property Image old: null

        property: "opacity"
        from: 0
        to: 1
        duration: 800
        easing.type: Easing.InOutQuad
        // the old photo is covered now: let it go
        onStopped: if (old && old !== backdrop.front) { old.opacity = 0; old.source = ""; }
    }

    SequentialAnimation on scale {
        running: backdrop.drift
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 1.05; duration: 60000; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.05; to: 1.0; duration: 60000; easing.type: Easing.InOutSine }
    }

    Image {
        id: photoA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1920
        asynchronous: true
        opacity: 0
        onStatusChanged: backdrop.loaded(photoA)
    }

    Image {
        id: photoB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1920
        asynchronous: true
        opacity: 0
        onStatusChanged: backdrop.loaded(photoB)
    }
}
