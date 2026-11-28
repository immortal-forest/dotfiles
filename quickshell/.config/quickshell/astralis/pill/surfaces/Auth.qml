pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../m3"
import "../../colors"
import "../../services"
import "../../config"

/**
 * 認 AUTH — every secret the shell is asked for outside the lock screen,
 * grown out of the pill:
 *
 *  - polkit (services/PolkitAuth.qml): pkexec, systemd, package managers.
 *  - GnuPG (services/Pinentry.qml ← ~/.local/bin/pinentry-astralis): key
 *    passphrases, plus pinentry's CONFIRM / MESSAGE dialogs. Shown as 鍵.
 *  - gnome-keyring, through the same pinentry (fed by
 *    ~/.local/bin/astralis-keyring-prompter, system/keyring-prompter):
 *    keyring unlock / new-password prompts. 鍵 too, KEYRING as the meta.
 *
 * shell.qml opens this surface on the focused screen while either has a
 * request, and closes it when the request completes. Enter answers, Esc (or
 * closing the surface any other way) cancels.
 *
 * The anatomy is the lock screen's, at surface scale: the kanji header
 * (who is asking as plain caps meta, no chip), the request as type, ONE
 * capsule — Ame as its leading mark just outside, the password as dots and
 * sumi dabs (pill/PassDots.qml), 開 trailing as the submit key — and
 * one quiet hint line. No buttons: Enter / 開 answers, Esc / the backdrop
 * cancels; only GnuPG's CONFIRM/MESSAGE dialogs get stadium buttons. A
 * rejection shakes the capsule, stains it, drops the dots and puts the
 * message where they were.
 *
 * The password lives in the hidden TextInput only. It goes to the service on
 * submit and the input is cleared on submit, on close and on a new prompt.
 */
