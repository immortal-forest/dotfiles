pragma Singleton
import QtQuick
import Quickshell

/**
 * astralis — idle/lock daemon bridge (ported from Ricelin pill/IdleLock.qml's
 * buildConf()/apply()). Generates ~/.config/hypr/hypridle.conf from the 錠 IDLE
 * / LOCK settings ([[Flags]].idle*Min + lockBeforeSleep) and (re)starts the
 * hypridle user unit whenever they change, so the Settings page's timeouts
 * actually take effect.
 *
 * The lock action is `loginctl lock-session`, which the astralis WlSessionLock
 * lockscreen (lock/Lock.qml) catches over D-Bus — no hyprlock, no lock_cmd (that
 * would loop, since our lock is triggered *by* the lock-session signal). A zero
 * timeout omits that listener entirely. Dim (scripts/idle-dim) drops every
 * screen — laptop backlight via brightnessctl, external monitors via ddcutil
 * DDC/CI — to 40% of its CURRENT level (floored at 1%) — PROPORTIONAL, so it
 * always dims and never raises an already-low screen (a fixed `set 10%`
 * brightened a screen sitting at 6%); the pre-dim levels are saved and put
 * back on resume. Screen-off sets dpms via the Lua hl.dsp.dpms dispatcher; suspend
 * calls systemctl. Screen-off and before_sleep_cmd first run `idle-dim
 * release`, which puts the DDC monitors back while they're still awake: DDC
 * sent to a monitor as it wakes from standby left the MSI re-plugged with no
 * modes (blank), so nothing may talk DDC on the way back.
 *
 * Loaded at startup via a reference in shell.qml so the conf is written and the
 * daemon started on login; the debounce coalesces a burst of seg changes into
 * one rewrite+restart.
 */
