# ASTRALIS — The Ame Soul Bead + Pill Internals Addendum
### The single glowing bead that shapeshifts and flies between every pill state

> **The repo is physically on disk at `~/Ricelin`.** Every agent should read the real
> source there directly — especially `~/Ricelin/configs/quickshell/pill/Ame.qml`, which
> is ~300 lines of hand-tuned canvas timeline that must be **ported near-verbatim** (only
> the color tokens change). Do not reimplement it from a paraphrase; the feel lives in the
> exact numbers.
>
> Standalone add-on to `astralis-quickshell-rice-spec.md`. Covers the "red dot": what it
> is, its forms, its motion, its anchoring, and how to recolor it through matugen.

---

## PART A — Implementation doc

### A.1 The concept
"Ame" (飴) is **one** `Item` — the shell's *only* glowing element. It is not a workspace
dot, not a caret, not a calendar ring: it is a single molten-glass bead that **changes
form and physically flies** to whatever context is active. That unity is the signature.
Recognizing this collapses what looks like six separate accents into one component:

| You see (screenshots/video) | It's the bead in form… |
|---|---|
| Red ring around today "16" in the calendar | `ring` |
| Blinking capsule in the launcher search field | `caret` |
| Bead at the media progress seam / toast | `seam` |
| Glowing dot under the active workspace, on hover | `soul` |
| Plain bead in mixer / power / link | `dock` |
| Bead on a focused settings row | `rowseam` / `tick` |
| Nothing (rest) — the kanji glyph glows instead | `off` |

Idle it just **breathes** (±1.25% scale, ~8s sine). No audio/physics coupling — every
motion is a fixed scripted timeline.

### A.2 Mode → form mapping (driven from `Pill.qml`)
The pill sets the bead's `form` and `point` from whatever's open:
```qml
form:  ameSurface ? ameSurface.ameForm
     : (mode === "hover" && hoverSoulGate ? "soul" : "off")
point: ameSurface ? mapToPill(ameSurface.amePoint)
     : (mode === "hover" ? soulPoint : wakePoint)
```
Each **surface exports its own `ameForm` + `amePoint`** (Calendar → `ring` at today's
cell; Launcher → `caret` in the search row; Media → `seam` at the progress line; Mixer/
Power/Link → `dock`). Surfaces with no anchor (wallpaper) return `null` → bead goes `off`.
In **rest** the bead is `off` and the resting kanji carries the glow; on **hover** it wakes
to `soul` under the active workspace dot.

### A.3 The motion system — three regimes
Total shapeshift flight = **`Motion.shapeshift` = 820 ms** (×0.4 under reduce-motion),
split into three phases by two constants `pAntic = 0.146`, `pFly = 0.658`:

1. **Anticipation (0 → 14.6%)** — the bead *stretches* toward the target
   (`pull = smoothstep(q)·0.55`) and a **remnant droplet pinches off at the origin**
   (separate 350 ms OutCubic fade).
2. **Flight (14.6% → 65.8%)** — a **quadratic bézier** from origin through a perpendicular
   control point (offset **22% of distance** to the side) to the target, eased by
   `easeInOutQuint`. The bead scales to **1.62×** and drags a **15-segment tapered streak**
   whose width/alpha ramp along the curve; heading tracks the path tangent. Crucially the
   **target is recomputed per frame** (`updateFlightGeo()`), so an anchor that slides with
   the pill's 420 ms morph **bends the arc mid-flight — no restart**.
3. **Settle (65.8% → 100%)** — a **three-droplet splash** (angles −2.35, −1.57, −0.79 rad;
   radius `13·sin(hop)`) then an **`easeOutBack` pop** into the final form.

**Thresholds decide which regime runs** (`flightThreshold = 30 px`):
- Target moved **> 30 px** and form changed → full **flight** (the above).
- Target near **but form changed** → **`startMorph`**: skip travel, replay only the settle
  (splash + pop) in place — a nearby form change still reads as a shapeshift.
- **Same form, target moved** (hover width shift, mixer focus hop, media seek) → **glide**:
  chase over **`Motion.glide` = 260 ms** OutCubic, *never* escalating to a flight.

