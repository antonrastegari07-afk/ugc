import sys,numpy as np,trimesh,fast_simplification; sys.path.insert(0,'tools')
from meshio import geom
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
U='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/'
_,HF,UV,FU,PI,_=geom(U+'c0c73cca-tripo_convert_24749a36-9b5c-47a0-b54c-83df27b9ee46.fbx')
H=np.load('hair/fitted.npy'); TARGET=int(sys.argv[1]) if len(sys.argv)>1 else 3950
# UV islands: triangles connected through shared UV indices
n=len(FU); rows=np.repeat(np.arange(n),3); A=coo_matrix((np.ones(3*n),(rows,FU.reshape(-1))),shape=(n,len(UV)))
G=(A@A.T).tocsr(); nis,isl=connected_components(G,directed=False)
print('tris',len(HF),'uv islands',nis)
# weld by position and decimate
m=trimesh.Trimesh(H,HF,process=True); V0,F0=m.vertices,m.faces
Vd,Fd=fast_simplification.simplify(V0.astype(np.float32),F0.astype(np.int32),target_count=TARGET)
Vd=Vd.astype(float); print('decimated',len(Fd))
# re-project UVs per corner, constrained to the island of the triangle's centroid
orig=trimesh.Trimesh(H,HF,process=False)
cen=Vd[Fd].mean(1); _,_,tid=trimesh.proximity.closest_point(orig,cen); tisl=isl[tid]
UVc=np.zeros((len(Fd),3,2))
for k in np.unique(tisl):
    sel=np.where(tisl==k)[0]; tri=np.where(isl==k)[0]
    sub=trimesh.Trimesh(H,HF[tri],process=False)
    P=Vd[Fd[sel]].reshape(-1,3); cp,_,t2=trimesh.proximity.closest_point(sub,P)
    bc=trimesh.triangles.points_to_barycentric(H[HF[tri[t2]]],cp)
    uvt=UV[FU[tri[t2]]]; UVc[sel]=np.einsum('ij,ijk->ik',bc,uvt).reshape(-1,3,2)
np.savez('hair/decimated.npz',V=Vd,F=Fd,UVc=UVc)
