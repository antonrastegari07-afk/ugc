import numpy as np, os
from PIL import Image, ImageFilter
S=1024
g=np.load('tex_geo.npz'); pos=g['pos']; nrm=g['nrm']; M=g['M']
col=np.asarray(Image.open('in/color.webp').convert('RGB'),float)/255
ref=np.asarray(Image.open('in/white_ref.webp').convert('L'),float)/255
# head bbox in the reference render  <->  mesh front (orthographic, calibrated on the orange render)
HX0,HX1,HY0,HY1=142,1111,132,1189
X0,X1,Z0,Z1=-0.05497,0.05497,0.05577,-0.05636
x,z=pos[...,0],pos[...,2]
px=HX0+(x-X0)/(X1-X0)*(HX1-HX0); py=HY0+(z-Z0)/(Z1-Z0)*(HY1-HY0)
nrm=nrm/(np.linalg.norm(nrm,axis=-1,keepdims=True)+1e-12)
front=M&(nrm[...,1]<-0.5)&(px>200)&(px<1060)&(py>400)&(py<1080)   # only the face area of the reference
def sample(img,px,py):
    h,w=img.shape; x0=np.clip(np.floor(px).astype(int),0,w-2); y0=np.clip(np.floor(py).astype(int),0,h-2); fx=np.clip(px-x0,0,1); fy=np.clip(py-y0,0,1)
    return img[y0,x0]*(1-fx)*(1-fy)+img[y0,x0+1]*fx*(1-fy)+img[y0+1,x0]*(1-fx)*fy+img[y0+1,x0+1]*fx*fy
v=sample(ref,px,py)*front
face=np.clip((v-0.30)/0.55,0,1)                     # white face (soft edge kept)
# remove the old orange face: replace bright/orange texels with the dark base
old=(col.max(2)>0.12)
old=np.asarray(Image.fromarray((old*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7)),float)/255>0.5
base=col.copy(); dark=np.median(col[~old],axis=0)
noise=np.asarray(Image.fromarray((np.random.default_rng(1).random((S,S))*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)),float)/255
base[old]=dark+ (noise[old,None]-0.5)*0.01
white=np.array([0.97,0.97,0.98])
newc=base*(1-face[...,None])+white*face[...,None]
os.makedirs('out',exist_ok=True)
sv=lambda a,n,mode: Image.fromarray((np.clip(a,0,1)*255+.5).astype(np.uint8),mode).save(f'out/{n}.png')
sv(newc,'WhiteFace_Color','RGB')
sv(face,'WhiteFace_Emissive','L')
sv(np.zeros((S,S)),'WhiteFace_Metalness','L')
sv(0.62-0.25*face,'WhiteFace_Roughness','L')
# normal: flat, with the face very slightly engraved
H=np.asarray(Image.fromarray((face*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)),float)/255
gx=(np.roll(H,-1,1)-np.roll(H,1,1))*0.5; gy=(np.roll(H,1,0)-np.roll(H,-1,0))*0.5
nm=np.stack([gx*3,gy*3,np.ones_like(H)],-1); nm/=np.linalg.norm(nm,axis=-1,keepdims=True)
sv(nm*0.5+0.5,'WhiteFace_Normal','RGB')
print('face texels',(face>0.5).sum())
