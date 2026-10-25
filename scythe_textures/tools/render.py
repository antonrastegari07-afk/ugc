import numpy as np, sys
from PIL import Image, ImageFilter
from mesh import load
V,T,N,F=load(__import__('os').path.join(__import__('os').path.dirname(__file__),'..','..','save obj SCYTHE.obj'))
c=V.mean(0); _,_,R=np.linalg.svd(V-c,full_matrices=False)
if np.linalg.det(R)<0: R[2]*=-1
L=(V-c)@R.T; NL=N@R.T; NL/=np.linalg.norm(NL,axis=1,keepdims=True)
# tangents (same as bake)
vi,ti,ni=F[:,:,0],F[:,:,1],F[:,:,2]
tan=np.zeros((len(V),3)); bit=np.zeros((len(V),3))
for f in range(len(F)):
    p=V[vi[f]]; uv=T[ti[f]]; e1=p[1]-p[0]; e2=p[2]-p[0]; d1=uv[1]-uv[0]; d2=uv[2]-uv[0]
    r=d1[0]*d2[1]-d2[0]*d1[1]
    if abs(r)<1e-12: continue
    r=1/r
    for k in range(3): tan[vi[f,k]]+=(e1*d2[1]-e2*d1[1])*r; bit[vi[f,k]]+=(e2*d1[0]-e1*d2[0])*r
tan=tan@R.T; bit=bit@R.T
d=sys.argv[1] if len(sys.argv)>1 else 'out'
ld=lambda n,ch: np.asarray(Image.open(f'{d}/Scythe_{n}.png').convert('RGB' if ch==3 else 'L'),float)/255
alb=ld('Color',3); nm=ld('Normal',3)*2-1; met=ld('Metalness',1); rgh=ld('Roughness',1); em=ld('Emissive',1)
def render(yaw,fname,W=900,H=1100):
    # view: screen up = +x local, screen right = -y local, rotate about up axis by yaw
    ca,sa=np.cos(yaw),np.sin(yaw)
    right=np.array([0,-ca,sa]); up=np.array([1,0,0]); fwd=np.cross(right,up)  # toward viewer = -fwd?
    P=np.stack([L@right,L@up,L@fwd],-1)
    sc=0.82*min(W,H)/ (P[:,:2].max(0)-P[:,:2].min(0)).max()
    mid=(P[:,:2].max(0)+P[:,:2].min(0))/2
    sx=(P[:,0]-mid[0])*sc+W/2; sy=H/2-(P[:,1]-mid[1])*sc; sz=P[:,2]
    zb=np.full((H,W),-1e9); col=np.zeros((H,W,3)); glow=np.zeros((H,W,3))
    view=-fwd  # camera direction from surface to eye: choose so +z toward camera
    lightdirs=[(np.array([0.6,0.2,0.5]),np.array([1.0,0.92,0.75])*3.0),(np.array([-0.5,-0.3,0.4]),np.array([1.0,0.8,0.5])*1.0)]
    for f in range(len(F)):
        a=vi[f]; xs=sx[a]; ys=sy[a]
        x0=max(int(xs.min()),0);x1=min(int(xs.max())+1,W-1);y0=max(int(ys.min()),0);y1=min(int(ys.max())+1,H-1)
        if x1<x0 or y1<y0: continue
        X,Y=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
        den=(ys[1]-ys[2])*(xs[0]-xs[2])+(xs[2]-xs[1])*(ys[0]-ys[2])
        if abs(den)<1e-9: continue
        w0=((ys[1]-ys[2])*(X-xs[2])+(xs[2]-xs[1])*(Y-ys[2]))/den
        w1=((ys[2]-ys[0])*(X-xs[2])+(xs[0]-xs[2])*(Y-ys[2]))/den
        w2=1-w0-w1; ins=(w0>=0)&(w1>=0)&(w2>=0)
        if not ins.any(): continue
        Wt=np.stack([w0,w1,w2],-1)[ins]; iy=(Y[ins]-.5).astype(int); ix=(X[ins]-.5).astype(int)
        z=Wt@sz[a]; ok=z>zb[iy,ix]
        if not ok.any(): continue
        Wt,iy,ix,z=Wt[ok],iy[ok],ix[ok],z[ok]; zb[iy,ix]=z
        uv=Wt@T[ti[f]]; px=np.clip((uv[:,0]*1024).astype(int),0,1023); py=np.clip(((1-uv[:,1])*1024).astype(int),0,1023)
        n=Wt@NL[ni[f]]; n/=np.linalg.norm(n,axis=1,keepdims=True)
        t=Wt@tan[a]; t-= (t*n).sum(1,keepdims=True)*n; t/=np.linalg.norm(t,axis=1,keepdims=True)+1e-9
        b=Wt@bit[a]; h=np.sign((np.cross(n,t)*b).sum(1,keepdims=True)); h[h==0]=1; b=np.cross(n,t)*h
        tn=nm[py,px]; N2=tn[:,0:1]*t+tn[:,1:2]*b+tn[:,2:3]*n; N2/=np.linalg.norm(N2,axis=1,keepdims=True)
        Ns=np.stack([N2@right,N2@up,N2@fwd],-1)
        Ns=np.where(Ns[:,2:3]<0,-Ns,Ns)  # double sided
        A=alb[py,px]**2.2; m=met[py,px][:,None]; r=rgh[py,px][:,None]
        Vd=np.array([0,0,1.])
        F0=0.04*(1-m)+A*m; diff=A*(1-m)
        Rv=2*Ns[:,2:3]*Ns-Vd
        env=np.clip(0.15+0.85*np.clip(Rv[:,1:2]*0.5+0.5,0,1)**3,0,1)*np.array([1.0,0.85,0.6])*0.9
        cc=F0*env*(1-0.5*r)+diff*0.08
        for ldir,lc in lightdirs:
            l=ldir/np.linalg.norm(ldir); hv=(l+Vd); hv/=np.linalg.norm(hv)
            nl=np.clip(Ns@l,0,1)[:,None]; nh=np.clip(Ns@hv,0,1)[:,None]
            a2=(r*r)**2; D=a2/(np.pi*((nh*nh)*(a2-1)+1)**2)
            cc+=lc*nl*(diff/np.pi + F0*D*0.25)
        e=em[py,px][:,None]*np.array([1.0,0.72,0.2])*2.2
        col[iy,ix]=cc+e; glow[iy,ix]=e
    gl=Image.fromarray((np.clip(glow/2.2,0,1)*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10))
    gl=np.asarray(gl,float)/255*1.2
    out=col+gl
    out=out/(1+out)*1.25  # tonemap
    out=np.clip(out,0,1)**(1/2.2)
    Image.fromarray((out*255).astype(np.uint8)).save(fname)
render(0.0,'prev_front.png'); render(np.pi,'prev_back.png'); render(0.7,'prev_34.png')
