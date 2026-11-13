import numpy as np, json
from PIL import Image
S=1024
ao=np.load('b_ao.npy'); pos=np.load('b_pos.npy'); nrm=np.load('b_nrm.npy'); part=np.round(np.load('b_part.npy')).astype(int)
meta=json.load(open('meta.json')); MW=np.array(meta['MW']); pcw=np.array(meta['pcw']); PR=meta['PR']
cov=np.load('b_alpha.npy')>0.5
ys,xs=np.mgrid[0:S,0:S]; U=(xs+0.5)/S; V=1-(ys+0.5)/S
hatreg=U<0.745
Mi=np.linalg.inv(MW); pc=pos@Mi[:3,:3].T+Mi[:3,3]          # canonical coords
def hash1(i,seed=0):
    x=np.sin(i*127.1+seed*311.7)*43758.5453; return x-np.floor(x)
def vnoise3(p,seed=0):
    i=np.floor(p); f=p-i; f=f*f*(3-2*f)
    def h(o): q=i+o; x=np.sin(q[...,0]*127.1+q[...,1]*311.7+q[...,2]*74.7+seed*19.19)*43758.5453; return x-np.floor(x)
    r=0
    for dx in (0,1):
        for dy in (0,1):
            for dz in (0,1):
                w=(f[...,0] if dx else 1-f[...,0])*(f[...,1] if dy else 1-f[...,1])*(f[...,2] if dz else 1-f[...,2])
                r=r+w*h(np.array([dx,dy,dz]))
    return r
def fbm(p,oc=4,seed=0):
    r=0;a=0.5;t=0
    for o in range(oc): r=r+a*vnoise3(p*2**o,seed+o); t+=a; a*=0.5
    return r/t
col=np.zeros((S,S,3)); rough=np.full((S,S),0.85); hgt=np.zeros((S,S))
# ---------- red velvet
red=hatreg&cov&(part==0)
n1=fbm(pos*2.2,4,1); n2=fbm(pos*14,3,5); n3=fbm(pos*70,2,9)
aoc=np.clip(ao,0,1)
light=0.5+0.5*(nrm[...,2]*0.75+nrm[...,1]*-0.35+nrm[...,0]*-0.2)          # soft baked top/front light
sh=np.clip(0.08+0.52*aoc**1.6+0.50*light**1.2,0,1.15)*(0.88+0.24*n1)
deep=np.array([0.20,0.008,0.012]); mid=np.array([0.60,0.035,0.03]); hi=np.array([0.86,0.11,0.07])
t=np.clip(sh,0,1)[...,None]
c=np.where(t<0.6,deep+(mid-deep)*(t/0.6),mid+(hi-mid)*np.clip((t-0.6)/0.4,0,1)**1.3)
c=c*(0.94+0.10*n2[...,None])*(0.97+0.06*n3[...,None])
col[red]=c[red]; rough[red]=0.78; hgt[red]=(n2*0.5+n3*0.5)[red]*0.25
# ---------- fur (band + pompom): layered zig-zag tufts + fibres
def vn2(x,y,seed=0):
    xi=np.floor(x); yi=np.floor(y); xf=x-xi; yf=y-yi; xf=xf*xf*(3-2*xf); yf=yf*yf*(3-2*yf)
    def h(a,b): v=np.sin(a*127.1+b*311.7+seed*74.7)*43758.5453; return v-np.floor(v)
    return (h(xi,yi)*(1-xf)+h(xi+1,yi)*xf)*(1-yf)+(h(xi,yi+1)*(1-xf)+h(xi+1,yi+1)*xf)*yf
def furshade(theta,z,seed=0,circ=4.9):
    x=theta/(2*np.pi)*circ                                   # arc length in studs
    wob=0.02*np.sin(z*23+x*5)                                # strands are not perfectly straight
    fine=vn2((x+wob)*150,z*9,seed); med=vn2((x+wob*2)*62,z*5+3,seed+1); big=vn2(x*17,z*4,seed+2)
    # tuft ends: soft sawtooth rows, different phase per medium column
    ph=vn2(x*40,0.5,seed+4)*5
    saw=(z/0.10+ph); saw=saw-np.floor(saw)
    tuft=0.40*fine+0.28*med+0.14*big+0.18*saw
    return tuft, fine
band=hatreg&cov&(part==1)
th=np.arctan2(pc[...,1],pc[...,0]); zc=-pc[...,2]+0.25*(np.hypot(pc[...,0],pc[...,1])-0.75)
tuft,fib=furshade(th,zc,0)
def furcol(tuft,fib,aoc,light):
    s=0.70+0.30*np.clip((tuft-0.25)/0.5,0,1)
    s=s*(0.66+0.34*aoc**0.9)*(0.86+0.18*light)
    s=np.clip(s*1.10,0,1)[...,None]
    shadow=np.array([0.48,0.51,0.61]); white=np.array([0.99,0.99,1.0])
    return shadow+(white-shadow)*s
