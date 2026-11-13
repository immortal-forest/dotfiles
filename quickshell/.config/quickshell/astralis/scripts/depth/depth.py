#!/usr/bin/env python3
"""astralis — wallpaper depth cut-out (services/WallpaperDepth.qml).

Estimates relative depth of the wallpaper with Depth Anything V2 Small (ONNX)
and writes the wallpaper's FOREGROUND as an RGBA PNG: the scene in front of the
cutoff, transparent behind it. The desktop clock draws between the real
wallpaper and this cut-out, so near objects pass in front of it.

The matte: everything nearer than `threshold` is fully opaque (a depth-space
feather made objects sitting just past the cutoff see-through). The cut line
is then edged in image space. Where it runs along a real occlusion edge (a head
against the sky) the depth jumps, and a colour matte in a thin band decides
alpha from the nearest sure-foreground and sure-background colours, so hair
strands survive and the strands' colour is cleaned of the background. The
colour matte is trusted only where a pixel really is a blend of those two
colours; against a busy background (lanterns, blossoms) the depth cut stands.
Where the scene slides slowly through the cutoff (a curtain, a floor) there is no
edge in the image, so the cut is feathered wide instead; `feather` (0..0.5)
sets that width.

The cut-out is pre-cropped and scaled to the screen exactly like skwd-paper's
`fill` (centred cover crop), so the shell just stretches it over the screen.

Same idea as Noctalia's wallpaper_depth plugin (threshold 0..1, lower = more
of the scene in front).

Prints one JSON line: {"path": ..., "ms": ..., "cached": bool}.
"""

import argparse
import fcntl
import hashlib
import json
import os
import sys
import tempfile
import time
from pathlib import Path

import numpy as np
from PIL import Image

INPUT = 518   # model's native short side
PATCH = 14    # input dims must be multiples of this
VERSION = 3   # bump to invalidate cut-outs when the pipeline changes


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:24]


def box(v, r):
    """Mean over a (2r+1)² window, edge-padded; separable running sums."""
    v = np.asarray(v, np.float32)
    if r <= 0:
        return v
    d = 2 * r + 1
    h, w = v.shape
    c = np.pad(v, ((r + 1, r), (0, 0)), mode="edge").cumsum(0)
    v = c[d:d + h] - c[:h]
    c = np.pad(v, ((0, 0), (r + 1, r)), mode="edge").cumsum(1)
    return (c[:, d:d + w] - c[:, :w]) / (d * d)


def blur(v, r):
    """Three box passes ≈ a gaussian of sigma ≈ r."""
    return box(box(box(v, r), r), r) if r > 0 else np.asarray(v, np.float32)


