pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../colors"
import "../services"

/**
 * astralis — session lockscreen (Ricelin lock/shell.qml collapsed into one
 * mountable scope). A REAL WlSessionLock: while `locked`, the compositor
 * blanks every output behind our WlSessionLockSurfaces and routes all input
 * to them; only PAM success (lock/Auth.qml) releases it.
 *
 * Triggers — the loginctl path is primary:
 *  - `loginctl lock-session` (the powermenu's Lock tile, idle daemons, DMs):
 *    Quickshell has no logind service, so a tiny resident `gdbus monitor`
 *    watches our own login1 session object for its Lock/Unlock signals. The
 *    session path is resolved once via busctl (XDG_SESSION_ID, then by-PID);
 *    if both fail we monitor all login1 signals — on a single-seat box any
 *    session Lock is ours.
 *  - `qs -c astralis ipc call lock lock` for scripts/keybinds.
 *
 * `loginctl unlock-session` is honored as the escape hatch (it is
 * polkit-gated on the logind side, so it carries at least our own
 * privileges). There is deliberately NO unlock IPC: the qs socket is plain
 * user-owned and must not be a soft bypass — fail closed.
 *
 * The password buffer lives here (`passBuf`) so every screen's capsule
 * mirrors one string (LockSurface syncs both ways); it is wiped on lock,
 * failure, and unlock.
 */
Scope {
    id: root

    readonly property string currentUser: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    readonly property bool locked: sessionLock.locked
    readonly property bool authenticating: auth.authenticating
    readonly property string lastError: auth.lastError

    /** Shared capsule text, mirrored across per-screen surfaces. */
    property string passBuf: ""

    signal failed
    signal succeeded

    function submit(password) {
        auth.submit(password);
    }

    function lock() {
        if (sessionLock.locked)
            return;
        root.passBuf = "";
        sessionLock.locked = true;
    }

    /** Internal: reached only via PAM success or loginctl unlock-session. */
    function unlock() {
        root.passBuf = "";
        sessionLock.locked = false;
    }

    Auth {
        id: auth
        user: root.currentUser
        onSucceeded: {
            root.succeeded();
            root.unlock();
        }
        onFailed: {
            root.passBuf = "";
            root.failed();
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        WlSessionLockSurface {
            id: lockWindow
            // Opaque from the first frame — never flash the desktop through.
            color: Colors.surface_container_lowest

            LockSurface {
                anchors.fill: parent
                ctx: root
                s: (lockWindow.screen ? lockWindow.screen.height / 1080 : 1) * Flags.uiScale
                screenName: lockWindow.screen ? lockWindow.screen.name : ""
            }
        }
    }

    // ── logind bridge: loginctl lock/unlock-session → sessionLock ──────────
    Process {
        id: logindWatch
        running: true

        // Whether the monitor is scoped to THIS session's login1 object path.
        // Until the script reports its mode we treat it as unscoped and refuse
        // to honour Unlock — fail closed against a stray multi-seat signal.
        property bool scoped: false
        // Fast-fail backoff: if the monitor dies almost immediately (missing
        // busctl/gdbus) we must not respawn it forever.
        property int watchFails: 0
        property double watchStart: 0

        command: ["sh", "-c",
            'p=""; ' +
            'if [ -n "$XDG_SESSION_ID" ]; then ' +
            'p=$(busctl --system call org.freedesktop.login1 /org/freedesktop/login1 ' +
            'org.freedesktop.login1.Manager GetSession s "$XDG_SESSION_ID" 2>/dev/null | cut -d\'"\' -f2); fi; ' +
            'if [ -z "$p" ]; then ' +
            'p=$(busctl --system call org.freedesktop.login1 /org/freedesktop/login1 ' +
            'org.freedesktop.login1.Manager GetSessionByPID u $$ 2>/dev/null | cut -d\'"\' -f2); fi; ' +
            // Emit a mode marker so QML knows whether Unlock is trustworthy, then
            // scope the monitor to our object path when we resolved one. Without a
            // path we still watch (single-seat Lock is ours) but the parser will
            // NOT act on Unlock — the SessionLock/PAM path handles unlock instead.
            'if [ -n "$p" ]; then echo "ASTRALIS_SCOPED"; ' +
            'exec gdbus monitor --system --dest org.freedesktop.login1 --object-path "$p"; fi; ' +
            'echo "ASTRALIS_UNSCOPED"; ' +
            'exec gdbus monitor --system --dest org.freedesktop.login1']
        stdout: SplitParser {
            onRead: line => {
                // gdbus prints ".../session/_3X: org.freedesktop.login1.Session.Lock ()".
                if (line.indexOf("ASTRALIS_UNSCOPED") >= 0) {
                    logindWatch.scoped = false;
                    return;
                }
                if (line.indexOf("ASTRALIS_SCOPED") >= 0) {
                    logindWatch.scoped = true;
                    return;
                }
                // Substring-match keeps PropertiesChanged noise out; the "(" suffix
                // disambiguates the signal. Unlock is honoured ONLY when the monitor
                // is scoped to our own session — otherwise another seat's Unlock
                // could release our lock (multi-seat bypass).
                if (line.indexOf(".Session.Unlock (") >= 0) {
                    if (logindWatch.scoped)
                        root.unlock();
                } else if (line.indexOf(".Session.Lock (") >= 0) {
                    root.lock();
                }
            }
        }
        Component.onCompleted: watchStart = Date.now()
        onRunningChanged: if (running) watchStart = Date.now();
        // If the monitor ever dies the lock trigger would go dead — relaunch it,
        // but stop hammering a missing/broken binary. A monitor that survived a
        // while resets the counter; repeated instant exits back off then give up
        // (the SessionLock + IPC lock paths keep working regardless).
        onExited: {
            if (Date.now() - watchStart < 3000)
                watchFails++;
            else
                watchFails = 0;
            if (watchFails <= 6)
                watchRestart.restart();
        }
    }
    Timer {
        id: watchRestart
        interval: Math.min(30000, 2000 * Math.pow(2, Math.min(logindWatch.watchFails, 4)))
        onTriggered: {
            // Re-establish scope from scratch on every relaunch (fail closed until
            // the fresh monitor re-announces its mode).
            logindWatch.scoped = false;
            logindWatch.running = true;
        }
    }

    /** Script/keybind door: `qs -c astralis ipc call lock lock`. Lock only — no unlock. */
    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
    }
}
