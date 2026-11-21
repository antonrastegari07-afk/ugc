"""Build the 1024 texture atlas + face data (mouth line, brows) from the reference face image."""
import cv2, numpy as np, json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from layout import *

SRC, OUT = sys.argv[1], sys.argv[2]
im = cv2.cvtColor(cv2.imread(SRC), cv2.COLOR_BGR2RGB).astype(np.float32)
H, W, _ = im.shape
if MIRROR_EYES and FACE_STYLE != 'girl2':   # the left eye + brow = mirror image of the right ones (screen left) (see layout.MIRROR_EYES)
    _r0, _r1 = MIRROR_ROWS
    _xs = np.arange(W, dtype=np.float32)
    _mir = cv2.remap(im, np.tile(2 * CX - _xs, (H, 1)).astype(np.float32),
                     np.tile(np.arange(H, dtype=np.float32)[:, None], (1, W)), cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    _ry = np.arange(H, dtype=np.float32)[:, None]
    _wy = np.clip(np.minimum(_ry - (_r0 - 15), (_r1 + 15) - _ry) / 15, 0, 1)
    _wx = np.clip((_xs[None, :] - CX - 2) / 4, 0, 1)                       # only the screen-right half, soft seam
    _w = (_wy * _wy * (3 - 2 * _wy) * _wx)[..., None]
    im = im * (1 - _w) + _mir * _w
# the eyelid crease line (between the brow and the eyeliner) follows the curve of the top of the eye (it was almost flat:
# the gap grew towards the nose); the brows come down a little to fill the space.  A smooth vertical displacement field,
# zero on and below the eyeliner (the 3D band and the eyes don't move); symmetric for both eyes.
CREASE_GAP, BROW_DOWN = 13.0, float(os.environ.get("BROW_DOWN", 9.0))
if os.environ.get('CREASE_FOLLOW', '1') == '1' and FACE_STYLE == 'boy':   # boy drawing fixes only
    _poly = LASH_PX['R']
    def _top(x):
        ys = []
        for i in range(len(_poly)):
            (x1, y1), (x2, y2) = _poly[i], _poly[(i + 1) % len(_poly)]
            if (x1 - x) * (x2 - x) <= 0 and x1 != x2: ys.append(y1 + (x - x1) * (y2 - y1) / (x2 - x1))
        return min(ys) if ys else None
    _CY0 = 520.0                                              # the drawn crease line (almost flat)
    def _sst(e0, e1, v):
        t = min(1.0, max(0.0, (v - e0) / (e1 - e0))); return t * t * (3 - 2 * t)
    _ys = np.arange(H, dtype=np.float32)
    # 1) the brows move down as a block (rows 430..510), nothing below them moves in this step
    Db = BROW_DOWN * np.clip((_ys - 430) / 15, 0, 1) * np.clip((510 - _ys) / 8, 0, 1)
    _mx, _my = np.meshgrid(np.arange(W, dtype=np.float32), np.arange(H, dtype=np.float32))
    im = cv2.remap(im, _mx, _my - Db[:, None], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    # 2) a CLEAN crease line: the drawn one is erased and redrawn as one smooth tapered stroke that follows the curve
    #    of the top of the eye (constant gap above the eyeliner), thin at both ends, a bit thicker in the middle
    _skin = np.median(im[512:528, 300:360].reshape(-1, 3), axis=0)
    XS, XE = 284.0, 474.0
    for x in range(232, 490):
        ty = _top(x)
        y1 = int((ty - 2) if ty is not None else 548)
        for xx in (x, int(round(2 * CX - x))):
            if 0 <= xx < W and y1 > 506: im[506:y1, xx] = _skin
    def _yc(x):
        ty = _top(x)
        ty = min(ty if ty is not None else 550.0, 550.0)
        return ty - CREASE_GAP - 1.0
    _xs = np.linspace(XS, XE, 240)
    _yy = np.array([_yc(x) for x in _xs])
    _yy = np.convolve(np.pad(_yy, 6, mode='edge'), np.ones(13) / 13, mode='valid')   # smooth curve
    _u = (_xs - XS) / (XE - XS)
    _hw = 1.7 * np.sin(np.pi * np.clip(_u, 0, 1)) ** 0.55 * (1 - 0.3 * _u)             # half width: pointed ends
    _up = np.stack([_xs, _yy - _hw], 1); _dn = np.stack([_xs, _yy + _hw], 1)[::-1]
    _pol = np.concatenate([_up, _dn])
    SS = 4                                                   # drawn at 4x then reduced: a smooth, even stroke
    _mask = np.zeros((H * SS, W * SS), np.uint8)
    for P in (_pol, np.stack([2 * CX - _pol[:, 0], _pol[:, 1]], 1)):
        cv2.fillPoly(_mask, [np.round((P + 0.5) * SS * 8 - 4).astype(np.int32)], 255, lineType=cv2.LINE_AA, shift=3)
    _m = cv2.resize(_mask.astype(np.float32) / 255, (W, H), interpolation=cv2.INTER_AREA)
    _m = cv2.GaussianBlur(_m, (0, 0), 0.45)[..., None]
    im = im * (1 - _m) + np.array([34, 32, 38], np.float32) * _m

# shorten the drawn eyeliner strokes beyond the eye corners like the 3D eyeliner (see layout.lash_corners)
_mx, _my = np.meshgrid(np.arange(W, dtype=np.float32), np.arange(H, dtype=np.float32))
_src = _mx.copy()
for c, sgn, lw, lw2 in lash_corners():
    u = (_mx[0] - c) * sgn
    su = np.array([corner_src_u(v, lw, lw2) if 0 < v <= lw2 else v for v in u], np.float32)
    sel = (u > 0) & (u <= lw2)
    _src[:, sel] = (c + sgn * su[sel])[None, :]
_b0, _b1 = LASH_BAND
_w = np.clip(np.minimum(_my - (_b0 - 8), (_b1 + 8) - _my) / 8, 0, 1)
_w = _w * _w * (3 - 2 * _w)
im = cv2.remap(im, _mx + (_src - _mx) * _w, _my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
g = im.mean(2)

# eye opening masks (image space)
eye_mask = np.zeros((H, W), np.uint8)
for side in 'RL':
    cv2.fillPoly(eye_mask, [np.round(np.array(EYE_PX[side]) * 8).astype(np.int32)], 255, lineType=cv2.LINE_AA, shift=3)

# --- skin estimate: inpaint everything that is darker than the local skin, plus the eyes
blur = cv2.GaussianBlur(g, (0, 0), 25)
feat = ((g < blur - 6) | (eye_mask > 0)).astype(np.uint8)
COLOR_FACE = FACE_STYLE == 'girl2'     # the drawing has coloured / light features (blush, sparkles): keep their colour
if COLOR_FACE:
    _bl3 = cv2.GaussianBlur(im, (0, 0), 25)
    feat |= ((np.abs(im - _bl3).max(2) > 7) | (g > blur + 5) | ((im.max(2) - im.min(2)) > 6)).astype(np.uint8)   # + any tint (the skin is grey)
    feat = cv2.dilate(feat, np.ones((11, 11), np.uint8))
feat = cv2.dilate(feat, np.ones((7, 7), np.uint8))
small = cv2.resize(im, (W // 2, H // 2), interpolation=cv2.INTER_AREA).astype(np.uint8)
fsmall = cv2.resize(feat, (W // 2, H // 2), interpolation=cv2.INTER_NEAREST)
skin = cv2.inpaint(small, fsmall, 12, cv2.INPAINT_TELEA).astype(np.float32)
skin = cv2.GaussianBlur(cv2.resize(skin, (W, H), interpolation=cv2.INTER_CUBIC), (0, 0), 3)
S = skin.mean(2)
K = 6.0                                                  # ink value
alpha = np.clip((S - g) / np.maximum(S - K, 1), 0, 1)
alpha[alpha < 0.06] = 0
alpha = np.clip((alpha - 0.06) / 0.94, 0, 1)
# ignore the dark background around the head
from scipy import ndimage as ndi
lab, n = ndi.label(g > 60)
head = lab == lab[int(CY), int(CX)]
head = ndi.binary_fill_holes(head)
head = cv2.erode(head.astype(np.uint8), np.ones((25, 25), np.uint8))
alpha *= cv2.GaussianBlur(head.astype(np.float32), (0, 0), 3)
# keep only the face's real lines: eyes / brows band and the mouth. The drawing's soft cheek shading (a grey smudge
# beside the mouth) is not ink: removed, the skin there is the plain recolourable skin
_keep = np.zeros((H, W), np.float32)
_keep[:690, :] = 1.0                                   # forehead, brows, eyes, lower lashes
_keep[725:790, 455:620] = 1.0                          # the mouth line
_keep = cv2.GaussianBlur(_keep, (0, 0), 4)
if not COLOR_FACE:
    alpha *= _keep
INK = np.array([14, 12, 15], np.float32)
INKCOL = None
SRCMAP = None
if COLOR_FACE:
    # exact separation on the FULL-RESOLUTION source: skin estimate S (smooth, features inpainted), then the minimal
    # alpha that explains each pixel as colour C over S (C in 0..255) -> composited back over the same skin it gives the
    # drawing exactly (blush intensity, white sparkles / hearts, thin brow tips all kept)
    _src = cv2.cvtColor(cv2.imread(os.path.join(os.path.dirname(SRC), GIRL2_SRC['path'])), cv2.COLOR_BGR2RGB).astype(np.float32)
    _gs = _src.mean(2)
    # skin: the drawing's skin is one flat grey (+-4 of render lighting, which is NOT part of the drawing); the
    # recolourable head supplies its own shading, so the skin reference is that flat grey
    _hs, _ws = _gs.shape
    _chroma = _src.max(2) - _src.min(2)
    _sel = (_chroma <= 6) & (_gs > 120) & (_gs < 170)
    _sel[:, :200] = False; _sel[:, -200:] = False
    _Sc = np.median(_src[_sel], axis=0)
    _Ss = np.broadcast_to(_Sc, _src.shape).astype(np.float32)
    _d = _src - _Ss
    _al = (np.clip(_d, 0, None) / np.maximum(255 - _Ss, 1)).max(2)          # lighter than the skin (white marks)
    _ad = (np.clip(-_d, 0, None) / np.maximum(_Ss, 1)).max(2)              # darker / tinted (ink, blush)
    def _ss(e0, e1, v): t = np.clip((v - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)
    _an = np.where(_al > _ad, _al * _ss(0.05, 0.12, _al), _ad * _ss(0.045, 0.09, _ad))   # render lighting (<~5%) dropped
    _an = np.clip(_an, 0, 1)
    _cs = np.clip(_Ss + _d / np.maximum(_an, 1e-3)[..., None], 0, 255)
    # ink (dark, grey): fully opaque with its own colour (the liner's sheen streaks stay as drawn, no skin through it)
    _ink = (1 - _ss(0.40, 0.62, _gs / max(float(_Sc.mean()), 1))) * (1 - _ss(10, 22, _src.max(2) - _src.min(2)))
    _cs = _cs * (1 - _ink[..., None]) + _src * _ink[..., None]
    _an = np.maximum(_an, _ink)
    SRCMAP = dict(a=_an.astype(np.float32), c=_cs.astype(np.float32), img=_src)
    def src_coords(px, py):
        g_ = GIRL2_SRC
        return ((g_['sx0'] + (px - g_['dx0']) * (g_['sx1'] - g_['sx0']) / (g_['dx1'] - g_['dx0'])).astype(np.float32),
                (g_['sy0'] + (py - g_['dy0']) * (g_['sy1'] - g_['sy0']) / (g_['dy1'] - g_['dy0'])).astype(np.float32))
    # premultiplied separation against the skin estimate: works for black ink, pink blush and white sparkles alike
    _d = im - skin
    _a = np.clip(np.abs(_d).max(2) / 115.0, 0, 1)
    _a[_a < 0.05] = 0
    _win = np.zeros((H, W), np.float32); _win[380:800, 228:836] = 1.0       # the face only (not the lit head edges)
    _a = np.clip((_a - 0.05) / 0.95, 0, 1) * cv2.GaussianBlur(head.astype(np.float32), (0, 0), 3) * cv2.GaussianBlur(_win, (0, 0), 6)
    INKCOL = np.clip(skin + _d / np.maximum(_a, 0.05)[..., None], 0, 255)
    INKCOL = np.where((g < 60)[..., None], INK, INKCOL)
    alpha = _a
# the upper eyeliner is real 3D geometry (it moves down when the eye closes): remove its ink from the face layer
lash_mask = np.zeros((H, W), np.uint8)
for side in 'RL':
    cv2.fillPoly(lash_mask, [np.round(np.array(LASH_PX[side]) * 8).astype(np.int32)], 255, lineType=cv2.LINE_AA, shift=3)
for side in ('RL' if FACE_STYLE == 'boy' else ''):   # the drawn eyeliner is a little thicker upwards than the traced band:
    _p = np.array(LASH_PX[side], np.float32); _p[:, 1] -= 4            # erase 4 px more above it (no grey sliver left
    cv2.fillPoly(lash_mask, [np.round(_p * 8).astype(np.int32)], 255, lineType=cv2.LINE_AA, shift=3)   # over the 3D band)
lash_mask = cv2.dilate(lash_mask, np.ones((7, 7) if FACE_STYLE == 'boy' else (3, 3), np.uint8))
# beyond the eye corners (the wings), keep the drawn ink of the bottom 6 px of the band: it lies under the 3D eyeliner
# (hidden from the front) and joins the 3D wing to the drawn lower strokes from every angle (no parallax gap)
wing_mask = np.zeros((H, W), np.uint8)
for side in 'RL':
    _p = np.array(LASH_PX[side], np.float32); _p[:, 1] -= 6
    cv2.fillPoly(wing_mask, [np.round(_p * 8).astype(np.int32)], 255, lineType=cv2.LINE_AA, shift=3)
wing_mask = cv2.dilate(wing_mask, np.ones((5, 5), np.uint8))
_wz = np.zeros(W, np.float32)
for side in 'RL':
    _e0, _e1 = min(p[0] for p in EYE_PX[side]), max(p[0] for p in EYE_PX[side])
    _x = np.arange(W, dtype=np.float32)
    _wz = np.maximum(_wz, np.clip(np.maximum(_e0 + 2 - _x, _x - _e1 - 2) / 6, 0, 1) * ((_x > _e0 - 90) & (_x < _e1 + 90)))
lash_mask = (lash_mask * (1 - _wz[None, :]) + np.minimum(lash_mask, wing_mask) * _wz[None, :]).astype(np.uint8)
ALPHA_FULL = alpha.copy()                              # (girl2: copied onto the 3D eyeliner before erasing)
if FACE_STYLE == 'girl2':                              # erase only the ink of the liner / lashes, not the eyeshadow
    lash_mask = np.minimum(lash_mask, cv2.dilate((ALPHA_FULL > 0.3).astype(np.uint8) * 255, np.ones((5, 5), np.uint8)))
ERASE = cv2.GaussianBlur(lash_mask.astype(np.float32) / 255, (0, 0), 1.0)
alpha *= 1 - ERASE
# outer wing: the drawn lower stroke and the 3D eyeliner meet at the tip with a thin wedge of skin between them; fill
# that wedge with ink (closing of ink + eyeliner band + opening, only beyond the outer corners) -> one solid wing
_solid = np.maximum((alpha > 0.45).astype(np.uint8) * 255, 0)
_band = np.zeros((H, W), np.uint8)
for side in 'RL':
    cv2.fillPoly(_band, [np.round(np.array(LASH_PX[side]) * 8).astype(np.int32)], 255, lineType=cv2.LINE_8, shift=3)
_sup = np.maximum(np.maximum(_solid, _band), eye_mask)
_cls = cv2.morphologyEx(_sup, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (17, 17)))
_zone = np.zeros((H, W), np.float32)
for side in 'RL':
    _e0, _e1 = min(p[0] for p in EYE_PX[side]), max(p[0] for p in EYE_PX[side])
    _l0, _l1 = min(p[0] for p in LASH_PX[side]), max(p[0] for p in LASH_PX[side])
    _ys = [p[1] for p in EYE_PX[side]]
    y0_, y1_ = int(min(p[1] for p in LASH_PX[side])) - 2, int(max(_ys)) + 4
    if side == 'R': x0_, x1_ = int(_l0) - 2, int(_e0 + 0.25 * (_e1 - _e0))      # outer corner is on the screen-left
    else: x0_, x1_ = int(_e1 - 0.25 * (_e1 - _e0)), int(_l1) + 2
    _zone[max(y0_, 0):y1_, max(x0_, 0):x1_] = 1.0
_fill = ((_cls > 0) & (_sup == 0) & (lash_mask < 64)).astype(np.float32) * _zone   # never back over the 3D band
if FACE_STYLE != 'boy': _fill[:] = 0                  # (boy drawing fix: would merge the girl's lash flicks)
_fill = cv2.GaussianBlur(_fill, (0, 0), 0.8)
alpha = np.maximum(alpha, _fill)
print('wing gap filled px', int((_fill > 0.5).sum()))
# inner corners (nose side): remove the small drawn spikes just past the corner, under the end of the 3D eyeliner
_kill = np.zeros((H, W), np.float32)
for side in 'RL':
    _e0, _e1 = min(p[0] for p in EYE_PX[side]), max(p[0] for p in EYE_PX[side])
    _top = min(p[1] for p in EYE_PX[side])
    if side == 'R': xa_, xb_ = int(_e1) + 1, int(_e1) + 34        # inner corner of the screen-left eye is on its right
    else: xa_, xb_ = int(_e0) - 34, int(_e0) - 1
    _kill[int(_top) - 2:int(_top) + 44, max(xa_, 0):xb_] = 1.0
_kill = cv2.GaussianBlur(_kill, (0, 0), 1.5)
if FACE_STYLE == 'boy': alpha *= 1 - _kill

# --- FACE block of the atlas: sample the image through the stud mapping
fx, fy, fw, fh = FACE_RECT
atlas = np.zeros((ATLAS, ATLAS, 4), np.float32)
ys, xs = np.mgrid[0:fh, 0:fw]
xst = FACE_X[0] + (xs + 0.5) / fw * (FACE_X[1] - FACE_X[0])
zst = FACE_Z[0] + (ys + 0.5) / fh * (FACE_Z[1] - FACE_Z[0])
mx = (CX + xst * SX).astype(np.float32); my = (CY - zst * SY).astype(np.float32)
a_s = cv2.remap(alpha.astype(np.float32), mx, my, cv2.INTER_LINEAR, borderValue=0)
rgb_s = cv2.remap(im, mx, my, cv2.INTER_LINEAR, borderValue=0)
em_s = cv2.remap(eye_mask.astype(np.float32) / 255, mx, my, cv2.INTER_LINEAR, borderValue=0)
face = np.zeros((fh, fw, 4), np.float32)
face[..., :3] = INK if INKCOL is None else cv2.remap(INKCOL.astype(np.float32), mx, my, cv2.INTER_LINEAR, borderValue=0)
face[..., 3] = a_s
if SRCMAP is not None:
    _mult = cv2.GaussianBlur(head.astype(np.float32), (0, 0), 3) * cv2.GaussianBlur(_win, (0, 0), 6) * (1 - ERASE)
    _sx, _sy = src_coords(mx, my)
    face[..., 3] = cv2.remap(SRCMAP['a'], _sx, _sy, cv2.INTER_CUBIC, borderValue=0).clip(0, 1) * cv2.remap(_mult, mx, my, cv2.INTER_LINEAR, borderValue=0)
    face[..., :3] = cv2.remap(SRCMAP['c'], _sx, _sy, cv2.INTER_LINEAR, borderValue=0)
# around/inside the openings keep the exact image pixels (no skin-coloured sliver at the rim)
face[..., :3] = face[..., :3] * (1 - em_s[..., None]) + rgb_s * em_s[..., None]
face[..., 3] = np.maximum(face[..., 3], em_s)
_l = rgb_s.mean(2)
_w = (em_s > 0.5) & (_l > 85)
face[..., :3] = np.where(_w[..., None], 255 - (255 - face[..., :3]) * 0.38, face[..., :3])
# upper half of each opening: plain transparent skin. It is always hidden by the 3D eyeliner when the eye is open,
# but texture filtering bleeds it onto the skin rim -> it would draw a thin dark/white line over the CLOSED lid
upper = np.zeros((H, W), np.uint8)
for side in 'RL':
    poly = np.array(EYE_PX[side], np.float32)
    m1 = np.zeros((H, W), np.uint8)
    cv2.fillPoly(m1, [np.round(poly * 8).astype(np.int32)], 255, lineType=cv2.LINE_AA, shift=3)
    m1 = cv2.dilate(m1, np.ones((5, 5), np.uint8))
    cols = np.where(m1.any(0))[0]
    for c in cols:
        rows = np.where(m1[:, c] > 0)[0]
        mid = (rows.min() + rows.max()) / 2
        upper[rows[rows < mid], c] = 255
up_s = cv2.remap(cv2.GaussianBlur(upper.astype(np.float32) / 255, (0, 0), 1.0), mx, my, cv2.INTER_LINEAR, borderValue=0)
face[..., 3] *= 1 - np.clip(up_s * 1.5, 0, 1)
atlas[fy:fy + fh, fx:fx + fw] = face

IRIS_COL = {}
# --- iris discs (full ellipse, hidden top rebuilt by mirroring the visible bottom) and sclera cups (iris removed)
inside = (eye_mask > 127).astype(np.uint8)
inner = cv2.erode(inside, np.ones((5, 5), np.uint8))
iris_mask = np.zeros((H, W), np.uint8)
for side in 'RL':
    (cx, cy), (rx, ry) = IRIS_PX[side], IRIS_R_PX[side]
    cv2.ellipse(iris_mask, (int(cx * 8), int(cy * 8)), (int(rx * 8), int(ry * 8)), 0, 0, 360, 255, -1, cv2.LINE_AA, 3)
iris_d = cv2.dilate(iris_mask, np.ones((7, 7), np.uint8))
known_iris = (iris_mask > 127) & (inner > 0)
highlight = known_iris & (g > 150)
known_nohl = known_iris & ~cv2.dilate(highlight.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
for side in 'RL':
    (cx, cy), (rx, ry) = IRIS_PX[side], IRIS_R_PX[side]
    rxr, ryr, rw, rh = iris_rect(side)
    yy, xx = np.mgrid[0:rh, 0:rw]
    a_ = (xx + 0.5) / rw * 2 - 1; b_ = 1 - (yy + 0.5) / rh * 2
    px_ = (cx + a_ * rx).astype(np.float32); py_ = (cy - b_ * ry).astype(np.float32)
    qx = (cx - a_ * rx).astype(np.float32); qy = (cy + b_ * ry).astype(np.float32)      # point reflection
    look = lambda X, Y, m: m[np.clip(np.round(Y).astype(int), 0, H - 1), np.clip(np.round(X).astype(int), 0, W - 1)]
    ok = look(px_, py_, known_nohl); okq = look(qx, qy, known_nohl) & ~ok
    col = np.where(ok[..., None], cv2.remap(im, px_, py_, cv2.INTER_LINEAR),
                   np.where(okq[..., None], cv2.remap(im, qx, qy, cv2.INTER_LINEAR), 0))
    have = (ok | okq).astype(np.uint8)
    if FACE_STYLE == 'girl2':          # the drawn iris is black at the top, under the eyeliner: keep it black
        okq[:] = False; have = ok.astype(np.uint8)
        col = np.where(ok[..., None], col, 0)
        col = np.where((have == 0)[..., None] & (b_ > -0.2)[..., None], 10.0, col); have = np.maximum(have, ((b_ > -0.2)).astype(np.uint8))
    col = cv2.inpaint(np.clip(col, 0, 255).astype(np.uint8), 1 - have, 7, cv2.INPAINT_TELEA).astype(np.float32)
    hl = look(px_, py_, highlight)
    col = np.where(hl[..., None], cv2.remap(im, px_, py_, cv2.INTER_LINEAR), col)
    hlm = hl[..., None]
    col = np.where(hlm, col, np.clip(col * 1.12 + 12, 0, 255))
    atlas[ryr:ryr + rh, rxr:rxr + rw, :3] = col
    atlas[ryr:ryr + rh, rxr:rxr + rw, 3] = 255
    IRIS_COL[side] = col.copy()
np.savez(os.path.join(OUT, 'iris_col.npz'), **IRIS_COL)
if os.environ.get('IRIS_SRC'):
    # the iris drawing comes from another face (the boy's, saved by its own run): its slit pupil and its drawn
    # highlight are painted out (this face draws its own round pupil and highlights)
    _src = np.load(os.environ['IRIS_SRC'])
    for side in 'RL':
        c0 = _src[side].astype(np.float32); ih_, iw_ = c0.shape[:2]
        yy, xx = np.mgrid[0:ih_, 0:iw_]
        a0 = (xx + 0.5) / iw_ * 2 - 1; b0 = 1 - (yy + 0.5) / ih_ * 2
        kill = (((a0 / 0.27) ** 2 + (b0 / 0.76) ** 2) <= 1.0) | (c0.mean(2) > 135)
        if os.environ.get('IRIS_SRC_RAW'): kill[:] = False            # a ready-made iris (girl_iris.py): used as is
        kill = cv2.dilate(kill.astype(np.uint8), np.ones((5, 5), np.uint8))
        c1 = cv2.inpaint(np.clip(c0, 0, 255).astype(np.uint8), kill, 9, cv2.INPAINT_TELEA).astype(np.float32)
        rxr, ryr, rw, rh = iris_rect(side)
        IRIS_COL[side] = cv2.resize(c1, (rw, rh), interpolation=cv2.INTER_CUBIC)

# sclera: exact pixels where visible, row-profile colour elsewhere (behind the iris / outside the opening)
keep = (inside > 0) & (iris_d == 0)
scl = keep & (g > 90)
eye_img = im.copy()
for side in 'RL':
    xs_ = [p[0] for p in EYE_PX[side]]; ys_ = [p[1] for p in EYE_PX[side]]
    X0, X1, Y0, Y1 = int(min(xs_)) - 45, int(max(xs_)) + 45, int(min(ys_)) - 45, int(max(ys_)) + 45
    prof = np.zeros((Y1 - Y0, 3), np.float32); have = np.zeros(Y1 - Y0, bool)
    for y in range(Y0, Y1):
        m = scl[y, X0:X1]
        if m.sum() >= 3:
            prof[y - Y0] = np.median(im[y, X0:X1][m], axis=0); have[y - Y0] = True
    idx = np.arange(Y1 - Y0)
    for c in range(3):
        prof[:, c] = np.interp(idx, idx[have], prof[have, c])
    prof = cv2.GaussianBlur(prof[:, None, :], (1, 0), sigmaX=0, sigmaY=2)[:, 0, :] if False else prof
    fill = np.repeat(prof[:, None, :], X1 - X0, axis=1)
    eye_img[Y0:Y1, X0:X1] = np.where(keep[Y0:Y1, X0:X1, None], im[Y0:Y1, X0:X1], fill)
# deep white: lift the sclera greys of the drawing towards white (keeps the soft lid shadow)
def whiten(v):
    return 255 - (255 - v) * 0.38
sclera_px = keep & (g > 85)
eye_img = np.where(sclera_px[..., None], whiten(eye_img), np.where(keep[..., None], eye_img, whiten(eye_img)))
for side in 'RL':
    x0, x1, z0, z1 = eye_bbox(side)
    rx, ry, rw, rh = cup_rect(side)
    yy, xx = np.mgrid[0:rh, 0:rw]
    xs_ = x0 + (xx + 0.5) / rw * (x1 - x0); zs_ = z1 - (yy + 0.5) / rh * (z1 - z0)
    m_x = (CX + xs_ * SX).astype(np.float32); m_y = (CY - zs_ * SY).astype(np.float32)
    # the sclera is the inside of an inverted eyeball that turns with the gaze: plain deep white, same tone as the
    # socket walls (no drawn line on it that would slide around when the eye moves)
    atlas[ry - 2:ry + rh + 2, rx - 2:rx + rw + 2, :3] = (222, 222, 225)
    atlas[ry - 2:ry + rh + 2, rx - 2:rx + rw + 2, 3] = 255

# --- the eye texture painted on the inside of the eye sphere (front projection): PURE WHITE (no line, no shading in the
#     hole) + the drawn iris (rings, highlight; its top rebuilt) with the PUPIL REMOVED: the pupil is the black 3D ball
#     at the centre of the sphere
SCLERA = np.array((222, 222, 225), np.float32)
_rR, _rL = eye_rect('R'), eye_rect('L')
atlas[_rR[1] - 2:_rR[1] + max(_rR[3], _rL[3]) + 2, _rR[0] - 2:_rL[0] + _rL[2] + 2, :3] = SCLERA   # no dark gap to bleed
atlas[_rR[1] - 2:_rR[1] + max(_rR[3], _rL[3]) + 2, _rR[0] - 2:_rL[0] + _rL[2] + 2, 3] = 255
for side in 'RL':
    x0, x1, z0, z1 = eye_tex_box(side)
    rx, ry, rw, rh = eye_rect(side)
    yy, xx = np.mgrid[0:rh, 0:rw]
    xs_ = x0 + (xx - 1 + 0.5) / (rw - 2) * (x1 - x0); zs_ = z1 - (yy - 1 + 0.5) / (rh - 2) * (z1 - z0)
    tex = np.zeros((rh, rw, 3), np.float32) + SCLERA
    xi, zi, irx, irz = iris_studs(side)
    a_ = (xs_ - xi) / irx; b_ = (zs_ - zi) / irz
    rr = np.sqrt(a_ ** 2 + b_ ** 2)
    icol = IRIS_COL[side]; ih, iw = icol.shape[:2]
    ix = np.clip((a_ + 1) / 2 * iw - 0.5, 0, iw - 1).astype(np.float32); iy = np.clip((1 - b_) / 2 * ih - 0.5, 0, ih - 1).astype(np.float32)
    iris_px = cv2.remap(icol, ix, iy, cv2.INTER_LINEAR)
    ia = np.clip((1.0 - rr) / 0.03, 0, 1)[..., None]                     # soft 1-texel edge
    tex = tex * (1 - ia) + iris_px * ia
    # remove the drawn pupil (the dark vertical lens in the middle), keep the highlight
    lens = ((a_ / PUPIL_AB[0]) ** 2 + (b_ / PUPIL_AB[1]) ** 2) <= 1.0
    if os.environ.get('EYE_STYLE', 'sphere') == 'flat':          # flat eye: the drawn pupil stays (no pupil ball)
        lens[:] = False
    t8 = np.clip(tex, 0, 255).astype(np.uint8)
    t8 = cv2.inpaint(t8, cv2.dilate(lens.astype(np.uint8), np.ones((5, 5), np.uint8)), 9, cv2.INPAINT_TELEA)
    hl_ = (iris_px.mean(2) > 140) & (rr < 1.0)
    t8 = np.where(hl_[..., None], np.clip(iris_px, 0, 255).astype(np.uint8), t8)
    if os.environ.get('EYE_STYLE', 'sphere') == 'flat':
        # flat eye: a paler grey iris (rings kept) and a pure black pupil, so the black hole in the centre stands out
        IRIS_LIGHT = float(os.environ.get('IRIS_LIGHT', 0.6))      # 0 = as drawn; how much paler the bottom gets
        pup = ((a_ / PUPIL_AB[0]) ** 2 + (b_ / PUPIL_AB[1]) ** 2) <= 1.0
        inside = (rr < 1.0) & ~pup & ~hl_
        f8 = t8.astype(np.float32)
        # vertical gradient: the top of the iris stays close to the drawing (dark, under the lid), the bottom gets paler;
        # the drawn rings keep their contrast (a blend towards white, not a flat grey)
        tb = np.clip((1 - b_) / 2, 0, 1)                         # 0 at the top of the iris, 1 at the bottom
        amt = (IRIS_LIGHT * (0.15 + 0.85 * tb ** 1.3))[..., None] * np.ones((1, 1, 3), np.float32)
        f8[inside] = f8[inside] * (1 - amt[inside]) + 235 * amt[inside]
        dark = pup & ~hl_ & (f8.mean(2) < 120)
        f8[dark] = 0
        soft = pup & ~hl_ & ~dark
        f8[soft] = f8[soft] * 0.35
        t8 = np.clip(f8, 0, 255).astype(np.uint8)
    if FACE_STYLE == 'girl2':          # the drawn eye white is shaded grey under the eyeliner
        shade = np.clip((zs_ - (zi - 0.25 * irz)) / (0.9 * irz), 0, 1)[..., None] * (rr >= 1.0)[..., None]
        t8 = np.clip(t8.astype(np.float32) * (1 - 0.30 * shade), 0, 255).astype(np.uint8)
    atlas[ry:ry + rh, rx:rx + rw, :3] = t8
    atlas[ry:ry + rh, rx:rx + rw, 3] = 255

EYE_WHITE = np.array((238, 238, 241), np.float32)
if SRCMAP is not None:
    # the eye painted at the back of the white hole: PURE WHITE everywhere (the hole is white, also on the sides and
    # above the opening) + the drawn iris as a FULL ROUND disc (its part hidden under the eyeliner rebuilt from the
    # visible part: dark at the top, like the drawing).  The iris keeps every drawn detail (heart, sparkles, dots).
    _src = SRCMAP['img']
    _om = np.zeros(_src.shape[:2], np.uint8)
    for side in 'RL':
        _ps = np.array([img2src(*p) for p in EYE_PX[side]], np.float32)
        cv2.fillPoly(_om, [np.round(_ps * 8).astype(np.int32)], 255, cv2.LINE_AA, 3)
    _vis = cv2.erode((_om > 127).astype(np.uint8), np.ones((7, 7), np.uint8))       # surely visible drawing pixels
    _ksx = (GIRL2_SRC['sx1'] - GIRL2_SRC['sx0']) / (GIRL2_SRC['dx1'] - GIRL2_SRC['dx0'])
    for side in 'RL':
        (icx, icy), (irx_, iry_) = IRIS_PX[side], IRIS_R_PX[side]
        scx, scy = img2src(icx, icy); srx, sry = irx_ * _ksx, iry_ * _ksx
        # iris disc in src space: visible pixels kept, hidden ones inpainted (from the dark top rows of the drawing)
        R0 = int(max(srx, sry) + 12)
        x0_, y0_ = int(scx - R0), int(scy - R0)
        crop = _src[y0_:y0_ + 2 * R0, x0_:x0_ + 2 * R0].copy()
        yy_, xx_ = np.mgrid[0:2 * R0, 0:2 * R0]
        aa = (xx_ + x0_ - scx) / srx; bb = (yy_ + y0_ - scy) / sry
        disc = np.sqrt(aa ** 2 + bb ** 2) < 1.2           # (the two light ovals sit on the iris edge)
        known = disc & (_vis[y0_:y0_ + 2 * R0, x0_:x0_ + 2 * R0] > 0)
        fill_m = (disc & ~known).astype(np.uint8)
        # the hidden top of the drawn iris is black (as drawn just under the eyeliner); a soft transition into it
        crop_i = crop.copy()
        crop_i[fill_m > 0] = (13, 11, 15)
        kb = cv2.GaussianBlur(known.astype(np.float32), (0, 0), 2.5)[..., None]
        crop_i = crop * kb + crop_i * (1 - kb) if False else np.where(known[..., None], crop, crop_i)
        _kb = cv2.GaussianBlur(known.astype(np.float32), (0, 0), 3.0)[..., None]       # soft seam drawing -> rebuilt top
        _kb = np.where(known[..., None], np.clip(_kb * 2 - 0.0, 0, 1), 0)
        crop_i = crop * _kb + np.array((13, 11, 15), np.float32) * (1 - _kb)
        x0, x1, z0, z1 = eye_tex_box(side); rx, ry, rw, rh = eye_rect(side)
        yy, xx = np.mgrid[0:rh, 0:rw]
        xs_ = x0 + (xx - 1 + 0.5) / (rw - 2) * (x1 - x0); zs_ = z1 - (yy - 1 + 0.5) / (rh - 2) * (z1 - z0)
        _qx, _qy = src_coords((CX + xs_ * SX), (CY - zs_ * SY))
        col = cv2.remap(crop_i, _qx - x0_, _qy - y0_, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
        ra = np.sqrt(((_qx - scx) / srx) ** 2 + ((_qy - scy) / sry) ** 2)
        ia = np.clip((1.0 - ra) / 0.02, 0, 1)                                       # crisp iris edge
        _vq = cv2.remap(_vis[y0_:y0_ + 2 * R0, x0_:x0_ + 2 * R0].astype(np.float32), _qx - x0_, _qy - y0_, cv2.INTER_LINEAR) > 0.5
        # the two light ovals the drawing puts on the lower iris edge (left and right), redrawn crisp
        _au = (_qx - scx) / srx; _bu = (_qy - scy) / sry
        _ovm = np.zeros_like(ra)
        for _oa, _ob in ((-0.80, 0.60), (0.80, 0.62)):
            _ovm = np.maximum(_ovm, np.clip((1 - np.sqrt(((_au - _oa) / 0.13) ** 2 + ((_bu - _ob) / 0.07) ** 2)) / 0.15, 0, 1))
        col = col * (1 - _ovm[..., None]) + 246 * _ovm[..., None]
        ia = np.maximum(ia, _ovm)
        ia = ia[..., None]
        atlas[ry:ry + rh, rx:rx + rw, :3] = np.clip(EYE_WHITE * (1 - ia) + col * ia, 0, 255)
        atlas[ry:ry + rh, rx:rx + rw, 3] = 255
    _rR, _rL = eye_rect('R'), eye_rect('L')                                          # gap between the two blocks: white
    _g0, _g1 = _rR[0] + _rR[2], _rL[0]
    atlas[_rR[1]:_rR[1] + _rR[3], _g0:_g1, :3] = EYE_WHITE

# --- lids: skin (transparent) with the lash line along the closing edge
for side in 'RL':
    rx, ry, rw, rh = LID_RECT[side]
    for y in range(rh):
        t = (y - 2) / (rh - 4)
        a = np.clip((t - 0.86) / 0.06, 0, 1)
        atlas[ry + y, rx:rx + rw, :3] = INK
        atlas[ry + y, rx:rx + rw, 3] = a * 255
# --- socket walls + mouth interior
for rect, tone in (((WALL_UP_RECT, (238, 238, 241)), (WALL_LO_RECT, (238, 238, 241))) if FACE_STYLE == 'girl2' else
                   ((WALL_UP_RECT, (236, 236, 238)), (WALL_LO_RECT, (222, 222, 225)))):
    x, y, w, h = rect; atlas[y:y + h, x:x + w, :3] = tone; atlas[y:y + h, x:x + w, 3] = 255
x, y, w, h = MOUTH_RECT; atlas[y:y + h, x:x + w] = (46, 20, 24, 255)
x, y, w, h = LASH_RECT; atlas[y:y + h, x:x + w] = (16, 14, 17, 255)
x, y, w, h = LASH_SIDE_RECT; atlas[y:y + h, x:x + w] = (52, 50, 55, 255)
x, y, w, h = CLEAR_RECT; atlas[y:y + h, x:x + w] = (0, 0, 0, 0)
# iris ball: one plain colour = the median of the drawn iris (highlights excluded)
_ball = np.array((0, 0, 0), np.float32)                 # the pupil ball: the deepest black (roughness 1, metal 0, no emission)
x, y, w, h = BALL_RECT; atlas[y:y + h, x:x + w, :3] = _ball; atlas[y:y + h, x:x + w, 3] = 255


fa = atlas[fy:fy + fh, fx:fx + fw]
fa[..., 3] = np.clip(fa[..., 3], 0, 1) * 255
atlas[fy:fy + fh, fx:fx + fw] = fa
os.makedirs(OUT, exist_ok=True)
out = np.clip(atlas, 0, 255).astype(np.uint8)
if FACE_STYLE == 'girl2':
    # the drawn eyeliner + lashes (+ eyeshadow between them) -> LINER_RECT, for the 3D eyeliner's front faces; inside the
    # opening (the eyeliner's lower edge overhangs it a few mm) it is solid ink
    for side in 'RL':
        x0, x1, y0, y1 = liner_box_px(side); rx, ry, rw, rh = LINER_RECT[side]; k = liner_scale(side)
        yy_, xx_ = np.mgrid[0:rh, 0:rw]
        sx_ = (x0 + (xx_ + 0.5) / k).astype(np.float32); sy_ = (y0 + (yy_ + 0.5) / k).astype(np.float32)
        _qx, _qy = src_coords(sx_, sy_)
        a_c = cv2.remap(SRCMAP['a'], _qx, _qy, cv2.INTER_CUBIC, borderValue=0).clip(0, 1) * cv2.remap(cv2.GaussianBlur(head.astype(np.float32), (0, 0), 3), sx_, sy_, cv2.INTER_LINEAR, borderValue=0)
        c_c = cv2.remap(SRCMAP['c'], _qx, _qy, cv2.INTER_LINEAR, borderValue=0)
        e_c = cv2.remap(eye_mask.astype(np.float32) / 255, sx_, sy_, cv2.INTER_LINEAR, borderValue=0)
        c_c = c_c * (1 - e_c[..., None]) + INK * e_c[..., None]; a_c = np.maximum(a_c, e_c)
        atlas[ry:ry + rh, rx:rx + rw, :3] = c_c; atlas[ry:ry + rh, rx:rx + rw, 3] = a_c * 255
    out = np.clip(atlas, 0, 255).astype(np.uint8)
cv2.imwrite(f'{OUT}/HeadTexture.png', cv2.cvtColor(out, cv2.COLOR_RGBA2BGRA))
# SurfaceAppearance companions
# emissive mask: the inside of the eye (sclera, socket walls, iris) glows with its own grey value -> flat "deep white",
# no shading, whatever the lighting. skin + ink = 0.
emis = np.zeros((ATLAS, ATLAS), np.float32)
lum = out[..., :3].astype(np.float32).mean(2)
def mark(rect):
    x, y, w, h = rect[:4]
    l_ = lum[y - 2:y + h + 2, x - 2:x + w + 2]
    # whites fully emissive (one flat deep white whatever the surface angle: sphere and socket walls match);
    # darks keep their (low) value: the iris / pupil stay deep black, no glow
    emis[y - 2:y + h + 2, x - 2:x + w + 2] = np.where(l_ > 150, 255, l_)
for side in 'RL':
    mark(cup_rect(side)); mark(iris_rect(side))
mark(WALL_UP_RECT); mark(WALL_LO_RECT); mark(BALL_RECT)
for side in 'RL':
    # the eye texture (white + drawn iris) is FULLY emissive: shown flat exactly as drawn, it does not react to the
    # light at all (no shading, no reflection).  The pupil ball (BALL_RECT) stays at 0: the deepest black.
    x, y, w, h = eye_rect(side)
    emis[y - 2:y + h + 2, x - 2:x + w + 2] = 255
# the eye pixels kept on the face block around the rim (opaque image pixels inside the dilated opening)
fem = cv2.remap(cv2.dilate(eye_mask, np.ones((5, 5), np.uint8)).astype(np.float32) / 255, mx, my, cv2.INTER_LINEAR)
fl = lum[fy:fy + fh, fx:fx + fw]
emis[fy:fy + fh, fx:fx + fw] = np.maximum(emis[fy:fy + fh, fx:fx + fw], fl * fem * (fl > 90))
cv2.imwrite(f'{OUT}/HeadTexture_Emissive.png', np.clip(emis, 0, 255).astype(np.uint8))
# roughness: 1 (no reflection) on everything opaque (eye interior, ink, eyeliner); skin 0.6
a = out[..., 3].astype(np.float32) / 255
rough = (0.6 * (1 - a) + 1.0 * a) * 255
if FACE_STYLE == 'girl2':                              # the drawn 3D eyeliner: fully matte
    for _r in LINER_RECT.values():
        rough[_r[1]:_r[1] + _r[3], _r[0]:_r[0] + _r[2]] = 255
cv2.imwrite(f'{OUT}/HeadTexture_Roughness.png', np.clip(rough, 0, 255).astype(np.uint8))
# metalness: 0 everywhere except the PUPIL (white = metal): the 3D black ball (style 'sphere') or the drawn pupil oval
# (style 'flat'); a black metal reflects (almost) nothing straight on -> the deepest black
_metal = np.zeros((ATLAS, ATLAS), np.uint8)
if os.environ.get('EYE_STYLE', 'sphere') == 'flat':
    # flat style: the WHOLE eye (drawn eye + the white hole walls) is white = metal
    for side in 'RL':
        rx, ry, rw, rh = eye_rect(side); _metal[ry:ry + rh, rx:rx + rw] = 255
    for rect in (WALL_UP_RECT, WALL_LO_RECT):
        x, y, w, h = rect; _metal[y:y + h, x:x + w] = 255
    _metal_pupil_only = np.zeros_like(_metal)
    for side in 'RL':
        x0, x1, z0, z1 = eye_tex_box(side); rx, ry, rw, rh = eye_rect(side)
        yy, xx = np.mgrid[0:rh, 0:rw]
        xs_ = x0 + (xx - 1 + 0.5) / (rw - 2) * (x1 - x0); zs_ = z1 - (yy - 1 + 0.5) / (rh - 2) * (z1 - z0)
        xi, zi, irx, irz = iris_studs(side)
        lens = (((xs_ - xi) / irx / PUPIL_AB[0]) ** 2 + ((zs_ - zi) / irz / PUPIL_AB[1]) ** 2) <= 1.0
        lens &= atlas[ry:ry + rh, rx:rx + rw, :3].mean(2) < 140          # not the white highlight
        _metal_pupil_only[ry:ry + rh, rx:rx + rw][lens] = 255
    cv2.imwrite(f'{OUT}/HeadTexture_Metalness_PupilleSeule.png', _metal_pupil_only)
else:
    x, y, w, h = BALL_RECT; _metal[y:y + h, x:x + w] = 255
cv2.imwrite(f'{OUT}/HeadTexture_Metalness.png', _metal)
cv2.imwrite(f'{OUT}/HeadTexture_Normal.png', np.full((ATLAS, ATLAS, 3), (255, 128, 128), np.uint8))   # BGR of (128,128,255)

# --- mouth centre line (studs) from the ink
mouth = []
for px in range(470, 600):
    col = alpha[735:790, px]
    if col.max() > 0.35:
        w_ = col ** 2
        py = 735 + (w_ * np.arange(len(col))).sum() / w_.sum()
        mouth.append(img2stud(px + 0.5, py))
data = dict(mouth=mouth)
json.dump(data, open(f'{OUT}/face_data.json', 'w'), indent=1)
print('mouth pts', len(mouth), 'x', round(mouth[0][0], 3), round(mouth[-1][0], 3), 'z', round(min(m[1] for m in mouth), 3), round(max(m[1] for m in mouth), 3))

# preview of the ink layer on a few skin colours
prev = []
for col in [(150, 150, 150), (234, 184, 146), (124, 84, 62)]:
    bg = np.ones((fh, fw, 3), np.float32) * col
    a = atlas[fy:fy + fh, fx:fx + fw, 3:] / 255
    prev.append(bg * (1 - a) + atlas[fy:fy + fh, fx:fx + fw, :3] * a)
cv2.imwrite(f'{OUT}/dbg_face_layer.png', cv2.cvtColor(np.clip(np.vstack(prev), 0, 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
