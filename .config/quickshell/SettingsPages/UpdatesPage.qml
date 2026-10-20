import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page

    property real marginLeft: 0
    property real marginRight: 10
    property real marginTop: 0
    property real marginBottom: 0

    // ---- Terminal used for anything that needs sudo / shows output ----
    readonly property string terminal: "kitty"

    // ---- Pending update counts: -2 = checking, -1 = unavailable ----
    property int pacmanCount: -2
    property int aurCount: -2
    property int flatpakCount: -2
    property string aurHelper: ""          // "paru" | "yay" | ""

    // ---- update.sh options ----
    property bool optPull: true            // git pull the dotfiles repo first
    property bool optDryRun: false
    property bool optSkipPackages: false
    property bool optSkipTheme: false
    property bool optRestartShell: false

    property string statusText: ""

    readonly property string stateDir: Quickshell.env("HOME") + "/.config/quickshell/state"

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function countLabel(n) {
        if (n === -2) return "CHECKING…"
        if (n === -1) return "N/A"
        if (n === 0)  return "UP TO DATE"
        return n + " PENDING"
    }

    function countColor(n) {
        if (n > 0) return Theme.accent2
        return Theme.textDim
    }

    // Wrap a script so the terminal stays open until Enter is pressed.
    function inTerminal(title, script) {
        const full = script
            + "; printf '\\n\\033[1;32m[DONE]\\033[0m Press Enter to close...'; read -r _"
        return [terminal, "--title", title, "bash", "-c", full]
    }

    function run(title, script) {
        if (runner.running) {
            page.statusText = "ANOTHER UPDATE IS STILL RUNNING"
            return
        }
        page.statusText = title.toUpperCase() + " RUNNING…"
        runner.title = title
        runner.command = inTerminal(title, script)
        runner.running = true
    }

    // ---- Individual update scripts ----
    // System packages: dnf on Fedora, pacman on Arch (the "pacman" names are kept
    // so the rest of the page is unchanged)
    property bool hasDnf: false
    readonly property string pkgName: hasDnf ? "DNF" : "PACMAN"
    readonly property string pacmanScript: hasDnf ? "sudo dnf upgrade --refresh" : "sudo pacman -Syu"
    readonly property string flatpakScript: "flatpak update -y"

    function aurScript() {
        if (aurHelper === "") return "echo 'No AUR helper (paru/yay) found.'"
        return aurHelper + " -Sua"
    }

    function allScript() {
        const parts = [pacmanScript]
        if (aurHelper !== "") parts.push(aurScript())
        parts.push("if command -v flatpak >/dev/null 2>&1; then " + flatpakScript + "; fi")
        return parts.join("; ")
    }

    // Resolve the dotfiles repo by following the theme.py symlink back to the repo.
    readonly property string repoResolve:
        "REPO=\"$(dirname \"$(dirname \"$(dirname \"$(dirname \"$(readlink -f \"$HOME/.config/43pr/bin/theme.py\")\")\")\")\")\"; "
        + "cd \"$REPO\" || exit 1; "
        // Fedora port: use fedora/update.sh when present
        + "UPD=./update.sh; if command -v dnf >/dev/null 2>&1 && [ -f fedora/update.sh ]; then UPD=./fedora/update.sh; fi; "
        + "if [ ! -f \"$UPD\" ]; then echo \"$UPD not found (resolved repo: $REPO)\"; exit 1; fi; "

    function desktopScript() {
        let s = repoResolve
        if (optPull) s += "echo '--- git pull ---'; git pull --ff-only; "
        let args = []
        if (optDryRun)        args.push("--dry-run")
        if (optSkipPackages)  args.push("--skip-packages")
        if (optSkipTheme)     args.push("--skip-theme")
        if (optRestartShell)  args.push("--restart-shell")
        s += "\"$UPD\"" + (args.length ? " " + args.join(" ") : "")
        return s
    }

    // ------------------------------------------------------------------
    // Processes
    // ------------------------------------------------------------------

    Process {
        id: runner
        property string title: ""
        onExited: exitCode => {
            page.statusText = runner.title.toUpperCase() + " FINISHED"
            refreshTimer.restart()
        }
    }

    Process {
        id: helperDetect
        command: ["sh", "-c", "command -v paru >/dev/null 2>&1 && echo paru || { command -v yay >/dev/null 2>&1 && echo yay; }"]
        stdout: StdioCollector {
            onStreamFinished: {
                page.aurHelper = text.trim()
                aurCheck.running = true
            }
        }
    }

    Process {
        id: pacmanCheck
        // dnf: read-only count from cached metadata (no sudo, no refresh)
        command: ["sh", "-c", "if command -v dnf >/dev/null 2>&1; then echo dnf; dnf -q repoquery --upgrades --qf '%{name}\\n' 2>/dev/null | sed '/^$/d' | sort -u | wc -l; elif command -v checkupdates >/dev/null 2>&1; then echo pacman; checkupdates 2>/dev/null | wc -l; else echo none; echo -1; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                page.hasDnf = lines[0] === "dnf"
                const n = parseInt(lines[lines.length - 1])
                page.pacmanCount = isNaN(n) ? -1 : n
            }
        }
    }

    Process {
        id: aurCheck
        command: ["sh", "-c", page.aurHelper === "" ? "echo -1" : page.aurHelper + " -Qua 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim())
                page.aurCount = isNaN(n) ? -1 : n
            }
        }
    }

    Process {
        id: flatpakCheck
        command: ["sh", "-c", "if command -v flatpak >/dev/null 2>&1; then flatpak remote-ls --updates 2>/dev/null | wc -l; else echo -1; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim())
                page.flatpakCount = isNaN(n) ? -1 : n
            }
        }
    }

    function refresh() {
        pacmanCount = -2
        aurCount = -2
        flatpakCount = -2
        pacmanCheck.running = true
        flatpakCheck.running = true
        helperDetect.running = true     // chains into aurCheck
    }

    Timer { id: refreshTimer; interval: 500; onTriggered: page.refresh() }

    // ------------------------------------------------------------------
    // Persist update.sh options
    // ------------------------------------------------------------------

    FileView {
        id: settingsFile
        path: page.stateDir + "/updates.json"
        blockLoading: true
    }

    Process {
        id: stateDirProcess
        command: ["mkdir", "-p", page.stateDir]
    }

    function loadSettings() {
        try {
            const s = JSON.parse(settingsFile.text())
            if (typeof s.pull === "boolean")          optPull = s.pull
            if (typeof s.dryRun === "boolean")        optDryRun = s.dryRun
            if (typeof s.skipPackages === "boolean")  optSkipPackages = s.skipPackages
            if (typeof s.skipTheme === "boolean")     optSkipTheme = s.skipTheme
            if (typeof s.restartShell === "boolean")  optRestartShell = s.restartShell
        } catch (error) {}
    }

    function setOpt(key, value) {
        if (key === "pull")              optPull = value
        else if (key === "dryRun")       optDryRun = value
        else if (key === "skipPackages") optSkipPackages = value
        else if (key === "skipTheme")    optSkipTheme = value
        else if (key === "restartShell") optRestartShell = value
        saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: {
            try {
                settingsFile.setText(JSON.stringify({
                    pull: page.optPull,
                    dryRun: page.optDryRun,
                    skipPackages: page.optSkipPackages,
                    skipTheme: page.optSkipTheme,
                    restartShell: page.optRestartShell
                }, null, 2))
            } catch (error) {}
        }
    }

    // ------------------------------------------------------------------
    // Reusable inline components
    // ------------------------------------------------------------------

    component SectionTitle: Text {
        color: Theme.text
        font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeSection; font.bold: true; font.letterSpacing: 2
    }

    component GroupLabel: Text {
        color: Theme.text
        font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeGroup; font.bold: true; font.letterSpacing: 1
    }

    component Card: Rectangle {
        id: card
        default property alias contentData: cardColumn.data
        width: parent.width
        height: cardColumn.implicitHeight + 28
        radius: Theme.radius
        color: "#00000000"; border.width: 1; border.color: Theme.border

        Column {
            id: cardColumn
            x: 14; y: 14
            width: parent.width - 28
            spacing: 16
        }
    }

    component SmallButton: Rectangle {
        id: sb
        property string label: ""
        property bool current: false
        property bool buttonEnabled: true
        signal clicked()
        height: 28; radius: Theme.radius
        opacity: buttonEnabled ? 1.0 : 0.35
        color: current ? Theme.alpha(Theme.accent, 0.10) : (sbMouse.containsMouse ? Theme.alpha(Theme.accent, 0.08) : "#00000000")
        border.width: 1
        border.color: current || sbMouse.containsMouse ? Theme.accent : Theme.border

        Text {
            anchors.centerIn: parent
            text: sb.label
            color: sb.current ? Theme.accent : Theme.text
            font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeBody; font.bold: true; font.letterSpacing: 1
        }

        MouseArea {
            id: sbMouse
            anchors.fill: parent; hoverEnabled: true
            enabled: sb.buttonEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: sb.clicked()
        }
    }

    component ToggleRow: Item {
        id: tg
        property string label: ""
        property bool checked: false
        signal toggled(bool v)

        width: parent.width; height: 28

        Text {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: tg.label
            color: Theme.textDim
            font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeBody; font.letterSpacing: 1
        }

        SmallButton {
            anchors.right: parent.right
            width: 72
            label: tg.checked ? "ON" : "OFF"
            current: tg.checked
            onClicked: tg.toggled(!tg.checked)
        }
    }

    // One source row: name, pending count, UPDATE button
    component UpdateRow: Item {
        id: ur
        property string label: ""
        property string detail: ""
        property int count: -2
        property bool buttonEnabled: true
        signal run()

        width: parent.width; height: 28

        Row {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ur.label
                color: Theme.text
                font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeBody; font.bold: true; font.letterSpacing: 1
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: ur.detail.length > 0
                text: ur.detail
                color: Theme.textDim
                font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeSmall
            }
        }

        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.countLabel(ur.count)
                color: page.countColor(ur.count)
                font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeSmall
            }

            SmallButton {
                width: 90
                label: "UPDATE"
                buttonEnabled: ur.buttonEnabled && !runner.running
                onClicked: ur.run()
            }
        }
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: page.marginLeft; anchors.rightMargin: page.marginRight
        anchors.topMargin: page.marginTop; anchors.bottomMargin: page.marginBottom
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            id: scrollBar

            background: Rectangle {
                color: "transparent"
                radius: width / 2
            }
            contentItem: Rectangle {
                color: "transparent"
                radius: width / 2
            }
        }

        Column {
            id: content
            width: flick.width
            spacing: 14

            Text {
                text: "UPDATES"; color: Theme.text
                font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeTitle; font.letterSpacing: 3
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border }

            // ---------------- SYSTEM PACKAGES ----------------
            Column {
                width: parent.width; spacing: 10
                topPadding: 6

                Item {
                    width: parent.width; height: 24

                    SectionTitle {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "SYSTEM PACKAGES"
                    }

                    SmallButton {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 90; height: 24
                        label: "REFRESH"
                        onClicked: page.refresh()
                    }
                }

                Card {
                    Column {
                        width: parent.width; spacing: 10

                        UpdateRow {
                            label: page.pkgName; detail: "official repos"
                            count: page.pacmanCount
                            onRun: page.run(page.pkgName + " update", page.pacmanScript)
                        }

                        UpdateRow {
                            label: "AUR"
                            detail: page.aurHelper !== "" ? "via " + page.aurHelper : "no helper found"
                            count: page.aurCount
                            buttonEnabled: page.aurHelper !== ""
                            onRun: page.run("AUR update", page.aurScript())
                        }

                        UpdateRow {
                            label: "FLATPAK"; detail: "apps & runtimes"
                            count: page.flatpakCount
                            buttonEnabled: page.flatpakCount !== -1
                            onRun: page.run("Flatpak update", page.flatpakScript)
                        }
                    }

                    Column {
                        width: parent.width; spacing: 8

                        GroupLabel { text: "EVERYTHING" }

                        SmallButton {
                            width: parent.width
                            label: page.hasDnf ? "UPDATE ALL (DNF + FLATPAK)" : "UPDATE ALL (PACMAN + AUR + FLATPAK)"
                            buttonEnabled: !runner.running
                            onClicked: page.run("Full system update", page.allScript())
                        }
                    }
                }
            }

            // ---------------- DESKTOP SETUP ----------------
            Column {
                width: parent.width; spacing: 10
                topPadding: 6
                bottomPadding: 6

                SectionTitle { text: "DESKTOP" }

                Card {
                    Column {
                        width: parent.width; spacing: 8

                        GroupLabel { text: "UPDATE.SH OPTIONS" }

                        ToggleRow {
                            label: "GIT PULL FIRST"; checked: page.optPull
                            onToggled: v => page.setOpt("pull", v)
                        }
                        ToggleRow {
                            label: "DRY RUN"; checked: page.optDryRun
                            onToggled: v => page.setOpt("dryRun", v)
                        }
                        ToggleRow {
                            label: "SKIP PACKAGES"; checked: page.optSkipPackages
                            onToggled: v => page.setOpt("skipPackages", v)
                        }
                        ToggleRow {
                            label: "SKIP THEME"; checked: page.optSkipTheme
                            onToggled: v => page.setOpt("skipTheme", v)
                        }
                        ToggleRow {
                            label: "RESTART QUICKSHELL"; checked: page.optRestartShell
                            onToggled: v => page.setOpt("restartShell", v)
                        }
                    }

                    Column {
                        width: parent.width; spacing: 8

                        SmallButton {
                            width: parent.width
                            label: page.optDryRun ? "RUN UPDATE.SH (DRY RUN)" : "UPDATE DESKTOP"
                            buttonEnabled: !runner.running
                            onClicked: page.run("Desktop setup update", page.desktopScript())
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Links new dotfiles, installs new packages.txt entries and regenerates the theme."
                            color: Theme.textDim
                            font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeSmall
                        }
                    }
                }

                Text {
                    visible: page.statusText.length > 0
                    text: page.statusText
                    color: Theme.accent2
                    font.family: Theme.fontFamily; font.pixelSize: Theme.textSizeSmall; font.letterSpacing: 1
                }
            }
        }
    }

    Component.onCompleted: {
        stateDirProcess.running = true
        loadSettings()
        refresh()
    }
}