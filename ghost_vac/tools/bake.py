import numpy as np, os
from PIL import Image, ImageFilter
from noise import fbm, worley
S=1024
d=np.load('geo.npz'); P=d['P']; UV=d['UV']; NN=d['N']; PID=d['pid']
NAMES=['inner','smokewall','cloud','outline','ghost','top','bottom','bars','hose','conn','stock','gunbody','barrel','fins','funnel','handle','clips','strapL','strapR','chest','plate']
ID={k:i for i,k in enumerate(NAMES)}
R={'hose':(0.0,0.0,0.5,0.125)}
TY=1.10; GS=1.5; GZ0=-0.385; GX=-0.84
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
idx=np.where(M); p=pos[idx]; k=pid[idx]; n=len(p); nr=nrm[idx]; nr/=np.linalg.norm(nr,axis=1,keepdims=True)+1e-9
tu=(idx[1]+0.5)/S; tv=1-(idx[0]+0.5)/S
x,y,z=p[:,0],p[:,1],p[:,2]
ss=lambda e0,e1,t:(lambda q:q*q*(3-2*q))(np.clip((t-e0)/(e1-e0),0,1))
col=np.zeros((n,3)); met=np.zeros(n); rgh=np.full(n,0.5); em=np.zeros(n); h=np.zeros(n)
cyan=np.array([0.55,0.93,1.0])
th=np.degrees(np.arctan2(x,y-TY))            # tank angle, 0 = window centre (+Y, behind the character)
rr=np.hypot(x,y-TY)
def setp(m,c,mt,r,e=0.0,hh=0.0):
    def g(v,vec=False):
        if np.ndim(v)==(1 if vec else 0): return v
        return v if len(v)==m.sum() and len(v)!=n else v[m]
    col[m]=g(c,True); met[m]=g(mt); rgh[m]=g(r); em[m]=g(e); h[m]=g(hh)
def bolts_ring(zc,count,rad,th0=0):
    out=np.zeros(n)
    for a in np.arange(count)*360/count+th0:
        dth=((th-a+180)%360-180)*np.pi/180*0.5
        out=np.maximum(out,1-ss(0.6,1.0,np.hypot(dth/rad,(z-zc)/rad)))
    return out
noise1=fbm(p*9,3,2)
_low=fbm(p*3.0,3,21); _brush=fbm(p*np.array([60,60,4.0]),2,22); _sm=fbm(p*14,3,23)
_scr=np.abs(np.sin(fbm(p*np.array([7,7,7]),3,24)*55)); scratches=(1-ss(0.0,0.06,_scr))*ss(0.1,0.35,fbm(p*5,2,25)+0.2)
def metal(base,edge=None,grime=None):
    # dark worn metal: low-freq tint, brushed streaks, scratches, worn bright edges, grime in recesses
    c=np.asarray(base)*(0.82+0.22*_low[:,None]+0.06*_brush[:,None])
    r=np.clip(0.40+0.12*_sm-0.06*_brush,0.2,0.7)
    if grime is not None:
        c=c*(1-0.45*grime[:,None]); r=np.clip(r+0.2*grime,0,1)
    if edge is not None:
        bare=np.clip(edge*(0.6+0.6*_low),0,1)
        c=c*(1-bare[:,None])+np.array([0.58,0.60,0.63])*bare[:,None]; r=r-0.12*bare
    c=c*(1-0.6*scratches[:,None])+np.array([0.62,0.64,0.67])*0.6*scratches[:,None]; r=r-0.15*scratches
    return c,np.clip(r,0.15,0.8)
