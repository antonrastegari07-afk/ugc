"""Progressive vertical gradient on the iris of a head texture (same layout / FBX): darker at the top, gradually lighter
towards the bottom, over the whole height of the iris; rings, black pupil and highlight kept.
usage: python iris_gradient.py IN.png OUT.png [DARKEN_TOP=0.35] [LIGHTEN_BOTTOM=0.55]"""
import os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layout import *

SRC, DST = sys.argv[1], sys.argv[2]
DK = float(sys.argv[3]) if len(sys.argv) > 3 else 0.35
LT = float(sys.argv[4]) if len(sys.argv) > 4 else 0.55
PW = float(sys.argv[5]) if len(sys.argv) > 5 else 1.15     # higher = the pale part starts lower
img = np.array(Image.open(SRC).convert('RGBA')).astype(np.float32)
for side in 'RL':
    x0, x1, z0, z1 = eye_tex_box(side); rx, ry, rw, rh = eye_rect(side)
    yy, xx = np.mgrid[0:rh, 0:rw]
    xs_ = x0 + (xx - 1 + 0.5) / (rw - 2) * (x1 - x0); zs_ = z1 - (yy - 1 + 0.5) / (rh - 2) * (z1 - z0)
    xi, zi, irx, irz = iris_studs(side)
    a_ = (xs_ - xi) / irx; b_ = (zs_ - zi) / irz
    rr = np.sqrt(a_ ** 2 + b_ ** 2)
    blk = img[ry:ry + rh, rx:rx + rw, :3]
    lum = blk.mean(2)
    pup = ((a_ / 0.24) ** 2 + (b_ / 0.70) ** 2) <= 1.0
    hl = (lum > 150) & (rr < 0.6)
    iris = (rr < 1.0) & ~pup & ~hl
    t = np.clip((1 - b_) / 2, 0, 1)                     # 0 at the top of the iris -> 1 at the bottom
    t = t * t * (3 - 2 * t)                             # smooth, progressive
    out = blk * (1 - DK * (1 - t))[..., None]           # darker towards the top
    out = out + (235 - out) * (LT * t ** PW)[..., None]     # lighter towards the bottom
    blk[iris] = out[iris]
    img[ry:ry + rh, rx:rx + rw, :3] = blk
Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGBA').save(DST)
print('saved', DST)
