from PIL import Image, ImageFilter
import numpy as np, sys
ims=[]
for n in ('34','front','side'):
    a=np.asarray(Image.open(f'render_{n}.png').convert('RGB'),float)/255
    br=np.clip((a.max(2)-0.55)/0.45,0,1)[...,None]*a
    bl=np.asarray(Image.fromarray((br*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)),float)/255
    o=np.clip(a+bl*0.5,0,1); im=Image.fromarray((o*255).astype(np.uint8)); im.save(f'preview_{n}.png'); ims.append(im)
o=Image.new('RGB',(1920,800)); [o.paste(im,(640*i,0)) for i,im in enumerate(ims)]; o.save('sheet.png')
