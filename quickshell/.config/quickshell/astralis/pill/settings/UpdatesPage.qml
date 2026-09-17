pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 更 UPDATES settings page (ported from Ricelin pill/Updates.qml):
 * the status hero row — badge circle, headline, count subline — over a
 * scrollable pending list, with a full-width check button at the bottom.
 *
 * Ricelin delta: Ricelin fronts its own rice-update engine
 * (ricelin-update.py check/apply — changelog, conflict merges, dep installs,
 * shell restart). astralis is a plain Arch dotfiles rig with no engine, so
 * this page checks PACKAGE updates instead: `checkupdates` (pacman-contrib,
 * repo — a safe dry-run against a temp db) plus the AUR helper's `-Qua` when
 * one is present, each degrading to a calm note when the tool is absent.
 * READ-ONLY on purpose: the shell never installs — the pending list is a
 * heads-up, the upgrade itself belongs to a terminal (pacman / yay). Checks
 * run once per pill session on first open; the button re-runs on demand.
 */
SettingsPage {
    id: root

    rows: []

    property bool checking: false
    property bool checkedOnce: false
    property bool repoDone: false
    property bool aurDone: false

    /** Tool presence, learned from the check itself (@notool / @nohelper markers). */
    property bool repoTool: true
    property bool aurHelper: true

    property var repoList: []
    property var aurList: []

    readonly property var updates: repoList.concat(aurList)
    readonly property bool behind: !checking && updates.length > 0
    readonly property bool upToDate: !checking && checkedOnce && repoTool && updates.length === 0

    readonly property string badgeIcon: root.behind ? "arrow-up"
        : !root.repoTool ? "download"
        : "check"

    readonly property color badgeTint: root.behind || root.upToDate
        ? Colors.primary : Colors.on_surface_variant

    readonly property string headline: root.checking ? "Checking…"
        : !root.repoTool ? "checkupdates not installed"
        : root.behind ? (root.updates.length + " update" + (root.updates.length === 1 ? "" : "s") + " pending")
        : root.upToDate ? "Up to date"
        : "Updates"

    /** A line beneath the headline that orients each state, dropped when empty. */
    readonly property string subline: root.checking ? ""
        : !root.repoTool ? "pacman-contrib provides the repo check; without it this page can only shrug."
        : root.behind ? ("repo " + root.repoList.length
            + (root.aurHelper ? " · AUR " + root.aurList.length : " · AUR not checked (no helper)"))
        : root.upToDate && !root.aurHelper ? "AUR not checked — no yay/paru found"
        : ""

    function check() {
        if (root.checking)
            return;
        root.checking = true;
        root.repoDone = false;
        root.aurDone = false;
        repoProc.running = true;
        aurProc.running = true;
    }

    function settle() {
        if (root.repoDone && root.aurDone) {
            root.checking = false;
            root.checkedOnce = true;
        }
    }

    /** "name oldver -> newver" lines → [{name, from, to, aur}]. */
    function parseLines(text, aur) {
        var out = [];
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var t = lines[i].trim();
            if (t.length === 0)
                continue;
            var p = t.split(/\s+/);
            if (p.length >= 4 && p[2] === "->")
                out.push({ name: p[0], from: p[1], to: p[3], aur: aur });
            else
                out.push({ name: t, from: "", to: "", aur: aur });
        }
        return out;
    }

    onActiveChanged: if (active && !checkedOnce && !checking) check()

    Process {
        id: repoProc
        command: ["sh", "-c",
            "if command -v checkupdates >/dev/null 2>&1; then checkupdates 2>/dev/null; else echo @notool; fi; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text;
                if (t.trim() === "@notool") {
                    root.repoTool = false;
                    root.repoList = [];
                } else {
                    root.repoTool = true;
                    root.repoList = root.parseLines(t, false);
                }
                root.repoDone = true;
                root.settle();
            }
        }
    }

    Process {
        id: aurProc
        command: ["sh", "-c",
            "h=$(command -v yay paru 2>/dev/null | head -n1); "
            + "if [ -n \"$h\" ]; then \"$h\" -Qua 2>/dev/null; else echo @nohelper; fi; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text;
                if (t.trim() === "@nohelper") {
                    root.aurHelper = false;
                    root.aurList = [];
                } else {
                    root.aurHelper = true;
                    root.aurList = root.parseLines(t, true);
                }
                root.aurDone = true;
                root.settle();
            }
        }
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "更"
        title: "UPDATES"
        onBack: root.back()
    }

    // ── hero: badge + headline + subline (Ricelin's status row) ─────────────
    Row {
        id: hero
        anchors.top: header.bottom
        anchors.topMargin: 14 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 4 * root.s
        anchors.rightMargin: 4 * root.s
        spacing: 12 * root.s

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 34 * root.s
            height: 34 * root.s
            radius: width / 2
            color: Qt.alpha(root.badgeTint, 0.16)

            GlyphIcon {
                anchors.centerIn: parent
                visible: !root.checking
                width: 17 * root.s
                height: 17 * root.s
                name: root.badgeIcon
                color: root.badgeTint
                stroke: 2.2
            }

            GlyphIcon {
                anchors.centerIn: parent
                visible: root.checking
                width: 16 * root.s
                height: 16 * root.s
                name: "reboot"
                color: root.badgeTint
                stroke: 2

                RotationAnimation on rotation {
                    running: root.checking && !Motion.reduceMotion
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    // Indeterminate spin rate, not any settle/entrance token —
                    // `running` already excludes reduceMotion, but the literal
                    // still owes the ×mult contract so it stays correct if that
                    // gate ever loosens.
                    duration: Math.round(900 * Motion.mult)
                }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 34 * root.s - 12 * root.s
            spacing: 3 * root.s

            Text {
                text: root.headline
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 14.5 * root.s
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                visible: root.subline.length > 0
                text: root.subline
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                lineHeight: 1.2
                font.features: ({ "tnum": 1 })
            }
        }
    }

    Text {
        id: pendingLabel
        anchors.top: hero.bottom
        anchors.left: parent.left
        visible: root.behind
        height: visible ? implicitHeight : 0
        topPadding: 14 * root.s
        bottomPadding: 6 * root.s
        leftPadding: 12 * root.s
        text: "Pending"
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 8.5 * root.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2 * root.s
    }

    ListView {
        id: list
        anchors.top: pendingLabel.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: note.top
        anchors.bottomMargin: 6 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.updates

        delegate: Item {
            id: urow
            required property int index
            required property var modelData

            width: ListView.view.width
            height: 26 * root.s

            // The pending list arrives as a unit each time a check finishes
            // (not per-keystroke, so the cascade never gets re-triggered by
            // typing) — same short wave as SettingsRow's entrance.
            property bool entered: false
            Timer {
                interval: Motion.rowStagger * Math.min(urow.index, 10)
                running: true
                onTriggered: urow.entered = true
            }
            opacity: urow.entered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            transform: Translate {
                y: urow.entered ? 0 : 10 * root.s
                Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            }

            // Read-only line — this page never installs, so there is no press
            // action, only a name and the version jump to announce (nothing
            // numeric enough to need `description` as a range; `Accessible.value`
            // doesn't exist regardless, see quickshell-core.md §9b).
            Accessible.role: Accessible.ListItem
            Accessible.name: urow.modelData.name
            Accessible.description: (urow.modelData.aur ? "AUR update" : "Repository update")
                + (urow.modelData.to.length > 0 ? ", " + urow.modelData.from + " to " + urow.modelData.to : "")
            Accessible.readOnly: true

            Rectangle {
                anchors.fill: parent
                radius: 7 * root.s
                color: urowArea.containsMouse ? Colors.surface_container_highest : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            MouseArea {
                id: urowArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            Row {
                id: nameRow
                anchors.left: parent.left
                anchors.leftMargin: 12 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: urow.modelData.name
                    color: Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 11.5 * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: urow.modelData.aur
                    width: aurTag.implicitWidth + 10 * root.s
                    height: aurTag.implicitHeight + 4 * root.s
                    radius: 5 * root.s
                    color: Qt.alpha(Colors.tertiary, 0.16)

                    Text {
                        id: aurTag
                        anchors.centerIn: parent
                        text: "AUR"
                        color: Colors.tertiary
                        font.family: Appearance.font.family
                        font.pixelSize: 7.5 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8 * root.s
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12 * root.s
                anchors.left: nameRow.right
                anchors.leftMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                visible: urow.modelData.to.length > 0
                text: urow.modelData.from + " → " + urow.modelData.to
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                font.features: ({ "tnum": 1 })
                elide: Text.ElideLeft
            }
        }
    }

    Text {
        id: note
        anchors.bottom: checkBtn.top
        anchors.bottomMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 4 * root.s
        anchors.rightMargin: 4 * root.s
        visible: root.behind
        height: visible ? implicitHeight : 0
        text: "Read-only — install from a terminal (pacman -Syu / yay)."
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 9.5 * root.s
        font.weight: Font.Medium
        wrapMode: Text.WordWrap
    }

    // ── the check button (Ricelin's full-width checkBtn) ────────────────────
    Rectangle {
        id: checkBtn
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34 * root.s
        radius: 10 * root.s
        color: Qt.alpha(Colors.primary, checkArea.containsMouse && !root.checking ? 0.30 : 0.16)
        border.width: 1
        border.color: Qt.alpha(Colors.primary, checkArea.containsMouse && !root.checking ? 0.6 : 0.4)
        opacity: root.checking ? 0.55 : 1
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        scale: (checkArea.pressed && !root.checking) ? 0.98 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: "Check for updates"
        Accessible.description: root.checking ? "Checking for updates" : root.headline
        Accessible.focusable: !root.checking
        Accessible.onPressAction: root.check()

        MouseArea {
            id: checkArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !root.checking
            cursorShape: Qt.PointingHandCursor
            onClicked: root.check()
        }

        Text {
            anchors.centerIn: parent
            text: root.checking ? "Checking…" : "Check for updates"
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 11.5 * root.s
            font.weight: Font.DemiBold
        }
    }
}
