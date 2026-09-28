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
 *  - camera — `fuser /dev/video*` lists PIDs holding a video device open
 *             (covers pipewire/libcamera AND direct v4l2 apps; wireplumber
 *             only opens the device while a client streams, so idle is clean
 *             — live-verified). fuser walks every fd of every process
 *             (~115ms CPU here), so it runs only when inotify reports an
 *             open/close on a device node, never on a clock.
 *
 *  - screen — Pipewire `Stream/Output/Video` nodes, in-process
 *             (xdg-desktop-portal-hyprland publishes one exactly while a
 *             screencast runs), OR-ed with a pgrep for the direct
 *             wlr-screencopy recorders that bypass the portal. The pgrep
 *             runs only when inotify sees one of those binaries exec or exit.
 *             `obs` is deliberately not counted — an idle OBS window isn't a
 *             capture, and when it does cast it goes through the portal node
 *             anyway. (`gpu-screen-reco.*` because comm truncates at 15.)
 *
 * The old design polled fuser + pw-cli + pgrep every 1.5s: ~11% of a core,
 * permanently, to watch for events that happen a few times a day.
 */
Singleton {
    id: root

    readonly property bool micActive: micCount > 0
    readonly property bool cameraActive: cameraCount > 0
    readonly property bool screenActive: screenCount > 0
    readonly property bool anyActive: micActive || cameraActive || screenActive

    property int micCount: 0
    property int cameraCount: 0
    readonly property int screenCount: castCount + recorderCount
    property int recorderCount: 0

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
    Component.onCompleted: {
        Qt.callLater(root.recountMic);
        // Baseline for the event-driven camera/recorder probes below.
        camProbe.running = true;
        recProbe.running = true;
    }

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

    // ── screencasts (event-driven Pipewire) ─────────────────────────────────

    /**
     * Quickshell only classifies the audio classes and Video/Source|Sink; a
     * screencast's `Stream/Output/Video` node lands as Untracked, and its
     * class is readable only once bound. There are only a handful of those
     * (MIDI bridges, drivers, bluez internals), so bind them all and count
     * by class. `properties` notifies, so the count follows on its own.
     */
    readonly property var untrackedNodes: {
        const out = [];
        const all = Pipewire.nodes.values;
        for (let i = 0; i < all.length; i++) {
            const n = all[i];
            if (n && n.type === PwNodeType.Untracked)
                out.push(n);
        }
        return out;
    }

    PwObjectTracker { objects: root.untrackedNodes }

    readonly property int castCount: {
        let c = 0;
        const l = root.untrackedNodes;
        for (let i = 0; i < l.length; i++) {
            const p = l[i] ? l[i].properties : null;
            if (p && p["media.class"] === "Stream/Output/Video")
                c++;
        }
        return c;
    }

    // ── camera + direct recorders (inotify-triggered probes) ────────────────

    /**
     * One inotifywait over the video nodes and whichever recorder binaries
     * exist. An exec of a watched binary reports OPEN and its exit CLOSE, so
     * the recorder pgrep runs exactly when one starts or stops. With the
     * Legion's camera switch off there are no nodes, and nothing to watch.
     *
     * `inotifywait -m` never exits on its own — it idles with zero watches
     * after every watched file is deleted (live-verified) — so re-arming is
     * ours: on a node/binary DELETE_SELF or MOVE_SELF (a camera unplug, a
     * package upgrade replacing a binary) and on every CameraToggle flip.
     *
     * Without inotify-tools it degrades to a slow tick that re-probes both.
     * setpriv --pdeathsig (kept across the exec): inotifywait writes only on
     * an event, so an orphan would otherwise outlive a crashed shell.
     */
    Process {
        id: watcher
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", "sh", "-c",
            "set --; "
            + "for f in /dev/video*; do [ -e \"$f\" ] && set -- \"$@\" \"$f\"; done; "
            + "for b in wf-recorder wl-screenrec gpu-screen-recorder; do "
            + "p=$(command -v \"$b\" 2>/dev/null) && set -- \"$@\" \"$p\"; done; "
            + "[ $# -gt 0 ] || exit 0; "
            + "command -v inotifywait >/dev/null 2>&1 || "
            + "exec sh -c 'while :; do echo \"TICK -\"; sleep 3; done'; "
            + "exec inotifywait -m -q -e open,close,delete_self,move_self --format '%e %w' \"$@\""]
        stdout: SplitParser {
            onRead: (line) => {
                const sp = line.indexOf(" ");
                const ev = sp > 0 ? line.slice(0, sp) : line;
                const path = sp > 0 ? line.slice(sp + 1) : "";
                if (ev === "TICK") {
                    camSettle.restart();
                    recSettle.restart();
                    return;
                }
                if (ev.indexOf("DELETE_SELF") !== -1 || ev.indexOf("MOVE_SELF") !== -1)
                    root.rearm();
                if (path.indexOf("/dev/video") === 0)
                    camSettle.restart();
                else
                    recSettle.restart();
            }
        }
        // Only an unexpected failure retries, and slowly; a clean exit means
        // there was nothing to watch, and our own rearm stop is not a failure.
        onExited: (code) => {
            if (!root.rearming && code !== 0)
                rearmTimer.start();
        }
    }

    property bool rearming: false

    function rearm() {
        rearming = true;
        watcher.running = false;
        rearmTimer.restart();
    }

    Timer {
        id: rearmTimer
        interval: root.rearming ? 400 : 10000
        onTriggered: {
            root.rearming = false;
            watcher.running = true;
            camSettle.restart();
            recSettle.restart();
        }
    }

    // A flipped switch adds or removes the nodes; watch the new set.
    Connections {
        target: CameraToggle
        function onPresentChanged() { root.rearm(); }
    }

    // Debounced so an app's quick probe (open → close) settles before fuser
    // counts; a probe that is already closed counts 0 and never flashes.
    Timer {
        id: camSettle
        interval: 300
        onTriggered: camProbe.running = true
    }

    Timer {
        id: recSettle
        interval: 300
        onTriggered: recProbe.running = true
    }

    Process {
        id: camProbe
        command: ["sh", "-c", "fuser /dev/video* 2>/dev/null | wc -w"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(this.text, 10);
                root.cameraCount = isNaN(n) ? 0 : n;
            }
        }
    }

    Process {
        id: recProbe
        command: ["pgrep", "-cx", "wf-recorder|wl-screenrec|gpu-screen-reco.*"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(this.text, 10);
                root.recorderCount = isNaN(n) ? 0 : n;
            }
        }
    }
}
