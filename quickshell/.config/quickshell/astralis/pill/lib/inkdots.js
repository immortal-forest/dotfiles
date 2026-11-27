.pragma library

/**
 * astralis — sumi dabs for the password fields (pill/PassDots.qml).
 *
 * Each typed character is one 点 (ten): the brush touches down light at the
 * upper left, presses into a full, slightly flattened head at the lower
 * right and lifts. Built as a polar outline in a 24×24 box — a round head
 * with a short tapered entry tail — plus a little bristle irregularity, all
 * from a seed, so no two dabs in a run are the same and a retyped password
 * deals new ones. Paths are cached per seed.
 */

const N = 72;
const cache = {};

function rng(seed) {
    let h = (seed >>> 0) || 1;
    return () => {
        h ^= h << 13; h >>>= 0;
        h ^= h >>> 17;
        h ^= h << 5; h >>>= 0;
        return h / 4294967296;
    };
}

const shapes = {};

/**
 * The dab for `seed` (any integer), in a 24×24 box: `pts` (closed outline),
 * `tip` (where the brush touched down), `head` (centre of the pressed head)
 * and `dir` (unit vector tip → head). Cached per seed.
 */
function shape(seed) {
    const key = seed | 0;
    if (shapes[key])
        return shapes[key];
    const r = rng(key * 2654435761 + 97);
    // tail toward the upper left (screen y grows down), varied a little
    const theta = Math.PI + 0.66 + (r() - 0.5) * 0.6;
    const tail = 0.62 + r() * 0.34;         // how far the entry point reaches
    const sharp = 8 + r() * 4;              // how quickly it tapers to the point
    const flank = 0.10 + r() * 0.08;        // one side of the stroke fuller than the other
    const press = 0.78 + r() * 0.12;        // head flattened along the stroke's normal
    const a1 = 0.025 + r() * 0.03, p1 = r() * 6.28;
    const a2 = 0.015 + r() * 0.02, p2 = r() * 6.28;
    const nx = Math.cos(theta + Math.PI / 2), ny = Math.sin(theta + Math.PI / 2);

    const raw = [];
    let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    let tipI = 0, tipR = -1;
    for (let i = 0; i < N; i++) {
        const t = (i / N) * Math.PI * 2;
        const c = Math.cos(t - theta);
        let rr = 1 + tail * Math.pow(Math.max(0, c), sharp);
        // the belly: fuller on the side the brush rolls onto as it presses
        rr *= 1 + flank * Math.sin(t - theta);
        rr *= 1 + a1 * Math.sin(3 * t + p1) + a2 * Math.sin(7 * t + p2);
        let x = rr * Math.cos(t);
        let y = rr * Math.sin(t);
        // flatten across the stroke: scale the component along the normal
        const d = x * nx + y * ny;
        x -= d * nx * (1 - press);
        y -= d * ny * (1 - press);
        raw.push([x, y]);
        if (c > tipR) { tipR = c; tipI = i; }
        minX = Math.min(minX, x); maxX = Math.max(maxX, x);
        minY = Math.min(minY, y); maxY = Math.max(maxY, y);
    }
    const k = 21 / Math.max(maxX - minX, maxY - minY);
    const ox = 12 - (minX + maxX) / 2 * k;
    const oy = 12 - (minY + maxY) / 2 * k;
    const pts = raw.map(p => [ox + p[0] * k, oy + p[1] * k]);
    const tip = pts[tipI];
    const head = [ox, oy];   // the polar centre is the middle of the pressed head
    let dx = head[0] - tip[0], dy = head[1] - tip[1];
    const len = Math.hypot(dx, dy) || 1;
    const out = { pts: pts, tip: tip, head: head, dir: [dx / len, dy / len], len: len };
    shapes[key] = out;
    return out;
}

/** SVG path of the dab for `seed`, for Shape overlays. */
function dab(seed) {
    const key = seed | 0;
    if (cache[key])
        return cache[key];
    const pts = shape(key).pts;
    let s = "";
    for (let i = 0; i < pts.length; i++)
        s += (i ? "L" : "M") + pts[i][0].toFixed(2) + " " + pts[i][1].toFixed(2) + " ";
    cache[key] = s + "Z";
    return cache[key];
}

/** Bristle gaps for the dry-brush entry: [{off, from, to, w}] in stroke units, seeded. */
function bristles(seed) {
    const r = rng((seed | 0) * 69069 + 5);
    const n = 3 + Math.floor(r() * 3);
    const out = [];
    for (let i = 0; i < n; i++)
        out.push({ off: (r() - 0.5) * 0.9, from: -0.15, to: 0.35 + r() * 0.35, w: 0.35 + r() * 0.45 });
    return out;
}

/** A small resting tilt per dab, degrees — the hand is never exactly level. */
function tilt(seed) {
    const r = rng((seed | 0) * 40503 + 11);
    r();
    return (r() - 0.5) * 22;
}
