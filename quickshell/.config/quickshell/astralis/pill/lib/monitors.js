/**
 * astralis — `hyprctl monitors -j` parsing for the 画 DISPLAY settings page
 * (ported from Ricelin pill/lib/monitors.js). Ricelin's setMonitor/replaceField
 * Lua-rewrite half is dropped: astralis persists monitor specs through the
 * Services.Settings overlay (settings.json + hypr-settings.lua), never by
 * editing hypr.d/monitor.lua in place.
 */

/**
 * Parses one availableModes entry like "2560x1440@279.96Hz" into its parts. The
 * Hz is rounded to a whole number for UI grouping and the apply mode string,
 * while `raw` keeps the original entry for reference. Returns null when the
 * entry does not match the WxH@HZHz shape.
 */
function parseMode(raw) {
    var m = raw.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
    if (!m)
        return null;
    return {
        w: parseInt(m[1], 10),
        h: parseInt(m[2], 10),
        hz: Math.round(parseFloat(m[3])),
        raw: raw
    };
}

/**
 * Parses the `hyprctl monitors -j` text into the slim shape the Display page
 * needs: per monitor its name, current width/height/refresh/scale/x/y and
 * transform (astralis delta: Ricelin had no transform control) plus the
 * available modes as `{ w, h, hz, raw }`. Refresh is rounded the same way as a
 * mode's Hz so the current mode can be matched against the list. Modes that do
 * not parse are dropped. Returns [] on bad input.
 */
function parse(jsonText) {
    var data;
    try {
        data = JSON.parse(jsonText);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(data))
        return [];

    return data.map(function (mon) {
        var modes = (mon.availableModes || [])
            .map(parseMode)
            .filter(function (m) { return m !== null; });
        return {
            name: mon.name,
            width: mon.width,
            height: mon.height,
            refresh: Number.isFinite(mon.refreshRate) ? Math.round(mon.refreshRate) : 0,
            scale: mon.scale,
            x: mon.x,
            y: mon.y,
            transform: mon.transform || 0,
            modes: modes
        };
    });
}
