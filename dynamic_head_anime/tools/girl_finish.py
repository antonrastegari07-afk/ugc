"""Girl face texture finishing: iris highlights (classic: a big glossy one + a small one; or heart) and cheek blush.
usage: FACE_STYLE=girl python girl_finish.py IN.png OUT.png classic|heart 0|1"""
import os, sys
os.environ['FACE_STYLE'] = 'girl'
import numpy as np, cv2
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layout import *

SRC, DST, HL, BLUSH = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == '1'
img = np.array(Image.open(SRC).convert('RGBA')).astype(np.float32)
SS = 4


def heart(a, b, cx, cy, s):
    """inside of a heart shape centred (cx, cy), size s (iris units), point down"""
    x = (a - cx) / s; y = (b - cy) / s + 0.25
    return (x * x + y * y - 0.3) ** 3 - x * x * y ** 3 * 1.0 <= 0


for side in 'RL':
    x0, x1, z0, z1 = eye_tex_box(side); rx, ry, rw, rh = eye_rect(side)
    yy, xx = np.mgrid[0:rh * SS, 0:rw * SS]
    xs_ = x0 + ((xx + 0.5) / SS - 1) / (rw - 2) * (x1 - x0); zs_ = z1 - ((yy + 0.5) / SS - 1) / (rh - 2) * (z1 - z0)
    xi, zi, irx, irz = iris_studs(side)
    a_ = (xs_ - xi) / irx; b_ = (zs_ - zi) / irz
    rr = np.sqrt(a_ ** 2 + b_ ** 2)
    if HL == 'heart':
        m = heart(a_, b_, -0.30, 0.30, 0.34)
    else:
        m = ((a_ + 0.30) / 0.25) ** 2 + ((b_ - 0.34) / 0.21) ** 2 <= 1.0
    m |= ((a_ - 0.34) / 0.10) ** 2 + ((b_ + 0.40) / 0.10) ** 2 <= 1.0          # the small second highlight
    m &= rr < 0.97
    cov = cv2.resize(m.astype(np.float32), (rw, rh), interpolation=cv2.INTER_AREA)[..., None]
    blk = img[ry:ry + rh, rx:rx + rw, :3]
    img[ry:ry + rh, rx:rx + rw, :3] = blk * (1 - cov) + 248 * cov

if BLUSH:
    fx, fy, fw, fh = FACE_RECT
    ys, xs = np.mgrid[0:fh, 0:fw]
    xst = FACE_X[0] + (xs + 0.5) / fw * (FACE_X[1] - FACE_X[0])
    zst = FACE_Z[0] + (ys + 0.5) / fh * (FACE_Z[1] - FACE_Z[0])
    px = CX + xst * SX; py = CY - zst * SY                     # image px of every face texel
    b = np.zeros((fh, fw), np.float32)
    for cxp in (GIRL['irx'] - 8, 2 * CX - (GIRL['irx'] - 8)):
        d = ((px - cxp) / 50.0) ** 2 + ((py - 662) / 19.0) ** 2
        b = np.maximum(b, np.exp(-d * 1.6))
    b = 0.42 * np.clip(b, 0, 1)
    pink = np.array((255, 128, 150), np.float32)
    blk = img[fy:fy + fh, fx:fx + fw]
    a = blk[..., 3] / 255.0
    na = a + b * (1 - a)
    col = (blk[..., :3] * a[..., None] + pink * (b * (1 - a))[..., None]) / np.maximum(na, 1e-6)[..., None]
    blk[..., :3] = np.where(na[..., None] > 0, col, blk[..., :3]); blk[..., 3] = na * 255
    img[fy:fy + fh, fx:fx + fw] = blk

Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGBA').save(DST)
print('saved', DST)
