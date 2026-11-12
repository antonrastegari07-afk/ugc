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
PR=0.185
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
TILT=math.radians(-5)
MW=Matrix.Translation((0,0.0,2.11))@Matrix.Rotation(TILT,4,'X')
bmesh.ops.transform(bm,matrix=MW,verts=bm.verts[:]); bm.normal_update()
pcw=MW@pcen
# ---- fur spikes (3-sided, sunk into the surface) on band + pompom
NTOP=240; NBOT=210; NSURF=110; NPOM=120
def shard(p,n,d,L,W,part=3,double=False):
    d=d.normalized(); t=d.cross(n)
    if t.length<1e-4: t=d.orthogonal()
    t.normalize(); base=p-n*0.010-d*0.025
    P=[base-t*W/2,base+t*W/2,base+d*(L+0.025)+t*random.uniform(-.3,.3)*W]
    var=random.randrange(4); u0=0.75+0.0625*var
    UV=[(u0+0.004,0.005),(u0+0.058,0.005),(u0+0.031,0.118)]
    v=[bm.verts.new(q) for q in P]
    for q in v: q[cnl]=(n*0.85+d*0.15).normalized()
    f=bm.faces.new(v); f[pl]=part; f.smooth=True; f.normal_update()
    if f.normal.dot(n)<0: f.normal_flip()
    for lp in f.loops: lp[uvl].uv=UV[v.index(lp.vert)]
    if double:
        v2=[bm.verts.new(q) for q in P]; g=bm.faces.new(v2); g[pl]=part; g.smooth=False; g.normal_update()
        if g.normal.dot(f.normal)>0: g.normal_flip()
        for lp in g.loops: lp[uvl].uv=UV[v2.index(lp.vert)]
ax=MW.to_3x3()@Vector((0,0,1)); org=MW@Vector((0,0,0))
nsp=0
# top fringe: along the red/white border, pointing up over the velvet
border=[e for e in bm.edges if len(e.link_faces)==2 and {e.link_faces[0][pl],e.link_faces[1][pl]}=={0,1}]
bl=np.array([e.calc_length() for e in border]); bc=np.cumsum(bl)/bl.sum()
for i in range(NTOP):
    e=border[min(int(np.searchsorted(bc,random.random())),len(border)-1)]
    fr=[f for f in e.link_faces if f[pl]==0][0]; fw=[f for f in e.link_faces if f[pl]==1][0]
    w=random.random(); p=e.verts[0].co.lerp(e.verts[1].co,w)
    n=fr.normal.copy(); et=(e.verts[1].co-e.verts[0].co).normalized()
    up=n.cross(et)
    if up.dot(fr.calc_center_median()-p)<0: up=-up
    az=random.uniform(-0.7,0.7); al=math.radians(random.uniform(18,42))
    d=(up*math.cos(az)+et*math.sin(az))*math.cos(al)+n*math.sin(al)
    shard(p-up*random.uniform(0.0,0.03)+n*0.012,n,d,random.uniform(0.045,0.10),random.uniform(0.04,0.065)); nsp+=1
# bottom fringe + sparse flat tufts on the outer face
bandf=[f for f in bm.faces if f[pl]==1]
areas=np.array([f.calc_area() for f in bandf]); cum=np.cumsum(areas)/areas.sum()
nb=0; ns=0; tries=0
while (nb<NBOT or ns<NSURF) and tries<40000:
    tries+=1
    f=bandf[min(int(np.searchsorted(cum,random.random())),len(bandf)-1)]
    n=f.normal.copy(); c=f.calc_center_median(); rel=c-org; h=rel.dot(ax); radial=(rel-ax*h); rd=radial.normalized()
    if radial.length<0.68 or n.dot(rd)<0.1: continue
    vs=[v.co for v in f.verts]; w=np.random.dirichlet([1,1,1]); p=vs[0]*w[0]+vs[1]*w[1]+vs[2]*w[2]
    down=(-ax-n*(-ax).dot(n))
    if down.length<0.2: down=-ax.copy()
    down.normalize(); side=down.cross(n); az=random.uniform(-0.6,0.6)
    if h<-0.185:
        if nb>=NBOT: continue
        d=(-ax*0.8+rd*0.25)*math.cos(az)+side*math.sin(az)
        shard(p,n,d,random.uniform(0.06,0.12),random.uniform(0.045,0.075)); nb+=1
    elif h<-0.04:
        if ns>=NSURF: continue
        al=math.radians(random.uniform(8,20))
        d=(down*math.cos(az)+side*math.sin(az))*math.cos(al)+n*math.sin(al)
        shard(p,n,d,random.uniform(0.06,0.10),random.uniform(0.05,0.08)); ns+=1
