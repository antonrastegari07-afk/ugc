# Ghost Jar UGC - geometry build (Blender bpy). Units = studs. Z up in Blender.
import bpy, bmesh, math, numpy as np, sys
from mathutils import Vector
OUT=sys.argv[-1]
SC=1.1  # overall scale -> ~1.2 stud tall
TEX=1024; PAD=8/TEX
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene

# ---------- atlas rects (u0,v0,u1,v1) ----------
R={
 'ghost':(0.0,0.5,0.5,1.0),
 'ghost_cap':(0.5,0.875,0.625,1.0),
 'sparkle':(0.625,0.875,0.75,1.0),
 'outer':(0.5,0.5,1.0,0.75),
 'outer_floor':(0.75,0.875,0.875,1.0),
 'inner':(0.5,0.25,1.0,0.5),
 'inner_floor':(0.875,0.875,1.0,1.0),
 'glow':(0.5,0.125,1.0,0.25),
 'smoke0':(0.0,0.25,0.25,0.5),'smoke1':(0.25,0.25,0.5,0.5),
 'smoke2':(0.0,0.0,0.25,0.25),'smoke3':(0.25,0.0,0.5,0.25),
 'cork':(0.5,0.0,0.75,0.125),
 'cork_top':(0.5,0.75,0.625,0.875),
 'outer_top':(0.5,0.5,1.0,0.625),'outer_base':(0.5,0.625,1.0,0.75),'puff':(0.875,0.75,1.0,0.875),
 'outline':(0.625,0.75,0.75,0.875),'outline_cap':(0.75,0.75,0.875,0.875),
 'band0':(0.75,0.0,1.0,0.0625),'band1':(0.75,0.0625,1.0,0.125),
}
PART_IDS={k:i for i,k in enumerate(['inner','glow','smoke0','smoke1','smoke2','smoke3','ghost','sparkle','cork','band0','band1','outer','outline','puff'])}
def rmap(rect,u,v):
    u0,v0,u1,v1=rect
    return (u0+PAD+(u1-u0-2*PAD)*u, v0+PAD+(v1-v0-2*PAD)*v)

def new_obj(name,coll):
    me=bpy.data.meshes.new(name); ob=bpy.data.objects.new(name,me); coll.objects.link(ob); return ob
def coll(name):
    c=bpy.data.collections.new(name); scene.collection.children.link(c); return c

def lathe(bm,uvl,profile,N,rect,invert=False,cap_rect=None,deform=None,theta0=-math.pi/2):
    """profile: list of (r,z). r==0 at ends -> pole fan. u wraps theta (front -Y at u=0.5)."""
    # cumulative length for v
    L=[0]
    for a,b in zip(profile[:-1],profile[1:]): L.append(L[-1]+math.hypot(b[0]-a[0],b[1]-a[1]))
    L=[x/L[-1] for x in L]
    rings=[]
    for i,(r,z) in enumerate(profile):
        ring=[]
        if r==0:
            ring=[bm.verts.new((0,0,z*SC))]
        else:
            for j in range(N):
                th=theta0+2*math.pi*j/N   # j=0 at back (+Y) seam, u=0.5 -> front (-Y)
                rr,zz=r,z
                if deform: rr,zz=deform(th,i,r,z)
                ring.append(bm.verts.new((rr*math.cos(th)*SC*-1, rr*math.sin(th)*SC*-1, zz*SC)))
        rings.append(ring)
    dz=profile[-1][1]-profile[0][1]
    up=(dz>0) if abs(dz)>1e-9 else (profile[1][1]>profile[0][1])
    flip=invert!=up
    def face(vs,uvs):
        if flip: vs=vs[::-1]; uvs=uvs[::-1]
        f=bm.faces.new(vs)
        for lp,uv in zip(f.loops,uvs): lp[uvl].uv=rmap(rect,*uv)
        f.smooth=True
    for i in range(len(rings)-1):
        A,B=rings[i],rings[i+1]; va,vb=1-L[i],1-L[i+1]
        for j in range(N):
            u0=j/N; u1=(j+1)/N; j1=(j+1)%N
            if len(A)==1:
                face([A[0],B[j],B[j1]],[((u0+u1)/2,va),(u0,vb),(u1,vb)])
            elif len(B)==1:
                face([A[j],B[0],A[j1]],[(u0,va),((u0+u1)/2,vb),(u1,va)])
            else:
                face([A[j],B[j],B[j1],A[j1]],[(u0,va),(u0,vb),(u1,vb),(u1,va)])
    return rings

