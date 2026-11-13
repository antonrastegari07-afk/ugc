import bpy, bmesh, sys, math, random, json
import numpy as np
from mathutils import Vector, Matrix, noise
D=sys.argv[-1]; random.seed(4)
bpy.ops.wm.open_mainfile(filepath=D+'/hatbase.blend'); sc=bpy.context.scene
o=bpy.data.objects['HatBase']; me=o.data
bm=bmesh.new(); bm.from_mesh(me)
pl=bm.faces.layers.int.new('part'); uvl=bm.loops.layers.uv.verify(); cnl=bm.verts.layers.float_vector.new('cn')
# parts: 0 red, 1 band, 2 pompom core, 3 fur spikes, 4 lining, 5 hair, 6 undercap
for f in bm.faces: f[pl]=f.material_index; f.smooth=True
# ---- clean the ragged underside left by the cut, then a clean lining ring to the head
ZC=-0.27
und=[f for f in bm.faces if f[pl]==1 and f.normal.z<-0.35 and f.calc_center_median().z<-0.05 and math.hypot(*f.calc_center_median()[:2])<0.72]
bmesh.ops.delete(bm,geom=und,context='FACES')
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
PC=Vector((-0.779,-0.158,-0.503))
be=[e for e in bm.edges if len(e.link_faces)==1]
tail=[e for e in be if ((e.verts[0].co+e.verts[1].co)/2-PC).length<0.33]
ring=[e for e in be if e not in tail]
tc=sum(((e.verts[0].co+e.verts[1].co)/2 for e in tail),Vector())/max(len(tail),1)
print('boundary edges',len(be),'tail',len(tail),'tail centre',[round(v,3) for v in tc])
RH=0.615
newv={}
def inner(v):
    if v not in newv:
        a=math.atan2(v.co.y,v.co.x); newv[v]=bm.verts.new((RH*math.cos(a),RH*math.sin(a),min(v.co.z,ZC+0.05)))
    return newv[v]
for e in ring:
    a,b=e.verts
    if math.hypot(a.co.x,a.co.y)<RH+0.01 and math.hypot(b.co.x,b.co.y)<RH+0.01: continue
    f=bm.faces.new([a,b,inner(b),inner(a)]); f[pl]=4; f.smooth=True
bmesh.ops.recalc_face_normals(bm,faces=[f for f in bm.faces if f[pl]==4])
for f in bm.faces:
    if f[pl]==4 and f.normal.z>0: f.normal_flip()
# ---- pompom core: noisy icosphere at the tail tip
PR=0.19
pcen=tc+(tc-Vector((tc.x*0.8,tc.y*0.8,tc.z+0.3))).normalized()*PR*0.75
r_=math.hypot(pcen.x,pcen.y)
if r_<0.6+PR+0.03: pcen.x*= (0.6+PR+0.03)/r_; pcen.y*=(0.6+PR+0.03)/r_
ico=bmesh.ops.create_icosphere(bm,subdivisions=2,radius=PR,matrix=Matrix.Translation(pcen))
for v in ico['verts']:
    d=(v.co-pcen).normalized(); v.co=pcen+d*PR*(1+0.10*noise.noise(d*2.5))
for v in ico['verts']:
    for f in v.link_faces: f[pl]=2; f.smooth=True
print('pompom centre',[round(v,3) for v in pcen])
# ---- place the hat on the head (canonical -> world)
import os
E=lambda k,d: float(os.environ.get(k,d))
TILT=math.radians(E('TILT',-4)); HSX=E('HSX',1.12); HSY=E('HSY',1.04); HZ=E('HZ',2.20); HY=E('HY',0.05)
MW=Matrix.Translation((0,HY,HZ))@Matrix.Rotation(TILT,4,'X')@Matrix.Diagonal((HSX,HSY,1.0,1.0))
bmesh.ops.transform(bm,matrix=MW,verts=bm.verts[:]); bm.normal_update()
pcw=MW@pcen

ax=MW.to_3x3()@Vector((0,0,1)); org=MW@Vector((0,0,0))
RU=random.uniform
# ================= FUR: dense small flat triangles lying on the band, all combed the same way =================
import os
FUR=int(os.environ.get('FUR','1080')); NSURF=int(FUR*0.435); NTOP=int(FUR*0.185); NBOT=int(FUR*0.148); NPOM=FUR-NSURF-NTOP-NBOT
def pick_roll():
    r=random.random()
    base=0.0 if r<0.55 else math.pi if r<0.75 else (math.pi/2 if r<0.875 else -math.pi/2)
    return base+RU(-0.35,0.35)
