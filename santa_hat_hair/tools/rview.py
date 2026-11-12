import bpy, bmesh, sys, math
from mathutils import Vector
a=sys.argv[sys.argv.index('--')+1:]; F,OUT=a[0],a[1]; HEADZ=float(a[2]) if len(a)>2 else None
bpy.ops.wm.open_mainfile(filepath=F); sc=bpy.context.scene
for m in bpy.data.materials:
    if False:
        m.use_nodes=True; m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=m.diffuse_color; m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=0.8
if HEADZ is not None:
    b=bmesh.new(); bmesh.ops.create_cone(b,segments=40,radius1=0.6,radius2=0.6,depth=1.2,cap_ends=True)
    bmesh.ops.bevel(b,geom=[e for e in b.edges if abs(e.verts[0].co.z-e.verts[1].co.z)<1e-6],offset=0.2,segments=5,affect='EDGES')
    for v in b.verts: v.co.z+=HEADZ
    bmesh.ops.create_cube(b,size=1.0,matrix=__import__('mathutils').Matrix.Translation((0,0,HEADZ-0.6-1.0))@__import__('mathutils').Matrix.Diagonal((2,1,2,1)))
    mh=bpy.data.meshes.new('h'); b.to_mesh(mh); Hd=bpy.data.objects.new('Head',mh); sc.collection.objects.link(Hd)
    hm=bpy.data.materials.new('hm'); hm.use_nodes=True; hm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(0.60,0.47,0.36,1); mh.materials.append(hm)
w=bpy.data.worlds.new('w'); sc.world=w; w.use_nodes=True; w.node_tree.nodes['Background'].inputs['Color'].default_value=(0.10,0.11,0.13,1); w.node_tree.nodes['Background'].inputs['Strength'].default_value=1.2
tg=Vector((0,0,0.05 if HEADZ is None else HEADZ+0.25))
for nm,loc,e in (('k',(-3,-4,5),450),('f',(4,-3,2),150),('r',(1,4,4),300),('u',(0,-1,-4),80)):
    l=bpy.data.lights.new(nm,'AREA'); l.energy=e; l.size=4; Lo=bpy.data.objects.new(nm,l); sc.collection.objects.link(Lo); Lo.location=tg+Vector(loc); Lo.rotation_euler=(Lo.location-tg).to_track_quat('Z','Y').to_euler()
cam=bpy.data.objects.new('c',bpy.data.cameras.new('c')); sc.collection.objects.link(cam); sc.camera=cam; cam.data.lens=50
RES=int(a[3]) if len(a)>3 else 500
sc.render.engine='CYCLES'; sc.cycles.samples=24; sc.render.resolution_x=RES; sc.render.resolution_y=RES; sc.view_settings.view_transform='Standard'
V={'front':(0,8),'34':(-40,15),'side':(-90,8),'back':(180,12),'34r':(45,15),'below':(-20,-45)}
CLOSE=1
if len(a)>5: tg=Vector((0,0,HEADZ+0.35)); V={'c34':(-35,12),'cback':(150,10),'cfront':(10,5)} if a[5]=='close' else {'cleft':(-95,8),'ctop':(-20,62),'cface':(0,0)} if a[5]=='close2' else {'x1':(60,50),'x2':(120,45),'x3':(20,40)}
D=float(a[4]) if len(a)>4 else 6.0
for n,(az,el) in V.items():
    A=math.radians(az); e=math.radians(el)
    cam.location=tg+Vector((math.sin(A)*math.cos(e)*D,-math.cos(A)*math.cos(e)*D,math.sin(e)*D)); cam.rotation_euler=(cam.location-tg).to_track_quat('Z','Y').to_euler()
    sc.render.filepath=f'{OUT}_{n}.png'; bpy.ops.render.render(write_still=True)
from PIL import Image
o=Image.new('RGB',(RES*3,RES*(2 if len(V)>3 else 1))); [o.paste(Image.open(f'{OUT}_{n}.png').convert('RGB'),(RES*(i%3),RES*(i//3))) for i,n in enumerate(V)]; o.save(OUT+'_sheet.png')
