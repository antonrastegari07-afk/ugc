# Procedural themed textures (Nebula, Ocean) on the same atlas layout as export10 (4 direction swatches + black outline band)
import sys,os,shutil,numpy as np
from PIL import Image
from scipy.ndimage import zoom, gaussian_filter, map_coordinates
OUT='/home/user/ugc/Horns_Iridescent'
SW=[(6+(d%2)*510, 6+(d//2)*390, 500, 380) for d in range(4)]   # d: +X right, -X left, +Y back, -Y front
def H(c): return np.array([int(c[i:i+2],16)/255 for i in (1,3,5)])
def vnoise(h,w,cell,rng):
    g=rng.random((h//cell+3,w//cell+3)); z=zoom(g,cell,order=3)[:h,:w]; return (z-z.min())/(np.ptp(z)+1e-9)
def fbm(h,w,rng,base=96,oct=5):
    s=np.zeros((h,w)); a=1; tot=0
    for o in range(oct):
        c=max(2,base>>o); s+=a*vnoise(h,w,c,rng); tot+=a; a*=0.55
    return s/tot
def warp(f,h,w,rng,amt=40,base=128):
    dx=(fbm(h,w,rng,base)-0.5)*2*amt; dy=(fbm(h,w,rng,base)-0.5)*2*amt
    yy,xx=np.mgrid[0:h,0:w]; return map_coordinates(f,[np.clip(yy+dy,0,h-1),np.clip(xx+dx,0,w-1)],order=1)
def ramp(t,stops):
    t=np.clip(t,0,1)[...,None]; pos=np.linspace(0,1,len(stops)); out=np.zeros(t.shape[:-1]+(3,))
    for i in range(len(stops)-1):
        a,b=pos[i],pos[i+1]; m=((t>=a)&(t<=b))[...,0]; f=((t[...,0]-a)/(b-a))[m][:,None]
        out[m]=H(stops[i])*(1-f)+H(stops[i+1])*f
    return out
def nebula(h,w,seed,stops,star_tint):
    rng=np.random.default_rng(seed)
    gas=warp(fbm(h,w,rng,110),h,w,rng,55,140); gas2=warp(fbm(h,w,rng,60),h,w,rng,30,90)
    dens=np.clip((gas*0.75+gas2*0.45-0.38)*1.9,0,1)            # cloud density
    col=ramp(dens,stops)
    core=np.clip((dens-0.72)*3.5,0,1)[...,None]; col=col*(1-core*0.5)+core*0.5*np.array([1,0.92,1])  # bright cores
    stars=np.zeros((h,w))
    for n,sz,amp in [(260,0.6,1.0),(40,1.6,1.0),(9,3.0,1.0)]:
        ys=rng.integers(0,h,n); xs=rng.integers(0,w,n); m=np.zeros((h,w)); m[ys,xs]=amp; stars=np.maximum(stars,np.clip(gaussian_filter(m,sz)*(sz*sz*6.0),0,1))
    col=np.clip(col+stars[...,None]*H(star_tint)[None,None,:]*1.1,0,1)
    emis=np.clip(stars*1.0+core[...,0]*0.8+dens*0.18,0,1)        # stars + cloud cores glow, dark space does not
    rough=np.clip(0.55-stars*0.3,0.2,1)
    return col,emis,rough
def ocean(h,w,seed,stops):
    rng=np.random.default_rng(seed)
    f=warp(fbm(h,w,rng,120),h,w,rng,70,150); f=warp(f,h,w,rng,35,80)            # swirling liquid
    base=ramp(f,stops)
    c1=np.abs(warp(fbm(h,w,rng,70),h,w,rng,25,60)-0.5); caust=np.clip(1-c1/0.05,0,1)**2   # thin caustic lines
    c2=np.abs(f-0.62); swirl=np.clip(1-c2/0.035,0,1)**1.5                                   # white swirl crest
    hl=np.clip(caust*0.85+swirl,0,1)
    col=np.clip(base*(1-hl[...,None]*0.85)+hl[...,None]*np.array([0.92,0.98,1.0]),0,1)
    emis=np.clip(hl*1.0+np.clip(f-0.55,0,1)*0.6,0,1)              # highlights glow, deep water stays dark
    rough=np.clip(0.18+0.15*(1-hl),0,1)                            # glossy water
    return col,emis,rough
THEMES={
 'nebula':{'fn':nebula,'dirs':[
    (['#05030F','#1B0B4A','#5A1FA8','#FF4FD8','#FFD6F8'],'#BFF4FF'),
    (['#04040F','#0B1E5A','#1F6BD8','#4FF0FF','#E6FFFF'],'#FFD6F8'),
    (['#06030C','#2A0B3F','#A21F8A','#FF7A5A','#FFE6C8'],'#D6E8FF'),
    (['#03030D','#140B4F','#4B2BD8','#B57BFF','#F2E6FF'],'#FFF2C8')]},
 'ocean':{'fn':ocean,'dirs':[
    ['#0A3C8C','#1466D8','#3AA0FF','#9ADFFF'],
    ['#0A4C80','#0C98C0','#2ED8EE','#B8F8FF'],
    ['#1A3AA8','#2F62F0','#6AA0FF','#D4E6FF'],
    ['#0A4C70','#0E8CB8','#22C0DC','#A6F0F6']]},
}
for name,T in THEMES.items():
    d=f'{OUT}/{name}'; os.makedirs(d,exist_ok=True)
    img=np.zeros((1024,1024,3)); em=np.zeros((1024,1024)); ro=np.ones((1024,1024))
    for k,(x,y,w,h) in enumerate(SW):
        if name=='nebula': stops,st=T['dirs'][k]; c,e,r=nebula(h,w,100+k,stops,st)
        else: c,e,r=ocean(h,w,200+k,T['dirs'][k])
        img[y:y+h,x:x+w]=c; em[y:y+h,x:x+w]=e; ro[y:y+h,x:x+w]=r
    img[776:,:]=0; em[776:,:]=0; ro[776:,:]=1          # outline band: pure black, matte, no glow
    Image.fromarray((img*255).astype(np.uint8)).save(f'{d}/Horns_{name}_Color.png')
    Image.fromarray((em*255).astype(np.uint8)).save(f'{d}/Horns_{name}_Emissive.png')
    Image.fromarray((img*em[...,None]*255).astype(np.uint8)).save(f'{d}/Horns_{name}_EmissiveColor.png')
    Image.fromarray((ro*255).astype(np.uint8)).save(f'{d}/Horns_{name}_Roughness.png')
    Image.fromarray(np.zeros((1024,1024),np.uint8)).save(f'{d}/Horns_{name}_Metalness.png')
    for suf in ['','_NoOutline']:
        for ext in ['fbx','obj']: shutil.copy(f'{OUT}/holo/Horns_holo{suf}.{ext}',f'{d}/Horns_{name}{suf}.{ext}')
    print(name,'done')
