"""Generate the GIRL reference face drawing (in/face_ref_girl.png) from the boy drawing: same head / skin, every
feature erased and redrawn (big round eyes, thick rounded eyeliner with lash flicks, a few lower lashes, a thin
double-eyelid line, thin arched brows, a small mouth line).  Symmetric (drawn for the right eye, mirrored).
usage: FACE_STYLE=girl python make_girl_ref.py in/face_ref.webp in/face_ref_girl.png"""
import os, sys, math
os.environ['FACE_STYLE'] = 'girl'
import numpy as np, cv2
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layout import *

SRC, DST = sys.argv[1], sys.argv[2]
im = cv2.cvtColor(cv2.imread(SRC), cv2.COLOR_BGR2RGB).astype(np.float32)
H, W, _ = im.shape
g = im.mean(2)
# 1) erase all features: inpaint everything darker than the local skin in the face area
blur = cv2.GaussianBlur(g, (0, 0), 25)
feat = ((g < blur - 4) | (g > blur + 8)).astype(np.uint8)        # every drawn feature (ink and eye whites)
from scipy import ndimage as ndi
_lab, _n = ndi.label(g > 60)
_head = ndi.binary_fill_holes(_lab == _lab[int(CY), int(CX)])
_head = cv2.erode(_head.astype(np.uint8), np.ones((15, 15), np.uint8))
area = np.zeros((H, W), np.uint8); area[400:830, :] = 1; area *= _head
feat = cv2.dilate(feat * area, np.ones((13, 13), np.uint8))
skin = cv2.inpaint(np.clip(im, 0, 255).astype(np.uint8), feat, 15, cv2.INPAINT_TELEA).astype(np.float32)
_af = cv2.GaussianBlur(area.astype(np.float32), (0, 0), 4)[..., None]
_flat = np.median(im[600:700, 450:620].reshape(-1, 3), axis=0)   # the skin is transparent in the texture anyway:
skin = _flat[None, None, :] * _af + im * (1 - _af)                # a flat skin tone, no leftover shading

SS = 4
INK = np.array((14, 12, 15), np.float32)
layer = np.zeros((H * SS, W * SS), np.uint8)          # ink coverage, drawn at 4x


def P(pts):
    return np.round(np.array(pts, np.float64) * SS * 8).astype(np.int32)


def stroke(pts, hw, both=True):
    """tapered stroke along a polyline; hw = list of half widths (px) per point"""
    pts = np.array(pts, np.float64); n = len(pts)
    d = np.gradient(pts, axis=0); d /= np.linalg.norm(d, axis=1, keepdims=True) + 1e-9
    nrm = np.stack([-d[:, 1], d[:, 0]], 1)
    up = pts + nrm * np.array(hw)[:, None]; dn = pts - nrm * np.array(hw)[:, None]
    poly = np.concatenate([up, dn[::-1]])
    for Q in ([poly, np.stack([2 * CX - poly[:, 0], poly[:, 1]], 1)] if both else [poly]):
        cv2.fillPoly(layer, [P(Q)], 255, cv2.LINE_AA, 3)


def fill(poly):
    poly = np.array(poly, np.float64)
    for Q in (poly, np.stack([2 * CX - poly[:, 0], poly[:, 1]], 1)):
        cv2.fillPoly(layer, [P(Q)], 255, cv2.LINE_AA, 3)


def bez(p0, p1, p2, n=40):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * np.array(p0) + 2 * (1 - t) * t * np.array(p1) + t ** 2 * np.array(p2)


top, bot = girl_eye_chains(48)                             # (fine sampling for the drawing only)
# 2) eyeliner band (it becomes the 3D eyeliner; drawn too so the outline reads in the drawing)
fill(LASH_PX['R'])
# lash flicks at the outer upper corner (stay as texture, outside the 3D band)
for (x0, y0, ang, L) in ((314, 528, 210, 17), (298, 532, 205, 22), (282, 538, 198, 25), (266, 545, 190, 24), (250, 550, 183, 18)):
    a = math.radians(ang)
    p0 = np.array((x0, y0)); p2 = p0 + L * np.array((math.cos(a), -abs(math.sin(a)) - 0.55))
    p1 = (p0 + p2) / 2 + np.array((0, -3))
    c = bez(p0, p1, p2, 24); stroke(c, list(np.linspace(2.4, 0.1, 24)))
