"""Animated previews: smooth sequences of FACS poses (blended like Roblox FaceControls), several camera angles.

usage: render_anim.py ROOT CLIP [angle,angle,...] [--test]
  CLIP: eyes | expressions | orbit
Frames go to previews/anim/<clip>_<angle>/NNNN.png (with the name of the current animation written on them).
"""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_ARG = sys.argv[1]
CLIP = sys.argv[2]
ANGLES_ARG = sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith('--') else None
TEST = '--test' in sys.argv
sys.argv = [sys.argv[0], ROOT_ARG, 'blinkseq']
src = open(os.path.join(HERE, 'render_previews.py')).read()
src = src[:src.index("if 'blinkseq' in args:")]
exec(compile(src, 'render_previews', 'exec'))
from mathutils import Quaternion
from PIL import Image, ImageDraw, ImageFont

FPS = 20
# ------------------------------------------------------------------ pose library (bone deltas read from the action)
CURVES = []
try:
    CURVES = list(act.fcurves)
except Exception:
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                CURVES += list(cb.fcurves)
POSE = {}
for k, v in head.items():
    if not k.startswith('Frame'): continue
    fr = int(k[5:]); val = {}
    for fc in CURVES:
        bn = fc.data_path.split('"')[1]; prop = fc.data_path.split('.')[-1]
        val.setdefault((bn, prop), {})[fc.array_index] = fc.evaluate(fr)
    bones = {}
    for (bn, prop), comps in val.items():
        loc, q = bones.get(bn, (Vector((0, 0, 0)), Quaternion((1, 0, 0, 0))))
        if prop == 'location': loc = Vector([comps.get(i, 0) for i in range(3)])
        elif prop == 'rotation_quaternion': q = Quaternion([comps.get(i, 1 if i == 0 else 0) for i in range(4)])
        bones[bn] = (loc, q)
    POSE[v] = bones
CORRECTIVES = {tuple(n.split('_')): n for n in POSE if '_' in n}


def apply_w(weights):
    """FaceControls-like blend: translations add, rotations compose (slerped by weight); a corrective pose adds
    (corrective - parts) scaled by the product of its parts' weights."""
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'; pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
    loc = {}; rot = {}
    for n, w in weights.items():
        if w <= 1e-4 or n not in POSE: continue
        for bn, (l, q) in POSE[n].items():
            loc[bn] = loc.get(bn, Vector()) + l * w
            rot[bn] = Quaternion((1, 0, 0, 0)).slerp(q, w) @ rot.get(bn, Quaternion((1, 0, 0, 0)))
    for parts, cname in CORRECTIVES.items():
        c = 1.0
        for p in parts: c *= weights.get(p, 0.0)
        if c <= 1e-4: continue
        for bn, (l, q) in POSE[cname].items():
            d = l - sum((POSE[p].get(bn, (Vector(), None))[0] for p in parts), Vector())
            loc[bn] = loc.get(bn, Vector()) + d * c
    for bn in set(loc) | set(rot):
        pb = arm.pose.bones[bn]
        pb.location = loc.get(bn, Vector()); pb.rotation_quaternion = rot.get(bn, Quaternion((1, 0, 0, 0)))
    bpy.context.view_layer.update()


def ease(t):
    t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)


def both(a, b, w=1.0): return {'Left' + a: w, 'Right' + b if b else 'Right' + a: w}


# ------------------------------------------------------------------ timelines: (label, pose dict, move seconds, hold seconds)
N = {}
LOOK_L, LOOK_R, LOOK_U, LOOK_D = {'EyesLookLeft': 1}, {'EyesLookRight': 1}, {'EyesLookUp': 1}, {'EyesLookDown': 1}
CLOSED = {'LeftEyeClosed': 1, 'RightEyeClosed': 1}
def mix(*ds):
    out = {}
    for d in ds:
        for k, v in d.items(): out[k] = out.get(k, 0) + v
    return out
