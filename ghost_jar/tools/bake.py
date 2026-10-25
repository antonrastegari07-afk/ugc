import numpy as np
from PIL import Image
from noise import fbm, perlin, worley
S=1024; SC=1.1
d=np.load('geo.npz'); P=d['P']/SC; UV=d['UV']; NN=d['N']; PID=d['pid']
pos=np.zeros((S,S,3)); nrm=np.zeros((S,S,3)); pid=-np.ones((S,S),int)
for f in range(len(P)):
    uv=UV[f]*S; uv=np.stack([uv[:,0],S-uv[:,1]],1)
    x0,y0=np.maximum(np.floor(uv.min(0)).astype(int)-1,0); x1,y1=np.minimum(np.ceil(uv.max(0)).astype(int)+1,S-1)
    xs,ys=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
    a,b,c=uv; den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
    if abs(den)<1e-12: continue
    w0=((b[1]-c[1])*(xs-c[0])+(c[0]-b[0])*(ys-c[1]))/den; w1=((c[1]-a[1])*(xs-c[0])+(a[0]-c[0])*(ys-c[1]))/den; w2=1-w0-w1
    ins=(w0>=-1e-3)&(w1>=-1e-3)&(w2>=-1e-3)
    if not ins.any(): continue
    W=np.stack([w0,w1,w2],-1)[ins]; iy=(ys[ins]-.5).astype(int); ix=(xs[ins]-.5).astype(int)
    pos[iy,ix]=W@P[f]; nrm[iy,ix]=W@NN[f]; pid[iy,ix]=PID[f]
M=pid>=0
print('coverage',M.mean())
idx=np.where(M); p=pos[idx]; k=pid[idx]; n=len(p)
x,y,z=p[:,0],p[:,1],p[:,2]
ss=lambda e0,e1,t:(lambda q:q*q*(3-2*q))(np.clip((t-e0)/(e1-e0),0,1))
az=np.degrees(np.arctan2(x,-y))   # 0 = front (-Y), +90 = +X side
col=np.zeros((n,3)); A=np.ones(n); met=np.zeros(n); rgh=np.full(n,0.5); em=np.zeros(n); h=np.zeros(n)
def put(m,c=None,a=None,mt=None,r=None,e=None,hh=None):
    if c is not None: col[m]=np.broadcast_to(c,(n,3))[m] if np.ndim(c)==1 else c[m]
    for arr,v in ((A,a),(met,mt),(rgh,r),(em,e),(h,hh)):
        if v is not None: arr[m]=v[m] if np.ndim(v) else v
cyan=np.array([0.50,0.91,1.0])
# ---- outer glass (11)
m=k==11
st=lambda c,w: np.exp(-((az-c)/w)**2)
stripes=(0.75*st(-46,4)+0.9*st(-34,1.4)+0.6*st(40,2.2)+0.35*st(54,5)+0.5*st(-140,6))*ss(0.08,0.16,z)*(1-ss(0.62,0.70,z))
arc=np.exp(-((az+38)/24)**2)*np.exp(-((z-0.765)/0.018)**2)
basel=np.exp(-((z-0.045)/0.010)**2)*(0.5+0.5*np.exp(-((az+40)/40)**2))
lipl=np.exp(-((z-0.985)/0.008)**2)
stripes=np.clip(stripes+0.9*arc+0.7*basel+0.6*lipl,0,1)
shoulder=ss(0.70,0.86,z); base=1-ss(0.03,0.07,z); lip=ss(0.955,0.975,z)
a_out=np.clip(0.025+0.10*shoulder+0.30*base+0.12*lip+0.85*stripes,0,0.95)
c_out=np.array([0.14,0.20,0.25])*(1-stripes[:,None])+np.array([1,1,1])*stripes[:,None]
c_out=c_out*(1-base[:,None]*0.5)+cyan*base[:,None]*0.5
put(m,c_out,a_out,0.0,0.05,0.35*base*(1-stripes),0.02*fbm(p*6,2,3)+0.3*lip)
# ---- inner inverted glass (0)
m=k==0
low=1-ss(0.06,0.38,z); fl=z<0.065
put(m,np.array([0.20,0.45,0.55]),np.clip(0.025+0.16*low+0.15*fl,0,1),0.0,0.05,0.6*low+0.3*fl,0.0)
# ---- glow inverted cylinder (1)
m=k==1
g=(1-ss(0.06,0.42,z))
put(m,np.array([0.55,0.93,1.0]),0.30*g**1.6,0.0,0.3,0.75*g,0.0)
# ---- smoke layers (2..5)
for L,(dens,emv) in enumerate([(0.95,1.0),(0.8,0.95),(0.62,0.85),(0.45,0.75)]):
    m=k==2+L
    if not m.any(): continue
    q=p[m]
    sw=fbm(q*np.array([7,7,7])+L*3.1,4,10+L)
    wisps=np.abs(np.sin((fbm(q*4+L,3,30)*9)))
    dd=np.clip(0.45+1.6*sw,0,1)**1.3*(0.5+0.5*wisps)
    a=np.clip(dd*dens,0.0,0.92)
    c=np.array([0.40,0.78,0.92])*(1-dd[:,None])+np.array([0.70,0.93,1.0])*dd[:,None]
    col[m]=c; A[m]=a; met[m]=0; rgh[m]=1.0; em[m]=np.clip(0.8*emv*(0.5+0.5*dd),0,1); h[m]=0.3*dd