def smoothstep(v, lo, hi):
    t = np.clip((v - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def dilate(m, r):
    return box(m, r) > 1e-4


def erode(m, r):
    return box(m, r) > 1 - 1e-4


def guided(I, p, r, eps):
    """He et al. guided filter with a colour guide: snaps p to the image's edges."""
    m = [box(I[..., c], r) for c in range(3)]
    mp = box(p, r)
    cov = [box(I[..., c] * p, r) - m[c] * mp for c in range(3)]
    v = {(i, j): box(I[..., i] * I[..., j], r) - m[i] * m[j] + (eps if i == j else 0)
         for i in range(3) for j in range(i, 3)}
    a11, a12, a13, a22, a23, a33 = v[0, 0], v[0, 1], v[0, 2], v[1, 1], v[1, 2], v[2, 2]
    c11, c12, c13 = a22 * a33 - a23 * a23, a13 * a23 - a12 * a33, a12 * a23 - a13 * a22
    c22, c23, c33 = a11 * a33 - a13 * a13, a12 * a13 - a11 * a23, a11 * a22 - a12 * a12
    det = a11 * c11 + a12 * c12 + a13 * c13
    det = np.where(np.abs(det) < 1e-12, 1e-12, det)
    a0 = (c11 * cov[0] + c12 * cov[1] + c13 * cov[2]) / det
    a1 = (c12 * cov[0] + c22 * cov[1] + c23 * cov[2]) / det
    a2 = (c13 * cov[0] + c23 * cov[1] + c33 * cov[2]) / det
    b = mp - a0 * m[0] - a1 * m[1] - a2 * m[2]
    return np.clip(box(a0, r) * I[..., 0] + box(a1, r) * I[..., 1] + box(a2, r) * I[..., 2] + box(b, r), 0, 1)


def spread(I, known, reach):
    """Each pixel within `reach` of `known` gets the colour of the nearest known
    pixels (grown outward ring by ring). Runs at half resolution: it only has to
    tell hair from sky, not resolve them."""
    h, w = known.shape
    Ih = I[: h // 2 * 2, : w // 2 * 2].reshape(h // 2, 2, w // 2, 2, 3).mean((1, 3))
    K = known[: h // 2 * 2, : w // 2 * 2].reshape(h // 2, 2, w // 2, 2).all((1, 3)).astype(np.float32)
    C = Ih * K[..., None]
    for _ in range(int(np.ceil(reach / 2 / 2)) + 1):
        Kb = box(K, 2)
        grow = (K == 0) & (Kb > 1e-6)
        if not grow.any():
            break
        for c in range(3):
            C[..., c] = np.where(grow, box(C[..., c], 2) / np.maximum(Kb, 1e-6), C[..., c])
        K = np.where(grow, 1, K).astype(np.float32)

    def up(x):
        return np.asarray(Image.fromarray(x).resize((w, h), Image.Resampling.BILINEAR), np.float32)

    return np.stack([up(C[..., c]) for c in range(3)], -1), up(K) > 0.999


def matte(I, depth, thr, fea):
    """Alpha (0..1) of the scene in front of `thr`; returns (alpha, nearest bg colour)."""
    h, w = depth.shape
    short = min(w, h)
    hard = depth > thr
    rs = max(1, round(short * 0.003))
    hard = erode(dilate(dilate(erode(hard, rs), rs), rs), rs)   # open + close: no specks, no pinholes
    hf = hard.astype(np.float32)
    b = max(3, round(short * 0.012))         # colour-matte band half-width
    rw = round(fea * short * 0.12)           # wide feather for slow depth ramps
    # Occlusion edge vs slow ramp: the depth gradient on the cut line (per
    # screen short side) is ≥7 at real edges and ≤1 where the scene slides
    # through the cutoff. Seed on the steep stretches, grow over the feather.
    gy, gx = np.gradient(depth)
    steep = (hard ^ erode(hard, 1)) & (np.hypot(gx, gy) * short > 3)
    sharp = blur(dilate(steep, 3 * rw + 2 * b), max(1, b // 2))
    fg, bg = erode(hard, b), erode(~hard, b)
    band = ~fg & ~bg
    F, fk = spread(I, fg, 2 * b)
    B, bk = spread(I, bg, 2 * b)
    d = F - B
    n2 = (d * d).sum(-1)
    au = np.clip(((I - B) * d).sum(-1) / (n2 + 1e-4), 0, 1)
    # Trust the colour model only where it explains the pixel: fg and bg colours
    # well apart, and the pixel actually a blend of the two (busy backgrounds —
    # lanterns, blossoms — are not, and would turn the edge into mottle).
    res = np.sqrt(((I - (au[..., None] * F + (1 - au[..., None]) * B)) ** 2).sum(-1))
    conf = smoothstep(np.sqrt(n2), 0.12, 0.3) * np.clip(1 - res / 0.08, 0, 1) * fk * bk
    conf = blur(conf, max(1, b // 4))
    crisp = np.where(band, conf * au + (1 - conf) * blur(hf, max(1, b // 6)), hf)
    crisp = np.where(band, guided(I, crisp, max(1, round(short * 0.002)), 1e-4), crisp)
    a = sharp * crisp + (1 - sharp) * blur(hf, rw)
    return np.clip(a, 0, 1).astype(np.float32), B


def infer(model: Path, rgb: Image.Image) -> np.ndarray:
    import onnxruntime as ort

    w, h = rgb.size
    k = max(INPUT / w, INPUT / h)
    mw = max(INPUT, round(w * k / PATCH) * PATCH)
    mh = max(INPUT, round(h * k / PATCH) * PATCH)
    x = np.asarray(rgb.resize((mw, mh), Image.Resampling.BICUBIC), np.float32) / 255
    x = (x - [0.485, 0.456, 0.406]) / [0.229, 0.224, 0.225]
    x = np.transpose(x, (2, 0, 1))[None].astype(np.float32)
    opts = ort.SessionOptions()
    opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    sess = ort.InferenceSession(str(model), opts, providers=["CPUExecutionProvider"])
    d = np.asarray(sess.run(None, {sess.get_inputs()[0].name: x})[0], np.float32).squeeze()
    lo, hi = float(d.min()), float(d.max())
    if not np.isfinite(lo) or hi <= lo:
        raise RuntimeError("model returned an invalid depth map")
    return (d - lo) / (hi - lo)   # relative inverse depth: 1 = nearest


def cover_box(w, h, W, H):
    """Source rectangle a centred cover-crop of (w,h) into (W,H) shows."""
    k = max(W / w, H / h)
    cw, ch = W / k, H / k
    l, t = (w - cw) / 2, (h - ch) / 2
    return (l, t, l + cw, t + ch)


def prune(d: Path, keep: int):
    files = sorted((p for p in d.iterdir() if p.is_file()), key=lambda p: p.stat().st_mtime, reverse=True)
    for p in files[keep:]:
        p.unlink(missing_ok=True)


def atomic_save(img: Image.Image, path: Path):
    with tempfile.NamedTemporaryFile("wb", dir=path.parent, suffix=".png", delete=False) as f:
        img.save(f, format="PNG", compress_level=1)
    os.replace(f.name, path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", type=Path, required=True)
    ap.add_argument("--wallpaper", type=Path, required=True)
    ap.add_argument("--threshold", type=float, default=0.30)
    ap.add_argument("--feather", type=float, default=0.08)
    ap.add_argument("--size", required=True, help="screen size in physical px, WxH")
    a = ap.parse_args()

    t0 = time.monotonic()
    W, H = (int(n) for n in a.size.lower().split("x"))
    thr = min(1.0, max(0.0, a.threshold))
    fea = min(0.5, max(0.0, a.feather))
    model = a.data_dir / "model.onnx"
    if not a.wallpaper.is_file():
        raise RuntimeError(f"wallpaper missing: {a.wallpaper}")
    if not model.is_file():
        raise RuntimeError("model missing — run scripts/depth/setup")

    key = sha(a.wallpaper)
    ddir = a.data_dir / "cache" / "depth"
    cdir = a.data_dir / "cache" / "cutout"
    ddir.mkdir(parents=True, exist_ok=True)
    cdir.mkdir(parents=True, exist_ok=True)
    dpath = ddir / f"{key}.npy"
    out = cdir / f"{key}-v{VERSION}-t{thr:.3f}-f{fea:.3f}-{W}x{H}.png"

    with (a.data_dir / "cache" / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if out.is_file():
            out.touch()
            print(json.dumps({"path": str(out), "ms": round((time.monotonic() - t0) * 1000), "cached": True}))
            return 0

        with Image.open(a.wallpaper) as im:
            rgb = im.convert("RGB")
        w, h = rgb.size

        depth = np.load(dpath) if dpath.is_file() else None
        if depth is None:
            depth = infer(model, rgb)
            with tempfile.NamedTemporaryFile("wb", dir=ddir, delete=False) as f:
                np.save(f, depth)
            os.replace(f.name, dpath)

        # Crop + scale to the screen exactly as the wallpaper is shown.
        boxf = cover_box(w, h, W, H)
        shown = rgb.resize((W, H), Image.Resampling.LANCZOS, box=boxf)
        dh, dw = depth.shape
        sx, sy = dw / w, dh / h
        dbox = (boxf[0] * sx, boxf[1] * sy, boxf[2] * sx, boxf[3] * sy)

        # Matte at the source crop's own resolution (no detail beyond it),
        # capped by the screen and at 2048 px on the long side.
        cw, ch = boxf[2] - boxf[0], boxf[3] - boxf[1]
        k = min(1.0, W / cw, 2048 / max(cw, ch))
        rw, rh = max(1, round(cw * k)), max(1, round(ch * k))
        I = np.asarray(rgb.resize((rw, rh), Image.Resampling.LANCZOS, box=boxf), np.float32) / 255
        coarse = np.asarray(Image.fromarray(depth).resize((rw, rh), Image.Resampling.BICUBIC, box=dbox), np.float32)
        alpha, B = matte(I, coarse, thr, fea)

        def up(x):
            return np.asarray(Image.fromarray(np.ascontiguousarray(x)).resize((W, H), Image.Resampling.BICUBIC), np.float32)

        A = np.clip(up(alpha), 0, 1)
        # Decontaminate the soft edge: take the background behind a pixel out of
        # its colour, so thin strands over the clock read as hair, not as grey
        # ghosts of the sky. Strongest where most transparent and capped, as an
        # underestimated alpha would otherwise over-saturate lit edges.
        S = np.asarray(shown, np.float32) / 255
        part = (A > 0.01) & (A < 0.99)
        for c in range(3):
            fc = (S[..., c] - (1 - A) * up(B[..., c])) / np.maximum(A, 0.01)
            fix = np.clip((fc - S[..., c]) * (1 - A), -0.2, 0.2)
            S[..., c] = np.where(part, np.clip(S[..., c] + fix, 0, 1), S[..., c])
        shown = Image.fromarray(np.rint(S * 255).astype(np.uint8))
        a8 = Image.fromarray(np.rint(A * 255).astype(np.uint8))
        shown.putalpha(a8)
        atomic_save(shown, out)
        prune(ddir, 16)
        prune(cdir, 24)

    print(json.dumps({"path": str(out), "ms": round((time.monotonic() - t0) * 1000), "cached": False}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
