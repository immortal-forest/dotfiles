pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — clipboard history store behind the 控 Clipboard surface. cliphist
 * (fed by the wl-paste watchers in hypr.d/autostart.lua) is the database; this
 * holds the parsed list for the shell's lifetime, so a surface rebuilt by the
 * pill's 30s idle reaper opens on the last snapshot instead of an empty list
 * and re-syncs in the background.
 *
 * A refresh is one `cliphist list` (~10ms), which lands right away, then a
 * thumbnail pass (scripts/clip-thumbs) over the image entries: it prunes thumbs
 * of entries that left the history, makes 208x128 thumbs for new images, and
 * prints the ready ones. Thumbs are keyed `<id>-<size+dims>` (`thumbKey`), not
 * by id alone, because cliphist reuses ids after a wipe or rebuild. An image
 * row binds its thumb only once its key is ready, so a row never points at a
 * missing or foreign file; a new image's thumb fades in a few frames after the
 * list.
 */
Singleton {
    id: root

    /** [{id, preview, secret, shown, hay, isImage, label, sizeLabel, thumbKey, thumb}], most recent first. */
    property var entries: []
    property bool unavailable: false

    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/astralis-cliphist/"
    // beside this file, not Quickshell.shellDir, so it resolves in dev harnesses too
    readonly property string thumbScript: decodeURIComponent(String(Qt.resolvedUrl("../scripts/clip-thumbs")).replace(/^file:\/\//, ""))

    // thumbKey → true for every image with a thumb on disk (filled by the thumb pass)
    property var readyThumbs: ({})

    // Deletes are queued and sent to cliphist in batches, one at a time, so a
    // fast run of ✕ clicks (or a multi-select delete) never drops an id.
    // `deleting` holds every id queued or in flight; a list that lands
    // meanwhile skips them, so a deleted row can't flash back.
    property var delQueue: []
    property var deleting: ({})

    // A refresh asked for mid-pass (e.g. the post-delete reload landing while
    // an open's pass runs) is remembered and flushed when the pass ends.
    property bool refreshPending: false

    function refresh() {
        if (listProc.running || thumbProc.running) {
            refreshPending = true;
            return;
        }
        listProc.exitSeen = false;
        listProc.running = true;
    }

    function validId(id) {
        return /^\d+$/.test(String(id));
    }

    /** Copy an entry back onto the clipboard. */
    function copy(id) {
        if (!validId(id))
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "_", String(id)]);
    }

    /** Delete one entry; the row goes at once, the db follows. */
    function remove(id) {
        removeMany([id]);
    }

    /**
     * Delete several entries; their rows go at once, the db follows in one
     * `cliphist delete` per batch. Their thumbs go with the post-delete
     * refresh's thumb pass, which prunes anything no longer listed.
     */
    function removeMany(ids) {
        var drop = {};
        var busy = Object.assign({}, deleting);
        var queue = delQueue.slice();
        for (var i = 0; i < ids.length; i++) {
            var id = String(ids[i]);
            if (!validId(id) || busy[id])
                continue;
            drop[id] = true;
            busy[id] = true;
            queue.push(id);
        }
        deleting = busy;
        delQueue = queue;
        entries = entries.filter(e => !drop[e.id]);
        flushDeletes();
    }

    function flushDeletes() {
        if (delProc.running || !delQueue.length)
            return;
        delProc.batch = delQueue;
        delQueue = [];
        delProc.command = ["sh", "-c", "printf '%s\\n' \"$@\" | cliphist delete", "_"].concat(delProc.batch);
        delProc.running = true;
    }

    function deletesDone() {
        var busy = Object.assign({}, deleting);
        for (var i = 0; i < delProc.batch.length; i++)
            delete busy[delProc.batch[i]];
        deleting = busy;
        delProc.batch = [];
        if (delQueue.length)
            flushDeletes();
        else
            refresh();
    }

    function wipe() {
        entries = [];
        readyThumbs = {};
        wipeProc.running = true;
    }

    function finishPass() {
        if (refreshPending) {
            refreshPending = false;
            refresh();
        }
    }

    /**
     * Key detection. A row that looks like a credential renders in Obel Mono
     * with its ss01 secret masking. Measured in Qt: ss01 masks uppercase
     * KEY=value lines and sk-/AQ./AIza/AKIA/gh*_/JWT/Slack-webhook tokens by
     * itself (`fontRe`), but leaves bare hex/base32 tokens, passwords and
     * lowercase `password=`/`token:` values readable, so those get bullets
     * here. Display only: cliphist keeps the real text and copying still pastes
     * it. Pure digits (OTPs, numbers) are never masked.
     */
    readonly property var fontRe: [
        /\b[A-Z][A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASSWD|PWD|AUTH)[A-Z0-9_]*\s*=\s*["']?[^\s"']{6,}/,
        /\bsk-[\w-]{16,}/, /\bAQ\.[\w-]{20,}/, /\bAIza[\w-]{30,}/, /\bAKIA[0-9A-Z]{16}\b/,
        /\bgh[pousr]_[A-Za-z0-9]{20,}/, /\beyJ[\w-]{8,}\.[\w-]{8,}\./, /hooks\.slack\.com\/services\//
    ]
    // name starts after a non-letter: `dokploy_api_key=` matches (no \b, `_`
    // is a word char) while `reauth=`/`oauth:` in URLs don't
    readonly property var valueRe: /(^|[^A-Za-z])((?:pass(?:word)?|passwd|pwd|token|secret|api[_-]?key|auth)["']?\s*[=:]\s*["']?|bearer\s+)([^\s"']{4,})/i
    readonly property var otherTokenRe: /\b(xox[abposr]-[\w-]{10,}|glpat-[\w-]{16,}|github_pat_\w{20,}|hf_[A-Za-z0-9]{20,}|discord(?:app)?\.com\/api\/webhooks\/\S+)/

    function dots(n) {
        return "•".repeat(Math.max(6, Math.min(n, 28)));
    }

    function charClass(ch) {
        return ch >= "0" && ch <= "9" ? 0 : ch >= "a" && ch <= "z" ? 1 : ch >= "A" && ch <= "Z" ? 2 : 3;
    }

    /**
     * Does this separator-free run look machine-generated? 16+ chars, letters
     * interleaved with digits (or case flipping on a third of the chars — random
     * base62, not CamelCase), and ≥3.3 bits/char of entropy. Prefix-agnostic,
     * so app_…, forge…, dokploy…, epidemic_live_… keys all qualify on their
     * random part. Git SHAs stay readable.
     */
    function randomish(seg) {
        if (seg.length < 16 || /^[0-9a-f]{40}$/.test(seg))
            return false;
        var flips = 0;
        for (var i = 1; i < seg.length; i++)
            if (charClass(seg[i]) !== charClass(seg[i - 1]))
                flips++;
        // digits+letters must interleave (hex/base36), not `episode12final…2026`
        var mixed = /\d/.test(seg) && /[A-Za-z]/.test(seg) && flips >= Math.max(4, seg.length / 6);
        if (!mixed && flips < seg.length / 3)
            return false;
        var f = {};
        for (var j = 0; j < seg.length; j++)
            f[seg[j]] = (f[seg[j]] || 0) + 1;
        var h = 0;
        for (var c in f) {
            var p = f[c] / seg.length;
            h -= p * Math.log(p) / Math.LN2;
        }
        return h >= 3.3;
    }

    /** Dots out the random run of every key-like word (links/paths/emails skipped), keeping its prefix + 4 chars; null if none. */
    function maskWords(s) {
        var parts = s.split(/(\s+)/);
        var hit = false;
        for (var w = 0; w < parts.length; w++) {
            var word = parts[w];
            if (!word.length || /\s/.test(word) || /[\/@]|:\/\//.test(word))
                continue;
            var segs = word.split(/([_\-.:=,;'"`()]+)/);
            var pos = 0;
            for (var k = 0; k < segs.length; k++) {
                if (k % 2 === 0 && randomish(segs[k])) {
                    parts[w] = word.slice(0, pos + 4) + dots(segs[k].length - 4) + word.slice(pos + segs[k].length);
                    hit = true;
                    break;
                }
                pos += segs[k].length;
            }
        }
        return hit ? parts.join("") : null;
    }

    function secretView(s) {
        var plain = { secret: false, shown: s };
        var t = s.trim();
        if (!t.length || /^\d+$/.test(t))
            return plain;
        for (var i = 0; i < fontRe.length; i++)
            if (fontRe[i].test(s))
                return { secret: true, shown: s };
        var m = otherTokenRe.exec(s);
        if (m)
            return { secret: true, shown: s.replace(m[1], m[1].slice(0, 6) + dots(m[1].length - 6)) };
        m = valueRe.exec(s);
        if (m && (/\d/.test(m[3]) || m[3].length >= 8))
            return { secret: true, shown: s.replace(m[0], m[1] + m[2] + dots(m[3].length)) };
        var masked = maskWords(s);
        if (masked !== null)
            return { secret: true, shown: masked };
        // A lone mixed-case word with digits reads as a password.
        var lone = !/\s/.test(t) && !/[\/@]|:\/\/|\.[a-z0-9]{2,4}$/i.test(t);
        if (lone && t.length >= 8 && t.length <= 64 && /[a-z]/.test(t) && /[A-Z]/.test(t) && /\d/.test(t))
            return { secret: true, shown: t.slice(0, 4) + dots(t.length - 4) };
        return plain;
    }

    function parseList(text) {
        var lines = text.split("\n");
        var out = [];
        var metaRe = /^\[\[ binary data (.*) \]\]$/;
        var imgRe = /\b(png|jpg|jpeg|gif|bmp|webp)\b/;
        var splitRe = /^(\S+ \S+) (\w+) (\d+)x(\d+)$/;
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            var tab = line.indexOf("\t");
            if (tab < 1)
                continue;
            var id = line.substring(0, tab);
            if (!/^\d+$/.test(id) || deleting[id])
                continue;
            var preview = line.substring(tab + 1);
            var m = metaRe.exec(preview);
            var isImage = m !== null && imgRe.test(m[1]);
            var label = "";
            var sizeLabel = "";
            var thumbKey = "";
            if (isImage) {
                thumbKey = id + "-" + m[1].replace(/[^A-Za-z0-9]+/g, "");
                var p = splitRe.exec(m[1]);
                label = p ? p[2] + " " + p[3] + "×" + p[4] : m[1];
                sizeLabel = p ? p[1] : "";
            }
            var sv = isImage ? { secret: false, shown: preview } : secretView(preview);
            out.push({
                id: id,
                preview: preview,
                secret: sv.secret,
                shown: sv.shown,
                // lowercased once here, not on every search keystroke
                hay: (isImage ? label + " " + sizeLabel : preview).toLowerCase(),
                isImage: isImage,
                label: label,
                sizeLabel: sizeLabel,
                thumbKey: thumbKey,
                thumb: isImage && readyThumbs[thumbKey] ? thumbDir + thumbKey + ".png" : ""
            });
        }
        return out;
    }

    // Quickshell delivers streamFinished, then exited, then running=false; a
    // binary that fails to start gets only running=false. So output is stashed
    // on stream end and committed on exit, and a failed `cliphist list` never
    // replaces a good snapshot with an empty one.
    function listExited(code) {
        if (code !== 0) {
            unavailable = true;
            finishPass();
            return;
        }
        unavailable = false;
        entries = parseList(listProc.out);
        var keys = [];
        for (var i = 0; i < entries.length; i++)
            if (entries[i].isImage)
                keys.push(entries[i].thumbKey);
        thumbProc.command = ["sh", thumbScript, thumbDir].concat(keys);
        thumbProc.exitSeen = false;
        thumbProc.running = true;
    }

    function thumbsExited() {
        var ready = {};
        var lines = thumbProc.out.split("\n");
        for (var i = 0; i < lines.length; i++)
            if (/^\d+-[A-Za-z0-9]*$/.test(lines[i]))
                ready[lines[i]] = true;
        readyThumbs = ready;
        // Re-point only rows whose thumb changed; a new array (same length)
        // re-evaluates each row's entry without rebuilding the delegates.
        var changed = false;
        var next = entries.map(e => {
            var t = e.isImage && ready[e.thumbKey] ? thumbDir + e.thumbKey + ".png" : "";
            if (t === e.thumb)
                return e;
            changed = true;
            return Object.assign({}, e, { thumb: t });
        });
        if (changed)
            entries = next;
        finishPass();
    }

    Process {
        id: listProc
        property string out: ""
        property bool exitSeen: false
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: listProc.out = this.text
        }
        onExited: (exitCode) => {
            exitSeen = true;
            root.listExited(exitCode);
        }
        onRunningChanged: if (!running && !exitSeen) root.listExited(-1)
    }

    Process {
        id: thumbProc
        property string out: ""
        property bool exitSeen: false
        stdout: StdioCollector {
            onStreamFinished: thumbProc.out = this.text
        }
        onExited: {
            exitSeen = true;
            root.thumbsExited();
        }
        onRunningChanged: if (!running && !exitSeen) {
            thumbProc.out = "";
            root.thumbsExited();
        }
    }

    Process {
        id: delProc
        property var batch: []
        // On running=false (it follows exited, and is the only signal a failed
        // start gets), deferred: the next batch restarts this same Process.
        onRunningChanged: if (!running) Qt.callLater(root.deletesDone)
    }

    Process {
        id: wipeProc
        command: ["cliphist", "wipe"]
        onExited: root.refresh()
    }
}