# ---- ghost (6)
m=k==6
q=p[m]; gx,gy,gz=q[:,0],q[:,1],q[:,2]
front=gy<-0.03
body=np.array([0.98,0.99,1.0])
c=np.tile(body,(m.sum(),1)); hem=1-ss(0.27,0.36,gz)
c=c*(1-hem[:,None]*0.45)+np.array([0.62,0.90,1.0])*hem[:,None]*0.45
a=0.94-0.30*hem; e=np.full(m.sum(),0.12)+0.35*hem; r=np.full(m.sum(),0.42); hh=np.zeros(m.sum())
# cheeks
for sx in (-1,1):
    dch=np.hypot((gx-sx*0.095)/0.026,(gz-0.468)/0.018)
    ch=(1-ss(0.6,1.0,dch))*front
    c=c*(1-0.7*ch[:,None])+np.array([1.0,0.55,0.66])*0.7*ch[:,None]
# eyes
eyes=np.zeros(m.sum()); hl=np.zeros(m.sum())
for sx in (-1,1):
    de=np.hypot((gx-sx*0.058)/0.027,(gz-0.508)/0.037)
    eyes=np.maximum(eyes,(1-ss(0.92,1.0,de))*front)
    d1=np.hypot((gx-(sx*0.058-0.009))/0.0095,(gz-0.522)/0.0105)
    d2=np.hypot((gx-(sx*0.058+0.008))/0.0045,(gz-0.494)/0.0048)
    hl=np.maximum(hl,np.maximum(1-ss(0.75,1.0,d1),1-ss(0.7,1.0,d2))*front)
