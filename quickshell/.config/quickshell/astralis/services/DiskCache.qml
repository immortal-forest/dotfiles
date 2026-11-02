pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — small JSON files under ~/.cache/astralis/<bucket>/<md5(key)>.json,
 * one per track, read only when that track plays. Used by Lyrics (results per
 * source) and TrackInfo (alternate-cover search). Files nobody has opened for
 * 90 days are deleted at startup (artcache images too).
 */
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.cache/astralis"

    function path(bucket, key) {
        return root.dir + "/" + bucket + "/" + Qt.md5(String(key)) + ".json";
    }

    /** cb(object) — null when missing or unreadable. Touches the file (keeps it from pruning). */
    function read(bucket, key, cb) {
        var p = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root, "DiskCache.read");
        p.command = ["sh", "-c", '[ -f "$0" ] && touch -a "$0" && cat "$0"', root.path(bucket, key)];
        p.exited.connect(function (code) {
            var obj = null;
            if (code === 0)
                try { obj = JSON.parse(p.stdout.text); } catch (e) {}
            p.destroy();
            cb(obj);
        });
        p.running = true;
    }

    /** Atomic write (tmp + mv); the JSON goes through stdin, so size is no issue. */
    function write(bucket, key, obj) {
        var json = JSON.stringify(obj);
        var p = Qt.createQmlObject('import Quickshell.Io; Process { stdinEnabled: true }', root, "DiskCache.write");
        p.command = ["sh", "-c", 'mkdir -p "${0%/*}" && cat > "$0.tmp" && mv "$0.tmp" "$0"', root.path(bucket, key)];
        p.started.connect(function () {
            p.write(json);
            p.stdinEnabled = false;     // EOF → cat finishes
        });
        p.exited.connect(function () { p.destroy(); });
        p.running = true;
    }

    Process {
        running: true
        command: ["sh", "-c", 'for d in lyrics covers artcache; do [ -d "$0/$d" ] && find "$0/$d" -type f -atime +90 -delete; done; true', root.dir]
    }
}
