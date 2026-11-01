import bpy, bmesh, math, sys
from mathutils import Vector
D=sys.argv[-1]; OUT=D+'/out'
bpy.ops.wm.open_mainfile(filepath=D+'/HBH_geo.blend'); sc=bpy.context.scene
ob=bpy.data.objects['HornsBlackHole_UGC']
mat=bpy.data.materials.new('Horns_Mat'); mat.use_nodes=True; mat.use_backface_culling=True
N=mat.node_tree.nodes; Lk=mat.node_tree.links
for nd in list(N): N.remove(nd)
def tex(nm,cs):
    im=bpy.data.images.load(f'{OUT}/{nm}.png'); im.colorspace_settings.name=cs; t=N.new('ShaderNodeTexImage'); t.image=im; return t
tc=tex('Horns_Color','sRGB'); tn=tex('Horns_Normal','Non-Color'); tm=tex('Horns_Metalness','Non-Color'); tr=tex('Horns_Roughness','Non-Color'); te=tex('Horns_Emissive','Non-Color')
bs=N.new('ShaderNodeBsdfPrincipled'); nm=N.new('ShaderNodeNormalMap')
Lk.new(tc.outputs['Color'],bs.inputs['Base Color']); Lk.new(tm.outputs['Color'],bs.inputs['Metallic']); Lk.new(tr.outputs['Color'],bs.inputs['Roughness'])
Lk.new(tn.outputs['Color'],nm.inputs['Color']); Lk.new(nm.outputs['Normal'],bs.inputs['Normal'])
mul=N.new('ShaderNodeMix'); mul.data_type='RGBA'; mul.blend_type='MULTIPLY'; mul.inputs['Factor'].default_value=1
Lk.new(te.outputs['Color'],mul.inputs['A']); mul.inputs['B'].default_value=((220/255)**2.2,(210/255)**2.2,1.0,1)
Lk.new(mul.outputs['Result'],bs.inputs['Emission Color']); bs.inputs['Emission Strength'].default_value=4.0
geo=N.new('ShaderNodeNewGeometry'); lp=N.new('ShaderNodeLightPath'); mx=N.new('ShaderNodeMath'); mx.operation='MAXIMUM'
trn=N.new('ShaderNodeBsdfTransparent'); mix=N.new('ShaderNodeMixShader'); out=N.new('ShaderNodeOutputMaterial')
Lk.new(geo.outputs['Backfacing'],mx.inputs[0]); Lk.new(lp.outputs['Is Shadow Ray'],mx.inputs[1]); Lk.new(mx.outputs['Value'],mix.inputs['Fac'])
Lk.new(bs.outputs['BSDF'],mix.inputs[1]); Lk.new(trn.outputs['BSDF'],mix.inputs[2]); Lk.new(mix.outputs['Shader'],out.inputs['Surface'])
ob.data.materials.clear(); ob.data.materials.append(mat)
heads=[]
if '--export' not in sys.argv:
    for nm_,c,s,colr in (('Head',(0,0,1.6),(1.2,1.2,1.2),(0.95,0.85,0.25)),('Torso',(0,0,0),(2,1,2),(0.15,0.35,0.8))):
        b=bmesh.new(); bmesh.ops.create_cube(b,size=1)
        for v in b.verts: v.co=Vector((v.co.x*s[0]+c[0],v.co.y*s[1]+c[1],v.co.z*s[2]+c[2]))
        me=bpy.data.meshes.new(nm_); b.to_mesh(me); o2=bpy.data.objects.new(nm_,me); sc.collection.objects.link(o2)
        sk=bpy.data.materials.new(nm_); sk.use_nodes=True; sk.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=colr+(1,); me.materials.append(sk)
w=bpy.data.worlds.new('w'); sc.world=w; w.use_nodes=True; w.node_tree.nodes['Background'].inputs['Color'].default_value=(0.03,0.03,0.04,1)
def light(nm_,loc,e,size,t=(0,0,2.5)):
    l=bpy.data.lights.new(nm_,'AREA'); l.energy=e; l.size=size; L=bpy.data.objects.new(nm_,l); sc.collection.objects.link(L); L.location=loc
    L.rotation_euler=(L.location-Vector(t)).to_track_quat('Z','Y').to_euler()
light('key',(-3,-4,5),500,3); light('fill',(4,-2,3),180,3); light('rim',(0,4,4.5),400,3)
cam=bpy.data.objects.new('cam',bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera=cam
sc.render.engine='CYCLES'; sc.cycles.samples=64; sc.render.resolution_x=800; sc.render.resolution_y=700
def shoot(n,az,el,dist=8,t=(0,0,2.45),lens=75):
    cam.data.lens=lens; t=Vector(t); a=math.radians(az); e=math.radians(el)
    cam.location=t+Vector((math.sin(a)*math.cos(e)*dist,-math.cos(a)*math.cos(e)*dist,math.sin(e)*dist))
    cam.rotation_euler=(cam.location-t).to_track_quat('Z','Y').to_euler(); sc.render.filepath=f'{D}/r_{n}.png'; bpy.ops.render.render(write_still=True)
if '--render' in sys.argv:
    shoot('back',180,20); shoot('back34',145,18); shoot('front',0,8); shoot('side',90,8)
    shoot('zoom',180,20,8,(0,0,2.82),220); shoot('zoomhorn',-40,8,8,(0.7,0,2.5),170)
    bs.inputs['Emission Strength'].default_value=0; shoot('noemis',150,20); shoot('noemis_zoom',180,20,8,(0,0,2.82),220); bs.inputs['Emission Strength'].default_value=4
if '--export' in sys.argv:
    vs=[v.co for v in ob.data.vertices]
    cen=Vector(tuple((min(v[i] for v in vs)+max(v[i] for v in vs))/2 for i in range(3)))
    for v in ob.data.vertices: v.co-=cen
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob
    bpy.ops.export_scene.fbx(filepath=OUT+'/HornsBlackHole_UGC.fbx',use_selection=True,axis_forward='Z',axis_up='Y',apply_unit_scale=True,global_scale=0.01,path_mode='RELATIVE',mesh_smooth_type='OFF')
    bpy.ops.wm.obj_export(filepath=OUT+'/HornsBlackHole_UGC.obj',export_selected_objects=True,forward_axis='Z',up_axis='Y',export_materials=True,export_triangulated_mesh=True,path_mode='RELATIVE')
    for im in list(bpy.data.images):
        if im.name.startswith('spiked_horns'): bpy.data.images.remove(im)
    ob.location=cen; bpy.ops.file.pack_all(); bpy.ops.wm.save_as_mainfile(filepath=OUT+'/HornsBlackHole_UGC.blend')
    print('TRIS',len(ob.data.polygons),'SIZE',[round(max(v[i] for v in vs)-min(v[i] for v in vs),3) for i in range(3)])