def fan_cap(bm,uvl,ring,center,rect,down=True,invert=False):
    c=bm.verts.new(center)
    pts=[v.co for v in ring]; R_=max((Vector((p.x,p.y,0))-Vector((center[0],center[1],0))).length for p in pts)
    for j in range(len(ring)):
        a,b=ring[j],ring[(j+1)%len(ring)]
        vs=[c,a,b] if down else [c,b,a]
        if invert: vs=vs[::-1]
        f=bm.faces.new(vs)
        for lp in f.loops:
            p=lp.vert.co; lp[uvl].uv=rmap(rect,0.5+(p.x-center[0])/(2*R_),0.5+(p.y-center[1])/(2*R_))
        f.smooth=True

def disc_dome(bm,uvl,R0,zc,zedge,N,rings,rect,seed,amp):
    rng=np.random.default_rng(seed); ph=rng.uniform(0,6.28,4)
    center=bm.verts.new((0,0,zc*SC)); prev=None; allr=[]
    for k in range(1,rings+1):
        t=k/rings; ring=[]
        for j in range(N):
            th=2*math.pi*j/N
            w=amp*(math.sin(3*th+ph[0])+0.6*math.sin(5*th+ph[1])+0.4*math.sin(2*th+ph[2]))*math.sin(math.pi*t)
            z=zc+(zedge-zc)*t**2+w
            r=R0*t*(1+0.0*w)
            ring.append(bm.verts.new((r*math.cos(th)*SC,r*math.sin(th)*SC,z*SC)))
        allr.append(ring)
    def setuv(f):
        for lp in f.loops:
            p=lp.vert.co; lp[uvl].uv=rmap(rect,0.5+p.x/(2*R0*SC),0.5+p.y/(2*R0*SC))
        f.smooth=True
    for j in range(N):
        j1=(j+1)%N; setuv(bm.faces.new([center,allr[0][j],allr[0][j1]]))
    for k in range(rings-1):
        A,B=allr[k],allr[k+1]
        for j in range(N):
            j1=(j+1)%N; setuv(bm.faces.new([A[j],B[j],B[j1],A[j1]]))

def octa(bm,uvl,c,s,rect):
    P=[Vector(c)*SC+Vector(d)*s*SC for d in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1.6),(0,0,-1.6)]]
    V=[bm.verts.new(p) for p in P]
    for a,b in [(0,2),(2,1),(1,3),(3,0)]:
        for top,order in ((4,(a,b)),(5,(b,a))):
            f=bm.faces.new([V[order[0]],V[order[1]],V[top]])
            for lp,uv in zip(f.loops,[(0.1,0.1),(0.9,0.1),(0.5,0.9)]): lp[uvl].uv=rmap(rect,*uv)

def build(name,collection,fn):
    ob=new_obj(name,collection); bm=bmesh.new(); uvl=bm.loops.layers.uv.new('UVMap')
    fn(bm,uvl); bmesh.ops.triangulate(bm,faces=bm.faces[:]); bm.to_mesh(ob.data); bm.free(); return ob

# ---------- profiles ----------
OUTER=[(0,0.0),(0.30,0.0),(0.365,0.008),(0.388,0.04),(0.392,0.10),(0.392,0.40),(0.392,0.66),(0.386,0.72),
       (0.36,0.78),(0.30,0.835),(0.235,0.87),(0.200,0.895),(0.192,0.93),(0.194,0.965),(0.222,0.975),(0.228,0.995),(0.205,1.008)]