def shard(p,n,d,L,W,lift,roll=0.0,part=3):
    d=(d-n*d.dot(n)).normalized(); t=d.cross(n).normalized()
    base=p-n*0.012-d*0.03
    axis=(d*math.cos(lift)+n*math.sin(lift)).normalized()         # shard length direction
    up=t.cross(axis).normalized()                                   # ~n : face normal for roll 0
    t2=t*math.cos(roll)+up*math.sin(roll); g=up*math.cos(roll)-t*math.sin(roll)
    tip=base+axis*(L+0.03)+n*0.012+t2*RU(-.25,.25)*W
    P=[base-t2*W/2,base+t2*W/2,tip]
    var=random.randrange(4); u0=0.75+0.0625*var
    UV=[(u0+0.004,0.005),(u0+0.058,0.005),(u0+0.031,0.095)]
    v=[bm.verts.new(q) for q in P]
    f=bm.faces.new(v); f[pl]=part; f.smooth=True; f.normal_update()
    if f.normal.dot(g)<0: f.normal_flip(); f.normal_update()
    cnv=(f.normal+n*0.6).normalized()
    for q in v: q[cnl]=cnv
    for lp in f.loops: lp[uvl].uv=UV[v.index(lp.vert)]
bandf=[f for f in bm.faces if f[pl]==1]
areas=np.array([f.calc_area() for f in bandf]); cum=np.cumsum(areas)/areas.sum()
cnt={'s':0,'t':0,'b':0}; lim={'s':NSURF,'t':NTOP,'b':NBOT}; tries=0
while sum(cnt.values())<NSURF+NTOP+NBOT and tries<200000:
    tries+=1
    f=bandf[min(int(np.searchsorted(cum,random.random())),len(bandf)-1)]
    n=f.normal.copy(); c=f.calc_center_median(); rel=c-org; h=rel.dot(ax); radial=(rel-ax*h); rd=radial.normalized()
    if radial.length<0.63: continue
    if n.dot(rd)<-0.05 and n.dot(ax)<0.3: continue
    kind='t' if h>-0.065 else 'b' if h<-0.20 else 's'
    if cnt[kind]>=lim[kind]: continue
    vs=[v.co for v in f.verts]; w=np.random.dirichlet([1,1,1]); p=vs[0]*w[0]+vs[1]*w[1]+vs[2]*w[2]
    tang=ax.cross(rd)
    if kind=='t': d=tang+ax*RU(0.25,0.55)
    elif kind=='b': d=tang-ax*RU(0.35,0.65)+rd*0.1
    else: d=tang-ax*RU(0.05,0.35)
    d=d+Vector((RU(-.12,.12),RU(-.12,.12),RU(-.12,.12)))
    if kind=='s': shard(p,n,d,RU(0.06,0.10),RU(0.035,0.055),math.radians(RU(5,16)),RU(-0.4,0.4))
    else: shard(p,n,d,RU(0.045,0.085),RU(0.03,0.045),math.radians(RU(14,34)),pick_roll())
    cnt[kind]+=1
nsp=sum(cnt.values())
for i in range(NPOM):
    v=Vector((random.gauss(0,1),random.gauss(0,1),random.gauss(0,1))).normalized()
    p=pcw+Vector((v.x*HSX,v.y*HSY,v.z))*PR*0.98
    dn=Vector((0,0,-1)); tg_=(dn-v*dn.dot(v))
    if tg_.length<0.25: tg_=Vector((1,0,0))-v*v.x
    tg_.normalize(); d=tg_+v.cross(tg_)*0.35+Vector((RU(-.15,.15),RU(-.15,.15),RU(-.15,.15)))
    shard(p,v,d,RU(0.04,0.08),RU(0.028,0.042),math.radians(RU(18,40)),pick_roll() if random.random()<0.5 else RU(-0.4,0.4))


bmesh.ops.triangulate(bm,faces=bm.faces[:]); bm.normal_update()
bm.to_mesh(me); bm.free(); me.materials.clear()
cn=me.attributes['cn'].data
nl_=[(tuple(cn[i].vector) if Vector(cn[i].vector).length>0.5 else tuple(v.normal)) for i,v in enumerate(me.vertices)]
me.normals_split_custom_set_from_vertices(nl_)
part=np.array([a.value for a in me.attributes['part'].data])
print('TRIS',len(me.polygons),{k:int((part==k).sum()) for k in range(7)})
json.dump({'MW':[list(r) for r in MW],'pcw':list(pcw),'PR':PR},open(D+'/meta.json','w'))
o.name='SantaHat'
bpy.ops.wm.save_as_mainfile(filepath=D+'/geo.blend')
