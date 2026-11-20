"""Build the 1024 texture atlas + face data (mouth line, brows) from the reference face image."""
import cv2, numpy as np, json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from layout import *

SRC, OUT = sys.argv[1], sys.argv[2]
im = cv2.cvtColor(cv2.imread(SRC), cv2.COLOR_BGR2RGB).astype(np.float32)
H, W, _ = im.shape
g = im.mean(2)

# eye opening masks (image space)
eye_mask = np.zeros((H, W), np.uint8)
for side in 'RL':
    cv2.fillPoly(eye_mask, [np.round(np.array(EYE_PX[side]) * 8).astype(np.int32)], 255, lineType=cv2.LINE_AA, shift=3)

# --- skin estimate: inpaint everything that is darker than the local skin, plus the eyes
blur = cv2.GaussianBlur(g, (0, 0), 25)
feat = ((g < blur - 6) | (eye_mask > 0)).astype(np.uint8)
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
INK = np.array([14, 12, 15], np.float32)
# the upper eyeliner is real 3D geometry (it moves down when the eye closes): remove its ink from the face layer
lash_mask = np.zeros((H, W), np.uint8)
for side in 'RL':
    cv2.fillPoly(lash_mask, [np.round(np.array(LASH_PX[side]) * 8).astype(np.int32)], 255, lineType=cv2.LINE_AA, shift=3)
lash_mask = cv2.dilate(lash_mask, np.ones((7, 7), np.uint8))
alpha *= 1 - cv2.GaussianBlur(lash_mask.astype(np.float32) / 255, (0, 0), 1.0)

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
face[..., :3] = INK
face[..., 3] = a_s
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
    col = cv2.inpaint(np.clip(col, 0, 255).astype(np.uint8), 1 - have, 7, cv2.INPAINT_TELEA).astype(np.float32)
    hl = look(px_, py_, highlight)
    col = np.where(hl[..., None], cv2.remap(im, px_, py_, cv2.INTER_LINEAR), col)
    hlm = hl[..., None]
    col = np.where(hlm, col, np.clip(col * 1.12 + 12, 0, 255))
    atlas[ryr:ryr + rh, rxr:rxr + rw, :3] = col
    atlas[ryr:ryr + rh, rxr:rxr + rw, 3] = 255

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

# --- lids: skin (transparent) with the lash line along the closing edge
for side in 'RL':
    rx, ry, rw, rh = LID_RECT[side]
    for y in range(rh):
        t = (y - 2) / (rh - 4)
        a = np.clip((t - 0.86) / 0.06, 0, 1)
        atlas[ry + y, rx:rx + rw, :3] = INK
        atlas[ry + y, rx:rx + rw, 3] = a * 255
# --- socket walls + mouth interior
for rect, tone in ((WALL_UP_RECT, (236, 236, 238)), (WALL_LO_RECT, (222, 222, 225))):
    x, y, w, h = rect; atlas[y:y + h, x:x + w, :3] = tone; atlas[y:y + h, x:x + w, 3] = 255
x, y, w, h = MOUTH_RECT; atlas[y:y + h, x:x + w] = (46, 20, 24, 255)
x, y, w, h = LASH_RECT; atlas[y:y + h, x:x + w] = (16, 14, 17, 255)
x, y, w, h = LASH_SIDE_RECT; atlas[y:y + h, x:x + w] = (52, 50, 55, 255)
x, y, w, h = CLEAR_RECT; atlas[y:y + h, x:x + w] = (0, 0, 0, 0)

fa = atlas[fy:fy + fh, fx:fx + fw]
fa[..., 3] = np.clip(fa[..., 3], 0, 1) * 255
atlas[fy:fy + fh, fx:fx + fw] = fa
os.makedirs(OUT, exist_ok=True)
out = np.clip(atlas, 0, 255).astype(np.uint8)
cv2.imwrite(f'{OUT}/HeadTexture.png', cv2.cvtColor(out, cv2.COLOR_RGBA2BGRA))
# SurfaceAppearance companions
# emissive mask: the inside of the eye (sclera, socket walls, iris) glows with its own grey value -> flat "deep white",
# no shading, whatever the lighting. skin + ink = 0.
emis = np.zeros((ATLAS, ATLAS), np.float32)
lum = out[..., :3].astype(np.float32).mean(2)
def mark(rect):
    x, y, w, h = rect[:4]
    emis[y - 2:y + h + 2, x - 2:x + w + 2] = lum[y - 2:y + h + 2, x - 2:x + w + 2]
for side in 'RL':
    mark(cup_rect(side)); mark(iris_rect(side))
mark(WALL_UP_RECT); mark(WALL_LO_RECT)
# the eye pixels kept on the face block around the rim (opaque image pixels inside the dilated opening)
fem = cv2.remap(cv2.dilate(eye_mask, np.ones((5, 5), np.uint8)).astype(np.float32) / 255, mx, my, cv2.INTER_LINEAR)
fl = lum[fy:fy + fh, fx:fx + fw]
emis[fy:fy + fh, fx:fx + fw] = np.maximum(emis[fy:fy + fh, fx:fx + fw], fl * fem * (fl > 90))
cv2.imwrite(f'{OUT}/HeadTexture_Emissive.png', np.clip(emis, 0, 255).astype(np.uint8))
# roughness: 1 (no reflection) on everything opaque (eye interior, ink, eyeliner); skin 0.6
a = out[..., 3].astype(np.float32) / 255
rough = (0.6 * (1 - a) + 1.0 * a) * 255
cv2.imwrite(f'{OUT}/HeadTexture_Roughness.png', np.clip(rough, 0, 255).astype(np.uint8))
cv2.imwrite(f'{OUT}/HeadTexture_Metalness.png', np.zeros((ATLAS, ATLAS), np.uint8))
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
