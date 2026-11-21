"""Cycles previews of the rigged head: several view angles + FACS poses + skin tones.
run: python tools/render_previews.py <project dir> [quick]"""
import bpy, sys, os, math
from mathutils import Vector, Euler

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].endswith('.py') else sys.argv[-1])
args = [a for a in sys.argv if a in ('quick', 'close', 'blinkseq')]
OUT = os.path.join(ROOT, 'previews'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, 'build', 'head_rig.blend'))
scn = bpy.context.scene
head = bpy.data.objects['Head_Geo']; arm = bpy.data.objects['Armature']
U = 1.0
import json as _json
HC = Vector(_json.load(open(os.path.join(ROOT, 'build', 'facs_map.json')))['head_centre'])
grey = bpy.data.materials.new('BodyGrey'); grey.diffuse_color = (0.42, 0.42, 0.42, 1)
for o in bpy.data.objects:
    if o.type == 'MESH' and o is not head:
        if o.name.endswith('_Att') or 'Cage' in o.name:
            o.hide_render = True
        else:
            o.data.materials.clear(); o.data.materials.append(grey)

# ---- material
mat = bpy.data.materials.new('Preview'); mat.use_nodes = True
head.data.materials.clear(); head.data.materials.append(mat)
for poly in head.data.polygons: poly.material_index = 0
nt = mat.node_tree; nt.nodes.clear()
tex = nt.nodes.new('ShaderNodeTexImage')
img = bpy.data.images.load(os.path.join(ROOT, 'HeadTexture.png')); img.alpha_mode = 'STRAIGHT'
tex.image = img; tex.interpolation = 'Linear'
skin = nt.nodes.new('ShaderNodeRGB'); skin.outputs[0].default_value = (0.42, 0.42, 0.42, 1)
mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
nt.links.new(tex.outputs['Alpha'], mix.inputs[0])
nt.links.new(skin.outputs[0], mix.inputs[6]); nt.links.new(tex.outputs['Color'], mix.inputs[7])
bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
bsdf.inputs['Roughness'].default_value = 0.55
nt.links.new(mix.outputs[2], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value = 0.6
# same RoughnessMap as the SurfaceAppearance (1 = no reflection on the eyes / ink / mouth inside, 0.6 on the skin)
rtex = nt.nodes.new('ShaderNodeTexImage'); rtex.image = bpy.data.images.load(os.path.join(ROOT, 'HeadTexture_Roughness.png'))
rtex.image.colorspace_settings.name = 'Non-Color'
nt.links.new(rtex.outputs['Color'], bsdf.inputs['Roughness'])
# emulate SurfaceAppearance EmissiveMask: the eye interior is shown flat/unlit
etex = nt.nodes.new('ShaderNodeTexImage'); etex.image = bpy.data.images.load(os.path.join(ROOT, 'HeadTexture_Emissive.png'))
etex.image.colorspace_settings.name = 'Non-Color'
em = nt.nodes.new('ShaderNodeEmission'); em.inputs['Strength'].default_value = 1.0
nt.links.new(tex.outputs['Color'], em.inputs['Color'])
lit = nt.nodes.new('ShaderNodeMixShader')
if os.environ.get('NOEMIS'):      # like Roblox with a plain TextureID / no emissive mask: everything lit
    lit.inputs[0].default_value = 0.0
else:
    nt.links.new(etex.outputs['Color'], lit.inputs[0])
nt.links.new(bsdf.outputs[0], lit.inputs[1]); nt.links.new(em.outputs[0], lit.inputs[2])
geo = nt.nodes.new('ShaderNodeNewGeometry'); tr = nt.nodes.new('ShaderNodeBsdfTransparent')
ms = nt.nodes.new('ShaderNodeMixShader')
nt.links.new(geo.outputs['Backfacing'], ms.inputs[0])
nt.links.new(lit.outputs[0], ms.inputs[1]); nt.links.new(tr.outputs[0], ms.inputs[2])
out = nt.nodes.new('ShaderNodeOutputMaterial'); nt.links.new(ms.outputs[0], out.inputs[0])
if os.environ.get('NORMALVIEW'):
    g2 = nt.nodes.new('ShaderNodeNewGeometry'); vm = nt.nodes.new('ShaderNodeVectorMath'); vm.operation = 'MULTIPLY_ADD'
    vm.inputs[1].default_value = (0.5, 0.5, 0.5); vm.inputs[2].default_value = (0.5, 0.5, 0.5)
    nt.links.new(g2.outputs['Normal'], vm.inputs[0])
    e2 = nt.nodes.new('ShaderNodeEmission'); nt.links.new(vm.outputs[0], e2.inputs['Color'])
    nt.links.new(e2.outputs[0], out.inputs[0])

# ---- world + lights
world = bpy.data.worlds.new('w'); scn.world = world; world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (0.11, 0.115, 0.13, 1)
world.node_tree.nodes['Background'].inputs[1].default_value = 1.0
world.node_tree.nodes['Background'].inputs[0].default_value = (0.20, 0.205, 0.22, 1)
scn.render.film_transparent = True
if os.environ.get('NOGI'):
    scn.cycles.max_bounces = 0
    world.node_tree.nodes['Background'].inputs[1].default_value = 0.0
def light(name, rot, energy, size=0.2):
    l = bpy.data.lights.new(name, 'SUN'); l.energy = energy; l.angle = size
    l.use_shadow = False          # Roblox-like: no self-shadowing / AO inside small cavities
    o = bpy.data.objects.new(name, l); scn.collection.objects.link(o); o.rotation_euler = Euler(rot)
light('key', (math.radians(40), 0, math.radians(-25)), 2.2)
light('fill', (math.radians(70), 0, math.radians(140)), 0.8)
light('front', (math.radians(85), 0, 0), 1.2)

# ---- camera
cam_d = bpy.data.cameras.new('cam'); cam_d.lens = 70; cam_d.clip_start = 0.05; cam_d.clip_end = 100
cam = bpy.data.objects.new('cam', cam_d); scn.collection.objects.link(cam); scn.camera = cam
def place(yaw, pitch, dist=0.052, tz=-0.0005):
    dist *= 100; tz = HC.z + tz * 100 + float(os.environ.get('FOCUS_Z', 0))
    # yaw 0 = in front of the face (camera on -Y). positive yaw = camera moves to the character's left (+X)
    y, p = math.radians(yaw), math.radians(pitch)
    target = Vector((HC.x + float(os.environ.get('FOCUS_X', 0)), HC.y, tz))
    pos = target + Vector((dist * math.sin(y) * math.cos(p), -dist * math.cos(y) * math.cos(p), dist * math.sin(p)))
    cam.location = pos
    cam.rotation_euler = (target - pos).to_track_quat('-Z', 'Y').to_euler()

scn.render.engine = 'CYCLES'
scn.cycles.device = 'CPU'
scn.cycles.samples = 24 if args else 64
scn.cycles.use_denoising = True
try:
    scn.cycles.denoiser = 'OPENIMAGEDENOISE'
except Exception:
    pass
scn.render.resolution_x = scn.render.resolution_y = 520
scn.render.film_transparent = True
scn.view_settings.view_transform = 'Standard'

# ---- poses: sum of FACS frames read from the action
act = arm.animation_data.action
def frame_of(name):
    for k, v in head.items():
        if k.startswith('Frame') and v == name: return int(k[5:])
def apply(names):
    """sum of FACS poses (like FaceControls at 1.0): locations add, rotations compose"""
    arm.animation_data.action = None
    curves = []
    try:
        curves = list(act.fcurves)
    except Exception:
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    curves += list(cb.fcurves)
    from mathutils import Quaternion
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
    for n in names:
        fr = frame_of(n)
        val = {}
        for fc in curves:
            bn = fc.data_path.split('"')[1]; prop = fc.data_path.split('.')[-1]
            val.setdefault((bn, prop), {})[fc.array_index] = fc.evaluate(fr)
        for (bn, prop), comps in val.items():
            pb = arm.pose.bones[bn]
            if prop == 'location':
                pb.location = pb.location + Vector([comps.get(i, 0) for i in range(3)])
            elif prop == 'rotation_quaternion':
                q = Quaternion([comps.get(i, 1 if i == 0 else 0) for i in range(4)])
                pb.rotation_quaternion = q @ pb.rotation_quaternion
    bpy.context.view_layer.update()

def render(fn):
    scn.render.filepath = os.path.join(OUT, fn)
    bpy.ops.render.render(write_still=True)
    from PIL import Image
    im = Image.open(scn.render.filepath); bg = Image.new('RGBA', im.size, (33, 35, 41, 255)); bg.alpha_composite(im.convert('RGBA'))
    bg.convert('RGB').save(scn.render.filepath)

def apply_frac(names, f):
    from mathutils import Quaternion
    apply(names)
    for pb in arm.pose.bones:
        pb.location = pb.location * f
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0)).slerp(pb.rotation_quaternion, f)
    bpy.context.view_layer.update()
