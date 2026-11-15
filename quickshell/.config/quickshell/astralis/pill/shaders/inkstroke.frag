#version 440
// astralis — 筆 ink-brush progress stroke (InkStroke.qml).
// Rebuild after editing:
//   /usr/lib/qt6/bin/qsb --glsl "300 es,330" --hlsl 50 --msl 12 -o inkstroke.frag.qsb inkstroke.frag
// then bump the "?v=" on fragmentShader in InkStroke.qml, or a running shell
// keeps the old one (Qt caches shaders by URL; hot reload does not re-read).
//
// Coordinates are the InkStroke item's own logical px (the shader rect
// overhangs it by `pad` on every side so the bleed is never clipped). All
// texture noise is keyed to absolute x, so it never swims as the stroke grows.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;      // shader rect size
    float pad;      // stroke item origin inside the shader rect
    float s;        // scale unit
    float halfW;    // half body thickness at rest pressure
    float inset;    // where the stroke starts
    float usable;   // track length
    float headX;    // where the dry head ends
    float midY;
    float wet;      // 1 wet (playing), 0 dried toward the paper
    vec4 c0;        // ink ramp along the whole track (all equal = flat ink)
    vec4 c1;
    vec4 c2;
    vec4 paper;     // background the dried ink fades toward
    vec4 ghostC;    // the grayed-out full stroke under the ink
    vec4 glintC;    // glint light
    float glintX;   // glint centre
    float glint;    // glint strength, 0 = none
};

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// approximate signed distance to an axis-aligned ellipse (iq)
float sdEllipse(vec2 q, vec2 r) {
    float k0 = length(q / r);
    float k1 = length(q / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 1e-5);
}

vec4 over(vec4 dst, vec3 rgb, float a) {
    return vec4(rgb * a, a) + dst * (1.0 - a);
}

// brush pressure along the stroke: an entry press, a slow uneven breath and
// a little paper-fibre roughness on the edge (unitless, ~1)
float pressure(float u) {
    float press = 0.30 * exp(-max(u, 0.0) / 9.0);
    float breath = 0.09 * sin(u / 11.3) + 0.035 * sin(u / 4.1 + 1.7);
    float rough = 0.06 * (vnoise(vec2(u * 0.7, 3.1)) - 0.5);
    return 1.0 + press + breath + rough;
}

// Ink coverage at p of a stroke whose head ends at `head`. Also hands back
// the signed distance to its outline `d` (for the bleed), where p sits in
// the dry zone `t` (0 body → 1 head) and across the stroke `yn` (-1..1).
// The ghost and the ink are the same stroke with different heads, so the
// ink lands exactly on the ghost behind its own dry zone.
float stroke(vec2 p, vec2 aa, float head, out float d, out float t, out float yn) {
    float len = max(head - inset, 1e-3);
    float u = (p.x - inset) / s;
    float dy = p.y - midY;

    // 掠れ dry zone at the head: the envelope narrows and the bristles run
    // out one by one, outer ones first
    float dry = max(min(22.0 * s, len * 0.45), 1e-3);
    t = clamp((p.x - (head - dry)) / dry, 0.0, 1.0);
    float ht = halfW * pressure(u) * (1.0 - 0.38 * t * t);
    float hb = ht * 0.92;

    // body: vertical distance to the envelope, square-ended at both ends
    // (the entry cap and the bristles round them off)
    float dEnv = dy < 0.0 ? -dy - ht : dy - hb;
    float dx = max(inset - p.x, p.x - head);
    float dBody = length(max(vec2(dx, dEnv), 0.0)) + min(max(dx, dEnv), 0.0);

    // 起筆 entry: the brush lands at the top-left and presses down-right, so
    // the head is an ellipse tilted along "\" — a raised shoulder top-left,
    // the bottom-left cut back. Grows in as the stroke starts.
    float land = smoothstep(0.0, 8.0 * s, len);
    float r0 = halfW * pressure(0.0) * mix(0.55, 1.0, land);
    vec2 cq = p - vec2(inset + 0.1 * r0, midY);
    cq = vec2(cq.x + cq.y, cq.y - cq.x) * 0.70710678;
    float dCap = sdEllipse(cq, vec2(1.22, 0.95) * r0);
    d = smin(dBody, dCap, 1.2 * s);

    float cover = clamp(0.5 - d / aa.y, 0.0, 1.0) * smoothstep(0.0, 1.5 * s, len);

    // bristles: which hair of the brush this row is (varies across the
    // stroke, drifts only slowly along it), so each one runs out once and
    // nothing floats loose past the tip
    yn = clamp(dy / max(ht, 1e-3), -1.0, 1.0);
    float bri = 0.6 * vnoise(vec2(p.x / s * 0.025, dy / s * 1.15 + 11.0))
              + 0.4 * vnoise(vec2(p.x / s * 0.04, dy / s * 2.6 + 3.0));
    float need = -0.06 + 1.1 * pow(t, 1.3) + 0.45 * t * yn * yn;
    float bw = max(fwidth(bri), 0.02);
    // (only inside the dry zone: on fine hairs the AA width can exceed the
    // margin and thin whole rows of the solid body)
    float streak = mix(1.0, smoothstep(need - bw, need + bw, bri), smoothstep(0.0, 0.15, t));
    // a few hairs skip where the brush ran short of ink — mid-zone only, so
    // a hair's last run never sits loose past the gap
    float skip = vnoise(vec2(p.x / s * 0.1, dy / s * 2.6 + 7.0));
    streak *= 1.0 - smoothstep(0.7, 0.8, skip) * smoothstep(0.2, 0.4, t) * (1.0 - smoothstep(0.6, 0.75, t));

    return cover * streak;
}

