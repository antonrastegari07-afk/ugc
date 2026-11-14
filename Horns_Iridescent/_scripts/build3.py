import sys,os,json; sys.path.insert(0,'tools')
from fbxio import read,write,child
from load import load; from comp import components
import numpy as np, colorsys; from PIL import Image
SRC='/root/.claude/uploads/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/807479b3-HornsBlackHole_UGC.fbx'
TEX='/tmp/claude-0/-home-user-ugc/2a2dc869-38e2-54de-8e85-531b1a0ba8eb/images/1.webp'
OUT=sys.argv[1] if len(sys.argv)>1 else 'out2'
BUDGET=3990; NDIR=6; NFAM=NDIR//2
V,F,UV,FUV,_,_=load(SRC); C=components(V,F)
# original per-polygon-vertex normals
ver,nodes,h,f=read(SRC); g=child([n for n in nodes if n[0]=='Objects'][0],'Geometry')[0]
nl=child(g,'LayerElementNormal')[0]; NRM=child(nl,'Normals')[0][1][0][1].reshape(-1,3); NIDX=child(nl,'NormalsIndex')[0][1][0][1].reshape(-1,3)
# --- keep fixed parts (drop duplicated chain 9 which z-fights with 7)
same=np.allclose(np.sort(V[F[C==7]].reshape(-1,3),0),np.sort(V[F[C==9]].reshape(-1,3),0))
print('chain 7 & 9 identical:',same)
keep=np.isin(C,[4,5,6,7,8,10,11]); kf=np.where(keep)[0]
# --- horn volume test: generalized winding number over horn components
horn=np.isin(C,[0,1,2,3]); HF=F[horn]
def winding(P,Vt,Ft):
    T=Vt[Ft]; w=np.zeros(len(P))
    for i0 in range(0,len(P),400):
        p=P[i0:i0+400,None,None,:]; a=T[None,:,0]-p[:,:,0]; b=T[None,:,1]-p[:,:,0]; c=T[None,:,2]-p[:,:,0]
        la,lb,lc=[np.linalg.norm(x,axis=-1) for x in (a,b,c)]
        num=np.einsum('ijk,ijk->ij',a,np.cross(b,c))
        den=la*lb*lc+np.einsum('ijk,ijk->ij',a,b)*lc+np.einsum('ijk,ijk->ij',b,c)*la+np.einsum('ijk,ijk->ij',c,a)*lb
        w[i0:i0+400]=(2*np.arctan2(num,den)).sum(1)/(4*np.pi)
    return w
# per-component inside (components overlap; union)
lo=V[F[horn]].reshape(-1,3).min(0); hi=V[F[horn]].reshape(-1,3).max(0)
def inside(P):
    m=np.zeros(len(P),bool)
    for k in [0,1,2,3]: m|=np.abs(winding(P,V,F[C==k]))>0.5
    return m
nkeep=keep.sum(); budget_cards=(BUDGET-nkeep)//2
fine=0.02; ax=[np.arange(lo[i],hi[i]+fine,fine) for i in range(3)]
G=np.stack(np.meshgrid(*ax,indexing='ij'),-1).reshape(-1,3)
cache='inside_cache.npy'
if os.path.exists(cache): IN=np.load(cache)
else: IN=inside(G); np.save(cache,IN)
shp=[len(a) for a in ax]; INg=IN.reshape(shp)
def isin(P):
    idx=np.round((P-lo)/fine).astype(int); ok=np.all((idx>=0)&(idx<np.array(shp)),1)
    idx=np.clip(idx,0,np.array(shp)-1); return ok&INg[idx[:,0],idx[:,1],idx[:,2]]
