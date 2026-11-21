"""FBX with the PBR textures EMBEDDED in the file: Roblox's 3D Importer then builds the head's SurfaceAppearance by
itself (ColorMap, NormalMap, RoughnessMap, MetalnessMap; the emissive mask is linked to the emission channel too).
usage: python export_embedded.py ROOT   (after build_head.py) -> ROOT/AnimeDynamicHead_Blocky_Textures.fbx"""
import bpy, os, sys

ROOT = os.path.abspath(sys.argv[-1])
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, 'build', 'head_rig.blend'))
head = bpy.data.objects['Head_Geo']


def img(name, color):
    im = bpy.data.images.load(os.path.join(ROOT, name))
    im.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
    im.pack()
    return im


mat = bpy.data.materials.new('HeadSurface')
mat.use_nodes = True
nt = mat.node_tree; N = nt.nodes; L = nt.links
for n in list(N):
    N.remove(n)
out = N.new('ShaderNodeOutputMaterial'); bsdf = N.new('ShaderNodeBsdfPrincipled')
L.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
def tex(name, color):
    t = N.new('ShaderNodeTexImage'); t.image = img(name, color); return t
col = tex('HeadTexture.png', True)
L.new(col.outputs['Color'], bsdf.inputs['Base Color'])
L.new(col.outputs['Alpha'], bsdf.inputs['Alpha'])
rough = tex('HeadTexture_Roughness.png', False); L.new(rough.outputs['Color'], bsdf.inputs['Roughness'])
metal = tex('HeadTexture_Metalness.png', False); L.new(metal.outputs['Color'], bsdf.inputs['Metallic'])
nrm = tex('HeadTexture_Normal.png', False)
nmap = N.new('ShaderNodeNormalMap'); L.new(nrm.outputs['Color'], nmap.inputs['Color']); L.new(nmap.outputs['Normal'], bsdf.inputs['Normal'])
emi = tex('HeadTexture_Emissive.png', False)
L.new(emi.outputs['Color'], bsdf.inputs['Emission Color']); bsdf.inputs['Emission Strength'].default_value = 1.0
head.data.materials.clear(); head.data.materials.append(mat)

bpy.ops.object.select_all(action='DESELECT')
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for o in bpy.data.objects:
    o.hide_set(False); o.hide_select = False; o.select_set(True)
bpy.context.view_layer.objects.active = arm
out_fbx = os.path.join(ROOT, 'AnimeDynamicHead_Blocky_Textures.fbx')
bpy.ops.export_scene.fbx(
    filepath=out_fbx, use_selection=True, object_types={'ARMATURE', 'MESH'},
    use_custom_props=True, add_leaf_bones=False, armature_nodetype='NULL', use_armature_deform_only=False,
    bake_anim=True, bake_anim_use_all_bones=False, bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
    bake_anim_force_startend_keying=False, bake_anim_step=1.0, bake_anim_simplify_factor=0.0,
    axis_forward='-Z', axis_up='Y', apply_unit_scale=True, apply_scale_options='FBX_SCALE_UNITS', global_scale=1.0,
    path_mode='COPY', embed_textures=True, mesh_smooth_type='FACE', use_mesh_modifiers=False)
print('embedded fbx', out_fbx, round(os.path.getsize(out_fbx) / 1e6, 2), 'MB')
