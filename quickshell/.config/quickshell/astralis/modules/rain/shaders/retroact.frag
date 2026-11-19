#version 440
// Retroact Rain (Wuthering Waves) — rain that falls, stops in mid-air, then
// falls UP. One analytic pass: sky, three back layers of drops masked by the
// wallpaper's depth cut-out (they pass behind the subject), the front layer.
//
// Drive it from QML with two numbers:
//   vel    — current speed in screen heights/s (+ falls, - rises)
//   travel — vel integrated over time (so drops keep their place when vel changes)
//
// `wall` is the wallpaper image itself, whole; wallScale maps screen uv onto
// it the way skwd-paper's `fill` (centred cover crop) shows it. `cut` is the
// depth cut-out, already cropped to the screen; only its alpha is used, since
// the pixels it would paint are the wallpaper's own, already on screen below.
//
// Every drop is the same thing: a glass capsule that bends the wallpaper
// behind it, stretched along its motion. Falling fast it is a thin streak;
// as it stops it shortens into a round bead; rising it is a slightly tall
// bubble with a glint on top and a caustic underneath (the open-world
// footage), never a splash.
//
//   /usr/lib/qt6/bin/qsb --glsl "300 es,330" --hlsl 50 --msl 12 -o retroact.frag.qsb retroact.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float travel;
    float vel;
    float aspect;
    float density;
    float sizeMul;     // drop size, x the default
    float sky;
    float cutMix;
    vec2 wallScale;
    vec4 tint;
};
layout(binding = 1) uniform sampler2D wall;
layout(binding = 2) uniform sampler2D cut;

const float SHUTTER = 0.03;   // s of motion smeared into one frame
const float KEEP = 0.40;      // share of the still drops that rise

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float h21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
vec2 h22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// gradient noise, -1..1
float gnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = dot(h22(i) * 2.0 - 1.0, f);
    float b = dot(h22(i + vec2(1, 0)) * 2.0 - 1.0, f - vec2(1, 0));
    float c = dot(h22(i + vec2(0, 1)) * 2.0 - 1.0, f - vec2(0, 1));
    float d = dot(h22(i + vec2(1, 1)) * 2.0 - 1.0, f - vec2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.4;
}

// distance to segment a-b, and how far along it (0 at a, 1 at b)
vec2 seg(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
    return vec2(length(pa - ba * h), h);
}

vec4 over(vec4 src, vec4 dst) { return src + dst * (1.0 - src.a); }

// the wallpaper as the screen shows it at screen uv p
vec3 wallAt(vec2 p) { return textureLod(wall, (p - 0.5) * wallScale + 0.5, 0.0).rgb; }

