import numpy as np, os
from PIL import Image, ImageFilter
from noise import fbm
S=1024
import sys
NOEM='--noemis' in sys.argv
PRE='HornsNoEmissive_' if NOEM else 'Horns_'
d=np.load('geo.npz'); P=d['P']; UV=d['UV']; A1=d['A1']; A2=d['A2']; NN=d['N']; PART=d['part']; PARTS=list(d['parts'])
pos=np.zeros((S,S,3)); nrm=np.zeros((S,S,3)); a1=np.zeros((S,S,2)); a2=np.zeros((S,S,2)); pid=-np.ones((S,S),int)
for f in range(len(P)):
    uv=UV[f]*S; uv=np.stack([uv[:,0],S-uv[:,1]],1)
    x0,y0=np.maximum(np.floor(uv.min(0)).astype(int)-1,0); x1,y1=np.minimum(np.ceil(uv.max(0)).astype(int)+1,S-1)
    xs,ys=np.meshgrid(np.arange(x0,x1+1)+.5,np.arange(y0,y1+1)+.5)
    a,b,c=uv; den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
    if abs(den)<1e-12: continue
    w0=((b[1]-c[1])*(xs-c[0])+(c[0]-b[0])*(ys-c[1]))/den; w1=((c[1]-a[1])*(xs-c[0])+(a[0]-c[0])*(ys-c[1]))/den; w2=1-w0-w1
    ins=(w0>=-2e-3)&(w1>=-2e-3)&(w2>=-2e-3)
    if not ins.any(): continue
    W=np.stack([w0,w1,w2],-1)[ins]; iy=(ys[ins]-.5).astype(int); ix=(xs[ins]-.5).astype(int)
    pos[iy,ix]=W@P[f]; nrm[iy,ix]=W@NN[f]; a1[iy,ix]=W@A1[f]; a2[iy,ix]=W@A2[f]; pid[iy,ix]=PART[f]
M=pid>=0; idx=np.where(M); p=pos[idx]; k=pid[idx]; A=a1[idx]; B=a2[idx]; n=len(p)
ss=lambda e0,e1,x:(lambda q:q*q*(3-2*q))(np.clip((x-e0)/(e1-e0),0,1))
col=np.zeros((n,3)); met=np.zeros(n); rgh=np.full(n,0.5); em=np.zeros(n); h=np.zeros(n)
low=fbm(p*5,3,1); mid=fbm(p*18,3,2); fine=fbm(p*70,2,3)
# ---------- horns ----------
m=k==0
th=A[m][:,0]; lx=B[m][:,0]; lz=B[m][:,1]
chain=(th<0.022)&(lz<0.33)&(lx>0.16)&(lx<0.37)
pend=chain&(lz<0.095)
tip=ss(0.075,0.012,th)**0.8*(~chain)                     # thin parts -> spikes and the horn tip turn white
ridges=0.5+0.5*np.sin(lz*90+low[m]*4)               # growth rings along the horn
black=np.array([0.010,0.010,0.012])*(0.85+0.25*low[m][:,None]+0.12*mid[m][:,None])*(0.85+0.3*ridges[:,None])
ivory=np.array([0.80,0.76,0.98])*(0.92+0.1*fine[m][:,None])
c=black*(1-tip[:,None])+ivory*tip[:,None]
r=(0.88+0.06*mid[m])*(1-tip)+0.45*tip       # matte black body, lavender tips keep a soft sheen
mt=(1-tip)*1.0                              # black metal body: no reflections
c[chain]=np.array([0.80,0.81,0.84])*(0.9+0.15*fine[m][chain][:,None]); mt[chain]=1.0; r[chain]=0.22
c[pend]=np.array([0.86,0.82,1.0]); mt[pend]=0; r[pend]=0.05
e=0.30*ss(0.012,0.004,th)*(~chain)                  # faint glow on the very tips
e[pend]=0.75
col[m]=c; met[m]=mt; rgh[m]=np.clip(r,0.05,0.9); em[m]=e; h[m]=0.35*ridges+0.1*mid[m]
# ---------- black hole ----------
white=np.array([0.97,0.96,1.0]); mauve=np.array([0.76,0.62,1.0]); deep=np.array([0.62,0.50,0.95])
def tint(v,seedp,sc_):
    w=np.clip(0.55+1.1*fbm(seedp*sc_,3,17),0,1)[:,None]          # patches between white and light mauve
    return white*(1-w)+mauve*w
m=k==PARTS.index('hole')                       # event horizon: absolute black, matte, no glow
col[m]=0.0; met[m]=1.0; rgh[m]=1.0; em[m]=0.0; h[m]=0.0   # black metal: F0 = 0 -> reflects (almost) no light
m=k==PARTS.index('halo')                       # inverted lensing shell: its far inner wall is the glowing ring around the ball
lon=A[m][:,0]*2*np.pi; lat=A[m][:,1]          # lat 0 = top pole, 0.5 = disk plane
eq=np.exp(-((lat-0.5)/0.10)**2)                # bright where the disk plane is
arc=0.45+0.55*np.abs(np.cos((lat-0.5)*np.pi))  # whole shell glows (lensed light wraps around the hole)
streak=0.65+0.35*np.sin(lat*95+fbm(p[m]*30,2,21)*3)
v=np.clip((0.55*arc+0.65*eq)*streak,0,1)
col[m]=tint(v,p[m],9)*(0.62+0.38*v)[:,None]; em[m]=0.8*v; rgh[m]=0.45
for nm_ in ('disk_top','disk_bot'):
    m=k==PARTS.index(nm_)
    rr=np.clip(A[m][:,0],0,1); ang=A[m][:,1]*2*np.pi
    rings=0.55+0.45*np.sin(rr*110+fbm(p[m]*22,3,8)*5)            # fine concentric streaks (Gargantua)
    gaps=0.75+0.25*np.sin(rr*23+1.3)
    doppler=0.72+0.28*np.cos(ang-np.pi)                            # one side brighter
    falloff=(1-rr)**0.9*ss(1.0,0.8,rr)
    v=np.clip((falloff*rings*gaps*doppler)*1.25+0.35*np.exp(-(rr/0.07)**2),0,1)
    col[m]=tint(v,p[m],7)*(0.42+0.58*np.clip(v*1.3,0,1))[:,None]*ss(1.02,0.9,rr)[:,None]+0.0; rgh[m]=0.45; em[m]=v; h[m]=0.15*rings