nsp+=nb+ns
for i in range(NPOM):
    v=Vector((random.gauss(0,1),random.gauss(0,1),random.gauss(0,1))).normalized()
    p=pcw+v*PR*0.98
    tgt=(Vector((0,0,-1))-v*(-v.z)); tgt=tgt.normalized() if tgt.length>0.2 else v.orthogonal().normalized()
    al=math.radians(random.uniform(18,45)); sd=tgt.cross(v); az=random.uniform(-1.2,1.2)
    d=(tgt*math.cos(az)+sd*math.sin(az))*math.cos(al)+v*math.sin(al)
    shard(p,v,d,random.uniform(0.05,0.09),random.uniform(0.05,0.075))
# ---- hair: wolf cut, wide layered locks on a cylinder around the head
HC=Vector((0,0,1.6))
def band_bottom(phi):
    p=MW@Vector((0.7*math.sin(phi),-0.7*math.cos(phi),ZC)); return p.z
def strip_rect(layer,var):   # atlas: u 0.75..1, 4 cols; rows: layer0 v .13-.42, layer1 .42-.71, layer2 .71-1.0
    u0=0.75+0.0625*var; v0=0.13+0.29*layer
    return (u0+0.003,v0+0.004,u0+0.0595,v0+0.286)
nl=0
def lock(phi0,z0,ztip,W,off,sweep,flick,twist,nseg,layer,closed=True,hook=0.0,r0=0.625,lift=0.0):
    global nl
    L=z0-ztip; pts=[]
    for i in range(nseg+1):
        s=i/nseg
        z=z0-L*s**0.95+lift*(max(s-0.6,0)/0.4)**2
        phi=phi0+sweep*s**1.4+hook*(max(s-0.65,0)/0.35)**2
        r=r0+off*min(s*3.0,1)+0.05*math.sin(math.pi*min(s*1.15,1))+flick*(max(s-0.45,0)/0.55)**2.2
        if z<1.08 and layer==0: r-=0.05*min((1.08-z)/0.3,1)
        pts.append(Vector((r*math.sin(phi),-r*math.cos(phi),z)))
    R=strip_rect(layer,random.randrange(4)); rings=[]
    for i,p in enumerate(pts):
        s=i/nseg
        tg=(pts[min(i+1,nseg)]-pts[max(i-1,0)]).normalized()
        rad=Vector((p.x,p.y,0)).normalized(); n=(rad-tg*rad.dot(tg)).normalized(); b=tg.cross(n).normalized()
        tw=twist*s; b2=b*math.cos(tw)+n*math.sin(tw); n2=n*math.cos(tw)-b*math.sin(tw)
        w=W*(1-s**1.9)**0.95
        h=0.20*w+0.006
        if i==nseg: rings.append(None); tipv=bm.verts.new(p); continue
        rings.append((bm.verts.new(p-b2*w/2),bm.verts.new(p+n2*h),bm.verts.new(p+b2*w/2),n2))
    def mk(vs,uvs,nref,inv=False):
        f=bm.faces.new(vs); f[pl]=5; f.smooth=True; f.normal_update()
        if (f.normal.dot(nref)<0)!=inv: f.normal_flip()
        m={v:uv for v,uv in zip(vs,uvs)}
        for lp in f.loops: u,v=m[lp.vert]; lp[uvl].uv=(R[0]+(R[2]-R[0])*u,R[1]+(R[3]-R[1])*(1-v))
    for i in range(nseg):
        A=rings[i]; B=rings[i+1]; v0,v1=i/nseg,(i+1)/nseg
        if B is None:
            mk([A[0],A[1],tipv],[(0,v0),(.5,v0),(.5,1)],A[3]); mk([A[1],A[2],tipv],[(.5,v0),(1,v0),(.5,1)],A[3])
            if closed: mk([A[2],A[0],tipv],[(1,v0),(0,v0),(.5,1)],A[3],True)
        else:
            mk([A[0],A[1],B[1],B[0]],[(0,v0),(.5,v0),(.5,v1),(0,v1)],A[3]); mk([A[1],A[2],B[2],B[1]],[(.5,v0),(1,v0),(1,v1),(.5,v1)],A[3])
            if closed: mk([A[2],A[0],B[0],B[2]],[(1,v0),(0,v0),(0,v1),(1,v1)],A[3],True)
    nl+=1
pom_phi=math.atan2(pcw.x,-pcw.y)
def tipz(phi,layer):
    a=abs(math.degrees(phi))
    if a<24: z=1.69
    elif a<52: z=1.69-(a-24)/28*0.26
    elif a<82: z=1.43-(a-52)/30*0.21
    elif a<120: z=1.22-(a-82)/38*0.10
    else: z=1.12-(a-120)/60*0.30
    if a>=82: z+=0.17*layer+(0.08 if layer==2 else 0)
    return z
