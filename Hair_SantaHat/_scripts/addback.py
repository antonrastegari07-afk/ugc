import sys,numpy as np, trimesh
from trimesh.ray.ray_pyembree import RayMeshIntersector as RMI
sys.path.insert(0,'tools'); from meshio import geom
U='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/c0c73cca-tripo_convert_24749a36-9b5c-47a0-b54c-83df27b9ee46.fbx'
_,HF,UV,FU,_,_=geom(U); H=np.load('hair/fitted.npy')
D=dict(np.load('hair/decimated.npz')); V,F,UVc=D['V'],D['F'],D['UVc']
A=RMI(trimesh.Trimesh(H,HF,process=False)); ctr=(H.min(0)+H.max(0))/2
added=set()
for it in range(1):
    B=RMI(trimesh.Trimesh(V,F,process=False)); rng=np.random.default_rng(it)
    dirs=rng.normal(size=(300,3)); dirs/=np.linalg.norm(dirs,axis=1)[:,None]; dirs=dirs[dirs[:,1]>-0.2]
    g=np.linspace(-1.3,1.3,150); need={}
    for d in dirs:
        u=np.cross(d,[0,1,0]); u/=np.linalg.norm(u); w=np.cross(d,u)
        O=(ctr+d*3)[None]+(g[:,None,None]*u+g[None,:,None]*w).reshape(-1,3); Dd=np.repeat(-d[None],len(O),0)
        sel=~B.intersects_any(O,Dd)
        loc,ri,ti=A.intersects_location(O[sel],Dd[sel],multiple_hits=False)
        for l,t in zip(loc,ti):
            if l[1]>2.3 and t not in added: need[t]=need.get(t,0)+1
    f=np.array([k for k,v in need.items() if v>=3],int)
    if len(f)==0: break
    added|=set(f.tolist())
    base=len(V); V=np.vstack([V,H[HF[f]].reshape(-1,3)]); F=np.vstack([F,base+np.arange(len(f)*3).reshape(-1,3)]); UVc=np.vstack([UVc,UV[FU[f]]])
    print('pass',it,'original hat/brim triangles put back',len(f),'| total',len(F))
np.savez('hair/decimated.npz',V=V,F=F,UVc=UVc)
