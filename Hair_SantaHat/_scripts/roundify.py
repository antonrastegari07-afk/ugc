import numpy as np, trimesh, sys
from trimesh.ray.ray_pyembree import RayMeshIntersector as RMI
from scipy.ndimage import gaussian_filter
D=np.load('hair/raw.npz'); H,HF=D['H'].copy(),D['HF']
c=np.load('hair/socket_c.npy')
RT=float(sys.argv[1]) if len(sys.argv)>1 else 0.30
I0=RMI(trimesh.Trimesh(H,HF,process=False))
AZd=np.arange(0,360,5); AZ=np.radians(AZd); YS=np.arange(0.04,0.50,0.02)
def rin(I,cc,y):
    O=np.repeat([[cc[0],y,cc[1]]],len(AZ),0); Dv=np.c_[np.sin(AZ),np.zeros(len(AZ)),np.cos(AZ)]
    loc,ri,_=I.intersects_location(O,Dv,multiple_hits=False); r=np.full(len(AZ),np.nan); r[ri]=np.linalg.norm(loc-O[ri],axis=1); r[r>0.6]=np.nan; return r
r_back=np.nanmedian([rin(I0,c,y)[34:39] for y in (0.30,0.34,0.38)])
cc=np.array([c[0], c[1]-r_back+RT])                     # back wall stays put, circle of radius RT
print('back radius',round(r_back,3),'new centre',cc.round(3))
Dm=np.full((len(YS),len(AZ)),np.nan)
for i,y in enumerate(YS): Dm[i]=RT-rin(I0,cc,y)
front=np.abs(((AZd+180)%360)-180)<55                     # face opening sector: never pull inward
Dm=np.clip(Dm,-0.03,0.12); Dm[:,front]=np.where(np.isfinite(Dm[:,front]),np.maximum(Dm[:,front],0),np.nan)
# fill gaps (front opening, sparse low strands) by normalized smoothing; extend downward
w=np.isfinite(Dm).astype(float); z=np.nan_to_num(Dm)
pad=lambda a: np.concatenate([a[:,-10:],a,a[:,:10]],1)
for s in [(1.0,1.5),(2.5,4),(6,10)]:
    num=gaussian_filter(pad(z*w),s,mode='nearest')[:,10:-10]; den=gaussian_filter(pad(w),s,mode='nearest')[:,10:-10]
    fill=num/np.maximum(den,1e-6); Dm=np.where(np.isfinite(Dm),Dm,np.where(den>0.02,fill,np.nan)); w=np.isfinite(Dm).astype(float); z=np.nan_to_num(Dm)
Dm=np.nan_to_num(Dm); Dm=gaussian_filter(pad(Dm),(1.2,1.5),mode='nearest')[:,10:-10]
# apply horizontal offsets; fade out inside the hat (above the slanted underside); pompom untouched
v=H-np.array([cc[0],0,cc[1]]); r=np.hypot(v[:,0],v[:,2]); u=np.c_[v[:,0],np.zeros(len(v)),v[:,2]]/np.maximum(r,1e-6)[:,None]
az=np.degrees(np.arctan2(v[:,0],v[:,2]))%360
yi=np.clip((H[:,1]-YS[0])/0.02,0,len(YS)-1); ai=az/5
y0=np.floor(yi).astype(int); y1=np.minimum(y0+1,len(YS)-1); fy=yi-y0; a0=np.floor(ai).astype(int)%len(AZ); a1=(a0+1)%len(AZ); fa=ai-np.floor(ai)
d=Dm[y0,a0]*(1-fy)*(1-fa)+Dm[y1,a0]*fy*(1-fa)+Dm[y0,a1]*(1-fy)*fa+Dm[y1,a1]*fy*fa
under=0.471+0.31*H[:,2]
wy=np.clip((under+0.10-H[:,1])/0.12,0,1); wy=wy*wy*(3-2*wy)
pom=np.linalg.norm(H-np.array([-0.40,0.42,0.22]),axis=1)<0.17
wgt=wy*(~pom)
H2=H+u*(d*wgt)[:,None]
np.save('hair/round_raw.npy',H2); np.savez('hair/round_info.npz',cc=cc,RT=RT)
I2=RMI(trimesh.Trimesh(H2,HF,process=False))
for y in (0.20,0.30,0.38,0.42):
    r=rin(I2,cc,y); ok=np.isfinite(r)&~front; print(f'y {y}: inner radius min {np.nanmin(r[ok]):.3f} max {np.nanmax(r[ok]):.3f} (target {RT})')