### A.4 Anchoring — where the bead is told to go
- **Hover (`soulPoint`)** uses a **sticky `soulTarget` key**. Each status icon and each
  workspace dot writes it on hover (`onContainsMouseChanged: if (containsMouse)
  soulTarget = "wifi"` … `"battery"`, `"inbox"`, `"mixer"`, `"power"`, `"settings"`,
  `"ws"` + `soulWsIndex`). `soulPoint` maps that key to the icon's center + a `12·s` drop.
  Sticky = crossing a gap between icons doesn't snap the bead home; it flies icon→icon.
- **Workspace dots** compute their center from **end-state** layout widths (`slotCenterX`),
  so the bead aims where the active "stick" *settles*, not where it's currently animating.
- **Wake anchor (`wakePoint`)** = the resting kanji center. Leaving `off` condenses the
  bead there first, then flies/pops to target — stale pre-hidden positions never leak in.

### A.5 The `decide()` coalescing — the subtle correctness bit
`form` and `point` are sibling bindings in `Pill.qml` that change **mid-cascade in
unspecified order**. Deciding synchronously would read a stale partner (a far form change
seeing `dd≈0` against a not-yet-updated point, silently degrading a flight to an in-place
morph). So both `onPointChanged` and `onFormChanged` do `Qt.callLater(decide)` — deferring
until both settle and collapsing a morph's per-frame handler burst into **one retarget per
tick**. `lastTarget` distinguishes a discrete mid-flight hop (hand to a glide) from a morph
slide (bend the arc). **Port this exactly; it's why the bead never teleports or stutters.**

### A.6 Performance (it's a 24/7 shell)
- `FrameAnimation` drives full-rate repaint **only while `busy`** (timeline/glide/remnant
  live). Otherwise a `Timer` ticks the slow inner swirl at **12 fps** (**30 fps** only while
  the caret blinks).
- The `MultiEffect` blur `layer` FBO (size of the whole pill) exists **only while the bead
  is drawn or fading** (`layer.enabled: opacity > 0.001 || busy`) — no GPU tax on an empty
  canvas during rest/wallpaper/toast.

### A.7 Recoloring through matugen (the only change you make to Ame.qml)
Ricelin hard-codes a vermilion ramp (`Theme.verm`, `vermLit`, `flameInk`, `flameEmber`,
`flameTip`, `flameBurn`). Swap these for matugen M3 tokens so the bead recolors with the
wallpaper. The bead's radial gradient runs **bright core → mid → dark edge**:
```qml
// replace the Theme.* constants the bead reads with:
readonly property color beadCore : Qt.lighter(Colors.tertiary, 1.35)  // flameInk  (hot ember core)
readonly property color beadLit  : Colors.tertiary                    // vermLit
readonly property color beadMid  : Qt.darker(Colors.tertiary, 1.12)   // verm
readonly property color beadEmber: Qt.darker(Colors.tertiary, 1.40)   // flameEmber (edge)
// swirl strokes: Colors.tertiary_container / Qt.lighter(Colors.tertiary,1.2) for flameBurn / flameTip
// specular highlight stays a warm near-white: rgba(255,246,240,0.6)
```
**The bead runs on `Colors.tertiary`, deliberately off the `Colors.primary` used by the
pill body / workspace stick / active accents.** In Material 3, tertiary is the contrasting
accent matugen extracts, so the bead reads as a distinct glowing ember that pops against a
cool wallpaper instead of blending into the primary-tinted UI around it. Keep the specular
white — it's what sells the glass look. Everything else in `Ame.qml` (geometry, timeline,
phases) stays byte-for-byte.

### A.8 The workspace row the `soul` bead sits under
(Full workspace widget is in the Hyprland addendum §A.4.) For the bead specifically: the
active workspace is a **wider filled "stick"** in `Colors.primary`; inactive are small dim
dots in `Colors.on_surface_variant`. The bead hovers **below** the active stick and flies
along the row as you hover other dots (`soulTarget = "ws"`, `soulWsIndex = index`), then to
a status icon if you move right. Active-stick width animates on `Motion.fast` (140 ms).

