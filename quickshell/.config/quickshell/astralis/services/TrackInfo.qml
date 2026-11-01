pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../colors"
import "../services"

/**
 * astralis — cover art for the current track, and every alternate cover of
 * the same song that exists (album / deluxe / compilation / single editions,
 * other storefronts). Sources, all keyless (picked from wotaku.wiki/music):
 *
 *   • iTunes Search API — the backend of the "Apple Music Artwork Finder"
 *     tools; artwork URLs are rewritten to `artSize`px. Queried in the us and
 *     jp storefronts (JP releases often only exist in jp).
 *   • Deezer search API — `cover_xl` (1000px). Also matches songs whose
 *     title is localised differently, via artist + identical duration.
 *   • MusicBrainz + Cover Art Archive — every release group (single, album,
 *     regional / limited editions) the recording appears on, minus
 *     various-artist compilations; only groups whose front cover exists
 *     (HEAD-checked) are kept. Needs an identifying User-Agent, so it runs
 *     through curl rather than XHR.
 *   • the player's own art (Spotify 640px, YouTube thumb, …) as the fallback.
 *
 * A candidate only counts as "the same song" when the artist matches AND the
 * title matches (or the duration matches to the second). Remix / live /
 * instrumental / sped-up versions are dropped unless the playing title is one.
 * Covers are de-duplicated by album name across sources.
 *
 * The user's pick per song (`next()` / `prev()` / `pick()`) is remembered
 * in ~/.cache/astralis/artpick.json, so the alternate cover sticks next time.
 * The chosen cover is downloaded once so ColorQuantizer can derive `accent`.
 */
