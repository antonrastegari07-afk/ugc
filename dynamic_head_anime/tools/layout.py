"""Shared constants: reference-image mapping, traced eye openings, texture atlas layout.
Units: studs. Blender axes: +X = character's left (screen right in front view), -Y = front, +Z = up."""
ATLAS = 1024
# --- reference image (in/face_ref.webp) -> studs (front orthographic)
IMG_X0, IMG_X1, IMG_Y0, IMG_Y1 = 175.0, 889.0, 170.0, 880.0
HEAD_W, HEAD_H = 1.228, 1.252          # white face mask base mesh size (studs)
SX = (IMG_X1 - IMG_X0) / HEAD_W
SY = (IMG_Y1 - IMG_Y0) / HEAD_H
CX, CY = (IMG_X0 + IMG_X1) / 2, (IMG_Y0 + IMG_Y1) / 2
def img2stud(px, py):
    return ((px - CX) / SX, (CY - py) / SY)
def stud2img(x, z):
    return (CX + x * SX, CY - z * SY)

# --- eye openings traced on the reference (image px, clockwise). R = character's right eye (screen left)
EYE_PX = {
 'R': [(255, 561), (270, 560), (300, 559), (329, 558.5), (360, 558.5), (390, 559), (420, 559), (440, 560),
       (447, 562), (449, 575), (448, 590), (444, 600), (436, 609), (428, 614), (400, 615.5), (370, 615.8),
       (340, 616), (310, 616.5), (292, 615.5), (282, 607), (273, 595), (265, 584), (259, 572)],
 'L': [(623, 572), (628, 566), (636, 561), (650, 559), (680, 559), (710, 559), (740, 558.5), (770, 558.5),
       (800, 559), (812, 561), (806, 575), (798, 587), (790, 599), (780, 608), (770, 613), (760, 615),
       (730, 615.8), (700, 616), (670, 615.8), (650, 615), (640, 611), (632, 604), (626, 594), (623, 584)],
}
IRIS_PX = {'R': (389.5, 556.0), 'L': (680.5, 556.0)}   # round iris centres (image px); top part hidden under the lid
IRIS_R_PX = {'R': (59.5, 58.0), 'L': (58.5, 57.0)}      # radii (image px) -> ~0.102 stud circle

# --- face style: 'boy' (the traced drawing, default) or 'girl' (a generated face built on the same model)
import os as _os, math as _m
FACE_STYLE = _os.environ.get('FACE_STYLE', 'boy')
PUPIL_AB = (0.24, 0.70)                # drawn pupil: a vertical slit (fraction of the iris radii)
BROW_PX = {'R': ((490, 497), (240, 468))}   # (inner, outer) brow ends, image px
# soft, calm, slightly half-lidded eyes (like the references): wider than tall, an almost flat gently arched upper lid
# that covers the top of the iris, the iris touching both lids
GIRL = dict(ox=268, oy=588, ix=446, iy=590, top=31, bot=29, irx=360, iry=594, irr=(46, 48))
def girl_eye_chains(n=14):
    """girl right eye (screen left): (top chain outer->inner, bottom chain inner->outer) in image px"""
    g = GIRL; top = []; bot = []
    for k in range(n + 1):
        u = -1 + 2 * k / n
        x = g['ox'] + (g['ix'] - g['ox']) * (u + 1) / 2
        base = g['oy'] + (g['iy'] - g['oy']) * (u + 1) / 2
        ib = ((u + 1) / 2) ** 4 * 8.0                      # blunt inner corner: a short vertical edge (no thin point)
        top.append((x, base - g['top'] * max(0.0, 1 - abs(u) ** 3.0) ** 0.45 * (1 - 0.10 * u) - ib))
        bot.append((x, base + g['bot'] * max(0.0, 1 - abs(u) ** 2.2) ** 0.6 + ib))
    return top, bot[::-1][:-1]
if FACE_STYLE == 'girl':
    _t, _b = girl_eye_chains()
    EYE_PX['R'] = _t + _b
    IRIS_PX['R'] = (GIRL['irx'], GIRL['iry']); IRIS_R_PX['R'] = GIRL['irr']
    PUPIL_AB = (0.40, 0.46)            # big soft round pupil
    BROW_PX = {'R': ((470, 503), (286, 496))}

GIRL2_EYE = [(258, 606), (275, 588), (295, 572), (316, 558), (350, 557), (390, 557), (425, 559), (440, 566), (450, 585),
             (458, 602), (458, 625), (455, 645), (420, 650), (380, 651), (340, 651), (305, 650), (285, 636), (270, 622)]
