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

# ================= HAIR: the user's own strand model, kept below the hat =================
HSC=1.05; CAPR=1.0; ADD_TRIS=0; TARGET_MASS=0; POKE=9.0; HAIR_BUDGET=2270; TUCK=0.02; EASE=0.20; KC=30
with bpy.data.libraries.load(D+'/hairbase.blend') as (src,dst): dst.meshes=[m for m in src.meshes]
hm=dst.meshes[0]
hb=bmesh.new(); hb.from_mesh(hm)
HCEN=Vector((0,0,1.6))
hb.transform(Matrix.Translation((0,0.03,0.05))@Matrix.Translation(HCEN)@Matrix.Scale(HSC,4)@Matrix.Translation(-HCEN))
bmesh.ops.remove_doubles(hb,verts=hb.verts[:],dist=1e-5)
cid=hb.faces.layers.int.new('cid'); tone=hb.faces.layers.int.new('tone')
huv=hb.loops.layers.uv.active
# components (cap = biggest)
seen=set(); comps=[]
for f in hb.faces:
    if f in seen: continue
    st=[f]; seen.add(f); c=[]
    while st:
        g=st.pop(); c.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h not in seen: seen.add(h); st.append(h)
    comps.append(c)
comps.sort(key=len,reverse=True)
for i,c in enumerate(comps):
    rs=[math.hypot(v.co.x,v.co.y) for f in c for v in f.verts]; mr=sum(rs)/len(rs)
    for f in c: f[cid]=i; f[tone]=0 if mr<0.74 else (1 if mr<0.86 else 2)
# ---- nothing visible is cut: only faces lying completely inside the hat (hidden) are dropped
from mathutils.bvhtree import BVHTree
hv=[v.co.copy() for v in bm.verts]; vi={v:i for i,v in enumerate(bm.verts)}
hf=[[vi[v] for v in f.verts] for f in bm.faces if f[pl] in (0,1)]
bvh=BVHTree.FromPolygons(hv,hf)
MWi=MW.inverted(); M3=MW.to_3x3()
def covered(p,margin=0.0):
    pc=MWi@p
    if pc.z<=ZC+margin: return False
    rad=Vector((pc.x,pc.y,0))
    if rad.length<1e-4: rad=Vector((1,0,0))
    d1=(M3@rad).normalized()
    d2=(d1*0.8-ax*0.6).normalized()
    ok=bvh.ray_cast(p,ax,3.0)[0] is not None and bvh.ray_cast(p,d1,3.0)[0] is not None
    if ok and pc.z<ZC+0.22: ok=bvh.ray_cast(p,d2,3.0)[0] is not None
    return ok
# tuck the hair under the hat: anything that would poke through is pulled inside (no cut), easing in below the band
def hit_dist(zc,dirc):
    o_=MW@Vector((0,0,zc)); d_=(M3@dirc).normalized(); h_=bvh.ray_cast(o_,d_,4.0)
    return (o_,d_,h_[3] if h_[0] is not None else None)
capv={v for f in hb.faces if f[cid]==0 for v in f.verts}
ntuck=0
def soft(d,lim,s=0.07):
    # monotonic squeeze: everything beyond (lim-s) is compressed into the last s under the hat surface (order kept)
    a0=lim-s
    return d if d<=a0 else a0+s*(1-math.exp(-(d-a0)/s))
for v in hb.verts:
    if v in capv: continue
    pc=MWi@v.co; rad=Vector((pc.x,pc.y,0))
    if rad.length<1e-4 or pc.z<ZC-EASE: continue
    dirc=rad.normalized()
    if pc.z>=ZC:
        o_,d_,dh=hit_dist(pc.z,dirc)
        if dh is None: o_,d_,dh=hit_dist(min(pc.z,0.55),dirc)
        if dh is None: continue
        dv=(v.co-o_).dot(d_); nd=soft(dv,max(dh-TUCK,0.1))
        if nd<dv-1e-5: v.co=v.co-d_*(dv-nd); ntuck+=1
    else:
        o_,d_,dh=hit_dist(ZC+0.03,dirc)
        if dh is None: continue
        o2=MW@Vector((0,0,pc.z)); dv=(v.co-o2).dot(d_); nd=soft(dv,dh-TUCK)
        if nd<dv-1e-5:
            w=((pc.z-(ZC-EASE))/EASE)**2
            v.co=v.co-d_*(dv-nd)*w; ntuck+=1
