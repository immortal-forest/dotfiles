pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

/**
 * astralis — the session's polkit authentication agent. When something asks
 * for admin rights (pkexec, a systemd unit, a package manager GUI) the pill
 * opens its 認 auth surface (pill/surfaces/Auth.qml) on the focused screen
 * instead of a separate hyprpolkitagent window.
 *
 * Only one agent can register per session, so hypr.d/autostart.lua no longer
 * starts hyprpolkitagent. There is deliberately NO fallback that starts it:
 * registration only fails when another agent already holds the session, so
 * prompts are covered either way — and the old 5 s fallback fired from every
 * dev harness / `qs -p` validation run (they can't register beside the live
 * shell), started hyprpolkitagent, and it then won the session from the
 * shell on its next reload (2026-11-27). Force-loaded from shell.qml, since
 * singletons are lazy.
 *
 * The password goes straight from the field to `flow.submit()` and is never
 * stored or logged here.
 */
Singleton {
    id: root

    /** The live request, or null between requests. */
    readonly property var flow: agent.flow
    /** A request is waiting for the user. */
    readonly property bool active: agent.isActive && agent.flow !== null && !agent.flow.isCompleted
    readonly property bool registered: agent.isRegistered

    /**
     * True for one beat after a request succeeds: the auth surface stays up
     * long enough to play its "accepted" sweep (PassDots.success) instead of
     * vanishing the instant PAM says yes. shell.qml keeps it open meanwhile.
     */
    property bool accepted: false
    Timer {
        id: acceptedBeat
        interval: Math.round(460 * Motion.mult)
        onTriggered: root.accepted = false
    }
    Connections {
        target: agent.flow
        function onAuthenticationSucceeded() {
            root.accepted = true;
            acceptedBeat.restart();
        }
    }

    function submit(response) {
        if (root.flow && !root.flow.isCompleted)
            root.flow.submit(response);
    }

    function cancel() {
        if (root.flow && !root.flow.isCompleted)
            root.flow.cancelAuthenticationRequest();
    }

    /** Display name of an identity ("immortalforest", "root"), whatever the backend exposes. */
    function identityName(id) {
        if (!id)
            return "";
        return String(id.displayName || id.name || id.id || "");
    }

    PolkitAgent {
        id: agent
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: if (!agent.isRegistered)
            console.warn("PolkitAuth: not the session's polkit agent (another one holds it) — prompts go there");
    }
}
