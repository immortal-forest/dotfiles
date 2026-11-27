pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

/**
 * astralis — sound follows Bluetooth (adopted from quartz's Audio.qml). A
 * Bluetooth output that connects while the shell runs becomes the default
 * sink, with a toast. WirePlumber only restores the output last picked by
 * hand, so without this a headset can connect while the sound stays on the
 * speakers. Outputs already there at startup don't count, so a shell reload
 * never moves the sound. Force-loaded from shell.qml.
 */
Singleton {
    id: root

    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    /** Ids of the sinks already known; null until Pipewire has settled after startup. */
    property var seen: null
    property var pending: null

    onSinksChanged: {
        if (!seen)
            return;
        const now = {};
        for (const n of sinks) {
            now[n.id] = true;
            if (!seen[n.id] && (n.name || "").startsWith("bluez_output"))
                pending = n;
        }
        seen = now;
        if (pending)
            follow.restart();
    }

    // Startup: take whatever is there as already known.
    Timer {
        interval: 2500
        running: Pipewire.ready
        onTriggered: {
            const now = {};
            for (const n of root.sinks)
                now[n.id] = true;
            root.seen = now;
        }
    }

    // A moment for the new node to finish binding before WirePlumber is asked.
    Timer {
        id: follow
        interval: 400
        onTriggered: {
            const n = root.pending;
            root.pending = null;
            if (!n || root.sinks.indexOf(n) < 0 || n === Pipewire.defaultAudioSink)
                return;
            Pipewire.preferredDefaultAudioSink = n;
            Quickshell.execDetached(["notify-send", "-a", "astralis", "-i", "audio-headphones",
                "Sound", "Now playing on " + (n.description || n.nickname || n.name)]);
        }
    }
}
