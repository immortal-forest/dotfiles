pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — live weather (ported from Ricelin pill/Singletons/Weather.qml),
 * served by Open-Meteo with no API key. Location resolves once and is cached
 * so a restart never re-hits the network for coordinates: by default the
 * city, latitude and longitude come from a keyless IP lookup (ip-api), but a
 * non-empty `Flags.weatherCity` override geocodes that name via Open-Meteo's
 * geocoder instead. Once coordinates are known the forecast runs immediately
 * and then every 20 minutes, exposing the current conditions plus a 24-hour
 * hourly strip and a short daily outlook.
 *
 * Two keyless forecast backends: Open-Meteo first, MET Norway (api.met.no)
 * as the fallback. Open-Meteo's forecast host can be unreachable from a
 * network while its geocoder still answers (2026-11-15 here: TCP connects,
 * the TLS handshake never completes), so a fetch that yields nothing usable
 * retries once on the other backend, and whichever answered is tried first
 * from then on (`source`, cached with the coordinates). MET Norway's
 * symbol codes are mapped onto WMO codes so every consumer stays on one
 * vocabulary.
 *
 * Everything is async through `Process` + `curl` so startup never blocks on
 * a slow or absent connection. The network FLAKES on this box, so a failed
 * or empty fetch is NORMAL: every JSON parse is guarded, a partial body or
 * network blip leaves the last good values in place, and `ready` simply
 * stays false until the first clean fetch lands — consumers show a dim
 * placeholder until then, never an error.
 *
 * Conditions map to GlyphIcon names via `glyphFor` — sun/moon, cloud,
 * cloud-rain, cloud-snow, cloud-fog, cloud-lightning — keyed off the WMO
 * weather code, with `labelFor` giving the short english word.
 */
