import sys,numpy as np; sys.path.insert(0,__file__.rsplit('/',1)[0])
from fbxio import read,child
def geom(path,gi=0):
    ver,nodes,h,f=read(path); obj=[n for n in nodes if n[0]=='Objects'][0]
    g=[k for k in obj[2] if k[0]=='Geometry' and child(k,'Vertices')][gi]
    V=child(g,'Vertices')[0][1][0][1].reshape(-1,3).astype(float)
    pv=child(g,'PolygonVertexIndex')[0][1][0][1].astype(np.int64)
    ends=np.where(pv<0)[0]; idx=pv.copy(); idx[ends]=~idx[ends]; starts=np.r_[0,ends[:-1]+1]
    polys=[idx[s:e+1] for s,e in zip(starts,ends)]; corner=[np.arange(s,e+1) for s,e in zip(starts,ends)]
    uvl=child(g,'LayerElementUV'); UV=UVc=None
    if uvl:
        L={c[0]:c[1][0][1] for c in uvl[0][2] if c[1]}; UV=L['UV'].reshape(-1,2)
        UVc=L['UVIndex'] if b'IndexToDirect' in L['ReferenceInformationType'] else np.arange(len(pv))
    T=[];TU=[];PI=[]
    for pi,(p,c) in enumerate(zip(polys,corner)):
        for j in range(1,len(p)-1):
            T.append([p[0],p[j],p[j+1]]); PI.append(pi)
            if UV is not None: TU.append([UVc[c[0]],UVc[c[j]],UVc[c[j+1]]])
    return V,np.array(T),UV,(np.array(TU) if TU else None),np.array(PI),(ver,nodes,h,f,g)