# ---------------- MACHINE BLOCKS ----------------
oct_face=np.round(th/45.0)*45.0          # octagon face centres every 45 deg, 0 = +Y
fx=(th-oct_face)/22.5                    # -1..1 across a face
for key,zl,zs,za in (('top',(0.50,0.60,0.68,0.72),0.62,0.75),('bottom',(-0.53,-0.63,-0.70,-0.82),-0.665,-0.60)):
    m=k==ID[key]
    gr=np.exp(-((z-(zl[-1] if key=='bottom' else zl[0]))/0.03)**2)
    seams=np.zeros(n)
    for zz in zl: seams=np.maximum(seams,np.exp(-((z-zz)/0.006)**2))
    edges=np.exp(-((np.abs(fx)-1)/0.06)**2)                 # facet edges: worn, lighter
    stripe=np.exp(-((z-zs)/0.012)**2)*(rr>0.45)              # light groove all around
    accent=(np.abs(fx)<0.55)&(np.abs(z-za)<0.03)&(np.abs(oct_face)<1)   # front accent plate
    lt=np.zeros(n)
    for f0 in (-90,90,180):
        lt=np.maximum(lt,1-ss(0.6,1.0,np.hypot(((th-f0)*np.pi/180*0.53)/0.022,(z-za)/0.022)))
    vent=np.zeros(n)
    if key=='bottom':
        vent=((np.abs(oct_face)==45)|(np.abs(oct_face)==135)).astype(float)*(np.abs(fx)<0.6)*((z>-0.81)&(z<-0.72))*(np.sin(z*260)>0.2)
    gauge=np.zeros(n)
    if key=='bottom':
        for gx_ in (-0.35,0,0.35): gauge=np.maximum(gauge,((np.abs(oct_face)<1)&(np.abs(fx-gx_)<0.14)&(np.abs(z+0.765)<0.03)).astype(float))
    c,rm=metal(np.array([0.20,0.22,0.25]),edge=np.clip(edges*1.2,0,1),grime=np.clip(seams+0.5*gr,0,1))
    c=c*(1-vent[:,None]*0.8)
    c[accent]=np.array([0.12,0.13,0.15])
    eT=np.clip(stripe+lt+gauge,0,1)
    c=c*(1-eT[:,None])+cyan*eT[:,None]
    setp(m,c,1.0*(1-eT),np.where(eT>0.3,0.2,rm),eT,0.4*edges-0.5*seams-0.4*vent+0.2*accent+0.15*scratches)
m=k==ID['bars']; cb,rb=metal(np.array([0.30,0.32,0.36]),edge=np.clip(np.abs(noise1)*0.6,0,1)); setp(m,cb,1.0,rb,0.0,0.15*scratches)
# ---------------- INNER WALL (seen through the window) ----------------
m=k==ID['inner']
t=ss(0.62,-0.45,z)   # 0 top -> 1 bottom
c1=np.array([0x14,0x26,0x3A])/255; c2=np.array([0x3D,0x7A,0x9E])/255; c3=np.array([0.45,0.88,1.0])
wall=np.where((t<0.5)[:,None],c1+(c2-c1)*(t/0.5)[:,None],c2+(c3-c2)*((t-0.5)/0.5)[:,None])
st=lambda c,w: np.exp(-((th-c)/w)**2)
hl=np.clip(0.7*st(150,5)+0.5*st(165,1.6)+0.6*st(-160,3)+0.4*st(-140,1.5),0,1)*ss(-0.3,-0.15,z)*(1-ss(0.5,0.62,z))
wall=wall*(1-0.65*hl[:,None])+np.array([0.85,0.95,1.0])*0.65*hl[:,None]
setp(m,wall,0.0,0.06,0.06+0.16*t,0.0)
# ---------------- SMOKE ----------------
for key in ('cloud','smokewall'):
    m=k==ID[key]; q=p[m]
    sw=fbm(q*7,4,10); wisps=np.abs(np.sin(fbm(q*4,3,30)*9))
    dd=np.clip(0.45+1.6*sw,0,1)**1.3*(0.5+0.5*wisps)
    if key=='cloud': dd=np.clip(0.25*dd+0.85*ss(GZ0-0.04,GZ0+0.08,q[:,2])**0.8,0,1)
    cc=np.array([0.22,0.50,0.70])*(1-dd[:,None])+np.array([0.82,0.97,1.0])*dd[:,None]
    col[m]=cc; met[m]=0; rgh[m]=1.0; em[m]=np.clip(0.45+0.35*dd,0,1); h[m]=0.3*dd
