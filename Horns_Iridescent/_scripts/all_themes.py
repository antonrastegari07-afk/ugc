# All themes for the 6-direction geometry: textures (Color, Roughness, Metalness, Emissive, EmissiveColor) + FBX/OBJ (outline / no outline)
import sys,os,colorsys,numpy as np; sys.path.insert(0,'tools')
from fbxio import read,write,child
from PIL import Image
from scipy.ndimage import zoom, gaussian_filter, map_coordinates
SRC='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/807479b3-HornsBlackHole_UGC.fbx'
OUT='/home/user/ugc/Horns_Iridescent'
SW=[(6+(d%3)*340, 6+(d//3)*390, 332, 380) for d in range(6)]
AZ=lambda d: ((d//2)+3*(d%2))%6        # swatch d -> azimuth index 0..5 (30,90,...,330 deg); index 4 = front
def H(c): return np.array([int(c[i:i+2],16)/255 for i in (1,3,5)]) if isinstance(c,str) else np.array(c,float)
def hsv(h,s,v): return np.array(colorsys.hsv_to_rgb((h/360)%1,s,v))
# ---------------- noise helpers
def vnoise(h,w,cell,rng):
    g=rng.random((h//cell+3,w//cell+3)); z=zoom(g,cell,order=3)[:h,:w]; return (z-z.min())/(np.ptp(z)+1e-9)
def fbm(h,w,rng,base=96,octv=5):
    s=np.zeros((h,w)); a=1; t=0
    for o in range(octv): s+=a*vnoise(h,w,max(2,base>>o),rng); t+=a; a*=0.55
    return s/t
def warp(f,rng,amt=40,base=128):
    h,w=f.shape; dx=(fbm(h,w,rng,base)-0.5)*2*amt; dy=(fbm(h,w,rng,base)-0.5)*2*amt
    yy,xx=np.mgrid[0:h,0:w]; return map_coordinates(f,[np.clip(yy+dy,0,h-1),np.clip(xx+dx,0,w-1)],order=1)
def ramp(t,stops):
    t=np.clip(t,0,1); pos=np.linspace(0,1,len(stops)); C=np.array([H(c) for c in stops])
    return np.stack([np.interp(t,pos,C[:,i]) for i in range(3)],-1)
def lines(f,width): return np.clip(1-np.abs(f-0.5)/width,0,1)
def dots(h,w,rng,spec):
    m=np.zeros((h,w))
    for n,sz in spec:
        z=np.zeros((h,w)); z[rng.integers(0,h,n),rng.integers(0,w,n)]=1; m=np.maximum(m,np.clip(gaussian_filter(z,sz)*sz*sz*6,0,1))
    return m
def vgrad(h,w): return np.repeat(np.linspace(0,1,h)[:,None],w,1)       # 0 top (tip side) -> 1 bottom
def cells(h,w,rng,n):
    P=np.c_[rng.random(n)*h,rng.random(n)*w]; yy,xx=np.mgrid[0:h,0:w]; D=np.sort(np.stack([np.hypot(yy-p[0],xx-p[1]) for p in P]),0)
    return D[1]-D[0]
lum=lambda c: 0.2126*c[...,0]+0.7152*c[...,1]+0.0722*c[...,2]
# ---------------- generators: return colour, emissive(0-1), roughness(0-1), metalness(0-1)
def g_basic(h,w,rng,stops):
    t=vgrad(h,w); col=ramp(t,stops); yy,xx=np.mgrid[0:h,0:w]
    col=np.clip(col*(0.88+0.12*np.sign(np.sin((xx+yy)*2*np.pi/7)))[...,None]*1.05,0,1)
    em=np.clip(0.42/np.maximum(lum(col),1e-3),0,1); return col,em,np.full((h,w),0.65),np.zeros((h,w))
def g_nebula(h,w,rng,p):
    stops,star=p; gas=warp(fbm(h,w,rng,110),rng,55,140); gas2=warp(fbm(h,w,rng,60),rng,30,90)
    dens=np.clip((gas*0.75+gas2*0.45-0.38)*1.9,0,1); col=ramp(dens,stops)
    core=np.clip((dens-0.72)*3.5,0,1); col=col*(1-core[...,None]*0.5)+core[...,None]*0.5
    st=dots(h,w,rng,[(200,0.6),(30,1.5),(7,2.8)]); col=np.clip(col+st[...,None]*H(star)*1.1,0,1)
    return col,np.clip(st+core*0.8+dens*0.18,0,1),np.clip(0.55-st*0.3,0.2,1),np.zeros((h,w))
def g_ocean(h,w,rng,stops):
    f=warp(warp(fbm(h,w,rng,120),rng,70,150),rng,35,80); base=ramp(f,stops)
    caust=lines(warp(fbm(h,w,rng,70),rng,25,60),0.05)**2; swirl=np.clip(1-np.abs(f-0.62)/0.035,0,1)**1.5
    hl=np.clip(caust*0.85+swirl,0,1); col=np.clip(base*(1-hl[...,None]*0.85)+hl[...,None]*np.array([0.92,0.98,1]),0,1)
    return col,np.clip(hl+np.clip(f-0.55,0,1)*0.6,0,1),np.clip(0.18+0.15*(1-hl),0,1),np.zeros((h,w))
def g_lava(h,w,rng,p):
    vein_c,rock_c=p; rock=fbm(h,w,rng,70); v=warp(fbm(h,w,rng,90),rng,40,110)
    veins=np.clip(lines(v,0.06)*1.2,0,1)**1.3; veins=np.maximum(veins,lines(warp(fbm(h,w,rng,45),rng,20,60),0.035)*0.8)
    glow=gaussian_filter(veins,3)*1.4
    col=ramp(rock*0.8,[rock_c,'#2A1410','#140808'])*(0.6+0.4*rock[...,None])
    vc=H(vein_c); hot=np.clip(veins*1.2,0,1)[...,None]
    col=np.clip(col*(1-hot)+hot*(vc*0.85+0.15)+np.clip(glow,0,1)[...,None]*vc*0.35,0,1)
    return col,np.clip(veins*1.1+glow*0.4,0,1),np.clip(0.9-veins*0.4,0,1),np.zeros((h,w))
def g_frost(h,w,rng,stops):
    t=vgrad(h,w)*0.6+fbm(h,w,rng,100)*0.4; base=ramp(t,stops)
    c=cells(h,w,rng,45); cr=np.clip(1-c/5.0,0,1)**1.5; fine=lines(warp(fbm(h,w,rng,40),rng,15,40),0.03)*0.6
    sp=dots(h,w,rng,[(160,0.5),(25,1.2)]); edge=np.clip(cr+fine,0,1)
    col=np.clip(base*(1-edge[...,None]*0.45)+edge[...,None]*0.45*np.array([0.95,1,1])+sp[...,None]*0.8,0,1)
    return col,np.clip(edge*0.7+sp+0.12,0,1),np.clip(0.15+0.25*(1-edge),0,1),np.zeros((h,w))
def g_radio(h,w,rng,p):
    goo_c,dark_c=p; g=warp(fbm(h,w,rng,90),rng,45,110); goo=np.clip((g-0.42)*3.2,0,1)
    yy,xx=np.mgrid[0:h,0:w]; bub=np.zeros((h,w))
    for _ in range(26):
        cy,cx,r=rng.random()*h,rng.random()*w,4+rng.random()*13; d=np.hypot(yy-cy,xx-cx)
        bub=np.maximum(bub,np.clip(1-np.abs(d-r)/1.6,0,1)*(goo>0.3))
    col=ramp(goo,[dark_c,H(goo_c)*0.55,goo_c,'#F8FFD0']); col=np.clip(col+bub[...,None]*0.6,0,1)
    return col,np.clip(goo*0.9+bub,0,1),np.clip(0.35-goo*0.2,0.1,1),np.zeros((h,w))
def g_vapor(h,w,rng,stops):
    t=vgrad(h,w); col=ramp(t+0.06*(fbm(h,w,rng,120)-0.5),stops)
    yy,xx=np.mgrid[0:h,0:w]; scan=(np.sin(yy*2*np.pi/6)>0.55).astype(float)
    grid=np.clip((np.abs(((xx+0.0)%40)-20)<1.0)*(t>0.6)+(np.abs((yy%26)-13)<0.8)*(t>0.6),0,1)
    col=np.clip(col*(1-0.35*scan[...,None])+grid[...,None]*0.55,0,1)
    return col,np.clip((0.55-0.4*scan)+grid*0.6,0,1),np.full((h,w),0.45),np.zeros((h,w))
def g_void(h,w,rng,neon):
    smoke=warp(fbm(h,w,rng,100),rng,50,130); col=ramp(smoke,['#020205','#0B0616','#1A0C2E'])
    n1=lines(warp(fbm(h,w,rng,80),rng,35,90),0.025); n2=lines(warp(fbm(h,w,rng,50),rng,20,60),0.018)*0.7
    neonm=np.clip(n1+n2,0,1); glow=np.clip(gaussian_filter(neonm,4)*2.0,0,1)
    nc=H(neon); col=np.clip(col+neonm[...,None]*nc+glow[...,None]*nc*0.35,0,1)
    return col,np.clip(neonm+glow*0.4,0,1),np.full((h,w),0.6),np.zeros((h,w))
def g_candy(h,w,rng,stops):
    f=warp(fbm(h,w,rng,140),rng,60,160); col=ramp(f*0.7+vgrad(h,w)*0.3,stops)
    sp=dots(h,w,rng,[(120,0.6),(20,1.4)]); col=np.clip(col*1.02+sp[...,None]*0.9,0,1)
    return col,np.clip(0.55+sp,0,1),np.clip(0.4-sp*0.2,0,1),np.zeros((h,w))
def g_royal(h,w,rng,p):
    base_c,vein_c=p; m=warp(fbm(h,w,rng,110),rng,60,140)
    veins=np.clip(lines(m,0.05)+lines(warp(fbm(h,w,rng,60),rng,25,70),0.025)*0.7,0,1)
    base=ramp(fbm(h,w,rng,150),[H(base_c)*0.6,base_c,H(base_c)*0.85+0.15])
    vc=H(vein_c); col=np.clip(base*(1-veins[...,None])+veins[...,None]*vc,0,1)
    return col,np.clip(veins*0.8,0,1),np.clip(0.3-veins*0.12,0.1,1),np.clip(veins*0.85,0,1)
def wheel(hues,s=(0.55,1,1),v=(1,1,0.95),shift=28):
    return [[hsv(hh,s[0],v[0]),hsv(hh,s[1],v[1]),hsv(hh+shift,s[2],v[2])] for hh in hues]
def grad3(c):   # 3-stop gradient from one main colour: lighter top -> colour -> deeper/hue-shifted bottom
    c=H(c); h,sat,v=colorsys.rgb_to_hsv(*c); return [np.clip(c*0.55+0.45,0,1),c,np.array(colorsys.hsv_to_rgb((h+0.06)%1,min(1,sat*1.05),v*0.82))]
THEMES={   # 6 CLEARLY DIFFERENT colours per theme, listed in azimuth order (index 4 = front)
 'holo':   (g_basic,[grad3(c) for c in ['#00E5FF','#3D4BFF','#FF2BD6','#FF3030','#FFE600','#2BFF4F']]),
 'galaxy': (g_basic,[grad3(c) for c in ['#00E5FF','#2B4BFF','#8A2BFF','#FF2BD6','#FF6B6B','#FFD65A']]),
 'toxic':  (g_basic,[grad3(c) for c in ['#7CFF00','#FFF000','#FF8A00','#B026FF','#00E5FF','#00FF9C']]),
 'inferno':(g_basic,[grad3(c) for c in ['#FFE600','#FF8A00','#FF1A1A','#FF2B9A','#8A2BFF','#4FC8FF']]),
 'nebula': (g_nebula,[(['#05030F','#2A0B4A','#B01FA8','#FF4FD8','#FFE0FA'],'#BFF4FF'),(['#03050F','#0B2A5A','#1F8BD8','#4FF0FF','#E6FFFF'],'#FFD6F8'),
                      (['#0A0503','#3F1A0B','#D8701F','#FFC24F','#FFF4D6'],'#D6E8FF'),(['#05030F','#1A0B5A','#5A2BD8','#A67BFF','#F2E6FF'],'#FFF2C8'),
                      (['#030A06','#0B3A2A','#1FA870','#5AFFB0','#E6FFF2'],'#FFD6F8'),(['#0A0305','#4A0B1A','#D81F3A','#FF6B5A','#FFE0D6'],'#BFF4FF')]),
 'ocean':  (g_ocean,[['#0A3C8C','#1466D8','#3AA0FF','#9ADFFF'],['#06606A','#0CA8A8','#2EE8D8','#B8FFF6'],['#0A6A4A','#14B884','#4FF0B0','#D0FFE8'],
                     ['#5A7A9A','#A8C8E0','#E0F0FF','#FFFFFF'],['#9A2A3A','#FF5A6A','#FF9A8A','#FFE0D6'],['#1A0A6A','#3A1AB8','#6A5AF0','#C8C0FF']]),
 'lava':   (g_lava,[('#FFE45A','#3A1A10'),('#FF8A00','#3A1A10'),('#FF1A1A','#2E1010'),('#FF2B9A','#2E1018'),('#9A3BFF','#1A1028'),('#4FC8FF','#101A28')]),
 'frost':  (g_frost,[['#9AE8FF','#3AB8FF','#1A7AE0','#0A4AA8'],['#F4F8FF','#D0D8E8','#A8B4C8','#7A8AA0'],['#D8C2FF','#A07AFF','#7A4BF0','#4A1AB8'],
                     ['#B8FFE4','#4FE8B0','#14C088','#0A8A60'],['#8AA0FF','#3A4BF0','#1A1AB8','#0A0A6A'],['#FFC8EA','#FF7AC8','#E83B9A','#A8146A']]),
 'radioactive':(g_radio,[('#7CFF00','#0A1A04'),('#FFF000','#1A1804'),('#00E5FF','#041A1A'),('#B026FF','#120418'),('#FF8A00','#1A0E04'),('#FF2B9A','#1A0410')]),
 'vaporwave':(g_vapor,[['#FF71CE','#FF2B9A','#B0006A'],['#01CDFE','#0A8AFF','#2B2BB8'],['#B967FF','#7A2BFF','#3A0B8A'],
                       ['#FFFB96','#FFD000','#FF8A00'],['#05FFA1','#00C88A','#007A6A'],['#FFB86A','#FF6A3D','#C8203A']]),
 'void':   (g_void,['#B026FF','#FF1A3C','#00E5FF','#39FF14','#FFC400','#FF2BD6']),
 'candy':  (g_candy,[['#FFC2E2','#FF8FC8','#FF5AA8'],['#B8FFE0','#6AF0B8','#2ED894'],['#DCC8FF','#B08AFF','#8A5AFF'],
                     ['#C2E2FF','#7ABEFF','#3D9AFF'],['#FFD8C2','#FFA87A','#FF7A4A'],['#FFF6B8','#FFE85A','#FFD000']]),
 'royal':  (g_royal,[('#E8B84A','#FFF4D0'),('#F4EAD0','#C8962A'),('#4A1A8A','#F0C860'),('#0E0C10','#E8B040'),('#0E5A3A','#F0C860'),('#8A0E2A','#F0C860')]),
}
def build_textures(name,gen,params):
    img=np.zeros((1024,1024,3)); em=np.zeros((1024,1024)); ro=np.ones((1024,1024)); me=np.zeros((1024,1024))
    for d,(x,y,w,h) in enumerate(SW):
        rng=np.random.default_rng(1000+17*d+len(name)); c,e,r,m=gen(h,w,rng,params[AZ(d)])
        img[y:y+h,x:x+w]=c; em[y:y+h,x:x+w]=e; ro[y:y+h,x:x+w]=r; me[y:y+h,x:x+w]=m
    img[776:,:]=0; em[776:,:]=0; ro[776:,:]=1; me[776:,:]=0       # outline band: pure black, matte, no metal, no glow
    dd=f'{OUT}/{name}'; os.makedirs(dd,exist_ok=True); sv=lambda a,n: Image.fromarray((np.clip(a,0,1)*255).astype(np.uint8)).save(f'{dd}/Horns_{name}_{n}.png')
    sv(img,'Color'); sv(ro,'Roughness'); sv(me,'Metalness'); sv(em,'Emissive'); sv(img*em[...,None],'EmissiveColor')
def edges(F):
    seen=set();E=[]
    for p,t in enumerate(F):
        for j in range(3):
            k=(min(t[j],t[(j+1)%3]),max(t[j],t[(j+1)%3]))
            if k not in seen: seen.add(k); E.append(p*3+j)
    return np.array(E,np.int32)
MESH={}
for key,f in [('','mesh11.npz'),('_NoOutline','mesh11_nool.npz')]:
    M=np.load(f); MESH[key]=(M['V'],M['F'],M['UV'],M['N'],edges(M['F']))
def write_mesh(name,suf):
    V,F,UV,N,ED=MESH[suf]; dd=f'{OUT}/{name}'
    ver,nodes,hd,ft=read(SRC); g=child([n for n in nodes if n[0]=='Objects'][0],'Geometry')[0]
    pvi=F.reshape(-1).astype(np.int32).copy(); pvi[2::3]=~pvi[2::3]
    child(g,'Vertices')[0][1][0]=('d',V.reshape(-1).astype(np.float64)); child(g,'PolygonVertexIndex')[0][1][0]=('i',pvi); child(g,'Edges')[0][1][0]=('i',ED)
    nl=child(g,'LayerElementNormal')[0]; child(nl,'Normals')[0][1][0]=('d',N.reshape(-1).astype(np.float64)); child(nl,'NormalsIndex')[0][1][0]=('i',np.repeat(np.arange(len(F)),3).astype(np.int32))
    ul=child(g,'LayerElementUV')[0]; child(ul,'UV')[0][1][0]=('d',UV.reshape(-1).astype(np.float64)); child(ul,'UVIndex')[0][1][0]=('i',np.arange(len(F)*3).astype(np.int32))
    write(f'{dd}/Horns_{name}{suf}.fbx',ver,nodes,hd,ft)
    with open(f'{dd}/Horns_{name}{suf}.obj','w') as o:
        o.write(f'# Horns lenticular 6-dir {name}{suf}\n'); o.writelines('v %.6f %.6f %.6f\n'%(v[0],v[2],-v[1]) for v in V)
        o.writelines('vt %.6f %.6f\n'%tuple(t) for t in UV); o.writelines('vn %.6f %.6f %.6f\n'%(n[0],n[2],-n[1]) for n in N)
        o.writelines('f '+' '.join('%d/%d/%d'%(fi[j]+1,i*3+j+1,i+1) for j in range(3))+'\n' for i,fi in enumerate(F))
only=sys.argv[1:] or list(THEMES)
for name in only:
    gen,params=THEMES[name]; build_textures(name,gen,params)
    for suf in ['','_NoOutline']: write_mesh(name,suf)
    print(name,'ok',flush=True)
