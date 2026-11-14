import sys,os; sys.path.insert(0,'tools')
from fbxio import read,child
from load import load; from comp import components
import numpy as np
from scipy.ndimage import gaussian_filter, map_coordinates
from skimage.measure import find_contours
from shapely.geometry import Polygon
from shapely.ops import unary_union
import mapbox_earcut as earcut
SRC='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/807479b3-HornsBlackHole_UGC.fbx'
BUDGET=3990; AXES=[0,1]          # vertical planes only: X-slices and Y-slices
V,F,UV,FUV,_,_=load(SRC); C=components(V,F)
ver,nodes,h,f=read(SRC); g=child([n for n in nodes if n[0]=='Objects'][0],'Geometry')[0]
nl=child(g,'LayerElementNormal')[0]; NRM=child(nl,'Normals')[0][1][0][1].reshape(-1,3); NIDX=child(nl,'NormalsIndex')[0][1][0][1].reshape(-1,3)
keep=np.isin(C,[4,5,6,7,8,10,11]); kf=np.where(keep)[0]
Z=np.load('field.npz'); W=gaussian_filter(Z['W'],0.9); lo=Z['lo']; R=float(Z['R']); shp=W.shape
hi=lo+(np.array(shp)-1)*R
r2=0.005
def section(ax,c):
    o=[i for i in range(3) if i!=ax]
    u=np.arange(lo[o[0]],hi[o[0]],r2); v=np.arange(lo[o[1]],hi[o[1]],r2)
    U,Vv=np.meshgrid(u,v,indexing='ij')
    coords=np.zeros((3,)+U.shape); coords[ax]=(c-lo[ax])/R; coords[o[0]]=(U-lo[o[0]])/R; coords[o[1]]=(Vv-lo[o[1]])/R
    S=map_coordinates(W,coords.reshape(3,-1),order=1).reshape(U.shape)
    S=np.pad(S,1)
    geo=None
    for cont in find_contours(S,0.5):
        if len(cont)<4: continue
        P=np.c_[lo[o[0]]+(cont[:,0]-1)*r2, lo[o[1]]+(cont[:,1]-1)*r2]
        poly=Polygon(P).buffer(0)
        if poly.is_empty: continue
        geo=poly if geo is None else geo.symmetric_difference(poly)
    return geo
def build(s,tol):
    tris=[]
    for ax in AXES:
        for c in np.arange(lo[ax]+s*0.5,hi[ax],s):
            G=section(ax,c)
            if G is None or G.is_empty: continue
            G=G.simplify(tol,preserve_topology=True)
            polys=[G] if G.geom_type=='Polygon' else [p for p in getattr(G,'geoms',[]) if p.geom_type=='Polygon']
            for P in polys:
                if P.is_empty or P.area<(tol*3)**2: continue
                rings=[np.array(P.exterior.coords)[:-1]]+[np.array(r.coords)[:-1] for r in P.interiors]
                verts=np.vstack(rings); ends=np.cumsum([len(r) for r in rings]).astype(np.uint32)
                idx=np.array(earcut.triangulate_float64(verts,ends)).reshape(-1,3)
                if len(idx): tris.append((ax,c,verts,idx))
    return tris,sum(len(t[3]) for t in tris)
budget=(BUDGET-len(kf))//2
s=float(sys.argv[1]) if len(sys.argv)>1 else 0.035; best=None
for it in range(10):
    tris,n=build(s,s*0.1); print(f'spacing {s:.4f}: one-side tris {n} / {budget}',flush=True)
    if n<=budget: best=(s,tris,n)
    if budget*0.94<=n<=budget: break
    s*=(n/budget)**0.6
s,tris,n=best
chainUV=np.array([[912/1024,1-912/1024]]); FUVk=FUV[kf].copy(); FUVk[np.isin(C[kf],[7,8,10,11])]=len(UV)
UV=np.vstack([UV,chainUV])
Vn=[V]; polys=[F[kf]]; uvs=[UV]; uvi=[FUVk]; nrm=[NRM]; nid=[NIDX[kf]]
SW=[(10+(d%2)*405,10+(d//2)*405,395,395) for d in range(4)]   # d = 2*ax+side : +X,-X,+Y,-Y
nv=len(V); nu=len(UV); nn=len(NRM)
for ax,c,verts,idx in tris:
    o=[i for i in range(3) if i!=ax]
    P3=np.zeros((len(verts),3)); P3[:,ax]=c; P3[:,o[0]]=verts[:,0]; P3[:,o[1]]=verts[:,1]
    nvec=np.zeros(3); nvec[ax]=1
    t=P3[idx]; cr=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0])@nvec; idx=np.where(cr[:,None]>0,idx,idx[:,[0,2,1]])
    Vn.append(P3)
    for side in (0,1):
        x,y,w,hh=SW[2*ax+side]; l=lo[o]; hg=hi[o]; q=(verts-l)/(hg-l)
        if side: q[:,0]=1-q[:,0]
        uv=np.c_[(x+8+q[:,0]*(w-16))/1024, 1-(y+8+(1-q[:,1])*(hh-16))/1024]
        ii=idx if side==0 else idx[:,[0,2,1]]
        uvs.append(uv); polys.append(nv+ii); uvi.append(nu+ii); nu+=len(uv)
        nrm.append((nvec if side==0 else -nvec)[None]); nid.append(np.full_like(ii,nn)); nn+=1
    nv+=len(P3)
Vn=np.vstack(Vn); Fn=np.vstack(polys)
used=np.unique(Fn); remap=-np.ones(len(Vn),int); remap[used]=np.arange(len(used))
print('FINAL spacing',round(s,4),'slices',len(set((t[0],round(t[1],5)) for t in tris)),'TOTAL TRIS',len(Fn))
np.savez('mesh4.npz',V=Vn[used],F=remap[Fn],UV=np.vstack(uvs),UI=np.vstack(uvi),N=np.vstack(nrm),NI=np.vstack(nid),SW=np.array(SW))
