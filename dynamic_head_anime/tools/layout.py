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

# raised (3D) upper eyeliner band, traced on the reference (image px)
LASH_PX = {
 'R': [(196, 539), (215, 540), (240, 538), (262, 535), (282, 533), (310, 534), (340, 535.5), (370, 538), (390, 541),
       (415, 545), (440, 550), (460, 557), (482, 570), (463, 566), (449, 562), (440, 560), (420, 559), (390, 559),
       (360, 558.5), (329, 558.5), (300, 559), (270, 560), (255, 561), (232, 553)],
 'L': [(585, 572.5), (605, 563), (630, 552.5), (650, 548), (670, 544), (695, 542), (720, 540), (745, 538), (770, 536),
       (785, 534.5), (820, 534), (850, 533.5), (872.5, 533), (845, 545), (812, 561), (800, 559), (770, 558.5),
       (740, 558.5), (710, 559), (680, 559), (650, 559), (636, 561), (628, 566), (623, 572), (605, 575)],
}
# the 3D eyeliner is shorter than the drawn one: the part beyond the eye opening (the wing / the inner tip) keeps only
# LASH_K of its length.  The texture still erases the WHOLE drawn eyeliner (LASH_PX_FULL), so nothing is left painted.
LASH_K = 0.5
LASH_PX_FULL = LASH_PX
def _shorten(poly, eye):
    ex0, ex1 = min(p[0] for p in eye), max(p[0] for p in eye)
    return [(ex0 - (ex0 - x) * LASH_K if x < ex0 else ex1 + (x - ex1) * LASH_K if x > ex1 else x, y) for x, y in poly]
LASH_PX = {sd: _shorten(LASH_PX_FULL[sd], EYE_PX[sd]) for sd in 'RL'}
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
CLEAR_RECT = (990, 990, 30, 30)        # transparent (skin colour shows through)
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
def eye_rect(side):
    """the drawn eye (white + iris, pupil removed) painted on the inside of the eye sphere; R then L side by side"""
    def size(sd):
        x0, x1, z0, z1 = eye_tex_box(sd)
        return int(round((x1 - x0) * PPS)), int(round((z1 - z0) * PPS))
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