Singleton {
    id: root

    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/astralis"

    property int tempNow: 0
    property int codeNow: 0
    property int humidity: 0
    property bool isDay: true
    property string city: ""
    property var hourly: []
    property var daily: []
    property bool ready: false

    property real lat: 0
    property real lon: 0
    property bool located: false

    /** Backend that answered last — "om" (Open-Meteo) or "met" (MET Norway); tried first next time. */
    property string source: "om"
    /** This refresh already fell back once; a second failure keeps the last good values. */
    property bool fellBack: false

    /**
     * Maps a WMO weather code to its GlyphIcon name. Clear skies show the
     * moon at night so the glance reads day-versus-night at a glance; every
     * other condition is the same glyph round the clock.
     */
    function glyphFor(code, day) {
        if (code === 0)
            return day ? "sun" : "moon";
        if (code <= 3)
            return "cloud";
        if (code === 45 || code === 48)
            return "cloud-fog";
        if (code >= 95)
            return "cloud-lightning";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return "cloud-snow";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return "cloud-rain";
        return "cloud";
    }

    /** Short english word for a WMO weather code, for labels and accessibility. */
    function labelFor(code) {
        if (code === 0)
            return "Clear";
        if (code <= 3)
            return "Cloudy";
        if (code === 45 || code === 48)
            return "Fog";
        if (code >= 95)
            return "Thunder";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return "Snow";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return "Rain";
        return "Cloudy";
    }

    /** Persist resolved coordinates so a restart skips the location round-trip. */
    function writeLoc() {
        locCache.setText(JSON.stringify({ city: root.city, lat: root.lat, lon: root.lon, source: root.source }));
    }

    function fetchWeather() {
        if (!located || wxProc.running || metProc.running)
            return;
        fellBack = false;
        (source === "met" ? metProc : wxProc).running = true;
    }

    /** `from` returned nothing usable: try the other backend once this refresh. */
    function fallback(from) {
        if (fellBack)
            return;
        fellBack = true;
        (from === "om" ? metProc : wxProc).running = true;
    }

    /** A backend delivered: remember it so the next refresh starts there. */
    function answered(from) {
        if (source === from)
            return;
        source = from;
        writeLoc();
    }

    /**
     * MET Norway symbol_code → the WMO code the rest of the shell speaks.
     * Day/night lives in the suffix (`clearsky_night`), read separately.
     */
    function wmoFromSymbol(sym) {
        var b = String(sym || "").replace(/_(day|night|polartwilight)$/, "");
        if (b === "clearsky")
            return 0;
        if (b === "fair")
            return 1;
        if (b === "partlycloudy")
            return 2;
        if (b === "fog")
            return 45;
        if (b.indexOf("thunder") >= 0)
            return 95;
        if (b.indexOf("snow") >= 0)
            return b.indexOf("showers") >= 0 ? 85 : 73;
        if (b.indexOf("sleet") >= 0)
            return 66;
        if (b.indexOf("rain") >= 0)
            return b.indexOf("showers") >= 0 ? 80 : 61;
        return 3;
    }

    /** Symbol for the nearest forecast horizon of one timeseries step, "" when none. */
    function metSymbol(data) {
        var n = data && (data.next_1_hours || data.next_6_hours || data.next_12_hours);
        return n && n.summary ? n.summary.symbol_code : "";
    }

    /**
     * Parses a MET Norway locationforecast/compact body into the same shape
     * the Open-Meteo path fills. Times arrive in UTC and are read in local
     * time. Returns false when the body is unusable.
     */
    function applyMet(text) {
        var d = JSON.parse(text);
        var ts = d && d.properties && d.properties.timeseries;
        if (!ts || !ts.length)
            return false;
        var now = Date.now();
        // current = the last step that has started (the first one may already be past)
        var ci = 0;
        for (var k = 0; k < ts.length && Date.parse(ts[k].time) <= now; k++)
            ci = k;
        var cur = ts[ci].data;
        var det = cur && cur.instant && cur.instant.details;
        if (!det || typeof det.air_temperature !== "number")
            return false;
        var curSym = metSymbol(cur);
        var curHour = new Date(ts[ci].time).getHours();

        var rows = [];
        for (var i = ci; i < ts.length && rows.length < 24; i++) {
            var di = ts[i].data;
            if (!di.next_1_hours || !di.instant || !di.instant.details)
                break; // past ~2.5 days the steps go 6-hourly
            var t = new Date(ts[i].time);
            rows.push({
                hour: (t.getHours() < 10 ? "0" : "") + t.getHours(),
                temp: Math.round(di.instant.details.air_temperature),
                code: wmoFromSymbol(metSymbol(di))
            });
        }

        // daily: max temperature, mean humidity, and the symbol nearest local noon
        var dn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        var byDay = {}, order = [];
        for (var j = 0; j < ts.length; j++) {
            var dj = ts[j].data;
            var dt = dj && dj.instant && dj.instant.details;
            if (!dt || typeof dt.air_temperature !== "number")
                continue;
            var tj = new Date(ts[j].time);
            var key = tj.getFullYear() + "-" + tj.getMonth() + "-" + tj.getDate();
            if (!byDay[key]) {
                if (order.length >= 5)
                    break;
                byDay[key] = { day: dn[tj.getDay()], max: -999, min: 999, rhSum: 0, rhN: 0, sym: "", noonGap: 99 };
                order.push(key);
            }
            var b = byDay[key];
            b.max = Math.max(b.max, dt.air_temperature);
            b.min = Math.min(b.min, dt.air_temperature);
            if (typeof dt.relative_humidity === "number") {
                b.rhSum += dt.relative_humidity;
                b.rhN++;
            }
            var sj = metSymbol(dj);
            var gap = Math.abs(tj.getHours() - 12);
            if (sj.length && gap < b.noonGap) {
                b.sym = sj;
                b.noonGap = gap;
            }
        }
        var days = order.map(function (key) {
            var b = byDay[key];
            return { day: b.day, code: wmoFromSymbol(b.sym), temp: Math.round(b.max), lo: Math.round(b.min), rh: b.rhN ? Math.round(b.rhSum / b.rhN) : 0 };
        });

        root.tempNow = Math.round(det.air_temperature);
        root.codeNow = wmoFromSymbol(curSym);
        root.humidity = Math.round(det.relative_humidity || 0);
        root.isDay = /_night$/.test(curSym) ? false
            : (/_(day|polartwilight)$/.test(curSym) ? true : (curHour >= 6 && curHour < 19));
        root.hourly = rows;
        root.daily = days;
        root.ready = true;
        return true;
    }

    /**
     * Loads cached coordinates synchronously (blockLoading) and fetches at once;
     * an absent or malformed cache falls through to a fresh location lookup.
     */
    Component.onCompleted: {
        try {
            var c = JSON.parse(locCache.text());
            if (c && typeof c.lat === "number" && typeof c.lon === "number") {
                root.city = c.city || "";
                root.lat = c.lat;
                root.lon = c.lon;
                if (c.source === "om" || c.source === "met")
                    root.source = c.source;
                root.located = true;
                root.fetchWeather();
                return;
            }
        } catch (e) {}
        root.locate();
    }

    FileView {
        id: locCache
        path: root.cacheDir + "/weather-loc.json"
        blockLoading: true
        printErrors: false
    }

    /** Resolve coordinates: geocode the manual city override, else fall back to IP. */
    function locate() {
        if (ipProc.running || geoProc.running)
            return;
        if (Flags.weatherCity && Flags.weatherCity.trim().length > 0)
            geoProc.running = true;
        else
            ipProc.running = true;
    }

    Connections {
        target: Flags
        function onWeatherCityChanged() { root.locate(); }
    }

    Process {
        id: ipProc
        command: ["curl", "-s", "--max-time", "8", "http://ip-api.com/json?fields=lat,lon,city"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (typeof d.lat === "number" && typeof d.lon === "number") {
                        root.city = d.city || "";
                        root.lat = d.lat;
                        root.lon = d.lon;
                        root.located = true;
                        root.writeLoc();
                        root.fetchWeather();
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: geoProc
        command: ["curl", "-s", "--max-time", "8", "-G",
            "https://geocoding-api.open-meteo.com/v1/search",
            "--data-urlencode", "name=" + (Flags.weatherCity || ""),
            "--data-urlencode", "count=1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    var r = d.results && d.results[0];
                    if (r && typeof r.latitude === "number" && typeof r.longitude === "number") {
                        root.city = r.name || "";
                        root.lat = r.latitude;
                        root.lon = r.longitude;
                        root.located = true;
                        root.writeLoc();
                        root.fetchWeather();
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: wxProc
        command: ["curl", "-s", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + root.lat
            + "&longitude=" + root.lon
            + "&current=temperature_2m,weather_code,is_day,relative_humidity_2m"
            + "&hourly=temperature_2m,weather_code&forecast_hours=24"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,relative_humidity_2m_mean&forecast_days=5&timezone=auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                // a timeout leaves an empty body: JSON.parse throws → fall back
                var ok = false;
                try {
                    var d = JSON.parse(this.text);
                    var cur = d.current;
                    if (!cur)
                        throw "no current";
                    var rows = [];
                    var h = d.hourly;
                    if (h && h.time && h.temperature_2m && h.weather_code) {
                        var n = Math.min(h.time.length, h.temperature_2m.length, h.weather_code.length);
                        for (var i = 0; i < n; i++) {
                            rows.push({
                                hour: h.time[i].slice(11, 13),
                                temp: Math.round(h.temperature_2m[i]),
                                code: h.weather_code[i]
                            });
                        }
                    }
                    var days = [];
                    var dd = d.daily;
                    if (dd && dd.time && dd.weather_code && dd.temperature_2m_max && dd.relative_humidity_2m_mean) {
                        var dn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                        var m = Math.min(dd.time.length, dd.weather_code.length, dd.temperature_2m_max.length, dd.relative_humidity_2m_mean.length);
                        for (var j = 0; j < m; j++) {
                            days.push({
                                day: dn[new Date(dd.time[j] + "T00:00:00").getDay()],
                                code: dd.weather_code[j],
                                temp: Math.round(dd.temperature_2m_max[j]),
                                lo: dd.temperature_2m_min ? Math.round(dd.temperature_2m_min[j]) : Math.round(dd.temperature_2m_max[j]),
                                rh: Math.round(dd.relative_humidity_2m_mean[j])
                            });
                        }
                    }
                    root.tempNow = Math.round(cur.temperature_2m);
                    root.codeNow = cur.weather_code;
                    root.humidity = Math.round(cur.relative_humidity_2m);
                    root.isDay = cur.is_day === 1;
                    root.hourly = rows;
                    root.daily = days;
                    root.ready = true;
                    ok = true;
                } catch (e) {}
                if (ok)
                    root.answered("om");
                else
                    root.fallback("om");
            }
        }
    }

    Process {
        id: metProc
        // api.met.no wants an identifying User-Agent and at most 4 decimals
        command: ["curl", "-s", "--max-time", "10", "-A", "astralis-shell/1.0",
            "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=" + root.lat.toFixed(4)
            + "&lon=" + root.lon.toFixed(4)]
        stdout: StdioCollector {
            onStreamFinished: {
                var ok = false;
                try {
                    ok = root.applyMet(this.text);
                } catch (e) {}
                if (ok)
                    root.answered("met");
                else
                    root.fallback("met");
            }
        }
    }

    Timer {
        interval: 1200000
        running: true
        repeat: true
        onTriggered: root.fetchWeather()
    }
}
