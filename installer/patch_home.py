"""Patch the TV's own LG Home files to load PearWebOS.

LG Home is proprietary, so PearWebOS ships none of it: `pear setup` copies
the few files below off your TV, this applies small exact edits to them, and
the results go back to your TV only.

Every edit must match exactly once. A firmware whose Home differs fails here,
on your computer, and nothing is installed.
"""
import os
import sys

APP = "/usr/palm/applications/com.webos.app.home/qml"

# where PearHome.qml is mounted: a file LG Home never loads
PEAR_SLOT = "UserInterfaceLayer/Containers/Main/GradationBG.qml"

LOADER = '''    // PearWebOS: an Apple TV style Home over LG's (which stays loaded beneath it)
    Loader {
        id: skinHome

        property bool skinActive: status === Loader.Ready && !uiController.isEditMode

        anchors.fill: parent
        z: 50
        visible: skinActive
        focus: skinActive
        source: "Main/GradationBG.qml"

        // if Pear fails to load, LG's Home shows; say why in a corner
        onStatusChanged: {
            if(status === Loader.Error) {
                var c = Qt.createComponent(source);
                skinError.text = "PearWebOS: " + c.errorString();
            }
        }

        // LG moves focus around after these settle, so take it back a beat later
        Timer {
            id: skinRefocus
            interval: 350
            onTriggered: if(skinHome.skinActive) skinHome.item.takeFocus()
        }

        Connections {
            target: uiController
            ignoreUnknownSignals: true
            onHomeShownChanged: {
                if(uiController.homeShown && skinHome.skinActive) {
                    if(skinHome.item.drawer) skinHome.item.closeDrawer();
                    skinHome.item.takeFocus();
                    skinRefocus.restart();
                }
            }
            onIsEditModeChanged: {
                if(!uiController.isEditMode) skinRefocus.restart();
            }
        }
    }

    Text {
        id: skinError
        z: 200
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 8
        color: "#ff8080"
        font.pixelSize: 14
        visible: text !== ""
    }

'''

PATCHES = {
    "UserInterfaceLayer/Containers/MainView.qml": [
        # LG's views stay loaded (and show in Edit Home) so launching,
        # ordering and editing keep working; Pear draws over them
        ('''        id: shelfListContainer

        objectName: "shelfListContainer"
''',
         '''        id: shelfListContainer

        objectName: "shelfListContainer"

        opacity: skinHome.skinActive ? 0 : 1
'''),
        # whatever LG hands focus to lands on its ribbon; send it to Pear instead
        ('''            onActiveFocusChanged: {
                if(activeFocus) {
                    appListLoader.forceActiveFocus();
                    if(systemProperties.isTopShelfGuide) {''',
         '''            onActiveFocusChanged: {
                if(activeFocus) {
                    if(skinHome.skinActive) skinHome.forceActiveFocus();
                    else appListLoader.forceActiveFocus();
                    if(systemProperties.isTopShelfGuide) {'''),
        ('''        visible: topArea.topShelfLoaded && shelfListContainer.state === "app" && !uiController.isEditMode''',
         '''        visible: !skinHome.skinActive && topArea.topShelfLoaded && shelfListContainer.state === "app" && !uiController.isEditMode'''),
        ('''    Connections {
        target: uiController

        ignoreUnknownSignals: true

        onHomeShownChanged: {''',
         LOADER + '''    Connections {
        target: uiController

        ignoreUnknownSignals: true

        onHomeShownChanged: {'''),
    ],
    "UserInterfaceLayer/UIController.qml": [
        # power-on opens the full Home and leaves it up, instead of a half
        # Home that closes itself after 8 seconds
        ('''                } else {
                    root.isAutoLaunch = true;
                    root.currentMode = "half";
                }''',
         '''                } else {
                    root.currentMode = "main";
                }'''),
        ('''                if(root.currentMode === "main") return;
                root.isAutoLaunch = true;
                root.currentMode = "half";''',
         '''                if(root.currentMode === "main") return;
                root.currentMode = "main";'''),
    ],
}

# the stock files `pear setup` needs from the TV
NEEDED = sorted(list(PATCHES) + [PEAR_SLOT])


def build(stock, out, pear_qml, fill):
    """Write the patched files and PearHome into out/, mirroring qml/."""
    if not os.path.exists(os.path.join(stock, PEAR_SLOT)):
        sys.exit(f"{PEAR_SLOT}: not on this TV, so there is nowhere to mount Pear")
    for rel, edits in PATCHES.items():
        with open(os.path.join(stock, rel), encoding="utf-8") as f:
            text = f.read()
        for old, new in edits:
            n = text.count(old)
            if n != 1:
                sys.exit(f"{rel}: this firmware's Home differs from the one Pear knows "
                         f"(expected 1 match, found {n}). Nothing was installed.")
            text = text.replace(old, new)
        write(out, rel, text)
    with open(pear_qml, encoding="utf-8") as f:
        text = f.read()
    for key, value in fill.items():
        text = text.replace(f"@{key}@", value)
    write(out, PEAR_SLOT, text)


def write(out, rel, text):
    dest = os.path.join(out, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w", encoding="utf-8") as f:
        f.write(text)