# ---------------- GHOST + OUTLINE ----------------
m=k==ID['outline']; setp(m,np.array([0x0F,0x1E,0x3D])/255,0.0,0.6,0.0,0.0)
m=k==ID['ghost']; q=p[m]
gx=q[:,0]/GS; gy=-(q[:,1]-TY)/GS; gz=(q[:,2]-GZ0)/GS+0.265
front=gy<-0.03
c=np.tile(np.array([0.98,0.99,1.0]),(m.sum(),1)); hem=1-ss(0.27,0.36,gz)
c=c*(1-hem[:,None]*0.45)+np.array([0.62,0.90,1.0])*hem[:,None]*0.45
e=np.zeros(m.sum()); r=np.full(m.sum(),0.42); hh=np.zeros(m.sum())
for sx in (-1,1):
    dch=np.hypot((gx-sx*0.095)/0.026,(gz-0.468)/0.018); ch=(1-ss(0.6,1.0,dch))*front
    c=c*(1-0.7*ch[:,None])+np.array([1.0,0.55,0.66])*0.7*ch[:,None]
eyes=np.zeros(m.sum()); hlg=np.zeros(m.sum())
for sx in (-1,1):
    de=np.hypot((gx-sx*0.058)/0.027,(gz-0.508)/0.037); eyes=np.maximum(eyes,(1-ss(0.92,1.0,de))*front)
    d1=np.hypot((gx-(sx*0.058-0.009))/0.0095,(gz-0.522)/0.0105); d2=np.hypot((gx-(sx*0.058+0.008))/0.0045,(gz-0.494)/0.0048)
    hlg=np.maximum(hlg,np.maximum(1-ss(0.75,1.0,d1),1-ss(0.7,1.0,d2))*front)
dm=np.hypot(gx,gz-0.478); mouth=(1-ss(0.0035,0.0060,np.abs(dm-0.020)))*(gz<0.474)*front
dark=np.maximum(eyes,mouth)
c=c*(1-dark[:,None])+np.array([0.035,0.045,0.08])*dark[:,None]; c=c*(1-hlg[:,None])+hlg[:,None]
col[m]=c; met[m]=0; rgh[m]=r*(1-dark)+0.08*dark; em[m]=e*(1-dark); h[m]=0.6*eyes+0.3*hlg-0.4*mouth
# ---------------- HOSE (rings along the length) ----------------
m=k==ID['hose']; u0,v0,u1,v1=R['hose']; lu=(tu[m]-u0)/(u1-u0)
ring=0.5+0.5*np.sin(lu*2*np.pi*26); ringm=ss(0.55,0.8,ring)
setp(m,np.array([0.07,0.075,0.085])*(1+1.1*ringm[:,None])*(0.9+0.2*_low[m][:,None]),0.0,0.72-0.12*ringm,0.0,0.6*ring)
m=k==ID['conn']; cc_,rc_=metal(np.array([0.34,0.36,0.40]),edge=np.clip(np.abs(noise1),0,1)); setp(m,cc_,1.0,rc_,0.0,0.1*scratches)
# ---------------- GUN ----------------
gth=np.degrees(np.arctan2(x-GX,y-TY)); gface=np.round(gth/45)*45; gfx=(gth-gface)/22.5
gedge=np.clip(1.2*np.exp(-((np.abs(gfx)-1)/0.07)**2),0,1)
# stock: side vents, top cap ring light, bolts
m=k==ID['stock']
vent=((np.abs(np.abs(gface)-90)<1)|(np.abs(np.abs(gface)-135)<1))&(np.abs(gfx)<0.6)&(z>0.66)&(z<0.88)&(np.sin(z*220)>0.25)
ringS=np.zeros(n)
bolt=np.zeros(n)
for gf in (-135,-45,45,135):
    for bz in (0.64,0.90):
        bolt=np.maximum(bolt,(np.abs(gface-gf)<1)*(1-ss(0.6,1.0,np.hypot(gfx/0.18,(z-bz)/0.014))))
