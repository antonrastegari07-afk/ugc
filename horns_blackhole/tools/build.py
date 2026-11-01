import bpy, bmesh, math, sys, numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
D=sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=D+'/in/horns.fbx')
src=[x for x in bpy.data.objects if x.type=='MESH'][0]
sc=bpy.context.scene
PARTS=['horn','hole','disk_top','disk_bot','disk_edge','halo']
SCALE=1.55; SHIFT=0.25; DZ=1.88
# ---------- horns: clean debris, decimate, measure thickness, place on the head ----------
bm=bmesh.new(); bm.from_mesh(src.data); bm.verts.ensure_lookup_table()
seen=set(); comps=[]
for v in bm.verts:
    if v in seen: continue
    st=[v]; c=[]
    while st:
        a=st.pop()
        if a in seen: continue
        seen.add(a); c.append(a); st.extend(e.other_vert(a) for e in a.link_edges)
    comps.append(c)
junk=[v for c in comps if len(c)<50 for v in c]
bmesh.ops.delete(bm,geom=junk,context='VERTS')
bm.to_mesh(src.data); bm.free()
mod=src.modifiers.new('dec','DECIMATE'); mod.ratio=0.86; mod.use_collapse_triangulate=True
bpy.context.view_layer.objects.active=src; bpy.ops.object.modifier_apply(modifier='dec')
hm=src.data
bm=bmesh.new(); bm.from_mesh(hm); bmesh.ops.triangulate(bm,faces=bm.faces[:]); bm.normal_update()
tree=BVHTree.FromBMesh(bm)
thick={}
for v in bm.verts:
    n=v.normal
    hit=tree.ray_cast(v.co-n*1e-4,-n,0.5)
    thick[v]=hit[3] if hit[0] is not None else 0.02
uvl=bm.loops.layers.uv['UVMap']; a1=bm.loops.layers.uv.new('Aux1'); a2=bm.loops.layers.uv.new('Aux2'); pl=bm.faces.layers.int.new('part')
for f in bm.faces:
    f[pl]=0
    for lp in f.loops:
        u,v=lp[uvl].uv; lp[uvl].uv=(u*0.8,0.2+v*0.8)
        co=lp.vert.co; lp[a1].uv=(thick[lp.vert],0); lp[a2].uv=(abs(co.x),co.z)      # local (pre-placement) coords
for v in bm.verts:
    side=1 if v.co.x>0 else -1
    v.co=Vector((v.co.x*SCALE+side*SHIFT, v.co.y*SCALE, v.co.z*SCALE+DZ))
# ---------- black hole (Gargantua style) ----------
BH=Vector((0,0.0,2.2+0.62)); TILT=Matrix.Rotation(math.radians(12),3,'X')@Matrix.Rotation(math.radians(-8),3,'Y')
def rect(r,u,v): return (r[0]+(r[2]-r[0])*u, r[1]+(r[3]-r[1])*v)
def addf(vs,uvs,part,aux=None,flip=False):
    if flip: vs=vs[::-1]; uvs=uvs[::-1]; aux=aux[::-1] if aux else None
    f=bm.faces.new(vs); f[pl]=PARTS.index(part)
    for i,lp in enumerate(f.loops):
        lp[uvl].uv=uvs[i]; lp[a1].uv=(aux[i] if aux else (0,0)); lp[a2].uv=(0,0)
    return f
def P(x,y,z): return BH+TILT@Vector((x,y,z))
def uvsphere(radius,ns,nr,rct,part,inward):
    sv=[[bm.verts.new(P(radius*math.sin(math.pi*i/nr)*math.cos(2*math.pi*j/ns),radius*math.sin(math.pi*i/nr)*math.sin(2*math.pi*j/ns),radius*math.cos(math.pi*i/nr))) for j in range(ns)] for i in range(nr+1)]
    for i in range(nr):
        for j in range(ns):
            j1=(j+1)%ns
            uv=[rect(rct,j/ns,1-i/nr),rect(rct,(j+1)/ns,1-i/nr),rect(rct,(j+1)/ns,1-(i+1)/nr),rect(rct,j/ns,1-(i+1)/nr)]
            ax=[(j/ns,i/nr),((j+1)/ns,i/nr),((j+1)/ns,(i+1)/nr),(j/ns,(i+1)/nr)]
            if i==0: vs,u_,x_=[sv[0][j],sv[1][j1],sv[1][j]],[uv[0],uv[2],uv[3]],[ax[0],ax[2],ax[3]]
            elif i==nr-1: vs,u_,x_=[sv[i][j],sv[i][j1],sv[i+1][j]],[uv[0],uv[1],uv[3]],[ax[0],ax[1],ax[3]]
            else: vs,u_,x_=[sv[i][j],sv[i][j1],sv[i+1][j1],sv[i+1][j]],uv,ax
            addf(vs,u_,part,x_,flip=not inward)
