import sys,os,json; sys.path.insert(0,'tools')
from fbxio import read,write,child
import numpy as np; from PIL import Image
SRC='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/807479b3-HornsBlackHole_UGC.fbx'
OUT=sys.argv[1]
M=np.load('mesh10.npz'); V,F,UV,N,SW=M['V'],M['F'],M['UV'],M['N'],M['SW']; BLK=json.load(open('blk.json'))
def H(c): return np.array([int(c[i:i+2],16)/255 for i in (1,3,5)])
# per direction (top colour, bottom colour); d: +X(right), -X(left), +Y(back), -Y(front)
PAL={   # per direction 3-stop gradient (top, middle, bottom); d: +X(right), -X(left), +Y(back), -Y(front)
 'holo':   {'dirs':[('#00FFF0','#2B6BFF','#7A2BFF'),('#FFF200','#FF8A00','#FF1A3C'),('#C6FF00','#00FF6A','#00B8A0'),('#FF6BF0','#FF1FA8','#8A1BFF')],'spike':'#0B0912','spike_ol':'#00E5FF','ring_ol':'#06060A'},
 'galaxy': {'dirs':[('#7DF9FF','#2B4BFF','#3A00B8'),('#FFB3F5','#FF2BD6','#7A00FF'),('#B8A6FF','#6A5CFF','#0090FF'),('#FF6BF0','#B026FF','#2B0B8A')],'spike':'#0B0912','spike_ol':'#B026FF','ring_ol':'#06060A'},
 'toxic':  {'dirs':[('#9CFFF0','#00FFC6','#0068FF'),('#FFF700','#9CFF00','#00C83C'),('#E6FF00','#39FF14','#00806A'),('#00FFA0','#00C8FF','#0040C0')],'spike':'#07120A','spike_ol':'#39FF14','ring_ol':'#06060A'},
 'inferno':{'dirs':[('#FFF27A','#FFB000','#FF4D00'),('#FF7AC8','#FF1F6A','#8A0018'),('#FFD600','#FF6A00','#C80000'),('#FF9A3C','#FF1744','#9A0060')],'spike':'#120707','spike_ol':'#FF5A00','ring_ol':'#06060A'},
}
def edges(F):
    seen=set();E=[]
    for p,t in enumerate(F):
        for j in range(3):
            k=(min(t[j],t[(j+1)%3]),max(t[j],t[(j+1)%3]))
            if k not in seen: seen.add(k); E.append(p*3+j)
    return np.array(E,np.int32)
ED=edges(F)
for name,P in PAL.items():
    d=f'{OUT}/{name}'; os.makedirs(d,exist_ok=True)
    img=np.zeros((1024,1024,3))+0.03
    for k,(x,y,w,h) in enumerate(SW):
        c0,c1,c2=[H(x) for x in P['dirs'][k]]; yy,xx=np.mgrid[0:h,0:w]; t=(yy/h)[...,None]
        col=np.where(t<0.5, c0*(1-2*t)+c1*(2*t), c1*(2-2*t)+c2*(2*t-1))
        hatch=0.86+0.14*np.sign(np.sin((xx+yy)*2*np.pi/7))[...,None]
        img[y:y+h,x:x+w]=np.clip(col*hatch*1.05,0,1)
    for b,(x,y,w,h) in BLK.items(): img[y:y+h,x:x+w]=H(P[b])
    Image.fromarray((img*255).astype(np.uint8)).save(f'{d}/Horns_{name}_Color.png')
    rough=np.full((1024,1024),0.65)                       # slices: soft sheen
    for b,(x,y,w,h) in BLK.items(): rough[y:y+h,x:x+w]=1.0  # fins + outlines: fully matte, no reflection
    Image.fromarray((rough*255).astype(np.uint8)).save(f'{d}/Horns_{name}_Roughness.png')
    Image.fromarray(np.zeros((1024,1024),np.uint8)).save(f'{d}/Horns_{name}_Metalness.png')
    em=np.zeros((1024,1024))
    for (x,y,w,h) in SW: em[y:y+h,x:x+w]=1.0                 # colour-shifting slices glow, outlines stay black
    Image.fromarray((em*255).astype(np.uint8)).save(f'{d}/Horns_{name}_Emissive.png')
    Image.fromarray((img*em[...,None]*255).astype(np.uint8)).save(f'{d}/Horns_{name}_EmissiveColor.png')
    ver,nodes,hd,ft=read(SRC); g=child([n for n in nodes if n[0]=='Objects'][0],'Geometry')[0]
    pvi=F.reshape(-1).astype(np.int32).copy(); pvi[2::3]=~pvi[2::3]
    child(g,'Vertices')[0][1][0]=('d',V.reshape(-1).astype(np.float64))
    child(g,'PolygonVertexIndex')[0][1][0]=('i',pvi)
    child(g,'Edges')[0][1][0]=('i',ED)
    nl=child(g,'LayerElementNormal')[0]; child(nl,'Normals')[0][1][0]=('d',N.reshape(-1).astype(np.float64)); child(nl,'NormalsIndex')[0][1][0]=('i',np.repeat(np.arange(len(F)),3).astype(np.int32))
    ul=child(g,'LayerElementUV')[0]; child(ul,'UV')[0][1][0]=('d',UV.reshape(-1).astype(np.float64)); child(ul,'UVIndex')[0][1][0]=('i',np.arange(len(F)*3).astype(np.int32))
    write(f'{d}/Horns_{name}.fbx',ver,nodes,hd,ft)
    with open(f'{d}/Horns_{name}.obj','w') as o:
        o.write(f'# Horns sliced lenticular v4 {name}\n')
        for v in V: o.write('v %.6f %.6f %.6f\n'%(v[0],v[2],-v[1]))
        for t in UV: o.write('vt %.6f %.6f\n'%tuple(t))
        for n in N: o.write('vn %.6f %.6f %.6f\n'%(n[0],n[2],-n[1]))
        for i,fi in enumerate(F): o.write('f '+' '.join('%d/%d/%d'%(fi[j]+1,i*3+j+1,i+1) for j in range(3))+'\n')
print('exported',len(F))
