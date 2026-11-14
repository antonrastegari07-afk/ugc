import numpy as np, sys
H=np.load('hair/round_raw_before_tail.npy'); D=np.load('hair/raw.npz'); HF=D['HF']
ax=np.array([0.086,-0.013])                                  # hat vertical axis (x,z)
POM=np.array([-0.40,0.42,0.22])
def az(p): return np.degrees(np.arctan2(p[...,0]-ax[0],p[...,2]-ax[1]))
TARGET=float(sys.argv[1]) if len(sys.argv)>1 else -90.0
phi=TARGET-az(POM); print('pompom azimuth',round(float(az(POM)),1),'-> rotate tail end by',round(float(phi),1),'deg')
r=np.hypot(H[:,0]-ax[0],H[:,2]-ax[1]); a=az(H)
w=np.clip((r-0.34)/(0.50-0.34),0,1); w=w*w*(3-2*w)          # 0 on dome/brim radius -> 1 at the pompom
w*=np.clip((H[:,1]-0.40)/0.06,0,1)                           # never touch the hair below the brim
w*=((a<-15)&(a>-150))                                         # left side only (where the tail is)
pom=np.linalg.norm(H-POM,axis=1)<0.19; w[pom]=1.0             # pompom rotates rigidly with the tip
t=np.radians(phi*w); x=H[:,0]-ax[0]; z=H[:,2]-ax[1]
H2=H.copy(); H2[:,0]=ax[0]+x*np.cos(t)+z*np.sin(t); H2[:,2]=ax[1]-x*np.sin(t)+z*np.cos(t)
moved=np.linalg.norm(H2-H,axis=1); print('vertices moved >1mm',(moved>0.001).sum(),'of',len(H))
np.save('hair/round_raw.npy',H2)
newpom=H2[pom].mean(0); print('new pompom azimuth',round(float(az(newpom)),1))
sys.path.insert(0,'tools'); from raster import render, sheet
col=np.ones((len(HF),3))*0.88
ims=[render(X,HF,col,y,p,420) for X in (H,H2) for y,p in [(0,90),(0,6),(-60,20)]]
sheet(ims,3).save('hair/tail_fix.png')
