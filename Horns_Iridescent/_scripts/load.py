import sys,numpy as np
sys.path.insert(0,__file__.rsplit('/',1)[0])
from fbxread import parse,find
def load(p):
    ver,nodes=parse(p)
    obj=[n for n in nodes if n['name']=='Objects'][0]
    g=[k for k in obj['kids'] if k['name']=='Geometry'][0]
    V=find(g,'Vertices')[0]['props'][0].reshape(-1,3).astype(float)
    pv=find(g,'PolygonVertexIndex')[0]['props'][0].copy()
    pv[pv<0]=~pv[pv<0]; F=pv.reshape(-1,3)
    uvl=find(g,'LayerElementUV')[0]
    info={c['name']:c['props'][0] for c in uvl['kids'] if c['props']}
    UV=info['UV'].reshape(-1,2); idx=info.get('UVIndex')
    FUV = idx.reshape(-1,3) if 'IndexToDirect' in info['ReferenceInformationType'] else np.arange(len(pv)).reshape(-1,3)
    return V,F,UV,FUV,info['MappingInformationType'],info['ReferenceInformationType']
