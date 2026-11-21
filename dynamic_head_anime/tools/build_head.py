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
DISH_D = float(os.environ.get('DISH_D', 0.10))   # depth of the sclera dish behind the face at the iris centre (concave -> eyes follow the camera)
DISH_RH = float(os.environ.get('DISH_RH', 0.42))   # curvature radii of the dish (horizontal, vertical): the inside of
DISH_RV = float(os.environ.get('DISH_RV', 0.26))   # an inverted eyeball; centres of curvature are in front
DISH_MIN = 0.006          # the dish never comes closer than this to the face surface
IRIS_OFF = 0.0025         # iris disc floats this much in front of the sclera dish
CUP_STEP = 0.04
SOCKET_EXTRA = 0.15       # cutter goes this much deeper than the deepest cup point
EYE_DC = float(os.environ.get('EYE_DC', 0.135))  # depth of the eyeball centre behind the face (at the iris centre)
EYE_STYLE = os.environ.get('EYE_STYLE', 'sphere')   # 'sphere': inverted iris sphere + pupil ball; 'flat': the drawn eye
                                                    # (iris + pupil) on a flat disc glued to the back of the white hole
FLAT_D = float(os.environ.get('FLAT_D', 0.085))      # flat style: depth of the back of the hole behind the face (iris centre)
IRIS_SPH_K = float(os.environ.get('IRIS_SPH_K', 1.0))   # iris sphere radius / drawn iris radius
CAVE_SIDE = 0.035         # ... and sideways at the corners (the iris sphere never touches a side wall)
CAVE_DOWN = 0.075         # the socket also widens downwards behind the lower rim (the iris ball is seen whole from above)
CAVE_H = 0.105            # the socket widens UPWARDS inside the head (a cave larger than its entrance): seen from
                          # below, the whole round iris and the white around it are visible (no flat white ceiling)
CAVE_D0, CAVE_D1 = 0.004, 0.065  # depth where the widening starts / is complete (the rim keeps the opening's shape)
if EYE_STYLE == 'flat':
    # flat eyes: the floor of the hole stays level with the opening (no hollow going down), the hole is shallower and
    # its white back wall sits right behind the drawn eye
    CAVE_DOWN = 0.0
    CAVE_D1 = 0.03
FLAT_YAW = math.radians(float(os.environ.get('FLAT_YAW', 25)))   # flat style: the drawn eye and the white wall behind it
                                                      # are ONE flat plane turned towards the outside of the face (diagonal
                                                      # seen from above): seen from the side you still see the iris
def flat_plane_y(s, x):
    """depth (y) of the flat eye plane at x: deeper towards the outer corner"""
    xi = IRIS_C[s][0]; out = 1.0 if xi > 0 else -1.0
    return EYE_C[s].y + math.tan(FLAT_YAW) * (x - xi) * out
LOOK_X, LOOK_Z = 0.035, 0.02
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
def cave_raise(s, x, z):
    """how much the cave ceiling is above the opening's top rim (fully widened), 0 on the lower rim / corners"""
    xs = [p[0] for p in EYES[s]]; x0, x1 = min(xs), max(xs)
    sp = vertical_span(EYES[s], min(max(x, x0 + 1e-4), x1 - 1e-4))
    if sp is None: return 0.0
    u = (x - (x0 + x1) / 2) / ((x1 - x0) / 2)
    shape = max(0.0, 1 - (0.9 * u) ** 4) ** 0.5
    return CAVE_H * shape if z >= (sp[0] + sp[1]) / 2 else -CAVE_DOWN * shape
def cave_frac(d):
    t = max(0.0, min(1.0, (d - CAVE_D0) / (CAVE_D1 - CAVE_D0)))
    return t * t * (3 - 2 * t)
def cave_side(s, x):
    xs = [e[0] for e in EYES[s]]; xc = (min(xs) + max(xs)) / 2; hw = (max(xs) - min(xs)) / 2
    u = (x - xc) / hw
    return math.copysign(1.0, u) * CAVE_SIDE * max(0.0, min(1.0, (abs(u) - 0.6) / 0.4)) ** 2
CAVE_POLY = {s: [(x + cave_side(s, x), z + cave_raise(s, x, z)) for x, z in EYES[s]] for s in 'LR'}   # fully widened outline
def surf_nb(x, z):
    """deepest face surface around (x, z) within a gaze shift: the face curves back towards the temples"""
    return max((surf_y(x + dx, z + dz) or -9) for dx in (-0.035, 0, 0.035) for dz in (-0.022, 0, 0.022))
EYE_R = {s: IRIS_SPH_K * IRIS[s][2] for s in 'LR'}   # iris sphere radius = the drawn iris (same size as the black ball)
EYE_DROP = 0.0 if EYE_STYLE == 'flat' else float(os.environ.get('EYE_DROP', 0.028))   # the eye (iris sphere + pupil) sits this much lower than the drawn
                                                      # iris centre, so the pupil is not hidden under the eyeliner
def _eye_depth(s):
    """smallest depth of the eye-sphere centre (>= EYE_DC) for which the whole sphere stays behind the skin (and behind
    the closed lid over the opening): a sphere turning about its centre always fills the same volume, so this holds for
    every gaze"""
    xi, zi = IRIS_C[s][0], IRIS_C[s][1] - EYE_DROP; y0 = surf_y(xi, zi)
    dirs = []
    for i in range(1, 19):
        th = math.radians(i * 5)                                     # front hemisphere, 5..90 deg from the front pole
        for k in range(36):
            ph = 2 * math.pi * k / 36
            dirs.append((math.sin(th) * math.cos(ph), -math.cos(th), math.sin(th) * math.sin(ph)))
    dirs.append((0.0, -1.0, 0.0))
    dc = EYE_DC
    while dc < 0.4:
        ok = True
        for dx, dy, dz in dirs:
            x, y, z = xi + EYE_R[s] * dx, y0 + dc + EYE_R[s] * dy, zi + EYE_R[s] * dz
            sy = surf_y(x, z)
            if sy is None: continue
            inside = pip((x, z), EYES[s]) and poly_dist((x, z), EYES[s]) > 0.004
            if y < sy + (0.008 if inside else 0.014):
                ok = False; break
        if ok: break
        dc += 0.0025
    return dc
