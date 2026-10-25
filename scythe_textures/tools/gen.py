import numpy as np
from PIL import Image
from mesh import load
from noise import perlin, fbm, worley
S=1024
g=np.load('gbuf.npz'); M=g['mask']
V,T,N,F=load(__import__('os').path.join(__import__('os').path.dirname(__file__),'..','..','save obj SCYTHE.obj'))
c=V.mean(0); _,_,R=np.linalg.svd(V-c,full_matrices=False)
if np.linalg.det(R)<0: R[2]*=-1
LV=(V-c)@R.T
# shaft centerline per x-bin
bins=np.linspace(LV[:,0].min(),LV[:,0].max(),40); cy=[];cz=[];bx=[]
for a,b in zip(bins[:-1],bins[1:]):
    s=(LV[:,0]>=a)&(LV[:,0]<b)&(np.abs(LV[:,1])<0.5)
    if s.sum()>3: bx.append((a+b)/2); cy.append(np.median(LV[s,1])); cz.append(np.median(LV[s,2]))
bx,cy,cz=map(np.array,(bx,cy,cz))
ao_v=np.load('ao_v.npy')
idx=np.where(M)
P=(g['pos'][idx]-c)@R.T
Nw=g['nrm'][idx]; Nw/=np.linalg.norm(Nw,axis=1,keepdims=True)
Tw=g['tg'][idx]; Bw=g['bt'][idx]
Tw=Tw-(Tw*Nw).sum(1,keepdims=True)*Nw; Tw/=np.linalg.norm(Tw,axis=1,keepdims=True)+1e-9
hand=np.sign((np.cross(Nw,Tw)*Bw).sum(1)); hand[hand==0]=1
Bo=np.cross(Nw,Tw)*hand[:,None]
Tl=Tw@R.T; Bl=Bo@R.T; Nl=Nw@R.T
fid=g['fid'][idx]; bary=g['bary'][idx]
AO=(bary*ao_v[F[fid,:,0]]).sum(1)
ss=lambda e0,e1,x: (lambda t: t*t*(3-2*t))(np.clip((x-e0)/(e1-e0),0,1))

def fields(p):
    x,y,z=p[...,0],p[...,1],p[...,2]
    ycen=np.interp(x,bx,cy); zcen=np.interp(x,bx,cz)
    head=np.maximum(ss(0.2,0.9,x), ss(-0.35,-0.6,y))
    shaft=1-head
    out={}
    # --- head: cellular ornament
    q=p*np.array([3.2,3.2,3.2])+0.6*np.stack([fbm(p*1.3,2,s) for s in (1,2,3)],-1)
    F1,F2,ID=worley(q,5)
    edge=F2-F1
    ridge=1-ss(0.0,0.10,edge)
    sel=(ID<0.42)*(1-ss(-1.3,-1.9,y))
    pocket=ss(0.16,0.30,edge)*sel
    gem=ss(0.22,0.42,edge)*sel
    # --- engraved scrollwork everywhere
    w=fbm(p*np.array([1.8,3.5,3.5]),3,20)
    lines=np.abs(np.sin(w*28.0))
    groove=1-ss(0.0,0.22,lines)
    # --- shaft twisted ribs
    ang=np.arctan2(z-zcen,y-ycen)
    tw=np.sin(x*9.0+2*ang)
    rib=ss(0.3,0.9,tw)
    bandpos=np.abs(np.sin(x*2.2+0.4))  # decorative rings
    ring=1-ss(0.0,0.08,bandpos)
    out['head']=head; out['ridge']=ridge*head; out['pocket']=pocket*head; out['gem']=gem*head
    out['groove']=groove*(1-0.6*head*pocket)
    out['rib']=rib*shaft; out['ring']=ring*shaft
    fine=fbm(p*14.0,3,40)
    out['fine']=fine
    out['height']=(0.55*out['ridge'] - 0.7*out['pocket'] + 0.35*out['gem']
                   - 0.45*out['groove'] + 0.6*out['rib'] + 0.5*out['ring'] + 0.06*fine)
    return out

