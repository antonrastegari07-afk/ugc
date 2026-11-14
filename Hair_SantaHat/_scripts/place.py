import numpy as np, trimesh, sys
from trimesh.ray.ray_pyembree import RayMeshIntersector as RMI
D=np.load('hair/raw.npz'); HF,R,RF=D['HF'],D['R'],D['RF']
H=np.load('hair/round_raw.npy'); info=np.load('hair/round_info.npz'); cc,RT=info['cc'],float(info['RT'])
s=0.63/RT
hf=RF[R[RF].mean(1)[:,1]>1.0]; head=trimesh.Trimesh(R,hf,process=True)
P,fi=trimesh.sample.sample_surface_even(head,5000,seed=2); N=head.face_normals[fi]
must=(P[:,1]>1.85)|((P[:,1]>1.55)&(N[:,2]<0.3))      # top + upper sides/back must be hidden
face=(N[:,2]>0.6)&(P[:,1]>1.30)&(P[:,1]<1.75)
def place(ty): return H*s+np.array([-cc[0]*s,ty,-cc[1]*s])
res=[]
for ty in np.arange(0.95,1.30,0.025):
    Hp=place(ty); I=RMI(trimesh.Trimesh(Hp,HF,process=False))
    hit=I.intersects_any(P+N*1e-4,N)
    # visible clipping: head point lies OUTSIDE the hair along its normal but behind hair from the viewer? -> use 'covered' metric
    res.append((ty,hit[must].mean(),hit[face].mean()))
    print(f'ty {ty:.3f}: top/sides/back hidden {hit[must].mean():.3f} | face covered {hit[face].mean():.2f}')