print('tucked verts',ntuck)
# real visibility test: a hair vertex is hidden only if NO outward direction reaches the open air
# (occluders = hat + a head/torso stand-in). Only faces one ring inside the hidden zone are dropped.
occ_v=list(hv); occ_f=list(hf)
def add_prism(pts,z0,z1):
    b0=len(occ_v); n=len(pts)
    for z in (z0,z1):
        for x,y in pts: occ_v.append(Vector((x,y,z)))
    for i in range(n):
        j=(i+1)%n; occ_f.append([b0+i,b0+j,b0+n+j,b0+n+i])
    occ_f.append([b0+i for i in range(n)]); occ_f.append([b0+n+i for i in range(n)])
add_prism([(0.585*math.cos(2*math.pi*i/24),0.585*math.sin(2*math.pi*i/24)) for i in range(24)],1.0,2.19)
add_prism([(-1,-0.5),(1,-0.5),(1,0.5),(-1,0.5)],-1.0,1.0)
obvh=BVHTree.FromPolygons(occ_v,occ_f)
ND=96; dirs=[]
for i in range(ND):
    zz=1-2*(i+0.5)/ND; rr=math.sqrt(max(0,1-zz*zz)); th=i*2.399963
    dirs.append(Vector((rr*math.cos(th),rr*math.sin(th),zz)))
def hidden(p):
    for d in dirs:
        if obvh.ray_cast(p+d*0.004,d,6.0)[0] is None: return False
    return True
hid={v:hidden(v.co) for v in hb.verts}
deepv={v:(hid[v] and all(hid[e.other_vert(v)] for e in v.link_edges)) for v in hb.verts}
below={v:((MWi@v.co).z<=ZC) for v in hb.verts}
cf0={}
for f in hb.faces: cf0.setdefault(f[cid],[]).append(f)
kill=[]; stats=[0,0,0]
for k,fs in cf0.items():
    vs={v for f in fs for v in f.verts}
    if k!=0 and all(hid[v] for v in vs): kill+=fs; stats[0]+=1; continue
    kill+=[f for f in fs if all(deepv[v] for v in f.verts)]
print('strands fully hidden',stats[0],'| hidden verts',sum(hid.values()),'of',len(hid))
bmesh.ops.delete(hb,geom=list(set(kill)),context='FACES')
bmesh.ops.delete(hb,geom=[v for v in hb.verts if not v.link_faces],context='VERTS')
hb.faces.ensure_lookup_table()
cut_co=MW@Vector((0,0,ZC))
capn=sum(len(f.verts)-2 for f in hb.faces if f[cid]==0); strn=sum(len(f.verts)-2 for f in hb.faces if f[cid]!=0)
STR=min(1.0,(HAIR_BUDGET-capn)/strn)
print('hair tris kept',capn+strn,'cap',capn,'strands',strn,'-> strand ratio',round(STR,3))
hb.faces.ensure_lookup_table()
# ---- add strands: copies of the user's own hanging strands, turned around the head to fill thin areas (back/sides)
def comp_faces():
    d={}
    for f in hb.faces: d.setdefault(f[cid],[]).append(f)
    return d
cf=comp_faces(); cutz=cut_co.z
def info(fs):
    vs={v for f in fs for v in f.verts}; P=np.array([v.co for v in vs])
    return dict(n=sum(len(f.verts)-2 for f in fs),az=math.atan2(P[:,0].mean(),-P[:,1].mean()),zmin=P[:,2].min(),zmax=P[:,2].max(),rmax=np.hypot(P[:,0],P[:,1]).max())
inf={k:info(v) for k,v in cf.items() if k!=0}
NB=12; mass=[0]*NB
def b(az): return int(((math.degrees(az)+360)%360)/(360/NB))%NB
for k,i in inf.items(): mass[b(i['az'])]+=i['n']
print('strand mass per 30deg bin (0=front, clockwise):',mass)
capP=np.array([v.co for v in {v for f in cf[0] for v in f.verts}])
capaz=np.arctan2(capP[:,0],-capP[:,1]); capr=np.hypot(capP[:,0],capP[:,1])
def cap_r(az):
    d=np.abs((capaz-az+np.pi)%(2*np.pi)-np.pi); m=d<0.35
    return float(np.percentile(capr[m],85)) if m.sum()>3 else 0.0
for k,i in inf.items():
    P=np.array([v.co for v in {v for f in cf[k] for v in f.verts}]); i['rmed']=float(np.median(np.hypot(P[:,0],P[:,1])))
