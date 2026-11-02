import numpy as np
from PIL import Image, ImageDraw, ImageFilter
S=1024; img=np.zeros((S,S,3)); y=np.arange(S)[:,None]/S
# gold rect = v 0.25..1 (image rows 0..0.75S). outer wall lower part, inner, edges
gold_top=np.array([1.0,0.90,0.30]); gold_bot=np.array([0.95,0.70,0.05])
rows=np.linspace(0,1,int(0.75*S))[:,None]          # 0 at image top (v=1)
v=1-rows*0.75                                        # atlas v
band=np.zeros((len(rows),3))
# outer wall: v 0.25..0.625 (rect v 0..0.5) -> vertical gradient + cel highlight stripe
t=np.clip((v-0.25)/0.375,0,1)                       # 0 bottom, 1 top
c=gold_bot*(1-t)+gold_top*t
hl=np.exp(-((t-0.28)/0.05)**2)*0.6                   # painted highlight stripe (toon)
c=c*(1-hl)+np.array([1.0,0.98,0.85])*hl
inner=(v>=0.625)&(v<0.925); c=np.where(inner,np.array([0.85,0.60,0.04]),c)
edge=(v>=0.925); c=np.where(edge,np.array([1.0,0.90,0.50]),c)
img[:int(0.75*S)]=c[:,None,:]
# gems: v 0..0.25, u 0..0.25 -> ruby red with highlight
gx,gy=np.meshgrid(np.linspace(0,1,S//4),np.linspace(0,1,S//4))
r=np.hypot(gx-0.5,gy-0.5)
gem=np.array([0.85,0.08,0.22])*(1-0.5*r[...,None])+np.array([1,0.75,0.8])*np.exp(-((gx-0.38)**2+(gy-0.36)**2)/0.008)[...,None]
img[int(0.75*S):,:S//4]=np.clip(gem,0,1)
# outline: black
img[int(0.9*S):,int(0.5*S):int(0.6*S)]=0.0
img[int(0.75*S):,S//4:]=np.where(img[int(0.75*S):,S//4:]==0,0,img[int(0.75*S):,S//4:])
Image.fromarray((np.clip(img,0,1)*255).astype(np.uint8)).save('ToonCrown_Color.png')
rough=np.full((S,S),0.55); rough[int(0.75*S):,:S//4]=0.2; Image.fromarray((rough*255).astype(np.uint8)).save('ToonCrown_Roughness.png')
Image.fromarray(np.zeros((S,S),np.uint8)).save('ToonCrown_Metalness.png')
Image.fromarray(np.full((S,S,3),(128,128,255),np.uint8)).save('ToonCrown_Normal.png')
