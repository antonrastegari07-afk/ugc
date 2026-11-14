import sys,os; sys.path.insert(0,'tools')
from fbxio import read,write,child
import numpy as np; from PIL import Image
SRC='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/807479b3-HornsBlackHole_UGC.fbx'
TEX='/tmp/claude-0/-home-user-ugc/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/images/1.webp'
OUT=sys.argv[1]
M=np.load('mesh4.npz'); V,F,UV,UI,N,NI,SW=[M[k] for k in ['V','F','UV','UI','N','NI','SW']]
def H(c): return np.array([int(c[i:i+2],16)/255 for i in (1,3,5)])
# order: +X(right side), -X(left side), +Y(back), -Y(front), +Z(top), -Z(bottom)   [Blender mesh axes]
PAL={   # order: +X (right side), -X (left side), +Y (back), -Y (front)  [Blender mesh axes]
 'holo':   ['#2B5BFF','#FFD000','#39FF14','#FF2BD6'],
 'galaxy': ['#2B4BFF','#00E5FF','#FF2BD6','#9B30FF'],
 'toxic':  ['#00FFC6','#B6FF00','#00A2FF','#39FF14'],
 'inferno':['#FF8A00','#FF2E9A','#FFD600','#FF1744'],
}
def edges(F):
    seen=set();E=[]
    for p,t in enumerate(F):
        for j in range(3):
            k=(min(t[j],t[(j+1)%3]),max(t[j],t[(j+1)%3]))
            if k not in seen: seen.add(k); E.append(p*3+j)
    return np.array(E,np.int32)
ED=edges(F)
orig=np.asarray(Image.open(TEX).convert('RGB')).astype(float)/255
for name,cols in PAL.items():
    d=f'{OUT}/{name}'; os.makedirs(d,exist_ok=True)
    img=orig.copy(); img[0:820,0:820]=0.04; img[840:985,840:985]=H('#C9A8FF')   # fixed chain colour   # old crystal area no longer used
    for k,(x,y,w,h) in enumerate(SW):
        c=H(cols[k]); yy,xx=np.mgrid[0:h,0:w]
        grad=0.75+0.35*(1-yy/h)                        # brighter towards top
        hatch=0.88+0.12*np.sign(np.sin((xx+yy)*2*np.pi/7))   # fine diagonal hatching like the reference
        sw=np.clip(c[None,None,:]*(grad*hatch)[...,None],0,1)
        img[y:y+h,x:x+w]=sw
    Image.fromarray((img*255).astype(np.uint8)).save(f'{d}/Horns_{name}_Color.png')
    ver,nodes,hd,ft=read(SRC); g=child([n for n in nodes if n[0]=='Objects'][0],'Geometry')[0]
    pvi=F.reshape(-1).astype(np.int32).copy(); pvi[2::3]=~pvi[2::3]
    child(g,'Vertices')[0][1][0]=('d',V.reshape(-1).astype(np.float64))
    child(g,'PolygonVertexIndex')[0][1][0]=('i',pvi)
    child(g,'Edges')[0][1][0]=('i',ED)
    nl=child(g,'LayerElementNormal')[0]; child(nl,'Normals')[0][1][0]=('d',N.reshape(-1).astype(np.float64)); child(nl,'NormalsIndex')[0][1][0]=('i',NI.reshape(-1).astype(np.int32))
    ul=child(g,'LayerElementUV')[0]; child(ul,'UV')[0][1][0]=('d',UV.reshape(-1).astype(np.float64)); child(ul,'UVIndex')[0][1][0]=('i',UI.reshape(-1).astype(np.int32))
    write(f'{d}/Horns_{name}.fbx',ver,nodes,hd,ft)
    with open(f'{d}/Horns_{name}.obj','w') as o:
        o.write(f'# Horns sliced lenticular {name}\n')
        for v in V: o.write('v %.6f %.6f %.6f\n'%(v[0],v[2],-v[1]))
        for t in UV: o.write('vt %.6f %.6f\n'%tuple(t))
        for n in N: o.write('vn %.6f %.6f %.6f\n'%(n[0],n[2],-n[1]))
        for fi,tu,tn in zip(F,UI,NI): o.write('f '+' '.join('%d/%d/%d'%(fi[j]+1,tu[j]+1,tn[j]+1) for j in range(3))+'\n')
print('exported',len(F))