if 'blinkseq' in args:
    scn.render.resolution_x, scn.render.resolution_y = int(os.environ.get("BW", 640)), int(os.environ.get("BH", 300))
    scn.cycles.samples = 32
    for vn, yaw, pitch in (('front', 0, 0), ('below', 0, -30), ('side', -35, 5)):
        for f in (0.0, 0.25, 0.5, 0.75, 1.0):
            apply_frac(['LeftEyeClosed', 'RightEyeClosed'], f)
            place(yaw, pitch, 0.03, -0.0002); cam.data.lens = float(os.environ.get('LENS', 85))
            render(f'blink_{vn}_{int(f * 100):03d}.png')
    apply([])
    sys.exit(0)
if 'close' in args:
    apply([])
    scn.render.resolution_x, scn.render.resolution_y = 900, 420
    for n, yaw, pitch in [('front', 0, 0), ('l30', 30, 0), ('r30', -30, 0), ('r60', -60, 0), ('down30', 0, -30), ('up15', 0, 15)]:
        place(yaw, pitch, 0.03, -0.0002)
        cam.data.lens = 85
        render(f'close_{n}.png')
    for n, names in [('blink', ['LeftEyeClosed', 'RightEyeClosed']), ('lookdown', ['EyesLookDown']), ('lookup', ['EyesLookUp']),
                     ('half', None), ('blinkside', ['LeftEyeClosed', 'RightEyeClosed']), ('squint', ['LeftCheekRaiser', 'RightCheekRaiser']),
                     ('m_jaw', ['JawDrop']), ('m_smile', ['LeftLipCornerPuller', 'RightLipCornerPuller']), ('m_down', ['LeftLipCornerDown', 'RightLipCornerDown', 'LeftLowerLipDepressor', 'RightLowerLipDepressor']),
                     ('m_pucker', ['Pucker']), ('m_talk', ['JawDrop', 'LeftLipCornerPuller', 'RightLipCornerPuller']), ('m_raise', ['LeftUpperLipRaiser', 'RightUpperLipRaiser', 'ChinRaiser'])]:
        if names is None:
            apply(['LeftEyeClosed', 'RightEyeClosed'])
            from mathutils import Quaternion
            for pb in arm.pose.bones:
                pb.location = pb.location * 0.5
                pb.rotation_quaternion = Quaternion((1, 0, 0, 0)).slerp(pb.rotation_quaternion, 0.5)
            bpy.context.view_layer.update()
        else:
            apply(names)
        if n == 'blinkside': place(-35, 5, 0.03, -0.0002)
        elif n.startswith('m_'): place(-15, 0, 0.022, -0.0040)
        else: place(0, 0, 0.03, -0.0002)
        render(f'close_pose_{n}.png')
    apply([])
    sys.exit(0)