RU=random.uniform
def ring_of(layer,n,W,off,flick,arc=(-180,180),skip_front=True,closed=True):
    for j in range(n):
        phi=math.radians(arc[0]+(arc[1]-arc[0])*(j+0.5)/n+RU(-4,4)+layer*5)
        a=abs(math.degrees(phi))
        if skip_front and a<50: continue
        dp=abs((phi-pom_phi+math.pi)%(2*math.pi)-math.pi)
        fl=flick*RU(0.6,1.2); of=off
        if dp<0.5 and layer==2: continue
        if dp<0.6: fl*=0.2
        sw=math.copysign(RU(0.05,0.22),phi)+0.45*noise.noise(Vector((math.cos(phi)*1.7,math.sin(phi)*1.7,layer*3.1)))+RU(-0.12,0.12)
        zt=tipz(phi,layer)+RU(-0.13,0.10)
        z0=band_bottom(phi)+0.09
        lock(phi,z0,zt,W*RU(0.85,1.2),of,sw,fl,RU(-0.25,0.25),5 if z0-zt<0.75 else 6,layer,closed,hook=RU(-0.06,0.06),lift=(RU(0.0,0.09) if layer==2 else RU(0.0,0.05) if layer==1 else 0.0))
ring_of(0,20,0.42,0.012,0.03,closed=False)
ring_of(1,25,0.34,0.075,0.15)
ring_of(2,23,0.28,0.140,0.20)
# bangs: swept to one side, two layers, a few longer face-framing pieces
for j in range(8):
    phi=math.radians(-48+96*(j+0.5)/8+RU(-3,3)); z0=band_bottom(phi)+0.08
    lock(phi,z0,tipz(phi,0)+RU(-0.05,0.06),0.26*RU(0.9,1.15),0.03,RU(0.10,0.26),0.03,RU(-0.2,0.2),5,1,True,hook=RU(0.0,0.08),r0=0.63)
for j in range(6):
    phi=math.radians(-40+80*(j+0.5)/6+RU(-5,5)); z0=band_bottom(phi)+0.08
    lock(phi,z0,tipz(phi,0)+0.08+RU(-0.04,0.06),0.21*RU(0.9,1.2),0.08,RU(0.12,0.32),0.09,RU(-0.25,0.25),5,2,True,hook=RU(0.02,0.10),r0=0.63,lift=RU(0,0.04))
for sgn in (-1,1):
    for j,(ang,zt,ly,w_) in enumerate(((52,1.36,1,0.26),(60,1.24,2,0.24),(68,1.30,1,0.28),(76,1.18,2,0.25),(63,1.42,2,0.20))):
        phi=math.radians(sgn*(ang+RU(-3,3))); z0=band_bottom(phi)+0.08
        lock(phi,z0,zt+RU(-0.05,0.05),w_,0.03+0.05*(ly-1),sgn*RU(-0.10,0.12),0.05*ly,RU(-0.2,0.2),5,ly,True,hook=RU(-0.05,0.05),r0=0.63)
# undercap (hides the scalp between locks, sides/back only)
NU=22; zc0=1.92; rows=[(0.612,1.95),(0.612,1.60),(0.605,1.32)]
grid=[]
for j in range(NU+1):
    phi=math.radians(72+216*j/NU)
    grid.append([bm.verts.new((r*math.sin(phi),-r*math.cos(phi),z)) for r,z in rows])
for j in range(NU):
    for k in range(2):
        f=bm.faces.new([grid[j][k],grid[j][k+1],grid[j+1][k+1],grid[j+1][k]]); f[pl]=6; f.smooth=True; f.normal_update()
        if f.normal.dot(Vector((f.calc_center_median().x,f.calc_center_median().y,0)))<0: f.normal_flip()
        for lp in f.loops: lp[uvl].uv=(0.76+0.01*(lp.vert.co.z>1.5),0.16+0.1*(lp.vert.co.z-1.1))
print('locks',nl,'spikes',nsp)
bmesh.ops.triangulate(bm,faces=bm.faces[:]); bm.normal_update()
# fix spike winding (outward)
for f in bm.faces:
    if f[pl]==3:
        c=f.calc_center_median(); tip=max(f.verts,key=lambda v:0)  # placeholder
bm.to_mesh(me); bm.free(); me.materials.clear()
cn=me.attributes['cn'].data
nl_=[(tuple(cn[i].vector) if Vector(cn[i].vector).length>0.5 else tuple(v.normal)) for i,v in enumerate(me.vertices)]
me.normals_split_custom_set_from_vertices(nl_)
part=np.array([a.value for a in me.attributes['part'].data])
print('TRIS',len(me.polygons),{k:int((part==k).sum()) for k in range(7)},'dims',[round(v,3) for v in o.dimensions])
json.dump({'MW':[list(r) for r in MW],'pcw':list(pcw),'PR':PR},open(D+'/meta.json','w'))
o.name='SantaHat'
bpy.ops.wm.save_as_mainfile(filepath=D+'/geo.blend')