# inner corner hook: the eyeliner turns down along the short inner edge of the eye
_ti = top[-1]; _bi = [p for p in bot if p[0] > top[-1][0] - 22]
hook = [(_ti[0] + 3, _ti[1] + 1), (_ti[0] + 4.5, (_ti[1] + _bi[0][1]) / 2 + 2), (_bi[0][0] - 2, _bi[0][1] + 1)]
hk = bez(hook[0], hook[1], hook[2], 16)
stroke(hk, list(np.linspace(2.6, 0.2, 16)))
# 3) lower lashes: a thin line under the outer part of the eye + 3 small lashes
lb = [(x, y + 2.5) for x, y in bot if x < 400][::-1]       # outer -> towards the middle
lb = np.array(lb)
hw = np.interp(np.arange(len(lb)), [0, len(lb) * 0.3, len(lb) - 1], [1.6, 1.1, 0.15])
stroke(lb, list(hw))
for (x0, ang, L) in ((288, 230, 10), (304, 245, 9), (322, 255, 8)):
    y0 = np.interp(x0, lb[:, 0], lb[:, 1]) + 0.5
    a = math.radians(ang)
    c = bez((x0, y0), (x0 + L * 0.5 * math.cos(a), y0 - L * 0.5 * math.sin(a)), (x0 + L * math.cos(a), y0 - L * math.sin(a)), 12)
    stroke(c, list(np.linspace(1.3, 0.1, 12)))
# 4) double-eyelid line, following the eye curve above the eyeliner
crease = []
for i, (x, y) in enumerate(top):
    u = -1 + 2 * i / (len(top) - 1)
    if -0.62 <= u <= 0.72:
        th = 6 + 13 * (1 - (u + 1) / 2) ** 0.8
        crease.append((x, y - th - 8))
crease = np.array(crease)
uu = np.linspace(0, 1, len(crease))
stroke(crease, list(1.25 * np.sin(np.pi * uu) ** 0.6 + 0.1))
# 5) thin arched brows (inner -> outer), thicker near the inner end, pointed outer end
(ix, iy), (ox, oy) = BROW_PX['R']
br = bez((ix, iy), (378, 452), (ox, oy), 60)
tb = np.linspace(0, 1, 60)
stroke(br, list(3.4 * (1 - tb) ** 0.7 * np.clip(tb / 0.06, 0, 1) ** 0.5 + 0.15))
# 6) small mouth line (centred), slight curve, tapered ends
mx = np.linspace(CX - 36, CX + 36, 48)
my = 761 + 2.6 * ((mx - CX) / 36) ** 2
um = np.linspace(0, 1, 48)
stroke(np.stack([mx, my], 1), list(1.7 * np.sin(np.pi * um) ** 0.5 + 0.2), both=False)

cov = cv2.resize(layer.astype(np.float32) / 255, (W, H), interpolation=cv2.INTER_AREA)[..., None]
out = skin * (1 - cov) + INK * cov
# 7) eye openings: white, with a dark iris disc (the real iris comes from IRIS_SRC; this only keeps the drawing readable)
em = np.zeros((H * SS, W * SS), np.uint8)
fill_poly = np.array(EYE_PX['R'], np.float64)
for Q in (fill_poly, np.stack([2 * CX - fill_poly[:, 0], fill_poly[:, 1]], 1)):
    cv2.fillPoly(em, [P(Q)], 255, cv2.LINE_AA, 3)
emf = cv2.resize(em.astype(np.float32) / 255, (W, H), interpolation=cv2.INTER_AREA)[..., None]
eye = np.full_like(out, 238.0)
yy, xx = np.mgrid[0:H, 0:W]
for (cx, cy), (rx, ry) in ((IRIS_PX['R'], IRIS_R_PX['R']), (IRIS_PX['L'], IRIS_R_PX['L'])):
    d = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    eye[d <= 1] = (60, 58, 64)
out = out * (1 - emf) + eye * emf
cv2.imwrite(DST, cv2.cvtColor(np.clip(out, 0, 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
print('saved', DST)
