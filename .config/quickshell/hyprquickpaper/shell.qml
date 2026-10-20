import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell.Wayland

PanelWindow {
    id: main
    readonly property real ui: Screen.height / 1080
    readonly property real refWidth: 1920
    readonly property real refHeight: 500
    property int speed: 5000
    property int animDuration: 1000
    property real zoomScale: 0.8
    property real edgeScale: 0.3
    property real skewFactor: 0
    property real baseSpacing: 0
    property real edgeSpacing: 80
    property int startPosition: -1   // -1 = open on the current wallpaper (else the middle one)
    property bool shadowEnabled: true
    property color shadowColor: "#000000"
    property real shadowOpacity: 0.4
    property real shadowBlur: 0.45
    property real shadowX: 6
    property real shadowY: 6
    property string wallpaperPath: configs.wallpaper_path.replace("$HOME", Quickshell.env("HOME"))
    property string cachePath: configs.cache_path.replace("$HOME", Quickshell.env("HOME"))

    readonly property color highlightColor:
        (configs.border_color && configs.border_color !== "transparent") ? configs.border_color : "#e6ffffff"

    property bool showEmpty: false
    readonly property bool looksEmpty: wallpaperPath !== ""
                                       && folderModel.status === FolderListModel.Ready
                                       && folderModel.count === 0

    onLooksEmptyChanged: {
        if (looksEmpty) {
            emptyDelay.restart()
        } else {
            emptyDelay.stop()
            showEmpty = false
        }
    }

    implicitHeight: Screen.height
    implicitWidth: Screen.width
    color: "transparent"
    aboveWindows: true
    exclusionMode: "Ignore"
    exclusiveZone: 1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Component.onCompleted: Quickshell.execDetached(["bash", Quickshell.shellPath("cache.sh"), Quickshell.shellDir])

    FileView {
        path: Quickshell.shellPath("config.json")
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: configs
            property string wallpaper_path
            property string cache_path
            property int number_of_pictures
            property string border_color
        }
    }

    // Current wallpaper (written by theme.py), so the picker opens centered on it
    property string currentWallpaper: ""
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/43pr/state.json"
        onLoaded: {
            try { main.currentWallpaper = JSON.parse(text()).wallpaper || "" } catch (e) {}
            list.centerOnStart()
        }
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + main.wallpaperPath
        showDirs: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        sortField: FolderListModel.Name
    }

    MouseArea {
        id: outsideClickArea
        anchors.fill: parent
        z: 0
        onClicked: Qt.quit()
    }

    Timer {
        id: emptyDelay
        interval: 300
        onTriggered: main.showEmpty = main.looksEmpty
    }

    Column {
        id: emptyState
        anchors.centerIn: parent
        spacing: 10 * main.ui
        z: 2
        visible: main.showEmpty

        Text {
            text: "No wallpapers found"
            color: "#ffffff"
            font.pixelSize: 22 * main.ui
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: "Add images to:"
            color: "#aaaaaa"
            font.pixelSize: 13 * main.ui
            anchors.horizontalCenter: parent.horizontalCenter
        }

        TextEdit {
            id: pathText
            text: main.wallpaperPath
            color: "#dddddd"
            font.pixelSize: 14 * main.ui
            readOnly: true
            selectByMouse: true
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
        }
    }

    ListView {
        id: list
        width: parent.width
        height: tileHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        z: 1
        focus: true
        model: folderModel
        orientation: ListView.Horizontal
        spacing: 0
        clip: true
        interactive: false   // position only changes through the selection (keys, wheel, click)
        cacheBuffer: 400 * main.ui
        boundsBehavior: Flickable.StopAtBounds

        property int selectedIndex: main.startPosition

        readonly property real tileHeight: main.refHeight * main.ui
        readonly property real tileWidth: (main.refWidth / Math.max(1, configs.number_of_pictures) - 10) * main.ui

        readonly property real viewportCenterX: width / 2
        readonly property real falloffRadius: (main.refWidth / 2) * main.ui

        readonly property real step: tileWidth + main.baseSpacing * main.ui
        readonly property real sideMargin: Math.max(0, viewportCenterX - tileWidth / 2)
        property bool ready: false
        property bool userMoved: false

        leftMargin: sideMargin
        rightMargin: sideMargin

        function clampIndex(i) { return Math.max(0, Math.min(i, count - 1)) }
        // contentX that puts tile i in the middle of the screen. With leftMargin
        // = sideMargin, tile 0 is centered at contentX = -sideMargin (the left
        // bound). Upstream used i * step, which put the selected tile at the
        // left edge and made the first tiles unreachable.
        function centerX(i) { return originX + i * step - sideMargin }
        function ensureVisibleAnimated(i) { contentX = centerX(i) }

        function startIndex() {
            if (main.startPosition >= 0) return clampIndex(main.startPosition)
            if (main.currentWallpaper !== "") {
                // match by file name: state.json holds a resolved path, which
                // differs from the model's if ~/Pictures is a symlink
                const name = main.currentWallpaper.split("/").pop()
                for (let i = 0; i < folderModel.count; i++)
                    if (folderModel.get(i, "fileName") === name) return i
            }
            return Math.floor((count - 1) / 2)
        }

        function centerOnStart() {
            if (userMoved || count <= 0 || configs.number_of_pictures <= 0) return
            selectedIndex = startIndex()
            ready = false              // jump there, don't animate the opening
            contentX = centerX(selectedIndex)
            readyTimer.restart()
        }
        Timer { id: readyTimer; interval: 50; onTriggered: list.ready = true }

        // Touchpads send many small wheel events; step one tile per notch-worth
        property real wheelAcc: 0
        function wheelStep(delta) {
            wheelAcc += delta
            if (Math.abs(wheelAcc) >= 120) {
                const n = wheelAcc > 0 ? -1 : 1
                wheelAcc = 0
                userMoved = true
                moveSelection(n, 1)
            }
        }

        function activateCurrent() {
            Quickshell.execDetached(["bash", Quickshell.shellPath("commands.sh"), folderModel.get(selectedIndex, "filePath")])
            Qt.quit()
        }

        function moveSelection(delta, speedMultiplier) {
            anim.velocity = main.speed * speedMultiplier
            selectedIndex = clampIndex(selectedIndex + delta)
            ensureVisibleAnimated(selectedIndex)
        }

        onCountChanged: centerOnStart()
        onWidthChanged: centerOnStart()
        onTileWidthChanged: centerOnStart()

        Connections {
            target: configs
            function onNumber_of_picturesChanged() { list.centerOnStart() }
        }

        // Fixed-duration move per step: every press feels the same. The old
        // velocity-based animation plus hover-to-select made jumps uneven.
        Behavior on contentX {
            enabled: list.ready
            NumberAnimation { id: anim; property real velocity: 0; duration: 220; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: delegateItem
            width: list.tileWidth
            height: list.tileHeight

            property bool active: index === list.selectedIndex
            readonly property real baseWidth: list.tileWidth
            readonly property real baseCenterX: x - list.contentX + baseWidth / 2
            readonly property real distance: Math.abs(baseCenterX - list.viewportCenterX)
            readonly property real fraction: Math.min(1, distance / list.falloffRadius)
            readonly property real compression: { const t = fraction; return t * t * t * t }
            readonly property real edgeOffset: {
                const amount = main.edgeSpacing * main.ui * compression
                return baseCenterX < list.viewportCenterX ? amount : -amount
            }
            readonly property real scaleFactor: {
                const t = 1 - fraction * fraction * (3 - 2 * fraction)
                return main.edgeScale + (main.zoomScale - main.edgeScale) * t
            }

            Item {
                id: content
                anchors.verticalCenter: parent.verticalCenter
                width: delegateItem.baseWidth * delegateItem.scaleFactor
                height: delegateItem.height * Math.min(1, delegateItem.scaleFactor)
                x: (delegateItem.baseWidth - width) / 2 + delegateItem.edgeOffset

                Image {
                    id: shadowImage
                    x: main.shadowX * main.ui
                    y: main.shadowY * main.ui
                    width: parent.width
                    height: parent.height
                    source: img.source
                    // Blurred black silhouette: decode and render it small. Full-size
                    // per-tile blur re-rendered every frame while scrolling = lag.
                    sourceSize.width: Math.max(1, img.sourceSize.width / 4)
                    sourceSize.height: Math.max(1, img.sourceSize.height / 4)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    visible: main.shadowEnabled
                    opacity: main.shadowOpacity
                    layer.enabled: true
                    layer.textureSize: Qt.size(Math.max(1, Math.round(width / 4)), Math.max(1, Math.round(height / 4)))
                    layer.effect: MultiEffect { brightness: -1; blurEnabled: true; blur: main.shadowBlur; blurMax: 16 }
                    transform: Shear { xFactor: main.skewFactor }
                }

                Text {
                    id: alt
                    text: ""
                    color: main.highlightColor
                    anchors.centerIn: parent
                    font.pixelSize: 16 * main.ui
                    transform: Shear { xFactor: main.skewFactor }
                }

                Image {
                    id: img
                    anchors.fill: parent
                    opacity: delegateItem.active ? 1 : 0.55
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    source: "file://" + main.cachePath + fileName
                    sourceSize.width: delegateItem.baseWidth * main.zoomScale
                    sourceSize.height: delegateItem.height
                    transform: Shear { xFactor: main.skewFactor }

                    // Thumbnail not made yet: retry with backoff (1s, 2s, 3s... max 5s),
                    // give up after ~1 min instead of reloading every tile every second.
                    property int retries: 0
                    Timer {
                        id: retryTimer
                        interval: Math.min(5000, 1000 * (img.retries + 1))
                        repeat: false
                        onTriggered: { img.retries++; const s = img.source; img.source = ""; img.source = s }
                    }

                    onStatusChanged: {
                        if (status === Image.Ready) { alt.text = "" }
                        else if (status === Image.Error) {
                            if (img.retries < 15) { alt.text = "Caching"; retryTimer.start() }
                            else alt.text = "No thumbnail"
                        }
                    }
                }

                Rectangle {
                    z: 10
                    anchors.fill: parent
                    anchors.margins: -Math.round(4 * main.ui)
                    opacity: delegateItem.active ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    color: "transparent"
                    border.width: Math.max(2, Math.round(2 * main.ui))
                    border.color: main.highlightColor
                    transform: Shear { xFactor: main.skewFactor }
                }

                // file name under the selected tile
                Text {
                    anchors.top: parent.bottom
                    anchors.topMargin: Math.round(12 * main.ui)
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(parent.width, 220 * main.ui)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: fileName
                    color: main.highlightColor
                    font.pixelSize: Math.round(12 * main.ui)
                    opacity: delegateItem.active ? 0.9 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }

            // Click a tile to select it, click the selected one to apply.
            // No hover-select: tiles sliding under the cursor kept changing the
            // selection mid-move, so the next arrow press jumped from there.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    list.userMoved = true
                    if (index === list.selectedIndex) list.activateCurrent()
                    else list.moveSelection(index - list.selectedIndex, 1)
                }
                onWheel: function(wheel) {
                    const d = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y) ? -wheel.angleDelta.x : wheel.angleDelta.y
                    list.wheelStep(d)
                    wheel.accepted = true
                }
            }
        }

        Keys.onPressed: function(event) {
            const fast = (event.modifiers & Qt.ShiftModifier) ? 3 : 1
            if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_D) {
                userMoved = true; moveSelection(fast, 1)
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_A) {
                userMoved = true; moveSelection(-fast, 1)
            } else if (event.key === Qt.Key_Home) {
                userMoved = true; moveSelection(-count, 3)
            } else if (event.key === Qt.Key_End) {
                userMoved = true; moveSelection(count, 3)
            } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                activateCurrent()
            } else if (event.key === Qt.Key_W || event.key === Qt.Key_Escape) {
                Qt.quit()
            } else {
                return
            }
            event.accepted = true
        }
    }
}