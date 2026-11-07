#!/usr/bin/env python3
# astralis — romanize lyric lines for the lyrics widget.
# Usage: romanize.py "<lines joined by \n>"  → exactly one romanized line per input line.
# Japanese (any kana present) needs kakasi (pacman -S kakasi). kakasi works in
# EUC-JP, so anything outside JIS X 0208 (é, ～, ¥, emoji, hangul, Chinese-only
# hanzi) comes out as "??"/"(kigou)" or even eats a newline. So only runs of
# JIS kana/kanji go to kakasi; everything else goes through ICU's uconv.
# Exit 3 = Japanese but kakasi missing.
import re, shutil, subprocess, sys

lines = (sys.argv[1] if len(sys.argv) > 1 else "").split("\n")
KANA = re.compile(r"[぀-ヿ]")
UCONV = "Any-Latin; Fullwidth-Halfwidth; NFC"
PUNCT = str.maketrans({"。": ". ", "、": ", ", "・": " ", "「": " ", "」": " ", "『": " ",
                       "』": " ", "【": " ", "】": " ", "〜": "~", "～": "~", "　": " "})


def run(cmd, items):
    """One process for all items (one per line); None if the count comes back wrong."""
    if not items:
        return []
    out = subprocess.run(cmd, input="\n".join(items) + "\n", capture_output=True,
                         text=True).stdout.rstrip("\n").split("\n")
    return out if len(out) == len(items) else None


def uconv(items):
    res = run(["uconv", "-x", UCONV], items)
    return res if res is not None else [x for x in items]


if not any(KANA.search(l) for l in lines):
    print("\n".join(uconv(lines)))
    sys.exit(0)
if not shutil.which("kakasi"):
    sys.exit(3)


def japanese(c):
    o = ord(c)
    if not (0x3040 <= o <= 0x30ff or 0x3400 <= o <= 0x4dbf or 0x4e00 <= o <= 0x9fff
            or c in "々〆ヶ"):
        return False
    try:
        c.encode("euc_jp")
        return True
    except UnicodeEncodeError:
        return False


# Split every line into (is_japanese, text) runs.
segs = []
for l in lines:
    s = []
    for c in l:
        j = japanese(c)
        if s and s[-1][0] == j:
            s[-1][1] += c
        else:
            s.append([j, c])
    segs.append(s)

jp = [t for s in segs for j, t in s if j]
other = [t.translate(PUNCT) for s in segs for j, t in s if not j]
KAKASI = ["kakasi", "-i", "utf8", "-o", "utf8", "-Ja", "-Ha", "-Ka", "-Ea", "-s"]
jr = run(KAKASI, jp)
if jr is None:  # never expected now, but stay line-exact: one call per run
    jr = [(run(KAKASI, [t]) or [t])[0] for t in jp]
orr = uconv(other)

ji = oi = 0
out = []
for s in segs:
    line = ""
    for j, _ in s:
        if j:
            piece = jr[ji]; ji += 1
        else:
            piece = orr[oi]; oi += 1
        # "する間にMoney" → "suru aida ni Money", not "...niMoney"
        if line and piece and line[-1].isalnum() and piece[0].isalnum():
            line += " "
        line += piece
    out.append(re.sub(r"\s+", " ", line).strip())
print("\n".join(out))