vec4 drops(float L, vec2 P, vec2 uv, float px, float falling, float still, float rising) {
    float n = L / 3.0;
    float cell = mix(0.07, 0.21, n);
    float size = mix(0.0030, 0.0085, n) * sizeMul;
    float spd  = mix(0.55, 1.45, n);
    float lum  = mix(0.55, 1.0, n);

    vec2 q = (P + vec2(h11(L * 7.13) * 31.0, h11(L * 3.71) * 17.0)) / cell;
    float col = floor(q.x);
    float cs = spd * mix(0.82, 1.18, h11(col * 1.37 + L * 31.0));
    q.y += h11(col * 2.91 + L) * 13.0;
    q.y -= travel * cs / cell;
    float v = vel * cs;                        // this column's speed, h/s
    float sg = vel >= 0.0 ? -1.0 : 1.0;        // the tail trails the motion (+y is down)

    // long streaks reach into the next cell; beads only past the nearer border
    int lo = -1, hi = 1;
    if (falling < 0.01) {
        lo = fract(q.y) < 0.5 ? -1 : 0;
        hi = lo + 1;
    }

    vec4 lay = vec4(0.0);
    for (int dy = lo; dy <= hi; dy++) {
        vec2 id = vec2(col, floor(q.y) + float(dy));
        vec2 r = h22(id + L * 17.0);
        if (r.x > density)
            continue;
        float r2 = h21(id * 1.31 + 4.0);
        float r3 = h21(id * 0.77 + 9.0);
        float r4 = h21(id * 2.17 + 1.3);
        // a share of the still drops rise; the rest shrink away as the rise begins
        float keep = 1.0 - smoothstep(-0.05, 0.05, r4 - mix(1.06, KEEP, rising));
        if (keep <= 0.0)
            continue;
        vec2 ctr = vec2(col + 0.18 + 0.64 * r.y, id.y + 0.5 + 0.35 * (r2 - 0.5));
        vec2 d = (q - ctr) * cell;             // pixel relative to the head, h units
        float s = size * mix(0.65, 1.35, r3);
        // rising bubbles run a touch bigger, the odd one close to the lens much bigger
        float near = (L > 2.5 && r2 > 0.8) ? 1.0 : 0.0;
        s *= mix(1.0, 1.2 + near * 1.1, rising) * mix(0.35, 1.0, keep);

        // still: a slow hover and a glint that comes and goes
        d.y += still * sin(time * (0.9 + r2) + r3 * 6.28) * s * 0.35;
        float glint = 0.55 + 0.45 * sin(time * (1.3 + 1.7 * r.y) + r2 * 6.28);

        // the shape: an ellipse stretched back along the motion from the head —
        // a tapered needle falling, a round bead still, a tall oval rising
        float len = max(v, 0.0) * SHUTTER + rising * s * mix(0.5, 1.3, r3);
        float rad = s * (falling * 0.2 + still + rising * 0.85);
        float radE = max(rad, px * 0.7);       // never under ~1.4 px wide…
        float thin = rad / radE;               // …a thinner streak fades instead
        vec2 ax = vec2(radE, radE + len * 0.5);                 // semi-axes
        vec2 dc = d - vec2(0.0, sg * len * 0.5);                // from the centre
        vec2 o = dc / ax;                                       // unit ellipse
        float rr = length(o);
        float aaw = px / radE;
        float body = 1.0 - smoothstep(1.0 - aaw, 1.0 + aaw, rr);
        if (body <= 0.0)
            continue;

        float stretch = smoothstep(1.5, 6.0, len / radE);    // 0 bead … 1 streak
        // lens: flipped and magnified, the way a real drop shows the scene
        vec2 lens = -o * ax * vec2(2.2, mix(2.2, 0.4, stretch));
        vec3 bg = wallAt(uv + vec2(lens.x / aspect, lens.y));

        float rim  = smoothstep(0.5, 1.0, rr);
        float ring = smoothstep(0.8, 0.98, rr);                                   // dark refraction ring
        float side = smoothstep(0.25, 0.95, -o.x) * (1.0 - smoothstep(0.9, 1.0, rr));  // lit left flank
        float spec = 1.0 - smoothstep(0.1, 0.3, length(o - vec2(-0.32, -0.45)));
        float caus = (1.0 - smoothstep(0.15, 0.4, abs(o.y - 0.62))) * (1.0 - smoothstep(0.25, 0.65, abs(o.x))) * (1.0 - stretch);
        float along = 0.5 + 0.5 * o.y * sg;                                      // 0 head … 1 tail
        float fadeT = mix(1.0, mix(1.0, 0.1, along), stretch);                   // streaks thin out behind the head

        vec3 bc = bg * (1.08 - 0.35 * ring)
                + tint.rgb * (rim * 0.2 + side * 0.3 + caus * 0.4 + spec * glint * 1.2 + stretch * 0.22);
        float ba = body * thin * fadeT * (0.85 + 0.15 * spec) * mix(1.0, 0.8, stretch) * keep * lum;
        lay = over(vec4(bc * ba, ba), lay);
    }
    return lay;
}

