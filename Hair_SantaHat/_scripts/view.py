import numpy as np, sys; sys.path.insert(0,'tools'); from raster import render, sheet
def view(Hc,HF,out,cols_hair=None,size=420,angles=[(0,8),(40,8),(90,8),(140,8),(180,8),(270,8),(0,70),(20,-20)]):
    D=np.load('hair/raw.npz'); R,RF=D['R'],D['RF']
    hf=RF[R[RF].mean(1)[:,1]>1.0]
    # face: two eyes + mouth as small dark quads on the front of the head
    V=np.vstack([R,Hc]); F=np.vstack([hf,HF+len(R)])
    hc=np.ones((len(hf),3))*[0.95,0.8,0.35]
    ex=[]; ec=[]
    def quad(cx,cy,w,h):
        z=0.601; b=len(V)+len(ex)*0
        return np.array([[cx-w,cy-h,z],[cx+w,cy-h,z],[cx+w,cy+h,z],[cx-w,cy+h,z]])
    Q=[quad(-0.18,1.62,0.05,0.09),quad(0.18,1.62,0.05,0.09),quad(0,1.34,0.17,0.035)]
    for q in Q:
        b=len(V); V=np.vstack([V,q]); F=np.vstack([F,[[b,b+1,b+2],[b,b+2,b+3]]])
    hcols=cols_hair if cols_hair is not None else np.ones((len(HF),3))*[0.85,0.55,0.9]
    cols=np.vstack([hc,hcols,np.ones((6,3))*0.08])
    # centre the camera on head+hair only
    u=np.unique(F); rm=-np.ones(len(V),int); rm[u]=np.arange(len(u)); V=V[u]; F=rm[F]
    ims=[render(V,F,cols,y,p,size) for y,p in angles]
    sheet(ims,4).save(out)