m=k==PARTS.index('disk_edge'); inner=A[m][:,0]<0.5
col[m]=np.where(inner[:,None],white,mauve*0.45); em[m]=np.where(inner,0.95,0.05)
if NOEM:
    mH=k==0; th=A[mH][:,0]; lx=B[mH][:,0]; lz=B[mH][:,1]
    chain=(th<0.022)&(lz<0.33)&(lx>0.16)&(lx<0.37); pend=chain&(lz<0.095)
    tip=ss(0.075,0.012,th)**0.8*(~chain)
    c=col[mH]; lav=np.array([0.84,0.76,1.0])*(0.9+0.12*fine[mH][:,None])
    c=c*(1-tip[:,None])+lav*tip[:,None]
    c[pend]=np.array([0.93,0.90,1.0]); col[mH]=c
    r=rgh[mH]; r=r*(1-tip)+0.30*tip; r[pend]=0.06; rgh[mH]=r
    mm=met[mH]; mm[pend]=0.0; met[mH]=mm
    for nm_ in ('disk_top','disk_bot'):
        m=k==PARTS.index(nm_); rr=np.clip(A[m][:,0],0,1); ang=A[m][:,1]*2*np.pi
        rings=0.5+0.5*np.sin(rr*110+fbm(p[m]*22,3,8)*5); gaps=0.7+0.3*np.sin(rr*23+1.3)
        doppler=0.80+0.20*np.cos(ang-np.pi)
        v=np.clip((0.45+0.55*rings)*gaps*doppler*(1-0.45*rr),0,1)
        col[m]=tint(v,p[m],7)*(0.35+0.65*v)[:,None]*ss(1.03,0.92,rr)[:,None]+np.array([0.02,0.02,0.03])
        rgh[m]=0.28+0.15*(1-rings); met[m]=0.0
    m=k==PARTS.index('halo'); lat=A[m][:,1]
    streak=0.6+0.4*np.sin(lat*95+fbm(p[m]*30,2,21)*3); eqb=np.exp(-((lat-0.5)/0.12)**2)
    v=np.clip((0.55+0.45*eqb)*streak,0,1)
    col[m]=tint(v,p[m],9)*(0.45+0.55*v)[:,None]; rgh[m]=0.3; met[m]=0.0
    m=k==PARTS.index('disk_edge'); inner=A[m][:,0]<0.5
    col[m]=np.where(inner[:,None],np.array([0.95,0.93,1.0]),mauve*0.5); rgh[m]=0.25
    em[:]=0.0
def img(vals,ch):
    im=np.zeros((S,S,ch)); im[idx]=vals.reshape(n,ch); return im
def dilate(im,it=10):
    im=im.copy(); mm=M.astype(float)
    for _ in range(it):
        acc=np.zeros_like(im); cnt=np.zeros(mm.shape)
        for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
            acc+=np.roll(np.roll(im*mm[...,None],dy,0),dx,1); cnt+=np.roll(np.roll(mm,dy,0),dx,1)
        new=(mm==0)&(cnt>0); im[new]=acc[new]/cnt[new][:,None]; mm[new]=1
    im[mm==0]=0; return im
def save(nm,arr,mode):
    a=(np.clip(arr,0,1)*255+.5).astype(np.uint8); Image.fromarray(a if a.shape[-1]>1 else a[...,0],mode).save(f'out/{nm}.png')
os.makedirs('out',exist_ok=True)
save(PRE+'Color',dilate(img(col,3)),'RGB'); save(PRE+'Metalness',dilate(img(met,1)),'L')
save(PRE+'Roughness',dilate(img(rgh,1)),'L'); save(PRE+'Emissive',dilate(img(em,1)),'L')
Hh=dilate(img(h,1))[...,0]
Hh=np.asarray(Image.fromarray((np.clip(Hh*0.5+0.5,0,1)*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)),float)/255
gx=(np.roll(Hh,-1,1)-np.roll(Hh,1,1))*0.5; gy=(np.roll(Hh,1,0)-np.roll(Hh,-1,0))*0.5
nm=np.stack([-gx*4,-gy*4,np.ones_like(Hh)],-1); nm/=np.linalg.norm(nm,axis=-1,keepdims=True)
save(PRE+'Normal',nm*0.5+0.5,'RGB')
mh=k==0; th_all=A[mh][:,0]
print('horn texels',mh.sum(),'chain share %.3f'%(((th_all<0.022)&(B[mh][:,1]<0.33)&(B[mh][:,0]>0.16)&(B[mh][:,0]<0.37)).mean()),'tip share %.3f'%((ss(0.045,0.006,th_all)>0.5).mean()))
