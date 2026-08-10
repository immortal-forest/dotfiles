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
 *  - udevadm monitor (video4linux) — event-driven; an add/remove lands within
 *    ms of the switch, a short settle coalesces the node burst, then a
 *    one-shot presence probe reads the truth.
 *  - a ~1.5s presence poll (Privacy's self-loop pattern, prints only on
 *    change) — the correctness backstop, and what primes the initial state.
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
    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=video4linux"]
        stdout: SplitParser {
            onRead: (line) => {
                // "UDEV  [ts] add|remove   /devices/.../video4linux/videoN (video4linux)"
                if (line.indexOf("UDEV") === 0 && (line.indexOf(" add ") !== -1 || line.indexOf(" remove ") !== -1))
                    settle.restart();
            }
        }
    }

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

    // ── poll backstop: presence loop, prints only on change ─────────────────
    Process {
        running: true
        command: ["sh", "-c",
            "last=''; while true; do "
            + "if [ -e /dev/video0 ]; then cur=on; else cur=off; fi; "
            + "if [ \"$cur\" != \"$last\" ]; then echo \"$cur\"; last=\"$cur\"; fi; "
            + "sleep 1.5; done"]
        stdout: SplitParser {
            onRead: (line) => root.apply(line.trim() === "on")
        }
    }

    // ── optional evdev accelerant (silent no-op without input group/evtest) ─
    Process {
        running: true
        command: ["sh", "-c",
            "command -v evtest >/dev/null 2>&1 || exit 0; "
            + "dev=$(awk -v RS= '/Ideapad extra buttons/{for(i=1;i<=NF;i++)if($i~/^event[0-9]+$/){print $i;exit}}' /proc/bus/input/devices 2>/dev/null); "
            + "[ -n \"$dev\" ] && [ -r \"/dev/input/$dev\" ] || exit 0; "
            + "evtest \"/dev/input/$dev\" 2>/dev/null | grep --line-buffered KEY_CAMERA_ACCESS"]
        stdout: SplitParser {
            // any KEY_CAMERA_ACCESS_* traffic just accelerates a presence re-probe;
            // presence stays the single source of truth
            onRead: () => settle.restart()
        }
    }
}
