import bpy, math, sys, os
D=sys.argv[-1]; OUT=D+'/out'
bpy.ops.wm.open_mainfile(filepath=D+'/GhostJar_geo.blend')
scene=bpy.context.scene
fin=bpy.data.objects['GhostJar_UGC']
# hide build parts (kept for editing), keep final visible
for c in scene.view_layers[0].layer_collection.children:
    if c.name!='GhostJar_UGC': c.exclude=True
# ---- material
mat=bpy.data.materials.new('GhostJar_Mat'); mat.use_nodes=True
mat.use_backface_culling=True
try: mat.surface_render_method='BLENDED'
except: pass
nt=mat.node_tree; N=nt.nodes; Lk=nt.links
for nd in list(N): N.remove(nd)
def tex(name,cs):
    im=bpy.data.images.load(f'{OUT}/{name}.png'); im.colorspace_settings.name=cs
    t=N.new('ShaderNodeTexImage'); t.image=im; t.interpolation='Linear'; return t
tc=tex('GhostJar_Color','sRGB'); tn=tex('GhostJar_Normal','Non-Color'); tm=tex('GhostJar_Metalness','Non-Color')
tr=tex('GhostJar_Roughness','Non-Color'); te=tex('GhostJar_Emissive','Non-Color')
bs=N.new('ShaderNodeBsdfPrincipled'); nm=N.new('ShaderNodeNormalMap')
Lk.new(tc.outputs['Color'],bs.inputs['Base Color']); Lk.new(tm.outputs['Color'],bs.inputs['Metallic']); Lk.new(tr.outputs['Color'],bs.inputs['Roughness'])
Lk.new(tn.outputs['Color'],nm.inputs['Color']); Lk.new(nm.outputs['Normal'],bs.inputs['Normal'])
mul=N.new('ShaderNodeMix'); mul.data_type='RGBA'; mul.blend_type='MULTIPLY'; mul.inputs['Factor'].default_value=1
Lk.new(te.outputs['Color'],mul.inputs['A']); mul.inputs['B'].default_value=(127/255)**2.2 and ((127/255)**2.2,(232/255)**2.2,1.0,1)
Lk.new(mul.outputs['Result'],bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value=2.5
geo=N.new('ShaderNodeNewGeometry'); tr_=N.new('ShaderNodeBsdfTransparent'); mix=N.new('ShaderNodeMixShader')
lp=N.new('ShaderNodeLightPath'); mx=N.new('ShaderNodeMath'); mx.operation='MAXIMUM'
Lk.new(geo.outputs['Backfacing'],mx.inputs[0]); Lk.new(lp.outputs['Is Shadow Ray'],mx.inputs[1]); Lk.new(mx.outputs['Value'],mix.inputs['Fac']); Lk.new(bs.outputs['BSDF'],mix.inputs[1]); Lk.new(tr_.outputs['BSDF'],mix.inputs[2])
out=N.new('ShaderNodeOutputMaterial'); Lk.new(mix.outputs['Shader'],out.inputs['Surface'])
fin.data.materials.clear(); fin.data.materials.append(mat)
fin.visible_glossy=False  # Roblox has no raytraced reflections of the item itself
# ---- world / lights / camera
w=bpy.data.worlds.new('World'); scene.world=w; w.use_nodes=True
bg=w.node_tree.nodes['Background']; v=(30/255)**2.2; bg.inputs['Color'].default_value=(v,(31/255)**2.2,(36/255)**2.2,1); bg.inputs['Strength'].default_value=1.0
def light(name,loc,energy,size,color=(1,1,1)):
    l=bpy.data.lights.new(name,'AREA'); l.energy=energy; l.size=size; l.color=color
    o=bpy.data.objects.new(name,l); scene.collection.objects.link(o); o.location=loc
    d=o.location-__import__('mathutils').Vector((0,0,0.6)); o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return o
light('Key',(-2.2,-2.5,2.6),420,2.0)
light('Rim',(2.0,2.4,1.8),180,1.5,(0.75,0.9,1.0))
light('Fill',(2.5,-2.0,0.6),110,2.0)
cam=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera')); scene.collection.objects.link(cam); scene.camera=cam
cam.data.lens=85
scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.cycles.samples=96
scene.cycles.transparent_max_bounces=64; scene.cycles.max_bounces=8
scene.render.resolution_x=640; scene.render.resolution_y=800
scene.view_settings.view_transform='AgX' if 'AgX' in [x for x in ('AgX',)] else 'Standard'
def shoot(name,az_deg,el=12,dist=4.6):
    import mathutils
    t=mathutils.Vector((0,0,0.6)); a=math.radians(az_deg); e=math.radians(el)
    cam.location=t+mathutils.Vector((math.sin(a)*math.cos(e)*dist,-math.cos(a)*math.cos(e)*dist,math.sin(e)*dist))
    cam.rotation_euler=(cam.location-t).to_track_quat('Z','Y').to_euler()
    scene.render.filepath=f'{D}/render_{name}.png'; bpy.ops.render.render(write_still=True)
if '--render' in sys.argv:
    shoot('34',-35); shoot('front',0,8); shoot('side',90,8)
# ---- exports
bpy.ops.object.select_all(action='DESELECT'); fin.select_set(True); bpy.context.view_layer.objects.active=fin
bpy.ops.wm.obj_export(filepath=OUT+'/GhostJar_UGC.obj',export_selected_objects=True,forward_axis='Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True,path_mode='RELATIVE')
bpy.ops.export_scene.fbx(filepath=OUT+'/GhostJar_UGC.fbx',use_selection=True,axis_forward='Z',axis_up='Y',apply_unit_scale=True,global_scale=1.0,path_mode='RELATIVE',mesh_smooth_type='FACE')
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/GhostJar_UGC.blend')
print('TRIS',len(fin.data.polygons),'MATS',len(fin.data.materials))
