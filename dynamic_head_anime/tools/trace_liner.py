"""Trace the drawn upper eyeliner + lashes of a girl drawing (screen-left eye) and write the 3D eyeliner outline:
per column, from the eye opening's top edge (or the ink's lower edge outside the eye) up to the highest ink (+margin).
The 3D eyeliner then carries the drawing itself (its front faces use the face texture), so it looks exactly like it.
usage: FACE_STYLE=girl2 python trace_liner.py in/face_ref2.png in/girl2_lash.json"""
import os, sys, json
import numpy as np, cv2
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layout import *

SRC, DST = sys.argv[1], sys.argv[2]
im = cv2.cvtColor(cv2.imread(SRC), cv2.COLOR_BGR2RGB).astype(np.float32)
H, W, _ = im.shape
g = im.mean(2)
eye = np.array(EYE_PX['R'], np.float32)
em = np.zeros((H, W), np.uint8)
cv2.fillPoly(em, [np.round(eye * 8).astype(np.int32)], 255, cv2.LINE_AA, 3)
em = cv2.dilate(em, np.ones((3, 3), np.uint8))
ex0, ex1 = eye[:, 0].min(), eye[:, 0].max()
ox, oy = eye[np.argmin(eye[:, 0])]                       # outer corner
ink = (g < 95) & (em == 0)
ink[:440] = False; ink[:, :180] = False; ink[:, int(CX):] = False
yy, xx = np.mgrid[0:H, 0:W]
ink &= ~((xx < ox + 2) & (yy > oy - 1))                  # not the lower lashes below the outer corner


def top_edge(x):
    ys = []
    for i in range(len(eye)):
        (x1, y1), (x2, y2) = eye[i], eye[(i + 1) % len(eye)]
        if (x1 - x) * (x2 - x) <= 0 and x1 != x2: ys.append(y1 + (x - x1) * (y2 - y1) / (x2 - x1))
    return min(ys) if ys else None


# the component(s) of ink touching the top edge of the opening (liner + upper lashes + wing)
seed = np.zeros((H, W), np.uint8)
for x in range(int(ex0) + 1, int(ex1)):
    t = top_edge(x)
    if t is not None: seed[int(t) - 4:int(t) + 1, x] = 1
n, lab = cv2.connectedComponents(ink.astype(np.uint8), connectivity=8)
keep = set(np.unique(lab[(seed > 0) & ink])) - {0}
comp = np.isin(lab, list(keep))
cols = np.where(comp.any(0))[0]
x_lo, x_hi = cols.min(), cols.max()
step = 4
top, bot = [], []
for x in range(int(x_lo), int(x_hi) + 1, step):
    sl = comp[:, max(x - step, 0):x + step + 1].any(1)
    ys = np.where(sl)[0]
    if len(ys) == 0: continue
    t_ = ys.min() - 3.0
    te = top_edge(x) if ex0 < x < ex1 else None
    b_ = te if te is not None else ys.max() + 2.0
    top.append((float(x), float(t_))); bot.append((float(x), float(max(b_, t_ + 4))))
# top edge = the UPPER CONVEX HULL of the lashes (+ margin): every spike tip is inside the band, straight between tips
# (the band is transparent between the spikes, so the hull costs nothing visually and needs few columns)
_pts = np.argwhere(comp)[:, ::-1].astype(np.float32)          # (x, y)
_hull = cv2.convexHull(_pts).reshape(-1, 2)
def hull_top(x):
    ys = []
    for i in range(len(_hull)):
        (x1, y1), (x2, y2) = _hull[i], _hull[(i + 1) % len(_hull)]
        if (x1 - x) * (x2 - x) <= 0 and x1 != x2: ys.append(y1 + (x - x1) * (y2 - y1) / (x2 - x1))
    return min(ys) if ys else None
top = [(float(x), float((hull_top(x) if hull_top(x) is not None else t) - 1.5)) for x, t in top]
poly = [top[0]] + top[1:] + bot[::-1]
# the eye opening, from the drawing: top edge = just under the drawn eyeliner ink, bottom edge = just above the drawn
# lower lash line; the ends are the points where they meet (rounded inner corner, pointed outer corner)
inkall = (g < 70)
ys_top, ys_bot, xs_e = [], [], []
for x in range(int(ex0) - 6, int(ex1) + 8):
    c = comp[:, x]
    ys = np.where(c[500:640])[0]
    if len(ys) == 0: continue
    yt = 500 + ys.max() + 1                                       # first row under the liner
    col = inkall[yt + 2:700, x]
    lower = np.where(col)[0]
    # the lower lash line: the first ink row at least 6 px below, that continues for >= 2 rows
    yb = None
    for k in lower:
        if k > 6 and col[k:k + 2].all(): yb = yt + 2 + k; break
    if yb is None or yb - yt < 4: continue
    xs_e.append(x); ys_top.append(yt + 0.5); ys_bot.append(yb - 0.5)
