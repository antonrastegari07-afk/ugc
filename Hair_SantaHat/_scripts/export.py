import sys,os,numpy as np,trimesh; sys.path.insert(0,'tools')
from fbxio import read,write,child
U='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/'
def export(V,F,UVc,out_fbx,tex_name='Hair_Color.png'):
    ver,nodes,h,f=read(U+'c0c73cca-tripo_convert_24749a36-9b5c-47a0-b54c-83df27b9ee46.fbx')
    _,rnodes,_,_=read(U+'b3aed151-r6_rigged.fbx')
    gi=[i for i,n in enumerate(nodes) if n[0]=='GlobalSettings'][0]; nodes[gi]=[n for n in rnodes if n[0]=='GlobalSettings'][0]   # same units/axes as the rig
    obj=[n for n in nodes if n[0]=='Objects'][0]; g=[k for k in obj[2] if k[0]=='Geometry'][0]
    pvi=F.reshape(-1).astype(np.int32).copy(); pvi[2::3]=~pvi[2::3]
    seen=set(); E=[]
    for p,t in enumerate(F):
        for j in range(3):
            k=(min(t[j],t[(j+1)%3]),max(t[j],t[(j+1)%3]))
            if k not in seen: seen.add(k); E.append(p*3+j)
    VN=trimesh.Trimesh(V,F,process=False).vertex_normals
    child(g,'Vertices')[0][1][0]=('d',V.reshape(-1).astype(np.float64))
    child(g,'PolygonVertexIndex')[0][1][0]=('i',pvi)
    child(g,'Edges')[0][1][0]=('i',np.array(E,np.int32))
    child(child(g,'LayerElementSmoothing')[0],'Smoothing')[0][1][0]=('i',np.ones(len(F),np.int32))
    nl=child(g,'LayerElementNormal')[0]; child(nl,'Normals')[0][1][0]=('d',VN.reshape(-1).astype(np.float64)); child(nl,'NormalsIndex')[0][1][0]=('i',F.reshape(-1).astype(np.int32))
    ul=child(g,'LayerElementUV')[0]; child(ul,'UV')[0][1][0]=('d',UVc.reshape(-1).astype(np.float64)); child(ul,'UVIndex')[0][1][0]=('i',np.arange(len(F)*3,dtype=np.int32))
    m=[k for k in obj[2] if k[0]=='Model'][0]; P=child(m,'Properties70')[0]
    P[2]=[p for p in P[2] if p[1][0][1] not in (b'Lcl Rotation',b'Lcl Translation',b'Lcl Scaling')]
    mk=lambda n,x: ['P',[('S',n),('S',n),('S',b''),('S',b'A'),('D',float(x[0])),('D',float(x[1])),('D',float(x[2]))],[]]
    P[2]=[mk(b'Lcl Translation',(0,100,0)),mk(b'Lcl Rotation',(0,0,0)),mk(b'Lcl Scaling',(100,100,100))]+P[2]   # identical to the rig mesh node
    for k in obj[2]:
        if k[0] in ('Texture','Video'):
            for c in k[2]:
                if c[0] in ('FileName','Filename','RelativeFilename'): c[1][0]=('S',tex_name.encode())
    m[1][1]=('S',b'Hair\x00\x01Model'); g[1][1]=('S',b'Hair\x00\x01Geometry')
    write(out_fbx,ver,nodes,h,f)
    # OBJ backup (studs, Y-up, same placement as the rig head)
    with open(out_fbx[:-4]+'.obj','w') as o:
        o.write('# Hair fitted to R6 head (studs, Y-up)\nmtllib Hair.mtl\nusemtl hair\n')
        o.writelines('v %.6f %.6f %.6f\n'%tuple(v) for v in V); o.writelines('vt %.6f %.6f\n'%tuple(t) for t in UVc.reshape(-1,2))
        o.writelines('vn %.6f %.6f %.6f\n'%tuple(n) for n in VN)
        o.writelines('f '+' '.join('%d/%d/%d'%(fi[j]+1,i*3+j+1,fi[j]+1) for j in range(3))+'\n' for i,fi in enumerate(F))
if __name__=='__main__':
    D=np.load('hair/final_geo.npz'); os.makedirs('/home/user/ugc/Hair_SantaHat',exist_ok=True)
    export(D['V'],D['F'],D['UVc'],'/home/user/ugc/Hair_SantaHat/Hair_SantaHat.fbx'); print('ok',len(D['F']))
