# Make ONLY the socket (inner hair wall) circular; outer hair shape untouched.
import numpy as np, trimesh, sys
from trimesh.ray.ray_pyembree import RayMeshIntersector as RMI
from scipy.ndimage import gaussian_filter
D=np.load('hair/raw.npz'); HF=D['HF']; PASS2=len(sys.argv)>2; H=(np.load('hair/round_raw.npy') if PASS2 else D['H']).copy(); H_orig=D['H']
ENL=float(sys.argv[1]) if len(sys.argv)>1 else 1.04; FALL=0.07
I0=RMI(trimesh.Trimesh(H,HF,process=False))
AZd=np.arange(0,360,5); AZ=np.radians(AZd); YS=np.arange(0.04,0.50,0.02)
fdist=np.abs(((AZd+180)%360)-180)                      # 0 = straight front
def rin(cc,y):
    O=np.repeat([[cc[0],y,cc[1]]],len(AZ),0); Dv=np.c_[np.sin(AZ),np.zeros(len(AZ)),np.cos(AZ)]
    loc,ri,_=I0.intersects_location(O,Dv,multiple_hits=False); r=np.full(len(AZ),np.nan); r[ri]=np.linalg.norm(loc-O[ri],axis=1); r[r>0.6]=np.nan; return r
# best-fit circle to the current socket wall (back, sides AND the forward-running arms)
c=np.load('hair/socket_c.npy').copy()
for it in range(6):
    pts=[]
    for y in (0.26,0.30,0.34,0.38,0.42):
        r=rin(c,y); ok=np.isfinite(r)&(fdist>=55); pts+=list(np.c_[c[0]+r[ok]*np.sin(AZ[ok]),c[1]+r[ok]*np.cos(AZ[ok])])
    pts=np.array(pts); A=np.c_[2*pts,np.ones(len(pts))]; sol=np.linalg.lstsq(A,(pts**2).sum(1),rcond=None)[0]; c=sol[:2]
Rfit=np.sqrt(sol[2]+c@c); RT=Rfit*ENL
if PASS2: info=np.load('hair/round_info.npz'); c,RT=info['cc'],float(info['RT'])
print('best-fit circle centre',c.round(3),'radius',round(Rfit,3),'-> target',round(RT,3))
R=np.full((len(YS),len(AZ)),np.nan)
for i,y in enumerate(YS): R[i]=rin(c,y)
R[:,fdist<55]=np.nan                                    # face opening: not part of the socket
# fill gaps of the wall map (sparse low strands) for vertex lookup
w=np.isfinite(R).astype(float); z=np.nan_to_num(R); pad=lambda a: np.concatenate([a[:,-10:],a,a[:,:10]],1)
Rf=R.copy()
for s in [(1,1.5),(2.5,4),(6,10)]:
    num=gaussian_filter(pad(z*w),s,mode='nearest')[:,10:-10]; den=gaussian_filter(pad(w),s,mode='nearest')[:,10:-10]
    Rf=np.where(np.isfinite(Rf),Rf,np.where(den>0.02,num/np.maximum(den,1e-6),np.nan)); w=np.isfinite(Rf).astype(float); z=np.nan_to_num(Rf)
Rf=gaussian_filter(pad(np.where(np.isfinite(Rf),Rf,RT)),(0.8,1.0),mode='nearest')[:,10:-10]
Dm=RT-Rf
fw=np.clip((fdist-45)/15,0,1)[None,:]; Dm=Dm*fw          # fade to 0 entering the face opening
v=H-np.array([c[0],0,c[1]]); r=np.hypot(v[:,0],v[:,2]); u=np.c_[v[:,0],np.zeros(len(v)),v[:,2]]/np.maximum(r,1e-6)[:,None]
az=np.degrees(np.arctan2(v[:,0],v[:,2]))%360
yi=np.clip((H[:,1]-YS[0])/0.02,0,len(YS)-1); ai=az/5
y0=np.floor(yi).astype(int); y1=np.minimum(y0+1,len(YS)-1); fy=yi-y0; a0=np.floor(ai).astype(int)%len(AZ); a1=(a0+1)%len(AZ); fa=ai-np.floor(ai)
bil=lambda M: M[y0,a0]*(1-fy)*(1-fa)+M[y1,a0]*fy*(1-fa)+M[y0,a1]*(1-fy)*fa+M[y1,a1]*fy*fa
d=bil(Dm); wall=bil(Rf)
ww=np.clip(1-(r-wall)/FALL,0,1); ww=ww*ww*(3-2*ww)          # 1 on/inside the wall -> 0 at 7 cm outward
under=0.471+0.31*H[:,2]; wy=np.clip((under+0.06-H[:,1])/0.08,0,1); wy=wy*wy*(3-2*wy)
inband=(H[:,1]>YS[0]-0.02)
pom=np.linalg.norm(H-np.array([-0.40,0.42,0.22]),axis=1)<0.17
wgt=ww*wy*inband*(~pom)
disp=d*wgt
# never let the inner wall cross outward through the outer layer: cap push at 60% of local thickness... approximated by FALL
disp=np.clip(disp,-0.06,FALL*0.8)
H2=H+u*disp[:,None]
mv=np.abs(disp)
print(f'vertices moved >1mm: {(mv>0.001).mean()*100:.1f}%  | mean move (moved ones) {mv[mv>0.001].mean():.3f} | max {mv.max():.3f}')
old=H_orig; tot=np.linalg.norm(H+u*disp[:,None]-H_orig,axis=1); print(f'total vs original: moved >1mm {(tot>0.001).mean()*100:.1f}% | max {tot.max():.3f}'); om=np.linalg.norm(np.load('hair/round_raw.npy')-H_orig,axis=1)+1e-9; print(f'previous version: moved >1mm {(om>0.001).mean()*100:.1f}% | mean {om[om>0.001].mean():.3f} | max {om.max():.3f}')
np.save('hair/round_raw.npy',H2); np.savez('hair/round_info.npz',cc=c,RT=RT)
I2=RMI(trimesh.Trimesh(H2,HF,process=False)); I0=I2
for y in (0.26,0.32,0.38,0.42):
    r=rin(c,y); ok=np.isfinite(r)&(fdist>=55); print(f'y {y}: socket radius min {np.nanmin(r[ok]):.3f} max {np.nanmax(r[ok]):.3f} (target {RT:.3f})')
