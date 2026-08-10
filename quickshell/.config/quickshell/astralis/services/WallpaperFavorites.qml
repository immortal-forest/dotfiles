pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — persisted wallpaper favorites.
 *
 * A FileView+JsonAdapter over ~/.cache/astralis/wallpaper-favorites.json
 * ({ "favorites": [absolute paths…] }). blockLoading so `list` is correct on
 * first read; watchChanges so external edits land live. Missing file ⇒ empty
 * list; the first toggle() creates it (mkdir guard below covers a fresh
 * ~/.cache on new machines).
 */
Singleton {
    id: root

    readonly property var list: adapter.favorites

    // A write attempted before the cache dir exists is deferred and flushed from
    // mkdirProc.onExited, so the first-ever toggle can't race the async mkdir.
    property bool dirReady: false
    property bool pendingWrite: false

    function has(path) {
        return adapter.favorites.indexOf(path) !== -1;
    }

    function toggle(path) {
        if (!path || !path.length)
            return;
        const next = adapter.favorites.slice();
        const i = next.indexOf(path);
        if (i === -1)
            next.push(path);
        else
            next.splice(i, 1);
        adapter.favorites = next;
        if (root.dirReady)
            file.writeAdapter();
        else
            root.pendingWrite = true;
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.cache/astralis/wallpaper-favorites.json"
        blockLoading: true
        watchChanges: true
        printErrors: false      // silent when the file doesn't exist yet
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property var favorites: []
        }
    }

    // writeAdapter() can't create directories; create the cache dir first, then
    // flush any write that landed before it existed.
    Component.onCompleted: mkdirProc.running = true
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.cache/astralis"]
        onExited: {
            root.dirReady = true;
            if (root.pendingWrite) {
                root.pendingWrite = false;
                file.writeAdapter();
            }
        }
    }
}