views = [('front', 0, 0), ('left35', 35, 0), ('right35', -35, 0), ('side70', -70, 0), ('below', -15, -40), ('above', 20, 35)]
apply([])
for n, yaw, pitch in views:
    place(yaw, pitch); render(f'view_{n}.png')
if not args:
    poses = [('sad', ['ChinRaiser', 'ChinRaiserUpperLip', 'LeftCheekRaiser', 'RightCheekRaiser', 'LeftInnerBrowRaiser', 'RightInnerBrowRaiser', 'LeftLipCornerDown', 'RightLipCornerDown', 'LeftLowerLipDepressor', 'RightLowerLipDepressor']), ('happy', ['Pucker', 'LeftLipCornerPuller', 'RightLipCornerPuller']), ('look_down', ['EyesLookDown']), ('look_up', ['EyesLookUp']), ('blink', ['LeftEyeClosed', 'RightEyeClosed']),
             ('wink', ['LeftEyeClosed']), ('jaw', ['JawDrop']), ('smile', ['LeftLipCornerPuller', 'RightLipCornerPuller']),
             ('angry', ['LeftBrowLowerer', 'RightBrowLowerer', 'LeftLipStretcher', 'RightLipStretcher']),
             ('surprised', ['LeftInnerBrowRaiser', 'RightInnerBrowRaiser', 'LeftOuterBrowRaiser', 'RightOuterBrowRaiser', 'JawDrop']),
             ('pucker', ['Pucker']), ('half_blink', [])]
    for n, names in poses:
        apply(names)
        if n == 'half_blink':
            apply(['LeftEyeClosed', 'RightEyeClosed'])
            from mathutils import Quaternion
            for pb in arm.pose.bones:
                pb.location = pb.location * 0.5
                pb.rotation_quaternion = Quaternion((1, 0, 0, 0)).slerp(pb.rotation_quaternion, 0.5)
            bpy.context.view_layer.update()
        place(-12, 4, 0.036); render(f'pose_{n}.png')
    apply([])
    for col, nm in [((0.80, 0.55, 0.40, 1), 'tan'), ((0.30, 0.18, 0.12, 1), 'brown'), ((0.95, 0.85, 0.80, 1), 'pale')]:
        skin.outputs[0].default_value = col
        place(-20, 5, 0.045); render(f'skin_{nm}.png')
print('done')