GIRL2_LASH = [(250, 585), (252, 566), (270, 549), (300, 539), (350, 535), (395, 536), (420, 541), (442, 553), (460, 574),
              (474, 598), (458, 601), (448, 585), (436, 566), (420, 559), (380, 557), (340, 557), (316, 558), (290, 578),
              (270, 596), (258, 606)]
if FACE_STYLE == 'girl2':              # the user's own girl drawing (in/face_ref2.png), traced
    EYE_PX['R'] = GIRL2_EYE
    IRIS_PX['R'] = (377, 582); IRIS_R_PX['R'] = (71, 70)
    PUPIL_AB = (0.15, 0.60)            # the drawn pupil: a thin vertical slit
    BROW_PX = {'R': ((455, 457), (255, 473))}
# SYMMETRIC EYES: the character's RIGHT eye + brow (screen left) is the reference; the left one is its mirror image
# about the face centre (CX), both in the drawing (extract_face mirrors the image band MIRROR_ROWS) and in all the
# traced shapes below
MIRROR_EYES = True
MIRROR_ROWS = (300, 728)               # image rows mirrored (brows -> lower lashes), feathered
def _mirror_poly(poly): return [(2 * CX - x, y) for x, y in reversed(poly)]
if MIRROR_EYES:
    EYE_PX['L'] = _mirror_poly(EYE_PX['R'])
    IRIS_PX['L'] = (2 * CX - IRIS_PX['R'][0], IRIS_PX['R'][1]); IRIS_R_PX['L'] = IRIS_R_PX['R']

# raised (3D) upper eyeliner band, traced on the reference (image px)
LASH_PX = {
 'R': [(196, 539), (215, 540), (240, 538), (262, 535), (282, 533), (310, 534), (340, 535.5), (370, 538), (390, 541),
       (415, 545), (440, 550), (460, 557), (482, 570), (463, 566), (449, 562), (440, 560), (420, 559), (390, 559),
       (360, 558.5), (329, 558.5), (300, 559), (270, 560), (255, 561), (232, 553)],
 'L': [(585, 572.5), (605, 563), (630, 552.5), (650, 548), (670, 544), (695, 542), (720, 540), (745, 538), (770, 536),
       (785, 534.5), (820, 534), (850, 533.5), (872.5, 533), (845, 545), (812, 561), (800, 559), (770, 558.5),
       (740, 558.5), (710, 559), (680, 559), (650, 559), (636, 561), (628, 566), (623, 572), (605, 575)],
}
def girl_lash_poly():
    """thick rounded girl eyeliner: the eye's top chain, offset upwards (thin at the inner end, thick at the outer end)
    with a lifted wing past the outer corner"""
    top, _ = girl_eye_chains()
    up = []
    for i, (x, y) in enumerate(top):
        u = -1 + 2 * i / (len(top) - 1)                    # -1 outer .. 1 inner
        th = 6 + 13 * (1 - (u + 1) / 2) ** 0.8             # 19 px at the outer end -> 6 px at the inner end
        up.append((x, y - th))
    wing = [(240, 562), (252, 572)]
    return [wing[0]] + up + [(top[-1][0] + 6, top[-1][1] + 1)] + top[::-1] + [wing[1]]
if FACE_STYLE == 'girl':
    LASH_PX['R'] = girl_lash_poly()
if FACE_STYLE == 'girl2':
    LASH_PX['R'] = GIRL2_LASH
    _lj = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), '..', 'in', 'girl2_lash.json')
    if _os.path.exists(_lj):                 # traced from the drawing (trace_liner.py): liner + lashes + wing
        import json as _json
        LASH_PX['R'] = [tuple(p) for p in _json.load(open(_lj))['R']]
if MIRROR_EYES:
    LASH_PX['L'] = _mirror_poly(LASH_PX['R'])
# the 3D eyeliner is shorter than the drawn one: the part beyond the eye opening (the wing / the inner tip) keeps only
# LASH_K of its length.  The texture still erases the WHOLE drawn eyeliner (LASH_PX_FULL), so nothing is left painted.
LASH_K = 1.0 if FACE_STYLE != 'boy' else 0.5
LASH_PX_FULL = LASH_PX
def _shorten(poly, eye):
    ex0, ex1 = min(p[0] for p in eye), max(p[0] for p in eye)
    return [(ex0 - (ex0 - x) * LASH_K if x < ex0 else ex1 + (x - ex1) * LASH_K if x > ex1 else x, y) for x, y in poly]