void main() {
    vec2 p = qt_TexCoord0 * area - vec2(pad);
    vec2 aa = max(fwidth(p), vec2(1e-4));
    float len = headX - inset;
    float dy = p.y - midY;
    vec4 col = vec4(0.0);

    // the unplayed rest: the whole stroke, grayed out, for the ink to fill
    float gd, gt, gyn;
    float ghost = stroke(p, aa, inset + usable, gd, gt, gyn);

    float inkA = 0.0;
    float bleed = 0.0;
    vec3 ink = vec3(0.0);
    vec3 body = vec3(0.0);
    if (len > 0.5) {
        float d, t, yn;
        inkA = stroke(p, aa, headX, d, t, yn);

        // ink colour: the ramp laid along the whole track, so the head's hue
        // reads the level; dried ink mixes toward the paper (no translucency)
        float g = clamp((p.x - inset) / max(usable, 1.0), 0.0, 1.0);
        ink = g < 0.5 ? mix(c0.rgb, c1.rgb, g * 2.0) : mix(c1.rgb, c2.rgb, g * 2.0 - 1.0);
        ink = mix(ink, paper.rgb, 0.45 * (1.0 - wet));

        // optional glint: a bright bead running along the wet ink (long tail
        // behind, short front), lighting the ink itself so it follows the
        // brush shape and the bristles
        float gx = p.x - glintX;
        float gs = (gx < 0.0 ? 9.0 : 3.0) * s;
        float gl = glint * exp(-(gx * gx) / (gs * gs));

        // 滲み bleed: a soft stain into the paper around the body, thinning
        // out toward the dry head; wetter ink bleeds further
        bleed = (0.16 + 0.08 * wet) * exp(-max(d, 0.0) / ((1.8 + 0.8 * wet) * s)) * (1.0 - 0.9 * t);
        bleed *= smoothstep(0.0, 1.5 * s, len) * (1.0 - inkA) * (1.0 + 1.2 * gl);
        ink = mix(ink, glintC.rgb, 0.4 * gl);

        // brush-hair grooves: faint long streaks of thinner ink in the body,
        // none in the solid entry press
        float groove = vnoise(vec2(p.x / s * 0.045, dy / s * 0.95 + 5.0));
        float grooveIn = smoothstep(inset + 4.0 * s, inset + 14.0 * s, p.x);
        body = mix(ink, paper.rgb, 0.1 * grooveIn * smoothstep(0.55, 0.95, groove));
        body = mix(body, glintC.rgb, 0.6 * gl * (1.0 - 0.7 * yn * yn));
    }

    // ghost (not under the ink, so their shared edges don't double up),
    // then the bleed, then the ink
    col = over(col, ghostC.rgb, 0.2 * ghost * (1.0 - inkA));
    col = over(col, ink, min(bleed, 1.0));
    col = over(col, body, inkA);

    fragColor = col * qt_Opacity;
}
