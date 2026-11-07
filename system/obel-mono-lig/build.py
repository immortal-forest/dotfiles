"""Add programming ligatures to Obel Mono (variable TTF) -> "Obel Mono Lig".

Technique (as Fira Code / JetBrains Mono): every char but the last becomes an
empty one-cell spacer; the last becomes a glyph that draws back over the earlier
cells. Cell widths never change, so the terminal grid stays intact.

Every ligature is a plain outline built from Obel's own glyphs and positioned
separately at each master (Thin / Regular / Black), so it follows the font's
design at every weight:
  * footprint  - a ligature starts where its first typed char starts and ends
                 where its last typed char ends (`->` spans `-`.xMin .. `>`.xMax)
  * math axis  - operators centre on the hyphen's centre line, like `- = < >`
  * shapes     - arrows/bars are Obel's own long arrows and bars, lengthened by
                 moving their end points (strokes and heads keep their drawing)
  * spacing    - `::` pulls the colons to 0.6 of a cell
  * italic     - vertical moves carry the italic slant
usage: build.py in.ttf out.ttf
"""
import sys, math, copy
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphCoordinates
from fontTools.ttLib.tables import ttProgram
from fontTools.ttLib.tables.TupleVariation import TupleVariation
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

CELL = 1200
src, dst = sys.argv[1], sys.argv[2]
f = TTFont(src)
glyf, hmtx, gvar = f["glyf"], f["hmtx"], f["gvar"]
cm = f.getBestCmap()
G = lambda ch: cm[ord(ch)]
order = list(f.getGlyphOrder())
SLANT = math.tan(math.radians(-f["post"].italicAngle))  # x per unit y

# ---------- masters ----------
REGIONS = []  # distinct gvar regions (axes dicts); master 0 = default
for tvs in gvar.variations.values():
    for tv in tvs:
        if tv.axes not in REGIONS:
            REGIONS.append(tv.axes)
MASTERS = [None] + REGIONS


def outline(name):
    """(points per master, ends, flags) with IUP-inferred deltas filled in."""
    g = glyf[name]
    assert not g.isComposite(), name
    coords, ends, flags = g.getCoordinates(glyf)
    base = [tuple(p) for p in coords]
    full, ctrl = glyf._getCoordinatesAndControls(name, hmtx.metrics)
    per = [base]
    for reg in REGIONS:
        d = None
        for tv in gvar.variations.get(name, []):
            if tv.axes == reg:
                tv = copy.deepcopy(tv)
                if any(c is None for c in tv.coordinates):
                    tv.calcInferredDeltas(full, ctrl.endPts)
                d = tv.coordinates
        per.append([(x + (d[i][0] if d else 0), y + (d[i][1] if d else 0)) for i, (x, y) in enumerate(base)])
    return per, list(ends), bytearray(flags)


_cache = {}
def O(name):
    if name not in _cache:
        _cache[name] = outline(name)
    return _cache[name]


def bounds(name, m):
    pts = O(name)[0][m]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


AXIS = [(bounds(G("-"), m)[1] + bounds(G("-"), m)[3]) / 2 for m in range(len(MASTERS))]


def mv(p, dx, dy):
    """move a point; vertical moves follow the italic slant"""
    return (p[0] + dx + dy * SLANT, p[1] + dy)


# ---------- pieces: fn(m) -> list of point lists (one per master) ----------
class Piece:
    def __init__(self, name, place):
        self.name, self.place = name, place  # place(m, pts) -> new pts


def split_x(name):
    """x split line closest to the cell centre that no point crosses at any master"""
    per = O(name)[0]
    rng = [(min(per[m][i][0] for m in range(len(per))), max(per[m][i][0] for m in range(len(per))))
           for i in range(len(per[0]))]
    return min((s for s in range(300, 901, 5) if all(not lo <= s <= hi for lo, hi in rng)),
               key=lambda s: abs(s - CELL / 2))


