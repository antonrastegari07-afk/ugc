import numpy as np, trimesh, sys
from scipy.sparse.csgraph import dijkstra
D=np.load('hair/raw.npz'); HF=D['HF']; H=np.load('hair/round_raw_before_tail.npy')
ANG=float(sys.argv[1]) if len(sys.argv)>1 else None; L=float(sys.argv[2]) if len(sys.argv)>2 else 0.38
m=trimesh.Trimesh(H,HF,process=False)
# weld coincident vertices for the graph (UV seams split them)
key=np.round(H,5); _,inv=np.unique(key,axis=0,return_inverse=True); inv=inv.ravel()
E=m.edges_unique; G=trimesh.graph.edges_to_coo(inv[E],data=np.linalg.norm(H[E[:,0]]-H[E[:,1]],axis=1),count=inv.max()+1)
G=G.maximum(G.T)
POM=np.array([-0.40,0.42,0.22]); pomv=np.where(np.linalg.norm(H-POM,axis=1)<0.12)[0]
dist=dijkstra(G.tocsr(),indices=np.unique(inv[pomv]),min_only=True)[inv]
pc=H[np.linalg.norm(H-POM,axis=1)<0.15].mean(0)
band=(dist>0.12+L-0.03)&(dist<0.12+L+0.03)
root=H[band].mean(0)
print('pompom centre',pc.round(3),'| tail root (geodesic',0.12+L,')',root.round(3),'| band verts',band.sum())
for dd in (0.15,0.25,0.35,0.45):
    b=(dist>dd-0.02)&(dist<dd+0.02); print(f'  along tail d={dd}: centre {H[b].mean(0).round(3)}')
axis=np.array([1.0,0,0])
v=pc-root; cur=np.degrees(np.arctan2(v[2],-v[1]))      # angle of pompom from straight-down, + = toward front
if ANG is None: ANG=cur
print(f'pompom hangs {cur:.1f} deg in front of vertical -> rotate {ANG:.1f} deg back')
w=np.clip(1-(dist-0.12)/L,0,1); w=w*w*(3-2*w); w[dist<=0.12]=1
t=np.radians(ANG*w)                                     # rotation about +X through root
p=H-root; y=p[:,1]*np.cos(t)-p[:,2]*np.sin(t); z=p[:,1]*np.sin(t)+p[:,2]*np.cos(t)
H2=H.copy(); H2[:,1]=root[1]+y; H2[:,2]=root[2]+z
mv=np.linalg.norm(H2-H,axis=1); print('vertices moved >1mm',(mv>0.001).sum(),'| new pompom centre',H2[np.linalg.norm(H-POM,axis=1)<0.15].mean(0).round(3))
np.save('hair/round_raw.npy',H2)
sys.path.insert(0,'tools'); from raster import render, sheet
col=np.ones((len(HF),3))*0.88; c=H[HF].mean(1); col[np.linalg.norm(c-POM,axis=1)<0.15]=[0.55,0.65,1]
ims=[render(X,HF,col,yy,pp,400) for X in (H,H2) for yy,pp in [(0,5),(-90,5),(90,5),(0,89)]]
sheet(ims,4).save('hair/tail_fix2.png')
