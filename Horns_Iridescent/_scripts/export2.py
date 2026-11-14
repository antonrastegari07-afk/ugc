import sys,os; sys.path.insert(0,'tools')
from fbxio import read,write,child
import numpy as np, colorsys; from PIL import Image
SRC='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/807479b3-HornsBlackHole_UGC.fbx'
TEX='/tmp/claude-0/-home-user-ugc/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/images/1.webp'
OUT=sys.argv[1]
M=np.load('mesh2.npz'); V,F,UV,UI,N,NI=M['V'],M['F'],M['UV'],M['UI'],M['N'],M['NI']; ND=int(M['ndir'])
def H(c): return np.array([int(c[i:i+2],16)/255 for i in (1,3,5)])
def loop(cols,n,cycles=1):
    cols=[H(c) if isinstance(c,str) else np.array(c) for c in cols]; out=[]
    for d in range(n):
        t=(d*cycles/n*len(cols))%len(cols); i=int(t); fr=t-i
        out.append(cols[i]*(1-fr)+cols[(i+1)%len(cols)]*fr)
    return out
PAL={
 'holo':   (loop([colorsys.hsv_to_rgb(x/6,1,1) for x in [5,0,1,2,3,4]],ND,1)),   # like the reference: purple,red,yellow,green,cyan,blue x2
 'galaxy': (loop(['#7A2BFF','#FF2BD6','#2B4BFF','#00E5FF'],ND,1)),
 'toxic':  (loop(['#39FF14','#00FFC6','#00A2FF','#B6FF00'],ND,1)),
 'inferno':(loop(['#FF1744','#FF8A00','#FFD600','#FF2E9A'],ND,1)),
}
X0,Y0,S=832,832,40
def edges(F):
    seen={};E=[]
    for p,t in enumerate(F):
        for j in range(3):
            a,b=t[j],t[(j+1)%3]; k=(min(a,b),max(a,b))
            if k not in seen: seen[k]=1; E.append(p*3+j)
    return np.array(E,np.int32)
ED=edges(F)
orig=Image.open(TEX).convert('RGB')
for name,cols in PAL.items():
    d=f'{OUT}/{name}'; os.makedirs(d,exist_ok=True)
    img=np.asarray(orig).copy().astype(float)/255
    for k,c in enumerate(cols):
        x,y=X0+(k%4)*S,Y0+(k//4)*S
        t=np.linspace(0,1,S)[:,None,None]          # 0 top (apex) -> 1 bottom (base)
        sw=(c*(1-t)+c*0.45*t)*1.0; sw=np.where(t<0.25,sw*(1-(0.25-t)*1.6)+ (0.25-t)*1.6,sw)  # bright tip glint
        img[y:y+S,x:x+S]=np.clip(np.broadcast_to(sw,(S,S,3)),0,1)
    Image.fromarray((img*255).astype(np.uint8)).save(f'{d}/Horns_{name}_Color.png')
    ver,nodes,h,f=read(SRC); g=child([n for n in nodes if n[0]=='Objects'][0],'Geometry')[0]
    pvi=F.reshape(-1).astype(np.int32).copy(); pvi[2::3]=~pvi[2::3]
    child(g,'Vertices')[0][1][0]=('d',V.reshape(-1).astype(np.float64))
    child(g,'PolygonVertexIndex')[0][1][0]=('i',pvi)
    child(g,'Edges')[0][1][0]=('i',ED)
    nl=child(g,'LayerElementNormal')[0]; child(nl,'Normals')[0][1][0]=('d',N.reshape(-1).astype(np.float64)); child(nl,'NormalsIndex')[0][1][0]=('i',NI.reshape(-1).astype(np.int32))
    ul=child(g,'LayerElementUV')[0]; child(ul,'UV')[0][1][0]=('d',UV.reshape(-1).astype(np.float64)); child(ul,'UVIndex')[0][1][0]=('i',UI.reshape(-1).astype(np.int32))
    write(f'{d}/Horns_{name}.fbx',ver,nodes,h,f)
    with open(f'{d}/Horns_{name}.obj','w') as o:
        o.write(f'# Horns lenticular {name}\n')
        for v in V: o.write('v %.6f %.6f %.6f\n'%(v[0],v[2],-v[1]))
        for t in UV: o.write('vt %.6f %.6f\n'%tuple(t))
        for n in N: o.write('vn %.6f %.6f %.6f\n'%(n[0],n[2],-n[1]))
        for fi,tu,tn in zip(F,UI,NI): o.write('f '+' '.join('%d/%d/%d'%(fi[j]+1,tu[j]+1,tn[j]+1) for j in range(3))+'\n')
print('exported',len(F),'tris')