T=0.012
INNER=[(0,0.006),(0.32,0.006),(0.372,0.02),(0.383,0.07),(0.380,0.40),(0.380,0.65),(0.374,0.715),(0.348,0.77),(0.29,0.822),(0.226,0.858),(0.188,0.89),(0.180,0.93)]
GLOW=[(0.360,0.06),(0.364,0.16),(0.364,0.30),(0.364,0.42)]
CORK=[(0,1.085),(0.176,1.085),(0.188,1.075),(0.190,1.04),(0.182,0.99),(0.176,0.93),(0,0.93)]
GH=[(0,0.635),(0.06,0.627),(0.105,0.605),(0.138,0.57),(0.155,0.53),(0.158,0.49),(0.153,0.45),(0.145,0.41),(0.138,0.37),(0.133,0.33),(0.130,0.295),(0.128,0.265)]
GH_Z=0.0
def ghost_deform(th,i,r,z):
    # th: angle, -Y front at th=-pi/2 (after the -1 flip in lathe front is +? handled by theta0)
    x=-math.cos(th); y=-math.sin(th)
    rr=r; zz=z
    # arms on the sides (x = +-1)
    side=abs(x)
    arm=math.exp(-((math.atan2(abs(y),side))/0.45)**2)*math.exp(-((z-0.43)/0.05)**2)
    rr+=0.085*arm; zz-=0.02*arm
    # wavy hem
    if i==len(GH)-1:
        zz+=0.022*math.sin(5*th)
    elif i==len(GH)-2:
        zz+=0.008*math.sin(5*th)
    # slightly flattened front/back for chibi look
    rr*=1-0.06*abs(y)*(z>0.45)
    return rr,zz

C={n:coll(n) for n in ['Jar_Outer','Jar_Inner_Inverted','Ghost','Smoke_Layers','Glow_Dome_Inverted','Cork','Sparkles','Ghost_Outline_Inverted','GhostJar_UGC']}
parts=[]
parts.append(('inner',build('Jar_Inner_Inverted',C['Jar_Inner_Inverted'],lambda bm,uvl:(lathe(bm,uvl,INNER,28,R['inner'],invert=True)))))
parts.append(('smoke0',build('Smoke_Mound',C['Smoke_Layers'],lambda bm,uvl:disc_dome(bm,uvl,0.373,0.185,0.15,24,4,R['smoke0'],1,0.028))))
def puff_fn(bm,uvl):
    rng=np.random.default_rng(3)
    for k in range(7):
        a=2*math.pi*k/7+rng.uniform(-0.3,0.3); rr=rng.uniform(0.17,0.27)
        cx,cy=rr*math.cos(a),rr*math.sin(a); rad=rng.uniform(0.07,0.10); cz=0.165+rng.uniform(0,0.03)
        ring=[]
        for i in range(1,4):
            ph=math.pi*i/4; row=[]
            for j in range(8):
                th=2*math.pi*j/8
                row.append(bm.verts.new(((cx+rad*math.sin(ph)*math.cos(th))*SC,(cy+rad*math.sin(ph)*math.sin(th))*SC,(cz+0.6*rad*math.cos(ph))*SC)))
            ring.append(row)
        top=bm.verts.new((cx*SC,cy*SC,(cz+0.6*rad)*SC)); bot=bm.verts.new((cx*SC,cy*SC,(cz-0.6*rad)*SC))
        def F(vs):
            f=bm.faces.new(vs); f.smooth=True
            for lp in f.loops:
                p=lp.vert.co; lp[uvl].uv=rmap(R['puff'],0.5+(p.x/SC-cx)/(2.2*rad),0.5+(p.y/SC-cy)/(2.2*rad))
        for j in range(8):
            j1=(j+1)%8
            F([top,ring[0][j],ring[0][j1]])
            for i in range(2): F([ring[i][j],ring[i+1][j],ring[i+1][j1],ring[i][j1]])
            F([bot,ring[2][j1],ring[2][j]])
parts.append(('puff',build('Smoke_Puffs',C['Smoke_Layers'],puff_fn)))
OFF=0.012
GH_OUT=[(0,GH[0][1]+OFF)]+[(r+OFF,z+OFF*0.5) for r,z in GH[1:-1]]+[(GH[-1][0]+OFF,GH[-1][1]-OFF)]
def outline_fn(bm,uvl):
    rings=lathe(bm,uvl,GH_OUT,30,R['outline'],invert=True,deform=ghost_deform)
    fan_cap(bm,uvl,rings[-1],(0,0,(0.29-OFF)*SC),R['outline_cap'],down=True,invert=True)
