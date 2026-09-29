pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — the one udev event stream. CameraToggle (video4linux add/remove:
 * the Legion's camera switch power-cuts the UVC device) and Backlight (the
 * backlight core emits a `change` uevent on every brightness write, sysfs or
 * hotkey — live-verified on nvidia_wmi_ec_backlight) both hang off this, so
 * the shell runs one `udevadm monitor` instead of one poller per service.
 *
 * Every long-running helper in astralis goes through `setpriv --pdeathsig
 * TERM`: Quickshell does not reap its children when it dies abruptly (a crash,
 * SIGTERM, `qs kill`), and a helper that only writes on change never meets the
 * SIGPIPE that would end it. Without the wrapper, each relaunch leaked a set
 * of pollers under systemd --user — 166 of them had piled up at one count.
 */
Singleton {
    id: root

    /** A device on `subsystem` saw `action` (add / remove / change / …). */
    signal event(string subsystem, string action)

    Process {
        id: monitor
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--",
            "udevadm", "monitor", "--udev",
            "--subsystem-match=video4linux", "--subsystem-match=backlight"]
        stdout: SplitParser {
            onRead: (line) => {
                // "UDEV  [128724.546] change   /devices/…/nvidia_wmi_ec_backlight (backlight)"
                const m = /^UDEV\s+\[[^\]]*\]\s+(\S+)\s+\S+\s+\((\S+)\)\s*$/.exec(line);
                if (m)
                    root.event(m[2], m[1]);
            }
        }
        // udevadm only exits if udevd goes away; come back without spinning.
        onExited: respawn.start()
    }

    Timer {
        id: respawn
        interval: 5000
        onTriggered: monitor.running = true
    }
}
