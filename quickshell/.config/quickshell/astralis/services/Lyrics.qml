pragma Singleton

import QtQuick
import Quickshell
import "../services"

/**
 * astralis — time-synced lyrics for the current track, from LRCLIB
 * (lrclib.net, keyless, listed on wotaku.wiki/music). One fetch per track,
 * results kept in memory for the session.
 *
 * LRCLIB is line-synced (its `hasWordSync` was false on every track
 * checked), so word timing is ESTIMATED: each line's singing span is guessed
 * from its length (≈65ms per Latin char, ≈240ms per CJK char, capped by the
 * gap to the next line) and spread across its words by weight. The widget
 * reads `wordFill()` per frame.
 *
 * `lines`: [{ t, end, span, text, gap, words: [{ text, space, a, b }] }]
 *   t/end in seconds; a/b = word start/end as fractions of the span.
 */
Singleton {
    id: root

    /** "idle" | "loading" | "synced" | "plain" | "none" | "instrumental" */
    readonly property string status: entry ? entry.status : (TrackInfo.key.length > 0 ? "loading" : "idle")
    readonly property var lines: entry && entry.lines ? entry.lines : []
    readonly property bool has: status === "synced" && lines.length > 0

    property var cache: ({})
    readonly property var entry: TrackInfo.key.length > 0 && cache[TrackInfo.key] ? cache[TrackInfo.key] : null

    /** Seconds the lyrics lead the reported position (MPRIS lags a little). */
    property real lead: 0.12

    function lineAt(pos) {
        var l = root.lines;
        var lo = 0, hi = l.length - 1, ans = -1;
        while (lo <= hi) {
            var mid = (lo + hi) >> 1;
            if (l[mid].t <= pos) {
                ans = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return ans;
    }

    // ── fetch ─────────────────────────────────────────────────────────────
    Connections {
        target: TrackInfo
        function onKeyChanged() { fetchTimer.restart(); }
    }
    // The singleton is created lazily, often after the key is already set.
    Component.onCompleted: fetchTimer.restart()
    // Watchdog: if the track has no entry yet (metadata arrived piecemeal and
    // the first attempt bailed), try again.
    Timer {
        interval: 4000
        repeat: true
        running: TrackInfo.key.length > 0 && !root.entry
        onTriggered: fetchTimer.restart()
    }
    Timer {
        id: fetchTimer
        interval: 500
        onTriggered: root.fetch(TrackInfo.key, TrackInfo.title, TrackInfo.artist, TrackInfo.album, TrackInfo.duration, 0)
    }

    function store(k, v) {
        var c = Object.assign({}, root.cache);
        c[k] = v;
        root.cache = c;
    }

    function request(url, cb) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 10000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var d = null;
            try { d = JSON.parse(xhr.responseText); } catch (e) {}
            cb(xhr.status, d);
        };
        xhr.open("GET", url);
        xhr.setRequestHeader("Lrclib-Client", "astralis (quickshell rice)");
        xhr.send();
    }

    function fetch(k, title, artist, album, dur, attempt) {
        if (k.length === 0 || artist.length === 0 || (root.cache[k] && attempt === 0))
            return;
        root.store(k, { status: "loading" });
        var q = "track_name=" + encodeURIComponent(title) + "&artist_name=" + encodeURIComponent(artist);
        var exact = "https://lrclib.net/api/get?" + q
            + (album ? "&album_name=" + encodeURIComponent(album) : "")
            + (dur > 0 ? "&duration=" + Math.round(dur) : "");
        request(exact, function(code, d) {
                if (root.transient(code) && attempt < 4) {
                retry.schedule(k, title, artist, album, dur, attempt + 1);
                return;
            }
            if (code === 200 && d && (d.syncedLyrics || d.instrumental)) {
                root.accept(k, d);
                return;
            }
            // No exact hit: search and take the synced result closest in length.
            root.search(k, title, artist, album, dur, attempt, d, "https://lrclib.net/api/search?" + q, true);
        });
    }

    /** 503 (LRCLIB overloaded), timeouts (0), 429, 5xx — retried, never cached as "none". */
    function transient(code) {
        return code === 0 || code === 429 || code >= 500;
    }

    function pickClosest(list, dur) {
        var best = null, bestD = 1e9;
        for (var i = 0; list && list.length && i < list.length; i++) {
            var r = list[i];
            if (!r.syncedLyrics)
                continue;
            var dd = dur > 0 ? Math.abs(r.duration - dur) : 0;
            if (dd < bestD) {
                bestD = dd;
                best = r;
            }
        }
        return best && bestD <= 4 ? best : null;
    }

    function search(k, title, artist, album, dur, attempt, exact, url, first) {
        request(url, function(code, list) {
            if (root.transient(code)) {
                if (attempt < 4)
                    retry.schedule(k, title, artist, album, dur, attempt + 1);
                else
                    root.drop(k);   // stay uncached → the watchdog tries again later
                return;
            }
            var best = root.pickClosest(list, dur);
            if (best) {
                root.accept(k, best);
                return;
            }
            // Field search found nothing synced (title spelt differently —
            // ’ vs ', romaji vs kana): one free-text pass.
            if (first) {
                root.search(k, title, artist, album, dur, attempt, exact,
                            "https://lrclib.net/api/search?q=" + encodeURIComponent(artist + " " + title), false);
                return;
            }
            root.store(k, { status: exact && exact.plainLyrics ? "plain" : "none" });
        });
    }

    function drop(k) {
        var c = Object.assign({}, root.cache);
        delete c[k];
        root.cache = c;
    }

    Timer {
        id: retry
        property var args: []
        interval: 3000
        function schedule(k, t, a, al, d, n) {
            args = [k, t, a, al, d, n];
            interval = 3000 * n;
            restart();
        }
        onTriggered: root.fetch(args[0], args[1], args[2], args[3], args[4], args[5])
    }

    function accept(k, d) {
        if (d.instrumental) {
            root.store(k, { status: "instrumental" });
            return;
        }
        root.store(k, { status: "synced", lines: parse(d.syncedLyrics, d.duration || 0) });
    }

    // ── parse ─────────────────────────────────────────────────────────────
    readonly property var cjk: /[぀-ヿ㐀-鿿가-힯ｦ-ﾟ]/

    function parse(lrc, total) {
        var raw = [];
        var offset = 0;
        var rows = String(lrc).split(/\r?\n/);
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            var off = row.match(/^\[offset:\s*([+-]?\d+)\]/i);
            if (off) {
                offset = parseInt(off[1]) / 1000;
                continue;
            }
            var stamps = [];
            var m, re = /\[(\d+):(\d+(?:\.\d+)?)\]/g, last = 0;
            while ((m = re.exec(row)) !== null) {
                stamps.push(parseInt(m[1]) * 60 + parseFloat(m[2]));
                last = re.lastIndex;
            }
            if (stamps.length === 0)
                continue;
            var text = row.slice(last).trim();
            for (var s = 0; s < stamps.length; s++)
                raw.push({ t: Math.max(0, stamps[s] - offset), text: text });
        }
        raw.sort((a, b) => a.t - b.t);

        var out = [];
        for (var j = 0; j < raw.length; j++) {
            var L = raw[j];
            var end = j + 1 < raw.length ? raw[j + 1].t : (total > L.t ? total : L.t + 6);
            var gap = L.text.length === 0 || /^[♪♫♬\s]+$/.test(L.text);
            // Collapse consecutive gaps.
            if (gap && out.length > 0 && out[out.length - 1].gap) {
                out[out.length - 1].end = end;
                continue;
            }
            out.push(gap ? { t: L.t, end: end, span: end - L.t, text: "", gap: true, words: [] }
                         : timeLine(L.t, end, L.text));
        }
        return out;
    }

    /** Splits a line into words (CJK per character) and estimates when each is sung. */
    function timeLine(t, end, text) {
        var tokens = [];
        var re = /([぀-ヿ㐀-鿿가-힯ｦ-ﾟ][ァ-ヴぁ-ゔーゃゅょっャュョッ]?[、。！？!?,.」』）)]*)|([^\s぀-ヿ㐀-鿿가-힯ｦ-ﾟ]+)(\s*)|(\s+)/g;
        var m;
        while ((m = re.exec(text)) !== null) {
            if (m[1])
                tokens.push({ text: m[1], space: false, w: m[1].replace(/[、。！？!?,.」』）)]/g, "").length * 2.2 });
            else if (m[2])
                tokens.push({ text: m[2], space: (m[3] || "").length > 0, w: m[2].length * 0.65 + 0.6 });
            else if (m[4] && tokens.length > 0)
                tokens[tokens.length - 1].space = true;
        }
        var total = 0;
        for (var i = 0; i < tokens.length; i++)
            total += tokens[i].w;
        var est = total * 0.1 + 0.35;
        var gap = Math.max(0.3, end - t);
        var span = Math.min(gap * 0.94, Math.max(0.6, est));
        var acc = 0;
        for (var k = 0; k < tokens.length; k++) {
            tokens[k].a = acc / total;
            acc += tokens[k].w;
            tokens[k].b = acc / total;
        }
        return { t: t, end: end, span: span, text: text, gap: false, words: tokens };
    }
}
