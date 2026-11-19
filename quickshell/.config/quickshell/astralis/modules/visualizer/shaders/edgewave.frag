#version 440
// astralis — the full-screen visualizer's edge wave (VizLayer.qml), drawn in
// ONE analytic pass instead of SVG paths re-triangulated 30×/s.
//
// Every edge a layout uses is a rail: `along` runs 0..1 down the edge and
// `across` is px in from it. Each rail maps `along` linearly onto the layout's
// path parameter t (eX.y at along 0, eX.z at along 1), t picks a spot on the
// spectrum (mirrored, so bass sits mid-path), and the wave is the signed
// distance `across - height(t)`, slope-corrected so the lit crest keeps one
// width up a steep flank. Adjacent rails meet in a smooth union, which rounds
// the inner corner instead of folding it.
//
// Two bodies: behind, the slow-falling trail of recent peaks as a faint veil;
// in front, the live wave, fading toward the screen edge it grows from, with a
// lit crest, hot tips on loud bands, and a two-term bloom outside only (inside
// it would wash the body milky).
//
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,330" --hlsl 50 --msl 12 -o edgewave.frag.qsb edgewave.frag
// then bump the "?v=" on fragmentShader in VizLayer.qml (Qt caches shaders by
// URL; hot reload does not re-read).
//
// Integer maths stays arithmetic (no bitwise ops) so every qsb target agrees.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;

    vec2 res;        // surface size, logical px
    float aa;        // one device pixel, logical px
    float bands;     // live band count (2..48)

    // 48 levels, 16 to a matrix. Qt fills matrix4x4 row-major and GLSL indexes
    // columns, so element n lives at m[n % 4][n / 4].
    mat4 lv0; mat4 lv1; mat4 lv2;   // live, eased
    mat4 pk0; mat4 pk1; mat4 pk2;   // trail: falling peaks

    // Rails: x on, y = t at along 0, z = t at along 1.
    vec4 eTop; vec4 eRight; vec4 eBottom; vec4 eLeft;

    float sym;       // 1 mirror (bass mid-path) · 2 loop (bass at t 0 and 1)
    float closed;    // 1: t wraps (the loop round the screen)
    float taper;     // share of t eased to 0 at each open end
    float depth;     // full wave height, px
    float glowPx;    // bloom reach, px
    float energy;    // 0..1 loudness: lifts the bloom
    float solid;     // 1: opaque body (Flags.vizFill "opaque"), 0: translucent glass

    vec4 c0; vec4 c1; vec4 c2;   // live wave, bass → treble
    vec4 d0; vec4 d1; vec4 d2;   // trail veil, bass → treble
};

float lvAt(int i) {
    int m = i / 16;
    int j = i - 16 * m;
    int r = j / 4;
    int c = j - 4 * r;
    if (m == 0) return lv0[c][r];
    if (m == 1) return lv1[c][r];
    return lv2[c][r];
}

float pkAt(int i) {
    int m = i / 16;
    int j = i - 16 * m;
    int r = j / 4;
    int c = j - 4 * r;
    if (m == 0) return pk0[c][r];
    if (m == 1) return pk1[c][r];
    return pk2[c][r];
}

// Catmull-Rom through the bands at spectrum position s (0..1): value and its
// slope per unit s, so the caller can slope-correct the distance.
vec2 curve(float s, bool trail) {
    float x = clamp(s, 0.0, 1.0) * (bands - 1.0);
    float i1 = floor(x);
    float f = x - i1;
    int a = int(max(i1 - 1.0, 0.0));
    int b = int(i1);
    int c = int(min(i1 + 1.0, bands - 1.0));
    int d = int(min(i1 + 2.0, bands - 1.0));
    float p0 = trail ? pkAt(a) : lvAt(a);
    float p1 = trail ? pkAt(b) : lvAt(b);
    float p2 = trail ? pkAt(c) : lvAt(c);
    float p3 = trail ? pkAt(d) : lvAt(d);
    float A = -p0 + p2;
    float B = 2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3;
    float C = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
    float v = 0.5 * (2.0 * p1 + A * f + B * f * f + C * f * f * f);
    float dv = 0.5 * (A + 2.0 * B * f + 3.0 * C * f * f) * (bands - 1.0);
    return vec2(max(v, 0.0), dv);
}

vec3 ramp3(vec3 a, vec3 b, vec3 c, float t) {
    t = clamp(t, 0.0, 1.0);
    return t < 0.5 ? mix(a, b, t * 2.0) : mix(b, c, t * 2.0 - 1.0);
}