xs_e = np.array(xs_e, float); ys_top = np.array(ys_top); ys_bot = np.array(ys_bot)
ok = (ys_bot - ys_top) > 3
xs_e, ys_top, ys_bot = xs_e[ok], ys_top[ok], ys_bot[ok]
k = 7
st = np.convolve(np.pad(ys_top, k // 2, mode='edge'), np.ones(k) / k, 'valid')
sb = np.convolve(np.pad(ys_bot, k // 2, mode='edge'), np.ones(k) / k, 'valid')
idx = np.linspace(0, len(xs_e) - 1, 16).round().astype(int)
eye_top = [(float(xs_e[i]), float(st[i])) for i in idx]
eye_bot = [(float(xs_e[i]), float(sb[i])) for i in idx[::-1][1:-1]]
# rounded inner end: a short arc between the last top and bottom points
xi_, ti_, bi_ = xs_e[-1], st[-1], sb[-1]
arc = [(float(xi_ + 3.5 * np.sin(a)), float((ti_ + bi_) / 2 - (bi_ - ti_) / 2 * np.cos(a))) for a in np.linspace(0.5, 2.6, 4)]
eye_poly = eye_top + arc + eye_bot
# the exact silhouette of the eyeliner + lashes (the 3D eyeliner is cut to it: no transparent slab between the spikes)
# = the liner ink (with its anti-aliased edge, the separate crease line excluded) + a thin strip just inside the
# opening's top edge (the overhang that hides the rim of the hole)
sil = comp.copy()                                   # dark ink only (g < 95): no grey haze between the lashes
# the lower branch of the outer corner's "<" (the short spike under the wing) goes on the eyeliner too: both ends of
# the corner move together when blinking (no gap between them); the line down the outer edge of the eye stays skin
_ink3 = (g < 95)                                     # (the rim line itself too, even where it touches the white)
_zone = (xx < ox + int(os.environ.get('CORNER_DX', 8))) & (yy >= oy - 6) & (yy < oy + int(os.environ.get('CORNER_DY', 24))) & (xx > ox - 70)
_n4, _lab4 = cv2.connectedComponents((_ink3 & (_zone | comp)).astype(np.uint8), connectivity=8)
_kc = set(np.unique(_lab4[comp])) - {0}
sil |= np.isin(_lab4, list(_kc)) & _zone
OV = float(os.environ.get('SIL_OV', 3.5))
for x in range(int(ex0) + 1, int(ex1)):
    t = top_edge(x)
    if t is not None:
        sil[int(t + OV) + 1:, x] = False             # (the thin liner along the inner edge stays on the skin)
        sil[int(t) - 1:int(t + OV) + 1, x] = True
_yc = top_edge(ex1 - 10) + OV                       # the thin line down the inner edge of the eye: skin, not eyeliner
sil[int(_yc) + 1:, int(ex1) - 14:int(ex1) - 1] = False     # (only that thin line: the lashes' inner point stays whole)
sil = cv2.morphologyEx(sil.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
SS_ = 4
big = cv2.resize(sil * 255, (W * SS_, H * SS_), interpolation=cv2.INTER_LINEAR)
big = cv2.GaussianBlur(big, (0, 0), 2.0)
big = cv2.dilate((big > 100).astype(np.uint8), np.ones((3, 3), np.uint8))   # ~0.3 px margin around the ink
cs, _ = cv2.findContours(big, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
c = max(cs, key=cv2.contourArea)
c = cv2.approxPolyDP(c, float(os.environ.get('SIL_EPS', 0.9)) * SS_, True).reshape(-1, 2).astype(np.float64) / SS_
SIL = [(float(x), float(y)) for x, y in c]
print('silhouette points', len(SIL), 'other pieces', len(cs) - 1, 'areas', sorted(int(cv2.contourArea(k) / SS_ ** 2) for k in cs)[-4:])
json.dump(dict(R=poly, EYE=eye_poly, SIL=SIL), open(DST, 'w'))
print('eye opening from the drawing: x', int(xs_e[0]), int(xs_e[-1]), 'top', round(float(st.min()), 1), 'bottom', round(float(sb.max()), 1))
print('liner outline points', len(poly), 'x', int(x_lo), int(x_hi), 'top', int(min(p[1] for p in top)))
