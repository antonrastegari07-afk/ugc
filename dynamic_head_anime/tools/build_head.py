"""Build the animated (FACS) anime dynamic head.

run:  python tools/build_head.py <project dir>     (python = venv with the `bpy` module)

The head is modelled in "mask studs" (white face mask size, centred on the origin), then placed on the official
Roblox Blocky character (R15 rig, body cages, attachments) at standard head size.  1 Blender unit = 1 stud, exported
like Roblox's reference FBX (UnitScaleFactor 100, no node rotation/scale).
Blender axes: +X = character's left, -Y = front, +Z = up.
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(sys.argv[-1])
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from layout import *

OUT = os.path.join(ROOT, 'build')
FACE = json.load(open(os.path.join(OUT, 'face_data.json')))

# ---------------------------------------------------------------- parameters
DISH_D = 0.088            # depth of the sclera dish behind the face at the iris centre (concave -> eyes follow the camera)
DISH_RH, DISH_RV = 0.42, 0.26   # curvature radii of the dish (horizontal, vertical); centres of curvature are in front
DISH_MIN = 0.006          # the dish never comes closer than this to the face surface
IRIS_OFF = 0.0025         # iris disc floats this much in front of the sclera dish
CUP_STEP = 0.03
SOCKET_EXTRA = 0.07       # cutter goes this much deeper than the deepest cup point
LOOK_X, LOOK_Z = 0.028, 0.017
MOUTH_HALF_GAP = 0.0026
MOUTH_DEPTH = 0.10
MOUTH_INSET = 0.012

# ---------------------------------------------------------------- base shape
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, 'in', 'WhiteFace_Mask.fbx'))
base = [o for o in bpy.data.objects if o.type == 'MESH'][0]
bm_base = bmesh.new(); bm_base.from_mesh(base.data)
bm_base.transform(Matrix.Scale(100.0, 4) @ base.matrix_world)       # -> studs
cen = sum((v.co for v in bm_base.verts), Vector()) / len(bm_base.verts)
lo = Vector([min(v.co[i] for v in bm_base.verts) for i in range(3)])
hi = Vector([max(v.co[i] for v in bm_base.verts) for i in range(3)])
bm_base.transform(Matrix.Translation(-(lo + hi) / 2))
BVH = BVHTree.FromBMesh(bm_base)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)

def surf_y(x, z):
    loc, n, i, d = BVH.ray_cast(Vector((x, -3.0, z)), Vector((0, 1, 0)))
    return loc.y if loc else None

def radial(p):
    loc, n, i, d = BVH.ray_cast(Vector((0, 0, 0)), p.normalized())
    return loc

# ---------------------------------------------------------------- 2D helpers
def pip(pt, poly):
    x, y = pt; inside = False
    for i in range(len(poly)):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % len(poly)]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return inside

def seg_dist(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy + 1e-12)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)

def poly_dist(p, poly):
    return min(seg_dist(p, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))

def vertical_span(poly, x):
    zs = []
    for i in range(len(poly)):
        (x1, z1), (x2, z2) = poly[i], poly[(i + 1) % len(poly)]
        if (x1 - x) * (x2 - x) <= 0 and x1 != x2:
            zs.append(z1 + (x - x1) * (z2 - z1) / (x2 - x1))
    return (max(zs), min(zs)) if zs else None

EYES = {'L': eye_poly_studs('L'), 'R': eye_poly_studs('R')}
IRIS = {s: iris_studs(s) for s in 'LR'}                      # x, z, rx, rz
IRIS_C = {s: IRIS[s][:2] for s in 'LR'}
DISH_B = {s: surf_y(*IRIS_C[s]) + DISH_D for s in 'LR'}       # deepest point (y)
def dish_y(s, x, z):
    xi, zi = IRIS_C[s]
    y = DISH_B[s] - (x - xi) ** 2 / (2 * DISH_RH) - (z - zi) ** 2 / (2 * DISH_RV)
    return max(y, surf_y(x, z) + DISH_MIN)

# mouth centre line: smooth polynomial through the extracted ink line
mx = [p[0] for p in FACE['mouth']]; mz = [p[1] for p in FACE['mouth']]
import numpy as np
coef = np.polyfit(mx, mz, 3)
MX0, MX1 = min(mx) + MOUTH_INSET, max(mx) - MOUTH_INSET
def mouth_z(x):
    return float(np.polyval(coef, min(max(x, MX0), MX1)))
MOUTH_C = ((MX0 + MX1) / 2, mouth_z((MX0 + MX1) / 2))
def mouth_gap(x):
    t = (x - MOUTH_C[0]) / ((MX1 - MX0) / 2)
    return MOUTH_HALF_GAP * max(0.0, 1 - t * t) ** 0.5
MOUTH_POLY = []
N = 24
for i in range(N + 1):
    x = MX0 + (MX1 - MX0) * i / N
    MOUTH_POLY.append((x, mouth_z(x) + mouth_gap(x)))
for i in range(N - 1, 0, -1):
    x = MX0 + (MX1 - MX0) * i / N
    MOUTH_POLY.append((x, mouth_z(x) - mouth_gap(x)))
MOUTH_POLY = MOUTH_POLY[::-1]                 # clockwise like the eyes (order does not matter for the prism)

# ---------------------------------------------------------------- head shell: cube-sphere fitted on the base
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=2.0)
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=11, use_grid_fill=True)
sel = set()
for f in bm.faces:
    c = radial(f.calc_center_median())
    brow = abs(c.x) < 0.56 and -0.03 < c.z < 0.22
    if c.y < -0.3 and brow:
        sel.update(f.edges)
bmesh.ops.subdivide_edges(bm, edges=list(sel), cuts=1, use_grid_fill=True)
for v in bm.verts:
    v.co = radial(v.co)
bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
print('shell tris before boolean', sum(len(f.verts) - 2 for f in bm.faces))
head_me = bpy.data.meshes.new('Head_Geo'); bm.to_mesh(head_me); bm.free()
head = bpy.data.objects.new('Head_Geo', head_me); bpy.context.scene.collection.objects.link(head)

# ---------------------------------------------------------------- cutters
def add_prism(b, pts, y0, y1):
    vf = [b.verts.new((x, y0, z)) for x, z in pts]
    vb = [b.verts.new((x, y1, z)) for x, z in pts]
    n = len(pts)
    b.faces.new(vf); b.faces.new(vb[::-1])
    for i in range(n):
        j = (i + 1) % n
        b.faces.new((vf[i], vf[j], vb[j], vb[i]))

eye_back = {}
bc = bmesh.new()
for s in 'LR':
    xi, zi = IRIS_C[s]
    yb = max(dish_y(s, x, z) for x, z in EYES[s] + [IRIS_C[s]]) + SOCKET_EXTRA
    eye_back[s] = yb
    add_prism(bc, EYES[s], -1.5, yb)
bmesh.ops.recalc_face_normals(bc, faces=bc.faces[:])
cut_me = bpy.data.meshes.new('cut'); bc.to_mesh(cut_me); bc.free()
cut = bpy.data.objects.new('cut', cut_me); bpy.context.scene.collection.objects.link(cut)
mod = head.modifiers.new('bool', 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.object = cut
mod.solver = 'EXACT'
bpy.context.view_layer.objects.active = head; head.select_set(True)
bpy.ops.object.modifier_apply(modifier='bool')
bpy.data.objects.remove(cut)

# ---------------------------------------------------------------- classify shell faces + UVs
bm = bmesh.new(); bm.from_mesh(head.data)
uvl = bm.loops.layers.uv.new('UVMap')
CLEAR_UV = rect_center_uv(CLEAR_RECT); MOUTH_UV = rect_center_uv(MOUTH_RECT)
WALL_UP_UV = rect_center_uv(WALL_UP_RECT); WALL_LO_UV = rect_center_uv(WALL_LO_RECT)
def socket_of(p):
    sy = surf_y(p.x, p.z)
    if sy is None or p.y < sy + 0.0025:
        return None
    for s in 'LR':
        q = (p.x, p.z)
        if pip(q, EYES[s]) or poly_dist(q, EYES[s]) < 0.002:
            return s
    q = (p.x, p.z)
    if pip(q, MOUTH_POLY) or poly_dist(q, MOUTH_POLY) < 0.002:
        return 'M'
    return None
n_face = 0
for f in bm.faces:
    c = f.calc_center_median()
    sk = socket_of(c)
    if sk in ('L', 'R'):
        rect = WALL_UP_RECT if f.normal.z < -0.5 else WALL_LO_RECT
        for l in f.loops:
            co = l.vert.co
            l[uvl].uv = wall_uv(rect, co.y - surf_y(co.x, co.z))
    elif sk == 'M':
        for l in f.loops: l[uvl].uv = MOUTH_UV
    elif f.normal.y < -0.2 and all(in_face_window(v.co.x, v.co.z) for v in f.verts):
        n_face += 1
        for l in f.loops: l[uvl].uv = face_uv(l.vert.co.x, l.vert.co.z)
    else:
        for l in f.loops: l[uvl].uv = CLEAR_UV
bmesh.ops.dissolve_degenerate(bm, dist=0.0006, edges=bm.edges[:])
for f in bm.faces:
    f.smooth = True

# ---------------------------------------------------------------- mouth: hand-built patch (no boolean slivers)
# concentric rings around the slit, upper and lower slit vertices at the same x, a strip-triangulated mouth bag,
# bridged to the head shell.  Clean deformation for JawDrop / smiles / pucker.
MN, MRINGS = 12, (0.014, 0.036, 0.066)
xs_m = [MX0 + (MX1 - MX0) * i / MN for i in range(MN + 1)]
slit = [(x, mouth_z(x) + mouth_gap(x), +1) for x in xs_m] + [(x, mouth_z(x) - mouth_gap(x), -1) for x in xs_m[-2:0:-1]]
def outward(x, z, sgn):
    if sgn == 0: return Vector(((1 if x > MOUTH_C[0] else -1), 0))
    d = Vector(((x - MOUTH_C[0]) / ((MX1 - MX0) / 2) * 0.9, sgn))
    return d.normalized()
slit2 = []
for j, (x, z, sg) in enumerate(slit):
    sg = 0 if j in (0, MN) else sg
    slit2.append((x, z, sg))
rings2d = [[(x, z) for x, z, _ in slit2]]
def outdir(j):
    x, z, sg = slit2[j]
    if sg != 0: return outward(x, z, sg)
    n1 = Vector(slit2[(j + 1) % len(slit2)][:2]); n2 = Vector(slit2[j - 1][:2])
    return (Vector((x, z)) - (n1 + n2) / 2).normalized()
for d in MRINGS:
    rings2d.append([tuple(Vector((x, z)) + outdir(j) * d) for j, (x, z, sg) in enumerate(slit2)])
outer2d = rings2d[-1]
cut2d = [tuple(Vector(p) + (Vector(p) - Vector(MOUTH_C)).normalized() * 0.03) for p in outer2d]
uv_layer = uvl
# delete the shell faces under the patch
kill = [f for f in bm.faces if f.calc_center_median().y < -0.3 and pip((f.calc_center_median().x, f.calc_center_median().z), cut2d)]
bmesh.ops.delete(bm, geom=kill, context='FACES')
hole_edges = [e for e in bm.edges if e.is_boundary]
def sv(x, z, back=0.0):
    return bm.verts.new((x, surf_y(x, z) + back, z))
rings = [[sv(x, z) for x, z in r] for r in rings2d]
M2 = len(slit2)
def face_front(vs):
    f = bm.faces.new(vs); f.smooth = True
    f.normal_update()
    if f.normal.y > 0: f.normal_flip()
    for l in f.loops: l[uvl].uv = face_uv(l.vert.co.x, l.vert.co.z)
    return f
for k in range(len(rings) - 1):
    for j in range(M2):
        j2 = (j + 1) % M2
        face_front((rings[k][j], rings[k][j2], rings[k + 1][j2], rings[k + 1][j]))
outer_edges = []
for j in range(M2):
    a, b2 = rings[-1][j], rings[-1][(j + 1) % M2]
    outer_edges.append(bm.edges.get((a, b2)))
faces_before = set(bm.faces)
res = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=list(dict.fromkeys(hole_edges + outer_edges)), normal=Vector((0, -1, 0)))
fill_faces = [f for f in res['geom'] if isinstance(f, bmesh.types.BMFace)]
bmesh.ops.beautify_fill(bm, faces=fill_faces, edges=list({e for f in fill_faces for e in f.edges if all(ff in fill_faces for ff in e.link_faces)}))
fill_faces = [f for f in bm.faces if f not in faces_before]          # every face created by the fill
for f in fill_faces:
    f.smooth = True
    f.normal_update()
    if f.normal.y > 0: f.normal_flip()
    for l in f.loops: l[uvl].uv = face_uv(l.vert.co.x, l.vert.co.z)
# mouth bag: walls + strip floor
back = [bm.verts.new(v.co + Vector((0, MOUTH_DEPTH, 0))) for v in rings[0]]
def mface(vs, want):
    f = bm.faces.new(vs); f.smooth = False
    f.normal_update()
    if f.normal.dot(want) < 0: f.normal_flip()
    for l in f.loops: l[uvl].uv = MOUTH_UV
mc3 = Vector((MOUTH_C[0], surf_y(*MOUTH_C) + MOUTH_DEPTH * 0.5, MOUTH_C[1]))
for j in range(M2):
    j2 = (j + 1) % M2
    a, b2, c2, d2 = rings[0][j], rings[0][j2], back[j2], back[j]
    mid = (a.co + b2.co + c2.co + d2.co) / 4
    mface((a, b2, c2, d2), mc3 - mid)                    # walls face into the bag
up_idx = list(range(0, MN + 1)); lo_idx = [0] + list(range(M2 - 1, MN, -1)) + [MN]
for i in range(MN):
    ua, ub = back[up_idx[i]], back[up_idx[i + 1]]
    la, lb = back[lo_idx[i]], back[lo_idx[i + 1]]
    vs = [ua, ub, lb, la] if la is not ua and lb is not ub else ([ua, ub, la] if lb is ub else [ua, ub, lb])
    vs = list(dict.fromkeys(vs))
    if len(vs) >= 3: mface(vs, Vector((0, -1, 0)))           # floor faces the front
# outer skin faces (face block / plain skin UVs) must point away from the head centre
def _is_skin_uv(f):
    for l in f.loops:
        px, py = l[uvl].uv.x * ATLAS, (1 - l[uvl].uv.y) * ATLAS
        inf = py <= FACE_RECT[1] + FACE_RECT[3] + 1
        inc = CLEAR_RECT[0] - 1 <= px <= CLEAR_RECT[0] + CLEAR_RECT[2] + 1 and CLEAR_RECT[1] - 1 <= py <= CLEAR_RECT[1] + CLEAR_RECT[3] + 1
        if not (inf or inc): return False
    return True
bm.normal_update()
nfix = 0
for f in bm.faces:
    if _is_skin_uv(f) and f.normal.dot(f.calc_center_median()) < 0:
        f.normal_flip(); nfix += 1
print('skin faces re-oriented:', nfix)
bm.normal_update()
SHELL_N = len(bm.verts)
print('shell tris after boolean', sum(len(f.verts) - 2 for f in bm.faces))

# ---------------------------------------------------------------- sclera dishes (static, holed) + round concave irises (move)
IRIS_SEG = 20
IRIS_WALL = 0.010         # depth of the little wall at the iris rim (light crescent seen at an angle)
IRIS_BOWL = 0.018         # extra depth of the iris bowl at its centre
SKIRT = (2 * LOOK_X + 0.05, 2 * LOOK_Z + 0.05)   # covers the dish hole for every gaze    # sclera skirt around the iris (covers the hole in the static dish while the eye looks around)
LIGHT_UV = rect_center_uv(WALL_LO_RECT)
cup_verts = {'L': [], 'R': []}
iris_verts = {'L': [], 'R': []}
def para(s, x, z):
    xi, zi = IRIS_C[s]
    return DISH_B[s] - (x - xi) ** 2 / (2 * DISH_RH) - (z - zi) ** 2 / (2 * DISH_RV)
for s in 'LR':
    xi, zi, r0, _ = IRIS[s]
    x0, x1, z0, z1 = eye_bbox(s)
    nx = int(math.ceil((x1 - x0) / CUP_STEP)); nz = int(math.ceil((z1 - z0) / CUP_STEP))
    grid = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx; z = z0 + (z1 - z0) * j / nz
            v = bm.verts.new((x, dish_y(s, x, z), z))
            row.append(v); cup_verts[s].append(v)
        grid.append(row)
    for j in range(nz):
        for i in range(nx):
            q = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])   # x right, z up -> normal -Y
            if any(((v.co.x - xi) / (r0 + LOOK_X + 0.004)) ** 2 + ((v.co.z - zi) / (r0 + LOOK_Z + 0.004)) ** 2 < 1 for v in q):
                continue                       # hole: iris + gaze range (the moving skirt covers it)
            f = bm.faces.new(q); f.smooth = True
            for l in f.loops: l[uvl].uv = cup_uv(s, l.vert.co.x, l.vert.co.z)
    for v in [v for v in cup_verts[s] if not v.link_faces]:
        cup_verts[s].remove(v); bm.verts.remove(v)
    # moving part: skirt ring (sclera) + rim wall (light) + concave bowl (iris texture)
    def ring(rx, rz, depth):
        out = []
        for k in range(IRIS_SEG):
            t = 2 * math.pi * k / IRIS_SEG
            x, z = xi + rx * math.cos(t), zi + rz * math.sin(t)
            y = para(s, x, z) - IRIS_OFF + depth
            sy = max((surf_y(x + dx, z + dz) or -9) for dx in (-0.05, -0.025, 0, 0.025, 0.05) for dz in (-0.025, 0, 0.025))
            y = max(y, sy + 0.02)                        # hidden part of the skirt stays inside the head for every gaze
            v = bm.verts.new((x, y, z))
            out.append(v); iris_verts[s].append(v)
        return out
    skirt = ring(r0 + SKIRT[0], r0 + SKIRT[1], 0.0)
    rim = ring(r0, r0, 0.0)
    wall = ring(r0 * 0.992, r0 * 0.992, IRIS_WALL)
    bowl = [(0.992, wall)]
    for rr in (0.70, 0.40):
        bowl.append((rr, ring(r0 * rr, r0 * rr, IRIS_WALL + IRIS_BOWL * (1 - (rr / 0.992) ** 2))))
    cen = bm.verts.new((xi, para(s, xi, zi) - IRIS_OFF + IRIS_WALL + IRIS_BOWL, zi)); iris_verts[s].append(cen)
    def quad(outer, inner, uvf):
        for k in range(IRIS_SEG):
            k2 = (k + 1) % IRIS_SEG
            f = bm.faces.new((inner[k], outer[k], outer[k2], inner[k2])); f.smooth = True
            for l in f.loops: l[uvl].uv = uvf(l.vert)
    def iuv(v, scale=1.0):
        a_, b_ = (v.co.x - xi) / r0, (v.co.z - zi) / r0
        return iris_uv(s, a_ / 0.992, b_ / 0.992)
    quad(skirt, rim, lambda v: cup_uv(s, v.co.x, v.co.z))
    quad(rim, wall, lambda v: LIGHT_UV)
    for (ra, outer), (rb, inner) in zip(bowl[:-1], bowl[1:]):
        quad(outer, inner, iuv)
    last = bowl[-1][1]
    for k in range(IRIS_SEG):
        f = bm.faces.new((cen, last[k], last[(k + 1) % IRIS_SEG])); f.smooth = True
        for l in f.loops: l[uvl].uv = iuv(l.vert)
bm.normal_update()
for s in 'LR':
    fs = {f for v in iris_verts[s] for f in v.link_faces}
    print('iris', s, 'mean normal y (want < 0)', round(sum(f.normal.y for f in fs) / len(fs), 3))

# ---------------------------------------------------------------- eyelids: curved skin lids that ROTATE closed
# The upper lid comes down ~2/3 of the eye and the lower lid comes up ~1/3; they meet under the eyeliner.
# Closed shape = a slightly bulged skin lid between the rim and the meeting line.  Rest shape = the same rigid lid
# rotated LID_ANGLE back into the head around a hinge axis that follows the rim (tilted with the face curvature),
# so it is invisible when the eye is open.  Roblox interpolates the bone rotation -> real half-blinks.
LID_ANGLE = math.radians(100)
def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
LID_BULGE = 0.008
MEET = 0.30                                   # meeting line height (fraction of the eye height above the lower rim)
LID_COLS = 10
def eye_xr(s):
    xs = [p[0] for p in EYES[s]]
    return min(xs), max(xs)
def span_c(s, x):
    x0, x1 = eye_xr(s)
    return vertical_span(EYES[s], min(max(x, x0 + 0.0015), x1 - 0.0015))
def meet_z(s, x):
    t, b = span_c(s, x)
    return b + MEET * (t - b)
lid_info = {}
def make_lid(s, kind):
    x0, x1 = eye_xr(s)
    xa, xb = x0 - 0.003, x1 + 0.003
    ts = [0.0, 0.25, 0.55, 0.8, 1.0] if kind == 'U' else [0.0, 0.5, 1.0]
    cols = LID_COLS
    def edge_z(x):
        t, b = span_c(s, x)
        return (t + 0.0025) if kind == 'U' else (b - 0.0025)
    def end_z(x):
        m = meet_z(s, x)
        return (m - 0.004) if kind == 'U' else (m + 0.004)
    hinge_a = Vector((xa, surf_y(xa, edge_z(xa)) - 0.0004, edge_z(xa)))
    hinge_b = Vector((xb, surf_y(xb, edge_z(xb)) - 0.0004, edge_z(xb)))
    axis = (hinge_b - hinge_a).normalized()
    pivot = (hinge_a + hinge_b) / 2
    grid, closed = [], {}
    hmax = max(abs(edge_z(xa + (xb - xa) * i / cols) - end_z(xa + (xb - xa) * i / cols)) for i in range(cols + 1))
    for r, t in enumerate(ts):
        row = []
        for i in range(cols + 1):
            x = xa + (xb - xa) * i / cols
            e, f_ = edge_z(x), end_z(x)
            z = e + (f_ - e) * t
            q = (x, z)
            ins = pip(q, EYES[s])
            d = poly_dist(q, EYES[s])
            dome = LID_BULGE * smoothstep(0.0, 0.035, d) if ins else 0.0
            t_, b_ = span_c(s, x)
            corner = 1 - smoothstep(0.0, 0.03, t_ - b_)          # tuck only where the opening is a sharp corner
            y = surf_y(x, z) - 0.0004 + 0.004 * corner - dome    # flush with the skin at the rim, domed over the hole
            row.append(Vector((x, y, z)))
        grid.append(row)
    # rotation sign: the free edge must go BACK into the head
    probe = grid[-1][cols // 2]
    ang = LID_ANGLE
    Rm = lambda a_: Matrix.Translation(pivot) @ Matrix.Rotation(a_, 4, axis) @ Matrix.Translation(-pivot)
    if (Rm(ang) @ probe).y < probe.y:
        ang = -ang
    R = Rm(ang)
    vrows = []
    for r, row in enumerate(grid):
        vr = []
        for c in row:
            v = bm.verts.new(R @ c); closed[v] = c; vr.append(v)
        vrows.append(vr)
    for r in range(len(ts) - 1):
        for i in range(cols):
            q = (vrows[r][i], vrows[r + 1][i], vrows[r + 1][i + 1], vrows[r][i + 1])
            f = bm.faces.new(q); f.smooth = True
            for l in f.loops: l[uvl].uv = CLEAR_UV                    # skin colour (recolourable)
            # visible side must face the front once closed
            cs = [closed[v] for v in f.verts]
            if (cs[1] - cs[0]).cross(cs[2] - cs[0]).y > 0:
                f.normal_flip()
    return dict(pivot=pivot, axis=axis, angle=-ang, verts=closed)   # pose angle: rest -> closed
for s in 'LR':
    lid_info[s] = make_lid(s, 'U')
    lid_info[s + 'low'] = make_lid(s, 'D')
bm.normal_update()

# ---------------------------------------------------------------- raised 3D upper eyeliner (moves down to close the eye)
LASH_T = 0.011            # thickness in front of the face
LASH_OVER = 0.0055        # overhang below the opening's top rim
LASH_SIDE_UV = rect_center_uv(LASH_SIDE_RECT); LASH_UV = rect_center_uv(LASH_RECT)
lash_verts = {'L': [], 'R': []}
def ear_clip(pts):
    """triangulate a simple counter-clockwise 2D polygon (list of (x, z)); returns index triples"""
    idx = list(range(len(pts))); out = []
    def cross(o, a, b): return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    def inside(p, a, b, c):
        return cross(a, b, p) >= 0 and cross(b, c, p) >= 0 and cross(c, a, p) >= 0
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        n = len(idx); best = None
        for k in range(n):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % n]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if cross(a, b, c) <= 1e-12: continue
            if any(inside(pts[j], a, b, c) for j in idx if j not in (i0, i1, i2)): continue
            # prefer the fattest ear
            ln = [math.dist(a, b), math.dist(b, c), math.dist(c, a)]
            q = cross(a, b, c) / (max(ln) ** 2 + 1e-12)
            if best is None or q > best[0]: best = (q, k)
        if best is None: break
        k = best[1]; n = len(idx)
        out.append((idx[k - 1], idx[k], idx[(k + 1) % n])); idx.pop(k)
    if len(idx) == 3: out.append(tuple(idx))
    return out
def densify(poly, step):
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        n = max(1, int(math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]) / step)))
        for k in range(n):
            out.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n))
    return out
def resample(chain, n):
    L = [0.0]
    for i in range(1, len(chain)): L.append(L[-1] + math.dist(chain[i - 1], chain[i]))
    out = []
    for k in range(n + 1):
        t = L[-1] * k / n
        i = max(1, min(len(chain) - 1, next((j for j in range(1, len(chain)) if L[j] >= t), len(chain) - 1)))
        u = (t - L[i - 1]) / max(L[i] - L[i - 1], 1e-9)
        out.append((chain[i - 1][0] + (chain[i][0] - chain[i - 1][0]) * u, chain[i - 1][1] + (chain[i][1] - chain[i - 1][1]) * u))
    return out
LASH_COLS = 26
for s in 'LR':
    poly = lash_poly_studs(s)
    i0 = min(range(len(poly)), key=lambda i: poly[i][0]); i1 = max(range(len(poly)), key=lambda i: poly[i][0])
    n = len(poly)
    ca = [poly[(i0 + k) % n] for k in range((i1 - i0) % n + 1)]
    cb = [poly[(i0 - k) % n] for k in range((i0 - i1) % n + 1)]
    top, bot = (ca, cb) if sum(p[1] for p in ca) / len(ca) > sum(p[1] for p in cb) / len(cb) else (cb, ca)
    def at_x(chain, x):
        ch = sorted(chain)
        for i in range(1, len(ch)):
            if ch[i][0] >= x:
                u = (x - ch[i - 1][0]) / max(ch[i][0] - ch[i - 1][0], 1e-9)
                return ch[i - 1][1] + (ch[i][1] - ch[i - 1][1]) * u
        return ch[-1][1]
    xl, xr = poly[i0][0], poly[i1][0]
    xsl = [xl + (xr - xl) * (0.5 - 0.5 * math.cos(math.pi * k / LASH_COLS)) for k in range(LASH_COLS + 1)]
    top = [(x, at_x(top, x)) for x in xsl]; bot = [(x, at_x(bot, x)) for x in xsl]
    bot = [(x, min(zb, zt - 0.002)) for (x, zb), (_, zt) in zip(bot, top)]
    bot = [(x, z - LASH_OVER) if poly_dist((x, z), EYES[s]) < 0.004 else (x, z) for x, z in bot]
    def mk(x, z):
        loc, nrm, _, _ = BVH.ray_cast(Vector((x, -3.0, z)), Vector((0, 1, 0)))
        return bm.verts.new(loc + nrm * LASH_T), bm.verts.new(loc - nrm * 0.004)
    T_ = [mk(*p) for p in top]; B_ = [mk(*p) for p in bot[1:-1]]
    B_ = [T_[0]] + B_ + [T_[-1]]                                   # tips shared
    for v in {v for pair in T_ + B_ for v in pair}: lash_verts[s].append(v)
    for i in range(LASH_COLS):
        vs = [T_[i][0], T_[i + 1][0], B_[i + 1][0], B_[i][0]]
        vs = list(dict.fromkeys(vs))
        f = bm.faces.new(vs); f.smooth = True
        f.normal_update()
        if f.normal.y > 0: f.normal_flip()
        for l in f.loops: l[uvl].uv = LASH_UV
    loop = T_ + B_[-2:0:-1]                                        # outline (front, back pairs)
    for i in range(len(loop)):
        (fa, ba), (fb, bb) = loop[i], loop[(i + 1) % len(loop)]
        f = bm.faces.new((fa, ba, bb, fb)); f.smooth = False
        f.normal_update()
        cen = sum((v.co for v in (fa, ba, bb, fb)), Vector()) / 4
        mid = sum((p[0].co for p in loop), Vector()) / len(loop)
        if f.normal.dot(cen - mid) < 0: f.normal_flip()
        for l in f.loops: l[uvl].uv = LASH_SIDE_UV
bm.normal_update()

# how far the eyeliner drops at each x to land on the lower rim (0 at the corners and beyond)
def lash_drop(s, x):
    xs = [p[0] for p in EYES[s]]
    if x <= min(xs) or x >= max(xs):
        return 0.0
    sp = vertical_span(EYES[s], x)
    d = max(0.0, (sp[0] - LASH_OVER) - (meet_z(s, x) - 0.006))
    return d * smoothstep(0.0, 0.09, min(x - min(xs), max(xs) - x)) ** 0.7   # rounded arc, no shear at the corners
LASH_H = {s: max(lash_drop(s, min(p[0] for p in EYES[s]) + (max(p[0] for p in EYES[s]) - min(p[0] for p in EYES[s])) * i / 200) for i in range(201)) for s in 'LR'}

# every n-gon -> clean triangles (the boolean leaves concave n-gons around the eyes; a naive fan would fold)
ng = [f for f in bm.faces if len(f.verts) > 3]                      # quads too: best diagonal, no sliver
bmesh.ops.triangulate(bm, faces=ng, quad_method='BEAUTY', ngon_method='EAR_CLIP')
bm.normal_update()

# sharp edges at the socket rims / mouth / eyeliner
for e in bm.edges:
    if len(e.link_faces) == 2:
        a, b = e.link_faces
        if a.normal.angle(b.normal, 0) > math.radians(48):
            e.smooth = False
bm.to_mesh(head.data); head.data.update()

bm.verts.ensure_lookup_table()
CUP_IDX = {s: set(v.index for v in cup_verts[s]) for s in 'LR'}
IRIS_IDX = {s: set(v.index for v in iris_verts[s]) for s in 'LR'}
LID_IDX = {s: set(v.index for v in lid_info[s]['verts']) for s in 'LR'}
LOWLID_IDX = {s: set(v.index for v in lid_info[s + 'low']['verts']) for s in 'LR'}
LASH_IDX = {s: set(v.index for v in lash_verts[s]) for s in 'LR'}
REST = [v.co.copy() for v in bm.verts]
SOCK = [socket_of(v.co) if v.index < SHELL_N else None for v in bm.verts]
bm.free()
tris = sum(len(p.vertices) - 2 for p in head.data.polygons)
print('triangles', tris, 'verts', len(head.data.vertices))
assert tris <= 4000, 'over the 4000 triangle DynamicHead budget'

# ---------------------------------------------------------------- face joints (positions in mask studs)
def img_s(px, py): return img2stud(px, py)
BROWS = {'R': (img_s(490, 497), img_s(240, 468)), 'L': (img_s(575, 500), img_s(845, 466))}   # (inner, outer)
mL, mR = (MX1, mouth_z(MX1)), (MX0, mouth_z(MX0))
def front(x, z, back=0.0): return (x, surf_y(x, z) + back, z)
def eye_c(s):
    xs = [p[0] for p in EYES[s]]; zs = [p[1] for p in EYES[s]]
    return (sum(xs) / len(xs), sum(zs) / len(zs))
EC = {s: eye_c(s) for s in 'LR'}
EYE_BOT = {s: min(p[1] for p in EYES[s]) for s in 'LR'}
FACE_BONES = {}
for s, nm in (('L', 'Left'), ('R', 'Right')):
    FACE_BONES[nm + 'Eye'] = (IRIS_C[s][0], DISH_B[s] - DISH_RH, IRIS_C[s][1])
    FACE_BONES[nm + 'UpperEyelid'] = tuple(lid_info[s]['pivot'])
    FACE_BONES[nm + 'Eyelash'] = front(EC[s][0], EC[s][1] + 0.05, -0.011)
    FACE_BONES[nm + 'LowerEyelid'] = tuple(lid_info[s + 'low']['pivot'])
    FACE_BONES[nm + 'UnderEye'] = front(EC[s][0], EYE_BOT[s] - 0.01)
    FACE_BONES[nm + 'Cheek'] = front(EC[s][0], EYE_BOT[s] - 0.06)
    FACE_BONES[nm + 'InnerBrow'] = front(*BROWS[s][0])
    FACE_BONES[nm + 'OuterBrow'] = front(*BROWS[s][1])
FACE_BONES['Jaw'] = front(MOUTH_C[0], MOUTH_C[1] - 0.05, 0.12)
FACE_BONES['LeftLipCorner'] = front(*mL)
FACE_BONES['RightLipCorner'] = front(*mR)
FACE_BONES['LeftUpperLip'] = front(MOUTH_C[0] + 0.045, mouth_z(MOUTH_C[0] + 0.045) + 0.012)
FACE_BONES['RightUpperLip'] = front(MOUTH_C[0] - 0.045, mouth_z(MOUTH_C[0] - 0.045) + 0.012)
FACE_BONES['LeftLowerLip'] = front(MOUTH_C[0] + 0.045, mouth_z(MOUTH_C[0] + 0.045) - 0.014)
FACE_BONES['RightLowerLip'] = front(MOUTH_C[0] - 0.045, mouth_z(MOUTH_C[0] - 0.045) - 0.014)

# ---------------------------------------------------------------- skin weights (computed on the rest shape)
def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
def gauss(p, c, r):
    d2 = (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2
    return math.exp(-d2 / (2 * r * r))
MW = (MX1 - MX0) / 2
def below_mouth(x, z):
    """0 above the mouth line .. 1 below; sharp across the slit, soft beyond the corners."""
    dx = abs(x - MOUTH_C[0]) - MW
    eps = 0.0015 + 0.05 * smoothstep(-0.01, 0.06, dx)
    return smoothstep(-eps, eps, mouth_z(x) - z)

weights = []
for idx, p in enumerate(REST):
    w = {}
    side = next((s for s in 'LR' if idx in IRIS_IDX[s] or idx in LID_IDX[s] or idx in LOWLID_IDX[s] or idx in LASH_IDX[s] or idx in CUP_IDX[s]), None)
    nm = {'L': 'Left', 'R': 'Right'}.get(side or SOCK[idx] if (side or SOCK[idx]) in ('L', 'R') else None, '')
    if side and idx in IRIS_IDX[side]:
        w[nm + 'Eye'] = 1.0
    elif side and idx in LID_IDX[side]:
        w[nm + 'UpperEyelid'] = 1.0
    elif side and idx in LOWLID_IDX[side]:
        w[nm + 'LowerEyelid'] = 1.0
    elif side and idx in LASH_IDX[side]:
        d = lash_drop(side, p.x) / LASH_H[side]
        if d > 0: w[nm + 'Eyelash'] = d
    elif side and idx in CUP_IDX[side]:
        pass                                             # sclera dish: static
    else:
        x, y, z = p
        frontish = smoothstep(-0.15, -0.35, y)
        depth = 0.0
        sy = surf_y(x, z)
        if sy is not None and SOCK[idx]:
            depth = max(0.0, y - sy)
        if SOCK[idx] in ('L', 'R'):
            # socket walls: their front edge follows the lower lid / the skin around the eye a little
            s = SOCK[idx]; nmw = 'Left' if s == 'L' else 'Right'
            near = smoothstep(0.03, 0.0, depth)
            sp = vertical_span(EYES[s], min(max(x, min(q[0] for q in EYES[s]) + 0.001), max(q[0] for q in EYES[s]) - 0.001))
            if sp and z < (sp[0] + sp[1]) / 2:
                w[nmw + 'UnderEye'] = smoothstep(0.05, 0.0, depth) * 0.6
        elif frontish > 0:
            # ---- mouth: at most Jaw + one/two lip bones + one corner per vertex, all smooth and shared by both
            #      edges of the slit (no crossing / folding)
            b = below_mouth(x, z)
            if SOCK[idx] == 'M':
                b = 1.0 if z < mouth_z(x) else 0.0
            dm = math.hypot((x - MOUTH_C[0]) / 1.4, z - MOUTH_C[1])                 # elliptical distance
            region = smoothstep(0.16, 0.06, dm) * frontish
            jaw = b * smoothstep(-0.62, -0.50, z) * math.exp(-((x - MOUTH_C[0]) / 0.24) ** 4) * frontish
            def cornerw(c, sgn):                      # short towards the mouth centre, wide towards the cheek / up / down
                u = (x - c[0]) * sgn
                r = math.hypot(u / (0.10 if u > 0 else 0.045), (z - c[1]) / 0.065)
                return smoothstep(1.0, 0.0, r)
            cl = cornerw(mL, 1) * frontish
            cr = cornerw(mR, -1) * frontish
            sx = smoothstep(-0.035, 0.035, x - MOUTH_C[0])                          # 0 right .. 1 left
            lip = region * (1 - max(cl, cr)) * smoothstep(0.10, 0.02, dm)
            corner = max(cl, cr)
            dcorner = min(math.hypot(x - mL[0], z - mL[1]), math.hypot(x - mR[0], z - mR[1]))
            rest_ = 1 - 0.9 * corner                                        # what the corner leaves
            if b > 0.5:
                w['Jaw'] = jaw * 0.5 * smoothstep(0.0, 0.03, dcorner) * rest_     # flat bottom, rounded corners
                w['LeftLowerLip'] = lip * sx * 0.45 * rest_; w['RightLowerLip'] = lip * (1 - sx) * 0.45 * rest_
            else:
                w['Jaw'] = jaw * 0.5 * smoothstep(0.0, 0.03, dcorner) * rest_ * (1 - region)   # chin only, not the upper lip
                w['LeftUpperLip'] = lip * sx * 0.8 * rest_; w['RightUpperLip'] = lip * (1 - sx) * 0.8 * rest_
            w['LeftLipCorner'] = cl * 0.9; w['RightLipCorner'] = cr * 0.9      # sums stay <= 1: no renormalisation
            for s in 'LR':
                nms = 'Left' if s == 'L' else 'Right'
                ex, ez = EC[s]
                xs_ = [q[0] for q in EYES[s]]
                inx = smoothstep(min(xs_) - 0.03, min(xs_) + 0.02, x) * smoothstep(max(xs_) + 0.03, max(xs_) - 0.02, x)
                sp = vertical_span(EYES[s], min(max(x, min(xs_) + 0.001), max(xs_) - 0.001))
                ztop, zbot = sp
                # skin just above the eye stretches down a little when the lid closes (follows the eyeliner)
                above = smoothstep(ztop + 0.06, ztop, z) * (1.0 if z >= ztop - 0.002 else 0.0)
                lw = lash_drop(s, min(max(x, min(xs_) + 0.001), max(xs_) - 0.001)) / LASH_H[s]
                w[nms + 'Eyelash'] = 0.10 * above * inx * lw * frontish
                # lower lid / cheek
                below = smoothstep(zbot - 0.06, zbot - 0.005, z) * smoothstep(zbot + 0.012, zbot, z)
                w[nms + 'UnderEye'] = 0.9 * below * inx * frontish
                ck = gauss((x, z), (ex, zbot - 0.07), 0.07) * smoothstep(zbot + 0.005, zbot - 0.03, z) * frontish * 0.7
                w[nms + 'Cheek'] = ck if ck > 0.06 else 0.0
                # brows
                bmask = smoothstep(ztop + 0.02, ztop + 0.08, z) * frontish
                inner, outer = BROWS[s]
                w[nms + 'InnerBrow'] = gauss((x, z), inner, 0.075) * bmask
                w[nms + 'OuterBrow'] = gauss((x, z), outer, 0.085) * bmask
    w = {k: v for k, v in w.items() if v > 0.01}
    if len(w) > 3:
        w = dict(sorted(w.items(), key=lambda kv: -kv[1])[:3])
    tot = sum(w.values())
    if tot > 1:
        w = {k: v / tot for k, v in w.items()}; tot = 1.0
    if tot < 0.999:
        w['DynamicHead'] = 1 - tot
    weights.append(w)

# ---------------------------------------------------------------- FACS poses (in mask studs; rigid transforms)
def T(*d): return ('t', Vector(d))
def ROT(piv, axis, ang): return ('r', Vector(piv), axis, ang)
def eye_rot(s, axis, dist):
    xi, zi = IRIS_C[s]
    Rr = DISH_RH if axis == 'Z' else DISH_RV
    piv = (xi, DISH_B[s] - Rr, zi)
    return ROT(piv, axis, (-dist / Rr) if axis == 'Z' else (dist / Rr))   # Z: +dist -> iris to +X ; X: +dist -> iris up
def mirror(d):
    out = {}
    for k, v in d.items():
        k2 = k.replace('Left', '§').replace('Right', 'Left').replace('§', 'Right')
        if v[0] == 't':
            out[k2] = T(-v[1].x, v[1].y, v[1].z)
        else:
            out[k2] = v                                   # rotations are built per side, never mirrored
    return out
P = {}
P['EyesLookDown'] = {'LeftEye': eye_rot('L', 'X', -LOOK_Z), 'RightEye': eye_rot('R', 'X', -LOOK_Z)}
P['EyesLookUp'] = {'LeftEye': eye_rot('L', 'X', LOOK_Z), 'RightEye': eye_rot('R', 'X', LOOK_Z)}
P['EyesLookLeft'] = {'LeftEye': eye_rot('L', 'Z', LOOK_X), 'RightEye': eye_rot('R', 'Z', LOOK_X)}
P['EyesLookRight'] = {'LeftEye': eye_rot('L', 'Z', -LOOK_X), 'RightEye': eye_rot('R', 'Z', -LOOK_X)}
def lid_rot(key, frac=1.0):
    L = lid_info[key]
    return ('r', Vector(L['pivot']), Vector(L['axis']), L['angle'] * frac)
for s_, nm_ in (('L', 'Left'), ('R', 'Right')):
    P[nm_ + 'EyeClosed'] = {nm_ + 'UpperEyelid': lid_rot(s_), nm_ + 'LowerEyelid': lid_rot(s_ + 'low'),
                            nm_ + 'Eyelash': T(0, -0.002, -LASH_H[s_]), nm_ + 'UnderEye': T(0, -0.001, 0.003)}
    P[nm_ + 'CheekRaiser'] = {nm_ + 'Cheek': T(0, -0.004, 0.012), nm_ + 'UnderEye': T(0, -0.002, 0.012)}
    # corrective: closing + squinting must not over-rotate the lower lid
    P[nm_ + 'CheekRaiser_' + nm_ + 'EyeClosed'] = {nm_ + 'UpperEyelid': lid_rot(s_), nm_ + 'LowerEyelid': lid_rot(s_ + 'low'),
                              nm_ + 'Eyelash': T(0, -0.002, -LASH_H[s_]), nm_ + 'UnderEye': T(0, -0.002, 0.010),
                              nm_ + 'Cheek': T(0, -0.004, 0.012)}
P['LeftEyeUpperLidRaiser'] = {'LeftEyelash': T(0, 0, 0.008), 'LeftOuterBrow': T(0, 0, 0.006), 'LeftInnerBrow': T(0, 0, 0.004)}
P['LeftLipCornerPuller'] = {'LeftLipCorner': T(0.014, 0.006, 0.020), 'LeftCheek': T(0, -0.002, 0.004)}
P['LeftLipCornerDown'] = {'LeftLipCorner': T(0.004, 0.0, -0.018)}
P['LeftLipStretcher'] = {'LeftLipCorner': T(0.024, 0.002, -0.006)}
P['LeftLowerLipDepressor'] = {'LeftLowerLip': T(0.004, 0, -0.024)}
P['LeftUpperLipRaiser'] = {'LeftUpperLip': T(0, -0.003, 0.018)}
P['LeftBrowLowerer'] = {'LeftInnerBrow': T(-0.008, 0, -0.024), 'LeftOuterBrow': T(0, 0, -0.008)}
P['LeftInnerBrowRaiser'] = {'LeftInnerBrow': T(0, 0, 0.028)}
P['LeftOuterBrowRaiser'] = {'LeftOuterBrow': T(0, 0, 0.028)}
for k in list(P):
    if k.startswith('Left') and 'Right' + k[4:] not in P and '_' not in k:
        P['Right' + k[4:]] = mirror(P[k])
P['JawDrop'] = {'Jaw': T(0, 0.012, -0.095)}
P['ChinRaiser'] = {'Jaw': T(0, -0.010, 0.006), 'LeftLowerLip': T(0, -0.004, 0.0), 'RightLowerLip': T(0, -0.004, 0.0)}
P['ChinRaiserUpperLip'] = {'LeftUpperLip': T(0, -0.005, 0.006), 'RightUpperLip': T(0, -0.005, 0.006), 'Jaw': T(0, -0.004, 0.003)}
P['LipsTogether'] = {'LeftLowerLip': T(0, -0.002, 0.004), 'RightLowerLip': T(0, -0.002, 0.004),
                     'LeftUpperLip': T(0, -0.002, -0.002), 'RightUpperLip': T(0, -0.002, -0.002)}
P['Pucker'] = {'LeftLipCorner': T(-0.022, -0.012, 0.002), 'RightLipCorner': T(0.022, -0.012, 0.002),
               'LeftUpperLip': T(-0.006, -0.012, -0.002), 'RightUpperLip': T(0.006, -0.012, -0.002),
               'LeftLowerLip': T(-0.006, -0.012, 0.003), 'RightLowerLip': T(0.006, -0.012, 0.003)}
ORDER = sorted(k for k in P if '_' not in k) + sorted(k for k in P if '_' in k)   # base poses A-Z, then combinations
REQUIRED = ['LeftEyeClosed', 'RightEyeClosed', 'EyesLookDown', 'JawDrop', 'Pucker', 'LeftLipCornerPuller',
            'RightLipCornerPuller', 'ChinRaiser', 'ChinRaiserUpperLip', 'LeftCheekRaiser', 'RightCheekRaiser',
            'LeftInnerBrowRaiser', 'RightInnerBrowRaiser', 'LeftLipCornerDown', 'RightLipCornerDown',
            'LeftLowerLipDepressor', 'RightLowerLipDepressor']
missing = [r for r in REQUIRED if r not in P]
assert not missing, missing
print('poses', len(ORDER))

# ---------------------------------------------------------------- place the head on the official Blocky body
REF = os.path.join(ROOT, 'in', 'roblox_ref', 'BlockyCharacter.fbx')
bpy.ops.import_scene.fbx(filepath=REF)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
old_head = next(o for o in bpy.data.objects if o.name.startswith('Head_Geo') and o is not head)
hb_lo = Vector([min((old_head.matrix_world @ v.co)[i] for v in old_head.data.vertices) for i in range(3)])
hb_hi = Vector([max((old_head.matrix_world @ v.co)[i] for v in old_head.data.vertices) for i in range(3)])
bpy.data.objects.remove(old_head)
head.name = 'Head_Geo'; head.data.name = 'Head_Geo'
my_lo = Vector([min(v.co[i] for v in head.data.vertices) for i in range(3)])
my_hi = Vector([max(v.co[i] for v in head.data.vertices) for i in range(3)])
S = (hb_hi.z - hb_lo.z) / (HEAD_H)                       # standard 1.2 stud head height
TR = Vector((0, (hb_lo.y + hb_hi.y) / 2, (hb_lo.z + hb_hi.z) / 2))
M = Matrix.Translation(TR) @ Matrix.Scale(S, 4)
print('head scale', round(S, 4), 'centre', tuple(round(v, 3) for v in TR))
def MP(p): return M @ Vector(p)
AW = arm.matrix_world.copy(); AL = AW.inverted()          # the reference armature is Y-up (rotated 90 deg)

# drop the reference face rig + its animation, keep Head / DynamicHead
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
for b in [b for b in eb if b.parent and b.parent.name == 'DynamicHead']:
    for c in b.children_recursive: eb.remove(c)
    eb.remove(b)
dyn = eb['DynamicHead']
for name, pos in FACE_BONES.items():
    b = eb.new(name)
    b.head = AL @ MP(pos); b.tail = AL @ (MP(pos) + Vector((0, 0, 0.03))); b.roll = 0
    b.parent = dyn
bpy.ops.object.mode_set(mode='OBJECT')
if arm.animation_data: arm.animation_data.action = None
for a in list(bpy.data.actions): bpy.data.actions.remove(a)

head.data.transform(AL @ M)
for bn in ['DynamicHead'] + list(FACE_BONES):
    head.vertex_groups.new(name=bn)
for idx, w in enumerate(weights):
    for bn, val in w.items():
        head.vertex_groups[bn].add([idx], val, 'REPLACE')
head.parent = arm
for m in list(head.modifiers): head.modifiers.remove(m)
am = head.modifiers.new('Armature', 'ARMATURE'); am.object = arm

# ---------------------------------------------------------------- keyframes: neutral + one FACS pose per frame, face joints only
arm.animation_data_create()
act = bpy.data.actions.new('FACS'); arm.animation_data.action = act
scn = bpy.context.scene
scn.frame_start, scn.frame_end = 0, len(ORDER)
scn.render.fps = 30
FACE = list(FACE_BONES)
def set_pose(pose):
    for bn in FACE:
        pb = arm.pose.bones[bn]
        pb.rotation_mode = 'QUATERNION'
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
        if pose and bn in pose:
            v = pose[bn]
            if v[0] == 't':
                Mw = Matrix.Translation(v[1] * S)
            else:
                piv = MP(v[1])
                ax = v[2] if isinstance(v[2], str) else Vector(v[2]).normalized()
                Mw = Matrix.Translation(piv) @ Matrix.Rotation(v[3], 4, ax) @ Matrix.Translation(-piv)
            Ma = AL @ Mw @ AW                                  # world -> armature space
            basis = pb.bone.matrix_local.inverted() @ Ma @ pb.bone.matrix_local
            loc, rot, sca = basis.decompose()
            pb.location = loc; pb.rotation_quaternion = rot
for fr, name in enumerate(['Neutral'] + ORDER):
    set_pose(P.get(name))
    for bn in FACE:
        pb = arm.pose.bones[bn]
        pb.keyframe_insert('location', frame=fr)
        pb.keyframe_insert('rotation_quaternion', frame=fr)

# ---------------------------------------------------------------- FACS mapping on Head_Geo (the only extra attributes)
for k in list(head.keys()): del head[k]
head['RootFaceJoint'] = 'DynamicHead'
MAP = {f'Frame{i}': n for i, n in enumerate(['Neutral'] + ORDER)}
for k, v in MAP.items(): head[k] = v
json.dump(dict(frames=MAP, triangles=tris, head_scale=S, head_centre=list(TR)), open(os.path.join(OUT, 'facs_map.json'), 'w'), indent=1)

# ---------------------------------------------------------------- outer cage: Blocky head cage (same topology / UVs /
# landmarks), its eye + mouth landmarks warped onto this face, then wrapped around this head
cage = bpy.data.objects['Head_OuterCage']
cbm = bmesh.new(); cbm.from_mesh(cage.data); cbm.transform(cage.matrix_world)
ref_feat = {'L': Vector((0.111, 2.675)), 'R': Vector((-0.111, 2.675)), 'M': Vector((0.0, 2.30))}
my_feat = {s: Vector((MP((EC[s][0], 0, EC[s][1])).x, MP((EC[s][0], 0, EC[s][1])).z)) for s in 'LR'}
mcx = MP((MOUTH_C[0], 0, MOUTH_C[1])); my_feat['M'] = Vector((mcx.x, mcx.z))
hc = TR
for v in cbm.verts:
    if v.co.y < hc.y - 0.25:                                   # front of the cage only
        q = Vector((v.co.x, v.co.z)); disp = Vector((0, 0)); wsum = 0
        for k in ref_feat:
            wgt = math.exp(-((q - ref_feat[k]).length / 0.16) ** 2)
            disp += wgt * (my_feat[k] - ref_feat[k]); wsum += wgt
        q2 = q + disp * min(1.0, wsum)
        v.co.x, v.co.z = q2.x, q2.y
hbm = bmesh.new(); hbm.from_mesh(head.data); hbm.transform(AW)
HB = BVHTree.FromBMesh(hbm)
for v in cbm.verts:                                            # wrap: 1.2 cm outside this head along the ray from the centre
    d = (v.co - hc).normalized()
    loc, nrm, _, dist = HB.ray_cast(hc + d * 2.0, -d)
    if loc is not None:
        v.co = loc + d * 0.012
cbm.transform(cage.matrix_world.inverted()); cbm.to_mesh(cage.data); cbm.free(); hbm.free()

# attachments: face front on the face surface
ffa = bpy.data.objects.get('FaceFront_Att')
if ffa:
    p = ffa.matrix_world.translation.copy(); p.y = MP((0, surf_y(0, (p.z - TR.z) / S), (p.z - TR.z) / S)).y
    mw = ffa.matrix_world.copy(); mw.translation = p; ffa.matrix_world = mw

# ---------------------------------------------------------------- smooth shading of the outer skin: custom normals taken from
# the smooth base surface, so long / irregular triangles (boolean rims, mouth patch) never show as shading facets
bt = bmesh.new(); bt.from_mesh(base.data) if False else None
tri_base = bm_base.copy(); bmesh.ops.triangulate(tri_base, faces=tri_base.faces[:])
tri_base.verts.ensure_lookup_table(); tri_base.faces.ensure_lookup_table(); tri_base.normal_update()
TB = BVHTree.FromBMesh(tri_base)
from mathutils.geometry import barycentric_transform
Minv = (M.inverted()) @ AW                     # armature-local -> mask studs
R3 = AL.to_3x3()
me = head.data
uvd = me.uv_layers['UVMap'].data
def skin_loop(li):
    u, v = uvd[li].uv; px, py = u * ATLAS, (1 - v) * ATLAS
    return py <= FACE_RECT[1] + FACE_RECT[3] + 1 or (CLEAR_RECT[0] - 1 <= px <= CLEAR_RECT[0] + CLEAR_RECT[2] + 1 and CLEAR_RECT[1] - 1 <= py <= CLEAR_RECT[1] + CLEAR_RECT[3] + 1)
cur = [Vector(n.vector) for n in me.corner_normals]
lid_or_inner = set().union(*[IRIS_IDX[s_] | LID_IDX[s_] | LOWLID_IDX[s_] | LASH_IDX[s_] | CUP_IDX[s_] for s_ in 'LR'])
newn = []
nset = 0
for poly in me.polygons:
    for li in poly.loop_indices:
        vi = me.loops[li].vertex_index
        if vi < SHELL_N and vi not in lid_or_inner and skin_loop(li) and SOCK[vi] is None:
            pm = Minv @ me.vertices[vi].co
            loc, _, fi, _ = TB.find_nearest(pm)
            f = tri_base.faces[fi]
            a, b, c = [x.co for x in f.verts]
            na, nb, nc = [x.normal for x in f.verts]
            w = barycentric_transform(loc, a, b, c, Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
            n = (na * w.x + nb * w.y + nc * w.z).normalized()
            newn.append((R3 @ n).normalized()); nset += 1
        else:
            newn.append(cur[li])
me.normals_split_custom_set(newn)
print('custom skin normals', nset)

# ---------------------------------------------------------------- material + save + export
mat = bpy.data.materials.new('HeadMat'); head.data.materials.clear(); head.data.materials.append(mat)
scn.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'head_rig.blend'))
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
    o.hide_set(False); o.hide_select = False; o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.fbx(
    filepath=os.path.join(ROOT, 'AnimeDynamicHead_Blocky.fbx'), use_selection=True, object_types={'ARMATURE', 'MESH'},
    use_custom_props=True, add_leaf_bones=False, armature_nodetype='NULL', use_armature_deform_only=False,
    bake_anim=True, bake_anim_use_all_bones=False, bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
    bake_anim_force_startend_keying=False, bake_anim_step=1.0, bake_anim_simplify_factor=0.0,
    axis_forward='-Z', axis_up='Y', apply_unit_scale=True, apply_scale_options='FBX_SCALE_UNITS', global_scale=1.0,
    path_mode='STRIP', mesh_smooth_type='FACE', use_mesh_modifiers=False)
print('exported')
