# Horns v4: vertical-slice lenticular horns + sliced halo ring (outlined) + fixed outlined crystal spikes
import sys,os; sys.path.insert(0,'tools')
from fbxio import read,write,child
import numpy as np; from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates
from skimage.measure import find_contours
from shapely.geometry import Polygon
import mapbox_earcut as earcut
SRC='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/807479b3-HornsBlackHole_UGC.fbx'
OUT=sys.argv[1]; BUDGET=3990
# ---------------- volumes
Z=np.load('field.npz'); _W=gaussian_filter(Z['W'],0.9); _lo=Z['lo']; _R=float(Z['R'])
_P=_lo+np.argwhere(_W>0.5)*_R; _Q=_P[_P[:,0]>0]; _pts=[]
for z in np.arange(_Q[:,2].min()+0.02,_Q[:,2].max(),0.03):
    q=_Q[np.abs(_Q[:,2]-z)<0.012]
    if len(q)>2: _pts.append([np.median(q[:,0]),0.0,z])
_pts=np.array(_pts); _pts=np.vstack([_pts,[_pts[-1]+(_pts[-1]-_pts[-3])*0.6]])
from scipy.ndimage import uniform_filter1d
_pts[:,0]=uniform_filter1d(_pts[:,0],5,mode='nearest')
seg=np.r_[0,np.cumsum(np.linalg.norm(np.diff(_pts,axis=0),axis=1))]; sN=np.linspace(0,seg[-1],600)
CL=np.c_[[np.interp(sN,seg,_pts[:,i]) for i in range(3)]].T; CS=sN/seg[-1]   # centreline + param 0 base ->1 tip
from scipy.ndimage import binary_opening
_B=Z['W']>0.5
rr=3; zz,yy,xx=np.mgrid[-rr:rr+1,-rr:rr+1,-rr:rr+1]; ball=(xx**2+yy**2+zz**2)<=rr*rr
_open=gaussian_filter(binary_opening(_B,structure=ball).astype(float),1.5)   # spikes removed, body kept
_soft=gaussian_filter(Z['W'],0.9)
zc=_lo[2]+np.arange(_B.shape[2])*_R; wz=np.clip((zc-0.42)/0.12,0,1)[None,None,:]   # 0 at base -> 1 higher up
b2=(lambda r: (np.mgrid[-r:r+1,-r:r+1,-r:r+1]**2).sum(0)<=r*r)(2)
_open2=gaussian_filter(binary_opening(_B,structure=b2).astype(float),1.2)
w2=np.clip((zc-0.30)/0.12,0,1)[None,None,:]; wt=np.clip((zc-0.56)/0.06,0,1)[None,None,:]
HW=_open*(1-w2)+_open2*w2; HW=HW*(1-wt)+_soft*wt; HLO=_lo; HR=_R
# ---- rebuild the lower part as a smooth tube (removes the bump at the base), blended into the horn
from scipy.spatial import cKDTree
from scipy.ndimage import uniform_filter1d as _uf
rs=[]
for j in range(len(CL)):
    c=CL[j]; t=CL[min(j+10,len(CL)-1)]-CL[max(j-10,0)]; t/=np.linalg.norm(t)
    q=_P[(_P[:,0]>0)&(np.abs((_P-c)@t)<0.012)]; q=q[np.linalg.norm(q-c,axis=1)<0.25]
    d=np.linalg.norm((q-c)-np.outer((q-c)@t,t),axis=1); rs.append(np.percentile(d,55) if len(d)>5 else 0.0)
rs=_uf(np.array(rs),61,mode='nearest')
_G=np.stack(np.meshgrid(*[_lo[i]+np.arange(_B.shape[i])*_R for i in range(3)],indexing='ij'),-1).reshape(-1,3)
TB=np.zeros(len(_G))
for sgn in (1,-1):
    Cs=CL*[sgn,1,1]; d,i=cKDTree(Cs).query(_G,k=1)
    f=np.clip(0.5-(d-rs[i])/(2*_R),0,1); t0=Cs[6]-Cs[0]; t0/=np.linalg.norm(t0); f[(_G-Cs[0])@t0<0]=0
    TB=np.maximum(TB,f)
