"""Export the dynamic head ALONE (no body) for a head UGC: AnimeDynamicHead_HeadOnly.fbx
Keeps: Head_Geo (FACS frames, custom props), Head_OuterCage, the head attachments (FaceCenter, FaceFront, Hair, Hat)
and the bones Root > HumanoidRootNode > LowerTorso > UpperTorso > Head > DynamicHead + face bones (the neck position
comes from the Head bone).  Everything else (body meshes, body cages, body attachments, arm / leg bones) is removed.
usage: python export_head_only.py ROOT     (after build_head.py, reads ROOT/build/head_rig.blend)"""
import bpy, os, sys

ROOT = os.path.abspath(sys.argv[-1])
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, 'build', 'head_rig.blend'))
KEEP_OBJ = {'Head_Geo', 'Head_OuterCage', 'FaceCenter_Att', 'FaceFront_Att', 'Hair_Att', 'Hat_Att'}
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name not in KEEP_OBJ:
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
chain = {'Root', 'HumanoidRootNode', 'LowerTorso', 'UpperTorso'}
def under_head(b):
    while b is not None:
        if b.name == 'Head': return True
        b = b.parent
    return False
keep_b = {b.name for b in arm.data.bones if b.name in chain or under_head(b)}
bpy.context.view_layer.objects.active = arm
for o in bpy.data.objects: o.hide_set(False); o.hide_select = False
bpy.ops.object.mode_set(mode='EDIT')
for eb in list(arm.data.edit_bones):
    if eb.name not in keep_b:
        arm.data.edit_bones.remove(eb)
bpy.ops.object.mode_set(mode='OBJECT')
missing = KEEP_OBJ - {o.name for o in bpy.data.objects}
assert not missing, missing
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
    o.select_set(True)
out = os.path.join(ROOT, 'AnimeDynamicHead_HeadOnly.fbx')
bpy.ops.export_scene.fbx(
    filepath=out, use_selection=True, object_types={'ARMATURE', 'MESH'},
    use_custom_props=True, add_leaf_bones=False, armature_nodetype='NULL', use_armature_deform_only=False,
    bake_anim=True, bake_anim_use_all_bones=False, bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
    bake_anim_force_startend_keying=False, bake_anim_step=1.0, bake_anim_simplify_factor=0.0,
    axis_forward='-Z', axis_up='Y', apply_unit_scale=True, apply_scale_options='FBX_SCALE_UNITS', global_scale=1.0,
    path_mode='STRIP', mesh_smooth_type='FACE', use_mesh_modifiers=False)
h = bpy.data.objects['Head_Geo']
print('head only:', sorted(o.name for o in bpy.data.objects), 'bones', len(arm.data.bones),
      'frames', len([k for k in h.keys() if k.startswith('Frame')]), 'tris', sum(len(p.vertices) - 2 for p in h.data.polygons))