c,rs=metal(np.array([0.19,0.21,0.24]),edge=gedge,grime=vent.astype(float)*0.6)
c=c*(1-0.8*vent[:,None]); c=c*(1-bolt[:,None])+np.array([0.55,0.57,0.6])*bolt[:,None]
c=c*(1-ringS[:,None])+cyan*ringS[:,None]
setp(m,c,1.0*(1-ringS),np.where(ringS>0.3,0.2,rs),ringS,0.3*gedge-0.4*vent+0.5*bolt+0.12*scratches)
# body: gauges on the 45 deg faces, LED strips on the side faces, panel seams
m=k==ID['gunbody']
gg=np.zeros(n)
for gz in (0.14,0.24,0.34):
    gg=np.maximum(gg,((np.abs(np.abs(gface)-45)<1)&(np.abs(gfx)<0.5)&(np.abs(z-gz)<0.035)).astype(float))
gpanel=((np.abs(np.abs(gface)-45)<1)&(np.abs(gfx)<0.7)&(z>0.08)&(z<0.40)).astype(float)
led=((np.abs(gface-90)<1)&(np.abs(gfx)<0.16)&(z>0.06)&(z<0.54)).astype(float)
seam=np.exp(-((z-0.46)/0.006)**2)+np.exp(-((z-0.04)/0.006)**2)
c,rg=metal(np.array([0.20,0.22,0.25]),edge=gedge,grime=np.clip(seam,0,1))
c=c*(1-gpanel[:,None])+np.array([0.06,0.07,0.08])*gpanel[:,None]
eG=np.clip(gg+led,0,1); c=c*(1-eG[:,None])+cyan*eG[:,None]
setp(m,c,1.0*(1-eG),np.where(eG>0.3,0.2,rg),eG,0.3*gedge-0.3*gpanel+0.2*gg-0.4*seam+0.12*scratches)
# barrel tube: dark with glowing slits between fins
m=k==ID['barrel']
slit=np.zeros(n)
c,rb=metal(np.array([0.13,0.14,0.16]))
c=c*(1-slit[:,None])+cyan*slit[:,None]
setp(m,c,1.0*(1-slit),rb,slit,-0.2*slit)
# fins: worn metal, glowing tips
m=k==ID['fins']
tip=np.zeros(n)
c,rf=metal(np.array([0.26,0.28,0.31]),edge=gedge)
c=c*(1-0.8*tip[:,None])+cyan*0.8*tip[:,None]
setp(m,c,1.0*(1-tip),rf,0.8*tip,0.3*gedge)
# emitter: glowing lip + core
m=k==ID['funnel']
core=(z<-0.96)&(np.hypot(x-GX,y-TY)<0.10)
lip=np.exp(-((z+0.86)/0.012)**2)
c,rf2=metal(np.array([0.24,0.26,0.29]),edge=gedge)
c=c*(1-lip[:,None])+cyan*lip[:,None]; c[core]=np.array([0.80,0.98,1.0])
eF=np.clip(lip+core,0,1)
setp(m,c,1.0*(1-eF),np.where(eF>0.3,0.2,rf2),eF,0.12*scratches)
m=k==ID['handle']; setp(m,np.array([0.06,0.065,0.075])*(0.9+0.2*_low[m][:,None]),0.0,0.72,0.0,0.25*fbm(p*60,2,7))
m=k==ID['clips']
lens=(y>TY+0.295)&(np.abs(z-0.42)<0.05)&(np.abs(x-GX)<0.025)
cc_,rc_=metal(np.array([0.24,0.26,0.30]),edge=np.clip(np.abs(noise1),0,1)); cc_[lens]=cyan
setp(m,cc_,np.where(lens,0.0,1.0),rc_,lens.astype(float),0.1*scratches)
# ---------------- STRAPS / PLATE ----------------
for key in ('strapL','strapR','chest'):
    m=k==ID[key]; q=p[m]
    if key=='chest':
        buckle=(np.abs(q[:,0])<0.075)
        across=np.abs(q[:,2]-0.38)
        stitch=((across>0.026)&(across<0.033)&(np.sin(q[:,0]*160)>0)).astype(float)*~buckle
    else:
        vv=(tv[m]%0.125)/0.125   # position around the rounded section (0..1)
        edge=np.minimum(np.abs(vv-0.0),np.minimum(np.abs(vv-0.5),np.abs(vv-1.0)))
        buckle=np.zeros(m.sum(),bool)
        stitch=((np.abs(vv-0.125)<0.02)|(np.abs(vv-0.375)<0.02)|(np.abs(vv-0.625)<0.02)|(np.abs(vv-0.875)<0.02)).astype(float)*(np.sin((q[:,0]+q[:,1]+q[:,2])*160)>0)
    fab=np.array([0.07,0.09,0.15])*(0.9+0.2*fbm(q*50,2,9)[:,None])
    c=fab*(1-stitch[:,None])+np.array([0.30,0.36,0.48])*stitch[:,None]
    c[buckle]=np.array([0.55,0.58,0.63])
    col[m]=c; met[m]=np.where(buckle,0.9,0.0); rgh[m]=np.where(buckle,0.3,0.85); em[m]=0; h[m]=0.4*stitch+0.5*buckle