dm=np.hypot(gx,gz-0.478); mouth=(1-ss(0.0035,0.0060,np.abs(dm-0.020)))*(gz<0.474)*front
dark=np.maximum(eyes,mouth)
c=c*(1-dark[:,None])+np.array([0.035,0.045,0.08])*dark[:,None]
c=c*(1-hl[:,None])+np.array([1,1,1])*hl[:,None]
a=np.maximum(a,dark); e=e*(1-dark)+0.9*hl*0; r=r*(1-dark)+0.08*dark; hh=0.6*eyes+0.3*hl-0.4*mouth
col[m]=c; A[m]=a; met[m]=0; rgh[m]=r; em[m]=e; h[m]=hh
# ---- outline inverted hull (12)
m=k==12; put(m,np.array([0.06,0.12,0.24]),1.0,0.0,0.6,0.0,0.0)
# ---- sparkles (7)
m=k==7; put(m,np.array([0.85,1.0,1.0]),1.0,0.0,0.2,1.0,0.0)
# ---- cork (8)
m=k==8
q=p[m]; F1,F2,_=worley(q*55,4); grain=fbm(q*40,3,5)
spots=1-ss(0.05,0.18,F1)
cc=np.array([0.60,0.42,0.25])*(0.88+0.25*grain[:,None])
cc=cc*(1-0.5*spots[:,None])+np.array([0.30,0.19,0.10])*0.5*spots[:,None]
top=q[:,2]>1.08; edge=ss(0.15,0.185,np.hypot(q[:,0],q[:,1]))*top
cc=cc*(1-0.3*edge[:,None])
col[m]=cc; A[m]=1; met[m]=0; rgh[m]=0.85; em[m]=0; h[m]=0.5*grain-0.6*spots
# ---- bands (9,10)
for bk,zlo,zhi,lights in ((9,0.012,0.085,(-14,14)),(10,0.900,0.945,(0,))):
    m=k==bk
    q=p[m]; bz=q[:,2]; baz=np.degrees(np.arctan2(q[:,0],-q[:,1]))
    mid=(zlo+zhi)/2; hgt=zhi-zlo
    edgeh=ss(0.30,0.48,np.abs(bz-mid)/hgt)
    cc=np.array([0.15,0.16,0.19])*(1+0.6*edgeh[:,None])
    riv=np.zeros(m.sum())
    for ang in range(-165,181,30):
        dd=np.hypot(((baz-ang+180)%360-180)/2.2,(bz-mid)/(hgt*0.16))
        riv=np.maximum(riv,1-ss(0.6,1.0,dd))
    cc=cc*(1-riv[:,None])+np.array([0.42,0.44,0.48])*riv[:,None]
    lt=np.zeros(m.sum())
    for ang in lights:
        dd=np.maximum(np.abs(((baz-ang+180)%360-180)/4.5),np.abs(bz-mid)/(hgt*0.18))
        lt=np.maximum(lt,1-ss(0.75,1.0,dd))
    cc=cc*(1-lt[:,None])+cyan*lt[:,None]
    col[m]=cc; A[m]=1; met[m]=1-lt; rgh[m]=0.35-0.1*riv; em[m]=lt; h[m]=0.6*riv+0.4*edgeh
# ---- write images with dilation
def img(vals,ch):
    im=np.zeros((S,S,ch)); im[idx]=vals.reshape(n,ch); return im
def dilate(im,it=16):
    im=im.copy(); mm=M.astype(float)
    for _ in range(it):
        acc=np.zeros_like(im); cnt=np.zeros(mm.shape)
        for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
            acc+=np.roll(np.roll(im*mm[...,None],dy,0),dx,1); cnt+=np.roll(np.roll(mm,dy,0),dx,1)
        new=(mm==0)&(cnt>0); im[new]=acc[new]/cnt[new][:,None]; mm[new]=1
    im[mm==0]=0
    return im
def save(name,arr,mode):
    a=(np.clip(arr,0,1)*255+.5).astype(np.uint8)
    Image.fromarray(a if a.shape[-1]>1 else a[...,0],mode).save(f'out/{name}.png')
import os; os.makedirs('out',exist_ok=True)
save('GhostJar_Color',dilate(img(np.concatenate([col,A[:,None]],1),4)),'RGBA')
save('GhostJar_Metalness',dilate(img(met,1)),'L')
save('GhostJar_Roughness',dilate(img(rgh,1)),'L')
save('GhostJar_Emissive',dilate(img(em,1)),'L')
H=dilate(img(h,1))[...,0]
from PIL import ImageFilter
H=np.asarray(Image.fromarray((np.clip(H*0.5+0.5,0,1)*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)),float)/255
gx_=(np.roll(H,-1,1)-np.roll(H,1,1))*0.5; gy_=(np.roll(H,1,0)-np.roll(H,-1,0))*0.5
nm=np.stack([-gx_*4,-gy_*4,np.ones_like(H)],-1); nm/=np.linalg.norm(nm,axis=-1,keepdims=True)
save('GhostJar_Normal',nm*0.5+0.5,'RGB')
print('ok')