### A.9 Constants to copy verbatim (from `Singletons/Motion.qml`)
```
mult = reduceMotion ? 0.4 : 1
fast=140  standard=300  morph=420  shapeshift=820  glide=260  heat=1100   (×mult)
morphCurve = cubic-bezier(0.16, 1, 0.3, 1)        // easeMorph = BezierSpline
Ame internals: pAntic=0.146  pFly=0.658  flightThreshold=30·s  restR=5·s
  remnant fade=350ms OutCubic   quickFlight=460ms   splash angles=[-2.35,-1.57,-0.79]
```

---

## PART B — Paste into Claude Code

```
IMPORTANT FOR ALL AGENTS: the full reference repo is on disk at ~/Ricelin (and the second
reference at ~/shell if present). Read the REAL source directly rather than working from
the spec's paraphrase — the spec tells you what to read and why; the files tell you the
exact values. Especially: ~/Ricelin/configs/quickshell/pill/{Ame,Pill,Workspaces,
Calendar,PillSurface}.qml and pill/Singletons/Motion.qml.

Add this sub-agent to the astralis build. DEPENDS ON Agent D (pill-engine) and the Hyprland
bridge (workspaces) existing; run after them, parallel with surfaces. Run on Claude Fable 5
(model: claude-fable-5) — it's the pill's signature animation. Stop for my verification.

Agent J — "soul-bead": [model: claude-fable-5]
  Port the Ame soul bead — ONE glowing shapeshifting bead, the shell's only glowing element.
  Read astralis-ame-soulbead-addendum.md Part A, then PORT ~/Ricelin/configs/quickshell/
  pill/Ame.qml NEAR-VERBATIM. The only changes:
    1. Replace the Theme.verm/vermLit/flameInk/flameEmber/flameTip/flameBurn constants with
       matugen tokens (addendum A.7). The bead runs on Colors.TERTIARY, deliberately off the
       Colors.primary used by the pill body and workspace stick, so it reads as a distinct
       glowing ember: gradient core→edge = Qt.lighter(Colors.tertiary,1.35) → Colors.tertiary
       → Qt.darker(Colors.tertiary,1.12) → Qt.darker(Colors.tertiary,1.40); swirl strokes
       from Colors.tertiary_container / Qt.lighter(Colors.tertiary,1.2); keep the warm-white
       specular. Read all durations from the Motion singleton (shapeshift=820, glide=260,
       fast=140, mult).
    2. Wire it in Pill.qml exactly as ~/Ricelin does (addendum A.2/A.4): form/point driven
       from ameSurface (each surface exports ameForm+amePoint) else hover soulPoint / wake.
    3. Implement the sticky soulTarget + soulWsIndex hover retargeting on every status icon
       and workspace dot (A.4), and the Qt.callLater(decide) coalescing (A.5) — port these
       verbatim; they are why the bead never teleports.
    4. Keep the perf gating (A.6): FrameAnimation only while busy, 12fps idle swirl / 30fps
       caret blink, layer FBO only while visible||busy.
  Surface anchors: Calendar exports ameForm "ring" at today's cell; Launcher "caret" in the
  search row; Media "seam" at the progress seam; Mixer/Power/Link "dock". Power adds heat
  (holdProgress) + wickDir up.

  VERIFY: hover the pill → bead wakes under the active workspace dot; hover another dot or a
  status icon → bead FLIES there on an arc with a tapered streak + splash landing, and bends
  its path if the pill is still morphing; open the calendar → bead becomes a ring around
  today; open the launcher → bead becomes a blinking caret in the search field; play media →
  bead sits at the progress seam; the bead recolors with the wallpaper (matugen); idle CPU/
  GPU stays low (no full-rate repaint at rest).
```

---

### Notes for you
- The bead is mapped to **`Colors.tertiary`** — matugen's contrasting accent — so it glows
  as a distinct ember rather than blending into the `Colors.primary` pill/workspace accents.
  On some wallpapers tertiary lands close to primary (matugen derives both from the same
  image); if a given wall makes the bead too similar to the UI, the `scheme` knob in
  `matugen/config.toml` (`expressive` / `vibrant` widen the hue spread) or bumping the
  `Qt.lighter` factor on `beadCore` restores the separation.
- The bead depends on the **workspace row** and each **surface's `amePoint` export**, so
  Agent J genuinely needs D + the surfaces + the Hyprland workspace widget in place first —
  slot it late. Everything it needs is already on disk at `~/Ricelin`.
