import bpy, bmesh, sys, math, random, json, os
import numpy as np
from mathutils import Vector, Matrix, noise
D=sys.argv[-1]; random.seed(4); RU=random.uniform
E=lambda k,d: float(os.environ.get(k,d))
bpy.ops.wm.read_factory_settings(use_empty=True); sc=bpy.context.scene
# ================= RED BODY: smooth dome + drooping cone, fused by voxel remesh =================
T=Vector((-0.97,0.24,0)).normalized(); UP=Vector((0,0,1)); SD=UP.cross(T)
# dome leaning towards the tail side + the tip draped against it, down over the band (crease kept between the two)
RXY=0.735; HD=E('HD',0.60); SK=E('SK',0.20)
bm=bmesh.new()
bmesh.ops.create_uvsphere(bm,u_segments=56,v_segments=32,radius=1.0)
for v in bm.verts:
    x,y,z=v.co; p=Vector((x*RXY,y*RXY*1.02,z*HD))
    if p.z>0: p+=T*SK*(p.z/HD)**1.3
    v.co=p
SP=[(0.08,0.18,0.36),(0.34,0.29,0.335),(0.57,0.25,0.275),(0.745,0.13,0.21),(0.85,-0.01,0.15),(0.90,-0.13,0.098)]
def catmull(P,t):
    n=len(P)-1; x=t*n; i=min(int(x),n-1); f=x-i
    p0=P[max(i-1,0)]; p1=P[i]; p2=P[i+1]; p3=P[min(i+2,n)]
    return tuple(0.5*((2*p1[k])+(-p0[k]+p2[k])*f+(2*p0[k]-5*p1[k]+4*p2[k]-p3[k])*f*f+(-p0[k]+3*p1[k]-3*p2[k]+p3[k])*f**3) for k in range(3))
NR=50; NS=28; rings=[]
for i in range(NR+1):
    t=i/NR; s,z,r=catmull(SP,t); s2,z2,_=catmull(SP,min(t+0.005,1)); s1,z1,_=catmull(SP,max(t-0.005,0))
    tg=(T*(s2-s1)+UP*(z2-z1)).normalized(); nr=tg.cross(SD).normalized(); c=T*s+UP*z
    rings.append([bm.verts.new(c+(nr*math.cos(2*math.pi*j/NS)*0.85+SD*math.sin(2*math.pi*j/NS)*1.10)*r) for j in range(NS)])
    last=(c,tg,r)
for i in range(NR):
    for j in range(NS):
        bm.faces.new([rings[i][j],rings[i][(j+1)%NS],rings[i+1][(j+1)%NS],rings[i+1][j]])
tipc=last[0]+last[1]*last[2]*0.8; tv=bm.verts.new(tipc)
for j in range(NS): bm.faces.new([rings[NR][j],rings[NR][(j+1)%NS],tv])
bm.faces.new(rings[0][::-1])
bmesh.ops.recalc_face_normals(bm,faces=bm.faces[:])
me=bpy.data.meshes.new('red'); bm.to_mesh(me); bm.free()
ob=bpy.data.objects.new('red',me); sc.collection.objects.link(ob); bpy.context.view_layer.objects.active=ob; ob.select_set(True)
m=ob.modifiers.new('r','REMESH'); m.mode='VOXEL'; m.voxel_size=0.018; m.use_smooth_shade=True
bpy.ops.object.modifier_apply(modifier='r')
m=ob.modifiers.new('s','SMOOTH'); m.factor=0.5; m.iterations=int(E('SMOOTH',6))
bpy.ops.object.modifier_apply(modifier='s')
bm=bmesh.new(); bm.from_mesh(me)
dome=[f for f in bm.faces if math.hypot(f.calc_center_median().x,f.calc_center_median().y)<0.80]
geom=dome+list({e for f in dome for e in f.edges})+list({v for f in dome for v in f.verts})
bmesh.ops.bisect_plane(bm,geom=geom,plane_co=(0,0,-0.08),plane_no=(0,0,1),clear_inner=True)
# drop anything left loose under the dome
seen=set(); comps=[]
for f in bm.faces:
    if f in seen: continue
    st=[f]; seen.add(f); c=[]
    while st:
        g=st.pop(); c.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h not in seen: seen.add(h); st.append(h)
    comps.append(c)
