import numpy as np, sys
def push(V):
    r=np.hypot(V[:,0],V[:,2]); y=V[:,1]; rh=np.where(y<1.95,0.6,np.interp(y,[1.95,2.05,2.11],[0.554,0.457,0.0]))
    bad=(y>0.99)&(y<2.11)&(r<rh+0.015); u=np.c_[V[:,0],np.zeros(len(V)),V[:,2]]/np.maximum(r,1e-6)[:,None]
    V=V.copy(); V[bad]+=u[bad]*((rh+0.02-r)[bad])[:,None]
    tor=(V[:,1]<1.02)&(np.abs(V[:,0])<1.0)&(np.abs(V[:,2])<0.52); V[tor,1]=1.02
    return V,bad.sum(),tor.sum()
if sys.argv[1]=='pre':
    V,b,t=push(np.load('hair/placed.npy')); np.save('hair/fitted.npy',V); print('pre: pushed',b,'lifted',t)
else:
    D=np.load('hair/decimated.npz'); V,b,t=push(D['V']); np.savez('hair/final_geo.npz',V=V,F=D['F'],UVc=D['UVc']); print('post: pushed',b,'lifted',t,'tris',len(D['F']))
