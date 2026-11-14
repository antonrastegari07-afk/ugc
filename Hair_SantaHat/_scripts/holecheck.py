import numpy as np, trimesh, sys
from trimesh.ray.ray_pyembree import RayMeshIntersector as RMI
def miss_rate(Vpre,Fpre,Vpost,Fpost,seed=0):
    A=RMI(trimesh.Trimesh(Vpre,Fpre,process=False)); B=RMI(trimesh.Trimesh(Vpost,Fpost,process=False))
    ctr=(Vpre.min(0)+Vpre.max(0))/2; rng=np.random.default_rng(seed)
    dirs=rng.normal(size=(120,3)); dirs/=np.linalg.norm(dirs,axis=1)[:,None]; dirs=dirs[dirs[:,1]>-0.2]
    g=np.linspace(-1.3,1.3,120); tot=0; miss=0; pts=[]
    for d in dirs:
        u=np.cross(d,[0,1,0]); u/=np.linalg.norm(u); w=np.cross(d,u)
        O=(ctr+d*3)[None]+(g[:,None,None]*u+g[None,:,None]*w).reshape(-1,3); D=np.repeat(-d[None],len(O),0)
        ha=A.intersects_any(O,D); hb=B.intersects_any(O,D)
        tot+=ha.sum(); mm=ha&~hb; miss+=mm.sum()
    return miss,tot