comps.sort(key=len,reverse=True)
for c in comps[1:]: bmesh.ops.delete(bm,geom=c,context='FACES')
bm.to_mesh(me); bm.free()
me.calc_loop_triangles(); n0=len(me.loop_triangles)
m=ob.modifiers.new('d','DECIMATE'); m.ratio=E('RED',900)/n0; bpy.ops.object.modifier_apply(modifier='d')
me.calc_loop_triangles(); co=np.array([v.co for v in me.vertices])
print('red tris',len(me.loop_triangles),'bounds',co.min(0).round(2),co.max(0).round(2))
# ================= assemble everything in one bmesh =================
bm=bmesh.new(); bm.from_mesh(me); bpy.data.objects.remove(ob)
pl=bm.faces.layers.int.new('part'); uvl=bm.loops.layers.uv.verify(); cnl=bm.verts.layers.float_vector.new('cn')
for f in bm.faces: f[pl]=0; f.smooth=True
# ---- fur band: revolved rounded-rectangle profile (outer, top and bottom faces; open towards the head)
RCB=0.715; HWB=0.105; ZCB=-0.17; HHB=0.19; PEXP=E('PEXP',2.6); NA=40; NP=9
ZC=ZCB-HHB
def prof(k):
    a=math.radians(-118+ (118+128)*k/(NP-1))          # from inner-bottom, round the outside, to inner-top
    c,s=math.cos(a),math.sin(a)
    return (RCB+HWB*math.copysign(abs(c)**(2/PEXP),c), ZCB+HHB*math.copysign(abs(s)**(2/PEXP),s))
bandr=[]
for i in range(NA):
    ph=2*math.pi*i/NA; row=[]
    for k in range(NP):
        r,z=prof(k); r*=1+0.012*noise.noise(Vector((math.cos(ph)*2.2,math.sin(ph)*2.2,k*0.7))); z+=0.010*noise.noise(Vector((math.cos(ph)*2.2+9,math.sin(ph)*2.2,k*0.7)))
        row.append(bm.verts.new((r*math.cos(ph),r*math.sin(ph),z)))
    bandr.append(row)
for i in range(NA):
    for k in range(NP-1):
        f=bm.faces.new([bandr[i][k],bandr[(i+1)%NA][k],bandr[(i+1)%NA][k+1],bandr[i][k+1]]); f[pl]=1; f.smooth=True
