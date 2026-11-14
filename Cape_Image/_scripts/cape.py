"""Cape UGC: fixed trapezoid slab + texture generator.
Usage:  python3 cape.py build            -> writes Cape.fbx / Cape.obj
        python3 cape.py tex IMAGE [OUT]  -> writes Cape_Color.png from any image (cover-crop, no stretch)"""
import sys, os, numpy as np
from PIL import Image, ImageFilter
HERE=os.path.dirname(os.path.abspath(__file__)); OUTDIR=os.path.dirname(HERE)
# ---- shape (studs, R6 rig space: Y up, +Z = front of the character, back of torso at z=-0.5)
TOP_W,BOT_W,LEN=1.9,2.4,2.9
TOP=np.array([0,0.95,-0.53]); BOT=np.array([0,0.95-2.82,-0.53-0.66])     # slants away from the legs
TH=0.05                                                                  # thickness
N=2048; FR=(0,0,1640,2040)          # atlas: outer face (image) region x0,y0,x1,y1 (aspect = BOT_W/LEN)
BK=(1660,0,2040,470); ED=(1660,500,2040,560)
def corners():
    d=BOT-TOP; L=np.linalg.norm(d); t=d/L; n=np.cross(np.array([1.,0,0]),t); n/=np.linalg.norm(n)   # n points outward (-z side)
    if n[2]>0: n=-n
    P=[TOP+np.array([-TOP_W/2,0,0]),TOP+np.array([TOP_W/2,0,0]),BOT+np.array([BOT_W/2,0,0]),BOT+np.array([-BOT_W/2,0,0])]
    return np.array(P),n
def uv_px(x,y): return np.array([x/N,1-y/N])
def build():
    P,n=corners(); out=P-n*0+n*TH/2; inn=P-n*TH/2
    x0,y0,x1,y1=FR; W=x1-x0; H=y1-y0
    # outer face UV: trapezoid inside the image rectangle -> no stretch (bottom edge = full width)
    def fuv(p,i):
        u=(p[0]+BOT_W/2)/BOT_W; v=i
        # x seen from behind the character is mirrored: viewer's left = +X
        return uv_px(x0+(1-u)*W, y0+v*H)
    tris=[];uvs=[]
    O=[out[0],out[1],out[2],out[3]]; Ou=[fuv(O[0],0),fuv(O[1],0),fuv(O[2],1),fuv(O[3],1)]
    for a,b,c in ((0,1,2),(0,2,3)): tris.append([O[a],O[b],O[c]]); uvs.append([Ou[a],Ou[b],Ou[c]])
    bx0,by0,bx1,by1=BK; Iu=[uv_px(bx0+(bx1-bx0)*((p[0]+BOT_W/2)/BOT_W),by0+(by1-by0)*v) for p,v in zip(inn,(0,0,1,1))]
    for a,b,c in ((0,2,1),(0,3,2)): tris.append([inn[a],inn[b],inn[c]]); uvs.append([Iu[a],Iu[b],Iu[c]])
    eu=[uv_px(ED[0]+5,ED[1]+5),uv_px(ED[2]-5,ED[1]+5),uv_px(ED[2]-5,ED[3]-5),uv_px(ED[0]+5,ED[3]-5)]
    for i in range(4):
        j=(i+1)%4; q=[out[i],out[j],inn[j],inn[i]]; ctr=(out.mean(0)+inn.mean(0))/2
        for a,b,c in ((0,1,2),(0,2,3)):
            T=[q[a],q[b],q[c]]
            if np.cross(T[1]-T[0],T[2]-T[0])@((T[0]+T[1]+T[2])/3-ctr)<0: T=[T[0],T[2],T[1]]
            tris.append(T); uvs.append([eu[a],eu[b],eu[c]])
    return np.array(tris),np.array(uvs)
def tex(img_path,out=None):
    im=Image.open(img_path).convert('RGB'); x0,y0,x1,y1=FR; W,H=x1-x0,y1-y0
    s=max(W/im.width,H/im.height); im=im.resize((round(im.width*s),round(im.height*s)),Image.LANCZOS)
    l=(im.width-W)//2; t=(im.height-H)//2; im=im.crop((l,t,l+W,t+H))           # cover-crop: centre kept, never stretched
    A=Image.new('RGB',(N,N)); A.paste(im,(x0,y0))
    back=im.transpose(Image.FLIP_LEFT_RIGHT).filter(ImageFilter.GaussianBlur(40))
    back=Image.fromarray((np.asarray(back).astype(float)*0.55).astype(np.uint8)).resize((BK[2]-BK[0],BK[3]-BK[1]))
    A.paste(back,BK[:2])
    edge=tuple((np.asarray(im).reshape(-1,3).mean(0)*0.5).astype(int)); A.paste(edge,ED)
    out=out or os.path.join(OUTDIR,'Cape_Color.png'); A.save(out); print('texture ->',out); return out
if __name__=='__main__':
    if sys.argv[1]=='tex': tex(sys.argv[2],sys.argv[3] if len(sys.argv)>3 else None)
    else:
        T,UVt=build(); np.savez(os.path.join(HERE,'cape_geo.npz'),V=T.reshape(-1,3),F=np.arange(len(T)*3).reshape(-1,3),UVc=UVt)
        print('triangles',len(T))
