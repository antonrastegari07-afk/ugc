"""Automatic mesh QA of every FACS frame (and the Roblox validation combos) of build/head_rig.blend.

For each pose the deformed head is compared with the rest head:
  * poke-through  : a vertex of the inner eye parts / eyelids lands in FRONT of the skin outside the eye opening
  * flipped faces : triangles whose normal turns more than 100 deg from rest (mesh folding / crossing)
  * stretch       : edges stretched > 3x or squashed < 0.25x
run: python tools/check_mesh.py <project dir>
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(sys.argv[-1])
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, 'build', 'head_rig.blend'))
head = bpy.data.objects['Head_Geo']; arm = bpy.data.objects['Armature']
act = arm.animation_data.action
frames = {v: int(k[5:]) for k, v in head.items() if k.startswith('Frame')}
scn = bpy.context.scene

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

def apply(names):
    from mathutils import Quaternion
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'; pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
    for n in names:
        fr = frames[n]; val = {}
        for fc in CURVES:
            bn = fc.data_path.split('"')[1]; prop = fc.data_path.split('.')[-1]
            val.setdefault((bn, prop), {})[fc.array_index] = fc.evaluate(fr)
        for (bn, prop), c in val.items():
            pb = arm.pose.bones[bn]
            if prop == 'location':
                pb.location = pb.location + Vector([c.get(i, 0) for i in range(3)])
            elif prop == 'rotation_quaternion':
                pb.rotation_quaternion = Quaternion([c.get(i, 1 if i == 0 else 0) for i in range(4)]) @ pb.rotation_quaternion
    bpy.context.view_layer.update()

def deformed():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = head.evaluated_get(dg)
    me = ev.to_mesh()
    co = [head.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return co

apply([])
rest = deformed()
me = head.data
tris = []
for p in me.polygons:
    vs = list(p.vertices)
    for i in range(1, len(vs) - 1):
        tris.append((vs[0], vs[i], vs[i + 1]))
edges = [tuple(e.vertices) for e in me.edges]
def normal(co, t):
    a, b, c = co[t[0]], co[t[1]], co[t[2]]
    n = (b - a).cross(c - a)
    return n.normalized() if n.length > 2e-7 else None      # zero-area slivers are invisible: ignored
rest_n = [normal(rest, t) for t in tris]

# skin surface (rest) for poke-through tests: shell = vertices weighted to DynamicHead only or skin bones
groups = {g.index: g.name for g in head.vertex_groups}
inner = set()
for v in me.vertices:
    names = {groups[g.group] for g in v.groups if g.weight > 0.01}
    if names & {'LeftEye', 'RightEye', 'LeftUpperEyelid', 'RightUpperEyelid', 'LeftLowerEyelid', 'RightLowerEyelid'}:
        inner.add(v.index)
mouth_bag = set()   # filled below
rigid = {v.index for v in me.vertices if {groups[g.group] for g in v.groups if g.weight > 0.99} & {'LeftUpperEyelid', 'RightUpperEyelid', 'LeftLowerEyelid', 'RightLowerEyelid'}}
# the rest OUTER skin only (face shell textured with the face block or the plain skin), never the eye interior,
# the eyeliner, the eyelids or the mouth bag
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from layout import FACE_RECT, CLEAR_RECT, ATLAS
uvl = me.uv_layers[0].data
def is_outer(p):
    if any(v in inner for v in p.vertices): return False
    for li in p.loop_indices:
        u, v = uvl[li].uv
        px, py = u * ATLAS, (1 - v) * ATLAS
        in_face = FACE_RECT[1] <= py <= FACE_RECT[1] + FACE_RECT[3]
        in_clear = CLEAR_RECT[0] <= px <= CLEAR_RECT[0] + CLEAR_RECT[2] and CLEAR_RECT[1] <= py <= CLEAR_RECT[1] + CLEAR_RECT[3]
        if not (in_face or in_clear): return False
    return True
bm2 = bmesh.new(); vmap = {}
for p in me.polygons:
    if not is_outer(p): continue
    vs = []
    for i in p.vertices:
        if i not in vmap: vmap[i] = bm2.verts.new(rest[i])
        vs.append(vmap[i])
    try: bm2.faces.new(vs)
    except ValueError: pass
SKIN = BVHTree.FromBMesh(bm2)
# mouth bag = vertices behind the lips (their opening edges must stretch when the mouth opens)
for p in me.polygons:
    u, v = uvl[p.loop_indices[0]].uv
    from layout import MOUTH_RECT
    px, py = u * ATLAS, (1 - v) * ATLAS
    if MOUTH_RECT[0] - 2 <= px <= MOUTH_RECT[0] + MOUTH_RECT[2] + 2 and MOUTH_RECT[1] - 2 <= py <= MOUTH_RECT[1] + MOUTH_RECT[3] + 2:
        mouth_bag.update(p.vertices)
def in_front_of_skin(p):
    """True if p sits in front of the FRONT skin (first skin surface met by a ray coming from the front)"""
    loc, nrm, idx, dist = SKIN.ray_cast(Vector((p.x, p.y - 3.0, p.z)), Vector((0, 1, 0)))
    if loc is None or nrm.y > 0:          # through a hole, or the first face met is a back face
        return False
    return 0.004 < loc.y - p.y < 0.15            # closed lids lie flush with the skin (<= 0.004 stud) by design

poses = [[n] for n in frames if n != 'Neutral']
poses += [['LeftEyeClosed', 'EyesLookDown'], ['RightEyeClosed', 'EyesLookDown'], ['JawDrop'],
          ['Pucker', 'LeftLipCornerPuller', 'RightLipCornerPuller'],
          ['ChinRaiser', 'ChinRaiserUpperLip', 'LeftCheekRaiser', 'RightCheekRaiser', 'LeftInnerBrowRaiser',
           'RightInnerBrowRaiser', 'LeftLipCornerDown', 'RightLipCornerDown', 'LeftLowerLipDepressor', 'RightLowerLipDepressor'],
          ['LeftEyeClosed', 'EyesLookUp'], ['LeftEyeClosed', 'EyesLookLeft'], ['RightEyeClosed', 'EyesLookRight'],
          ['JawDrop', 'LeftLipCornerPuller', 'RightLipCornerPuller']]
report = {}
bad_total = 0
for names in [[]] + poses:
    apply(names)
    co = deformed()
    poke = [i for i in inner if (co[i] - rest[i]).length > 1e-5 and in_front_of_skin(co[i])]
    flips = 0; where = {}
    for t, n0 in zip(tris, rest_n):
        if all(i in rigid for i in t): continue            # eyelids rotate rigidly ~100 deg by design
        n1 = normal(co, t)
        if n0 is not None and n1 is not None and n0.dot(n1) < math.cos(math.radians(100)):
            flips += 1
            c = (rest[t[0]] + rest[t[1]] + rest[t[2]]) / 3
            g = {groups[x.group] for i in t for x in me.vertices[i].groups if x.weight > 0.05} - {'DynamicHead'}
            k = ','.join(sorted(g)) or 'static'
            where[k] = where.get(k, 0) + 1
    stretch = 0
    for a, b in edges:
        l0 = (rest[a] - rest[b]).length; l1 = (co[a] - co[b]).length
        if l0 > 1e-4 and (l1 / l0 > 3.0 or l1 / l0 < 0.25) and not (a in mouth_bag and b in mouth_bag):
            stretch += 1
    moved = sum(1 for i in range(len(co)) if (co[i] - rest[i]).length > 1e-4)
    key = '+'.join(names) or 'Neutral'
    maxinf = max(sum(1 for g in v.groups if g.weight > 0.0) for v in me.vertices)
    report[key] = dict(moved=moved, poke=len(poke), flipped=flips, stretched=stretch)
    if poke or flips or stretch or (names and moved == 0):
        bad_total += 1
        print(f'!! {key[:60]:60s} moved={moved:5d} poke={len(poke):4d} flipped={flips:4d} stretched={stretch:4d}', where if flips else '',
              sorted({groups[x.group] for i in poke for x in me.vertices[i].groups if x.weight > 0.05}) if poke else '')
    else:
        print(f'ok {key:70s} moved={moved:5d}')
json.dump(report, open(os.path.join(ROOT, 'build', 'mesh_check.json'), 'w'), indent=1)
print('max bone influences per vertex:', max(sum(1 for g in v.groups if g.weight > 0.0) for v in me.vertices))
print('poses with problems:', bad_total, '/', len(poses) + 1)