TB=gaussian_filter(TB.reshape(_B.shape),0.8)
wb=np.clip((zc-(-0.22))/0.2,0,1)[None,None,:]          # 0 = base (tube), 1 = higher (original shape)
HW=TB*(1-wb)+HW*wb
def horn_radius(c,t):
    P=_P[np.abs((_P-c)@t)<0.012]; P=P[np.linalg.norm(P-c,axis=1)<0.2]
    d=np.linalg.norm((P-c)-np.outer((P-c)@t,t),axis=1)
    return np.percentile(d,92) if len(d) else 0.05
RC=np.array([0,0,0.458]); RN=np.array([0.0,0.0,1.0])   # halo perfectly horizontal; RN/=np.linalg.norm(RN)
RING_R,RING_r=0.30,0.042
def ring_field():
    R=0.008; lo=RC-0.40; n=int(0.80/R)+1; ax=[lo[i]+np.arange(n)*R for i in range(3)]
    P=np.stack(np.meshgrid(*ax,indexing='ij'),-1)-RC
    h=P@RN; rad=np.linalg.norm(P-h[...,None]*RN,axis=-1)
    d=np.sqrt((rad-RING_R)**2+h**2)-RING_r
    return np.clip(0.5-d/(2*R),0,1),lo,R
RW,RLO,RR=ring_field()
VOLS=[(HW,HLO,HR),(RW,RLO,RR)]
def section(W,lo,R,ax,c,r2=0.004):
    hi=lo+(np.array(W.shape)-1)*R; o=[i for i in range(3) if i!=ax]
    if not (lo[ax]<=c<=hi[ax]): return None
    u=np.arange(lo[o[0]],hi[o[0]],r2); v=np.arange(lo[o[1]],hi[o[1]],r2); U,Vv=np.meshgrid(u,v,indexing='ij')
    co=np.zeros((3,)+U.shape); co[ax]=(c-lo[ax])/R; co[o[0]]=(U-lo[o[0]])/R; co[o[1]]=(Vv-lo[o[1]])/R
    S=np.pad(map_coordinates(W,co.reshape(3,-1),order=1).reshape(U.shape),1); geo=None
    for cont in find_contours(S,0.5):
        if len(cont)<4: continue
        p=Polygon(np.c_[lo[o[0]]+(cont[:,0]-1)*r2, lo[o[1]]+(cont[:,1]-1)*r2]).buffer(0)
        if not p.is_empty: geo=p if geo is None else geo.symmetric_difference(p)
    return geo
def slices(s,tol):
    out=[]
    glo=np.minimum(HLO,RLO)
    for vi,(W,lo,R) in enumerate(VOLS):
        hi=lo+(np.array(W.shape)-1)*R
        for ax in (0,1):                       # vertical planes only
            first=glo[ax]+s*0.5+np.ceil((lo[ax]-glo[ax]-s*0.5)/s)*s   # shared global lattice
            for c in np.arange(first,hi[ax],s):
                G=section(W,lo,R,ax,c)
                if G is None or G.is_empty: continue
                G=G.simplify(tol,preserve_topology=True)
                for P in ([G] if G.geom_type=='Polygon' else [p for p in getattr(G,'geoms',[]) if p.geom_type=='Polygon']):
                    if P.is_empty or P.area<(tol*3)**2: continue
                    rings=[np.array(P.exterior.coords)[:-1]]+[np.array(r.coords)[:-1] for r in P.interiors]
                    vt=np.vstack(rings); ends=np.cumsum([len(r) for r in rings]).astype(np.uint32)
                    idx=np.array(earcut.triangulate_float64(vt,ends)).reshape(-1,3)
                    if len(idx): out.append((vi,ax,c,vt,idx))
    return out