LASH_PX = {sd: _shorten(LASH_PX_FULL[sd], EYE_PX[sd]) for sd in 'RL'}
# the DRAWN strokes around the eye corners (lower edge of the wing, inner tip, small lashes) are shortened the same way
# in the texture: beyond each corner, inside the eye band, the image is compressed horizontally by LASH_K, so the
# painted wing ends exactly where the 3D eyeliner ends.  (corner x, outward direction, compressed width, back-to-normal width)
LASH_BAND = (528, 630)                 # image rows affected (eyeliner top -> lower lashes), feathered at both ends
def lash_corners():
    out = []
    for sd in 'RL':
        ex0, ex1 = min(p[0] for p in EYE_PX[sd]), max(p[0] for p in EYE_PX[sd])
        f0, f1 = min(p[0] for p in LASH_PX_FULL[sd]), max(p[0] for p in LASH_PX_FULL[sd])
        for c, sgn, ov in ((ex0, -1, ex0 - f0), (ex1, +1, f1 - ex1)):
            lw = ov + 10                                     # the drawn strokes reach a little beyond the traced tip
            lim = (c - IMG_X0 - 5) if sgn < 0 and c < CX else (IMG_X1 - c - 5) if sgn > 0 and c > CX else lw + 30
            out.append((c, sgn, lw, max(lim, lw + 3)))
    return out
def corner_src_u(u, lw, lw2):
    """distance from the corner in the shortened image -> distance in the drawing"""
    if u <= LASH_K * lw: return u / LASH_K
    if u <= lw2: return lw + (u - LASH_K * lw) * (lw2 - lw) / (lw2 - LASH_K * lw)
    return u
LASH_RECT = (870, 762, 150, 20)        # eyeliner front (ink)
LASH_SIDE_RECT = (870, 786, 150, 20)   # eyeliner sides

# --- texture atlas (pixel rects x, y, w, h ; y down)
FACE_RECT = (0, 0, 1024, 642)
FACE_X = (-0.614, 0.614)               # studs mapped to FACE_RECT width
FACE_Z = (0.25, -0.52)                 # studs mapped to FACE_RECT height (top -> bottom)
PPS = 1024 / (FACE_X[1] - FACE_X[0])   # atlas px per stud (834)
CUP_MARGIN = 0.022                     # studs of sclera beyond the opening
CUP_RECT = {'R': (4, 650), 'L': (362, 650)}     # top-left; size from bbox * PPS
LID_RECT = {'R': (722, 650, 140, 46), 'L': (722, 702, 140, 46)}
WALL_UP_RECT = (870, 650, 150, 24)     # upper socket wall (seen from below): lid shadow grey
WALL_LO_RECT = (870, 678, 150, 24)     # lower / side socket walls: sclera
IRIS_RECT = {'R': (4, 790), 'L': (190, 790)}         # top-left; size from the iris ellipse
MOUTH_RECT = (870, 706, 150, 50)       # mouth interior
CLEAR_RECT = (990, 990, 30, 30)
LASH_CLEAR_RECT = (1000, 958, 18, 18)  # transparent too: the skin-coloured edges of a drawn 3D eyeliner        # transparent (skin colour shows through)
BALL_RECT = (952, 990, 30, 30)         # pupil ball: deep black
EYE_TEX_UP = 0.14                      # the eye texture also covers the socket widened above the opening (seen from below)

def eye_poly_studs(side):
    return [img2stud(*p) for p in EYE_PX[side]]
def eye_bbox(side):
    pts = eye_poly_studs(side)
    xs = [p[0] for p in pts]; zs = [p[1] for p in pts]
    return (min(xs) - CUP_MARGIN, max(xs) + CUP_MARGIN, min(zs) - CUP_MARGIN, max(zs) + CUP_MARGIN)
def cup_rect(side):
    x0, x1, z0, z1 = eye_bbox(side)
    return (CUP_RECT[side][0], CUP_RECT[side][1], int(round((x1 - x0) * PPS)), int(round((z1 - z0) * PPS)))

def px2uv(px, py):
    return (px / ATLAS, 1 - py / ATLAS)
def face_uv(x, z):
    fx, fy, fw, fh = FACE_RECT
    px = fx + (x - FACE_X[0]) / (FACE_X[1] - FACE_X[0]) * fw
    py = fy + (z - FACE_Z[0]) / (FACE_Z[1] - FACE_Z[0]) * fh
    return px2uv(px, py)
