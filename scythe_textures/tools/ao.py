import numpy as np
from mesh import load
V,T,N,F=load(__import__('os').path.join(__import__('os').path.dirname(__file__),'..','..','save obj SCYTHE.obj'))
vi=F[:,:,0]
P0=V[vi[:,0]];E1=V[vi[:,1]]-P0;E2=V[vi[:,2]]-P0
Nn=N/np.linalg.norm(N,axis=1,keepdims=True)
rng=np.random.default_rng(1)
R=48
dirs=rng.normal(size=(R,3)); dirs/=np.linalg.norm(dirs,axis=1,keepdims=True)
size=np.linalg.norm(V.max(0)-V.min(0)); maxd=size*0.08
ao=np.zeros(len(V))
for i in range(len(V)):
    n=Nn[i]; d=dirs*np.sign(dirs@n)[:,None]
    o=V[i]+n*size*1e-3
    # moller trumbore, rays x tris
    pv=np.cross(d[:,None,:],E2[None]); det=(E1[None]*pv).sum(-1)
    inv=1/np.where(np.abs(det)<1e-12,1e-12,det)
    tv=o-P0
    u=(tv[None]*pv).sum(-1)*inv
    qv=np.cross(tv[None],E1[None]) # (1,T,3)
    v=(d[:,None,:]*qv).sum(-1)*inv
    t=(E2[None]*qv).sum(-1)*inv
    hit=(np.abs(det)>1e-12)&(u>=0)&(v>=0)&(u+v<=1)&(t>1e-6)&(t<maxd)
    w=np.clip(d@n,0,1)
    ao[i]=1-(hit.any(1)*w).sum()/w.sum()
np.save('ao_v.npy',ao); print(ao.min(),ao.mean())