# ---------------- mesh accumulator
VV=[];FF=[];UU=[];NN=[]   # per-triangle: 3 verts, 3 uvs, 1 normal
def add_tris(T,UVt):     # T (n,3,3) world, UVt (n,3,2)
    n=np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0]); n/=np.linalg.norm(n,axis=1)[:,None]+1e-12
    VV.append(T); UU.append(UVt); NN.append(n)
# texture layout (pixels): 4 direction swatches + solid blocks
SW=[(6+(d%2)*510, 6+(d//2)*390, 500, 380) for d in range(4)]   # d: 0 +X,1 -X,2 +Y,3 -Y
BLK={'spike':(20,800,180,200),'spike_ol':(220,800,180,200),'ring_ol':(420,800,180,200)}
def blk_uv(name,n):
    x,y,w,h=BLK[name]; c=np.array([(x+w/2)/1024,1-(y+h/2)/1024]); d=np.array([[-.01,-.01],[.01,-.01],[0,.01]])
    return np.broadcast_to(c+d,(n,3,2)).copy()
# ---------------- fins: bracelet around the horn + vertical arrow blade (fixed colour, outlined, matte)
from shapely.geometry import Polygon as SP
def cap(poly2d,origin,ea,eb,nrm,off):
    rings=[np.array(poly2d.exterior.coords)[:-1]]+[np.array(r.coords)[:-1] for r in poly2d.interiors]
    vt=np.vstack(rings); ends=np.cumsum([len(r) for r in rings]).astype(np.uint32)
    ii=np.array(earcut.triangulate_float64(vt,ends)).reshape(-1,3)
    T=(origin+nrm*off+vt[:,:1]*ea+vt[:,1:]*eb)[ii]
    cr=np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0])@nrm; T[cr<0]=T[cr<0][:,[0,2,1]]; return T
def band(c,t,u,v,r,h,nseg=10,outward=True):
    T=[]
    for i in range(nseg):
        a0,a1=2*np.pi*i/nseg,2*np.pi*(i+1)/nseg
        p=lambda a,s_: c+(u*np.cos(a)+v*np.sin(a))*r+t*s_*h/2
        q=[p(a0,-1),p(a1,-1),p(a1,1),p(a0,1)]; T+=[[q[0],q[1],q[2]],[q[0],q[2],q[3]]]
    T=np.array(T); n_=np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0]); out=np.einsum('ij,ij->i',n_,T.mean(1)-c)>0
    flip=out!=outward; T[flip]=T[flip][:,[0,2,1]]; return T
# ---------------- horn outline: inverted hull of the horn volume (black, matte)
from scipy.ndimage import distance_transform_edt
from skimage.measure import marching_cubes
import fast_simplification
inside=HW>0.5
dist=distance_transform_edt(~inside)*HR - distance_transform_edt(inside)*HR
OFF=0.016
vv,ff,_,_=marching_cubes(np.pad(dist,2,constant_values=1.0),level=OFF)
vv=HLO+(vv-2)*HR
vv,ff=fast_simplification.simplify(vv.astype(np.float32),ff.astype(np.int32),target_reduction=1-700/len(ff))
vv=vv.astype(float); T=vv[ff]
# make outward then flip -> inverted hull
n=np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0]); vol=np.einsum('ij,ij->i',T[:,0],n).sum()
if vol<0: T=T[:,[0,2,1]]
T=T[:,[0,2,1]]
NOOL=os.environ.get('NOOL')=='1'
if not NOOL: add_tris(T,blk_uv('ring_ol',len(T)))
nfin=0 if NOOL else len(T)
print('horn outline tris',nfin)
# ---------------- ring outline (inverted hull torus)
e1=np.cross(RN,[1,0,0]); e1/=np.linalg.norm(e1); e2=np.cross(RN,e1)
NU,NV=22,6; ro=RING_r+0.013
def tp(i,j):
    a=2*np.pi*i/NU; b=2*np.pi*j/NV; rad=RING_R+ro*np.cos(b)
    return RC+(e1*np.cos(a)+e2*np.sin(a))*rad+RN*ro*np.sin(b)
