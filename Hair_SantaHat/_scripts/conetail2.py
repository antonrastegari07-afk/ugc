import numpy as np, trimesh, sys
from scipy.sparse.csgraph import dijkstra, connected_components
D=np.load('hair/raw.npz'); HF=D['HF']; H=np.load('hair/round_raw_before_tail.npy')
L=float(sys.argv[1]) if len(sys.argv)>1 else 0.30; RTIP=float(sys.argv[2]) if len(sys.argv)>2 else 0.02
m=trimesh.Trimesh(H,HF,process=False)
key=np.round(H,5); _,inv=np.unique(key,axis=0,return_inverse=True); inv=inv.ravel()
E=m.edges_unique; G=trimesh.graph.edges_to_coo(inv[E],data=np.linalg.norm(H[E[:,0]]-H[E[:,1]],axis=1),count=inv.max()+1); G=G.maximum(G.T).tocsr()
nc,lab=connected_components(G,directed=False); vl=lab[inv]
POM0=np.array([-0.40,0.42,0.22]); pl=vl[np.argmin(np.linalg.norm(H-POM0,axis=1))]
pom=vl==pl; pc=H[pom].mean(0); prad=np.median(np.linalg.norm(H[pom]-pc,axis=1))
main=vl==np.bincount(vl).argmax()
print('pompom: separate piece with',pom.sum(),'verts, centre',pc.round(3),'radius',round(prad,3))
# stem tip = main-body vertex closest to the pompom
tipi=np.where(main)[0][np.argmin(np.linalg.norm(H[main]-pc,axis=1))]; tip=H[tipi]
dist=dijkstra(G,indices=[inv[tipi]])[0][inv]; dist[~main]=np.inf
eu=np.linalg.norm(H-tip,axis=1); tailm=main&(dist<1.8*eu+0.03)   # same sheet as the tail (excludes brim/dome under it)
print('tail-sheet vertices within L:',(tailm&(dist<=L)).sum())
print('stem tip',tip.round(3),'gap to pompom centre',round(np.linalg.norm(tip-pc),3))
# original centreline from geodesic bands
ds=np.arange(0.0,L+0.001,0.02); Cl=[]
for dd in ds:
    b=tailm&(dist>=dd-0.012)&(dist<dd+0.012); Cl.append(H[b].mean(0) if b.sum() else Cl[-1])
Cl=np.array(Cl); Cl[0]=tip
root=Cl[-1]; rb=tailm&(dist>L-0.02)&(dist<L+0.005)
Rroot=np.median(np.linalg.norm(H[rb]-root,axis=1))
# new straight axis: from root toward the original tip, but with NO forward swing (keep root's z)
tip_new=tip.copy(); ax=tip_new-root; Lc=np.linalg.norm(ax); ax/=Lc
print('root',root.round(3),'root radius',round(Rroot,3),'| tip moved',tip.round(3),'->',tip_new.round(3))
def rodrigues(a,b):
    a=a/np.linalg.norm(a); b=b/np.linalg.norm(b); v=np.cross(a,b); c=a@b
    if np.linalg.norm(v)<1e-9: return np.eye(3)
    K=np.array([[0,-v[2],v[1]],[v[2],0,-v[0]],[-v[1],v[0],0]]); return np.eye(3)+K+K@K*(1/(1+c))
sel=np.where(tailm&(dist<=L))[0]
H2=H.copy(); P=H[sel]
sp=np.clip((P-root)@ax,0,Lc); C=root+np.outer(sp,ax)
rad=P-C; rad-=np.outer(rad@ax,ax); rl=np.linalg.norm(rad,axis=1)
u=np.where(rl[:,None]>1e-6,rad/np.maximum(rl,1e-9)[:,None],np.cross(ax,[0,0,1.0]))
t=sp/Lc                                             # 0 root -> 1 tip, straight axis
rt=Rroot*(1-t)+RTIP*t
target=C+u*rt[:,None]
w=np.clip((1-dist[sel]/L)/0.4,0,1); w=w*w*(3-2*w)  # full cone on the hanging part, blended into the hat at the root
H2[sel]=P*(1-w[:,None])+target*w[:,None]
H2[pom]=H[pom]+(tip_new-tip)               # pompom follows the tip rigidly
print('reshaped tail verts',len(sel),'| pompom moved by',np.round(tip_new-tip,3))
np.save('hair/round_raw.npy',H2)
sys.path.insert(0,'tools'); from raster import render, sheet
col=np.ones((len(HF),3))*[0.85,0.25,0.2]; col[np.isin(HF,np.where(pom)[0]).all(1)]=[0.96,0.96,0.96]
hairish=H[HF].mean(1)[:,1]<0.47+0.31*H[HF].mean(1)[:,2]-0.02; col[hairish&~np.isin(HF,np.where(pom)[0]).all(1)]=[0.9,0.9,0.9]
ims=[render(X,HF,col,y,p,400) for X in (H,H2) for y,p in [(0,5),(90,5),(45,10),(0,89)]]
sheet(ims,4).save('hair/cone2_compare.png')
near=np.linalg.norm(H[HF].mean(1)-np.array([-0.33,0.6,0.15]),axis=1)<0.42
for tag,X in (('a',H),('b',H2)):
    F=HF[near]; uu=np.unique(F); rm=-np.ones(len(X),int); rm[uu]=np.arange(len(uu))
    sheet([render(X[uu],rm[F],col[near],y,p,420) for y,p in [(30,5),(60,5),(90,5),(90,45)]],4).save(f'hair/cone2_close_{tag}.png')
