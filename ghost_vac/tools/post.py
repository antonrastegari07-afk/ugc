from PIL import Image, ImageFilter, ImageDraw
import numpy as np
names=[('back','Dos'),('34L','3/4 dos gauche'),('34R','3/4 dos droit'),('side','Profil'),('top','Plongée'),('noemis','Sans emissive'),('front','Face'),('zoom','Zoom réservoir')]
ims=[]
for n,lab in names:
    a=np.asarray(Image.open(f'r_{n}.png').convert('RGB'),float)/255
    if n!='noemis':
        br=np.clip((a.max(2)-0.6)/0.4,0,1)[...,None]*a
        bl=np.asarray(Image.fromarray((br*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10)),float)/255
        a=np.clip(a+bl*0.5,0,1)
    im=Image.fromarray((a*255).astype(np.uint8)); ImageDraw.Draw(im).text((12,10),lab,fill=(235,235,235)); ims.append(im)
W,H=ims[0].size; o=Image.new('RGB',(W*4,H*2))
for i,im in enumerate(ims): o.paste(im,((i%4)*W,(i//4)*H))
o.save('sheet.png')