def in_face_window(x, z):
    return FACE_X[0] <= x <= FACE_X[1] and FACE_Z[1] <= z <= FACE_Z[0]
def cup_uv(side, x, z):
    x0, x1, z0, z1 = eye_bbox(side)
    rx, ry, rw, rh = cup_rect(side)
    return px2uv(rx + (x - x0) / (x1 - x0) * rw, ry + (z1 - z) / (z1 - z0) * rh)
def lid_uv(side, s, t):                 # s: 0..1 across the eye, t: 0 hinge .. 1 lid edge
    rx, ry, rw, rh = LID_RECT[side]
    return px2uv(rx + 2 + s * (rw - 4), ry + 2 + t * (rh - 4))
def rect_center_uv(r):
    return px2uv(r[0] + r[2] / 2, r[1] + r[3] / 2)

def iris_studs(side):
    (cx, cy), (rx, ry) = IRIS_PX[side], IRIS_R_PX[side]
    x, z = img2stud(cx, cy)
    return x, z, rx / SX, ry / SY
def iris_rect(side):
    x, z, rx, rz = iris_studs(side)
    return (IRIS_RECT[side][0], IRIS_RECT[side][1], int(round(2 * rx * PPS)), int(round(2 * rz * PPS)))
def iris_uv(side, a, b):                 # a, b in [-1, 1]: ellipse-normalised offsets (x right, z up)
    rx_, ry_, rw, rh = iris_rect(side)
    return px2uv(rx_ + (a + 1) / 2 * rw, ry_ + (1 - b) / 2 * rh)

def eye_tex_box(side):
    x0, x1, z0, z1 = eye_bbox(side)
    return (x0, x1, z0, z1 + EYE_TEX_UP)
EYE_RECT_K = 0.8 if FACE_STYLE == 'girl2' else 1.0      # girl2: eye texture a little smaller (room for the liner copy)
# girl2: the drawn eyeliner + lashes are copied here; the 3D eyeliner's front uses this copy (the skin under it is
# erased, so nothing is left on the skin when the eye closes)
LINER_RECT = {'R': (4, 888, 470, 134), 'L': (480, 888, 470, 134)}
def liner_box_px(side):
    xs = [p[0] for p in LASH_PX[side]]; ys = [p[1] for p in LASH_PX[side]]
    return min(xs) - 5, max(xs) + 5, min(ys) - 5, max(ys) + 12
def liner_scale(side):
    x0, x1, y0, y1 = liner_box_px(side); rx, ry, rw, rh = LINER_RECT[side]
    return min(rw / (x1 - x0), rh / (y1 - y0))
def liner_uv(side, x, z):
    """studs on the face -> the copied drawing of that side's eyeliner"""
    px, py = stud2img(x, z)
    x0, x1, y0, y1 = liner_box_px(side); rx, ry, rw, rh = LINER_RECT[side]; k = liner_scale(side)
    u = min(max((px - x0) * k, 0.5), rw - 0.5); v = min(max((py - y0) * k, 0.5), rh - 0.5)
    return px2uv(rx + u, ry + v)
def eye_rect(side):
    """the drawn eye (white + iris, pupil removed) painted on the inside of the eye sphere; R then L side by side"""
    def size(sd):
        x0, x1, z0, z1 = eye_tex_box(sd)
        k = EYE_RECT_K
        return int(round((x1 - x0) * PPS * k)), int(round((z1 - z0) * PPS * k))
    wR, hR = size('R'); w, h = size(side)
    return (4, 650, w, h) if side == 'R' else (4 + wR + 8, 650, w, h)
def eye_tex_uv(side, x, z):
    x0, x1, z0, z1 = eye_tex_box(side)
    rx, ry, rw, rh = eye_rect(side)
    u = min(max((x - x0) / (x1 - x0), 0.0), 1.0); v = min(max((z1 - z) / (z1 - z0), 0.0), 1.0)
    return px2uv(rx + 1 + u * (rw - 2), ry + 1 + v * (rh - 2))

WALL_DEPTH = 0.06                       # socket depth mapped over the wall gradient
def wall_uv(rect, depth):
    t = max(0.0, min(1.0, depth / WALL_DEPTH))
    return px2uv(rect[0] + rect[2] / 2, rect[1] + 2 + t * (rect[3] - 4))
def lash_poly_studs(side):
    return [img2stud(*p) for p in LASH_PX[side]]