m=k==ID['plate']
pb=np.zeros(n)
for bx in (-0.78,0.78):
    for bz in (-0.65,0.80):
        pb=np.maximum(pb,1-ss(0.6,1.0,np.hypot((x-bx)/0.02,(z-bz)/0.02)))
setp(m,np.array([0.16,0.17,0.20])*(1-pb[:,None])+np.array([0.55,0.58,0.63])*pb[:,None],0.8,0.4,0.0,0.6*pb)
# ---------------- write ----------------
def img(vals,ch):
    im=np.zeros((S,S,ch)); im[idx]=vals.reshape(n,ch); return im
def dilate(im,it=16):
    im=im.copy(); mm=M.astype(float)
    for _ in range(it):
        acc=np.zeros_like(im); cnt=np.zeros(mm.shape)
        for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
            acc+=np.roll(np.roll(im*mm[...,None],dy,0),dx,1); cnt+=np.roll(np.roll(mm,dy,0),dx,1)
        new=(mm==0)&(cnt>0); im[new]=acc[new]/cnt[new][:,None]; mm[new]=1
    im[mm==0]=0; return im
def save(name,arr,mode):
    a=(np.clip(arr,0,1)*255+.5).astype(np.uint8)
    Image.fromarray(a if a.shape[-1]>1 else a[...,0],mode).save(f'out/{name}.png')
os.makedirs('out',exist_ok=True)
save('GhostVac_Color',dilate(img(col,3)),'RGB')
save('GhostVac_Metalness',dilate(img(met,1)),'L'); save('GhostVac_Roughness',dilate(img(rgh,1)),'L'); save('GhostVac_Emissive',dilate(img(em,1)),'L')
H=dilate(img(h,1))[...,0]
H=np.asarray(Image.fromarray((np.clip(H*0.5+0.5,0,1)*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)),float)/255
gx_=(np.roll(H,-1,1)-np.roll(H,1,1))*0.5; gy_=(np.roll(H,1,0)-np.roll(H,-1,0))*0.5
nm=np.stack([-gx_*4,-gy_*4,np.ones_like(H)],-1); nm/=np.linalg.norm(nm,axis=-1,keepdims=True)
save('GhostVac_Normal',nm*0.5+0.5,'RGB')
print('coverage',M.mean(),'emissive coverage of mesh texels',(em>0.3).mean())
