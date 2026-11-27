pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — on battery, pause the effects outside the shell that redraw
 * every frame for nothing.
 *
 * Ghostty's custom cursor shader (shaders/blaze.glsl) animates every frame
 * while the terminal is focused, though the trail it draws is done 0.5 s after
 * the cursor last moved: Hyprland went 61–68% → 27% of the 780M and Ghostty
 * 20–24% → 5% with the animation off (measured 2026-11-27). On mains power the
 * trail keeps its full animation; on battery this writes
 * `custom-shader-animation = false` into ~/.cache/astralis/ghostty-power.conf
 * (included last by ghostty/config as an optional file) and asks Ghostty to
 * reload with SIGUSR2. The border's own power behaviour is Settings › Look ›
 * Border motion ("On AC").
 *
 * Force-loaded from shell.qml.
 */
Singleton {
    id: root

    readonly property bool onBattery: Battery.discharging
    readonly property string ghosttyConf: "# Written by astralis (services/PowerSaver.qml) on every power change — DO NOT EDIT.\n"
        + "# Battery: no per-frame cursor-shader animation; mains: Ghostty's default.\n"
        + "custom-shader-animation = " + (root.onBattery ? "false" : "true") + "\n"

    function apply() {
        if (!file.ready)
            return;
        if (String(file.text()) === root.ghosttyConf)
            return;
        file.setText(root.ghosttyConf);
        // -O 2: a Ghostty still starting has no USR2 handler yet and would be
        // killed; it reads this file at startup anyway (see scripts/setwall).
        Quickshell.execDetached(["pkill", "-USR2", "-O", "2", "-x", "ghostty"]);
    }

    onGhosttyConfChanged: apply()

    FileView {
        id: file
        // ~/.cache/astralis already exists (Settings, Widgets and others write there).
        path: Quickshell.env("HOME") + "/.cache/astralis/ghostty-power.conf"
        printErrors: false
        atomicWrites: true
        // A missing file is fine: treat it as empty and write it.
        property bool ready: false
        onLoaded: { ready = true; root.apply(); }
        onLoadFailed: { ready = true; root.apply(); }
    }
}