parts.append(('outline',build('Ghost_Outline',C['Ghost_Outline_Inverted'],outline_fn)))
def ghost_fn(bm,uvl):
    rings=lathe(bm,uvl,GH,30,R['ghost'],deform=ghost_deform)
    fan_cap(bm,uvl,rings[-1],(0,0,0.29*SC),R['ghost_cap'],down=True)
parts.append(('ghost',build('Ghost',C['Ghost'],ghost_fn)))
def spark_fn(bm,uvl):
    rng=np.random.default_rng(7)
    pts=[(0.22,-0.12,0.55),(-0.24,-0.05,0.62),(0.17,0.2,0.68),(-0.15,0.22,0.36),(0.27,0.1,0.33),(-0.28,-0.16,0.30),(0.05,-0.27,0.70),(-0.05,0.28,0.52)]
    for p in pts: octa(bm,uvl,p,rng.uniform(0.016,0.024),R['sparkle'])
parts.append(('sparkle',build('Sparkles',C['Sparkles'],spark_fn)))
def cork_fn(bm,uvl):
    lathe(bm,uvl,CORK,24,R['cork'])
parts.append(('cork',build('Cork',C['Cork'],cork_fn)))
def band(z0,z1,r_in,r_out,rect):
    prof=[(r_in,z0),(r_out,z0+0.008),(r_out,z1-0.008),(r_in,z1),(r_in,z0)]
    return lambda bm,uvl: lathe(bm,uvl,prof,24,rect)
OUTER_TOP=[(0.205,1.008),(0.228,0.995),(0.222,0.975),(0.194,0.965),(0.192,0.93),(0.200,0.895),(0.235,0.87),(0.30,0.835),(0.36,0.78),(0.386,0.725),(0.392,0.70),(0.362,0.70)]
OUTER_BASE=[(0.376,0.10),(0.392,0.10),(0.390,0.04),(0.365,0.008),(0.30,0.0),(0,0.0)]
OUTER_FLOOR=[(0.385,0.0),(0.2,0.0),(0,0.0)]
parts.append(('outer',build('Jar_Outer_Floor',C['Jar_Outer'],lambda bm,uvl:lathe(bm,uvl,OUTER_FLOOR,28,R['outer_base']))))

# ---------- final fused mesh, in draw order (back -> front) ----------
fin=new_obj('GhostJar_UGC',C['GhostJar_UGC']); bm=bmesh.new()
pid=[]
for key,ob in parts:
    n0=len(bm.faces); bm.from_mesh(ob.data); bm.faces.ensure_lookup_table()
    pid+= [PART_IDS[key]]*(len(bm.faces)-n0)
bm.to_mesh(fin.data); bm.free()
me=fin.data
# orientation report per part: mean dot(normal, radial-ish) to check winding
import collections
P=np.array([v.co[:] for v in me.vertices])
tri=np.array([[l for l in p.vertices] for p in me.polygons])
fn_=np.array([p.normal[:] for p in me.polygons]); fc=np.array([p.center[:] for p in me.polygons])
pid=np.array(pid)
inv={v:k for k,v in PART_IDS.items()}
for k in sorted(set(pid)):
    m=pid==k; rad=fc[m].copy(); rad[:,2]=0
    print(inv[k], m.sum(), 'up=%.2f'%np.mean(np.sign(fn_[m][:,2])), 'tris  outward=%.2f'%np.mean(np.sign((fn_[m]*rad).sum(1)+1e-9)))
print('TOTAL TRIS',len(me.polygons))
uv=np.zeros((len(me.polygons),3,2))
for p in me.polygons:
    for c,li in enumerate(p.loop_indices): uv[p.index,c]=me.uv_layers[0].data[li].uv[:]
me.calc_normals_split() if hasattr(me,'calc_normals_split') else None
ln=np.array([me.corner_normals[li].vector[:] for p in me.polygons for li in p.loop_indices]).reshape(-1,3,3)
np.savez(OUT+'/geo.npz',P=P[tri],UV=uv,N=ln,pid=pid)
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/GhostJar_geo.blend')
