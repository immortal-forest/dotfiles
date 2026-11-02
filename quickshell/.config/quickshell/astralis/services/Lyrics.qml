pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
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

    /** key → { run, pending, cands: { <source>: { lines, sourceRoman, timed, cjk } | null },
     *  instrumental, plain, transient }. Every source is asked at once; a
     *  missing cand = still answering, null = no lyrics there. */
    property var cache: ({})
    /** "key|source" → { romanStatus, roman, rlines } */
    property var romans: ({})
    readonly property var sources: ["netease", "lrclib", "kugou"]
    readonly property var sourceNames: ({ netease: "NetEase", lrclib: "LRCLIB", kugou: "Kugou" })
    /** Widgets.lyrics.provider: "auto" (best available) or one source, which
     *  falls back to the best available when it has nothing for the track. */
    readonly property string prefer: Widgets.lyrics.provider || "auto"
    readonly property var raw: TrackInfo.key.length > 0 && cache[TrackInfo.key] ? cache[TrackInfo.key] : null
    /** Sources that have synced lyrics for this track, best first. */
    readonly property var available: raw ? ranked(raw) : []
    /** Sources still answering for this track. */
    readonly property bool searching: raw !== null && raw.pending > 0
    /** Where the shown lyrics come from: "" | "netease" | "lrclib" | "kugou". */
    readonly property string source: entry && entry.source ? entry.source : ""
    readonly property bool wordTimed: entry && entry.timed ? true : false
    readonly property var entry: {
        var c = root.raw;
        if (!c)
            return null;
        var src = root.choose(c);
        if (src) {
            var cand = c.cands[src];
            return Object.assign({ status: "synced", source: src, lines: cand.lines, timed: cand.timed,
                                   sourceRoman: cand.sourceRoman },
                                 root.romans[TrackInfo.key + "|" + src] || {});
        }
        if (c.pending > 0)
            return { status: "loading" };
        return { status: c.instrumental ? "instrumental" : c.plain ? "plain" : "none" };
    }

    /** Word-timed (NetEase yrc) beats everything — held notes hold. Then
     *  line-synced: NetEase for CJK lyrics (it ships romaji too), LRCLIB for
     *  the rest, Kugou last. */
    function score(src, cand) {
        var base = src === "kugou" ? 1 : src === "netease" ? (cand.cjk ? 3 : 2) : (cand.cjk ? 2 : 3);
        return (cand.timed ? 10 : 0) + base;
    }
    function ranked(c) {
        return root.sources.filter(s => !!c.cands[s])
            .sort((a, b) => root.score(b, c.cands[b]) - root.score(a, c.cands[a]));
    }
    function choose(c) {
        if (root.prefer !== "auto" && c.cands[root.prefer])
            return root.prefer;
        var r = root.ranked(c);
        return r.length > 0 ? r[0] : "";
    }

    /** Seconds the lyrics lead the reported position: MPRIS lags a little
     *  (measured ~0.1 s vs the sink's audio), but Bluetooth output plays
     *  ~0.25 s after the sink (aptX/AAC/SBC; PipeWire reports 0 for it), so
     *  on a bluez sink the lyrics wait instead. The editor's Sync offset
     *  fine-tunes on top. */
    readonly property bool bluetooth: {
        var s = Pipewire.defaultAudioSink;
        return !!s && String(s.name).indexOf("bluez") === 0;
    }
    readonly property real lead: bluetooth ? -0.13 : 0.12

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
    // Disk cache first (instant, even while skipping); the network only on a
    // miss, after a short debounce — 1.5s while skipping (a change within 3s
    // of the last), 250ms otherwise.
    Connections {
        target: TrackInfo
        function onKeyChanged() {
            var now = Date.now();
            fetchTimer.interval = now - root.lastKeyChange < 3000 ? 1500 : 250;
            root.lastKeyChange = now;
            root.lookup();
        }
    }
    property real lastKeyChange: 0
    // The singleton is created lazily, often after the key is already set.
    Component.onCompleted: lookup()
    // Watchdog: no entry yet (metadata arrived piecemeal and the first
    // attempt bailed, or a network failure was forgotten) → try again.
    Timer {
        interval: 4000
        repeat: true
        running: TrackInfo.key.length > 0 && !root.raw
        onTriggered: root.lookup()
    }
    Timer {
        id: fetchTimer
        interval: 250
        onTriggered: root.fetch(TrackInfo.key, TrackInfo.title, TrackInfo.artist, TrackInfo.album, TrackInfo.duration)
    }

    function lookup() {
        var k = TrackInfo.key;
        fetchTimer.stop();
        if (k.length === 0 || root.cache[k])
            return;
        DiskCache.read("lyrics", k, function (d) {
            if (root.cache[k])
                return;
            if (root.fresh(d))
                root.store(k, { run: {}, pending: 0, cands: d.cands || {}, instrumental: !!d.instrumental, plain: !!d.plain });
            else if (k === TrackInfo.key)
                fetchTimer.restart();
        });
    }
    /** A saved miss is asked again after a week (lyrics get added). */
    function fresh(d) {
        if (!d || d.v !== 1)
            return false;
        return root.sources.some(s => d.cands && d.cands[s]) || d.instrumental
            || Date.now() - d.saved < 7 * 86400000;
    }

    function store(k, v) {
        var c = Object.assign({}, root.cache);
        c[k] = v;
        root.cache = c;
    }
    function setRoman(rk, o) {
        var r = Object.assign({}, root.romans);
        r[rk] = Object.assign({}, r[rk], o);
        root.romans = r;
    }
    function later(ms, fn) {
        var t = Qt.createQmlObject('import QtQuick; Timer {}', root, "Lyrics.later");
        t.interval = ms;
        t.triggered.connect(function () { t.destroy(); fn(); });
        t.start();
    }

    // ── romanization (on demand, scripts/romanize.sh) ─────────────────────
    /** Per-line romanized text for the current track ([] until ready). */
    readonly property var roman: entry && entry.roman ? entry.roman : []
    /** `lines` re-timed on their romanized text (the widget's "replace" mode). */
    readonly property var romanLines: entry && entry.rlines ? entry.rlines : []
    /** "" | "busy" | "ready" | "none" (nothing to romanize) | "nokakasi" | "error" */
    readonly property string romanStatus: entry && entry.romanStatus ? entry.romanStatus : ""
    readonly property bool wantRoman: Widgets.lyrics.roman !== "off"
    readonly property string romanScript: String(Qt.resolvedUrl("../scripts/romanize.sh")).replace(/^file:\/\//, "")
    // Toggling the option retries a failed run (e.g. kakasi installed since).
    onWantRomanChanged: romanize(true)
    // Deferred: writing `romans` from inside entry's change notification
    // is a binding loop on `entry` (QML drops the re-evaluation).
    onEntryChanged: Qt.callLater(romanize)

    function romanize(retry) {
        var e = root.entry;
        if (!root.wantRoman || !e || e.status !== "synced")
            return;
        if (e.romanStatus && !(retry === true && (e.romanStatus === "nokakasi" || e.romanStatus === "error")))
            return;
        var rk = TrackInfo.key + "|" + e.source;
        var texts = e.lines.map(l => l.text);
        if (!texts.some(t => root.cjk.test(t))) {
            root.setRoman(rk, { romanStatus: "none" });
            return;
        }
        root.setRoman(rk, { romanStatus: "busy" });
        var p = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root, "Lyrics.roman");
        p.command = [root.romanScript, texts.join("\n")];
        p.exited.connect(function (code) {
            var out = String(p.stdout.text).replace(/\n$/, "").split("\n");
            p.destroy();
            // No kakasi → fall back to romaji the lyrics source shipped, if any.
            if (code === 3 && e.sourceRoman && e.sourceRoman.some(x => x.length > 0))
                out = e.sourceRoman;
            else if (code === 3)
                return root.setRoman(rk, { romanStatus: "nokakasi" });
            else if (code !== 0)
                return root.setRoman(rk, { romanStatus: "error" });
            if (out.length !== texts.length)
                return root.setRoman(rk, { romanStatus: "error" });
            var clean = out.map(x => x.replace(/\s+/g, " ").trim());
            var rl = e.lines.map(function (l, i) {
                if (l.gap || clean[i].length === 0)
                    return l;
                var n = root.timeLine(l.t, l.end, clean[i]);
                n.span = l.span;    // keep the original line's sung span
                return n;
            });
            root.setRoman(rk, { romanStatus: "ready", roman: clean, rlines: rl });
        });
        p.running = true;
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

    /** Asks NetEase, Kugou and LRCLIB at once; each answer lands in
     *  cands[source] as it comes, so the first usable one shows right away
     *  and a better one replaces it. Saved to disk once all have answered. */
    function fetch(k, title, artist, album, dur) {
        if (k.length === 0 || artist.length === 0 || root.cache[k])
            return;
        var run = {};
        root.store(k, { run: run, pending: root.sources.length, cands: {}, instrumental: false, plain: false, transient: false });
        var done = function (src, cand, flags) {
            var cur = root.cache[k];
            if (!cur || cur.run !== run)
                return;
            var c = Object.assign({}, cur);
            c.cands = Object.assign({}, c.cands);
            c.cands[src] = cand;
            for (var f in flags || {})
                c[f] = c[f] || flags[f];
            c.pending--;
            root.store(k, c);
            if (c.pending === 0)
                root.finish(k, c);
        };
        // Spotify reports localized titles ("Dawn and Fireflies" for Ado's
        // 夜明けと蛍) that NetEase/Kugou don't know: a miss retries under the
        // original title from iTunes Japan (looked up once, shared).
        var alt = null, altWait = [];
        var withAlt = function (cb) {
            if (alt !== null)
                return cb(alt);
            altWait.push(cb);
            if (altWait.length === 1)
                root.altTitle(title, artist, dur, function (a) {
                    alt = a || "";
                    altWait.forEach(f => f(alt));
                });
        };
        var keyed = function (src, fn) {
            var tryTitle = function (t, onMiss) {
                fn(t, artist, dur, function (lrc, roma, yrc) {
                    var c = root.candidate(lrc, roma, yrc, dur);
                    if (c)
                        done(src, c);
                    else
                        onMiss();
                }, onMiss);
            };
            tryTitle(title, function () {
                withAlt(a => a ? tryTitle(a, () => done(src, null)) : done(src, null));
            });
        };
        keyed("netease", root.netease);
        keyed("kugou", root.kugou);
        root.lrclib(k, title, artist, album, dur, 0, run, done);
    }

    function finish(k, c) {
        if (!root.sources.some(s => c.cands[s]) && c.transient) {
            // Network trouble, not a real miss: forget it after a while so
            // the watchdog asks again.
            root.later(20000, function () {
                if (root.cache[k] && root.cache[k].run === c.run) {
                    var cc = Object.assign({}, root.cache);
                    delete cc[k];
                    root.cache = cc;
                }
            });
            return;
        }
        DiskCache.write("lyrics", k, { v: 1, saved: Date.now(), cands: c.cands, instrumental: c.instrumental, plain: c.plain });
    }

    /** Parsed LRC (+ romaji, + word timing) → a cand, or null when it is too
     *  thin to use (< 3 sung lines). */
    function candidate(lrc, roma, yrc, dur) {
        var lines = lrc ? root.parse(lrc, dur, true) : [];
        var sung = lines.filter(l => !l.gap).length;
        if (sung < 3)
            return null;
        if (yrc)
            lines = root.applyWordTiming(lines, root.parseYrc(yrc));
        var c = { lines: lines, timed: lines.filter(l => l.timed).length >= sung / 2,
                  cjk: lines.some(l => root.cjk.test(l.text)) };
        if (roma)
            c.sourceRoman = root.alignRoman(lines, roma);
        return c;
    }
    function lrclibCand(d, dur) {
        var lines = root.parse(d.syncedLyrics, d.duration || 0);
        if (lines.filter(l => !l.gap).length === 0)
            return null;
        return { lines: lines, timed: false, cjk: lines.some(l => root.cjk.test(l.text)) };
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

    /** Exact lookup → field search → free-text search (titles spelt
     *  differently: ’ vs ', romaji vs kana). LRCLIB 503s for long stretches:
     *  retried twice (3s, 6s) while the track plays, then given up. */
    function lrclib(k, title, artist, album, dur, attempt, run, done) {
        var q = "track_name=" + encodeURIComponent(title) + "&artist_name=" + encodeURIComponent(artist);
        var exact = "https://lrclib.net/api/get?" + q
            + (album ? "&album_name=" + encodeURIComponent(album) : "")
            + (dur > 0 ? "&duration=" + Math.round(dur) : "");
        var down = function () {
            if (attempt < 2 && k === TrackInfo.key)
                root.later(3000 * (attempt + 1), () => root.lrclib(k, title, artist, album, dur, attempt + 1, run, done));
            else
                done("lrclib", null, { transient: true });
        };
        root.request(exact, function (code, d) {
            if (root.transient(code))
                return down();
            if (code === 200 && d && d.instrumental)
                return done("lrclib", null, { instrumental: true });
            var hit = code === 200 && d && d.syncedLyrics ? root.lrclibCand(d, dur) : null;
            if (hit)
                return done("lrclib", hit);
            var plain = !!(d && d.plainLyrics);
            root.request("https://lrclib.net/api/search?" + q, function (c2, list) {
                if (root.transient(c2))
                    return down();
                var best = root.pickClosest(list, dur);
                if (best)
                    return done("lrclib", root.lrclibCand(best, dur));
                root.request("https://lrclib.net/api/search?q=" + encodeURIComponent(artist + " " + title), function (c3, l3) {
                    var b3 = root.transient(c3) ? null : root.pickClosest(l3, dur);
                    done("lrclib", b3 ? root.lrclibCand(b3, dur) : null, { plain: plain, transient: root.transient(c3) });
                });
            });
        });
    }
    function norm(s) {
        return String(s || "").toLowerCase()
            .replace(/[(\[（【].*?[)\]）】]/g, "")
            .replace(/\s*[-–—]\s*(feat|ft|with)\.?\s.*$/, "")
            .replace(/[\s'’"“”!！?？.,，、。・~〜:：\-–—_/\\]+/g, "");
    }
    function titleMatch(a, b) {
        var x = root.norm(a), y = root.norm(b);
        return x.length > 0 && y.length > 0 && (x === y || x.indexOf(y) >= 0 || y.indexOf(x) >= 0);
    }

    function getJson(url, cb) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 10000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var d = null;
            try { d = JSON.parse(xhr.responseText); } catch (e) {}
            cb(xhr.status, d);
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function netease(title, artist, dur, got, next) {
        var q = encodeURIComponent(artist + " " + title);
        root.getJson("https://music.163.com/api/search/get?s=" + q + "&type=1&limit=12", function (code, d) {
            var songs = d && d.result && d.result.songs ? d.result.songs : [];
            var best = null, bestScore = -1;
            for (var j = 0; j < songs.length; j++) {
                var s = songs[j];
                if (!root.titleMatch(s.name, title))
                    continue;
                var dd = dur > 0 && s.duration ? Math.abs(s.duration / 1000 - dur) : 0;
                if (dd > 5)
                    continue;
                var arts = (s.artists || []).map(a => a.name).join(" ");
                var score = (root.titleMatch(arts, artist) ? 2 : 0) + (root.norm(s.name) === root.norm(title) ? 1 : 0) - dd / 10;
                if (score > bestScore) {
                    bestScore = score;
                    best = s;
                }
            }
            if (!best)
                return next();
            // v1 endpoint: also returns `yrc`, NetEase's word-timed lyrics.
            root.getJson("https://music.163.com/api/song/lyric/v1?id=" + best.id + "&lv=-1&yv=-1&tv=-1&rv=-1", function (c2, l) {
                var lrc = l && l.lrc && l.lrc.lyric ? l.lrc.lyric : "";
                var roma = l && l.romalrc && l.romalrc.lyric ? l.romalrc.lyric : "";
                var yrc = l && l.yrc && l.yrc.lyric ? l.yrc.lyric : "";
                if (!/\[\d+:\d+/.test(lrc))
                    return next();
                got(lrc, roma, yrc);
            });
        });
    }

    function kugou(title, artist, dur, got, next) {
        var q = encodeURIComponent(artist + " " + title);
        root.getJson("https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=" + q
                     + (dur > 0 ? "&duration=" + Math.round(dur * 1000) : ""), function (code, d) {
            var cands = d && d.candidates ? d.candidates : [];
            var best = null;
            for (var j = 0; j < cands.length; j++) {
                var c = cands[j];
                var dd = dur > 0 && c.duration ? Math.abs(c.duration / 1000 - dur) : 0;
                if (dd <= 5 && root.titleMatch(c.song, title)) {
                    best = c;
                    break;
                }
            }
            if (!best)
                return next();
            root.getJson("https://lyrics.kugou.com/download?ver=1&client=pc&fmt=lrc&charset=utf8&id=" + best.id
                         + "&accesskey=" + best.accesskey, function (c2, l) {
                // Qt.atob already decodes the bytes as UTF-8 (verified: "5pel"
                // → 日); decoding again turned every kana/kanji into mojibake.
                var lrc = l && l.content ? String(Qt.atob(l.content)).replace(/^﻿/, "") : "";
                if (!/\[\d+:\d+/.test(lrc))
                    return next();
                got(lrc, "");
            });
        });
    }

    /** Source-provided romaji (an LRC) → one string per line, matched by timestamp. */
    function alignRoman(lines, roma) {
        var rl = root.parse(roma, 0, true);
        return lines.map(function (l) {
            if (l.gap)
                return "";
            for (var j = 0; j < rl.length; j++)
                if (!rl[j].gap && Math.abs(rl[j].t - l.t) < 0.08)
                    return rl[j].text;
            return "";
        });
    }

    /**
     * NetEase yrc → [{ t, span, segs: [{ t, d, text }] }] (seconds). A line is
     * `[start,dur]` followed by `(start,dur,0)text` per sung word/character;
     * the JSON credit rows (`{"t":…}`) are skipped.
     */
    function parseYrc(yrc) {
        var out = [];
        var rows = String(yrc).split(/\r?\n/);
        for (var i = 0; i < rows.length; i++) {
            var h = rows[i].match(/^\[(\d+),(\d+)\]/);
            if (!h)
                continue;
            var segs = [], m, re = /\((\d+),(\d+),\d+\)([^(]*)/g;
            while ((m = re.exec(rows[i])) !== null)
                segs.push({ t: parseInt(m[1]) / 1000, d: parseInt(m[2]) / 1000, text: m[3] });
            if (segs.length > 0)
                out.push({ t: parseInt(h[1]) / 1000, span: parseInt(h[2]) / 1000, segs: segs });
        }
        return out;
    }

    /**
     * Replace the estimated per-word timing with the real one wherever a yrc
     * line starts at (about) the same time as an LRC line. Held notes then
     * hold the highlight instead of it running on at speaking pace.
     */
    function applyWordTiming(lines, ylines) {
        if (ylines.length === 0)
            return lines;
        return lines.map(function (l) {
            if (l.gap)
                return l;
            var y = null, best = 0.6;
            for (var j = 0; j < ylines.length; j++) {
                var dd = Math.abs(ylines[j].t - l.t);
                if (dd < best) {
                    best = dd;
                    y = ylines[j];
                }
            }
            if (!y)
                return l;
            var span = Math.max(0.1, Math.min(y.span, l.end - y.t));
            var words = [];
            for (var k = 0; k < y.segs.length; k++) {
                var sg = y.segs[k];
                var txt = sg.text.replace(/\s+$/, "");
                if (txt.length === 0) {
                    if (words.length > 0)
                        words[words.length - 1].space = true;
                    continue;
                }
                words.push({
                    text: txt,
                    space: txt.length < sg.text.length,
                    w: 1,
                    a: Math.max(0, Math.min(1, (sg.t - y.t) / span)),
                    b: Math.max(0, Math.min(1, (sg.t + sg.d - y.t) / span))
                });
            }
            if (words.length === 0)
                return l;
            return { t: y.t, end: l.end, span: span, text: y.segs.map(s => s.text).join("").trim(),
                     gap: false, words: words, timed: true };
        });
    }

    /** The track's original-language title from iTunes Japan (same artist,
     *  length within 3s), or "" when it has none / it is the same title. */
    function altTitle(title, artist, dur, cb) {
        if (root.cjk.test(title))
            return cb("");
        root.getJson("https://itunes.apple.com/search?country=jp&entity=song&limit=10&term="
                     + encodeURIComponent(artist + " " + title), function (code, d) {
            var rs = d && d.results ? d.results : [];
            for (var i = 0; i < rs.length; i++) {
                var r = rs[i], t = String(r.trackName || "");
                if (!root.cjk.test(t) || !root.titleMatch(r.artistName, artist))
                    continue;
                if (dur > 0 && !(r.trackTimeMillis && Math.abs(r.trackTimeMillis / 1000 - dur) <= 3))
                    continue;
                return cb(t);
            }
            cb("");
        });
    }

    // ── parse ─────────────────────────────────────────────────────────────
    readonly property var cjk: /[぀-ヿ㐀-鿿가-힯ｦ-ﾟ]/

    /** stripCredits: drop NetEase/Kugou preamble lines ("作词 : …", "Artist - Title"). */
    function parse(lrc, total, stripCredits) {
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
            // [mm:ss.xx] — and NetEase's [mm:ss:xx] (colon before the
            // fraction), which otherwise parsed to zero lines and threw the
            // track onto LRCLIB's slow retry chain.
            var m, re = /\[(\d+):(\d+)(?:[.:](\d+))?\]/g, last = 0;
            while ((m = re.exec(row)) !== null) {
                stamps.push(parseInt(m[1]) * 60 + parseInt(m[2]) + (m[3] ? parseFloat("0." + m[3]) : 0));
                last = re.lastIndex;
            }
            if (stamps.length === 0)
                continue;
            var text = row.slice(last).trim();
            if (stripCredits && stamps[0] < 45 && (/^[^\s:：]{1,14}\s*[:：]\s*\S/.test(text)
                    || (raw.filter(x => x.text.length > 0).length === 0 && stamps[0] < 15 && /\s-\s/.test(text))))
                continue;
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

    /** Sung length of a CJK token in morae: kana ≈ 1 (small kana / ー add
     *  ~0.5), kanji ≈ 1.7 (most readings are 1–3 morae), hangul ≈ 1. */
    function moraWeight(s) {
        var w = 0;
        for (var i = 0; i < s.length; i++) {
            var c = s[i];
            if (/[ゃゅょャュョぁぃぅぇぉァィゥェォ]/.test(c)) w += 0.25;
            else if (/[っッー]/.test(c)) w += 0.6;
            else if (/[぀-ヿｦ-ﾟ]/.test(c)) w += 1;
            else if (/[㐀-鿿]/.test(c)) w += 1.7;
            else if (/[가-힯]/.test(c)) w += 1;
        }
        return Math.max(0.3, w);
    }
    /** Syllables in a Latin word ≈ vowel groups (silent trailing e dropped). */
    function syllables(word) {
        var w = word.toLowerCase().replace(/[^a-zà-ÿ']/g, "");
        if (w.length === 0)
            return 0.3;
        var n = (w.replace(/e$/, "").match(/[aeiouyà-ÿ]+/g) || []).length;
        return Math.max(1, n);
    }

    /** Splits a line into words (CJK per character) and estimates when each is sung. */
    function timeLine(t, end, text) {
        var tokens = [];
        var re = /([぀-ヿ㐀-鿿가-힯ｦ-ﾟ][ァ-ヴぁ-ゔーゃゅょっャュョッ]?[、。！？!?,.」』）)]*)|([^\s぀-ヿ㐀-鿿가-힯ｦ-ﾟ]+)(\s*)|(\s+)/g;
        var m;
        while ((m = re.exec(text)) !== null) {
            if (m[1])
                tokens.push({ text: m[1], space: false, w: root.moraWeight(m[1]) });
            else if (m[2])
                tokens.push({ text: m[2], space: (m[3] || "").length > 0, w: root.syllables(m[2]) });
            else if (m[4] && tokens.length > 0)
                tokens[tokens.length - 1].space = true;
        }
        var total = 0;
        for (var i = 0; i < tokens.length; i++)
            total += tokens[i].w;
        total = Math.max(total, 0.0001);
        // How long the line is sung. Singers carry a line across most of the
        // time until the next one (minus a breath), so the gap is the best
        // guide; only when the gap is far longer than the line could take
        // (a pause / instrumental follows) fall back to a syllable estimate
        // (~0.24s per syllable / mora).
        var est = total * 0.24 + 0.3;
        var gap = Math.max(0.3, end - t);
        var breath = Math.min(0.45, gap * 0.08);
        var span = gap - breath <= est * 1.9 ? gap - breath : Math.max(0.6, est * 1.35);
        var acc = 0;
        for (var k = 0; k < tokens.length; k++) {
            tokens[k].a = acc / total;
            acc += tokens[k].w;
            tokens[k].b = acc / total;
        }
        return { t: t, end: end, span: span, text: text, gap: false, words: tokens };
    }
}
