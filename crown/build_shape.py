# Fallen King Crown - shape pass. Units = studs, Z up, front = -Y. Mannequin head: cube 1.2, top at z=2.2.
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix
OUT=sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc=bpy.context.scene
Z0=2.17                   # band bottom (sits on the head)
RI,RO=0.50,0.555          # band inner / outer radius
HB=0.30                   # band height
NS=7                      # spikes
def obj(name,bm):
    me=bpy.data.meshes.new(name); bmesh.ops.triangulate(bm,faces=bm.faces[:]); bm.to_mesh(me); bm.free()
    o=bpy.data.objects.new(name,me); sc.collection.objects.link(o)
    for p in me.polygons: p.use_smooth=False
    return o
def lathe(bm,prof,N):
    rings=[[bm.verts.new((r*math.sin(2*math.pi*j/N),-r*math.cos(2*math.pi*j/N),z)) for j in range(N)] for r,z in prof]
    for i in range(len(rings)-1):
        for j in range(N):
            j1=(j+1)%N; bm.faces.new([rings[i][j],rings[i][j1],rings[i+1][j1],rings[i+1][j]])
# ---- band with raised rims (closed ring profile, counter-clockwise in r/z)
band=bmesh.new()
prof=[(RI,Z0),(RO+0.03,Z0),(RO+0.04,Z0+0.015),(RO+0.04,Z0+0.06),(RO+0.01,Z0+0.075),(RO,Z0+0.09),
      (RO,HB+Z0-0.09),(RO+0.01,HB+Z0-0.075),(RO+0.04,HB+Z0-0.06),(RO+0.04,HB+Z0-0.015),(RO+0.03,HB+Z0),(RI,HB+Z0),(RI,Z0)]
lathe(band,prof,40); bmesh.ops.recalc_face_normals(band,faces=band.faces[:]); obj('Band',band)
# ---- blade spikes
def spike(bm,ang,height,scale=1.0,gem=False):
    c=Vector((math.sin(ang),-math.cos(ang),0)); tg=Vector((math.cos(ang),math.sin(ang),0)); up=Vector((0,0,1))
    rmid=(RI+RO)/2+0.01
    # (z from band top, half width, radial half thickness, outward offset)
    prof=[(-0.20,0.20,0.045,0.0),(0.0,0.20,0.045,0.0),(0.06,0.15,0.040,0.0),(0.13,0.09,0.036,0.0),
          (0.19,0.085,0.034,0.0),(0.27,0.16,0.036,0.0),(0.33,0.14,0.033,0.0),(0.47,0.06,0.025,0.0),(0.60,0.0,0.0,0.0)]
    rings=[]
    for zf,hw,ht,_ in prof:
        z=Z0+HB+zf*height/0.60 if zf>0 else Z0+HB+zf
        hw*=scale; ht*=scale
        base=c*rmid+up*z
        if hw==0: rings.append([bm.verts.new(base)]); continue
        sec=[(-hw,0),(-hw*0.55,ht),(0,ht*1.25),(hw*0.55,ht),(hw,0),(hw*0.55,-ht),(0,-ht*1.25),(-hw*0.55,-ht)]   # faceted blade section
        rings.append([bm.verts.new(base+tg*a+c*b) for a,b in sec])
    m=8
    for i in range(len(rings)-1):
        A,B=rings[i],rings[i+1]
        for k in range(m):
            k1=(k+1)%m
            if len(B)==1: bm.faces.new([A[k],A[k1],B[0]])
            else: bm.faces.new([A[k],A[k1],B[k1],B[k]])
    bm.faces.new(rings[0][::-1])
sp=bmesh.new()
for i in range(NS):
    ang=2*math.pi*i/NS
    front=(i==0)
    spike(sp,ang,0.62 if front else (0.48 if i in (1,NS-1) else 0.40),1.15 if front else 1.0)
bmesh.ops.recalc_face_normals(sp,faces=sp.faces[:]); obj('Spikes',sp)
# ---- front gem frame (diamond) + gem, and diamond studs between spikes
def diamond_frame(bm,ang,zc,h,w,depth,outr):
    c=Vector((math.sin(ang),-math.cos(ang),0)); tg=Vector((math.cos(ang),math.sin(ang),0)); up=Vector((0,0,1))
    o=c*outr+up*zc
    outer=[o+up*h,o+tg*w,o-up*h,o-tg*w]; inner=[o+up*h*0.72+c*depth,o+tg*w*0.72+c*depth,o-up*h*0.72+c*depth,o-tg*w*0.72+c*depth]
    back=[p-c*0.05 for p in outer]
    vo=[bm.verts.new(p) for p in outer]; vi=[bm.verts.new(p) for p in inner]; vb=[bm.verts.new(p) for p in back]
    for k in range(4):
        k1=(k+1)%4
        bm.faces.new([vo[k],vo[k1],vi[k1],vi[k]])     # bevelled front of the frame
        bm.faces.new([vb[k],vb[k1],vo[k1],vo[k]])     # sides
    bm.faces.new(vb[::-1])
    return o,c,up,tg
