# Tone down the Tripo texture: muted Christmas red, warm off-white with recovered detail.
import sys, numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
src,dst=sys.argv[1],sys.argv[2]
im=Image.open(src).convert('RGB'); rgb=np.asarray(im).astype(float)/255
hsv=np.asarray(im.convert('HSV')).astype(float)/255; h,s,v=hsv[...,0],hsv[...,1],hsv[...,2]
red=np.clip((s-0.35)/0.3,0,1)                       # soft mask: 1 on the red cloth, 0 on whites/greys
# reds: deeper and a bit less saturated
s2=s*(1-0.22*red); v2=v*(1-0.24*red)
# whites/greys: compress highlights (0.93 avg -> ~0.84) and bring back local detail
w=1-red
base=gaussian_filter(v,6); detail=v-base
vw=0.10+0.78*np.clip(v,0,1)**1.15+detail*0.9
v2=v2*(1-w)+np.clip(vw,0,1)*w
out=np.asarray(Image.fromarray((np.stack([h,s2,v2],-1)*255).clip(0,255).astype(np.uint8),'HSV').convert('RGB')).astype(float)/255
warm=np.array([1.0,0.985,0.955])                     # slightly warm white instead of pure #FFFFFF
out=out*(1-w[...,None])+out*warm*w[...,None]
Image.fromarray((np.clip(out,0,1)*255).astype(np.uint8)).save(dst)
o=Image.open(dst).convert('HSV'); a=np.asarray(o).astype(float)/255; m=np.asarray(Image.open(dst)).max(2)>8
print('saturation mean',a[...,1][m].mean().round(3),'| value mean',a[...,2][m].mean().round(3),'| % sat>0.8',(a[...,1][m]>0.8).mean().round(3))
