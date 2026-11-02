import bpy, bmesh, math, sys, numpy as np
from mathutils import Vector, Matrix
D=sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True); sc=bpy.context.scene
R0=0.40; T=0.035; HB=0.11; NPT=8; NA=80
HBASE=0.05      # socle (base band) height
def top(th):
    # 8 points alternating tall/short, concave flanks and tips leaning sideways (swirl/flame look)
    k=(th/(2*math.pi))*NPT; f=k-math.floor(k); i=int(math.floor(k))%NPT
    H=0.24
    p=0.62
    d=(p-f)/p if f<p else (f-p)/(1-p)
    return HB+H*(1-d)**1.9
bm=bmesh.new(); uvl=bm.loops.layers.uv.new('UVMap'); pl=bm.faces.layers.int.new('part')
GOLD=(0,0.25,1,1); GEM=(0,0,0.25,0.25); OUT=(0.5,0.0,0.6,0.1)
def rect(r,u,v): return (r[0]+(r[2]-r[0])*u, r[1]+(r[3]-r[1])*v)
def face(vs,uvs,part,rr):
    f=bm.faces.new(vs); f[pl]=part; f.smooth=True
    for lp,uv in zip(f.loops,uvs): lp[uvl].uv=rect(rr,*uv)
    return f
NZ=2
cols=[]
for j in range(NA):
    th=2*math.pi*j/NA; c,s=math.cos(th),math.sin(th); ht=top(th)
    zs=[0.0,HBASE,HBASE+0.0001]+[HBASE+0.0001+(ht-HBASE-0.0001)*k/NZ for k in range(1,NZ+1)]
    outer=[]; inner=[]
    for z in zs:
        flare=0.05*max(z-HBASE,0)+0.25*max(z-HBASE-0.18,0)**2*4                      # walls open slightly outward
        socle=0.022 if z<=HBASE+1e-6 else 0.0           # thick base band
        ro=R0+flare+socle; ri=R0-T+flare
        outer.append(bm.verts.new((ro*s,-ro*c,z))); inner.append(bm.verts.new((ri*s,-ri*c,z)))
    cols.append((outer,inner,ht))
for j in range(NA):
    j1=(j+1)%NA; (O0,I0,h0),(O1,I1,h1)=cols[j],cols[j1]; u0,u1=j/NA,(j+1)/NA
    NZZ=len(zs)-1
    for k in range(NZZ):
        v0,v1=zs[k]/0.5,zs[k+1]/0.5
        face([O0[k],O1[k],O1[k+1],O0[k+1]],[(u0,v0*0.5+0.5*0),(u1,v0*0.5),(u1,v1*0.5),(u0,v1*0.5)],0,GOLD)       # outer (lower half of gold rect)
        face([I0[k+1],I1[k+1],I1[k],I0[k]],[(u0,0.5+v1*0.4),(u1,0.5+v1*0.4),(u1,0.5+v0*0.4),(u0,0.5+v0*0.4)],1,GOLD)   # inner
    face([O0[-1],O1[-1],I1[-1],I0[-1]],[(u0,0.95),(u1,0.95),(u1,0.98),(u0,0.98)],2,GOLD)   # top edge
    face([I0[0],I1[0],O1[0],O0[0]],[(u0,0.91),(u1,0.91),(u1,0.93),(u0,0.93)],2,GOLD)        # bottom edge
bmesh.ops.triangulate(bm,faces=bm.faces[:]); bmesh.ops.recalc_face_normals(bm,faces=bm.faces[:]); bm.normal_update()
# ---- inverted-hull outline: copy pushed along vertex normals, faces reversed
OFF=0.03
src=list(bm.faces); vm={}
for v in {v for f in src for v in f.verts}: vm[v]=bm.verts.new(v.co+v.normal*OFF)
for f in src:
    nf=bm.faces.new([vm[v] for v in f.verts][::-1]); nf[pl]=4; nf.smooth=True
    for lp in nf.loops: lp[uvl].uv=rect(OUT,0.5,0.5)
# ---- float + tilt above the head (head top at z=2.2)
M=Matrix.Translation((0.06,0.0,2.2+0.18))@Matrix.Rotation(math.radians(14),4,'Y')@Matrix.Rotation(math.radians(8),4,'X')
bmesh.ops.transform(bm,matrix=M,verts=bm.verts[:])
me=bpy.data.meshes.new('ToonCrown_UGC'); bm.to_mesh(me); bm.free()
ob=bpy.data.objects.new('ToonCrown_UGC',me); sc.collection.objects.link(ob)
part=np.array([a.value for a in me.attributes['part'].data])
print('TRIS',len(me.polygons),'outline',(part==4).sum(),'dims',[round(v,3) for v in ob.dimensions])
bpy.ops.wm.save_as_mainfile(filepath=D+'/geo.blend')