def lengthen(name, n, left_ref, right_ref):
    """Obel's own long shape, left half moved n-1 cells left; left end lands on
    left_ref's xMin, right end on right_ref's xMax, centred on the math axis."""
    mid = split_x(name)
    def place(m, pts):
        L = [p for p in pts if p[0] < mid]; R = [p for p in pts if p[0] >= mid]
        dxl = bounds(left_ref, m)[0] - min(p[0] for p in L) - (n - 1) * CELL
        dxr = bounds(right_ref, m)[2] - max(p[0] for p in R)
        b = bounds(name, m); dy = AXIS[m] - (b[1] + b[3]) / 2
        return [mv(p, dxl if p[0] < mid else dxr, dy) for p in pts]
    return [Piece(name, place)]


def centred(name, n=2, dy_axis=False):
    """glyph unchanged, centred over the n cells"""
    def place(m, pts):
        b = bounds(name, m)
        dx = -(n - 1) * CELL / 2 + (CELL / 2 - (b[0] + b[2]) / 2)
        return [mv(p, dx, 0) for p in pts]
    return [Piece(name, place)]


def widened(name, extra):
    """glyph widened by `extra` units (halves pulled apart at a split no point
    crosses, so strokes keep their drawing), centred over the two cells"""
    mid = split_x(name)
    def place(m, pts):
        b = bounds(name, m)
        c = (b[0] + b[2]) / 2
        return [mv(p, (-extra / 2 if p[0] < mid else extra / 2) - c, 0) for p in pts]
    return [Piece(name, place)]


def dot_pair(pitch_cells=0.6):
    """`::` - two colons pulled together to `pitch_cells` of a cell, centred on the boundary"""
    col = G(":")
    def at(sign):
        def place(m, pts):
            b = bounds(col, m)
            return [mv(p, sign * pitch_cells * CELL / 2 - (b[0] + b[2]) / 2, 0) for p in pts]
        return place
    return [Piece(col, at(-1)), Piece(col, at(+1))]


def bar_chevron(chev, bar_side):
    """`|>` / `<|` - a triangle from the baseline up, centred on the math axis: the
    chevron's arms lengthened along their own angle (strokes keep Obel's weight)
    and Obel's bar cut to the same height, butted against the flat arm ends."""
    bar = G("|")
    def tall_chev(m):
        cp = O(chev)[0][m]
        xs = [p[0] for p in cp]; xmid = (min(xs) + max(xs)) / 2
        is_end = (lambda p: p[0] < xmid) if bar_side == "left" else (lambda p: p[0] > xmid)
        ends = [p for p in cp if is_end(p)]; apex = [p for p in cp if not is_end(p)]
        def arm(pick, target_y):
            # move along this arm's own outer edge (italic arms differ) until it reaches target_y
            tip, ap = pick(ends, key=lambda p: p[1]), pick(apex, key=lambda p: p[1])
            ux, uy = tip[0] - ap[0], tip[1] - ap[1]
            k = (target_y - tip[1]) / uy
            return k * ux, k * uy
        top, bot = arm(max, 2 * AXIS[m]), arm(min, 0)       # baseline up, centred on the axis
        out = []
        for p in cp:
            d = (0, 0) if not is_end(p) else top if p[1] > AXIS[m] else bot
            out.append((p[0] + d[0], p[1] + d[1]))
        return out
    def geometry(m):
        cp = tall_chev(m)
        top = max(cp, key=lambda p: p[1]); bot = min(cp, key=lambda p: p[1])
        bp = O(bar)[0][m]
        midy = (max(p[1] for p in bp) + min(p[1] for p in bp)) / 2
        cut = [mv(p, 0, (top[1] - p[1]) if p[1] > midy else (bot[1] - p[1])) for p in bp]
        tops = [p for p in cut if p[1] > midy]
        corner = max(tops, key=lambda p: p[0]) if bar_side == "left" else min(tops, key=lambda p: p[0])
        cut = [(x + top[0] - corner[0], y) for x, y in cut]
        allx = [p[0] for p in cut + cp]
        shift = -(min(allx) + max(allx)) / 2
        return cut, cp, shift
    def place_bar(m, pts):
        cut, _, shift = geometry(m)
        return [(x + shift, y) for x, y in cut]
    def place_chev(m, pts):
        _, cp, shift = geometry(m)
        return [(x + shift, y) for x, y in cp]
    return [Piece(bar, place_bar), Piece(chev, place_chev)]


