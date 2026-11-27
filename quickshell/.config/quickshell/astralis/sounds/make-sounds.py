#!/usr/bin/env python3
"""astralis notification sounds — synthesised, so they can be tuned and remade.

  chime.oga   a 風鈴 (wind bell): two glass strikes a fifth apart, D6 → A6,
              with a soft clapper tick and a short airy tail
  urgent.oga  two descending pairs a minor third apart (A5 → F♯5), lower and
              rounder — asks for attention without a buzzer
  soft.oga    one quiet strike, for low-urgency notifications

The glass timbre is the inharmonic partial set of a free bar / small bell
(1, 2.76, 5.40, 8.93), each partial slightly detuned against itself so it
shimmers, higher partials dying faster. Plain Python, no numpy; ffmpeg
encodes to Ogg Vorbis. Run it from anywhere:  python3 sounds/make-sounds.py
"""

import math
import os
import random
import struct
import subprocess
import tempfile
import wave

SR = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
GLASS = [(1.0, 1.0), (2.76, 0.30), (5.40, 0.13), (8.93, 0.05)]
ROUND = [(1.0, 1.0), (2.0, 0.22), (2.76, 0.12), (5.40, 0.04)]


def strike(buf, t0, f0, amp, tau, partials, tick=0.04, seed=1):
    """Add one struck bell at t0 seconds."""
    rnd = random.Random(seed)
    start = int(t0 * SR)
    attack = int(0.003 * SR)
    for ratio, rel in partials:
        f = f0 * ratio
        t_p = tau / (ratio ** 0.75)
        n = min(len(buf) - start, int(t_p * 7 * SR))
        det = 0.6 * ratio            # Hz between the two voices: the shimmer
        # in phase at the strike: the two voices only drift apart slowly, so
        # the note swells gently instead of dipping right after the hit
        ph1 = ph2 = rnd.random() * 6.28
        w1 = 2 * math.pi * (f - det / 2) / SR
        w2 = 2 * math.pi * (f + det / 2) / SR
        a = amp * rel * 0.5
        for i in range(n):
            env = math.exp(-i / (t_p * SR))
            if i < attack:
                env *= 0.5 - 0.5 * math.cos(math.pi * i / attack)
            buf[start + i] += a * env * (math.sin(ph1 + w1 * i) + math.sin(ph2 + w2 * i))
    # the clapper: a few ms of bright, quickly-dying noise
    hp = 0.0
    last = 0.0
    for i in range(int(0.006 * SR)):
        x = rnd.uniform(-1, 1)
        hp = 0.85 * (hp + x - last)
        last = x
        buf[start + i] += tick * amp * hp * math.exp(-i / (0.0012 * SR))


def air(buf, mix):
    """A small Schroeder room: space around the bell, not an echo."""
    def comb(x, d, g):
        y = [0.0] * len(x)
        for i in range(len(x)):
            y[i] = x[i] + (g * y[i - d] if i >= d else 0.0)
        return y

    def allpass(x, d, g):
        y = [0.0] * len(x)
        for i in range(len(x)):
            xd = x[i - d] if i >= d else 0.0
            yd = y[i - d] if i >= d else 0.0
            y[i] = -g * x[i] + xd + g * yd
        return y

    wet = [0.0] * len(buf)
    for d, g in ((1557, 0.62), (1617, 0.60), (1491, 0.63), (1422, 0.61)):
        c = comb(buf, d, g)
        for i in range(len(buf)):
            wet[i] += c[i] * 0.25
    wet = allpass(allpass(wet, 225, 0.5), 556, 0.5)
    return [(1 - mix) * a + mix * b for a, b in zip(buf, wet)]


def finish(buf, peak):
    # gentle fade at the very end, normalise
    fade = int(0.08 * SR)
    for i in range(fade):
        buf[-1 - i] *= i / fade
    m = max(abs(v) for v in buf) or 1
    return [v * peak / m for v in buf]


def write(name, buf):
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()
    with wave.open(tmp.name, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in buf))
    out = os.path.join(HERE, name)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp.name,
                    "-c:a", "libvorbis", "-q:a", "6", out], check=True)
    os.unlink(tmp.name)
    print("wrote", out)


def chime():
    buf = [0.0] * int(1.25 * SR)
    strike(buf, 0.000, 1174.66, 0.85, 0.36, GLASS, seed=3)   # D6
    strike(buf, 0.095, 1760.00, 0.62, 0.32, GLASS, seed=7)   # A6
    return finish(air(buf, 0.16), 0.32)


def urgent():
    buf = [0.0] * int(1.35 * SR)
    for k, t in enumerate((0.0, 0.40)):
        strike(buf, t, 880.00, 0.9, 0.28, ROUND, tick=0.03, seed=11 + k)          # A5
        strike(buf, t + 0.12, 739.99, 0.8, 0.32, ROUND, tick=0.03, seed=21 + k)   # F#5
    return finish(air(buf, 0.12), 0.44)


def soft():
    buf = [0.0] * int(0.8 * SR)
    strike(buf, 0.0, 1318.51, 0.6, 0.26, GLASS, tick=0.025, seed=5)   # E6
    return finish(air(buf, 0.14), 0.28)


if __name__ == "__main__":
    write("chime.oga", chime())
    write("urgent.oga", urgent())
    write("soft.oga", soft())