Singleton {
    id: root

    // Hyprland runs the Lua config, so `hyprctl dispatch` takes Lua: the old
    // `dpms off` form is a Lua syntax error that hyprctl rejects (idle never
    // actually blanked the screen). hypridle runs these through sh, so the
    // single quotes survive.
    function dpms(action) {
        return "hyprctl dispatch 'hl.dsp.dpms({ action = \"" + action + "\" })'";
    }

    // Beside this file (not shellDir) so it resolves in dev harnesses too.
    readonly property string idleDim: decodeURIComponent(String(Qt.resolvedUrl("../scripts/idle-dim")).replace(/^file:\/\//, ""))

    function buildConf() {
        var out = "general {\n"
            + "    before_sleep_cmd = " + root.idleDim + " release"
            + (Flags.lockBeforeSleep ? "; loginctl lock-session" : "") + "\n"
            + "    after_sleep_cmd = " + root.dpms("on") + "\n"
            + "}\n";

        if (Flags.idleDimMin > 0)
            out += "\nlistener {\n"
                + "    timeout = " + (Flags.idleDimMin * 60) + "\n"
                + "    on-timeout = " + root.idleDim + " dim\n"
                + "    on-resume = " + root.idleDim + " restore\n"
                + "}\n";

        if (Flags.idleScreenOffMin > 0)
            out += "\nlistener {\n"
                + "    timeout = " + (Flags.idleScreenOffMin * 60) + "\n"
                + "    on-timeout = " + root.idleDim + " release; " + root.dpms("off") + "\n"
                // Skipped while the power menu's Screen off holds its
                // inhibitor: hypridle's resume fires on ANY activity, which
                // would make "wake on touchpad/mouse: off" leak once this
                // listener has timed out during a long manual blank.
                + "    on-resume = systemd-inhibit --list --no-legend | grep -q astralis-screen-off || " + root.dpms("on") + "\n"
                + "}\n";

        if (Flags.idleLockMin > 0)
            out += "\nlistener {\n"
                + "    timeout = " + (Flags.idleLockMin * 60) + "\n"
                + "    on-timeout = loginctl lock-session\n"
                + "}\n";

        if (Flags.idleSuspendMin > 0)
            out += "\nlistener {\n"
                + "    timeout = " + (Flags.idleSuspendMin * 60) + "\n"
                + "    on-timeout = systemctl suspend\n"
                + "}\n";

        return out;
    }

    // One shell command writes the conf then restarts hypridle, so the file is
    // guaranteed on disk before the daemon reads it. Idempotent: if the conf on
    // disk already matches and the unit's hypridle is the only one running, it
    // exits without a restart — so a hot reload (or a `qs -p` check, which
    // loads this too) doesn't re-arm the idle timers.
    //
    // Exactly ONE hypridle, the unit's. Only one process can own
    // org.freedesktop.ScreenSaver, which is where Firefox says "video playing,
    // don't dim". This used to fall back to a bare `setsid hypridle` whenever
    // `systemctl restart` failed — and it failed with start-limit-hit after a
    // burst of reloads (each load restarted twice, see below). The stray kept
    // the name, the unit's copy logged "Another service is already providing
    // org.freedesktop.ScreenSaver", never heard the inhibit, and dimmed both
    // screens 3 min into a fullscreen video (2026-11-27). So: strays are
    // killed, the failure counter is reset before a restart, and the bare
    // spawn is only for a machine with no hypridle unit at all.
    function apply() {
        if (!Flags.loaded)
            return;
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/hypr\"; f=\"$HOME/.config/hypr/hypridle.conf\"; same=; "
            // The script path, resolved: the daemon reaches the tree through
            // the ~/.config/quickshell symlink and a `qs -p` run through
            // ~/dotfiles, so each saw the other's conf as changed and restarted.
            + "d=$(readlink -f \"$2\" 2>/dev/null) || d=\"$2\"; want=$(printf '%s' \"$1\" | sed \"s|$2|$d|g\"); "
            + "[ \"$(cat \"$f\" 2>/dev/null)\" = \"$want\" ] && same=1; "
            + "if ! systemctl --user cat hypridle.service >/dev/null 2>&1; then "
            + "  [ -n \"$same\" ] && pgrep -x hypridle >/dev/null 2>&1 && exit 0; "
            + "  printf '%s\\n' \"$want\" > \"$f\"; pkill -x hypridle; setsid hypridle >/dev/null 2>&1 & exit 0; "
            + "fi; "
            + "main=$(systemctl --user show -p MainPID --value hypridle.service); stray=; "
            + "for p in $(pgrep -x hypridle); do [ \"$p\" = \"$main\" ] || { kill \"$p\"; stray=1; }; done; "
            + "[ -n \"$same\" ] && [ -z \"$stray\" ] && systemctl --user is-active --quiet hypridle.service && exit 0; "
            // let a killed stray drop the bus name before the unit asks for it
            + "i=0; while [ -n \"$stray\" ] && [ $i -lt 20 ] && pgrep -x hypridle | grep -qvx \"$main\"; do sleep 0.1; i=$((i+1)); done; "
            + "printf '%s\\n' \"$want\" > \"$f\"; "
            + "systemctl --user reset-failed hypridle.service 2>/dev/null; "
            + "systemctl --user restart hypridle.service",
            "astralis-hypridle", root.buildConf(), root.idleDim]);
    }

    Timer { id: debounce; interval: 400; onTriggered: root.apply() }

    Connections {
        target: Flags
        function onIdleDimMinChanged() { debounce.restart(); }
        function onIdleScreenOffMinChanged() { debounce.restart(); }
        function onIdleLockMinChanged() { debounce.restart(); }
        function onIdleSuspendMinChanged() { debounce.restart(); }
        function onLockBeforeSleepChanged() { debounce.restart(); }
    }

    // Write the conf + start the daemon on login — once Flags has loaded.
    // Applying at Component.onCompleted ran on QML DEFAULTS (no dim, lock at
    // 5 min): every shell start or hot reload wrote that conf, restarted
    // hypridle, then wrote the real one and restarted it again.
    Component.onCompleted: if (Flags.loaded) debounce.restart()
    Connections {
        target: Flags
        function onLoadedChanged() { if (Flags.loaded) debounce.restart(); }
    }
}