# ---------- glyph assembly ----------
def build(pieces):
    pts_m = [[] for _ in MASTERS]
    ends, flags = [], bytearray()
    for pc in pieces:
        per, e, fl = O(pc.name)
        off = len(pts_m[0])
        for m in range(len(MASTERS)):
            pts_m[m] += pc.place(m, per[m])
        ends += [x + off for x in e]
        flags += fl
    g = Glyph()
    g.numberOfContours = len(ends)
    base = [(round(x), round(y)) for x, y in pts_m[0]]
    g.coordinates = GlyphCoordinates(base)
    g.endPtsOfContours = ends
    g.flags = flags
    g.program = ttProgram.Program(); g.program.fromBytecode(b"")
    tvs = []
    for m, reg in enumerate(REGIONS, start=1):
        d = [(round(x) - bx, round(y) - by) for (x, y), (bx, by) in zip(pts_m[m], base)]
        tvs.append(TupleVariation(reg, d + [(0, 0)] * 4))
    return g, tvs


def add_glyph(name, glyph, variations):
    order.append(name)
    f.setGlyphOrder(order)
    glyf.glyphOrder = order
    glyf.glyphs[name] = glyph
    glyph.recalcBounds(glyf)
    hmtx[name] = (CELL, glyph.xMin if glyph.numberOfContours else 0)
    gvar.variations[name] = variations


ligs = []
def lig(chars, name, pieces):
    add_glyph(name, *build(pieces))
    ligs.append((chars, name))


H, GT, LT, EQ = G("-"), G(">"), G("<"), G("=")
# arrows: Obel's long arrows, spanning exactly the typed characters
lig("->",  "hyphen_greater.liga",        lengthen(G("⟶"), 2, H, GT))
lig("-->", "hyphen_hyphen_greater.liga", lengthen(G("⟶"), 3, H, GT))
lig("<-",  "less_hyphen.liga",           lengthen(G("⟵"), 2, LT, H))
lig("<--", "less_hyphen_hyphen.liga",    lengthen(G("⟵"), 3, LT, H))
lig("<->", "less_hyphen_greater.liga",   lengthen(G("⟷"), 3, LT, GT))
lig("=>",  "equal_greater.liga",         lengthen(G("⟹"), 2, EQ, GT))
lig("==>", "equal_equal_greater.liga",   lengthen(G("⟹"), 3, EQ, GT))
lig("<==", "less_equal_equal.liga",      lengthen(G("⟸"), 3, LT, EQ))
lig("<=>", "less_equal_greater.liga",    lengthen(G("⟺"), 3, LT, GT))
# equality: Obel's = and ≡ bars joined across the cells
lig("==",  "equal_equal.liga",           lengthen(EQ, 2, EQ, EQ))
lig("===", "equal_equal_equal.liga",     lengthen(G("≡"), 3, EQ, EQ))
lig("!=",  "exclam_equal.liga",          lengthen(EQ, 2, EQ, EQ) + centred(G("≠")))
# comparison: Obel's own ≥ ≤, widened to sit across both cells
lig(">=",  "greater_equal.liga",         widened(G("≥"), 0.8 * CELL))
lig("<=",  "less_equal.liga",            widened(G("≤"), 0.8 * CELL))
# punctuation
lig("::",  "colon_colon.liga",           dot_pair())
lig("|>",  "bar_greater.liga",           bar_chevron(GT, "left"))
lig("<|",  "less_bar.liga",              bar_chevron(LT, "right"))