EYES = [
    ('Repos', N, 0.0, 0.5),
    ('Regard à gauche', LOOK_L, 0.35, 0.45), ('Regard à droite', LOOK_R, 0.45, 0.45),
    ('Regard en haut', LOOK_U, 0.4, 0.45), ('Regard en bas', LOOK_D, 0.45, 0.45),
    ('Repos', N, 0.35, 0.3),
    ('Clignement', CLOSED, 0.12, 0.05), ('Clignement', N, 0.18, 0.35),
    ('Clignement lent', CLOSED, 0.45, 0.35), ('Clignement lent', N, 0.5, 0.3),
    ('Demi-fermés (fatigué)', {'LeftEyeClosed': 0.55, 'RightEyeClosed': 0.55}, 0.5, 0.6), ('Repos', N, 0.35, 0.25),
    ('Clin d\'œil gauche', {'LeftEyeClosed': 1}, 0.15, 0.3), ('Repos', N, 0.2, 0.2),
    ('Clin d\'œil droit', {'RightEyeClosed': 1}, 0.15, 0.3), ('Repos', N, 0.2, 0.25),
    ('Regard en bas + clignement', LOOK_D, 0.35, 0.2), ('Regard en bas + clignement', mix(LOOK_D, CLOSED), 0.15, 0.15),
    ('Regard en bas + clignement', LOOK_D, 0.2, 0.3),
    ('Yeux grands ouverts', {'LeftEyeUpperLidRaiser': 1, 'RightEyeUpperLidRaiser': 1, 'LeftInnerBrowRaiser': 0.7,
                             'RightInnerBrowRaiser': 0.7, 'LeftOuterBrowRaiser': 0.7, 'RightOuterBrowRaiser': 0.7}, 0.35, 0.5),
    ('Plissés', {'LeftCheekRaiser': 1, 'RightCheekRaiser': 1, 'LeftEyeClosed': 0.3, 'RightEyeClosed': 0.3,
                 'LeftBrowLowerer': 0.5, 'RightBrowLowerer': 0.5}, 0.4, 0.5),
    ('Repos', N, 0.4, 0.4),
]
SMILE = {'LeftLipCornerPuller': 1, 'RightLipCornerPuller': 1}
EXPR = [
    ('Neutre', N, 0.0, 0.5),
    ('Sourire', SMILE, 0.4, 0.5),
    ('Joyeux', mix(SMILE, {'LeftCheekRaiser': 1, 'RightCheekRaiser': 1, 'LeftEyeClosed': 0.25, 'RightEyeClosed': 0.25,
                           'JawDrop': 0.25}), 0.35, 0.6),
    ('Neutre', N, 0.35, 0.2),
    ('Fâché', {'LeftBrowLowerer': 1, 'RightBrowLowerer': 1, 'LeftLipCornerDown': 0.6, 'RightLipCornerDown': 0.6,
               'LeftLipStretcher': 0.4, 'RightLipStretcher': 0.4, 'ChinRaiser': 0.5}, 0.4, 0.7),
    ('Triste', {'LeftInnerBrowRaiser': 1, 'RightInnerBrowRaiser': 1, 'LeftLipCornerDown': 1, 'RightLipCornerDown': 1,
                'LeftLowerLipDepressor': 0.4, 'RightLowerLipDepressor': 0.4, 'EyesLookDown': 0.4,
                'LeftEyeClosed': 0.2, 'RightEyeClosed': 0.2}, 0.5, 0.7),
    ('Surpris', {'JawDrop': 0.8, 'LeftEyeUpperLidRaiser': 1, 'RightEyeUpperLidRaiser': 1, 'LeftInnerBrowRaiser': 1,
                 'RightInnerBrowRaiser': 1, 'LeftOuterBrowRaiser': 1, 'RightOuterBrowRaiser': 1}, 0.25, 0.7),
    ('Neutre', N, 0.35, 0.2),
    ('Parle', {'JawDrop': 0.6, 'LeftLipStretcher': 0.2, 'RightLipStretcher': 0.2}, 0.12, 0.05),
    ('Parle', {'JawDrop': 0.15, 'Pucker': 0.4}, 0.12, 0.05),
    ('Parle', {'JawDrop': 0.8}, 0.12, 0.05),
    ('Parle', {'JawDrop': 0.2, 'LeftLipCornerPuller': 0.4, 'RightLipCornerPuller': 0.4}, 0.12, 0.05),
    ('Parle', {'JawDrop': 0.55, 'Pucker': 0.3}, 0.12, 0.05),
    ('Parle', {'LipsTogether': 0.6}, 0.12, 0.2),
    ('Bisou', {'Pucker': 1}, 0.3, 0.6),
    ('Sourire en coin', {'LeftLipCornerPuller': 1, 'LeftOuterBrowRaiser': 0.8, 'RightBrowLowerer': 0.3,
                         'RightEyeClosed': 0.15}, 0.35, 0.7),
    ('Dégoûté', {'LeftUpperLipRaiser': 1, 'RightUpperLipRaiser': 0.6, 'LeftBrowLowerer': 0.7, 'RightBrowLowerer': 0.7,
                 'LeftCheekRaiser': 0.5, 'ChinRaiserUpperLip': 0.5}, 0.35, 0.7),
    ('Neutre', N, 0.4, 0.4),
]
ORBIT = [('Les yeux suivent la caméra', N, 0.0, 4.0), ('Clignement', CLOSED, 0.12, 0.05),
         ('Clignement', N, 0.18, 1.6)]


