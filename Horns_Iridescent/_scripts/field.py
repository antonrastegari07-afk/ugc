import sys,os,time; sys.path.insert(0,'tools')
from load import load; from comp import components; import numpy as np
SRC='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/807479b3-HornsBlackHole_UGC.fbx'
V,F,UV,FUV,_,_=load(SRC); C=components(V,F)
HC=[0,1,2,3]; lo=V[F[np.isin(C,HC)]].reshape(-1,3).min(0)-0.03; hi=V[F[np.isin(C,HC)]].reshape(-1,3).max(0)+0.03
R=0.012; ax=[np.arange(lo[i],hi[i]+R,R) for i in range(3)]
G=np.stack(np.meshgrid(*ax,indexing='ij'),-1).reshape(-1,3)
def winding(P,T):
    w=np.zeros(len(P))
    for i0 in range(0,len(P),600):
        p=P[i0:i0+600,None,:]; a=T[None,:,0]-p; b=T[None,:,1]-p; c=T[None,:,2]-p
        la,lb,lc=[np.sqrt((x*x).sum(-1)) for x in (a,b,c)]
        num=(a*np.cross(b,c)).sum(-1)
        den=la*lb*lc+(a*b).sum(-1)*lc+(b*c).sum(-1)*la+(c*a).sum(-1)*lb
        w[i0:i0+600]=(2*np.arctan2(num,den)).sum(1)/(4*np.pi)
    return w
t=time.time(); W=np.zeros(len(G))
for k in HC:
    T=V[F[C==k]]; m=np.all((G>=T.reshape(-1,3).min(0)-R)&(G<=T.reshape(-1,3).max(0)+R),1)
    W[m]=np.maximum(W[m],np.clip(np.abs(winding(G[m],T)),0,1)); print('comp',k,round(time.time()-t,1),'s')
np.savez('field.npz',W=W.reshape([len(a) for a in ax]),lo=lo,R=R)