RT=[]
for i in range(NU):
    for j in range(NV):
        p00,p10,p11,p01=tp(i,j),tp(i+1,j),tp(i+1,j+1),tp(i,j+1); RT+=[[p00,p10,p11],[p00,p11,p01]]
RT=np.array(RT); n=np.cross(RT[:,1]-RT[:,0],RT[:,2]-RT[:,0])
cen=RC+ (e1*np.cos(0)) *0  # orient outward then flip -> inward-facing shell
# outward test: compare with vector from ring core circle
core=lambda p: RC+((p-RC)-((p-RC)@RN)*RN)/np.linalg.norm((p-RC)-((p-RC)@RN)*RN)*RING_R
out=np.array([n[i]@(RT[i].mean(0)-core(RT[i].mean(0))) for i in range(len(RT))])>0
RT[~out]=RT[~out][:,[0,2,1]]; RT=RT[:,[0,2,1]]     # flip -> inverted hull
add_tris(RT,blk_uv('ring_ol',len(RT)))
fixed=sum(len(x) for x in VV); budget=(BUDGET-fixed)//2
print('fixed tris (spikes+outlines)',fixed,'| slice budget per side',budget)
# ---------------- fit slice spacing to budget
s=0.035;best=None
for it in range(10):
    sl=slices(s,s*0.1); n=sum(len(x[4]) for x in sl); print(f'spacing {s:.4f} -> {n}',flush=True)
    if n<=budget: best=(s,sl)
    if budget*0.95<=n<=budget: break
    s*=(n/budget)**0.6
s,sl=best
for vi,ax,c,vt,idx in sl:
    W,lo,R=VOLS[vi]; hi=lo+(np.array(W.shape)-1)*R; o=[i for i in range(3) if i!=ax]
    P3=np.zeros((len(vt),3)); P3[:,ax]=c; P3[:,o[0]]=vt[:,0]; P3[:,o[1]]=vt[:,1]
    nvec=np.zeros(3); nvec[ax]=1; T=P3[idx]
    cr=np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0])@nvec; idx=np.where(cr[:,None]>0,idx,idx[:,[0,2,1]])
    q=(vt-lo[o])/(hi[o]-lo[o])
    for side in (0,1):
        x,y,w,h=SW[2*ax+side]; qq=q.copy()
        if side: qq[:,0]=1-qq[:,0]
        uv=np.c_[(x+8+qq[:,0]*(w-16))/1024, 1-(y+8+(1-qq[:,1])*(h-16))/1024]
        ii=idx if side==0 else idx[:,[0,2,1]]
        add_tris(P3[ii],uv[ii])
T=np.vstack(VV); UVt=np.vstack(UU); N=np.vstack(NN)
print('FINAL spacing',round(s,4),'TOTAL TRIS',len(T))
SCALE=1.2/(T.reshape(-1,3)[:,0].max()-T.reshape(-1,3)[:,0].min()); T=T*SCALE; print('scale',round(SCALE,4),'size X,Y,Z (Blender)',(T.reshape(-1,3).max(0)-T.reshape(-1,3).min(0)).round(3))
# weld vertices
P=T.reshape(-1,3); key=np.round(P,6); uniq,inv=np.unique(key,axis=0,return_inverse=True)
np.savez('mesh10_nool.npz' if NOOL else 'mesh10.npz',V=uniq,F=inv.reshape(-1,3),UV=UVt.reshape(-1,2),N=N,SW=np.array(SW))
import json; json.dump(BLK,open('blk.json','w'))