def timeline(segs):
    """frames: list of (label, weights)"""
    frames = []; prev = {}
    for label, pose, mv, hold in segs:
        nm = max(1, round(mv * FPS)) if mv > 0 else 0
        for i in range(nm):
            t = ease((i + 1) / nm)
            keys = set(prev) | set(pose)
            frames.append((label, {k: prev.get(k, 0) * (1 - t) + pose.get(k, 0) * t for k in keys}))
        for i in range(round(hold * FPS)):
            frames.append((label, dict(pose)))
        prev = dict(pose)
    return frames


# ------------------------------------------------------------------ cameras
ANG = {'face': (0, 0), 'gauche35': (35, 0), 'droite35': (-35, 0), 'dessous': (0, -28), 'dessus': (0, 22),
       'gauche60': (60, 0)}
if CLIP == 'eyes':
    segs, angles, res, dist, tz, lens = EYES, ['face', 'gauche35', 'droite35', 'dessous'], (480, 270), 0.03, -0.0002, 70
elif CLIP == 'expressions':
    segs, angles, res, dist, tz, lens = EXPR, ['face', 'gauche35', 'droite35'], (400, 400), 0.036, -0.0005, 70
else:
    segs, angles, res, dist, tz, lens = ORBIT, ['orbite'], (480, 360), 0.034, -0.0004, 70
if ANGLES_ARG: angles = ANGLES_ARG.split(',')
frames = timeline(segs)
if TEST: frames = frames[:3]
scn.render.resolution_x, scn.render.resolution_y = res
scn.cycles.samples = 12
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 17)
except Exception:
    font = ImageFont.load_default()
for ang in angles:
    od = os.path.join(OUT, 'anim', f'{CLIP}_{ang}'); os.makedirs(od, exist_ok=True)
    for fi, (label, w) in enumerate(frames):
        apply_w(w)
        if ang == 'orbite':
            u = fi / max(1, len(frames) - 1)
            yaw = 65 * math.sin(2 * math.pi * u); pitch = 14 * math.sin(4 * math.pi * u + 0.6)
        else:
            yaw, pitch = ANG[ang]
        place(yaw, pitch, dist, tz); cam.data.lens = lens
        fn = os.path.join(od, f'{fi:04d}.png')
        scn.render.filepath = fn
        bpy.ops.render.render(write_still=True)
        im = Image.open(fn).convert('RGBA'); bg = Image.new('RGBA', im.size, (33, 35, 41, 255)); bg.alpha_composite(im)
        im = bg.convert('RGB'); d = ImageDraw.Draw(im)
        d.rectangle((0, 0, im.width, 26), fill=(20, 21, 25)); d.text((8, 4), label, fill=(235, 235, 235), font=font)
        tag = {'face': 'face', 'gauche35': '3/4 gauche', 'droite35': '3/4 droite', 'dessous': 'dessous',
               'dessus': 'dessus', 'gauche60': 'profil', 'orbite': 'caméra en orbite'}[ang]
        tw = d.textlength(tag, font=font); d.text((im.width - tw - 8, 4), tag, fill=(150, 160, 175), font=font)
        im.save(fn)
    print('done', CLIP, ang, len(frames))