float hash12(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

struct Rail {
    float sd;    // live wave, signed px (negative inside)
    float sdP;   // trail veil
    float h;     // live height here, px
    float hp;    // trail height here, px
    float lift;  // 0 at the baseline, 1 at the crest (straight across, not slope-corrected)
    float s;     // spectrum position (colour)
};

Rail none() {
    Rail o;
    o.sd = 1e5; o.sdP = 1e5; o.h = 0.0; o.hp = 0.0; o.lift = 0.0; o.s = 0.0;
    return o;
}

// t along the layout's path where rail `e` sits at `along`; < -1 when the rail
// is off or that spot is outside the path.
float tOf(vec4 e, float along) {
    if (e.x < 0.5)
        return -2.0;
    float t = e.y + (e.z - e.y) * along;
    if (closed > 0.5)
        return fract(t);
    return (t < -0.0001 || t > 1.0001) ? -2.0 : clamp(t, 0.0, 1.0);
}

// The wave at path position t, `across` px in from its baseline; `dtdpx` is
// how fast t runs per px along the baseline (for the slope correction).
Rail wave(float t, float across, float dtdpx) {
    Rail o;
    float env = 1.0;
    if (taper > 0.0) {
        float q = min(t, 1.0 - t) / taper;
        if (q < 1.0)
            env = q * q * (3.0 - 2.0 * q);
    }
    float s, dsdt;
    if (sym > 1.5) {            // loop: bass at both ends of t, treble mid
        s = 1.0 - abs(1.0 - 2.0 * t);
        dsdt = t < 0.5 ? 2.0 : -2.0;
    } else {                    // mirror: bass mid-path, treble at the ends
        s = abs(2.0 * t - 1.0);
        dsdt = t < 0.5 ? -2.0 : 2.0;
    }
    // d(height px)/d(along px) = depth·env · dv/ds · ds/dt · dt/dpx
    float k = depth * env * dsdt * dtdpx;

    // Slope correction is a first-order fix that only holds near the curve:
    // far below a steep flank it would keep the bloom lit straight down in
    // streaks. Hand back to the plain distance as it leaves the crest.
    vec2 live = curve(s, false);
    o.h = depth * env * live.x;
    float sl = k * live.y;
    float raw = across - o.h;
    o.sd = mix(raw * inversesqrt(1.0 + sl * sl), raw, smoothstep(glowPx, glowPx * 4.0, abs(raw)));

    vec2 pk = curve(s, true);
    o.hp = depth * env * pk.x;
    float slp = k * pk.y;
    float rawP = across - o.hp;
    o.sdP = mix(rawP * inversesqrt(1.0 + slp * slp), rawP, smoothstep(glowPx, glowPx * 4.0, abs(rawP)));

    o.lift = clamp(across / max(o.h, 1.0), 0.0, 1.0);
    o.s = s;
    return o;
}

// Each live corner owns a square this far along both of its edges.
float cornerQ() {
    return depth * 0.6;
}

// A straight rail. A live corner at either end owns the first cornerQ() px of
// it; the rail spreads its stretch of the path over what is left, so it hands
// over to the corner exactly at the corner's own path position.
Rail rail(vec4 e, float along, float across, float len, bool ownedLo, bool ownedHi) {
    float px = along * len;
    float Q = cornerQ();
    float lo = ownedLo ? Q : 0.0;
    float hi = ownedHi ? Q : 0.0;
    if (px < lo || px > len - hi)
        return none();
    float span = max(len - lo - hi, 1.0);
    float t = tOf(e, (px - lo) / span);
    if (t < -1.0)
        return none();
    return wave(t, across, (e.z - e.y) / span);
}

// Signed distance (positive outside the wave) for a band `h` thick along both
// edges of a corner, its inner corner rounded with radius h (as far as the
// corner square allows). q = distance from (vertical edge, horizontal edge).
float filletSd(vec2 q, float h) {
    float rho = max(0.0, min(h, cornerQ() - h));
    vec2 u = q - vec2(h);
    return (u.x < rho && u.y < rho) ? rho - length(vec2(rho) - u) : min(u.x, u.y);
}

// A corner both of whose rails run into it holds ONE spot of the path: the
// band there keeps that spot's height along both edges and rounds the inside
// with a fillet of the same radius, so it swells and sinks with the music and
// tucks into the screen corner at silence. Letting the spectrum run on round
// the corner squeezed its detail into spikes; letting the two rails' wavy
// bands overlap closed off pockets.
Rail corner(vec2 q, float tc) {
    Rail o = wave(tc, 0.0, 0.0);
    o.sd = filletSd(q, o.h);
    o.sdP = filletSd(q, o.hp);
    o.lift = clamp(1.0 + o.sd / max(o.h, 1.0), 0.0, 1.0);
    return o;
}

void main() {
    vec2 p = qt_TexCoord0 * res;
    float W = res.x;
    float H = res.y;

    // Cheap reject: farther from every live rail than any wave or bloom reaches.
    float reach = depth + glowPx * 6.0;
    float near = 1e5;
    if (eTop.x > 0.5) near = min(near, p.y);
    if (eBottom.x > 0.5) near = min(near, H - p.y);
    if (eLeft.x > 0.5) near = min(near, p.x);
    if (eRight.x > 0.5) near = min(near, W - p.x);
    if (near > reach) {
        fragColor = vec4(0.0);
        return;
    }

    // Live corners: both rails on and on the path at the corner itself.
    bool tl = tOf(eTop, 0.0) > -1.0 && tOf(eLeft, 0.0) > -1.0;
    bool tr = tOf(eTop, 1.0) > -1.0 && tOf(eRight, 0.0) > -1.0;
    bool br = tOf(eBottom, 1.0) > -1.0 && tOf(eRight, 1.0) > -1.0;
    bool bl = tOf(eBottom, 0.0) > -1.0 && tOf(eLeft, 1.0) > -1.0;
    float D = cornerQ();

    Rail r;
    float s, h, hp, lift;
    if (tl && p.x < D && p.y < D) {
        r = corner(vec2(p.x, p.y), tOf(eTop, 0.0));
    } else if (tr && p.x > W - D && p.y < D) {
        r = corner(vec2(W - p.x, p.y), tOf(eTop, 1.0));
    } else if (br && p.x > W - D && p.y > H - D) {
        r = corner(vec2(W - p.x, H - p.y), tOf(eBottom, 1.0));
    } else if (bl && p.x < D && p.y > H - D) {
        r = corner(vec2(p.x, H - p.y), tOf(eBottom, 0.0));
    } else {
        // Straight stretches. Outside the corner squares no two rails' bands
        // can meet (a wave never stands taller than `depth`), so a plain
        // union is exact; colour follows the nearer rail.
        Rail r0 = rail(eTop, p.x / W, p.y, W, tl, tr);
        Rail r1 = rail(eRight, p.y / H, W - p.x, H, tr, br);
        Rail r2 = rail(eBottom, p.x / W, H - p.y, W, bl, br);
        Rail r3 = rail(eLeft, p.y / H, p.x, H, tl, bl);
        r = r0;
        if (r1.sd < r.sd) r = r1;
        if (r2.sd < r.sd) r = r2;
        if (r3.sd < r.sd) r = r3;
        float sdP = min(min(r0.sdP, r1.sdP), min(r2.sdP, r3.sdP));
        if (r.sd > 1e4 && sdP > 1e4) {
            fragColor = vec4(0.0);
            return;
        }
        r.sdP = sdP;
    }
    float sd = r.sd;
    float sdP = r.sdP;
    s = r.s;
    h = r.h;
    hp = r.hp;
    lift = r.lift;

    float lvl = clamp(h / max(depth, 1.0), 0.0, 1.0);
    // Where the wave has sunk to nothing, crest and bloom go too: no lit
    // hairline left lying along the screen edge.
    float present = smoothstep(0.0, 6.0, h);

    // ── live wave ──────────────────────────────────────────────────────────
    float body = 1.0 - smoothstep(-aa, aa, sd);
    // Glass: roots read as light rather than paint, the tip carries full
    // weight. Opaque: one solid body, as the wave used to be.
    float fillA = body * (solid > 0.5 ? 1.0 : mix(0.42, 0.9, lift * lift)) * present;
    float crestW = max(1.1, aa * 2.2);
    float crest = exp(-abs(sd) / crestW) * 0.7 * present;
    float g = max(sd, 0.0);
    float halo = (exp(-g / max(glowPx * 0.45, 0.8)) * 0.38
                + exp(-g / max(glowPx * 2.6, 3.0)) * 0.16)
                * (0.3 + 0.7 * energy) * (1.0 - body) * present;

    vec3 col = ramp3(c0.rgb, c1.rgb, c2.rgb, s);
    // A loud band's tip runs hot — what makes a spectrum look lit. Gentle: a
    // hard push to white would drain the wallpaper accent.
    vec3 hot = min(col * 1.25 + 0.10, vec3(1.0));
    vec3 bodyCol = mix(col, hot, smoothstep(0.55, 1.0, lift) * smoothstep(0.25, 0.9, lvl) * 0.6);
    vec3 crestCol = mix(col, hot, 0.75);

    float aMain = clamp(fillA + crest + halo, 0.0, 1.0);
    vec3 pMain = bodyCol * fillA + crestCol * crest + col * halo;

    // ── trail veil (behind) ───────────────────────────────────────────────
    float bodyP = 1.0 - smoothstep(-aa * 1.5, aa * 1.5 + 1.0, sdP);
    float liftP = clamp(1.0 + sdP / max(depth * 0.1, 1.0), 0.0, 1.0);
    float veil = bodyP * mix(0.10, 0.26, liftP) * smoothstep(0.0, 6.0, hp);
    float rim = exp(-abs(sdP) / max(1.0, aa * 1.6)) * 0.32 * smoothstep(0.0, 6.0, hp);
    vec3 colP = ramp3(d0.rgb, d1.rgb, d2.rgb, s);
    float aP = clamp(veil + rim, 0.0, 1.0);
    vec3 pP = colP * aP;

    // live over trail, premultiplied
    float a = aMain + aP * (1.0 - aMain);
    vec3 rgb = pMain + pP * (1.0 - aMain);

    if (a <= 0.002) {
        fragColor = vec4(0.0);
        return;
    }
    // A touch of noise keeps the long soft bloom from banding.
    float n = (hash12(p * 1.37) - 0.5) / 255.0;
    a = clamp(a + n, 0.0, 1.0);
    fragColor = vec4(rgb + n, a) * qt_Opacity;
}
