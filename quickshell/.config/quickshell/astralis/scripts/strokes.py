#!/usr/bin/env python3
"""astralis — pen strokes for the lyrics "write" effect.

argv[1] = text (any characters). Prints JSON {char: {u, w, b, s: [[d, len], ...]}}:
the strokes of each character in writing order as SVG path data, `u` units
per em with the em box's top at y = 0 (baseline at 0.88 em), `w` the glyph's
advance in those units, `b` the strokes' centre-line bounds [x0, y0, x1, y1]
(the widget fits them onto the font's own ink box for that character),
`len` each stroke's length in those units. Characters
with no stroke data are left out (the widget fades the font glyph instead).

Stroke data, read from ~/.local/share/astralis/strokes/:
  kanji / kana / CJK punctuation — KanjiVG (kanjivg.xml.gz), real stroke order.
      KanjiVG © Ulrich Apel, CC BY-SA 3.0, http://kanjivg.tagaini.net
  Latin — a Hershey single-line font (futural.jhf; public domain).
"""
import gzip
import json
import math
import os
import re
import sys
import unicodedata

DATA = os.path.expanduser("~/.local/share/astralis/strokes")
HERSHEY = os.environ.get("ASTRALIS_HERSHEY", "futural")


# ── KanjiVG ────────────────────────────────────────────────────────────────
def kanjivg(chars):
    want = {"%05x" % ord(c): c for c in chars}
    out = {}
    if not want:
        return out
    with gzip.open(os.path.join(DATA, "kanjivg.xml.gz"), "rt", encoding="utf-8") as f:
        xml = f.read()
    for m in re.finditer(r'<kanji id="kvg:kanji_([0-9a-f]{5})">(.*?)</kanji>', xml, re.S):
        c = want.get(m.group(1))
        if c is None:
            continue
        strokes, pts = [], []
        for d in re.findall(r'<path [^>]*?\bd="([^"]+)"', m.group(2)):
            strokes.append([d, path_len(d, pts)])
        if strokes:
            out[c] = {"u": 109, "w": 109, "b": bounds(pts), "s": strokes}
    return out


def bounds(pts):
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return [round(min(xs), 2), round(min(ys), 2), round(max(xs), 2), round(max(ys), 2)]


def path_len(d, pts):
    """Length of an SVG path (M/L/C/S/Z, absolute or relative); appends
    points along it to `pts` (for the bounds)."""
    toks = re.findall(r"[MmLlCcSsZzHhVv]|-?\d*\.?\d+(?:e-?\d+)?", d)
    i, cmd = 0, None
    x = y = sx = sy = 0.0
    lc = None   # last cubic control point (for S)
    total = 0.0

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    def cubic(p0, p1, p2, p3):
        n, L, prev = 16, 0.0, p0
        for k in range(1, n + 1):
            t = k / n
            mt = 1 - t
            q = (mt**3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t**3 * p3[0],
                 mt**3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t**3 * p3[1])
            L += math.dist(prev, q)
            pts.append(q)
            prev = q
        return L

    while i < len(toks):
        if re.match(r"[A-Za-z]", toks[i]):
            cmd = toks[i]
            i += 1
            if cmd in "Zz":
                total += math.dist((x, y), (sx, sy))
                x, y = sx, sy
                continue
        rel = cmd.islower()
        C = cmd.upper()
        if C == "M":
            nx, ny = num(), num()
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            sx, sy = x, y
            pts.append((x, y))
            cmd = "l" if rel else "L"   # further pairs are line-tos
            lc = None
        elif C == "L":
            nx, ny = num(), num()
            n = (x + nx, y + ny) if rel else (nx, ny)
            total += math.dist((x, y), n)
            x, y = n
            pts.append(n)
            lc = None
        elif C == "H":
            v = num()
            n = (x + v if rel else v, y)
            total += math.dist((x, y), n)
            x, y = n
            pts.append(n)
            lc = None
        elif C == "V":
            v = num()
            n = (x, y + v if rel else v)
            total += math.dist((x, y), n)
            x, y = n
            lc = None
        elif C == "C":
            a = [num() for _ in range(6)]
            if rel:
                a = [a[0] + x, a[1] + y, a[2] + x, a[3] + y, a[4] + x, a[5] + y]
            total += cubic((x, y), (a[0], a[1]), (a[2], a[3]), (a[4], a[5]))
            lc = (a[2], a[3])
            x, y = a[4], a[5]
        elif C == "S":
            a = [num() for _ in range(4)]
            if rel:
                a = [a[0] + x, a[1] + y, a[2] + x, a[3] + y]
            c1 = (2 * x - lc[0], 2 * y - lc[1]) if lc else (x, y)
            total += cubic((x, y), c1, (a[0], a[1]), (a[2], a[3]))
            lc = (a[0], a[1])
            x, y = a[2], a[3]
        else:
            i += 1
    return round(total, 2)


