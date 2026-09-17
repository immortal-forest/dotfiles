pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

/**
 * astralis — 録 screen-recording service (the backend the Recorder surface,
 * the rest-pill capture chip and the record OSD all read).
 *
 * astralis does NOT ship its own encoder: it drives whichever wlroots screen
 * recorder is installed, detected once at startup and exposed as `installed`.
 * Three are understood, in preference order:
 *
 *  1. **gpu-screen-recorder** — fully GPU-encoded (NVENC / VAAPI), the only one
 *     of the three that can pause mid-recording, draw the cursor on request and
 *     merge two audio devices into one track. Sources map to `-w <monitor>` /
 *     `-w region -region WxH+X+Y`.
 *  2. **wl-screenrec** — VAAPI, wlr-screencopy. `-o <monitor>` / `-g "x,y WxH"`
 *     (mutually exclusive). Damage-tracked, so `-m` sets a framerate CEILING
 *     the real rate floats below, and quality is a raw `-b` bitrate in BYTES
 *     per second rather than a preset. Cannot merge two audio devices.
 *  3. **wf-recorder** — ffmpeg/libx264 by default, so quality is a CRF and the
 *     framerate is explicit; `-o <monitor>` / `-g "x,y WxH"`.
 *
 * Flags each backend does not implement are never passed — `cap` publishes what
 * the selected backend can do so the surface can dim the rows it would ignore,
 * rather than silently lying about a setting. Everything the recorder prints on
 * a failed launch lands in `error`, so a flag that drifted in a newer release of
 * one of these tools shows up as its own message instead of a dead UI.
 *
 * Geometry for the window and region sources comes from `slurp` (window mode
 * feeds it the current workspaces' client rects, so a click picks a window);
 * cancelling the picker aborts the take. Audio devices are read live off
 * Pipewire — the default sink's `.monitor` for desktop audio, the default
 * source for the mic — which is the same device naming all three tools take.
 *
 * The recorder runs as a tracked `Process`, so stopping is a real SIGINT
 * (`stop()`), which is what makes each of these finalise the container instead
 * of leaving a truncated file. Settings live in Flags (`record*`), so they
 * persist and are shared with the settings tree.
 */