PillSurface {
    id: root

    // The bead is the field's leading mark, just outside the capsule — the
    // lock screen's grammar (bead · capsule · 開) and SearchField's (mark ·
    // field). Not inside: Ame paints under the surfaces, the capsule would
    // hide it. It flares to a wicked soul while the answer is checked.
    ameForm: open ? (root.busy ? "soul" : "dock") : "off"
    amePoint: {
        void capsule.width;
        void column.y;
        void fieldWrap.y;
        const p = capsule.mapToItem(root, -15 * s, capsule.height / 2);
        return root.wantsPin ? p : Qt.point(width / 2, height - 5 * s);
    }

    objectName: "authSurface"

    // ── the request, whichever service it came from ─────────────────────
    /** Not readonly only so a dev harness can hand it a stand-in flow. */
    property var flow: PolkitAuth.flow
    readonly property bool polkitLive: PolkitAuth.active || PolkitAuth.accepted
    /** Polkit said yes: one beat of the run merging into a bar before the surface closes. */
    readonly property bool accepted: kind === "polkit" && PolkitAuth.accepted
    readonly property bool gpgLive: Pinentry.active || Pinentry.lingering
    /** Latched so the surface keeps its face while it fades out. */
    property string kind: "polkit"
    onPolkitLiveChanged: if (polkitLive) kind = "polkit"
    onGpgLiveChanged: if (gpgLive && !polkitLive) kind = "gpg"
    readonly property bool isGpg: kind === "gpg"
    /** A gnome-keyring prompt, carried by the pinentry service. */
    readonly property bool isKeyring: isGpg && Pinentry.source === "keyring"
    /** "pin" | "confirm" | "message" */
    readonly property string mode: isGpg ? Pinentry.mode : "pin"
    readonly property bool wantsPin: mode === "pin"

    /** Polkit: submitted and waiting for PAM. GnuPG: sent, gpg-agent is checking it. */
    readonly property bool busy: isGpg
        ? (Pinentry.lingering && !Pinentry.active)
        : (root.flow !== null && !root.flow.isCompleted && !root.flow.isResponseRequired)

    /** Second entry of a new passphrase (SETREPEAT). */
    property bool repeating: false
    property string firstPin: ""
    property bool repeatMismatch: false

    readonly property var descLines: {
        const d = String(Pinentry.desc || "").trim();
        return d.length ? d.split(/\n+/).map(l => l.trim()).filter(l => l.length) : [];
    }

    // gnome-keyring: desc is "message\ndescription". The message is often
    // just "Authentication required"; then the title ("Unlock Keyring") is
    // the better headline, in sentence case.
    readonly property string keyringHead: {
        const d = String(Pinentry.desc || "");
        const i = d.indexOf("\n");
        const head = (i < 0 ? d : d.slice(0, i)).trim().replace(/\.$/, "");
        if (head.length && !/^authentication required$/i.test(head))
            return head;
        const t = String(Pinentry.title || "").trim();
        return t.length ? t.charAt(0) + t.slice(1).toLowerCase() : "Unlock keyring";
    }
    readonly property string keyringBody: {
        const d = String(Pinentry.desc || "");
        const i = d.indexOf("\n");
        return i < 0 ? "" : d.slice(i + 1).replace(/\s*\n\s*/g, " ").trim().replace(/\.$/, "");
    }

    readonly property string message: {
        if (root.isKeyring)
            return root.keyringHead;
        if (root.isGpg) {
            if (root.descLines.length === 0)
                return root.mode === "pin" ? "Enter the passphrase" : "GnuPG needs an answer";
            let m = root.descLines[0].replace(/:\s*$/, "");
            const short = m.replace(/^please enter (the |your )?(passphrase|pin|password) to /i, "");
            if (short !== m)
                m = short.charAt(0).toUpperCase() + short.slice(1);
            return m;
        }
        if (!root.flow)
            return "";
        let m = String(root.flow.message || "").trim();
        const short = m.replace(/^authentication is required (in order )?to /i, "");
        if (short !== m)
            m = short.charAt(0).toUpperCase() + short.slice(1);
        return m.replace(/\.$/, "");
    }

    /** GnuPG: the key's user id, unquoted — the thing you'd recognise. */
    readonly property string detailLead: root.isGpg && !root.isKeyring && root.descLines.length > 1
        ? root.descLines[1].replace(/^"(.*)"$/, "$1") : ""
    readonly property string detail: {
        if (root.isKeyring)
            return root.keyringBody;
        if (root.isGpg)
            return root.descLines.slice(2).join(" ");
        // Who you are proving to be. The action id is for logs, not people.
        const who = root.flow ? PolkitAuth.identityName(root.flow.selectedIdentity) : "";
        return who.length ? "as " + who : "";
    }

    readonly property string promptText: {
        let p = "";
        if (root.isGpg)
            p = root.repeating ? (Pinentry.repeatPrompt || "Repeat") : (Pinentry.prompt || "Passphrase");
        else
            p = root.flow && root.flow.inputPrompt ? root.flow.inputPrompt : "Password";
        return p.replace(/:\s*$/, "").replace(/_/g, "");
    }

    readonly property string errorText: {
        if (root.isGpg) {
            if (root.repeatMismatch)
                return (Pinentry.repeatError || "Those don't match — try again").replace(/_/g, "");
            return Pinentry.error;
        }
        return root.flow && root.flow.supplementaryIsError ? root.flow.supplementaryMessage : "";
    }
    readonly property string infoText: !root.isGpg && root.flow && !root.flow.supplementaryIsError
        ? root.flow.supplementaryMessage : ""
    readonly property bool showError: root.errorText.length > 0 && !root.busy

    readonly property string identity: root.isGpg ? ""
        : (root.flow ? PolkitAuth.identityName(root.flow.selectedIdentity) : "")

    // What the hero shows, latched: after a success polkit drops the flow
    // while the surface is still playing its accepted beat.
    property string showMessage: ""
    property string showDetail: ""
    property string showLead: ""
    property string showIdentity: ""
    onMessageChanged: if (message.length) showMessage = message
    onDetailChanged: if (detail.length || !root.accepted) showDetail = detail
    onDetailLeadChanged: if (detailLead.length || !root.accepted) showLead = detailLead
    onIdentityChanged: if (identity.length) showIdentity = identity

    readonly property bool canSubmit: root.wantsPin && !root.busy && input.text.length > 0
        && (root.isGpg ? Pinentry.active : (root.flow !== null && root.flow.isResponseRequired))

    function clean(label, fallback) {
        const l = String(label || "").replace(/_/g, "").trim();
        return l.length ? l : fallback;
    }

    // ── answering ───────────────────────────────────────────────────────
    function submit() {
        if (!root.canSubmit)
            return;
        const pw = input.text;
        if (root.isGpg && Pinentry.repeat && !root.repeating) {
            root.firstPin = pw;
            root.repeating = true;
            root.repeatMismatch = false;
            input.text = "";
            return;
        }
        if (root.isGpg && root.repeating && pw !== root.firstPin) {
            root.firstPin = "";
            root.repeating = false;
            root.repeatMismatch = true;
            root.dotLen = pw.length;
            input.text = "";
            failHold.restart();
            shake.restart();
            return;
        }
        // Hold the run on screen while the answer is checked: the busy wave
        // rides the shapes the user just typed.
        root.dotLen = pw.length;
        root.holding = true;
        input.text = "";
        root.firstPin = "";
        if (root.isGpg)
            Pinentry.submit(pw);
        else
            PolkitAuth.submit(pw);
    }

    function answer(ok) {
        if (!root.isGpg)
            return;
        if (ok) Pinentry.confirm(); else Pinentry.cancel();
    }

    function resetEntry() {
        input.text = "";
        root.firstPin = "";
        root.repeating = false;
        root.repeatMismatch = false;
        root.holding = false;
        failHold.stop();
        root.dotLen = 0;
    }

    // ── entrance: hero, field and answers rise in on a stagger ─────────
    // (the header arrives with the pill body itself, via PillSurface)
    property real enterT: 1
    readonly property int enterDelay: Math.round(70 * Motion.mult)
    readonly property int enterDur: Motion.normalDur
    readonly property int enterTotal: enterDelay + 2 * Motion.cascadeStep + enterDur
    NumberAnimation {
        id: enterAnim
        target: root; property: "enterT"; from: 0; to: 1
        duration: root.enterTotal
        // linear clock on purpose: each row eases its own slice of it (rowIn)
        easing.type: Motion.easeClock
    }
    function rowIn(k) {
        const t = (root.enterT * root.enterTotal - root.enterDelay - k * Motion.cascadeStep) / root.enterDur;
        return Motion.ease(Math.max(0, Math.min(1, t)), Motion.emphasizedDecel);
    }

    onOpenChanged: {
        resetEntry();
        if (open) {
            if (Motion.reduceMotion) root.enterT = 1;
            else enterAnim.restart();
            Qt.callLater(() => input.forceActiveFocus());
        } else {
            // Closed by the user (Esc, the backdrop, another surface): that's a no.
            if (PolkitAuth.active)
                PolkitAuth.cancel();
            if (Pinentry.active)
                Pinentry.cancel();
        }
    }

    // ── what the shapes show (held through a check and a rejection) ─────
    property int dotLen: 0
    property bool holding: false
    Timer {
        id: failHold
        interval: Math.round(420 * Motion.mult)
        onTriggered: {
            root.holding = false;
            root.dotLen = input.text.length;
        }
    }
    function rejected() {
        if (root.dotLen > 0) {
            failHold.restart();
        } else {
            root.holding = false;
        }
        shake.restart();
        Qt.callLater(() => input.forceActiveFocus());
    }

    Connections {
        target: root.flow
        // A fresh prompt (after a wrong password): empty field, focus back in it.
        function onIsResponseRequiredChanged() {
            if (root.flow && root.flow.isResponseRequired) {
                input.text = "";
                if (root.flow.supplementaryIsError)
                    root.rejected();
                else {
                    root.holding = false;
                    root.dotLen = 0;
                }
                Qt.callLater(() => input.forceActiveFocus());
            }
        }
    }
    Connections {
        target: Pinentry
        // gpg-agent's retry is a brand-new request carrying SETERROR.
        function onSerialChanged() {
            const wasHolding = root.holding;
            input.text = "";
            root.repeating = false;
            root.firstPin = "";
            root.repeatMismatch = false;
            if (Pinentry.error.length > 0 && wasHolding)
                root.rejected();
            else {
                root.holding = false;
                root.dotLen = 0;
            }
            Qt.callLater(() => input.forceActiveFocus());
        }
    }

    readonly property bool echoPlain: !root.isGpg && root.flow !== null && root.flow.responseVisible
    property bool capsLock: false

    desiredH: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: 0

        // ── header: 認 AUTHENTICATE ··························· POLKIT ──
        // The surface's one mark is the kanji; who is asking is plain meta
        // text in the header's own caps, like 系's uptime.
        Item {
            width: parent.width
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: root.isGpg ? "鍵" : "認"
                    color: Colors.on_surface
                    font.family: Appearance.font.jp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: !root.isGpg ? "AUTHENTICATE"
                        : root.mode !== "pin" ? "CONFIRM"
                        : (root.repeating ? "CONFIRM " : "") + (root.isKeyring ? "PASSWORD" : "PASSPHRASE")
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.6 * root.s
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.isKeyring ? "KEYRING" : root.isGpg ? "GNUPG" : "POLKIT"
                color: Qt.alpha(Colors.on_surface_variant, 0.6)
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 1.6 * root.s
            }
        }

        Item { width: 1; height: 14 * root.s }

        // ── the request, as type ────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 4 * root.s
            opacity: root.rowIn(0)
            transform: Translate { y: (1 - root.rowIn(0)) * 10 * root.s }

            Text {
                width: parent.width
                text: root.showMessage
                color: Colors.on_surface
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Appearance.font.family
                font.pixelSize: 15 * root.s
                font.weight: Font.DemiBold
                lineHeight: 1.1
            }
            Text {
                width: parent.width
                text: root.showLead
                visible: text.length > 0
                color: Colors.on_surface
                elide: Text.ElideRight
                font.family: Appearance.font.family
                font.pixelSize: 11 * root.s
                font.weight: Font.Medium
            }
            Text {
                width: parent.width
                text: root.showDetail
                visible: text.length > 0
                color: Qt.alpha(Colors.on_surface_variant, 0.85)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Medium
            }
        }

        Item { width: 1; height: 18 * root.s }

        // ── the capsule: bead · password · 開 ─────────────────────────────
        // The lock screen's capsule at surface scale, and the only container
        // here. No border at rest; a soft ring just outside the edge while it
        // has focus (the lock's), the error colour when an attempt fails.
        Item {
            id: fieldWrap
            width: parent.width
            height: root.wantsPin ? 52 * root.s : 0
            visible: root.wantsPin
            opacity: root.rowIn(1)
            transform: [
                Translate { id: fieldShift },
                Translate { y: (1 - root.rowIn(1)) * 10 * root.s }
            ]

            // Hard reversals, no easing: the abruptness is the signal.
            SequentialAnimation {
                id: shake
                NumberAnimation { target: fieldShift; property: "x"; to: 8 * root.s; duration: Math.round(45 * Motion.mult) }
                NumberAnimation { target: fieldShift; property: "x"; to: -8 * root.s; duration: Math.round(45 * Motion.mult) }
                NumberAnimation { target: fieldShift; property: "x"; to: 5 * root.s; duration: Math.round(45 * Motion.mult) }
                NumberAnimation { target: fieldShift; property: "x"; to: -5 * root.s; duration: Math.round(45 * Motion.mult) }
                NumberAnimation { target: fieldShift; property: "x"; to: 0; duration: Math.round(45 * Motion.mult) }
            }

            Rectangle {
                anchors.fill: capsule
                anchors.margins: -4 * root.s
                radius: height / 2
                color: "transparent"
                border.width: 1.5 * root.s
                border.color: Qt.alpha(root.showError ? Colors.error : Colors.primary, 0.3)
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                opacity: (input.activeFocus || root.showError) && !root.busy && !root.accepted ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }

            Rectangle {
                id: capsule
                anchors.fill: parent
                anchors.leftMargin: 30 * root.s
                radius: height / 2
                color: Qt.tint(Colors.surface_container_highest,
                               Qt.alpha(Colors.error, root.showError ? 0.16 : 0))
                Behavior on color { ColorAnimation { duration: Motion.standard } }

                PassDots {
                    id: dots
                    anchors.centerIn: parent
                    width: parent.width - 2 * 54 * root.s
                    s: root.s
                    dot: 17 * root.s
                    gap: 6 * root.s
                    count: root.echoPlain ? 0 : root.dotLen
                    busy: root.busy
                    error: root.showError || root.repeatMismatch
                    success: root.accepted
                    animate: root.open && !Motion.reduceMotion
                }

                // Empty: the prompt, centred, with the caret ahead of it.
                Row {
                    anchors.centerIn: parent
                    spacing: 7 * root.s
                    opacity: root.dotLen === 0 && input.text.length === 0 && !root.showError ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                    Rectangle {
                        id: caret
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2 * root.s
                        height: 16 * root.s
                        radius: width / 2
                        color: Colors.primary
                        opacity: input.activeFocus ? 1 : 0
                        SequentialAnimation on opacity {
                            running: root.open && input.activeFocus && root.dotLen === 0 && !Motion.reduceMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 1; duration: 80; easing.type: Easing.OutQuad }
                            PauseAnimation { duration: 480 }
                            NumberAnimation { to: 0.1; duration: 220; easing.type: Easing.InOutSine }
                            PauseAnimation { duration: 280 }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.promptText.toLowerCase()
                        color: Qt.alpha(Colors.on_surface_variant, 0.7)
                        font.family: Appearance.font.family
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.Medium
                        font.letterSpacing: 1.2 * root.s
                    }
                }

                // Rejected: the message takes the slot the dots fell out of.
                Text {
                    id: errText
                    anchors.centerIn: parent
                    width: parent.width - 2 * 22 * root.s
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    readonly property bool up: root.showError && root.dotLen === 0 && input.text.length === 0
                    text: root.errorText.toLowerCase().replace(/\.$/, "")
                    color: Colors.error
                    font.family: Appearance.font.family
                    font.pixelSize: 12 * root.s
                    font.weight: Font.Medium
                    font.letterSpacing: 0.5 * root.s
                    opacity: up ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                    transform: Translate {
                        y: errText.up ? 0 : 6 * root.s
                        Behavior on y {
                            NumberAnimation {
                                duration: Motion.expressiveFastSpatialDur
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }
                    }
                }

                // Polkit says the answer isn't secret: show it.
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 2 * 54 * root.s
                    horizontalAlignment: Text.AlignHCenter
                    text: input.text
                    elide: Text.ElideLeft
                    visible: root.echoPlain && input.text.length > 0
                    color: Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 13.5 * root.s
                    font.weight: Font.Medium
                }

                // 開 — the key you are about to press, as on the lock screen.
                Item {
                    id: openKey
                    anchors.right: parent.right
                    anchors.rightMargin: 12 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32 * root.s
                    height: 32 * root.s
                    readonly property bool shown: root.canSubmit
                    opacity: shown ? 1 : 0
                    scale: shown ? (keyArea.pressed ? 0.92 : 1) : 0.7
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.expressiveFastSpatialDur
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: keyArea.containsMouse ? Qt.alpha(Colors.primary, 0.14) : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "開"
                        color: Colors.primary
                        font.family: Appearance.font.jp
                        font.pixelSize: 15 * root.s
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: keyArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submit()
                        Accessible.role: Accessible.Button
                        Accessible.name: root.isGpg ? "Unlock" : "Authenticate"
                    }
                }

                // The real input: live, focused, invisible. The dots are its face.
                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 54 * root.s
                    anchors.rightMargin: 54 * root.s
                    echoMode: TextInput.Password
                    color: "transparent"
                    selectionColor: "transparent"
                    selectedTextColor: "transparent"
                    font.pixelSize: 1
                    cursorVisible: false
                    cursorDelegate: Item {}
                    enabled: root.open && root.wantsPin && !root.busy && !root.accepted
                    focus: true
                    onTextChanged: {
                        if (text.length > 0) {
                            root.repeatMismatch = false;
                            failHold.stop();
                            root.holding = false;
                        }
                        if (!root.holding)
                            root.dotLen = text.length;
                    }
                    Keys.onPressed: event => {
                        const t = event.text;
                        if (t.length === 1 && t.toLowerCase() !== t.toUpperCase()) {
                            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                            root.capsLock = (t === t.toUpperCase()) !== shift;
                        }
                    }
                    Keys.onEscapePressed: root.requestClose()
                    onAccepted: root.submit()
                }
            }
        }

        // ── GnuPG's yes/no dialogs: the only place with buttons ──────────
        Row {
            id: buttons
            visible: !root.wantsPin
            width: parent.width
            spacing: 8 * root.s
            opacity: root.rowIn(1)
            transform: Translate { y: (1 - root.rowIn(1)) * 10 * root.s }

            readonly property var specs: {
                if (root.mode === "message")
                    return [{ id: "ok", label: root.clean(Pinentry.okLabel, "OK"), primary: true }];
                const out = [];
                if (Pinentry.notOkLabel.length)
                    out.push({ id: "notok", label: root.clean(Pinentry.notOkLabel, "No"), primary: false });
                out.push({ id: "cancel", label: root.clean(Pinentry.cancelLabel, "Cancel"), primary: false });
                out.push({ id: "ok", label: root.clean(Pinentry.okLabel, "OK"), primary: true });
                return out;
            }

            Repeater {
                model: buttons.visible ? buttons.specs : []
                delegate: AuthButton {
                    required property var modelData
                    width: (buttons.width - buttons.spacing * (buttons.specs.length - 1)) / buttons.specs.length
                    label: modelData.label
                    primary: modelData.primary
                    onClicked: {
                        switch (modelData.id) {
                        case "ok": root.answer(true); break;
                        case "notok": Pinentry.notOk(); break;
                        default: root.requestClose();
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 10 * root.s }

        // ── one quiet line: what the keys do, or what is happening ──────
        Item {
            width: parent.width
            height: hint.implicitHeight
            opacity: root.rowIn(2)
            transform: Translate { y: (1 - root.rowIn(2)) * 10 * root.s }

            readonly property bool warn: root.capsLock && root.wantsPin && !root.busy
            readonly property string line: {
                if (warn)
                    return "caps lock is on";
                if (root.accepted)
                    return "done";
                if (root.busy)
                    return "checking…";
                if (root.infoText.length)
                    return root.infoText.toLowerCase();
                if (!root.wantsPin)
                    return "enter to confirm  ·  esc to cancel";
                return root.repeating ? "type it once more  ·  esc to cancel"
                    : "enter to " + (!root.isGpg ? "authenticate" : (Pinentry.repeat ? "continue" : "unlock"))
                        + "  ·  esc to cancel";
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: root.wantsPin ? 15 * root.s : 0
                spacing: 6 * root.s
                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.parent.warn
                    width: 11 * root.s
                    height: 11 * root.s
                    name: "caps-lock"
                    stroke: 2
                    color: Colors.tertiary
                }
                Text {
                    id: hint
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.line
                    color: parent.parent.warn ? Colors.tertiary
                        : (root.accepted ? Colors.primary : Qt.alpha(Colors.on_surface_variant, 0.6))
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    font.family: Appearance.font.family
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2 * root.s
                }
            }
        }

        Item { width: 1; height: 4 * root.s }
    }

    // Confirm / message dialogs have no field to catch the keys.
    Item {
        anchors.fill: parent
        focus: root.open && !root.wantsPin
        Keys.onReturnPressed: root.answer(true)
        Keys.onEnterPressed: root.answer(true)
        Keys.onEscapePressed: root.requestClose()
    }

    /** The shell's button (architecture §2b-v): a filled stadium, no rule. */
    component AuthButton: Rectangle {
        id: btn
        property string label: ""
        property bool primary: false
        signal clicked()

        height: 36 * root.s
        radius: height / 2
        color: btn.primary ? Colors.primary : Colors.surface_container_highest

        M3StateLayer {
            anchors.fill: parent
            s: root.s
            radius: btn.radius
            contentColor: btn.primary ? Colors.on_primary : Colors.on_surface
            pressScale: 0.96
            minTarget: 36
            accessibleRole: Accessible.Button
            accessibleName: btn.label
            onClicked: btn.clicked()
        }

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? Colors.on_primary : Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 12 * root.s
            font.weight: Font.DemiBold
        }
    }
}
