"""Sharper, more detailed iris on a head texture (same layout, same FBX): unsharp mask on the drawn iris, fine radial
fibres, a crisp dark limbal ring, a light collarette around the pupil, a clean pupil edge and a crisp highlight.
usage: python enhance_iris.py IN.png OUT.png"""
import os, sys
import numpy as np
import cv2
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layout import *

SRC, DST = sys.argv[1], sys.argv[2]
img = np.array(Image.open(SRC).convert('RGBA')).astype(np.float32)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


for side in 'RL':
    x0, x1, z0, z1 = eye_tex_box(side); rx, ry, rw, rh = eye_rect(side)
    yy, xx = np.mgrid[0:rh, 0:rw]
    xs_ = x0 + (xx - 1 + 0.5) / (rw - 2) * (x1 - x0); zs_ = z1 - (yy - 1 + 0.5) / (rh - 2) * (z1 - z0)
    xi, zi, irx, irz = iris_studs(side)
    a_ = (xs_ - xi) / irx; b_ = (zs_ - zi) / irz
    rr = np.sqrt(a_ ** 2 + b_ ** 2)
    th = np.arctan2(b_, a_)
    dl = np.sqrt((a_ / PUPIL_AB[0]) ** 2 + (b_ / PUPIL_AB[1]) ** 2)                 # pupil lens distance (1 = its edge)
    blk = img[ry:ry + rh, rx:rx + rw, :3].copy()
    lum = blk.mean(2)
    hl = (lum > 150) & (rr < 0.6) & (dl > 0.2)                       # the drawn highlight (kept crisp)
    hl |= (lum > 150) & (rr < 0.6) & (dl <= 1.0)
    iris = rr < 1.0
    # 1) unsharp mask: the drawn rings and shading come out
    blur = cv2.GaussianBlur(blk, (0, 0), 2.2)
    sharp = blk + 1.3 * (blk - blur)
    # 2) fine radial fibres, strongest in the middle of the iris
    fib = np.sin(th * 56 + 2.5 * np.sin(th * 9) + rr * 6) * 0.5 + np.sin(th * 23 + 1.7) * 0.5
    band = sstep(0.32, 0.5, rr) * (1 - sstep(0.82, 0.95, rr))
    sharp *= (1 + 0.09 * fib * band)[..., None]
    # 3) crisp dark limbal ring
    sharp *= (1 - 0.55 * sstep(0.86, 0.97, rr))[..., None]
    # 4) light collarette around the pupil
    coll = sstep(0.98, 1.08, dl) * (1 - sstep(1.12, 1.45, dl))
    sharp = sharp + (255 - sharp) * (0.22 * coll)[..., None]
    out = blk.copy()
    out[iris] = sharp[iris]
    # 5) clean, anti-aliased pupil edge (pure black inside)
    pa = 1 - sstep(0.96, 1.02, dl)
    out = out * (1 - pa[..., None])
    # 6) crisp highlight back on top
    out[hl] = np.maximum(out[hl], 238)
    # soft 1-texel edge between the iris and the white
    e = sstep(0.985, 1.01, rr)[..., None]
    out = out * (1 - e) + blk * e
    img[ry:ry + rh, rx:rx + rw, :3] = np.clip(out, 0, 255)

Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGBA').save(DST)
print('saved', DST)