c=furcol(tuft*0.5+0.25,fib,aoc,light)*np.array([0.93,0.93,0.95]); col[band]=c[band]; rough[band]=0.95; hgt[band]=(tuft*0.8+fib*0.2)[band]
pom=hatreg&cov&(part==2)
dv=pos-pcw; rr=np.linalg.norm(dv,axis=-1)+1e-9; thp=np.arctan2(dv[...,1],dv[...,0]); pol=np.arccos(np.clip(dv[...,2]/rr,-1,1))
tuft,fib=furshade(thp,pol*PR*1.2,5,circ=1.0)
c=furcol(tuft,fib,np.clip(aoc*1.15,0,1),light); col[pom]=c[pom]; rough[pom]=0.95; hgt[pom]=tuft[pom]
lin=hatreg&cov&(part==4); col[lin]=np.array([0.42,0.44,0.52]); rough[lin]=0.9
# dilate hat region into gutters (avoid seams)
def dilate(img,mask,n=10):
    img=img.copy(); m=mask.copy()
    for it in range(n):
        acc=np.zeros_like(img,dtype=float); cnt=np.zeros(m.shape)
        for dy,dx in ((0,1),(0,-1),(1,0),(-1,0)):
            sm=np.roll(m,(dy,dx),(0,1)); si=np.roll(img,(dy,dx),(0,1))
            acc+=si*(sm[...,None] if img.ndim==3 else sm); cnt+=sm
        new=(~m)&(cnt>0)
        if img.ndim==3: img[new]=acc[new]/cnt[new][:,None]
        else: img[new]=acc[new]/cnt[new]
        m=m|new
    return img
mk=hatreg&cov; fill=hatreg&~cov
for arr in (col,rough,hgt):
    d=dilate(arr,mk); arr[fill]=d[fill]
# ---------- strips (u 0.75..1): fur shards, undercap, hair
R=np.random.default_rng(2)
su=(U-0.75)/0.0625; sv_i=np.floor(su); uu=su-sv_i                 # column 0..3, uu 0..1 within column
strip=U>=0.75
def fibres(uu,vv,col_id,dens=(11,27,61)):
    s=0
    for k,(f,a) in enumerate(zip(dens,(0.5,0.3,0.2))):
        ph=hash1(col_id*7+k,3)*6.28
        s=s+a*np.sin(uu*f*2*np.pi+ph+np.sin(vv*(1.5+k)+ph)*0.25)
    return 0.5+0.5*s
# shards: v 0..0.125
sh_m=strip&(V<0.10); vv=V/0.095
fb=fibres(uu,vv,sv_i,(7,17,39))
s=np.clip(0.70+0.34*np.clip(vv,0,1)**0.7,0,1)*(0.93+0.07*fb)
shadow=np.array([0.50,0.53,0.62]); white=np.array([0.99,0.99,1.0])
c=shadow+(white-shadow)*np.clip(s,0,1)[...,None]
col[sh_m]=c[sh_m]; rough[sh_m]=0.95; hgt[sh_m]=fb[sh_m]*0.6
# undercap texels (u~.76-.78, v .02-.1) share the shard root tone: overwrite small patch
ucm=strip&(U<0.775)&(V<0.11)&(V>0.0)  # (kept as shard strip; undercap uses dark root part)
# base cap patch
cp=strip&(V>=0.10)&(V<0.13); col[cp]=np.array([0.90,0.91,0.94]); rough[cp]=0.6
# hair: 3 tone columns (inner dark -> outer bright), root at the top of the strip
hm_=strip&(V>=0.13); cf=(U-0.75)/0.0833; ci=np.floor(cf); uu3=cf-ci; s_=np.clip(1-(V-0.134)/0.862,0,1)
tone=np.choose(np.clip(ci,0,2).astype(int),[0.74,0.88,1.0])
fb=fibres(uu3,s_*2.0,ci,(4,9,19))
ridge=np.exp(-((uu3-0.5)/0.22)**2); edge=np.abs(uu3-0.5)*2
root=np.clip(1-s_/0.35,0,1)**1.3
val=tone*(0.86+0.08*fb+0.05*ridge)*(1-0.20*edge**3)*(1-0.22*root)
val=np.clip(val,0,1)[...,None]
shadow=np.array([0.46,0.49,0.58]); white=np.array([0.99,0.99,1.0])
c=shadow+(white-shadow)*val
col[hm_]=c[hm_]; rough[hm_]=0.55; hgt[hm_]=(fb*0.7+ridge*0.3)[hm_]
# ---------- normal map from height
gy,gx=np.gradient(hgt); k=2.2
k_map=np.where(strip,1.6,np.where(part==0,1.2,3.0))
nx=-gx*k_map; ny=gy*k_map; nz=np.ones_like(nx); l=np.sqrt(nx*nx+ny*ny+nz*nz)
nm=np.stack([nx/l*0.5+0.5,ny/l*0.5+0.5,nz/l*0.5+0.5],-1)
sv=lambda a,n: Image.fromarray((np.clip(a,0,1)*255).astype(np.uint8)).save(n)
sv(col,'SantaHair_Color.png'); sv(rough,'SantaHair_Roughness.png'); sv(nm,'SantaHair_Normal.png'); sv(np.zeros((S,S)),'SantaHair_Metalness.png')
