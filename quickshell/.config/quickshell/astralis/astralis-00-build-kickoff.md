# ASTRALIS — Build Kickoff Prompt (paste this first into Claude Code)

> Paste the fenced block below into Claude Code, run from `~/.config`. It frames the whole
> build: study the reference repos that are physically on disk, reproduce their feel
> faithfully, but produce **my own** shell (matugen M3, my layout) — not a fork of someone
> else's personal dotfiles.

```
You are building "astralis" — MY OWN Quickshell dynamic-island rice for Hyprland. This is
not a fork and not a copy: it's my own shell that reproduces the FEEL and MECHANICS of a
reference implementation while being re-themed, re-structured, and extended to my design.

═══ REFERENCE REPOS ARE ON DISK — READ THE REAL SOURCE ═══
  ~/Ricelin   — the morphing pill + the Ame soul bead. THE primary reference. Hand-written
                Quickshell. Study its actual QML under ~/Ricelin/configs/quickshell/pill/
                and ~/Ricelin/configs/hypr/.
  ~/shell     — (dhrruvsharma, if present) matugen→quickshell live color pipeline, the
                full-screen Canvas music visualizer, and the swww+matugen wallpaper changer.

Do NOT work from memory or from the spec's paraphrase when the real file is right there.
For every component: OPEN THE REFERENCE FILE FIRST, understand exactly how it works, then
write my version. The spec tells you WHAT to read and WHY; the files give you the exact
numbers that make it feel right.

═══ MY SPEC KIT (read all of these before starting) ═══
  astralis-quickshell-rice-spec.md          — architecture, layout, implementation, agents
  astralis-notifications-addendum.md         — Agent I (toasts-as-pill-mode + center)
  astralis-hypr-integration-addendum.md      — replaces Agent H (the pill↔compositor bridge)
  astralis-ame-soulbead-addendum.md          — Agent J (the shapeshifting glowing bead)

═══ WHAT "MY OWN VERSION" MEANS — THE FIDELITY CONTRACT ═══
PORT NEAR-VERBATIM (the feel lives in the exact numbers — match them, change only colors):
  • The pill morph engine: mode→geometry, the surfaces descriptor map, morphCloseness,
    the width/height/radius Behaviors, latch-once Loaders. (~/Ricelin pill/Pill.qml, shell.qml)
  • Ame.qml — the soul bead's entire canvas timeline (anticipation→flight→splash→settle,
    glide, thresholds, the Qt.callLater(decide) coalescing). Port it line-for-line.
  • The Motion constants (shapeshift=820, morph=420, glide=260, fast=140, morphCurve
    0.16,1,0.3,1). (~/Ricelin pill/Singletons/Motion.qml)
  • The event-driven Hyprland refresh whitelist, workspace-rules sourcing, fullscreen retract.

REBUILD AS MINE (do NOT copy — replace/restructure):
  • Theming: Ricelin hardcodes a vermilion Theme.qml + wallust. RIP IT OUT. All color comes
    from a matugen Colors.qml singleton (M3 tokens, live FileView reload). No hardcoded hex,
    no vermilion anywhere. The Ame bead runs on Colors.TERTIARY (distinct ember), the pill
    body/workspace stick/accents on Colors.primary. Colors animate via Behavior on color so
    a wallpaper change re-themes the whole shell live.
  • Directory layout: use the astralis qmldir-module layout from the spec (colors/, config/,
    services/, pill/, modules/, …). Don't mirror Ricelin's file tree.
  • Integrate the ~/shell pieces as mine: the full-screen Canvas visualizer (WlrLayer.Bottom,
    matugen gradient) and the swww+matugen wallpaper carousel + setwall retheme.
  • Add notifications (toasts as a pill `toast` mode + a center surface) — my addendum.

LEAVE BEHIND (Ricelin's personal baggage — do not pull any of this in):
  its KDE theming, brave-theme, SDDM/grub/fastfetch/fish configs, wallust, the vermilion
  palette, and any hardcoded personal paths. Take the shell mechanics, leave the dotfiles.

═══ GROUND RULES ═══
  • Target: Arch, Hyprland 0.55 (Lua config), Quickshell (release), Qt6, matugen, swww, cava,
    playerctl, NVIDIA RTX 4070 (Wayland env per spec 3.1).
  • Every color ← Colors singleton. Every duration/curve ← Motion singleton. One reduce-motion
    knob (Motion.mult).
  • Name the shell config `astralis` and keep `-c astralis` consistent across `qs` launch,
    `qs -c astralis ipc call …` scripts, and the Hyprland `layerrule` namespace.
  • Build in stages using sub-agents per the spec's orchestration (A+B → C → D → {E,F,G,I in
    parallel} → hypr-bridge → J last). Honor the per-agent model tags (claude-fable-5 on
    core-shell, pill-engine, pill-surfaces, wallpaper, hypr-bridge, soul-bead).
  • After each stage, give me a `qs` command to verify it and STOP for my confirmation before
    continuing. This is feel-driven — do not gold-plate before the core morph feels right.
  • When you port something, say which reference file you read and what you changed (colors/
    layout) vs. kept (mechanics), so I can diff the behavior against ~/Ricelin running.

Start by reading the spec kit and ~/Ricelin/configs/quickshell/pill/{shell,Pill,Ame}.qml and
Singletons/Motion.qml, then give me your staged build plan (agents, order, models) for my
sign-off before writing any code.
```

---

### How to use it
1. Have the four spec files and both repos where Claude Code can read them (repos at
   `~/Ricelin` and optionally `~/shell`; spec files in `~/.config` or wherever you run `claude`).
2. Paste the block. It ends by asking CC to **read first and hand you a staged plan for
   sign-off** — so you get a checkpoint before it writes anything.
3. From there it runs the spec's sub-agent orchestration, stopping after each stage for a
   `qs` verify. Keep `~/Ricelin` runnable if you can — the fastest QA is watching your build
   next to the original and matching the motion.
