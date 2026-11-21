"""Procedural girl iris (its own design, not the boy's drawn rings): very dark at the top (under the lid), a smooth
gradient to a soft light grey at the bottom, a darker rim, a big soft pupil, a faint light crescent at the bottom and
very subtle radial streaks.  Saved as iris_col.npz (same format extract_face.py loads with IRIS_SRC + IRIS_SRC_RAW=1).
usage: python girl_iris.py OUT.npz"""
import sys
import numpy as np, cv2

N = 512
yy, xx = np.mgrid[0:N, 0:N]
a = (xx + 0.5) / N * 2 - 1; b = 1 - (yy + 0.5) / N * 2      # iris units, b up
r = np.sqrt(a * a + b * b); th = np.arctan2(b, a)


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)


top, bot = np.array((14, 12, 17), np.float32), np.array((150, 146, 158), np.float32)
t = ss(0.25, -0.85, b)                                       # 0 at the upper part -> 1 at the bottom
col = top * (1 - t[..., None]) + bot * t[..., None]
col *= (1 - 0.10 * (np.sin(th * 40) * 0.5 + 0.5) * ss(0.45, 0.8, r) * (1 - ss(0.86, 0.95, r)))[..., None]   # streaks
cres = ss(0.55, 0.78, r) * (1 - ss(0.82, 0.93, r)) * ss(-0.2, -0.7, b) * ss(0.75, 0.2, np.abs(a))
col = col + (225 - col) * (0.35 * cres)[..., None]           # soft light crescent at the bottom
col *= (1 - 0.65 * ss(0.84, 0.99, r))[..., None]             # dark rim
pd = np.sqrt((a / 0.40) ** 2 + (b / 0.46) ** 2)
col *= (1 - 0.92 * (1 - ss(0.85, 1.15, pd)))[..., None]      # big soft pupil (forced pure black inside by extract_face)
col = cv2.GaussianBlur(col, (0, 0), 1.2)
out = {s: np.clip(col, 0, 255).astype(np.float32) for s in 'RL'}
np.savez(sys.argv[1], **out)
cv2.imwrite(sys.argv[1].replace('.npz', '_preview.png'), cv2.cvtColor(np.clip(col, 0, 255).astype(np.uint8), cv2.COLOR_RGB2BGR))
print('saved', sys.argv[1])
