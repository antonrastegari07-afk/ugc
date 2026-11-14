# Tone down an over-saturated / over-bright Tripo texture: lower saturation, compress highlights, gentle contrast.
import sys,numpy as np
from PIL import Image
def fix(src,dst,sat=0.62,hi=0.9,gamma=1.08):
    im=Image.open(src).convert('RGB'); a=np.asarray(im).astype(float)/255
    import colorsys
    hsv=np.asarray(im.convert('HSV')).astype(float)/255
    hsv[...,1]*=sat                                   # less saturation
    v=hsv[...,2]; v=np.where(v>0.7,0.7+(v-0.7)*(hi-0.7)/0.3,v); hsv[...,2]=v**gamma   # soften highlights
    out=Image.fromarray((np.clip(hsv,0,1)*255).astype(np.uint8),'HSV').convert('RGB'); out.save(dst)
if __name__=='__main__': fix(sys.argv[1],sys.argv[2])
