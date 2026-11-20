"""Automatic mesh / animation QA of build/head_rig.blend (what Roblox will play).

Every FACS pose is evaluated at 25 / 50 / 75 / 100 % (translations scaled, rotations slerped, like FaceControls),
plus the Roblox validation combos (with our corrective frames applied the way Studio does).

Checks
  * poke-through : an eye part (iris, eyelid) comes out in FRONT of the skin
  * flipped      : a triangle turns > 100 deg from its rest orientation (folding / crossing), rigid lid excluded
  * stretch      : an edge stretches > 3x or squashes < 0.25x (mouth bag excluded: it has to open)
  * rest-hidden  : at rest, the parked eyelid must not be visible from any of 7 view directions
  * closed-cover : LeftEyeClosed / RightEyeClosed at 100 % must cover the whole eye opening from 5 view directions
run: python tools/check_mesh.py <project dir>
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector, Quaternion
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(sys.argv[-1])
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from layout import *
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, 'build', 'head_rig.blend'))
head = bpy.data.objects['Head_Geo']; arm = bpy.data.objects['Armature']
act = arm.animation_data.action
frames = {v: int(k[5:]) for k, v in head.items() if k.startswith('Frame')}
FM = json.load(open(os.path.join(ROOT, 'build', 'facs_map.json')))
HC = Vector(FM['head_centre']); SC = FM['head_scale']
def to_mask(p): return (p - HC) / SC

def curves():
    try:
        return list(act.fcurves)
    except Exception:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out += list(cb.fcurves)
        return out
CURVES = curves()
POSE = {}
for name, fr in frames.items():
    val = {}
    for fc in CURVES:
        bn = fc.data_path.split('"')[1]; prop = fc.data_path.split('.')[-1]
        val.setdefault(bn, {}).setdefault(prop, {})[fc.array_index] = fc.evaluate(fr)
    POSE[name] = {bn: (Vector([d.get('location', {}).get(i, 0) for i in range(3)]),
                       Quaternion([d.get('rotation_quaternion', {}).get(i, 1 if i == 0 else 0) for i in range(4)]))
                  for bn, d in val.items()}
CORRECTIVES = {tuple(sorted(n.split('_'))): n for n in frames if '_' in n}

def apply(weights):
    """weights: {pose name: 0..1}.  Base poses add up; a corrective replaces the sum of its parts (Studio behaviour)."""
    arm.animation_data.action = None
    active = {n: w for n, w in weights.items() if w > 0}
    use = dict(active)
    for parts, cname in CORRECTIVES.items():
        if all(p in active and active[p] >= 0.999 for p in parts):
            for p in parts: use.pop(p, None)
            use[cname] = 1.0
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'; pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
    for n, w in use.items():
        for bn, (loc, q) in POSE[n].items():
            pb = arm.pose.bones[bn]
            pb.location = pb.location + loc * w
            pb.rotation_quaternion = Quaternion((1, 0, 0, 0)).slerp(q, w) @ pb.rotation_quaternion
    bpy.context.view_layer.update()

def deformed():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = head.evaluated_get(dg)
    m = ev.to_mesh()
    co = [head.matrix_world @ v.co for v in m.vertices]
    ev.to_mesh_clear()
    return co

me = head.data
groups = {g.index: g.name for g in head.vertex_groups}
uvl = me.uv_layers[0].data
def in_rect(px, py, r, m=2): return r[0] - m <= px <= r[0] + r[2] + m and r[1] - m <= py <= r[1] + r[3] + m
def category(p):
    u, v = uvl[p.loop_indices[0]].uv; px, py = u * ATLAS, (1 - v) * ATLAS
    if in_rect(px, py, LASH_RECT) or in_rect(px, py, LASH_SIDE_RECT): return 'lash'
    if in_rect(px, py, MOUTH_RECT): return 'mouth'
    if in_rect(px, py, WALL_UP_RECT) or in_rect(px, py, WALL_LO_RECT): return 'wall'
    for s in 'LR':
        if in_rect(px, py, cup_rect(s)): return 'dish'
        if in_rect(px, py, iris_rect(s)): return 'iris'
    if in_rect(px, py, CLEAR_RECT) and all(any(groups[g.group].endswith('UpperEyelid') and g.weight > 0.99 for g in me.vertices[i].groups) for i in p.vertices):
        return 'lid'
    return 'skin'
CAT = [category(p) for p in me.polygons]
lid_v = {i for p, c in zip(me.polygons, CAT) if c == 'lid' for i in p.vertices}
iris_v = {i for p, c in zip(me.polygons, CAT) if c == 'iris' for i in p.vertices}
mouth_v = {i for p, c in zip(me.polygons, CAT) if c == 'mouth' for i in p.vertices}
inner = lid_v | iris_v
POLYS = [tuple(p.vertices) for p in me.polygons]
tris = []
for p, c in zip(me.polygons, CAT):
    vs = list(p.vertices)
    for i in range(1, len(vs) - 1):
        tris.append(((vs[0], vs[i], vs[i + 1]), c))
edges = [tuple(e.vertices) for e in me.edges]
def normal(co, t):
    a, b, c = co[t[0]], co[t[1]], co[t[2]]
    n = (b - a).cross(c - a)
    return n.normalized() if n.length > 2e-7 else None

apply({})
rest = deformed()
rest_n = [normal(rest, t) for t, c in tris]
bm2 = bmesh.new(); vmap = {}
for p, c in zip(POLYS, CAT):
    if c != 'skin': continue
    vs = []
    for i in p:
        if i not in vmap: vmap[i] = bm2.verts.new(rest[i])
        vs.append(vmap[i])
    try: bm2.faces.new(vs)
    except ValueError: pass
bm2.normal_update()
SKIN = BVHTree.FromBMesh(bm2)
def in_front_of_skin(p):
    loc, nrm, idx, dist = SKIN.ray_cast(Vector((p.x, p.y - 3.0, p.z)), Vector((0, 1, 0)))
    if loc is None or nrm.y > 0:
        return False
    return 0.004 < loc.y - p.y < 0.15             # closed lids lie flush with the skin (<= 0.004 stud) by design

# ---------------------------------------------------------------- view rays towards the eyes
EYES = {s: eye_poly_studs(s) for s in 'LR'}
def pip(pt, poly):
    x, y = pt; inside = False
    for i in range(len(poly)):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % len(poly)]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return inside
DIRS = {'front': (0, 0), 'below35': (0, -35), 'above25': (0, 25), 'left35': (35, 0), 'right35': (-35, 0),
        'below20left25': (25, -20), 'below20right25': (-25, -20)}
def dir_vec(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    return Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))     # from the head towards the camera
def eye_targets(s, inset=0.004, step=0.01):
    xs = [p[0] for p in EYES[s]]; zs = [p[1] for p in EYES[s]]
    out = []
    x = min(xs)
    while x <= max(xs):
        z = min(zs)
        while z <= max(zs):
            if pip((x, z), EYES[s]):
                # keep only points at least `inset` inside the outline
                ok = all(pip((x + dx, z + dz), EYES[s]) for dx, dz in ((inset, 0), (-inset, 0), (0, inset), (0, -inset)))
                if ok: out.append((x, z))
            z += step
        x += step
    return out
TARGETS = {s: eye_targets(s) for s in 'LR'}
def first_hits(co, s, dirs):
    bvh = BVHTree.FromPolygons(co, POLYS)
    res = {}
    for dn in dirs:
        d = dir_vec(*DIRS[dn])
        cnt = {}
        for (x, z) in TARGETS[s]:
            # target point on the face plane of the opening (mask studs -> world), ray from the camera side
            ys = []
            ztop_, zbot_ = max(q[1] for q in EYES[s]), min(q[1] for q in EYES[s])
            for zz in (ztop_ + 0.03, zbot_ - 0.03, ztop_ + 0.05, zbot_ - 0.05, ztop_ + 0.08, zbot_ - 0.08):
                loc, nrm, idx, dist = SKIN.ray_cast(Vector((HC.x + x * SC, HC.y - 3, HC.z + zz * SC)), Vector((0, 1, 0)))
                if loc is not None and nrm.y < 0: ys.append(loc.y)
                if len(ys) >= 2: break
            if not ys: continue                          # cannot place the target reliably: skip it
            yw = sum(ys) / len(ys)
            tgt = Vector((HC.x + x * SC, yw, HC.z + z * SC))
            org = tgt + d * 2.0
            loc, nrm, idx, dist = bvh.ray_cast(org, -d)
            c = CAT[idx] if idx is not None else 'none'
            cnt[c] = cnt.get(c, 0) + 1
        res[dn] = cnt
    return res

report = {}
problems = []
# double surface: two skin layers on top of each other anywhere on the front of the face (overlapping faces)
bvh_all = BVHTree.FromPolygons(rest, POLYS)
double = []
for gx in range(-50, 51):
    for gz in range(-50, 31):
        x, z = gx * 0.011, gz * 0.011
        org = HC + Vector((x, -3, z)) * SC
        loc, nrm, idx, dist = bvh_all.ray_cast(org, Vector((0, 1, 0)))
        if idx is None or CAT[idx] != 'skin' or nrm.y > 0: continue
        loc2, nrm2, idx2, d2 = bvh_all.ray_cast(loc + Vector((0, 1e-5, 0)), Vector((0, 1, 0)), 0.004 * SC)
        if idx2 is not None and CAT[idx2] == 'skin' and nrm2.y < 0:
            double.append((round(x, 3), round(z, 3)))
print(('ok ' if not double else '!! ') + f'double skin layers: {len(double)} {double[:6]}')
# holes: a ray from the front must first meet a front-facing surface (outside the eye / mouth openings)
holes = []
for gx in range(-50, 51):
    for gz in range(-52, 50):
        x, z = gx * 0.011, gz * 0.011
        if any(pip((x, z), EYES[s_]) for s_ in 'LR'): continue
        org = HC + Vector((x, -3, z)) * SC
        loc, nrm, idx, dist = bvh_all.ray_cast(org, Vector((0, 1, 0)))
        if idx is None: continue                          # outside the head silhouette
        if nrm.y > 0.05 and CAT[idx] not in ('mouth',):
            holes.append((round(x, 3), round(z, 3), CAT[idx]))
print(('ok ' if not holes else '!! ') + f'holes in the skin: {len(holes)} {holes[:8]}')
# texture islands: eye textures (dish / iris / socket wall) only inside the eye area, mouth texture only in the mouth
wrong_uv = []
for p, c in zip(me.polygons, CAT):
    q = to_mask(head.matrix_world @ p.center)
    if c in ('dish', 'iris', 'wall'):
        ok = q.y < -0.3 and any(min(x for x, _ in EYES[s_]) - 0.08 < q.x < max(x for x, _ in EYES[s_]) + 0.08 and
                 min(z for _, z in EYES[s_]) - 0.08 < q.z < max(z for _, z in EYES[s_]) + 0.16 for s_ in 'LR')
        if not ok: wrong_uv.append((c, round(q.x, 3), round(q.z, 3)))
    if c == 'mouth' and q.y > -0.3: wrong_uv.append((c, round(q.x, 3), round(q.y, 3), round(q.z, 3)))
print(('ok ' if not wrong_uv else '!! ') + f'faces with a texture from the wrong place: {len(wrong_uv)} {wrong_uv[:6]}')
# the back half of the head must not follow any eye / eyelid / mouth joint
back_w = []
for v in me.vertices:
    q = to_mask(head.matrix_world @ v.co)
    if q.y > 0.0:
        bad = [groups[g.group] for g in v.groups if g.weight > 0.001 and any(k in groups[g.group] for k in ('Eye', 'Lid', 'Lash', 'Jaw', 'Lip', 'Cheek', 'Brow'))]
        if bad: back_w.append((round(q.x, 3), round(q.y, 3), round(q.z, 3), bad))
print(('ok ' if not back_w else '!! ') + f'back of the head driven by face joints: {len(back_w)} {back_w[:4]}')
if back_w: problems.append('back weights')
if wrong_uv: problems.append('wrong uv')
if holes: problems.append('holes')
if double: problems.append('double skin')
# rest: parked lid never visible
apply({})
co = deformed()
vis = {}
for s in 'LR':
    for dn, cnt in first_hits(co, s, DIRS).items():
        if cnt.get('lid'):
            vis[f'{s}:{dn}'] = cnt['lid']
rest_poke = [i for i in lid_v if in_front_of_skin(co[i])]
print(('ok ' if not vis and not rest_poke else '!! ') + f'rest: parked lid visible from {vis or "nowhere"}, lid in front of skin: {len(rest_poke)}')
if vis or rest_poke: problems.append('rest')

# closed eyes cover the whole opening
for nm, s in (('LeftEyeClosed', 'L'), ('RightEyeClosed', 'R')):
    apply({nm: 1.0})
    co = deformed()
    bad = {}
    for dn, cnt in first_hits(co, s, ['front', 'below35', 'above25', 'left35', 'right35']).items():
        leak = {k: v for k, v in cnt.items() if k not in ('lid', 'lash', 'skin')}
        if leak: bad[dn] = leak
    print(('ok ' if not bad else '!! ') + f'{nm}: opening covered' + ('' if not bad else f' -> leaks {bad}'))
    if bad: problems.append(nm + ' cover')

cases = []
for n in frames:
    if n == 'Neutral' or '_' in n: continue
    for f in (0.25, 0.5, 0.75, 1.0):
        cases.append({n: f})
for combo in (['LeftEyeClosed', 'EyesLookDown'], ['RightEyeClosed', 'EyesLookDown'], ['JawDrop'],
              ['Pucker', 'LeftLipCornerPuller', 'RightLipCornerPuller'],
              ['ChinRaiser', 'ChinRaiserUpperLip', 'LeftCheekRaiser', 'RightCheekRaiser', 'LeftInnerBrowRaiser',
               'RightInnerBrowRaiser', 'LeftLipCornerDown', 'RightLipCornerDown', 'LeftLowerLipDepressor', 'RightLowerLipDepressor'],
              ['LeftEyeClosed', 'EyesLookUp'], ['LeftEyeClosed', 'EyesLookLeft'], ['RightEyeClosed', 'EyesLookRight'],
              ['LeftEyeClosed', 'RightEyeClosed', 'LeftCheekRaiser', 'RightCheekRaiser'],
              ['JawDrop', 'LeftLipCornerPuller', 'RightLipCornerPuller'], ['JawDrop', 'Pucker'], ['JawDrop', 'LipsTogether']):
    for f in (0.5, 1.0):
        cases.append({n: f for n in combo})
# see-through: from usual camera angles, the first surface hit in front of the face must never be a back face
SEE_DIRS = ['front', 'left35', 'right35', 'below35', 'above25']
SEE_PTS = [(gx * 0.025, gz * 0.025) for gx in range(-20, 21) for gz in range(-21, 5)]
def see_through(co):
    bvh = BVHTree.FromPolygons(co, POLYS); bad = []
    for dn in SEE_DIRS:
        d = dir_vec(*DIRS[dn])
        for (x, z) in SEE_PTS:
            loc, nrm, idx, dist = SKIN.ray_cast(Vector((HC.x + x * SC, HC.y - 3, HC.z + z * SC)), Vector((0, 1, 0)))
            if loc is None or nrm.y > 0: continue
            org = loc + d * 2.0
            h, n2, i2, _ = bvh.ray_cast(org, -d)
            if i2 is not None and n2.dot(d) < -0.08 and CAT[i2] != 'lash':          # clearly turned away (not a grazing hit)
                bad.append((dn, round(x, 3), round(z, 3), CAT[i2]))
    return bad
see_bad_total = 0
for w in cases:
    apply(w)
    co = deformed()
    if all(v in (0.5, 1.0) for v in w.values()):
        sb = see_through(co)
        if sb:
            see_bad_total += len(sb)
            print(f'!! {"+".join(w)[:60]} seen from behind: {len(sb)} {sb[:4]}')
            problems.append('see-through')
    poke = [i for i in inner if (co[i] - rest[i]).length > 1e-5 and in_front_of_skin(co[i])]
    flips = 0; where = {}
    for (t, c), n0 in zip(tris, rest_n):
        if c == 'lid': continue                           # the eyelid is rigid: it rotates as a whole by design
        n1 = normal(co, t)
        if n0 is not None and n1 is not None and n0.dot(n1) < math.cos(math.radians(100)):
            flips += 1; where[c] = where.get(c, 0) + 1
        elif c == 'skin' and n0 is not None and n1 is not None and n0.dot(n1) < math.cos(math.radians(35)):
            flips += 1; where['skin crease'] = where.get('skin crease', 0) + 1     # a skin triangle folding
    stretch = 0
    for a, b in edges:
        l0 = (rest[a] - rest[b]).length; l1 = (co[a] - co[b]).length
        if l0 > 1e-4 and (l1 / l0 > 3.0 or l1 / l0 < 0.25) and not (a in mouth_v and b in mouth_v):
            stretch += 1
    moved = sum(1 for i in range(len(co)) if (co[i] - rest[i]).length > 1e-4)
    key = '+'.join(f'{n}@{int(f * 100)}' for n, f in w.items())
    report[key] = dict(moved=moved, poke=len(poke), flipped=flips, stretched=stretch)
    if poke or flips or stretch or moved == 0:
        problems.append(key)
        print(f'!! {key[:70]:70s} moved={moved:5d} poke={len(poke):3d} flipped={flips:3d} stretched={stretch:3d} {where if flips else ""}')
json.dump(report, open(os.path.join(ROOT, 'build', 'mesh_check.json'), 'w'), indent=1)
print('cases tested:', len(cases) + 3, '| max bone influences per vertex:', max(sum(1 for g in v.groups if g.weight > 0.0) for v in me.vertices))
print('PROBLEMS:', len(problems))
