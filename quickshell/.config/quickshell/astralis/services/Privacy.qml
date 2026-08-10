pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * astralis — iOS-style privacy watch: is anything capturing the microphone,
 * the camera, or the screen right now? The rest pill shows a tiny pulsing
 * glyph per active source (Pill.qml privacyRow).
 *
 * Detection per source (each degrades to `false` rather than erroring on a
 * box missing its probe tool):
 *
 *  - mic    — event-driven Pipewire, no polling. An app recording audio owns
 *             a `Stream/Input/Audio` node, which Quickshell surfaces as
 *             isStream && !isSink. Crucially NOT every capture stream is a
 *             microphone: astralis's own cava taps the sink monitor
 *             (`stream.capture.sink: true`, live-verified on this box), and
 *             portal audio-casts do the same, so monitor/sink taps are
 *             filtered out through each node's bound pw properties.
 *
 *  - camera — a shell poller: `fuser /dev/video*` lists PIDs holding a video
 *             device open (covers pipewire/libcamera AND direct v4l2 apps;
 *             wireplumber only opens the device while a client streams, so
 *             idle is clean — live-verified). fuser exists here; lsof doesn't.
 *
 *  - screen — same poller: count of Pipewire `Stream/Output/Video` nodes via
 *             `pw-cli ls Node` (xdg-desktop-portal-hyprland publishes one
 *             exactly while a screencast runs; 2.6KB output vs pw-dump's
 *             242KB, so it's cheap to poll), OR-ed with a pgrep for direct
 *             wlr-screencopy recorders that bypass the portal. `obs` is
 *             deliberately not pgrep'd — an idle OBS window isn't a capture,
 *             and when it does cast it goes through the portal node anyway.
 *             (`gpu-screen-reco.*` because comm truncates at 15 chars.)
 */
Singleton {
    id: root

    readonly property bool micActive: micCount > 0
    readonly property bool cameraActive: cameraCount > 0
    readonly property bool screenActive: screenCount > 0
    readonly property bool anyActive: micActive || cameraActive || screenActive

    property int micCount: 0
    property int cameraCount: 0
    property int screenCount: 0

    // ── microphone (event-driven Pipewire) ──────────────────────────────────

    /**
     * Every live audio capture stream. Binding them through the tracker below
     * is what populates `.properties`, which recountMic needs to tell a real
     * mic capture from a monitor tap.
     */
    readonly property var captureStreams: {
        const out = [];
        const all = Pipewire.nodes.values;
        for (let i = 0; i < all.length; i++) {
            const n = all[i];
            if (n && n.isStream && !n.isSink && n.audio)
                out.push(n);
        }
        return out;
    }

    PwObjectTracker { objects: root.captureStreams }

    // Node add/remove (an app starting/stopping capture) is the real trigger;
    // the settle timer below covers pw properties landing a beat after bind.
    onCaptureStreamsChanged: Qt.callLater(root.recountMic)
    Component.onCompleted: Qt.callLater(root.recountMic)

    /**
     * pw props arrive shortly after a node is bound; until then a stream's
     * monitor-ness is unknown and it is left uncounted (a not-yet-resolved
     * stream must not flash the mic dot every time cava spawns). While any
     * stream is unresolved, re-count on a short timer — it stops by itself
     * once everything has reported in.
     */
    Timer {
        id: settle
        interval: 500
        onTriggered: root.recountMic()
    }

    function recountMic() {
        let c = 0;
        let pending = false;
        const list = root.captureStreams;
        for (let i = 0; i < list.length; i++) {
            const n = list[i];
            if (!n)
                continue;
            try {
                if (!n.ready) {
                    pending = true;
                    continue;
                }
                const p = n.properties || ({});
                if (Object.keys(p).length === 0) {
                    pending = true;
                    continue;
                }
                // monitor / sink taps (cava, portal audio-cast) aren't mics
                if (String(p["stream.monitor"]) === "true")
                    continue;
                if (String(p["stream.capture.sink"]) === "true")
                    continue;
                if (String(p["target.object"]).indexOf(".monitor") !== -1)
                    continue;
                c++;
            } catch (e) {
                // node died mid-walk; the removal recount is already queued
                continue;
            }
        }
        root.micCount = c;
        if (pending)
            settle.restart();
    }

    // ── camera + screen (shell poller, Backlight's self-loop pattern) ──────
    // Prints "<cam> <scr>" only when a value changes (first pass always
    // prints, establishing the baseline). Every probe degrades to 0 when its
    // tool is missing: fuser/pw-cli/pgrep failures are silenced and the
    // arithmetic falls back through ${var:-0}.
    Process {
        running: true
        command: ["sh", "-c",
            "last=''; while true; do "
            + "cam=$(fuser /dev/video* 2>/dev/null | wc -w); "
            + "scr=$(pw-cli ls Node 2>/dev/null | grep -c 'media.class = \"Stream/Output/Video\"'); "
            + "rec=$(pgrep -cx 'wf-recorder|wl-screenrec|gpu-screen-reco.*' 2>/dev/null); "
            + "cur=\"${cam:-0} $(( ${scr:-0} + ${rec:-0} ))\"; "
            + "if [ \"$cur\" != \"$last\" ]; then echo \"$cur\"; last=\"$cur\"; fi; "
            + "sleep 1.5; done"]
        stdout: SplitParser {
            onRead: (line) => {
                const parts = line.trim().split(" ");
                if (parts.length < 2)
                    return;
                const cam = parseInt(parts[0], 10);
                const scr = parseInt(parts[1], 10);
                if (!isNaN(cam))
                    root.cameraCount = cam;
                if (!isNaN(scr))
                    root.screenCount = scr;
            }
        }
    }
}