def octa(bm,o,c,up,tg,h,w,d):
    v=[bm.verts.new(p) for p in (o+up*h,o+tg*w,o-up*h,o-tg*w,o+c*d,o-c*d*0.3)]
    for a,b in ((0,1),(1,2),(2,3),(3,0)):
        bm.faces.new([v[a],v[b],v[4]]); bm.faces.new([v[b],v[a],v[5]])
fr=bmesh.new(); gm=bmesh.new()
o,c,up,tg=diamond_frame(fr,0.0,Z0+HB*0.55,0.17,0.14,0.03,RO+0.045)
octa(gm,o+c*0.025,c,up,tg,0.115,0.095,0.06)
for i in range(NS):
    ang=2*math.pi*(i+0.5)/NS
    if i in (0,NS-1): continue   # room for the front gem frame
    cc=Vector((math.sin(ang),-math.cos(ang),0)); tt=Vector((math.cos(ang),math.sin(ang),0))
    octa(fr,cc*(RO+0.005)+Vector((0,0,Z0+HB/2)),cc,Vector((0,0,1)),tt,0.045,0.045,0.05)
bmesh.ops.recalc_face_normals(fr,faces=fr.faces[:]); bmesh.ops.recalc_face_normals(gm,faces=gm.faces[:])
obj('Frame_Studs',fr); obj('Gem',gm)
tris=sum(len(o.data.polygons) for o in sc.objects if o.type=='MESH'); print('TRIS',tris)
# ---- preview
head=bmesh.new(); bmesh.ops.create_cube(head,size=1.2)
for v in head.verts: v.co.z+=1.6
mh=bpy.data.meshes.new('Head'); head.to_mesh(mh); H=bpy.data.objects.new('Head',mh); sc.collection.objects.link(H)
tor=bmesh.new(); bmesh.ops.create_cube(tor,size=1.0)
for v in tor.verts: v.co=Vector((v.co.x*2,v.co.y*1,v.co.z*2))
mt=bpy.data.meshes.new('Torso'); tor.to_mesh(mt); T=bpy.data.objects.new('Torso',mt); sc.collection.objects.link(T)
clay=bpy.data.materials.new('clay'); clay.use_nodes=True; b=clay.node_tree.nodes['Principled BSDF']; b.inputs['Base Color'].default_value=(0.05,0.05,0.055,1); b.inputs['Roughness'].default_value=0.45; b.inputs['Metallic'].default_value=0.6
gemm=bpy.data.materials.new('gem'); gemm.use_nodes=True; g=gemm.node_tree.nodes['Principled BSDF']; g.inputs['Base Color'].default_value=(0.3,0.9,1,1); g.inputs['Emission Color'].default_value=(0.3,0.9,1,1); g.inputs['Emission Strength'].default_value=6
skin=bpy.data.materials.new('skin'); skin.use_nodes=True; skin.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(0.62,0.64,0.68,1)
for o in sc.objects:
    if o.type=='MESH': o.data.materials.append(gemm if o.name=='Gem' else (skin if o.name in ('Head','Torso') else clay))
w=bpy.data.worlds.new('w'); sc.world=w; w.use_nodes=True; w.node_tree.nodes['Background'].inputs['Color'].default_value=(0.12,0.12,0.14,1)
for nm,loc,e in (('k',(-3,-4,5),500),('f',(4,-2,3),200),('r',(0,4,4),300)):
    l=bpy.data.lights.new(nm,'AREA'); l.energy=e; l.size=3; L=bpy.data.objects.new(nm,l); sc.collection.objects.link(L); L.location=loc
    L.rotation_euler=(L.location-Vector((0,0,2.4))).to_track_quat('Z','Y').to_euler()
cam=bpy.data.objects.new('cam',bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera=cam; cam.data.lens=85
sc.render.engine='CYCLES'; sc.cycles.samples=48; sc.render.resolution_x=700; sc.render.resolution_y=600
def shoot(n,az,el,dist=7,t=(0,0,2.45)):
    t=Vector(t); a=math.radians(az); e=math.radians(el)
    cam.location=t+Vector((math.sin(a)*math.cos(e)*dist,-math.cos(a)*math.cos(e)*dist,math.sin(e)*dist))
    cam.rotation_euler=(cam.location-t).to_track_quat('Z','Y').to_euler(); sc.render.filepath=f'{OUT}/c_{n}.png'; bpy.ops.render.render(write_still=True)
shoot('front34',-30,15); shoot('front',0,8); shoot('side',90,5); shoot('top',20,55)
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/Crown_shape.blend')