# ── Hershey ────────────────────────────────────────────────────────────────
def hershey(chars):
    """Glyphs are stored in ASCII order from 32. Coordinates are letters
    offset from 'R'; ' R' lifts the pen; the first pair is left/right bound."""
    want = {c for c in chars if 33 <= ord(c) <= 126}
    out = {}
    if not want:
        return out
    with open(os.path.join(DATA, HERSHEY + ".jhf"), encoding="ascii", errors="replace") as f:
        raw = f.read().splitlines()
    # Re-join wrapped records: a record starts with a 5-wide id + 3-wide count.
    recs = []
    for line in raw:
        if re.match(r"^[ \d]{5}[ \d]{3}", line) and recs and len(recs[-1]) >= 8 + 2 * int(recs[-1][5:8]):
            recs.append(line)
        elif recs and len(recs[-1]) < 8 + 2 * int(recs[-1][5:8]):
            recs[-1] += line
        else:
            recs.append(line)
    # Units: Hershey caps run y -12..9 (21 high); map to a 100-unit em with the
    # cap height 0.70 em and the baseline at 0.88 em.
    k = 70 / 21
    for idx, rec in enumerate(recs):
        c = chr(32 + idx)
        if c not in want:
            continue
        body = rec[8:]
        L, R = ord(body[0]) - 82, ord(body[1]) - 82
        strokes, cur = [], []
        for j in range(2, len(body) - 1, 2):
            pair = body[j:j + 2]
            if pair == " R":
                if len(cur) > 1:
                    strokes.append(cur)
                cur = []
                continue
            px = (ord(pair[0]) - 82 - L) * k
            py = 88 + (ord(pair[1]) - 82 - 9) * k
            cur.append((round(px, 2), round(py, 2)))
        if len(cur) > 1:
            strokes.append(cur)
        s, allp = [], [p for st in strokes for p in st]
        for pts in strokes:
            d = "M%g,%g" % pts[0] + "".join(" L%g,%g" % p for p in pts[1:])
            s.append([d, round(sum(math.dist(pts[n], pts[n + 1]) for n in range(len(pts) - 1)), 2)])
        if s:
            out[c] = {"u": 100, "w": round((R - L) * k, 2), "b": bounds(allp), "s": s}
    return out


def main():
    text = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
    chars = {c for c in text if not c.isspace()}
    # Full-width Latin / digits → their ASCII strokes.
    norm = {c: unicodedata.normalize("NFKC", c) for c in chars}
    latin = {c for c in chars if len(norm[c]) == 1 and 33 <= ord(norm[c]) <= 126}
    # Latin punctuation is too small to read as strokes and Hershey's shapes
    # (curly quotes) don't match the UI font's: left out, so it fades in.
    skip = {c for c in latin if unicodedata.category(norm[c])[0] in "PS"}
    latin -= skip
    chars -= skip
    out = {}
    h = hershey({norm[c] for c in latin})
    for c in latin:
        if norm[c] in h:
            out[c] = h[norm[c]]
    out.update(kanjivg(chars - latin))
    json.dump(out, sys.stdout, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