EYE_DEPTH = {s: (FLAT_D if EYE_STYLE == 'flat' else _eye_depth(s)) for s in 'LR'}
EYE_C = {s: Vector((IRIS_C[s][0], surf_y(IRIS_C[s][0], IRIS_C[s][1] - EYE_DROP) + EYE_DEPTH[s], IRIS_C[s][1] - EYE_DROP)) for s in 'LR'}   # eye centres
print('eye sphere centre depth', {s: round(v, 4) for s, v in EYE_DEPTH.items()})

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
# the back of the head never deforms and is never seen up close: half the grid density there (its shading comes from
# the smooth base surface normals anyway) -> triangles for round 3D eyes
bmesh.ops.unsubdivide(bm, verts=[v for v in bm.verts if v.co.y > 0.25], iterations=2)
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
    yb = EYE_C[s].y + EYE_R[s] + 0.06                          # behind the back of the iris sphere
    if EYE_STYLE == 'flat':
        yb = EYE_C[s].y + 0.004                                  # flat back wall, right behind the drawn eye
    eye_back[s] = yb
    # loft: straight through the skin, then widening upwards behind it
    rings = [[(x, -1.5, z) for x, z in EYES[s]]]
    def ring_pt(x, z, d):
        cr = cave_raise(s, x, z)
        # up: widens from CAVE_D0; down: only from 3 cm deep (straight under the lower rim first: the cheek is close)
        fr = cave_frac(d) if cr >= 0 else max(0.0, min(1.0, (d - 0.03) / (CAVE_D1 - 0.03)))
        z2 = z + cr * fr
        x = x + cave_side(s, x) * cave_frac(d)
        # behind the skin both at the rim AND where the widened outline lands (the cheek recedes under the eye)
        y = max(surf_y(x, z) + d, (surf_y(x, z2) or -9) + max(d, 0.03) if d > CAVE_D0 else -9)
        return (x, y, z2)
    for d in ((CAVE_D0, 0.018, CAVE_D1) if EYE_STYLE == 'flat' else (CAVE_D0, 0.03, CAVE_D1)):
        rings.append([ring_pt(x, z, d) for x, z in EYES[s]])
    if EYE_STYLE == 'flat':                                     # the white back wall = the eye plane, 4 mm behind it
        rings.append([(rings[-1][i][0], max(flat_plane_y(s, rings[-1][i][0]) + 0.004, rings[-1][i][1] + 0.004),
                       z + cave_raise(s, x, z)) for i, (x, z) in enumerate(EYES[s])])
    else:
        rings.append([(rings[-1][i][0], max(yb, rings[-1][i][1] + 0.05), z + cave_raise(s, x, z)) for i, (x, z) in enumerate(EYES[s])])
    vr = [[bc.verts.new(p) for p in r] for r in rings]
    n = len(EYES[s])
    bc.faces.new(vr[0]); bc.faces.new(vr[-1][::-1])
    for a, b in zip(vr, vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            bc.faces.new((a[i], a[j], b[j], b[i]))
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
def set_skin_uv(f):
    """face block UVs only if the whole face is inside the face window, else plain skin (never another atlas block)"""
    if all(in_face_window(v.co.x, v.co.z) for v in f.verts):
        for l in f.loops: l[uvl].uv = face_uv(l.vert.co.x, l.vert.co.z)
    else:
        for l in f.loops: l[uvl].uv = CLEAR_UV
WALL_UP_UV = rect_center_uv(WALL_UP_RECT); WALL_LO_UV = rect_center_uv(WALL_LO_RECT)
def socket_of(p):
    sy = surf_y(p.x, p.z)
    if sy is None or p.y < sy + 0.0025 or p.y > sy + 0.45:      # only the eye / mouth cavities (not the back of the head!)
        return None
    for s in 'LR':
        q = (p.x, p.z)
        if pip(q, EYES[s]) or poly_dist(q, EYES[s]) < 0.002:
            return s
        if pip(q, CAVE_POLY[s]) or poly_dist(q, CAVE_POLY[s]) < 0.002:
            # the widened part of the socket: above the eye it starts right behind the rim; below the eye only from
            # 3 cm deep (shallower points there are cheek skin, a little behind the ideal surface)
            sp = vertical_span(EYES[s], min(max(p.x, min(e[0] for e in EYES[s]) + 1e-4), max(e[0] for e in EYES[s]) - 1e-4))
            xs_e = [e[0] for e in EYES[s]]
            below = sp is not None and p.z < sp[1] and min(xs_e) + 0.03 < p.x < max(xs_e) - 0.03
            # outside the opening itself, shallow points are skin (the shell's chords lie a few mm behind the ideal
            # surface): the widened socket is only there deeper than 1.2 cm (2.5 cm under the eye)
            if p.y > sy + (0.025 if below else 0.012):
                return s
    q = (p.x, p.z)
    if pip(q, MOUTH_POLY) or poly_dist(q, MOUTH_POLY) < 0.002:
        return 'M'
    return None
n_face = 0
for f in bm.faces:
    c = f.calc_center_median()
    sk = socket_of(c)
    if sk is None:
        # the first, shallow band of the socket wall (rim -> 4 mm deep, before the cave widens): its centre is barely
        # behind the surface, but it is a wall: one of its vertices is inside the socket and it hugs the outline
        vs_ = [socket_of(v.co) for v in f.verts]
        for s_ in 'LR':
            if s_ in vs_ and poly_dist((c.x, c.z), EYES[s_]) < 0.003 and abs(f.normal.y) < 0.9:
                sk = s_
    if sk in ('L', 'R'):
        rect = WALL_LO_RECT                                       # plain deep white everywhere in the socket (no shading band)
        for l in f.loops:
            co = l.vert.co
            l[uvl].uv = wall_uv(rect, co.y - surf_y(co.x, co.z))
    elif sk == 'M':
        for l in f.loops: l[uvl].uv = MOUTH_UV
    elif f.normal.y < -0.2 and all(in_face_window(v.co.x, v.co.z) for v in f.verts):
        n_face += 1
        set_skin_uv(f)
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
kill = [f for f in bm.faces if f.calc_center_median().y < -0.3 and any(pip((v.co.x, v.co.z), cut2d) for v in f.verts)]
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
    set_skin_uv(f)
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
    set_skin_uv(f)
# mouth bag: walls + strip floor
# straight tube; every back vertex is skinned EXACTLY like its rim vertex (see weights), so the bag moves rigidly
# with the lips: its walls can never be turned towards the inside (a wall seen from behind = a hole in Roblox)
back = [bm.verts.new(v.co + Vector((0, MOUTH_DEPTH, 0))) for v in rings[0]]
BAG_PAIRS = list(zip(rings[0], back))
def mface(vs, want):
    f = bm.faces.new(vs); f.smooth = False
    f.normal_update()
    if f.normal.dot(want) < 0: f.normal_flip()
    for l in f.loops: l[uvl].uv = MOUTH_UV
mc3 = Vector((MOUTH_C[0], surf_y(*MOUTH_C) + MOUTH_DEPTH * 0.5, MOUTH_C[1]))
for j in range(M2):
    j2 = (j + 1) % M2
    a, b2, c2, d2 = rings[0][j], rings[0][j2], back[j2], back[j]
    # walls face into the bag: upper-lip walls look down, lower-lip walls look up (decided by the lip, not by the
    # bag centre: near the corners a wall is almost flat and the centre test could pick the outer side)
    sg_ = slit2[j][2] or slit2[j2][2]
    if sg_:
        want = Vector((0, 0, -1.0 if sg_ > 0 else 1.0))
    else:
        mid = (a.co + b2.co + c2.co + d2.co) / 4
        want = Vector((mc3.x - mid.x, 0, mc3.z - mid.z))
    mface((a, b2, c2, d2), want)
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

# ---------------------------------------------------------------- 3D eyes: inverted IRIS sphere + black pupil ball at its centre
# Each eye has exactly two meshes in the white socket:
#   - the IRIS: a complete sphere the size of the drawn iris, seen from the INSIDE (inverted mesh: its front half is
#     back-facing, so invisible), with the drawn iris (rings, highlight, drawn pupil removed) projected on it;
#   - the PUPIL: a real black 3D ball (normal mesh) exactly at the centre of the iris sphere.
# The pupil is nearer than the iris painted on the far wall of the sphere, so when you move around it slides towards
# you: the eye follows you.  The white around is the white socket itself.  Gaze: the iris sphere turns, the pupil follows.
PUPIL_K = float(os.environ.get('PUPIL_K', 0.45))    # pupil ball radius / drawn iris radius
cup_verts = {'L': [], 'R': []}
iris_verts = {'L': [], 'R': []}
def sph_dir(theta, phi, back=True):
    """unit vector; theta from the back (+Y) pole if back else from the front (-Y) pole"""
    st, ct = math.sin(theta), math.cos(theta)
    return Vector((st * math.cos(phi), ct if back else -ct, st * math.sin(phi)))
def uv_sphere(C, R, seg, lats, inward, uvf, store):
    """closed UV sphere; lats = latitudes in degrees from the front pole (0 and 180 are the poles)"""
    fpole = bm.verts.new(C + sph_dir(0, 0, back=False) * R); store.append(fpole)
    bpole = bm.verts.new(C + sph_dir(0, 0, back=True) * R); store.append(bpole)
    rows = []
    for la in lats[1:-1]:
        row = []
        for k in range(seg):
            v = bm.verts.new(C + sph_dir(math.radians(la), 2 * math.pi * k / seg, back=False) * R)
            row.append(v); store.append(v)
        rows.append(row)
    def face(vs):
        f = bm.faces.new(vs); f.smooth = True
        f.normal_update()
        cen_ = sum((v.co for v in vs), Vector()) / len(vs)
        out = f.normal.dot(cen_ - C) > 0
        if out == inward: f.normal_flip()
        for l in f.loops: l[uvl].uv = uvf(cen_, l.vert.co)
    for k in range(seg):
        k2 = (k + 1) % seg
        face((fpole, rows[0][k], rows[0][k2]))
        for j in range(len(rows) - 1):
            face((rows[j][k], rows[j + 1][k], rows[j + 1][k2], rows[j][k2]))
        face((rows[-1][k], bpole, rows[-1][k2]))
def flat_disc(s, store):
    """flat eye: the drawn iris WITH its pupil on an elliptic disc facing the front, glued to the back of the hole"""
    xi, zi, rx, rz = IRIS[s]; C = EYE_C[s]; seg = 28
    def P_(x, z): return (x, flat_plane_y(s, x), z)
    rows = [[bm.verts.new(P_(xi + f * rx * math.cos(2 * math.pi * k / seg), zi + f * rz * math.sin(2 * math.pi * k / seg)))
             for k in range(seg)] for f in (0.4, 0.75, 1.0)]
    cen = bm.verts.new(P_(xi, zi))
    store += [cen] + [v for r in rows for v in r]
    def face(vs):
        f = bm.faces.new(vs); f.smooth = False
        f.normal_update()
        if f.normal.y > 0: f.normal_flip()
        for l in f.loops: l[uvl].uv = eye_tex_uv(s, l.vert.co.x, l.vert.co.z)
    for k in range(seg):
        k2 = (k + 1) % seg
        face((cen, rows[0][k], rows[0][k2]))
        for j in range(len(rows) - 1):
            face((rows[j][k], rows[j + 1][k], rows[j + 1][k2], rows[j][k2]))
for s in ('LR' if EYE_STYLE == 'flat' else ''):
    flat_disc(s, cup_verts[s])
    print('eye', s, 'flat drawn eye disc %.3f behind the face' % EYE_DEPTH[s])
for s in ('' if EYE_STYLE == 'flat' else 'LR'):
    xi, zi, r0, _ = IRIS[s]
    C = EYE_C[s]
    R_ = EYE_R[s]
    # the whole sphere (seen from the inside) carries the drawn iris, projected from the front (its outer ring sampled
    # just inside the rim: no white border)
    uv_sphere(C, R_, 20, [0, 30, 60, 90, 120, 150, 180], True,
              lambda cen_, co: eye_tex_uv(s, xi + (co.x - C.x) * 0.93 * r0 / R_, zi + (co.z - C.z) * 0.93 * r0 / R_),
              cup_verts[s])
    BALL_UV = rect_center_uv(BALL_RECT)
    rp = PUPIL_K * r0
    uv_sphere(C, rp, 18, [0, 22.5, 45, 67.5, 90, 112.5, 135, 157.5, 180], False, lambda cen_, co: BALL_UV, iris_verts[s])
    print('eye', s, 'iris sphere radius %.3f (inverted), pupil ball radius %.3f at its centre, %.3f behind the face' % (R_, rp, EYE_DEPTH[s]))
bm.normal_update()

# ---------------------------------------------------------------- eyelid: ONE rigid skin lid + the 3D eyeliner on ONE bone
# Both SLIDE together (one translation, down along the face and slightly forward):
#   rest  : the lid is parked behind the skin above the eye, the eyeliner sits on its rim
#   closed: the lid covers the whole opening (tucked under the skin all around), the eyeliner lies on the lower rim
# Same bone for both -> the eyeliner stays glued to the lid edge at every blend value (no plate, no gap), and since
# nothing rotates the lid keeps the skin's normals (same shading as the skin around it at every moment).
# the REAL skin (triangulated shell, not the smooth base surface): what the lid must hide behind
bm.normal_update()
_sk_faces = [f for f in bm.faces if f.normal.y < 0 and all(socket_of(v.co) is None for v in f.verts)]
_sk_verts = {v: i for i, v in enumerate({v for f in _sk_faces for v in f.verts})}
SKIN_BVH = BVHTree.FromPolygons([v.co.copy() for v in _sk_verts], [[_sk_verts[v] for v in f.verts] for f in _sk_faces])
def skin_y(x, z):
    loc, n, i, d = SKIN_BVH.ray_cast(Vector((x, -3.0, z)), Vector((0, 1, 0)))
    sy = surf_y(x, z)
    if loc is None or loc.y - sy > 0.008: return sy   # no skin right here (opening): the base surface
    return max(loc.y, sy)                # the deeper of the two (chords of the shell lie behind the base surface)
LID_DOME = 0.004
LID_COLS, LID_ROWS = 12, 7     # columns: one tucked beyond each corner, one right at the outline, 12 across
LASH_T = 0.011            # eyeliner thickness in front of the face
LASH_OVER = 0.0055        # eyeliner overhang below the opening's top rim
def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
def eye_xr(s):
    xs = [p[0] for p in EYES[s]]
    return min(xs), max(xs)
def span_c(s, x):
    x0, x1 = eye_xr(s)
    return vertical_span(EYES[s], min(max(x, x0 + 0.0015), x1 - 0.0015))
def inside_d(s, x, z):
    """signed distance to the opening outline (positive inside)"""
    d = poly_dist((x, z), EYES[s])
    return d if pip((x, z), EYES[s]) else -d
lid_info = {}
PULL = {}
LID_D = float(os.environ.get('LID_D', 0.0025))   # how far behind the skin the lid slides back up
for s in 'LR':
    x0, x1 = eye_xr(s)
    xc = (x0 + x1) / 2
    top, bot = span_c(s, xc)
    # The face is vertical around the eyes (its normals have no vertical component there), so the lid simply SLIDES
    # down along it (a translation, slightly forward): it stays on the skin surface at every blend value and its
    # normals never turn -> it is shaded exactly like the skin around it (no lighter "plate").
    pivot = Vector((xc, surf_y(xc, (top + bot) / 2) + 0.03, (top + bot) / 2))   # bone head, behind the eye
    xq0, xq1 = x0 + 0.25 * (x1 - x0), x1 - 0.25 * (x1 - x0)
    bq0, bq1 = span_c(s, xq0)[1], span_c(s, xq1)[1]
    def lid_bottom(x):
        """lower edge of the closed lid: the lower rim, but kept low in the corners (where the almond outline rises)
        so that the lid never uncovers a corner of the opening while it slides; the extra part stays under the skin"""
        line = bq0 + (bq1 - bq0) * (x - xq0) / (xq1 - xq0)
        return min(span_c(s, x)[1], line) - 0.001
    def lift(dz, f):           # rest (parked) = closed + lift(dz, 1)
        return Vector((0.0, LID_D * f, dz * f))
    def real_y(x, z):
        """the real (triangulated) skin level; across the opening: the base surface shifted to meet the real rims"""
        tp, bt = span_c(s, x)
        if z >= tp or z <= bt:
            return skin_y(x, z)
        za, zb = tp + 0.0012, bt - 0.0012
        oa, ob = skin_y(x, za) - surf_y(x, za), skin_y(x, zb) - surf_y(x, zb)
        u = (tp - z) / max(tp - bt, 1e-6)
        return surf_y(x, z) + oa + (ob - oa) * u
    def closed_pt(x, t, dz):
        tp, bt = span_c(s, x)
        r_ = round(t * LID_ROWS)                                        # row 0 above the top rim, row 1 right at it, then down
        z = (tp + 0.005) if r_ == 0 else (tp - 0.001) + (lid_bottom(x) - (tp - 0.001)) * (r_ - 1) / (LID_ROWS - 1)
        sy = surf_y(x, z)
        # tucked under the skin only if the point is never over the opening during the slide
        sd = max(inside_d(s, x, z + dz * f / 10) for f in range(11))
        y_d = real_y(x, z) + 0.00015 + 0.0006 * smoothstep(0.0, 0.002, bt - z)   # a hair behind the rims (no step); more below the lower rim
        if sd < 0:
            y_d = y_d + (skin_y(x, z) + 0.0025 - y_d) * smoothstep(0.0, 0.002, -sd)
        c = Vector((x, y_d, z))
        # wherever it is NOT over the opening it must be behind the (real, triangulated) skin at every moment
        need = 0.0
        for f in range(11):
            q = c + lift(dz, f / 10)
            if inside_d(s, q.x, q.z) < -0.0005:
                need = max(need, skin_y(q.x, q.z) + 0.0003 + 0.0007 * f / 10 - q.y)
        c.y += need
        PULL[(s, round(x, 3), round(z, 3))] = (inside_d(s, x, z), z - bt, need)
        return c
    xa, xb = x0 - 0.008, x1 + 0.008
    lid_xs = [xa] + [x0 + 0.0015 + (x1 - x0 - 0.003) * (0.5 - 0.5 * math.cos(math.pi * k / (LID_COLS - 2))) for k in range(LID_COLS - 1)] + [xb]   # dense in the corners
    def parked_margin(grid, dz):
        """worst clearance of the parked lid: behind the skin where there is skin, under the eyeliner overhang where
        it is over the opening"""
        worst = 9
        for row in grid:
            for c in row:
                q = c + lift(dz, 1.0)
                if pip((q.x, q.z), EYES[s]):
                    tp, bt = span_c(s, q.x)
                    # tucked high under the eyeliner: the band stands 1.1 cm out, so seen from below (up to ~50 deg)
                    # the lid edge must sit well above its lower edge, or it peeks out as a light strip
                    m = q.z - (tp - LASH_OVER + 0.002) - LID_TUCK
                else:
                    m = q.y - (skin_y(q.x, q.z) + 0.0009)                 # behind the skin
                worst = min(worst, m)
        return worst
    LID_TUCK = float(os.environ.get('LID_TUCK', 0.0015))
    # smallest lift that parks the lid out of sight
    dz = max(span_c(s, x)[0] - LASH_OVER + 0.002 - lid_bottom(x) for x in lid_xs[1:-1]) - 0.004
    while True:
        grid = [[closed_pt(lid_xs[i], r / LID_ROWS, dz) for i in range(LID_COLS + 1)] for r in range(LID_ROWS + 1)]
        if parked_margin(grid, dz) >= 0.0 or dz > 0.2: break
        dz += 0.001
    t_close = -lift(dz, 1.0)
    R_close = Matrix.Translation(t_close); R_open = Matrix.Translation(-t_close)
    if os.environ.get('LID_DEBUG'):
        for k, (sd0, dzb, pl) in sorted(PULL.items()):
            if k[0] == s and pl > 0.0008 and sd0 > -0.002: print('LIDPULL', k, 'sd %.4f above-bottom %.4f pushed back %.4f' % (sd0, dzb, pl))
    print('lid', s, 'slide %.4f down, %.4f forward, parked clearance %.4f' % (dz, LID_D, parked_margin(grid, dz)))
    closed = {}
    vrows = []
    for row in grid:
        vr = []
        for c in row:
            v = bm.verts.new(R_open @ c); closed[v] = c; vr.append(v)
        vrows.append(vr)
    for r in range(LID_ROWS):
        for i in range(LID_COLS):
            f = bm.faces.new((vrows[r][i], vrows[r + 1][i], vrows[r + 1][i + 1], vrows[r][i + 1])); f.smooth = True
            for l in f.loops: l[uvl].uv = CLEAR_UV                    # skin colour (recolourable)
            cs = [closed[v] for v in f.verts]
            if (cs[1] - cs[0]).cross(cs[2] - cs[0]).y > 0:              # visible side faces the front when closed
                f.normal_flip()
    lid_info[s] = dict(pivot=pivot, t=t_close, verts=closed, x0=x0, x1=x1, R_open=R_open, R_close=R_close)
bm.normal_update()
def lash_w(s, x):
    """how much of the lid rotation each eyeliner column follows (1 over the eye, ~0.55 at the tips)"""
    x0, x1 = eye_xr(s)
    return 0.80 + 0.20 * smoothstep(-0.05, 0.0, min(x - x0, x1 - x))   # rigid with the lid over the whole eye

# ---------------------------------------------------------------- raised 3D upper eyeliner (hides the top of the hole, closes with the lid)
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
LASH_COLS = 22
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
    # overhang below the rim: full on the rim, fading out smoothly where the band leaves it towards the tips (a binary
    # cut made a step under the eyeliner, showing a notch of the white socket wall from below); the tips keep their shape
    def _ov(x, z):
        d = poly_dist((x, z), EYES[s])
        t = max(0.0, min(1.0, (0.012 - d) / 0.008))
        return LASH_OVER * t * t * (3 - 2 * t)
    bot = [(x, z - _ov(x, z)) for x, z in bot]
    bot = [(x, min(zb, zt - 0.002)) for (x, zb), (_, zt) in zip(bot, top)]
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
    # outward direction of each outline edge from the outline's winding (the hooked inner end is concave: a
    # "away from the centroid" test flipped some underside faces inwards -> invisible in Roblox, white showed through)
    p2 = [(fr.co.x, fr.co.z) for fr, _ in loop]
    area2 = sum(p2[i][0] * p2[(i + 1) % len(p2)][1] - p2[(i + 1) % len(p2)][0] * p2[i][1] for i in range(len(p2)))
    for i in range(len(loop)):
        (fa, ba), (fb, bb) = loop[i], loop[(i + 1) % len(loop)]
        f = bm.faces.new((fa, ba, bb, fb)); f.smooth = False
        f.normal_update()
        ex_, ez_ = fb.co.x - fa.co.x, fb.co.z - fa.co.z
        out_ = (ez_, -ex_) if area2 > 0 else (-ez_, ex_)            # right-hand normal of a CCW outline points out
        if f.normal.x * out_[0] + f.normal.z * out_[1] < 0: f.normal_flip()
        for l in f.loops: l[uvl].uv = LASH_SIDE_UV
bm.normal_update()

# every n-gon -> clean triangles (the boolean leaves concave n-gons around the eyes; a naive fan would fold)
ng = [f for f in bm.faces if len(f.verts) > 3]                      # quads too: best diagonal, no sliver
bmesh.ops.triangulate(bm, faces=ng, quad_method='BEAUTY', ngon_method='EAR_CLIP')
bm.normal_update()

# no degenerate (sliver / zero-area) triangles: the boolean's concave n-gons left a few on the socket walls, which
# Roblox validation rejects ("Head_Geo has x% degenerate triangles").  Rotate the long edge of each sliver with its
# neighbour of the same kind (wall/wall, skin/skin); positions don't move, UVs are recomputed from the same formulas.
WALL_LO_UV_RECT = WALL_LO_RECT
def _cat(f):
    u, v = f.loops[0][uvl].uv; px, py = u * ATLAS, (1 - v) * ATLAS
    x, y, w, h = WALL_LO_RECT
    if x <= px <= x + w and y <= py <= y + h: return 'wall'
    x, y, w, h = FACE_RECT
    if x <= px <= x + w and y <= py <= y + h: return 'skin'
    x, y, w, h = CLEAR_RECT
    if x <= px <= x + w and y <= py <= y + h: return 'clear'
    return None
def _set_uv(f, cat):
    if cat == 'wall':
        for l in f.loops:
            co = l.vert.co; sy_ = surf_y(co.x, co.z)
            l[uvl].uv = wall_uv(WALL_LO_RECT, co.y - sy_) if sy_ is not None else rect_center_uv(WALL_LO_RECT)
    elif cat == 'skin':
        set_skin_uv(f)
    elif cat == 'clear':
        for l in f.loops: l[uvl].uv = CLEAR_UV
def _minang(f):
    return min(l.calc_angle() for l in f.loops)
def _bad(f):
    return len(f.verts) == 3 and (f.calc_area() < 1e-7 or _minang(f) < math.radians(2.0))
n_fix = 0
for _it in range(6):
    bad_ = [f for f in bm.faces if _bad(f)]
    if not bad_: break
    for f in bad_:
        if not f.is_valid or not _bad(f): continue
        for e in sorted(f.edges, key=lambda e: -e.calc_length()):
            if len(e.link_faces) != 2 or e.seam: continue
            g = e.link_faces[0] if e.link_faces[1] == f else e.link_faces[1]
            cf, cg = _cat(f), _cat(g)
            if cf is None or cf != cg or len(g.verts) != 3: continue
            n0 = (f.normal * f.calc_area() + g.normal * g.calc_area()).normalized()
            q0 = min(_minang(f), _minang(g))
            ne = bmesh.utils.edge_rotate(e, True)
            if ne is None: continue
            nf = list(ne.link_faces)
            for x_ in nf: x_.normal_update()
            if len(nf) == 2 and all(x_.normal.dot(n0) > 0.3 for x_ in nf) and min(_minang(x_) for x_ in nf) > q0:
                for x_ in nf:
                    x_.smooth = True; _set_uv(x_, cf)
                n_fix += 1
                break
            back = bmesh.utils.edge_rotate(ne, False)                  # worse: undo
            if back is not None:
                for x_ in back.link_faces: x_.normal_update(); _set_uv(x_, cf)
            break                                                      # f no longer exists after a rotation
# needles (one ~1 mm edge) can't be fixed by a rotation: collapse their short edge (shell only, never a vertex of
# the eyes, lids, eyeliner or mouth patch); the shell vertex count (SHELL_N) is updated
bm.verts.ensure_lookup_table()
_shell = set(bm.verts[:SHELL_N])
_prot = set()
for s_ in 'LR':
    _prot |= set(lid_info[s_]['verts']) | set(cup_verts[s_]) | set(iris_verts[s_]) | set(lash_verts[s_])
for a_, b_ in BAG_PAIRS: _prot |= {a_, b_}
n_col = 0
for _it in range(6):
    bad_ = [f for f in bm.faces if _bad(f)]
    if not bad_: break
    for f in bad_:
        if not f.is_valid or not _bad(f): continue
        e = min(f.edges, key=lambda e: e.calc_length())
        a_, b_ = e.verts
        if a_ in _prot or b_ in _prot or a_ not in _shell or b_ not in _shell: continue
        if e.calc_length() > 0.006: continue
        aff = {x_: _cat(x_) for x_ in set(a_.link_faces) | set(b_.link_faces)}
        if any(c_ is None for c_ in aff.values()): continue
        bmesh.ops.collapse(bm, edges=[e], uvs=True)
        for x_, c_ in aff.items():
            if x_.is_valid:
                x_.normal_update(); _set_uv(x_, c_)
        n_col += 1
bm.verts.index_update(); bm.verts.ensure_lookup_table()
SHELL_N = sum(1 for v in bm.verts if v in _shell)
print('degenerate triangles fixed', n_fix, 'collapsed', n_col, 'left', sum(1 for f in bm.faces if _bad(f)))

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
BAG_IDX = [(a.index, b.index) for a, b in BAG_PAIRS]
LASH_IDX = {s: set(v.index for v in lash_verts[s]) for s in 'LR'}
REST_ = [v.co.copy() for v in bm.verts]
TIP_DZ = -0.2
LASH_WT = {}
for s in 'LR':
    L = lid_info[s]; xc = (L['x0'] + L['x1']) / 2
    disp = {i: (L['R_close'] @ REST_[i]) - REST_[i] for i in LASH_IDX[s]}
    centre = [disp[i].z for i in LASH_IDX[s] if abs(REST_[i].x - xc) < 0.03]
    dz_des = sum(centre) / len(centre)
    for i, d in disp.items():
        wt = (dz_des - d.z) / (TIP_DZ - d.z)
        LASH_WT[i] = max(0.0, min(0.85, wt))
REST = [v.co.copy() for v in bm.verts]
REST_ = REST
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
    FACE_BONES[nm + 'UpperEyelid'] = tuple(lid_info[s]['pivot'])
    FACE_BONES[nm + 'LashTip'] = front(lid_info[s]['x1'] if s == 'L' else lid_info[s]['x0'], EC[s][1] + 0.04, -0.011)
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
    side = next((s for s in 'LR' if idx in IRIS_IDX[s] or idx in LID_IDX[s] or idx in LASH_IDX[s] or idx in CUP_IDX[s]), None)
    nm = {'L': 'Left', 'R': 'Right'}.get(side or SOCK[idx] if (side or SOCK[idx]) in ('L', 'R') else None, '')
    if side and idx in IRIS_IDX[side]:
        pass                                             # black pupil ball: fixed
    elif side and idx in LID_IDX[side]:
        w[nm + 'UpperEyelid'] = 1.0
    elif side and idx in LASH_IDX[side]:
        wt = LASH_WT[idx]
        w[nm + 'UpperEyelid'] = 1.0 - wt
        if wt > 0.01: w[nm + 'LashTip'] = wt
    elif side and idx in CUP_IDX[side]:
        pass                                             # iris sphere: fixed (an eye does not spin)
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
                xs_w = [q[0] for q in EYES[s]]
                corner = smoothstep(0.0, 0.04, min(x - min(xs_w), max(xs_w) - x))   # same corner fade as the skin
                w[nmw + 'UnderEye'] = smoothstep(0.05, 0.0, depth) * 0.6 * (0.15 + 0.85 * corner)
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
                w[nms + 'UpperEyelid'] = 0.08 * above * inx * frontish     # skin above the eye follows the lid a little
                # lower lid / cheek
                below = smoothstep(zbot - 0.06, zbot - 0.005, z) * smoothstep(zbot + 0.012, zbot, z)
                # ... fading out towards the eye corners, where the top and bottom rims meet (else the corner rim
                # vertex moves while its neighbour just above does not -> a folded sliver)
                corner = smoothstep(0.0, 0.04, min(x - min(xs_), max(xs_) - x))
                w[nms + 'UnderEye'] = 0.9 * below * inx * frontish * (0.15 + 0.85 * corner)
                ck = gauss((x, z), (ex, zbot - 0.07), 0.07) * smoothstep(zbot + 0.005, zbot - 0.03, z) * frontish * 0.7
                w[nms + 'Cheek'] = ck if ck > 0.06 else 0.0
                # brows
                bmask = smoothstep(ztop + 0.02, ztop + 0.08, z) * frontish
                # weight painting along the brow: the whole brow moves as one piece (inner + outer = 1 on it),
                # inner -> outer blended smoothly along its length, soft falloff up into the forehead and down
                inner, outer = BROWS[s]
                ax_, az_ = outer[0] - inner[0], outer[1] - inner[1]
                L2 = ax_ * ax_ + az_ * az_
                t_raw = ((x - inner[0]) * ax_ + (z - inner[1]) * az_) / L2
                t_ = min(1.0, max(0.0, t_raw))
                dz_ = z - (inner[1] + az_ * t_)
                beyond = max(-t_raw, t_raw - 1.0, 0.0) * math.sqrt(L2)
                base = math.exp(-(dz_ / (0.07 if dz_ > 0 else 0.035)) ** 2) * math.exp(-(beyond / 0.05) ** 2) * bmask
                ts = smoothstep(0.15, 0.85, t_)
                w[nms + 'InnerBrow'] = base * (1 - ts)
                w[nms + 'OuterBrow'] = base * ts
    w = {k: v for k, v in w.items() if v > 0.01}
    if len(w) > 3:
        w = dict(sorted(w.items(), key=lambda kv: -kv[1])[:3])
    tot = sum(w.values())
    if tot > 1:
        w = {k: v / tot for k, v in w.items()}; tot = 1.0
    if tot < 0.999:
        w['DynamicHead'] = 1 - tot
    weights.append(w)
for ia, ib in BAG_IDX:
    weights[ib] = dict(weights[ia])                       # mouth bag back = same skinning as its rim vertex
# the shallow first band of the eye socket wall (rim -> CAVE_D0) follows the rim skin exactly (no shearing)
from mathutils.kdtree import KDTree
_rim = [i for i in range(SHELL_N) if SOCK[i] is None]
_kd = KDTree(len(_rim))
for k, i in enumerate(_rim): _kd.insert(Vector((REST[i].x, 0.0, REST[i].z)), k)
_kd.balance()
n_band = 0
for i in range(SHELL_N):
    if SOCK[i] in ('L', 'R'):
        sy_ = surf_y(REST[i].x, REST[i].z)
        if sy_ is not None and REST[i].y - sy_ < CAVE_D0 + 0.002:
            co_, k, d_ = _kd.find(Vector((REST[i].x, 0.0, REST[i].z)))
            if d_ < 0.004:
                weights[i] = dict(weights[_rim[k]]); n_band += 1
print('socket rim band vertices skinned like the rim:', n_band)

# ---------------------------------------------------------------- FACS poses (in mask studs; rigid transforms)
def T(*d): return ('t', Vector(d))
def ROT(piv, axis, ang): return ('r', Vector(piv), axis, ang)
def eye_look(axis, dist):
    """the eye itself never moves nor turns (iris sphere and pupil are fixed: the hollow-eye illusion does the looking);
    the gaze poses only move the eyelids"""
    return {}
def mirror(d):
    out = {}
    for k, v in d.items():
        k2 = k.replace('Left', '§').replace('Right', 'Left').replace('§', 'Right')
        if v[0] == 't' and len(v) > 2 and v[2] == 'lid':
            out[k2] = lid_rot('R' if k2.startswith('Right') else 'L', v[3])
        elif v[0] == 't':
            out[k2] = T(-v[1].x, v[1].y, v[1].z)
        else:
            sd = 'R' if k2.startswith('Right') else 'L'
            out[k2] = v
    return out
P = {}
P['EyesLookDown'] = eye_look('X', -LOOK_Z)
P['EyesLookUp'] = eye_look('X', LOOK_Z)
def lid_rot(s_, frac=1.0):
    """the lid slide (a pure translation): frac 1 = closed"""
    return ('t', Vector(lid_info[s_]['t']) * frac, 'lid', frac)
LID_FOLLOW = 0.12                                   # the upper lid follows the gaze down a little
def tip(frac): return T(0, 0, TIP_DZ * frac)
P['EyesLookDown']['LeftUpperEyelid'] = lid_rot('L', LID_FOLLOW); P['EyesLookDown']['LeftLashTip'] = tip(LID_FOLLOW)
P['EyesLookDown']['RightUpperEyelid'] = lid_rot('R', LID_FOLLOW); P['EyesLookDown']['RightLashTip'] = tip(LID_FOLLOW)
LID_UP = -0.05                                      # ... and lifts a little when looking up
for s_, nm_ in (('L', 'Left'), ('R', 'Right')):
    P['EyesLookUp'][nm_ + 'UpperEyelid'] = lid_rot(s_, LID_UP); P['EyesLookUp'][nm_ + 'LashTip'] = tip(LID_UP)
for s_, nm_ in (('L', 'Left'), ('R', 'Right')):
    o_ = 'Right' if nm_ == 'Left' else 'Left'; os_ = 'R' if s_ == 'L' else 'L'
    P[nm_ + 'EyeClosed_EyesLookUp'] = {nm_ + 'UpperEyelid': lid_rot(s_), o_ + 'UpperEyelid': lid_rot(os_, LID_UP),
                                       nm_ + 'LashTip': tip(1.0), o_ + 'LashTip': tip(LID_UP),
                                       **eye_look('X', LOOK_Z)}
    P[nm_ + 'EyeClosed'] = {nm_ + 'UpperEyelid': lid_rot(s_), nm_ + 'LashTip': tip(1.0)}
    P[nm_ + 'CheekRaiser'] = {nm_ + 'Cheek': T(0, -0.004, 0.012), nm_ + 'UnderEye': T(0, -0.004, 0.012)}
    # corrective (same naming as Roblox's own Blocky head): closed + looking down must stay exactly closed
    P[nm_ + 'EyeClosed_EyesLookDown'] = {nm_ + 'UpperEyelid': lid_rot(s_), o_ + 'UpperEyelid': lid_rot(os_, LID_FOLLOW),
                                         nm_ + 'LashTip': tip(1.0), o_ + 'LashTip': tip(LID_FOLLOW),
                                         **eye_look('X', -LOOK_Z)}
P['LeftEyeUpperLidRaiser'] = {'LeftUpperEyelid': lid_rot('L', -0.07), 'LeftLashTip': tip(-0.07), 'LeftOuterBrow': T(0, 0, 0.006), 'LeftInnerBrow': T(0, 0, 0.004)}
P['LeftLipCornerPuller'] = {'LeftLipCorner': T(0.014, 0.006, 0.020), 'LeftCheek': T(0, -0.002, 0.005), 'LeftUnderEye': T(0, -0.001, 0.003)}
P['LeftLipCornerDown'] = {'LeftLipCorner': T(0.004, 0.0, -0.024)}
P['LeftLipStretcher'] = {'LeftLipCorner': T(0.024, 0.002, -0.006)}
P['LeftLowerLipDepressor'] = {'LeftLowerLip': T(0.004, 0, -0.024)}
P['LeftUpperLipRaiser'] = {'LeftUpperLip': T(0, -0.003, 0.018)}
P['LeftBrowLowerer'] = {'LeftInnerBrow': T(-0.008, 0, -0.024), 'LeftOuterBrow': T(0, 0, -0.008)}
P['LeftInnerBrowRaiser'] = {'LeftInnerBrow': T(0, 0, 0.028)}
P['LeftOuterBrowRaiser'] = {'LeftOuterBrow': T(0, 0, 0.028)}
for k in list(P):
    if k.startswith('Left') and 'Right' + k[4:] not in P and '_' not in k:
        P['Right' + k[4:]] = mirror(P[k])
P['JawDrop'] = {'Jaw': T(0, 0.014, -0.120)}
P['ChinRaiser'] = {'Jaw': T(0, -0.020, 0.005), 'LeftLowerLip': T(0, -0.014, 0.003), 'RightLowerLip': T(0, -0.014, 0.003),
                   'LeftUpperLip': T(0, -0.010, 0.004), 'RightUpperLip': T(0, -0.010, 0.004)}   # chin pushed up/forward (pout)
# chin raiser pushing the upper lip up too (mouth shrug): clearly visible, Studio flags tiny poses as "identical to Neutral"
P['ChinRaiserUpperLip'] = {'LeftUpperLip': T(0, -0.010, 0.016), 'RightUpperLip': T(0, -0.010, 0.016),
                           'LeftLowerLip': T(0, -0.010, 0.012), 'RightLowerLip': T(0, -0.010, 0.012),
                           'LeftLipCorner': T(0, -0.004, 0.0), 'RightLipCorner': T(0, -0.004, 0.0),
                           'Jaw': T(0, -0.012, 0.012)}
# extra Roblox base poses (no tongue, the eyes never move): more expressions available in Studio / with face tracking
P['JawLeft'] = {'Jaw': T(0.022, 0, 0)}
P['JawRight'] = {'Jaw': T(-0.022, 0, 0)}
_lips = ('LeftUpperLip', 'RightUpperLip', 'LeftLowerLip', 'RightLowerLip', 'LeftLipCorner', 'RightLipCorner')
P['MouthLeft'] = {b: T(0.020, 0, 0.002 if 'Corner' in b and b.startswith('Left') else 0) for b in _lips}
P['MouthRight'] = {b: T(-0.020, 0, 0.002 if 'Corner' in b and b.startswith('Right') else 0) for b in _lips}
P['Funneler'] = {'LeftUpperLip': T(-0.004, -0.012, 0.008), 'RightUpperLip': T(0.004, -0.012, 0.008),
                 'LeftLowerLip': T(-0.004, -0.012, -0.008), 'RightLowerLip': T(0.004, -0.012, -0.008),
                 'LeftLipCorner': T(-0.014, -0.008, 0), 'RightLipCorner': T(0.014, -0.008, 0)}
P['LipPresser'] = {'LeftUpperLip': T(0, 0.005, -0.002), 'RightUpperLip': T(0, 0.005, -0.002),
                   'LeftLowerLip': T(0, 0.005, 0.004), 'RightLowerLip': T(0, 0.005, 0.004),
                   'LeftLipCorner': T(0, 0.003, 0), 'RightLipCorner': T(0, 0.003, 0)}
P['LowerLipSuck'] = {'LeftLowerLip': T(0, 0.008, 0.006), 'RightLowerLip': T(0, 0.008, 0.006)}
P['UpperLipSuck'] = {'LeftUpperLip': T(0, 0.016, -0.004), 'RightUpperLip': T(0, 0.016, -0.004),
                     'LeftLipCorner': T(-0.003, 0.006, -0.002), 'RightLipCorner': T(0.003, 0.006, -0.002),
                     'LeftLowerLip': T(0, 0.004, 0.002), 'RightLowerLip': T(0, 0.004, 0.002)}
for s_, sg in (('Left', 1), ('Right', -1)):
    o_ = 'Right' if s_ == 'Left' else 'Left'
    P[s_ + 'CheekPuff'] = {s_ + 'Cheek': T(0.004 * sg, -0.016, -0.002), s_ + 'UnderEye': T(0, -0.004, 0),
                           s_ + 'LipCorner': T(0.004 * sg, -0.004, 0)}
    P[s_ + 'Dimpler'] = {s_ + 'LipCorner': T(0.010 * sg, 0.006, 0.002)}
    P[s_ + 'NoseWrinkler'] = {s_ + 'UpperLip': T(0, -0.002, 0.012), s_ + 'Cheek': T(0, -0.002, 0.008),
                              s_ + 'UnderEye': T(0, -0.002, 0.006), s_ + 'InnerBrow': T(-0.004 * sg, 0, -0.010)}
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
# the cage MOUTH landmarks (the hole of the cage mouth and its second loop) must lie on THIS mouth, which is much
# narrower than the Blocky one: Roblox validation projects them on the head and checks that they move for "mouth
# open" (JawDrop) and the sad expression.  Scale the cage mouth area onto the mouth (same centre, mouth width, a lip
# height), fading out smoothly around it (no fold).
_bnd = [e for e in cbm.edges if e.is_boundary]
_adj = {}
for e in _bnd:
    a_, b_ = e.verts; _adj.setdefault(a_, []).append(b_); _adj.setdefault(b_, []).append(a_)
_seen = set(); _loops = []
for v0 in _adj:
    if v0 in _seen: continue
    st = [v0]; comp = []
    while st:
        x_ = st.pop()
        if x_ in _seen: continue
        _seen.add(x_); comp.append(x_); st += _adj[x_]
    _loops.append(comp)
_front = [L for L in _loops if sum(v.co.y for v in L) / len(L) < hc.y - 0.25]
_mloop = min(_front, key=lambda L: sum(v.co.z for v in L) / len(L))      # lowest front hole = the mouth
_mx = [v.co.x for v in _mloop]; _mz = [v.co.z for v in _mloop]
mc_c = Vector(((min(_mx) + max(_mx)) / 2, (min(_mz) + max(_mz)) / 2)); hw_c = (max(_mx) - min(_mx)) / 2
_qc = np.polyfit([v.co.x for v in _mloop], [v.co.z for v in _mloop], 2)          # Blocky's (smile) slit
_tx = [MX0 + (MX1 - MX0) * k / 20 for k in range(21)]
_tw = [MP((x_, 0, mouth_z(x_))) for x_ in _tx]
_qt = np.polyfit([p_.x for p_ in _tw], [p_.z for p_ in _tw], 2)                  # this mouth's line (world)
mc_t_x = (_tw[0].x + _tw[-1].x) / 2; hw_t = (_tw[-1].x - _tw[0].x) / 2 + 0.006
# lip landmark colours of Roblox's cage template: green = upper lip, purple = lower lip
_ccol = cage.data.color_attributes[0]
_vcol = {}
for li_, dd_ in enumerate(_ccol.data):
    _vcol.setdefault(cage.data.loops[li_].vertex_index, set()).add(tuple(round(x_, 2) for x_ in dd_.color[:3]))
cbm.verts.ensure_lookup_table()
LIP_UP, LIP_LO = 0.018, 0.018
targets = {}
for v in cbm.verts:
    cs = _vcol.get(v.index, set())
    up = (0.05, 0.35, 0.05) in cs; lo = (0.1, 0.02, 0.1) in cs
    on_hole = v in set(_mloop)
    if not (up or lo or on_hole) or v.co.y > hc.y - 0.25: continue
    u = max(-1.15, min(1.15, (v.co.x - mc_c.x) / hw_c))
    x2 = mc_t_x + u * hw_t; z0 = float(np.polyval(_qt, x2))
    above = v.co.z >= float(np.polyval(_qc, v.co.x))
    if on_hole and not (up or lo):
        z2 = z0 + (0.003 if above else -0.003)
    else:
        taper = max(0.35, 1.0 - 0.55 * u * u)                    # lips thinner towards the corners
        if on_hole: z2 = z0 + (0.004 if up else -0.004)
        else: z2 = z0 + (LIP_UP if up else -LIP_LO) * taper
    targets[v] = Vector((x2, z2))
_disp = [(Vector((v.co.x, v.co.z)), t_ - Vector((v.co.x, v.co.z))) for v, t_ in targets.items()]
for v in cbm.verts:
    if v.co.y > hc.y - 0.25: continue
    q = Vector((v.co.x, v.co.z))
    if v in targets:
        v.co.x, v.co.z = targets[v].x, targets[v].y; continue
    dmin = min((q - p_).length for p_, _ in _disp)
    fall = max(0.0, min(1.0, (0.09 - dmin) / 0.07)); fall = fall * fall * (3 - 2 * fall)
    if fall <= 0: continue
    ws = [1.0 / ((q - p_).length ** 2 + 1e-4) for p_, _ in _disp]
    dsp = sum((d_ * w_ for (_, d_), w_ in zip(_disp, ws)), Vector((0, 0))) / sum(ws)
    v.co.x += dsp.x * fall; v.co.z += dsp.y * fall
print('cage mouth landmarks: %d placed on the mouth (upper lip +%.3f, lower lip -%.3f, half-width %.3f)' % (len(targets), LIP_UP, LIP_LO, hw_t))
hbm = bmesh.new(); hbm.from_mesh(head.data); hbm.transform(AW)
HB = BVHTree.FromBMesh(hbm)
for v in cbm.verts:                                            # wrap: 1.2 cm outside this head along the ray from the centre
    d = (v.co - hc).normalized()
    # (same wrap as v1.3, which passed the eye-closing validation: around the real head mesh)
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
lid_or_inner = set().union(*[IRIS_IDX[s_] | LID_IDX[s_] | LASH_IDX[s_] | CUP_IDX[s_] for s_ in 'LR'])
newn = []
nset = 0
for poly in me.polygons:
    for li in poly.loop_indices:
        vi = me.loops[li].vertex_index
        lid_side = next((s_ for s_ in 'LR' if vi in LID_IDX[s_]), None)
        if lid_side:
            Lf = lid_info[lid_side]
            pr = Minv @ me.vertices[vi].co                         # rest position (mask studs)
            # the lid only slides (no rotation): its normal is the skin normal where it lies when closed
            pc = Lf['R_close'] @ pr
            loc, _, fi, _ = TB.find_nearest(pc)
            f = tri_base.faces[fi]
            a, b, c = [x.co for x in f.verts]
            na, nb, nc = [x.normal for x in f.verts]
            w = barycentric_transform(loc, a, b, c, Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
            n_rest = (na * w.x + nb * w.y + nc * w.z).normalized()
            newn.append((R3 @ n_rest).normalized()); nset += 1
        elif EYE_STYLE == 'flat' and ((vi < SHELL_N and SOCK[vi] in ('L', 'R') and not skin_loop(li))
                                      or any(vi in CUP_IDX[s_] for s_ in 'LR')):
            # inside of the hole (walls, back wall, drawn eye): normals facing the front -> one even tone, no facets,
            # even with a plain TextureID (no emissive)
            newn.append((R3 @ Vector((0, -1, 0))).normalized()); nset += 1
        elif vi < SHELL_N and vi not in lid_or_inner and skin_loop(li) and SOCK[vi] is None:
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
