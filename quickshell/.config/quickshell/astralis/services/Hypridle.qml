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
    // guaranteed on disk before the daemon reads it. Falls back to a bare
    // (re)spawn if the systemd user unit isn't available. Idempotent: if the
    // conf on disk already matches AND hypridle is running, it exits without a
    // restart — so a hot-reload (which re-runs Component.onCompleted) does not
    // needlessly restart the unit and re-arm the idle timers.
    function apply() {
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$HOME/.config/hypr\"; f=\"$HOME/.config/hypr/hypridle.conf\"; "
            + "if [ \"$(cat \"$f\" 2>/dev/null)\" = \"$(printf '%s' \"$1\")\" ] && pgrep -x hypridle >/dev/null 2>&1; then exit 0; fi; "
            + "printf '%s' \"$1\" > \"$f\"; "
            + "systemctl --user restart hypridle 2>/dev/null || { pkill -x hypridle 2>/dev/null; setsid hypridle >/dev/null 2>&1 & }",
            "astralis-hypridle", root.buildConf()]);
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

    // Write the initial conf + start the daemon on login. Flags' JSON may still
    // be loading (defaults for one tick); the Connections above re-apply once
    // the persisted values land.
    Component.onCompleted: root.apply()
}
