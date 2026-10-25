# Rasterize mesh into UV space: per-texel position, normal, tangent, bitangent
import numpy as np
from mesh import load
S=1024
V,T,N,F=load(__import__('os').path.join(__import__('os').path.dirname(__file__),'..','..','save obj SCYTHE.obj'))
vi=F[:,:,0]; ti=F[:,:,1]; ni=F[:,:,2]
# per-vertex (by obj index) tangents
tan=np.zeros((len(V),3)); bit=np.zeros((len(V),3))
for f in range(len(F)):
    p=V[vi[f]]; uv=T[ti[f]]
    e1=p[1]-p[0]; e2=p[2]-p[0]; d1=uv[1]-uv[0]; d2=uv[2]-uv[0]
    r=d1[0]*d2[1]-d2[0]*d1[1]
    if abs(r)<1e-12: continue
    r=1/r
    t=(e1*d2[1]-e2*d1[1])*r; b=(e2*d1[0]-e1*d2[0])*r
    for k in range(3): tan[vi[f,k]]+=t; bit[vi[f,k]]+=b
Nn=N/np.linalg.norm(N,axis=1,keepdims=True)
pos=np.zeros((S,S,3)); nrm=np.zeros((S,S,3)); tg=np.zeros((S,S,3)); bt=np.zeros((S,S,3)); mask=np.zeros((S,S),bool); fid=-np.ones((S,S),int); bary=np.zeros((S,S,3))
for f in range(len(F)):
    uv=T[ti[f]]*[S,S]; uv[:,1]=S-uv[:,1]
    x0,y0=np.floor(uv.min(0)).astype(int)-1; x1,y1=np.ceil(uv.max(0)).astype(int)+1
    x0=max(x0,0);y0=max(y0,0);x1=min(x1,S-1);y1=min(y1,S-1)
    xs,ys=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
    a,b,c=uv
    den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
    if abs(den)<1e-12: continue
    w0=((b[1]-c[1])*(xs-c[0])+(c[0]-b[0])*(ys-c[1]))/den
    w1=((c[1]-a[1])*(xs-c[0])+(a[0]-c[0])*(ys-c[1]))/den
    w2=1-w0-w1
    eps=-1e-4
    inside=(w0>=eps)&(w1>=eps)&(w2>=eps)
    if not inside.any(): continue
    W=np.stack([w0,w1,w2],-1)[inside]
    iy=(ys[inside]-.5).astype(int); ix=(xs[inside]-.5).astype(int)
    pos[iy,ix]=W@V[vi[f]]; nrm[iy,ix]=W@Nn[ni[f]]; tg[iy,ix]=W@tan[vi[f]]; bt[iy,ix]=W@bit[vi[f]]
    mask[iy,ix]=True; fid[iy,ix]=f; bary[iy,ix]=W
print('coverage',mask.mean())
np.savez_compressed('gbuf.npz',pos=pos,nrm=nrm,tg=tg,bt=bt,mask=mask,fid=fid,bary=bary)