// fast glints while rising: long faint vertical streaks that live 2-3 frames
// and shoot up (close drops smeared by the shutter, in both references)
vec4 glints(bool front, vec2 P, float px, float rising) {
    float rate = 24.0;
    float slot = floor(time * rate);
    float age = fract(time * rate) / rate;                   // s since this slot began
    vec2 csz = front ? vec2(0.16, 0.34) : vec2(0.075, 0.30);
    vec2 cid = floor(P / csz);
    vec2 g = cid + vec2(slot * 17.0, slot * 3.0) + (front ? 50.0 : 0.0);
    if (h21(g + 3.3) >= (front ? 0.05 : 0.2))
        return vec4(0.0);
    float x0 = (cid.x + 0.1 + 0.8 * h21(g + 7.7)) * csz.x;
    float len = (0.05 + 0.10 * h21(g + 5.1)) * (front ? 1.4 : 1.0);
    float y0 = (cid.y + 0.25 + 0.5 * h21(g + 1.9)) * csz.y - age * 2.2;   // centre, rising
    vec2 sd = seg(P, vec2(x0, y0 + len * 0.5), vec2(x0, y0 - len * 0.5));
    float w = max(px * 0.8, front ? 0.0026 : 0.0016);
    float k = (1.0 - smoothstep(w * 0.4, w * 1.6, sd.x)) * sin(sd.y * 3.14159);
    k *= (front ? 0.28 : 0.2) * mix(0.5, 1.0, h21(g + 9.4)) * rising;
    return vec4(tint.rgb * k, k);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 P = vec2(uv.x * aspect, uv.y);          // screen-height units, +y down
    float px = max(fwidth(P.y), 1e-5);            // one pixel

    // 0 falling … 1 still … rising
    float falling = smoothstep(0.25, 1.4, vel);
    float rising  = smoothstep(0.04, 0.3, -vel);
    float still   = clamp(1.0 - falling - rising, 0.0, 1.0);

    vec4 acc = vec4(0.0);

    // ── the inverted sea overhead: the underside of a water surface ──
    if (sky > 0.001 && uv.y < 0.5) {
        float t = time;
        float fade = 1.0 - smoothstep(0.04, 0.5, uv.y);
        vec2 q = vec2(P.x * 6.0, P.y * 17.0);
        vec2 w = vec2(gnoise(q * 0.35 + vec2(t * 0.07, 0.0)), gnoise(q * 0.35 + vec2(5.2, t * 0.06)));
        float n = gnoise(q + w * 1.6 + vec2(t * 0.04, -t * 0.03))
                + 0.45 * gnoise(q * 2.3 + w * 2.0 + vec2(-t * 0.06, t * 0.05));
        float d1 = abs(n - 0.12), d2 = abs(n + 0.38);
        float r1 = pow(1.0 - min(d1 * 3.0, 1.0), 10.0);
        float r2 = pow(1.0 - min(d2 * 3.0, 1.0), 10.0) * 0.7;
        float frag = smoothstep(-0.15, 0.35, gnoise(q * 0.9 + vec2(-t * 0.05, 21.0)));
        float sheen = pow(1.0 - min(min(d1, d2) * 2.2, 1.0), 3.0) * 0.07;
        float body = 0.35 + 0.65 * smoothstep(-0.4, 0.3, gnoise(q * 0.22 + vec2(11.0, t * 0.02)));
        vec2 gc = floor(q * vec2(3.0, 1.5));
        float tw = step(0.93, h21(gc + floor(t * 2.0 + h21(gc) * 4.0)));
        float lines = max(r1, r2) * frag * body * (1.0 + tw * 1.6);
        float shade = sky * fade * 0.18;
        acc = over(vec4(vec3(0.02, 0.035, 0.06) * shade, shade), acc);
        float a = sky * fade * clamp(lines * 0.4 + sheen * 0.7, 0.0, 1.0);
        acc = over(vec4(tint.rgb * a, a), acc);
    }

    for (int li = 0; li < 3; li++)
        acc = over(drops(float(li), P, uv, px, falling, still, rising), acc);
    if (rising > 0.0)
        acc = over(glints(false, P, px, rising), acc);

    // the wallpaper's foreground: back drops pass behind the subject
    if (cutMix > 0.0)
        acc *= 1.0 - textureLod(cut, uv, 0.0).a * cutMix;

    acc = over(drops(3.0, P, uv, px, falling, still, rising), acc);
    if (rising > 0.0)
        acc = over(glints(true, P, px, rising), acc);

    fragColor = acc * qt_Opacity;
}