bmesh.ops.recalc_face_normals(bm,faces=[f for f in bm.faces if f[pl]==1])
tst=[f for f in bm.faces if f[pl]==1][NP//2]
if tst.normal.dot(Vector((tst.calc_center_median().x,tst.calc_center_median().y,0)))<0:
    for f in bm.faces:
        if f[pl]==1: f.normal_flip()
# ---- pompom core at the end of the cone
PR=E('PR',0.182)
pcen=tipc+Vector((0,0,-1))*PR*0.80+T*0.045
core=bmesh.ops.create_uvsphere(bm,u_segments=12,v_segments=8,radius=PR,matrix=Matrix.Translation(pcen))
for v in core['verts']:
    d=(v.co-pcen).normalized(); v.co=pcen+d*PR*(1+0.07*noise.noise(d*2.5))
    for f in v.link_faces: f[pl]=2; f.smooth=True
# ---- place on the head
TILT=math.radians(E('TILT',-5)); HZ=E('HZ',2.12); HY=E('HY',0.02)
MW=Matrix.Translation((0,HY,HZ))@Matrix.Rotation(TILT,4,'X')
bmesh.ops.transform(bm,matrix=MW,verts=bm.verts[:]); bm.normal_update()
pcw=MW@pcen; ax=MW.to_3x3()@UP; org=MW@Vector((0,0,0))
# ================= FUR: many tiny flat triangles, all combed one way =================
FUR=int(E('FUR',2250)); fs=[float(x) for x in os.environ.get('FSH','0.47,0.11,0.09,0.10').split(',')]
NSURF=int(FUR*fs[0]); NBORD=int(FUR*fs[1]); NTOP=int(FUR*fs[2]); NBOT=int(FUR*fs[3]); NPOM=FUR-NSURF-NBORD-NTOP-NBOT
K=E('SPK',1.0)
def pick_roll():
    r=random.random()
    base=0.0 if r<0.78 else math.pi if r<0.90 else (math.pi/2 if r<0.95 else -math.pi/2)
    return base+RU(-0.25,0.25)
def shard(p,n,d,L,W,lift,roll=0.0):
    d=(d-n*d.dot(n)).normalized(); t=d.cross(n).normalized()
    base=p-n*0.010-d*0.02
    axis=(d*math.cos(lift)+n*math.sin(lift)).normalized(); up=t.cross(axis).normalized()
    t2=t*math.cos(roll)+up*math.sin(roll); g=up*math.cos(roll)-t*math.sin(roll)
    tip=base+axis*(L+0.02)+n*0.010+t2*RU(-.25,.25)*W
    v=[bm.verts.new(q) for q in (base-t2*W/2,base+t2*W/2,tip)]
    var=random.randrange(4); u0=0.75+0.0625*var
    UV=[(u0+0.004,0.005),(u0+0.058,0.005),(u0+0.031,0.095)]
    f=bm.faces.new(v); f[pl]=3; f.smooth=True; f.normal_update()
    if f.normal.dot(g)<0: f.normal_flip(); f.normal_update()
    cnv=(f.normal*0.35+n).normalized()
    for q in v: q[cnl]=cnv
    for lp in f.loops: lp[uvl].uv=UV[v.index(lp.vert)]
J=lambda a: Vector((RU(-a,a),RU(-a,a),RU(-a,a)))
# border row where the velvet meets the fur
for i in range(NBORD):
    ph=RU(0,2*math.pi); rd0=Vector((math.cos(ph),math.sin(ph),0))
    pc=rd0*RU(0.705,0.735)+UP*RU(0.004,0.02)
    p=MW@pc; rd=(MW.to_3x3()@rd0).normalized(); n=(rd*0.75+ax*0.66).normalized(); tang=ax.cross(rd)
    upv=(ax*0.8-rd*0.6).normalized()
    shard(p,n,tang+upv*RU(0.10,0.35)+J(0.06),RU(0.045,0.075)*K,RU(0.026,0.040)*K,math.radians(RU(5,14)),RU(-0.25,0.25))
bandf=[f for f in bm.faces if f[pl]==1]
areas=np.array([f.calc_area() for f in bandf]); cum=np.cumsum(areas)/areas.sum()
cnt={'s':0,'t':0,'b':0}; lim={'s':NSURF,'t':NTOP,'b':NBOT}; tries=0
while sum(cnt.values())<NSURF+NTOP+NBOT and tries<600000:
    tries+=1
    f=bandf[min(int(np.searchsorted(cum,random.random())),len(bandf)-1)]
    n=f.normal.copy(); c=f.calc_center_median(); rel=c-org; h=rel.dot(ax); rd=(rel-ax*h).normalized()
    kind='t' if n.dot(ax)>0.55 else 'b' if n.dot(ax)<-0.45 else 's'
    if cnt[kind]>=lim[kind]: continue
    vs=[v.co for v in f.verts]; w=np.random.dirichlet([1,1,1,1][:len(vs)]); p=sum((vs[i]*w[i] for i in range(len(vs))),Vector())
    tang=ax.cross(rd)
    if kind=='t': shard(p,n,tang+rd*RU(-0.25,0.05)+J(0.07),RU(0.045,0.075)*K,RU(0.026,0.040)*K,math.radians(RU(6,16)),RU(-0.25,0.25))
    elif kind=='b': shard(p,n,tang+rd*RU(0.0,0.3)-ax*0.1+J(0.07),RU(0.040,0.065)*K,RU(0.024,0.036)*K,math.radians(RU(10,24)),pick_roll())
    else: shard(p,n,tang-ax*RU(0.05,0.22)+J(0.07),RU(0.045,0.075)*K,RU(0.026,0.040)*K,math.radians(RU(5,15)),RU(-0.25,0.25))
    cnt[kind]+=1
for i in range(NPOM):
    v=Vector((random.gauss(0,1),random.gauss(0,1),random.gauss(0,1))).normalized()
    p=pcw+v*PR*0.985
    dn=Vector((0,0,-1)); tg_=(dn-v*dn.dot(v))
    if tg_.length<0.25: tg_=Vector((1,0,0))-v*v.x
    tg_.normalize()
    shard(p,v,tg_+v.cross(tg_)*0.30+J(0.09),RU(0.030,0.055)*K,RU(0.020,0.030)*K,math.radians(RU(20,40)),pick_roll() if random.random()<0.3 else RU(-0.25,0.25))
bmesh.ops.triangulate(bm,faces=bm.faces[:]); bm.normal_update()
me=bpy.data.meshes.new('SantaHat'); bm.to_mesh(me); bm.free()
o=bpy.data.objects.new('SantaHat',me); sc.collection.objects.link(o)
cn=me.attributes['cn'].data
me.normals_split_custom_set_from_vertices([(tuple(cn[i].vector) if Vector(cn[i].vector).length>0.5 else tuple(v.normal)) for i,v in enumerate(me.vertices)])
part=np.array([a.value for a in me.attributes['part'].data])
print('TRIS',len(me.polygons),{k:int((part==k).sum()) for k in range(5)})
json.dump({'MW':[list(r) for r in MW],'pcw':list(pcw),'PR':PR,'T':list(T)},open(D+'/meta.json','w'))
bpy.ops.wm.save_as_mainfile(filepath=D+'/geo.blend')
