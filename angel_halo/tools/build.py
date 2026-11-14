import bpy, bmesh, sys, math
import numpy as np
from mathutils import Vector
from PIL import Image
D=sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True); sc=bpy.context.scene
R=0.55; r=0.05; M=198; N=10          # major/minor radius (studs), segments -> 2*M*N = 3960 triangles
ZH=3.0                                # ring centre height for the preview (head centre 1.6 -> 1.4 above)
bm=bmesh.new(); uvl=bm.loops.layers.uv.new('UVMap')
V=[[bm.verts.new(((R+r*math.cos(2*math.pi*j/N))*math.cos(2*math.pi*i/M),(R+r*math.cos(2*math.pi*j/N))*math.sin(2*math.pi*i/M),r*math.sin(2*math.pi*j/N))) for j in range(N)] for i in range(M)]
for i in range(M):
    for j in range(N):
        i2=(i+1)%M; j2=(j+1)%N
        quad=[(V[i][j],i,j),(V[i2][j],i+1,j),(V[i2][j2],i+1,j+1),(V[i][j2],i,j+1)]
        for tri in ((0,1,2),(0,2,3)):
            f=bm.faces.new([quad[k][0] for k in tri]); f.smooth=True
            for lp,k in zip(f.loops,tri): lp[uvl].uv=(0.02+0.96*quad[k][1]/M,0.02+0.96*quad[k][2]/N)
bm.normal_update()
me=bpy.data.meshes.new('AngelHalo_UGC'); bm.to_mesh(me); bm.free()
ob=bpy.data.objects.new('AngelHalo_UGC',me); sc.collection.objects.link(ob)
# exact torus normals
nl=[]
for v in me.vertices:
    c=Vector((v.co.x,v.co.y,0)).normalized()*R; nl.append(tuple((v.co-c).normalized()))
me.normals_split_custom_set_from_vertices(nl)
# roundness check: every vertex exactly on the torus
dev=max(abs((Vector((v.co.x,v.co.y,0)).normalized()*R-v.co).length-r) for v in me.vertices)
print('tris',len(me.polygons),'verts',len(me.vertices),'max deviation from torus',dev,'outer diameter',2*(R+r),'tube diameter',2*r)
# textures
S=256
Image.new('RGB',(S,S),(255,255,255)).save(D+'/AngelHalo_Color.png')
Image.new('RGB',(S,S),(128,128,255)).save(D+'/AngelHalo_Normal.png')
Image.new('L',(S,S),0).save(D+'/AngelHalo_Metalness.png')
Image.new('L',(S,S),255).save(D+'/AngelHalo_Roughness.png')
Image.new('L',(S,S),255).save(D+'/AngelHalo_Emissive.png')
# export (centred on origin, studs)
m=bpy.data.materials.new('AngelHalo'); me.materials.append(m)
bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob
bpy.ops.export_scene.fbx(filepath=D+'/AngelHalo_UGC.fbx',use_selection=True,axis_forward='Z',axis_up='Y',apply_unit_scale=True,global_scale=0.01,mesh_smooth_type='OFF',bake_anim=False,add_leaf_bones=False)
# ---- preview: emissive white ring over a dark test avatar
m.use_nodes=True; nt=m.node_tree; bs=nt.nodes['Principled BSDF']
bs.inputs['Base Color'].default_value=(1,1,1,1); bs.inputs['Roughness'].default_value=1.0; bs.inputs['Metallic'].default_value=0.0
bs.inputs['Emission Color'].default_value=(1,1,1,1); bs.inputs['Emission Strength'].default_value=3.0
ob.location=(0,0,ZH)
b=bmesh.new(); bmesh.ops.create_cone(b,segments=40,radius1=0.6,radius2=0.6,depth=1.2,cap_ends=True)
bmesh.ops.bevel(b,geom=[e for e in b.edges if abs(e.verts[0].co.z-e.verts[1].co.z)<1e-6],offset=0.2,segments=5,affect='EDGES')
for v in b.verts: v.co.z+=1.6
from mathutils import Matrix
bmesh.ops.create_cube(b,size=1.0,matrix=Matrix.Translation((0,0,0.0))@Matrix.Diagonal((2,1,2,1)))
mh=bpy.data.meshes.new('h'); b.to_mesh(mh); H=bpy.data.objects.new('Head',mh); sc.collection.objects.link(H)
hm=bpy.data.materials.new('hm'); hm.use_nodes=True; hm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(0.05,0.07,0.25,1); mh.materials.append(hm)
w=bpy.data.worlds.new('w'); sc.world=w; w.use_nodes=True; w.node_tree.nodes['Background'].inputs['Color'].default_value=(0.012,0.013,0.018,1)
l=bpy.data.lights.new('k','AREA'); l.energy=250; l.size=4; Lo=bpy.data.objects.new('k',l); sc.collection.objects.link(Lo); Lo.location=(-3,-4,5); Lo.rotation_euler=(Lo.location-Vector((0,0,2))).to_track_quat('Z','Y').to_euler()
cam=bpy.data.objects.new('c',bpy.data.cameras.new('c')); sc.collection.objects.link(cam); sc.camera=cam; cam.data.lens=50
RES=700; sc.render.engine='CYCLES'; sc.cycles.samples=32; sc.render.resolution_x=RES; sc.render.resolution_y=RES; sc.view_settings.view_transform='Standard'
tg=Vector((0,0,2.3)); views={'front':(0,24,5.0),'34':(-40,28,5.0),'top':(0,89,4.5),'close':(20,22,2.6)}
for n,(az,el,dist) in views.items():
    t=tg if n!='close' else Vector((0,0,ZH))
    A=math.radians(az); e=math.radians(el)
    cam.location=t+Vector((math.sin(A)*math.cos(e)*dist,-math.cos(A)*math.cos(e)*dist,math.sin(e)*dist)); cam.rotation_euler=(cam.location-t).to_track_quat('Z','Y').to_euler()
    sc.render.filepath=f'{D}/p_{n}.png'; bpy.ops.render.render(write_still=True)
from PIL import ImageFilter, ImageChops
sheet=Image.new('RGB',(RES*4,RES))
for i,n in enumerate(views):
    im=Image.open(f'{D}/p_{n}.png').convert('RGB')
    a=np.asarray(im,float)/255; mask=(a.min(-1)>0.93)[...,None]*a           # bright (emissive) pixels only
    glow=Image.fromarray((mask*255).astype(np.uint8))
    g=np.asarray(glow.filter(ImageFilter.GaussianBlur(RES*0.006)),float)*0.5+np.asarray(glow.filter(ImageFilter.GaussianBlur(RES*0.03)),float)*0.9
    out=1-(1-a)*(1-np.clip(g/255,0,1))                                      # screen blend = bloom like in the avatar viewer
    sheet.paste(Image.fromarray((np.clip(out,0,1)*255).astype(np.uint8)),(RES*i,0))
sheet.save(D+'/Preview.png')
# ---- reimport check
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=D+'/AngelHalo_UGC.fbx')
for x in bpy.data.objects:
    if x.type=='MESH':
        x.data.calc_loop_triangles(); print('REIMPORT',x.name,'studs',[round(v*100,4) for v in x.dimensions],'tris',len(x.data.loop_triangles),'mats',len(x.data.materials),'uv',len(x.data.uv_layers),'meshes',len([q for q in bpy.data.objects if q.type=='MESH']))
