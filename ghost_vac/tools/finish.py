import bpy, math, sys, mathutils
D=sys.argv[-1]; OUT=D+'/out'
bpy.ops.wm.open_mainfile(filepath=D+'/GhostVac_geo.blend')
sc=bpy.context.scene
fin=bpy.data.objects['GhostVac_UGC']
for c in sc.view_layers[0].layer_collection.children:
    c.exclude = c.name not in ('GhostVac_UGC','Preview_Mannequin')
mat=bpy.data.materials.new('GhostVac_Mat'); mat.use_nodes=True; mat.use_backface_culling=True
nt=mat.node_tree; N=nt.nodes; Lk=nt.links
for nd in list(N): N.remove(nd)
def tex(name,cs):
    im=bpy.data.images.load(f'{OUT}/{name}.png'); im.colorspace_settings.name=cs
    t=N.new('ShaderNodeTexImage'); t.image=im; return t
tc=tex('GhostVac_Color','sRGB'); tn=tex('GhostVac_Normal','Non-Color'); tm=tex('GhostVac_Metalness','Non-Color'); tr=tex('GhostVac_Roughness','Non-Color'); te=tex('GhostVac_Emissive','Non-Color')
bs=N.new('ShaderNodeBsdfPrincipled'); nm=N.new('ShaderNodeNormalMap')
Lk.new(tc.outputs['Color'],bs.inputs['Base Color']); Lk.new(tm.outputs['Color'],bs.inputs['Metallic']); Lk.new(tr.outputs['Color'],bs.inputs['Roughness'])
Lk.new(tn.outputs['Color'],nm.inputs['Color']); Lk.new(nm.outputs['Normal'],bs.inputs['Normal'])
mul=N.new('ShaderNodeMix'); mul.data_type='RGBA'; mul.blend_type='MULTIPLY'; mul.inputs['Factor'].default_value=1
Lk.new(te.outputs['Color'],mul.inputs['A']); mul.inputs['B'].default_value=((127/255)**2.2,(232/255)**2.2,1.0,1)
Lk.new(mul.outputs['Result'],bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value=2.5
geo=N.new('ShaderNodeNewGeometry'); lp=N.new('ShaderNodeLightPath'); mx=N.new('ShaderNodeMath'); mx.operation='MAXIMUM'
trn=N.new('ShaderNodeBsdfTransparent'); mix=N.new('ShaderNodeMixShader'); out=N.new('ShaderNodeOutputMaterial')
Lk.new(geo.outputs['Backfacing'],mx.inputs[0]); Lk.new(lp.outputs['Is Shadow Ray'],mx.inputs[1]); Lk.new(mx.outputs['Value'],mix.inputs['Fac'])
Lk.new(bs.outputs['BSDF'],mix.inputs[1]); Lk.new(trn.outputs['BSDF'],mix.inputs[2]); Lk.new(mix.outputs['Shader'],out.inputs['Surface'])
fin.data.materials.clear(); fin.data.materials.append(mat); fin.visible_glossy=False
mm=bpy.data.materials.new('Mannequin'); mm.use_nodes=True; pb=mm.node_tree.nodes['Principled BSDF']; pb.inputs['Base Color'].default_value=(0.62,0.64,0.68,1); pb.inputs['Roughness'].default_value=0.6
for o in bpy.data.collections['Preview_Mannequin'].objects: o.data.materials.clear(); o.data.materials.append(mm)
w=bpy.data.worlds.new('World'); sc.world=w; w.use_nodes=True; bg=w.node_tree.nodes['Background']; bg.inputs['Color'].default_value=(0.10,0.11,0.13,1); bg.inputs['Strength'].default_value=1.0
def light(name,loc,energy,size,color=(1,1,1),t=(0,0.6,0.2)):
    l=bpy.data.lights.new(name,'AREA'); l.energy=energy; l.size=size; l.color=color
    o=bpy.data.objects.new(name,l); sc.collection.objects.link(o); o.location=loc
    o.rotation_euler=(o.location-mathutils.Vector(t)).to_track_quat('Z','Y').to_euler()
light('Key',(-3,5,5),380,3); light('Fill',(4,3,1),150,3,(0.85,0.92,1.0)); light('Rim',(0,-4,4),200,3); light('Bottom',(0,4,-3),80,3)
cam=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera')); sc.collection.objects.link(cam); sc.camera=cam; cam.data.lens=60
sc.render.engine='CYCLES'; sc.cycles.device='CPU'; sc.cycles.samples=64; sc.cycles.max_bounces=6
sc.render.resolution_x=600; sc.render.resolution_y=700
def shoot(name,az,el,dist=8.5,t=(0,0.7,0.45)):
    t=mathutils.Vector(t); a=math.radians(az); e=math.radians(el)
    cam.location=t+mathutils.Vector((math.sin(a)*math.cos(e)*dist,math.cos(a)*math.cos(e)*dist,math.sin(e)*dist))
    cam.rotation_euler=(cam.location-t).to_track_quat('Z','Y').to_euler(); sc.render.filepath=f'{D}/r_{name}.png'; bpy.ops.render.render(write_still=True)
if '--render' in sys.argv:
    shoot('back',0,8); shoot('34L',-40,12); shoot('34R',40,12); shoot('side',90,5); shoot('top',20,50)
    shoot('front',180,8)
    bs.inputs['Emission Strength'].default_value=0.0; shoot('noemis',-25,10); bs.inputs['Emission Strength'].default_value=2.5
    cam.data.lens=150; shoot('zoom',0,4,8.5,(0,1.1,0.3)); cam.data.lens=60
for c in sc.view_layers[0].layer_collection.children:
    if c.name=='Preview_Mannequin': c.exclude=True
# ---- origin at the centre of the bounding box (geometry untouched relative to itself) ----
import mathutils as _mu
vs=[v.co for v in fin.data.vertices]
cen=_mu.Vector(((min(v.x for v in vs)+max(v.x for v in vs))/2,(min(v.y for v in vs)+max(v.y for v in vs))/2,(min(v.z for v in vs)+max(v.z for v in vs))/2))
for v in fin.data.vertices: v.co-=cen
fin.location=(0,0,0)
print('ORIGIN SHIFT',tuple(round(c,3) for c in cen))
bpy.ops.object.select_all(action='DESELECT'); fin.select_set(True); bpy.context.view_layer.objects.active=fin
bpy.ops.wm.obj_export(filepath=OUT+'/GhostVac_UGC.obj',export_selected_objects=True,forward_axis='Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True,path_mode='RELATIVE')
bpy.ops.export_scene.fbx(filepath=OUT+'/GhostVac_UGC.fbx',use_selection=True,axis_forward='Z',axis_up='Y',apply_unit_scale=True,path_mode='RELATIVE',mesh_smooth_type='FACE')
for c in sc.view_layers[0].layer_collection.children:
    if c.name=='Preview_Mannequin': c.exclude=False
fin.location=cen   # keep it on the preview mannequin in the .blend; origin stays at the centre
bpy.ops.file.pack_all(); bpy.ops.wm.save_as_mainfile(filepath=OUT+'/GhostVac_UGC.blend')
print('TRIS',len(fin.data.polygons),'MATS',len(fin.data.materials))
