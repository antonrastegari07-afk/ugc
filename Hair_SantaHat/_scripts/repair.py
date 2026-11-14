import numpy as np, trimesh
from collections import defaultdict
G=np.load('hair/final_geo.npz'); V,F,UVc=G['V'].copy(),G['F'].copy(),G['UVc'].copy()
# --- weld-aware boundary loops (ordered)
key=np.round(V,6); _,wid=np.unique(key,axis=0,return_inverse=True); wid=wid.ravel()
WF=wid[F]
ecount=defaultdict(int); eface={}
for fi,t in enumerate(WF):
    for j in range(3):
        a,b=t[j],t[(j+1)%3]; k=(min(a,b),max(a,b)); ecount[k]+=1; eface[(a,b)]=(fi,j)
nxt={}
for (a,b),(fi,j) in eface.items():
    if ecount[(min(a,b),max(a,b))]==1: nxt[b]=a          # boundary edge reversed -> fill orientation consistent
wpos={}; 
for vi,w in enumerate(wid): wpos[w]=V[vi]
# uv for a welded vertex: from any face corner touching it
wuv={}
for fi,t in enumerate(WF):
    for j in range(3): wuv.setdefault(t[j],UVc[fi][j])
loops=[]; used=set()
for s in list(nxt):
    if s in used: continue
    L=[s]; used.add(s); x=nxt.get(s)
    while x is not None and x not in used and len(L)<40: L.append(x); used.add(x); x=nxt.get(x)
    if x==s: loops.append(L)
newV=[];newF=[];newUV=[]; base=len(V); filled=0
for L in loops:
    P=np.array([wpos[w] for w in L])
    if len(L)>12 or np.ptp(P,0).max()>0.35: continue
    filled+=1
    for k in range(1,len(L)-1):
        tri=[L[0],L[k],L[k+1]]
        newF.append([base+len(newV)+i for i in range(3)])
        for w in tri: newV.append(wpos[w])
        newUV.append([wuv[w] for w in tri])
print('holes filled',filled,'| new triangles',len(newF))
V=np.vstack([V,np.array(newV)]) if newV else V
F=np.vstack([F,np.array(newF)]) if newF else F
UVc=np.vstack([UVc,np.array(newUV)]) if newUV else UVc
# --- flip faces whose BACK looks at the outside while their FRONT is enclosed (inverted outer faces)
from trimesh.ray.ray_pyembree import RayMeshIntersector as RMI
m=trimesh.Trimesh(V,F,process=False); I=RMI(m)
c=m.triangles_center; n=m.face_normals; eps=1e-4
def escapes(d):
    hit=np.zeros(len(F),bool); k=np.arange(len(F))
    loc,ri,ti=I.intersects_location(c+d*eps*10,d,multiple_hits=False)
    hit[ri]=True; return ~hit
# test several directions around each side for robustness
def frac_escape(sign):
    tot=np.zeros(len(F))
    rng=np.random.default_rng(0)
    for t in range(5):
        j=rng.normal(size=n.shape)*0.25; d=sign*n+j; d/=np.linalg.norm(d,axis=1)[:,None]
        d=np.where((np.einsum('ij,ij->i',d,n)*sign>0.3)[:,None],d,sign*n)
        tot+=escapes(d)
    return tot/5
front=frac_escape(1); back=frac_escape(-1)
flip=np.zeros(len(F),bool)
F[flip]=F[flip][:,[0,2,1]]; UVc[flip]=UVc[flip][:,[0,2,1]]
print('inverted faces flipped',flip.sum(),'| total tris',len(F))
np.savez('hair/final_geo.npz',V=V,F=F,UVc=UVc)