Singleton {
    id: root

    property int artSize: 1200
    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/astralis"

    // ── cleaned query ─────────────────────────────────────────────────────
    readonly property string rawTitle: Players.has && Players.active.trackTitle ? Players.active.trackTitle : ""
    readonly property string rawArtist: Players.artist
    readonly property string album: Players.has && Players.active.trackAlbum ? Players.active.trackAlbum : ""
    readonly property real duration: Players.length

    readonly property var parsed: parse(rawTitle, rawArtist)
    readonly property string title: parsed.title
    readonly property string artist: parsed.artist
    readonly property string key: title.length > 0 ? (title + "|" + artist).toLowerCase() : ""

    /** Strips video-site decoration and splits "Artist - Title" when the artist is a channel. */
    function parse(t, a) {
        var title = String(t || "");
        var artist = String(a || "").replace(/\s*-\s*Topic$/i, "").replace(/VEVO$/i, "").trim();
        title = title.replace(/\s*[|｜]\s*(youtube|spotify|soundcloud|bandcamp).*$/i, "");
        title = title.replace(/\s*[\(\[【「（][^\)\]】」）]*(official|video|audio|lyrics?|m\/?v|visuali[sz]er|hd|4k|歌詞|公式)[^\)\]】」）]*[\)\]】」）]/gi, "");
        title = title.replace(/\s*[\/／]\s*(official|music video|mv).*$/i, "");
        var dash = title.match(/^(.+?)\s+[-–—]\s+(.+)$/);
        if (dash && (artist.length === 0 || loose(dash[1], artist))) {
            artist = dash[1].trim();
            title = dash[2].trim();
        }
        title = title.replace(/\s*[\(\[](feat|ft)\.?[^\)\]]*[\)\]]/i, "").trim();
        return { title: title, artist: artist };
    }

    function norm(s) {
        return String(s || "").toLowerCase().normalize("NFKC")
            .replace(/[\(\[].*?[\)\]]/g, "").replace(/\s+-\s+(single|ep)$/, "")
            .replace(/[^\p{L}\p{N}]+/gu, "");
    }

    function loose(a, b) {
        var x = norm(a), y = norm(b);
        return x.length > 0 && y.length > 0 && (x === y || x.indexOf(y) >= 0 || y.indexOf(x) >= 0);
    }

    function hasCJK(s) {
        return /[぀-ヿ㐀-鿿가-힯]/.test(s);
    }

    readonly property var versionWords: /\b(remix|live|instrumental|acoustic|karaoke|sped|slowed|nightcore|cover|demo|edit|mix)\b|リミックス|インスト/i

    /** Same song, same version? */
    function sameSong(cTitle, cArtist, cDur) {
        if (!loose(cArtist, root.artist))
            return false;
        if (root.versionWords.test(cTitle) && !root.versionWords.test(root.rawTitle))
            return false;
        if (loose(cTitle, root.title))
            return true;
        return root.duration > 0 && cDur > 0 && Math.abs(cDur - root.duration) < 1.5;
    }

    // ── candidates ────────────────────────────────────────────────────────
    /** key → { pending: n, list: [{ url, album, source, year, genre }] } */
    property var found: ({})
    readonly property var entry: key.length > 0 && found[key] ? found[key] : null
    readonly property bool searching: entry !== null && entry.pending > 0

    /** Covers whose image failed to load; dropped from the list. */
    property var bad: ({})
    function markBad(u) {
        u = String(u);
        if (u.length === 0 || root.bad[u] || u === Players.artUrl)
            return;
        var b = Object.assign({}, root.bad);
        b[u] = true;
        root.bad = b;
    }

    /** Every cover for this song: hi-res editions first (the playing album leading), player art last. */
    readonly property var covers: {
        var out = [];
        var seen = {};
        // Hold the player's own art until every source has answered, so the
        // cover changes once (to the hi-res pick) instead of flickering.
        var lst = entry && entry.pending <= 0 ? entry.list.filter(c => !root.bad[c.url]) : [];
        var own = norm(root.album);
        var sorted = lst.slice().sort((a, b) => (norm(b.album) === own ? 1 : 0) - (norm(a.album) === own ? 1 : 0));
        for (var i = 0; i < sorted.length; i++) {
            var c = sorted[i];
            var k = norm(c.album) || c.url;
            if (seen[k])
                continue;
            seen[k] = true;
            out.push(c);
        }
        var pa = Players.artUrl;
        if (pa.length > 0 && !(own.length > 0 && seen[own]))
            out.push({ url: pa, album: root.album, kind: "",
                       source: Players.serviceLabel || "Player", year: "", genre: "" });
        return out;
    }
    readonly property int count: covers.length

    /** Remembered pick: key → cover url. */
    property var picks: ({})
    readonly property int index: {
        var want = key.length > 0 ? picks[key] : undefined;
        for (var i = 0; want && i < covers.length; i++)
            if (covers[i].url === want)
                return i;
        return 0;
    }
    readonly property var cover: count > 0 ? covers[index] : null

    readonly property string art: cover ? cover.url : ""
    readonly property string coverSource: cover ? cover.source : ""
    readonly property string coverAlbum: cover && cover.album ? cover.album : album
    readonly property string coverYear: cover && cover.year ? cover.year : ""

    function pick(i) {
        if (count === 0 || key.length === 0)
            return;
        var p = Object.assign({}, root.picks);
        p[key] = covers[((i % count) + count) % count].url;
        root.picks = p;
        pickFile.setText(JSON.stringify(p));
    }
    function next() { pick(index + 1); }
    function prev() { pick(index - 1); }

    FileView {
        id: pickFile
        path: root.cacheDir + "/artpick.json"
        printErrors: false
        onLoaded: {
            try { root.picks = JSON.parse(text()) || {}; } catch (e) {}
        }
    }

    // ── lookups ───────────────────────────────────────────────────────────
    onKeyChanged: lookupTimer.restart()
    Component.onCompleted: lookupTimer.restart()
    // Debounced: browsers emit the title before the artist on a track change.
    Timer {
        id: lookupTimer
        interval: 400
        onTriggered: root.lookup()
    }

    function add(k, items, done) {
        var f = Object.assign({}, root.found);
        var e = f[k] || { pending: 0, list: [] };
        f[k] = { pending: e.pending - (done ? 1 : 0), list: e.list.concat(items) };
        root.found = f;
    }

    function get(url, cb) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 8000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var data = null;
            if (xhr.status === 200)
                try { data = JSON.parse(xhr.responseText); } catch (e) {}
            cb(data);
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function lookup() {
        var k = root.key;
        if (k.length === 0 || root.found[k] || root.artist.length === 0)
            return;
        var f = Object.assign({}, root.found);
        f[k] = { pending: 4, list: [] };
        root.found = f;
        var term = encodeURIComponent(root.artist + " " + root.title);
        var stores = hasCJK(root.title + root.artist) ? ["jp", "us"] : ["us", "jp"];

        stores.forEach(function(cc) {
            get("https://itunes.apple.com/search?media=music&entity=musicTrack&limit=25&country=" + cc + "&term=" + term,
                function(d) {
                    var items = [];
                    var rs = d && d.results ? d.results : [];
                    for (var i = 0; i < rs.length; i++) {
                        var r = rs[i];
                        if (!r.artworkUrl100 || !sameSong(r.trackName, r.artistName, (r.trackTimeMillis || 0) / 1000))
                            continue;
                        items.push({
                            url: r.artworkUrl100.replace(/\/\d+x\d+bb\.(jpg|png)$/, "/" + root.artSize + "x" + root.artSize + "bb.jpg"),
                            album: String(r.collectionName || "").replace(/\s+-\s+(Single|EP)$/, ""),
                            kind: /-\s+Single$/.test(r.collectionName || "") ? "Single" : (/-\s+EP$/.test(r.collectionName || "") ? "EP" : ""),
                            source: "Apple Music",
                            year: r.releaseDate ? String(r.releaseDate).slice(0, 4) : "",
                            genre: r.primaryGenreName || ""
                        });
                    }
                    root.add(k, items, true);
                });
        });

        get("https://api.deezer.com/search?limit=25&q=" + term, function(d) {
            var items = [];
            var rs = d && d.data ? d.data : [];
            for (var i = 0; i < rs.length; i++) {
                var r = rs[i];
                if (!r.album || !r.album.cover_xl || !r.artist || !sameSong(r.title, r.artist.name, r.duration || 0))
                    continue;
                items.push({ url: r.album.cover_xl, album: r.album.title || "", kind: r.album.record_type || "",
                             source: "Deezer", year: "", genre: "" });
            }
            root.add(k, items, true);
        });

        musicbrainz(k);
    }

    // MusicBrainz → release groups → Cover Art Archive (HEAD-checked).
    readonly property string userAgent: "astralis/1.0 ( https://github.com/immortal-forest/dotfiles )"

    function lucene(s) {
        return String(s).replace(/["\\]/g, " ");
    }

    function run(args, cb) {
        var p = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root, "TrackInfo.run");
        p.command = args;
        p.exited.connect(function(code) {
            var out = p.stdout.text;
            p.destroy();
            cb(code === 0 ? out : "");
        });
        p.running = true;
    }

    function musicbrainz(k) {
        var q = 'recording:"' + lucene(root.title) + '" AND artist:"' + lucene(root.artist) + '"';
        var url = "https://musicbrainz.org/ws/2/recording?fmt=json&limit=25&query=" + encodeURIComponent(q);
        run(["curl", "-sf", "--max-time", "10", "-A", root.userAgent, url], function(txt) {
            var groups = [];
            var seen = {};
            try {
                var recs = JSON.parse(txt).recordings || [];
                for (var i = 0; i < recs.length; i++) {
                    var r = recs[i];
                    var ra = (r["artist-credit"] || []).map(a => a.name).join(" ");
                    if (!sameSong(r.title, ra, (r.length || 0) / 1000))
                        continue;
                    var rels = r.releases || [];
                    for (var j = 0; j < rels.length; j++) {
                        var rel = rels[j];
                        var g = rel["release-group"] || {};
                        var va = (rel["artist-credit"] || []).some(a => /various artists/i.test(a.name));
                        var comp = (g["secondary-types"] || []).indexOf("Compilation") >= 0;
                        if (!g.id || seen[g.id] || va || comp)
                            continue;
                        seen[g.id] = true;
                        groups.push({ id: g.id, album: g.title || rel.title || "", kind: g["primary-type"] || "",
                                      year: rel.date ? String(rel.date).slice(0, 4) : "" });
                    }
                }
            } catch (e) {}
            groups = groups.slice(0, 12);
            if (groups.length === 0) {
                root.add(k, [], true);
                return;
            }
            // Keep only groups that really have a front cover.
            var script = 'ua="$0"; for id in "$@"; do curl -sfI -o /dev/null --max-time 6 -A "$ua" "https://coverartarchive.org/release-group/$id/front-250" && echo "$id"; done; true';
            run(["sh", "-c", script, root.userAgent].concat(groups.map(g => g.id)), function(ok) {
                var have = {};
                ok.split("\n").forEach(l => { if (l.trim()) have[l.trim()] = true; });
                var items = groups.filter(g => have[g.id]).map(g => ({
                    url: "https://coverartarchive.org/release-group/" + g.id + "/front-1200",
                    album: g.album, kind: g.kind, source: "MusicBrainz", year: g.year, genre: ""
                }));
                root.add(k, items, true);
            });
        });
    }

    // ── accent from the chosen cover ──────────────────────────────────────
    /** ColorQuantizer only reads local files, so a remote pick is fetched once. */
    property string paletteFile: ""
    property var paletteMap: ({})
    onArtChanged: fetchPalette()
    function fetchPalette() {
        var u = root.art;
        if (u.indexOf("file:") === 0) {
            root.paletteFile = u;
            return;
        }
        if (u.length === 0)
            return;
        if (root.paletteMap[u]) {
            root.paletteFile = root.paletteMap[u];
            return;
        }
        var out = root.cacheDir + "/artcache/pick-" + Qt.md5(u) + ".jpg";
        var p = Qt.createQmlObject('import Quickshell.Io; Process {}', root, "TrackInfo.fetch");
        p.command = ["sh", "-c", 'mkdir -p "${1%/*}" && { [ -s "$1" ] || { curl -fsL --max-time 10 -o "$1.part" "$0" && mv "$1.part" "$1"; }; }', u, out];
        p.exited.connect(function(code) {
            if (code === 0) {
                var m = Object.assign({}, root.paletteMap);
                m[u] = "file://" + out;
                root.paletteMap = m;
                if (root.art === u)
                    root.paletteFile = "file://" + out;
            }
            p.destroy();
        });
        p.running = true;
    }

    ColorQuantizer {
        id: quant
        source: root.paletteFile
        depth: 3
        rescaleSize: 64
    }

    /** Most colourful swatch on the cover, or null when the cover is greyscale. */
    readonly property var swatch: {
        var cs = quant.colors;
        var best = null, bestScore = 0.12;
        for (var i = 0; i < cs.length; i++) {
            var c = cs[i];
            var score = c.hslSaturation * (1 - Math.abs(c.hslLightness - 0.5) * 1.4);
            if (score > bestScore) {
                bestScore = score;
                best = c;
            }
        }
        return best;
    }

    /** Text-safe light accent (lit lyrics, highlights). Falls back to the wallpaper primary. */
    readonly property color accent: swatch
        ? Qt.hsla(swatch.hslHue, Math.max(0.5, Math.min(0.85, swatch.hslSaturation)), 0.78, 1)
        : Colors.primary
    /** Deep accent for glows and fills. */
    readonly property color accentDeep: swatch
        ? Qt.hsla(swatch.hslHue, Math.max(0.55, swatch.hslSaturation), 0.5, 1)
        : Colors.primary_container

    /** A second colourful swatch with a different hue (gradient partner for `accent`). */
    readonly property var swatch2: {
        var cs = quant.colors, b = root.swatch;
        if (!b)
            return null;
        var best = null, bestScore = 0.08;
        for (var i = 0; i < cs.length; i++) {
            var c = cs[i];
            var dh = Math.abs(c.hslHue - b.hslHue);
            dh = Math.min(dh, 1 - dh);
            if (dh < 0.06)
                continue;
            var score = c.hslSaturation * (1 - Math.abs(c.hslLightness - 0.5) * 1.4);
            if (score > bestScore) {
                bestScore = score;
                best = c;
            }
        }
        return best;
    }
    /** Light partner of `accent` — a second cover hue, or `accent` nudged round the wheel. */
    readonly property color accent2: swatch2
        ? Qt.hsla(swatch2.hslHue, Math.max(0.5, Math.min(0.85, swatch2.hslSaturation)), 0.8, 1)
        : swatch ? Qt.hsla((swatch.hslHue + 0.07) % 1, Math.max(0.45, Math.min(0.8, swatch.hslSaturation)), 0.84, 1)
                 : Colors.tertiary
    /** Unsung-text ink: near-white faintly tinted with the cover. */
    readonly property color ink: swatch
        ? Qt.hsla(swatch.hslHue, 0.14, 0.92, 1)
        : Colors.on_surface
}