RH,RS=0.11,0.19
uvsphere(RH,14,8,(0.8,0.8,1.0,1.0),'hole',inward=False)          # event horizon: solid ball, as black as possible
uvsphere(RS,16,10,(0.0,0.0,0.8,0.2),'halo',inward=True)          # lensing shell: inverted, only its far inner wall shows behind the ball
# accretion disk
R0,R1,TH=0.15,0.48,0.008; ND=40; RADS=[R0,0.25,R1]
def ring(r,z): return [bm.verts.new(P(r*math.cos(2*math.pi*j/ND),r*math.sin(2*math.pi*j/ND),z)) for j in range(ND)]
top=[ring(r,TH/2) for r in RADS]; bot=[ring(r,-TH/2) for r in RADS]
RT,RB,RE=(0.8,0.6,1.0,0.8),(0.8,0.4,1.0,0.6),(0.8,0.2,1.0,0.4)
def pol(rr,r,j): a=2*math.pi*j/ND; return rect(rr,0.5+0.5*r/R1*math.cos(a),0.5+0.5*r/R1*math.sin(a))
for k in range(len(RADS)-1):
    for j in range(ND):
        j1=(j+1)%ND; r0,r1=RADS[k],RADS[k+1]
        aux=[((r0-R0)/(R1-R0),j/ND),((r0-R0)/(R1-R0),(j+1)/ND),((r1-R0)/(R1-R0),(j+1)/ND),((r1-R0)/(R1-R0),j/ND)]
        addf([top[k][j],top[k][j1],top[k+1][j1],top[k+1][j]],[pol(RT,r0,j),pol(RT,r0,j+1),pol(RT,r1,j+1),pol(RT,r1,j)],'disk_top',aux,flip=True)
        addf([bot[k][j],bot[k][j1],bot[k+1][j1],bot[k+1][j]],[pol(RB,r0,j),pol(RB,r0,j+1),pol(RB,r1,j+1),pol(RB,r1,j)],'disk_bot',aux)
for (A,B,lo) in ((top[0],bot[0],0.0),(top[-1],bot[-1],0.5)):
    for j in range(ND):
        j1=(j+1)%ND
        uvs=[rect(RE,j/ND,lo),rect(RE,(j+1)/ND,lo),rect(RE,(j+1)/ND,lo+0.5),rect(RE,j/ND,lo+0.5)]
        addf([A[j],A[j1],B[j1],B[j]],uvs,'disk_edge',[(0 if lo==0 else 1,j/ND)]*4,flip=(lo==0.5))
bmesh.ops.triangulate(bm,faces=bm.faces[:])
me=bpy.data.meshes.new('HornsBlackHole_UGC'); bm.to_mesh(me); bm.free()
ob=bpy.data.objects.new('HornsBlackHole_UGC',me); sc.collection.objects.link(ob)
bpy.data.objects.remove(src)
for p in me.polygons: p.use_smooth=True
P_=np.array([v.co[:] for v in me.vertices]); tri=np.array([list(p.vertices) for p in me.polygons])
g=lambda nm: np.array([[me.uv_layers[nm].data[l].uv[:] for l in p.loop_indices] for p in me.polygons])
part=np.array([a.value for a in me.attributes['part'].data])
ln=np.array([me.corner_normals[l].vector[:] for p in me.polygons for l in p.loop_indices]).reshape(-1,3,3)
np.savez(D+'/geo.npz',P=P_[tri],UV=g('UVMap'),A1=g('Aux1'),A2=g('Aux2'),N=ln,part=part,parts=np.array(PARTS),bh=np.array(BH[:]),tilt=np.array(TILT))
me.uv_layers.remove(me.uv_layers['Aux1']); me.uv_layers.remove(me.uv_layers['Aux2'])
fn=np.cross(P_[tri][:,1]-P_[tri][:,0],P_[tri][:,2]-P_[tri][:,0])
for k,nm in enumerate(PARTS):
    m=part==k; t=P_[tri[m]]
    print('%-9s tris %4d vol %+.5f'%(nm,m.sum(),(np.einsum('ij,ij->i',t[:,0],np.cross(t[:,1],t[:,2]))).sum()/6))
print('TOTAL TRIS',len(me.polygons),'BBOX',P_.min(0).round(3),P_.max(0).round(3))
bpy.ops.wm.save_as_mainfile(filepath=D+'/HBH_geo.blend')
