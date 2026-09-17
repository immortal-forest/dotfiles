pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — resume-from-suspend self-heal.
 *
 * Symptom this fixes: after the machine wakes from suspend/sleep the pill
 * (and its reserve strip) can come back BLANK while still holding its
 * exclusive zone — a dead strip you had to `reload` by hand to clear. Root
 * cause is a known Quickshell/wlroots-stack issue: on resume the GL/EGL
 * context the layer-shell surfaces render through is lost (EGL_BAD_CONTEXT),
 * so the process stays alive but never presents another frame. A config
 * reload rebuilds the windows (and with them a fresh render context), which
 * is exactly the manual step being automated here.
 *
 * Trigger: systemd-logind's `PrepareForSleep` signal on the Manager object
 * (`/org/freedesktop/login1`) — it fires `(true)` heading into sleep and
 * `(false)` on resume. Watched with the same resident `gdbus monitor` +
 * fail-backoff pattern lock/Lock.qml already uses for the session Lock/Unlock
 * signals (Quickshell ships no logind service), just aimed at the Manager
 * object rather than our session object, since PrepareForSleep lives there.
 *
 * SAFETY — never reload while the session is locked. Reloading Quickshell
 * with a live WlSessionLock up is a documented crash / lock-loss hazard
 * (the lock client is torn down and the desktop can be exposed without
 * auth, or the shell SIGABRTs). So on resume we reload only when unlocked;
 * if we woke to a lock screen we hold the request and run it right after the
 * unlock instead — by then the pill is being remapped anyway and no lock is
 * on screen to endanger. `locked` is bound from shell.qml's lockScope.
 */
Item {
    id: root

    // Bound from shell.qml (lockScope.locked). Gates the reload — see SAFETY.
    property bool locked: false

    // A resume fired but we haven't reloaded yet (still settling, or held
    // because we woke locked). Cleared once the reload actually runs.
    property bool resumePending: false

    // How long to let the compositor bring outputs back before reloading.
    // PrepareForSleep(false) lands early in resume — on this box's AMD iGPU
    // the output pipeline isn't necessarily ready the instant it fires, so a
    // reload done too eagerly can land in the same half-initialised state.
    // Generous on purpose; a blank bar for two extra seconds after wake beats
    // reloading into another broken frame.
    property int settleMs: 2000

    function recover() {
        // Re-check `locked` at fire time, not just at schedule time: the user
        // could have re-locked during the settle window. Fail closed —
        // hold the request for the next unlock rather than reload under a lock.
        if (root.locked)
            return;
        root.resumePending = false;
        Quickshell.reload(false);
    }

    onLockedChanged: {
        // Woke to a lock screen, then unlocked with a reload still owed:
        // now it's safe, run it (settled) instead of dropping the recovery.
        if (!locked && resumePending)
            settleTimer.restart();
    }

    Timer {
        id: settleTimer
        interval: root.settleMs
        onTriggered: root.recover()
    }

    // ── logind Manager bridge: PrepareForSleep → reload on resume ───────────
    Process {
        id: sleepWatch
        running: true

        // Fast-fail backoff, mirroring Lock.qml: a monitor that dies almost
        // immediately (missing gdbus, no system bus) must not be respawned
        // forever.
        property int watchFails: 0
        property double watchStart: 0

        // Manager object carries PrepareForSleep (not the session object the
        // lock watch scopes to). No busctl lookup needed — the path is fixed.
        command: ["gdbus", "monitor", "--system",
            "--dest", "org.freedesktop.login1",
            "--object-path", "/org/freedesktop/login1"]

        stdout: SplitParser {
            onRead: line => {
                // gdbus prints e.g.
                //   /org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)
                // The boolean is the payload: false = resuming (heal now),
                // true = about to sleep (ignored). Matched as name + token
                // rather than a fixed "(false)" literal, because GVariant
                // renders a single-element tuple with a trailing comma —
                // `(false,)`, not `(false)` — so a literal-suffix match would
                // silently never fire. `false`/`true` appears nowhere else on
                // this signal's line, so the two independent substrings are an
                // unambiguous, format-tolerant match.
                if (line.indexOf("PrepareForSleep") >= 0 && line.indexOf("false") >= 0) {
                    root.resumePending = true;
                    settleTimer.restart();
                }
            }
        }

        Component.onCompleted: watchStart = Date.now();
        onRunningChanged: if (running) watchStart = Date.now();
        // If the monitor dies the self-heal goes dead — relaunch it, but stop
        // hammering a missing/broken binary. A monitor that survived a while
        // resets the counter; repeated instant exits back off then give up.
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
        interval: Math.min(30000, 2000 * Math.pow(2, Math.min(sleepWatch.watchFails, 4)))
        onTriggered: sleepWatch.running = true
    }
}
