"""Coloured-eye variants of a head texture (same layout, same FBX): the iris gets a colour ramp (dark at the top under the
lid -> bright, almost white at the bottom, rings kept), the pupil stays black, the highlight stays white.
usage: python colorize_eyes.py HeadTexture.png OUT_DIR"""
import os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layout import *

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
base = np.array(Image.open(SRC).convert('RGBA')).astype(np.float32)

COLORS = {                    # name: iris colour (RGB)
    'Rouge': (235, 45, 30), 'BleuGlace': (90, 170, 255), 'Violet': (160, 70, 255), 'Vert': (40, 220, 90),
    'Or': (255, 185, 30), 'Rose': (255, 90, 190), 'Cyan': (20, 230, 240), 'Orange': (255, 120, 20),
}
DARK_SCLERA = {'Rouge', 'Violet', 'Vert', 'Cyan'}           # these also get a dark-white version (like the red example)


def masks(side):
    x0, x1, z0, z1 = eye_tex_box(side); rx, ry, rw, rh = eye_rect(side)
    yy, xx = np.mgrid[0:rh, 0:rw]
    xs_ = x0 + (xx - 1 + 0.5) / (rw - 2) * (x1 - x0); zs_ = z1 - (yy - 1 + 0.5) / (rh - 2) * (z1 - z0)
    xi, zi, irx, irz = iris_studs(side)
    a_ = (xs_ - xi) / irx; b_ = (zs_ - zi) / irz
    rr = np.sqrt(a_ ** 2 + b_ ** 2)
    return (rx, ry, rw, rh), a_, b_, rr


def make(color, dark_sclera):
    img = base.copy()
    c = np.array(color, np.float32)
    for side in 'RL':
        (rx, ry, rw, rh), a_, b_, rr = masks(side)
        blk = img[ry:ry + rh, rx:rx + rw, :3]
        lum = blk.mean(2) / 255.0
        pup = ((a_ / PUPIL_AB[0]) ** 2 + (b_ / PUPIL_AB[1]) ** 2) <= 1.0
        hl = (lum > 0.62) & (rr < 1.0) & ~(rr > 0.97)        # the drawn white highlight inside the iris
        hl &= ((a_ / 0.45) ** 2 + (b_ / 0.45) ** 2) <= 1.0
        iris = (rr < 1.0) & ~pup & ~hl
        # brightness of the drawn (gradient) iris -> colour ramp: dark tinted -> colour -> light tint (a glowing core)
        t = np.clip((lum - 0.25) / 0.6, 0, 1)
        tb = np.clip((1 - b_) / 2, 0, 1)                    # 0 top .. 1 bottom: brighter towards the bottom
        t = np.clip(0.55 * t + 0.55 * tb ** 1.2, 0, 1)
        dark = c * 0.18; light = c * 0.35 + 255 * 0.65
        col = np.where((t < 0.5)[..., None], dark + (c - dark) * (t / 0.5)[..., None],
                       c + (light - c) * ((t - 0.5) / 0.5)[..., None])
        edge = np.clip((rr - 0.86) / 0.14, 0, 1)[..., None]  # darker rim around the iris
        col = col * (1 - 0.55 * edge)
        out = blk.copy()
        out[iris] = col[iris]
        out[pup & ~hl] = 0
        if dark_sclera:                                      # dark eye white, slightly tinted
            sc = ~(rr < 1.0)
            out[sc] = np.array((26, 20, 24), np.float32) + c * 0.05
            soft = (rr >= 1.0) & (rr < 1.12)                 # a faint glow of the colour around the iris
            g = np.clip(1 - (rr - 1.0) / 0.12, 0, 1)[..., None]
            out[soft] = (out * (1 - 0.5 * g) + c * 0.5 * g)[soft]
        img[ry:ry + rh, rx:rx + rw, :3] = out
    if dark_sclera:                                          # the walls of the hole and the gap between the eye blocks too
        dk = np.array((26, 20, 24), np.float32) + c * 0.05
        for rect in (WALL_UP_RECT, WALL_LO_RECT):
            x, y, w, h = rect; img[y:y + h, x:x + w, :3] = dk
        (rxa, rya, rwa, rha) = eye_rect('R'); (rxb, ryb, rwb, rhb) = eye_rect('L')
        img[rya - 2:rya + max(rha, rhb) + 2, rxa - 2:rxb + rwb + 2, :3] = np.where(
            img[rya - 2:rya + max(rha, rhb) + 2, rxa - 2:rxb + rwb + 2, :3].mean(2, keepdims=True) > 200, dk,
            img[rya - 2:rya + max(rha, rhb) + 2, rxa - 2:rxb + rwb + 2, :3])
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGBA')


names = []
for name, col in COLORS.items():
    make(col, False).save(os.path.join(OUT, f'HeadTexture_Yeux{name}.png')); names.append(f'Yeux{name}')
    if name in DARK_SCLERA:
        make(col, True).save(os.path.join(OUT, f'HeadTexture_Yeux{name}_BlancSombre.png')); names.append(f'Yeux{name}_BlancSombre')
print('variants', len(names), names)