NFAM=NDIR//2
def make(a,p):
    cards=[]
    hgt=a*np.sqrt(3)/2
    for k in range(NFAM):
        th=np.radians(k*180/NFAM+15); n=np.array([np.cos(th),np.sin(th),0]); e1=np.array([-np.sin(th),np.cos(th),0]); e2=np.array([0,0,1.])
        corners=np.array([[x,y,z] for x in (lo[0],hi[0]) for y in (lo[1],hi[1]) for z in (lo[2],hi[2])])
        on=corners@n; ou=corners@e1
        for o in np.arange(on.min()+p*(0.5+k/NFAM),on.max(),p):
            for r,w in enumerate(np.arange(lo[2],hi[2]+hgt,hgt)):
                shift=(r%2)*a/2
                for j,u in enumerate(np.arange(ou.min()-a+shift,ou.max()+a,a/2)):
                    up=(j%2==0)
                    if up: A=(u+a/2,w+hgt); B=(u,w); Cc=(u+a,w)
                    else:  A=(u+a/2,w);     B=(u,w+hgt); Cc=(u+a,w+hgt)
                    pts=[n*o+e1*q[0]+e2*q[1] for q in (A,B,Cc)]
                    cards.append((k,up,pts))
    K=np.array([c[0] for c in cards]); U=np.array([c[1] for c in cards]); T=np.array([c[2] for c in cards])
    m=isin(T.mean(1)); return K[m],U[m],T[m]
p=0.07; a=0.06
for it in range(12):
    K,U,T=make(a,p); n_=len(K)
    if budget_cards*0.96<=n_<=budget_cards: break
    a*= (n_/budget_cards)**0.5
print('cards',len(K),'side',round(a,4),'plane spacing',p)
fam=K; th=np.radians(fam*180/NFAM+15)
N=np.c_[np.cos(th),np.sin(th),np.zeros(len(th))]
fa,fb,fc=T[:,0],T[:,1],T[:,2]
cr=np.cross(fb-fa,fc-fa); sg=np.einsum('ij,ij->i',cr,N)>0
fb,fc=np.where(sg[:,None],fb,fc),np.where(sg[:,None],fc,fb)
dir_front=fam; dir_back=fam+NFAM
# ---------- assemble mesh
Vk=V; newV=[V]; base=len(V)
polys=[F[kf]]; uvs=[UV]; uvidx=[FUV[kf]]; nrm=[NRM]; nidx=[NIDX[kf]]
cV=np.stack([fa,fb,fc],1).reshape(-1,3); newV.append(cV)
ci=base+np.arange(len(cV)).reshape(-1,3)
front=ci; back=ci[:,[0,2,1]]
polys+= [front,back]
# UV: swatch d at 4x4 grid in pixel block 832..992; apex at top of swatch (bright), base at bottom
X0,Y0,S=832,832,40
def sw(d,which):
    cx=X0+(d%4)*S; cy=Y0+(d//4)*S
    if which=='apex': return np.c_[cx+S/2+0*d, cy+5+0*d]
    if which=='l': return np.c_[cx+6+0*d, cy+S-5+0*d]
    return np.c_[cx+S-6+0*d, cy+S-5+0*d]
def uvof(d,order):
    pts=[sw(d,w) for w in order]; return np.stack([np.c_[p[:,0]/1024,1-p[:,1]/1024] for p in pts],1)
# front tri vertex order = (apex,b,c) where b/c may be swapped from (bl,br); uv l/r swap is cosmetic
uf=uvof(dir_front,['apex','l','r']); ub=uvof(dir_back,['apex','r','l'])
u0=len(UV); allu=np.vstack([uf.reshape(-1,2),ub.reshape(-1,2)]); uvs.append(allu)
uvidx+=[u0+np.arange(len(uf)*3).reshape(-1,3), u0+len(uf)*3+np.arange(len(ub)*3).reshape(-1,3)]
n0=len(NRM); nrm.append(np.vstack([N,-N])); nidx+=[np.repeat(n0+np.arange(len(N))[:,None],3,1), np.repeat(n0+len(N)+np.arange(len(N))[:,None],3,1)]
Vn=np.vstack(newV); Fn=np.vstack(polys); UVn=np.vstack(uvs); UIn=np.vstack(uvidx); Nn=np.vstack(nrm); NIn=np.vstack(nidx)
# compact unused vertices
used=np.unique(Fn); remap=-np.ones(len(Vn),int); remap[used]=np.arange(len(used)); Vn=Vn[used]; Fn=remap[Fn]
print('TOTAL TRIS',len(Fn),'verts',len(Vn))
np.savez('mesh2.npz',V=Vn,F=Fn,UV=UVn,UI=UIn,N=Nn,NI=NIn,ndir=NDIR)
