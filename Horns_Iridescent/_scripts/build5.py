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
Z=np.load('field.npz'); HW=gaussian_filter(Z['W'],0.9); HLO=Z['lo']; HR=float(Z['R'])
RC=np.array([0,0,0.458]); RN=np.array([0.139,0.206,-0.969]); RN/=np.linalg.norm(RN)
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
# ---------------- crystal spikes (fixed colour) + inverted-hull outline
def shard(base,d,L,wv,wy):
    d=d/np.linalg.norm(d); side=np.cross(d,[0,1,0]); side/=np.linalg.norm(side); yax=np.array([0,1.0,0])
    ring0=[base+side*wv*0.55,base+yax*wy*0.55,base-side*wv*0.55,base-yax*wy*0.55]
    m=base+d*L*0.38; ring1=[m+side*wv,m+yax*wy,m-side*wv,m-yax*wy]; tip=base+d*L+side*wv*0.25
    T=[]
    for i in range(4):
        j=(i+1)%4; T+= [[ring0[i],ring1[i],ring1[j]],[ring0[i],ring1[j],ring0[j]],[ring1[i],tip,ring1[j]]]
    T=np.array(T); c=base+d*L*0.4
    n=np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0]); flip=np.einsum('ij,ij->i',n,T.mean(1)-c)<0
    T[flip]=T[flip][:,[0,2,1]]
    return T
def hull(T,t):
    P=T.reshape(-1,3); key=[tuple(np.round(p,6)) for p in P]; acc={}
    n=np.cross(T[:,1]-T[:,0],T[:,2]-T[:,0]); n/=np.linalg.norm(n,axis=1)[:,None]
    for i,k in enumerate(key): acc[k]=acc.get(k,0)+n[i//3]
    off=np.array([acc[k]/np.linalg.norm(acc[k]) for k in key]).reshape(T.shape)
    return (T+off*t)[:,[0,2,1]]             # pushed out + flipped = outline shell
idx=np.argwhere(HW>0.5); HP=HLO+idx*HR
nspk=0
for sgn in (1,-1):
    Q=HP[HP[:,0]*sgn>0]
    for k,z in enumerate([-0.16,-0.02,0.11,0.23,0.35,0.46]):
        m=np.abs(Q[:,2]-z)<0.015; q=Q[m]; s_=q[np.argmax(q[:,0]*sgn)]
        L=0.24-0.02*k; d=np.array([sgn,0,0.5+0.07*k])
        T=shard(s_-np.array([sgn*0.04,0,0]),d,L,0.06-0.004*k,0.032)
        add_tris(T,blk_uv('spike',len(T))); H=hull(T,0.013); add_tris(H,blk_uv('spike_ol',len(H))); nspk+=2*len(T)
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
# weld vertices
P=T.reshape(-1,3); key=np.round(P,6); uniq,inv=np.unique(key,axis=0,return_inverse=True)
np.savez('mesh5.npz',V=uniq,F=inv.reshape(-1,3),UV=UVt.reshape(-1,2),N=N,SW=np.array(SW))
import json; json.dump(BLK,open('blk.json','w'))