def chunked(fn,P,n=60000):
    res=[fn(P[i:i+n]) for i in range(0,len(P),n)]
    return {k:np.concatenate([r[k] for r in res]) for k in res[0]}
f=chunked(fields,P)
e=0.004
hT=chunked(lambda p: {'h':fields(p)['height']},P+e*Tl)['h']
hB=chunked(lambda p: {'h':fields(p)['height']},P+e*Bl)['h']
k=0.018
dT=(hT-f['height'])/e*k; dB=(hB-f['height'])/e*k
nt=np.stack([-dT,-dB,np.ones_like(dT)],-1); nt/=np.linalg.norm(nt,axis=1,keepdims=True)

# --- material composition
gold=np.array([236,176,58])/255; goldHi=np.array([255,214,112])/255; goldDk=np.array([96,56,8])/255
gemCol=np.array([255,226,120])/255
t=np.clip(0.5+0.5*f['fine']*1.5,0,1)[:,None]
alb=gold*(0.88+0.12*t)
alb=alb*(1-f['ridge'][:,None])+goldHi*f['ridge'][:,None]
alb=alb*(1-0.35*f['rib'][:,None])+goldHi*0.35*f['rib'][:,None]
alb=alb*(1-0.7*f['groove'][:,None])+goldDk*0.7*f['groove'][:,None]
cav=np.clip(1-AO,0,1)[:,None]
alb=alb*(1-0.55*cav)+goldDk*0.55*cav
pk=f['pocket'][:,None]
gemEdge=np.array([226,128,22])/255
gc=gemEdge+(gemCol-gemEdge)*f['gem'][:,None]
alb=alb*(1-pk)+gc*pk
alb=np.clip(alb,0,1)
metal=np.clip(1-0.9*f['pocket']-0.15*f['groove'],0,1)
rough=np.clip(0.24+0.06*f['fine']+0.30*f['groove']-0.10*f['ridge']-0.08*f['rib']+0.15*cav[:,0],0.08,1)
rough=rough*(1-f['pocket'])+0.18*f['pocket']
emis=np.clip(f['gem']*0.75+0.35*f['pocket']+0.10*f['groove']*f['head']*(1-f['pocket']),0,1)
emis=np.clip(emis*(0.7+0.3*AO+0.0),0,1)

def to_img(vals,ch):
    im=np.zeros((S,S,ch)); im[idx]=vals.reshape(len(P),ch); return im
def dilate(im,mask,it=12):
    im=im.copy(); m=mask.copy().astype(float)
    for _ in range(it):
        acc=np.zeros_like(im); cnt=np.zeros(m.shape)
        for dy,dx in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)):
            acc+=np.roll(np.roll(im*m[...,None],dy,0),dx,1); cnt+=np.roll(np.roll(m,dy,0),dx,1)
        new=(m==0)&(cnt>0)
        im[new]=acc[new]/cnt[new][:,None]; m[new]=1
    # fill remaining with mean
    im[m==0]=im[m>0].mean(0)
    return im
def save(name,vals,ch,srgb=False,normal=False):
    im=dilate(to_img(vals,ch),M)
    if srgb: im=np.where(im<=0.0031308,12.92*im,1.055*np.power(np.clip(im,0,1),1/2.4)-0.055)
    if normal: im=im*0.5+0.5
    a=(np.clip(im,0,1)*255+0.5).astype(np.uint8)
    Image.fromarray(a if ch==3 else a[...,0],'RGB' if ch==3 else 'L').save(f'out/{name}.png')
import os; os.makedirs('out',exist_ok=True)
# albedo values above treated as linear colors
save('Scythe_Color',alb,3)
save('Scythe_Normal',nt,3,normal=True)
save('Scythe_Metalness',metal[:,None],1)
save('Scythe_Roughness',rough[:,None],1)
save('Scythe_Emissive',emis[:,None],1)
print('done')