donors=[k for k,i in inf.items() if 40<=i['n']<=150 and i['zmax']>cutz-0.12 and i['zmax']-i['zmin']>0.35 and i['rmax']<1.02]
print('donors',len(donors))
random.seed(21); added=0; nextid=max(cf)+1
pom_az=math.atan2(pcw.x,-pcw.y)
order=sorted(range(NB),key=lambda j:mass[j])
guard=0
while added<ADD_TRIS and donors and guard<400:
    guard+=1
    j=min(range(NB),key=lambda q:mass[q]); 
    if mass[j]>=TARGET_MASS: break
    az_t=math.radians((j+random.random())*360/NB)
    k=random.choice(donors); i=inf[k]
    rot=Matrix.Rotation((az_t-i['az']),4,'Z')          # azimuth measured from -Y towards +X
    sc_=RU(0.92,1.12); dz=RU(-0.06,0.03)
    push=max(0.0,cap_r(az_t)+0.05-i['rmed']*sc_)
    M_=Matrix.Translation((math.sin(az_t)*push,-math.cos(az_t)*push,dz))@Matrix.Translation(HCEN)@rot@Matrix.Diagonal((sc_,sc_,RU(0.95,1.2),1))@Matrix.Translation(-HCEN)
    vmap2={}
    for f in cf[k]:
        nf=hb.faces.new([vmap2.setdefault(v,hb.verts.new(M_@v.co)) for v in f.verts])
        nf[cid]=nextid; nf[tone]=f[tone]
        for l2,l1 in zip(nf.loops,f.loops): l2[huv].uv=l1[huv].uv
    nextid+=1; added+=i['n']; mass[j]+=i['n']
print('added tris',added,'mass now',mass)
hb.faces.ensure_lookup_table()
# ---- final UVs (tone columns), then light decimation of cap and strands
def to_obj(faces,name,ratio,with_uv):
    tmp=bmesh.new(); tu=tmp.loops.layers.uv.new('UVMap'); vm2={}
    for f in faces:
        nf=tmp.faces.new([vm2.setdefault(v,tmp.verts.new(v.co)) for v in f.verts])
        for l2,l1 in zip(nf.loops,f.loops):
            if with_uv:
                u,v=l1[huv].uv; un=min(max((u-0.09)/0.47,0),1); vn=min(max((v-0.08)/0.87,0),1)
                l2[tu].uv=(0.75+f[tone]*0.0833+0.004+un*0.0753,0.134+vn*0.862)
            else:
                cc=f.calc_center_median(); azc=math.atan2(cc.x,-cc.y) % (2*math.pi); cell=math.floor(azc*KC/(2*math.pi))
                co=l1.vert.co; az_=math.atan2(co.x,-co.y) % (2*math.pi)
                if az_-azc>math.pi: az_-=2*math.pi
                if azc-az_>math.pi: az_+=2*math.pi
                t_=min(max(az_*KC/(2*math.pi)-cell,0.0),1.0)
                vn=min(max((co.z-1.05)/1.30,0),1)
                l2[tu].uv=(0.75+0.004+t_*0.0753,0.134+vn*0.862)
    tm=bpy.data.meshes.new(name); tmp.to_mesh(tm); tmp.free(); to=bpy.data.objects.new(name,tm); sc.collection.objects.link(to)
    if ratio<0.999:
        md=to.modifiers.new('d','DECIMATE'); md.ratio=ratio; bpy.context.view_layer.objects.active=to; bpy.ops.object.modifier_apply(modifier='d')
    r=bmesh.new(); r.from_mesh(tm); bpy.data.objects.remove(to); return r
for faces,prt,ratio,wuv in (([f for f in hb.faces if f[cid]==0],6,CAPR,False),([f for f in hb.faces if f[cid]!=0],5,STR,True)):
    r=to_obj(faces,'t',ratio,wuv); ru=r.loops.layers.uv.active; vm3={}; r.normal_update()
    for f in r.faces:
        nf=bm.faces.new([vm3.setdefault(v,bm.verts.new(v.co)) for v in f.verts]); nf.smooth=True; nf[pl]=prt
        if prt==6:
            for v in f.verts:
                rad_=Vector((v.co.x,v.co.y-0.05,(v.co.z-1.75)*0.5)); 
                vm3[v][cnl]=(rad_.normalized()*0.65+v.normal*0.35).normalized()
        for l2,l1 in zip(nf.loops,f.loops): l2[uvl].uv=l1[ru].uv
    r.free()
hb.free()
bmesh.ops.delete(bm,geom=[f for f in bm.faces if f[pl]==4],context='FACES')
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
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
