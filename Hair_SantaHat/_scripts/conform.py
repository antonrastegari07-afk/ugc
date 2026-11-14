import numpy as np, trimesh
from scipy.ndimage import gaussian_filter
from trimesh.ray.ray_pyembree import RayMeshIntersector as RMI
D=np.load('hair/raw.npz'); H0,HF,R,RF=D['H'],D['HF'],D['R'],D['RF']
hf=RF[R[RF].mean(1)[:,1]>1.0]; head=trimesh.Trimesh(R,hf,process=True); HI=RMI(head)
C=np.array([0,1.544,0.0])
EL=np.radians(np.arange(-60,91,4)); AZ=np.radians(np.arange(0,360,5))
E,A=np.meshgrid(EL,AZ,indexing='ij'); DIR=np.stack([np.cos(E)*np.sin(A),np.sin(E),np.cos(E)*np.cos(A)],-1).reshape(-1,3)  # az 0 = +Z (front)
def first_hit(I,O,Dv):
    loc,ri,_=I.intersects_location(O,Dv,multiple_hits=False); r=np.full(len(Dv),np.nan); r[ri]=np.einsum('ij,ij->i',loc-O[ri],Dv[ri]); return r
RH=first_hit(HI,np.repeat(C[None],len(DIR),0),DIR).reshape(E.shape)
def margin_map():
    m=np.full(E.shape,0.03); front=(np.cos(A)>0.5)&(E<np.radians(25)); m[front]=0.045   # a bit more room in front of the face
    return m
def conform(H,passes=3,maxd=0.35):
    H=H.copy()
    for p in range(passes):
        hm=trimesh.Trimesh(H,HF,process=False); I=RMI(hm)
        RI=first_hit(I,np.repeat(C[None],len(DIR),0),DIR).reshape(E.shape)
        d=(RH+margin_map())-RI
        valid=np.isfinite(d)&np.isfinite(RH)
        # fill holes (face opening / below hair) by normalized convolution, then smooth (wrap in azimuth)
        w=valid.astype(float); dd=np.where(valid,np.clip(d,-maxd,maxd),0)
        pad=lambda x: np.concatenate([x[:,-12:],x,x[:,:12]],1)
        num=gaussian_filter(pad(dd*w),(2.5,3.0))[:,12:-12]; den=gaussian_filter(pad(w),(2.5,3.0))[:,12:-12]
        sm=num/np.maximum(den,1e-6); sm[den<0.02]=0
        # vertex lookup
        v=H-C; r=np.linalg.norm(v,axis=1); u=v/np.maximum(r,1e-9)[:,None]
        el=np.degrees(np.arcsin(np.clip(u[:,1],-1,1))); az=np.degrees(np.arctan2(u[:,0],u[:,2]))%360
        ei=np.clip((el+60)/4,0,len(EL)-1); ai=az/5
        e0=np.floor(ei).astype(int); e1=np.minimum(e0+1,len(EL)-1); fe=ei-e0
        a0=np.floor(ai).astype(int)%len(AZ); a1=(a0+1)%len(AZ); fa=ai-np.floor(ai)
        val=sm[e0,a0]*(1-fe)*(1-fa)+sm[e1,a0]*fe*(1-fa)+sm[e0,a1]*(1-fe)*fa+sm[e1,a1]*fe*fa
        H=H+u*val[:,None]
        print(f' pass {p}: mean |d| {np.nanmean(np.abs(d[valid])):.3f}  max {np.nanmax(np.abs(d[valid])):.3f}  inside-violations {(d[valid]>0.005).mean():.3f}')
    return H
if __name__=='__main__':
    import sys
    s,ty,tz=1.95,0.80,0.0
    Hb=H0*s+np.array([0,ty,tz])
    Hc=conform(Hb,passes=4)
    np.save('hair/conformed.npy',Hc); np.save('hair/base.npy',Hb)
