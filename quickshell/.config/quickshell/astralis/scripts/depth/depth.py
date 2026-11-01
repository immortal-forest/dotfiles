#!/usr/bin/env python3
"""astralis — wallpaper depth cut-out (services/WallpaperDepth.qml).

Estimates relative depth of the wallpaper with Depth Anything V2 Small (ONNX),
refines it against the image with a guided filter, thresholds it with a soft
feather, and writes the wallpaper's FOREGROUND as an RGBA PNG: the scene in
front of the cutoff, transparent behind it. The desktop clock draws between the
real wallpaper and this cut-out, so near objects pass in front of it.

The cut-out is pre-cropped and scaled to the screen exactly like skwd-paper's
`fill` (centred cover crop), so the shell just stretches it over the screen.

Same idea as Noctalia's wallpaper_depth plugin (threshold 0..1, lower = more
of the scene in front; feather = soft band width).

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
VERSION = 1   # bump to invalidate cut-outs when the pipeline changes


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:24]


def box(v, r):
    """Mean over a (2r+1)² window via an integral image, edge-padded."""
    p = np.pad(v, r, mode="edge")
    s = np.pad(p, ((1, 0), (1, 0))).cumsum(0, dtype=np.float64).cumsum(1)
    d = 2 * r + 1
    return ((s[d:, d:] - s[:-d, d:] - s[d:, :-d] + s[:-d, :-d]) / (d * d)).astype(np.float32)


def guided(guide, src, r=8, eps=1e-3):
    """He et al. guided filter: snaps the coarse depth to the image's edges."""
    mg, ms = box(guide, r), box(src, r)
    var = box(guide * guide, r) - mg * mg
    cov = box(guide * src, r) - mg * ms
    a = cov / (var + eps)
    b = ms - a * mg
    return np.clip(box(a, r) * guide + box(b, r), 0, 1)


def smoothstep(v, lo, hi):
    if hi <= lo:
        return (v >= hi).astype(np.float32)
    t = np.clip((v - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


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

        # Refine at ≤1920 px on the long side (guided filter is O(pixels)).
        k = min(1.0, 1920 / max(W, H))
        rw, rh = max(1, round(W * k)), max(1, round(H * k))
        guide = np.asarray(shown.convert("L").resize((rw, rh), Image.Resampling.BILINEAR), np.float32) / 255
        coarse = np.asarray(Image.fromarray(depth).resize((rw, rh), Image.Resampling.BICUBIC, box=dbox), np.float32)
        fine = guided(guide, coarse)
        alpha = smoothstep(fine, thr - fea / 2, thr + fea / 2)
        a8 = Image.fromarray(np.rint(alpha * 255).astype(np.uint8))
        if (rw, rh) != (W, H):
            a8 = a8.resize((W, H), Image.Resampling.BICUBIC)

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
