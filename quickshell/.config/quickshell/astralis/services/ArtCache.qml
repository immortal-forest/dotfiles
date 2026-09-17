pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

/**
 * astralis — a local copy of whatever album art is CURRENTLY playing, kept
 * so the lock screen never has to touch the network to show a cover.
 *
 * The problem this exists for: `Players.artUrlFor()` returns whatever the
 * MPRIS player reports via `trackArtUrl`, and that is a `file:` path only
 * when the PLAYER ITSELF already cached that cover — Spotify does this
 * inconsistently, and browser/web players essentially never do. Quickshell
 * does no caching of its own; astralis was previously (wrongly) documented
 * as relying on that. The result was art that showed on the lock screen for
 * some tracks and silently fell back to the placeholder for others, with no
 * visible reason why — confusing, not a real privacy boundary.
 *
 * This singleton is the fix: it watches `Players.artUrl`/`trackKey` and, the
 * moment a track lands on a remote http(s) cover, downloads ONE copy to
 * `~/.cache/astralis/artcache/`. `LockSurface.qml`'s `artSrc` then prefers
 * this cache over the raw MPRIS url, so by the time anyone actually locks
 * the screen the art for whatever is playing has near-certainly already
 * landed — the lock screen still never initiates a fetch itself, it only
 * ever reads a file that is already sitting on disk.
 *
 * `cached`/`attempted` are in-memory, so a hot-reload of this singleton
 * forgets what it already fetched and `Component.onCompleted` re-attempts —
 * cheap (one small image) and only a dev-time concern; nothing a normal
 * running session ever hits.
 *
 * The one honest gap: skipping tracks FROM the lock screen's own 前/次 (or
 * `Players.next()`/`previous()`) changes `artUrl` while still locked, and
 * this singleton — which runs unconditionally, same as `Players` itself —
 * will fetch that new cover right then. That is a real, if narrow, way a
 * lock-screen action can cause outbound traffic; everything else (arriving
 * already locked, or the track changing on its own) never does, because the
 * fetch already happened earlier, while unlocked.
 */
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.cache/astralis/artcache"

    Process {
        command: ["mkdir", "-p", root.dir]
        running: true
    }

    /** Filesystem-safe stand-in for a track key, capped so paths stay sane. */
    function safeKey(k) {
        return String(k).replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 120);
    }

    readonly property string currentKey: Players.trackKey
    readonly property string currentUrl: Players.artUrl
    readonly property bool currentIsRemote: currentUrl.indexOf("http:") === 0
        || currentUrl.indexOf("https:") === 0

    /** key → true once a fetch for it has been started (success or not — never retried). */
    property var attempted: ({})
    /** key → local filesystem path, once a fetch actually lands (curl exits 0). */
    property var cached: ({})

    /** file:// URL for the CURRENTLY PLAYING track's art, once cached; "" otherwise. */
    readonly property string localArt: (currentKey.length > 0 && root.cached[currentKey])
        ? "file://" + root.cached[currentKey] : ""

    onCurrentUrlChanged: root.maybeFetch()
    onCurrentKeyChanged: root.maybeFetch()
    Component.onCompleted: root.maybeFetch()

    /**
     * One attempt per key, ever. A key already in `cached` needs nothing; a
     * key already in `attempted` without a `cached` entry failed once (dead
     * link, offline, timeout) and is left alone rather than hammered on
     * every re-evaluation of this binding.
     */
    function maybeFetch() {
        if (!root.currentIsRemote || root.currentKey.length === 0)
            return;
        if (root.attempted[root.currentKey])
            return;
        var a = Object.assign({}, root.attempted);
        a[root.currentKey] = true;
        root.attempted = a;

        var key = root.currentKey;
        var url = root.currentUrl;
        var out = root.dir + "/" + root.safeKey(key) + ".img";

        // A fresh Process per fetch (rather than one reused instance) so an
        // overlapping track change never has to queue behind or clobber a
        // request already in flight — each is independent and self-destructs.
        // Atomic: curl writes to `.part` and only `mv`s it into place on its
        // own success (exit 0), so a failed/partial download never leaves a
        // truncated file behind or gets marked `cached`.
        var p = Qt.createQmlObject(
            'import Quickshell.Io; Process {}', root, "ArtCache.fetch");
        p.command = ["sh", "-c",
            'curl -fsL --max-time 8 -o "$1.part" "$0" && mv "$1.part" "$1"',
            url, out];
        p.exited.connect(function (code) {
            if (code === 0) {
                var c = Object.assign({}, root.cached);
                c[key] = out;
                root.cached = c;
            }
            p.destroy();
        });
        p.running = true;
    }
}