Singleton {
    id: root

    // ── backend detection ───────────────────────────────────────────────────

    /** Preference order; `installed` keeps this order. */
    readonly property var known: ["gpu-screen-recorder", "wl-screenrec", "wf-recorder"]

    /** Which of `known` are actually on PATH (probed once at startup). */
    property var installed: []
    property bool probed: false

    /**
     * The backend in use: the user's pick when it is installed, else the best
     * installed one, else empty (nothing to record with).
     */
    readonly property string backend: {
        const want = Flags.recordBackend;
        if (want.length > 0 && installed.indexOf(want) !== -1)
            return want;
        return installed.length > 0 ? installed[0] : "";
    }

    readonly property bool available: backend.length > 0

    /**
     * What each backend actually implements. The surface dims the rows a
     * backend would ignore; `buildArgv` never emits a flag whose cap is false.
     */
    readonly property var caps: ({
        "gpu-screen-recorder": { fps: true,  quality: true,  cursor: true,  pause: true,  mergeAudio: true },
        "wl-screenrec":        { fps: true,  quality: true,  cursor: true,  pause: false, mergeAudio: false },
        "wf-recorder":         { fps: true,  quality: true,  cursor: false, pause: false, mergeAudio: false }
    })
    /**
     * With no backend installed nothing is KNOWN to be unsupported, so the
     * settings stay live and configurable — dimming them all would leave the
     * surface with nothing the user could touch, and the whole point of the
     * dimming is "the recorder you picked ignores this", which needs a picked
     * recorder to mean anything. `pause` stays false because it gates a live
     * transport control rather than a setting, and there is no take to pause.
     */
    readonly property var cap: caps[backend] !== undefined ? caps[backend]
        : ({ fps: true, quality: true, cursor: true, pause: false, mergeAudio: true })

    readonly property var labels: ({
        "gpu-screen-recorder": "GPU Screen Recorder",
        "wl-screenrec": "wl-screenrec",
        "wf-recorder": "wf-recorder"
    })
    readonly property string backendLabel: labels[backend] !== undefined ? labels[backend] : ""

    Process {
        id: probe
        running: true
        command: ["sh", "-c",
            "for b in gpu-screen-recorder wl-screenrec wf-recorder; do "
            + "command -v \"$b\" >/dev/null 2>&1 && echo \"$b\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                const lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const n = lines[i].trim();
                    if (n.length > 0 && root.known.indexOf(n) !== -1)
                        found.push(n);
                }
                root.installed = found;
                root.probed = true;
            }
        }
    }

    /** Re-run detection (after the user installs one without restarting the shell). */
    function rescan() {
        probe.running = false;
        probe.running = true;
    }

    // ── live state ──────────────────────────────────────────────────────────

    property bool recording: false
    property bool paused: false

    /** Set by stop() so the process's onExited can tell a requested stop from a crash. */
    property bool stopRequested: false

    /** Counting down before the take starts (the picker is already done by then). */
    property bool arming: false
    property int countdown: 0

    /** Seconds of actual (unpaused) capture in the current take. */
    property int elapsed: 0

    /** "screen" | "window" | "region" — what the current/last take captures. */
    property string source: "screen"

    /** Absolute path being written right now, and the last one finished. */
    property string outputFile: ""
    property string lastFile: ""

    /** Last failure text (recorder stderr, or a local reason). Cleared on each start. */
    property string error: ""

    signal started()
    signal stopped(string file)
    signal failed(string message)

    /** True from the moment a take is requested until it has fully stopped. */
    readonly property bool busy: recording || arming || picking

    property bool picking: false

    // ── settings (persisted in Flags) ───────────────────────────────────────

    readonly property string dir: Flags.recordDir.length > 0 ? Flags.recordDir
        : Quickshell.env("HOME") + "/Videos/astralis"

    readonly property var fpsOptions: [30, 60, 120, 144]
    readonly property var qualityOptions: ["medium", "high", "very_high", "ultra"]

    /** gpu-screen-recorder takes these verbatim; the others get a mapping. */
    readonly property var crfFor: ({ medium: 28, high: 23, very_high: 20, ultra: 17 })
    /** wl-screenrec's -b is BYTES per second (its own default is "5 MB" ≈ 40 Mbps). */
    readonly property var bitrateFor: ({ medium: "2.5 MB", high: "5 MB", very_high: "10 MB", ultra: "20 MB" })

    // ── audio devices (live off Pipewire; the same names all three take) ────

    readonly property string desktopDevice: {
        const sink = Pipewire.defaultAudioSink;
        return sink && sink.name ? sink.name + ".monitor" : "";
    }
    readonly property string micDevice: {
        const src = Pipewire.defaultAudioSource;
        return src && src.name ? src.name : "";
    }

    /**
     * Not for the properties above (`name` is a plain PwNode field), but to
     * reference Pipewire at construction: the connection is established
     * asynchronously on first use, so a singleton that only touches it inside
     * buildArgv() would read null devices and silently drop audio from a take
     * started seconds after login. Binding here starts the connection when
     * ScreenRec itself is instantiated.
     */
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(Boolean)
    }

    // ── formatting helpers ──────────────────────────────────────────────────

    function pad(n) {
        return n < 10 ? "0" + n : "" + n;
    }

    /** m:ss up to an hour, then h:mm:ss. */
    function clockText(sec) {
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        const s = Math.floor(sec % 60);
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s);
    }

    readonly property string elapsedText: clockText(elapsed)

    function baseName(path) {
        const i = path.lastIndexOf("/");
        return i === -1 ? path : path.slice(i + 1);
    }

    // ── take sequencing ─────────────────────────────────────────────────────
    //
    // start(kind) → [pick geometry] → mkdir output dir → countdown → launch.
    // Each step is a Process exit or a timer tick, so any of them can abort the
    // take by calling cancel(); nothing is spawned until the step before it
    // actually succeeded.

    property string pendingKind: ""
    property string pendingGeometry: ""
    property string pendingMonitor: ""

    function focusedMonitorName() {
        const m = Hyprland.focusedMonitor;
        return m && m.name ? m.name : "";
    }

    /** kind: "screen" | "window" | "region". */
    function start(kind) {
        if (root.recording || root.arming || root.picking)
            return;
        if (!root.available) {
            root.fail("No screen recorder installed — install gpu-screen-recorder, wl-screenrec or wf-recorder.");
            return;
        }

        root.error = "";
        root.pendingKind = (kind === "window" || kind === "region") ? kind : "screen";
        root.pendingGeometry = "";
        root.pendingMonitor = root.focusedMonitorName();

        if (root.pendingKind === "region") {
            root.picking = true;
            picker.command = ["sh", "-c", "slurp -d"];
            picker.running = true;
        } else if (root.pendingKind === "window") {
            root.picking = true;
            // Feed slurp every client on the workspaces currently shown, so a
            // click snaps to a whole window instead of a freehand box.
            picker.command = ["sh", "-c",
                "ws=$(hyprctl -j monitors | jq -r 'map(.activeWorkspace.id) | join(\",\")') || exit 1; "
                + "hyprctl -j clients "
                + "| jq -r --argjson w \"[$ws]\" '.[] | select([.workspace.id] | inside($w)) "
                + "| \"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"' "
                + "| slurp -r"];
            picker.running = true;
        } else {
            root.prepare();
        }
    }

    function toggle(kind) {
        if (root.recording || root.arming || root.picking)
            root.stop();
        else
            root.start(kind);
    }

    /**
     * Geometry picker (slurp). The decision hangs off the collector rather
     * than the exit code because the two arrive independently and the text is
     * the thing being waited on: an Escape (or a broken pipeline) closes the
     * stream with nothing on it, which is exactly the abort condition.
     */
    Process {
        id: picker
        stdout: StdioCollector {
            onStreamFinished: {
                const g = this.text.trim();
                if (g.length === 0 || root.parseGeometry(g) === null) {
                    root.pendingGeometry = "";
                    root.pendingKind = "";
                    return;
                }
                root.pendingGeometry = g;
                root.prepare();
            }
        }
        onExited: root.picking = false
    }

    function prepare() {
        root.source = root.pendingKind;
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        root.outputFile = root.dir + "/astralis_" + stamp + ".mp4";
        mkdir.command = ["mkdir", "-p", root.dir];
        mkdir.running = true;
    }

    Process {
        id: mkdir
        onExited: (code) => {
            if (code !== 0) {
                root.fail("Could not create " + root.dir);
                return;
            }
            root.beginCountdown();
        }
    }

    function beginCountdown() {
        const n = Math.max(0, Flags.recordCountdown);
        if (n === 0) {
            root.launch();
            return;
        }
        root.countdown = n;
        root.arming = true;
        countTimer.restart();
    }

    Timer {
        id: countTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0) {
                countTimer.stop();
                root.arming = false;
                root.launch();
            }
        }
    }

    /** Abort a pending take, or stop a running one. */
    function cancel() {
        countTimer.stop();
        root.arming = false;
        root.countdown = 0;
        root.pendingKind = "";
        root.pendingGeometry = "";
        if (picker.running)
            picker.running = false;
    }

    function fail(message) {
        root.cancel();
        root.error = message;
        root.failed(message);
    }

    // ── argv ────────────────────────────────────────────────────────────────

    /** slurp prints "x,y WxH"; split it for the backends that want the parts. */
    function parseGeometry(g) {
        const parts = g.split(" ");
        if (parts.length < 2)
            return null;
        const pos = parts[0].split(",");
        const size = parts[1].split("x");
        if (pos.length < 2 || size.length < 2)
            return null;
        const out = {
            x: parseInt(pos[0], 10),
            y: parseInt(pos[1], 10),
            w: parseInt(size[0], 10),
            h: parseInt(size[1], 10)
        };
        if (isNaN(out.x) || isNaN(out.y) || isNaN(out.w) || isNaN(out.h) || out.w <= 0 || out.h <= 0)
            return null;
        return out;
    }

    /** Devices this take should capture, most-wanted first. */
    function audioDevices() {
        const devs = [];
        if (Flags.recordDesktop && root.desktopDevice.length > 0)
            devs.push(root.desktopDevice);
        if (Flags.recordMic && root.micDevice.length > 0)
            devs.push(root.micDevice);
        return devs;
    }

    function buildArgv() {
        const out = root.outputFile;
        const geom = root.pendingGeometry;
        const mon = root.pendingMonitor;
        const devs = root.audioDevices();
        const fps = Math.max(10, Flags.recordFps);
        const quality = root.qualityOptions.indexOf(Flags.recordQuality) !== -1 ? Flags.recordQuality : "high";

        if (root.backend === "gpu-screen-recorder") {
            const a = ["gpu-screen-recorder"];
            if (geom.length > 0) {
                const g = root.parseGeometry(geom);
                if (g === null)
                    return null;
                // Region capture; on releases without it gpu-screen-recorder
                // exits with its own message, which lands in `error`.
                a.push("-w", "region", "-region", g.w + "x" + g.h + "+" + g.x + "+" + g.y);
            } else {
                a.push("-w", mon.length > 0 ? mon : "screen");
            }
            a.push("-f", String(fps));
            a.push("-q", quality);
            a.push("-k", "auto");
            a.push("-cursor", Flags.recordCursor ? "yes" : "no");
            // gpu-screen-recorder names sources symbolically (`default_output`,
            // `default_input`, `device:<name>`, `app:<name>`), and combines them
            // with `|` into ONE track — separate -a flags would make a second
            // track most players ignore. The symbolic aliases are used rather
            // than the resolved Pipewire node names so the take follows whatever
            // is default at launch, with no naming mismatch to get wrong.
            const gsrDevs = [];
            if (Flags.recordDesktop)
                gsrDevs.push("default_output");
            if (Flags.recordMic)
                gsrDevs.push("default_input");
            if (gsrDevs.length > 0)
                a.push("-a", gsrDevs.join("|"));
            a.push("-c", "mp4");
            a.push("-o", out);
            return a;
        }

        if (root.backend === "wl-screenrec") {
            const a = ["wl-screenrec", "-f", out, "--codec", "auto"];
            // -g and -o are mutually exclusive here (it says so itself).
            if (geom.length > 0)
                a.push("-g", geom);
            else if (mon.length > 0)
                a.push("-o", mon);
            // `-m` is a CEILING, not a target: wl-screenrec only copies changed
            // frames, so the real rate floats below this with damage tracking.
            a.push("-m", String(fps));
            // Quality is a bitrate rather than a preset, and the unit is BYTES
            // per second — "5 MB" is its own default, i.e. 40 Mbps.
            a.push("-b", root.bitrateFor[quality]);
            if (!Flags.recordCursor)
                a.push("--no-cursor");
            // One device only (no merge), and it wants a pactl source name —
            // which is exactly what the Pipewire node names resolve to.
            if (devs.length > 0)
                a.push("--audio", "--audio-device", devs[0]);
            return a;
        }

        if (root.backend === "wf-recorder") {
            const a = ["wf-recorder", "-f", out];
            if (geom.length > 0)
                a.push("-g", geom);
            else if (mon.length > 0)
                a.push("-o", mon);
            a.push("-r", String(fps));
            // Software libx264 is wf-recorder's default encoder, so quality is
            // a CRF; a lower number is a bigger, better file.
            a.push("-p", "crf=" + root.crfFor[quality]);
            // `--audio=<dev>`, never `-a <dev>`: wf-recorder's audio flag takes
            // an OPTIONAL argument, so a separated value is not consumed by it —
            // it would be read as a positional and clobber the output path.
            if (devs.length > 0)
                a.push("--audio=" + devs[0]);
            return a;
        }

        return null;
    }

    function launch() {
        const argv = root.buildArgv();
        if (argv === null) {
            root.fail("Could not build a command for " + root.backend);
            return;
        }
        errText.clear();
        rec.command = argv;
        rec.running = true;
    }

    QtObject {
        id: errText
        property string buffer: ""
        function clear() { buffer = ""; }
    }

    Process {
        id: rec

        stderr: SplitParser {
            onRead: (line) => {
                const t = line.trim();
                if (t.length === 0)
                    return;
                // Keep the tail: the useful message is what it said last.
                errText.buffer = (errText.buffer.length > 0 ? errText.buffer + "\n" : "") + t;
                const lines = errText.buffer.split("\n");
                if (lines.length > 6)
                    errText.buffer = lines.slice(lines.length - 6).join("\n");
            }
        }

        onStarted: {
            root.elapsed = 0;
            root.paused = false;
            root.recording = true;
            root.started();
        }

        onExited: (code) => {
            const file = root.outputFile;
            const wasRecording = root.recording;
            root.recording = false;
            root.paused = false;
            root.outputFile = "";

            // Recorders stopped with SIGINT report the signal, not a clean 0;
            // a written file is the real success signal, so treat a stop we
            // asked for as success and only surface an unexpected exit.
            if (wasRecording && root.stopRequested) {
                root.stopRequested = false;
                root.lastFile = file;
                root.stopped(file);
                root.toast("normal", "Recording saved", root.baseName(file));
                return;
            }
            root.stopRequested = false;

            const why = errText.buffer.length > 0 ? errText.buffer
                : (root.backend + " exited with code " + code);
            root.error = why;
            root.failed(why);
        }
    }

    /**
     * astralis owns org.freedesktop.Notifications, so this lands as an in-pill
     * toast. It is the only feedback a take started from a keybind gets when it
     * fails — the OSD only flashes on a recording actually opening or closing,
     * and a start that never got that far would otherwise be silent.
     */
    function toast(urgency, title, body) {
        notify.running = false;
        notify.command = ["notify-send", "-u", urgency, "-a", "astralis",
            "-i", "video-x-generic", title, body];
        notify.running = true;
    }

    onFailed: (message) => root.toast("critical", "Recording failed", message)

    Process { id: notify }

    /**
     * SIGINT rather than dropping `running` (which sends SIGTERM): all three
     * recorders treat an interrupt as "finish and mux", so the container is
     * closed properly instead of the file being left truncated.
     */
    function stop() {
        if (!root.recording) {
            root.cancel();
            return;
        }
        root.stopRequested = true;
        rec.signal(2);
    }

    /**
     * Only gpu-screen-recorder implements pause, as a SIGUSR2 toggle; the
     * others have no equivalent, so the surface hides the control (cap.pause).
     */
    function togglePause() {
        if (!root.recording || !root.cap.pause)
            return;
        rec.signal(12); // SIGUSR2
        root.paused = !root.paused;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording && !root.paused
        onTriggered: root.elapsed += 1
    }

    // ── output folder ───────────────────────────────────────────────────────

    function openLast() {
        if (root.lastFile.length === 0)
            return;
        open.command = ["xdg-open", root.lastFile];
        open.running = true;
    }

    function openFolder() {
        open.command = ["xdg-open", root.dir];
        open.running = true;
    }

    Process { id: open }
}
