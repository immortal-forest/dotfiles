pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — camera hardware kill-switch watcher (Lenovo Legion privacy
 * toggle). Distinct from Privacy.cameraActive ("something is capturing right
 * now"): this is whether the webcam is powered at all. The switch power-cuts
 * the UVC device, so /dev/video0 vanishing/reappearing IS the state — a
 * permission-free signal that needs no group membership.
 *
 * Detection, layered:
 *  - Udev (the shell's one `udevadm monitor`) — event-driven; a video4linux
 *    add/remove lands within ms of the switch, a short settle coalesces the
 *    node burst, then a one-shot presence probe reads the truth. The same
 *    probe primes the initial state at startup. (A 1.5s presence poll used to
 *    back this up; it forked `sleep` forever to re-learn what udev reports.)
 *  - optional evdev accelerant: the "Ideapad extra buttons" node emits
 *    KEY_CAMERA_ACCESS_* on the key itself, but /dev/input/event* is
 *    input-group-only (`sudo usermod -aG input $USER` + relogin for instant,
 *    explicit events). Without the group — or without evtest — that branch
 *    exits 0 silently and the two presence paths above still carry the
 *    feature.
 *
 * `toggled(on)` fires only on a real transition after the first reading, so
 * login never flashes the OSD.
 */
Singleton {
    id: root

    /** true = camera hardware present/on (the privacy switch is not engaged). */
    readonly property bool enabled: present

    /** A real on/off transition — never the initial populate. */
    signal toggled(bool on)

    property bool present: false
    property bool primed: false

    function apply(on) {
        if (!primed) {
            primed = true;
            present = on;
            return;
        }
        if (on === present)
            return;
        present = on;
        toggled(on);
    }

    // ── event path: udev add/remove on the v4l subsystem ────────────────────
    Connections {
        target: Udev
        function onEvent(subsystem, action) {
            if (subsystem === "video4linux" && (action === "add" || action === "remove"))
                settle.restart();
        }
    }

    Component.onCompleted: recheck.running = true

    /** Coalesces the event burst (video0+video1 flip together), then re-probes. */
    Timer {
        id: settle
        interval: 200
        onTriggered: recheck.running = true
    }

    Process {
        id: recheck
        command: ["sh", "-c", "[ -e /dev/video0 ] && echo on || echo off"]
        stdout: SplitParser {
            onRead: (line) => root.apply(line.trim() === "on")
        }
    }

    // ── optional evdev accelerant (silent no-op without input group/evtest) ─
    // pdeathsig cascades down the pipeline: qs dies → sh gets TERM → evtest
    // and grep (sh's children) get theirs. grep writes only on a key press,
    // so without it an orphaned pair would outlive the shell indefinitely.
    Process {
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", "sh", "-c",
            "command -v evtest >/dev/null 2>&1 || exit 0; "
            + "dev=$(awk -v RS= '/Ideapad extra buttons/{for(i=1;i<=NF;i++)if($i~/^event[0-9]+$/){print $i;exit}}' /proc/bus/input/devices 2>/dev/null); "
            + "[ -n \"$dev\" ] && [ -r \"/dev/input/$dev\" ] || exit 0; "
            + "setpriv --pdeathsig TERM -- evtest \"/dev/input/$dev\" 2>/dev/null "
            + "| setpriv --pdeathsig TERM -- grep --line-buffered KEY_CAMERA_ACCESS"]
        stdout: SplitParser {
            // any KEY_CAMERA_ACCESS_* traffic just accelerates a presence re-probe;
            // presence stays the single source of truth
            onRead: () => settle.restart()
        }
    }
}