for chars, name in ligs:
    for i in range(len(chars) - 1):
        g = Glyph(); g.numberOfContours = 0
        add_glyph(f"{name}.sp{i}", g, [])

hv = f["HVAR"].table
gdef = f["GDEF"].table
for chars, name in ligs:
    for n in [name] + [f"{name}.sp{i}" for i in range(len(chars) - 1)]:
        hv.AdvWidthMap.mapping[n] = hv.AdvWidthMap.mapping["space"]
        if gdef.GlyphClassDef:
            gdef.GlyphClassDef.classDefs[n] = 1

# ---------- calt: one lookup per ligature, longest first ----------
ops = " ".join(sorted({G(c) for c in "=<>-!|:"}))
fea = [f"@OPS = [{ops}];"]
lookups = []
for chars, name in sorted(ligs, key=lambda l: -len(l[0])):
    gn = [G(c) for c in chars]
    ln = name.replace(".", "_")
    body = [f"  ignore sub @OPS {gn[0]}' {' '.join(gn[1:])};",
            f"  ignore sub {gn[0]}' {' '.join(gn[1:])} @OPS;"]
    for i in range(len(gn)):
        before = " ".join(f"{name}.sp{j}" for j in range(i))
        after = " ".join(gn[i + 1:])
        target = f"{name}.sp{i}" if i < len(gn) - 1 else name
        body.append(" ".join(f"  sub {before} {gn[i]}' {after} by {target};".split()).join(["  ", ""]))
    fea.append(f"lookup {ln} {{\n" + "\n".join(body) + f"\n}} {ln};")
    lookups.append(ln)
fea.append("feature calt {\n" + "\n".join(f"  lookup {l};" for l in lookups) + "\n} calt;")

tmp = TTFont()
tmp.setGlyphOrder(order)
addOpenTypeFeaturesFromString(tmp, "\n".join(fea), tables=["GSUB"])
new, gsub = tmp["GSUB"].table, f["GSUB"].table
off = len(gsub.LookupList.Lookup)


def remap(obj):
    for r in getattr(obj, "SubstLookupRecord", []) or []:
        r.LookupListIndex += off
    for attr in ("ChainSubRuleSet", "ChainSubClassSet"):
        for rs in getattr(obj, attr, []) or []:
            if rs is None: continue
            for rule in (getattr(rs, "ChainSubRule", None) or getattr(rs, "ChainSubClassRule", None) or []):
                remap(rule)


for lk in new.LookupList.Lookup:
    for st in lk.SubTable:
        remap(st)
    gsub.LookupList.Lookup.append(lk)
gsub.LookupList.LookupCount = len(gsub.LookupList.Lookup)
calt = new.FeatureList.FeatureRecord[0]
calt.Feature.LookupListIndex = [i + off for i in calt.Feature.LookupListIndex]
gsub.FeatureList.FeatureRecord.append(calt)
fi = len(gsub.FeatureList.FeatureRecord) - 1
gsub.FeatureList.FeatureCount = fi + 1
for sr in gsub.ScriptList.ScriptRecord:
    for ls in ([sr.Script.DefaultLangSys] if sr.Script.DefaultLangSys else []) + [l.LangSys for l in sr.Script.LangSysRecord]:
        ls.FeatureIndex.append(fi)
        ls.FeatureCount = len(ls.FeatureIndex)

for rec in f["name"].names:
    s = rec.toUnicode()
    s2 = s.replace("Obel Mono", "Obel Mono Lig").replace("ObelMono", "ObelMonoLig")
    if s2 != s:
        rec.string = s2

f.save(dst)
print("ligatures:", " ".join(c for c, _ in ligs), "| masters:", len(MASTERS), "| slant:", round(SLANT, 3))
