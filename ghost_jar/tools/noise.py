import numpy as np
def _hash(ix,iy,iz,seed=0):
    h=(ix*73856093) ^ (iy*19349663) ^ (iz*83492791) ^ (seed*2654435761)
    h=h.astype(np.uint64)
    h^=h>>np.uint64(13); h*=np.uint64(0x5bd1e995); h&=np.uint64(0xffffffff); h^=h>>np.uint64(15)
    return h
def _rand(ix,iy,iz,seed): return (_hash(ix,iy,iz,seed)&np.uint64(0xffffff)).astype(np.float64)/0xffffff
def _grad(ix,iy,iz,seed):
    g=np.stack([_rand(ix,iy,iz,seed+k)*2-1 for k in range(3)],-1)
    return g/ (np.linalg.norm(g,axis=-1,keepdims=True)+1e-9)
def perlin(p,seed=0):
    i=np.floor(p).astype(np.int64); f=p-i
    u=f*f*f*(f*(f*6-15)+10)
    out=0
    def corner(dx,dy,dz):
        g=_grad(i[...,0]+dx,i[...,1]+dy,i[...,2]+dz,seed)
        return (g*(f-np.array([dx,dy,dz]))).sum(-1)
    n000=corner(0,0,0);n100=corner(1,0,0);n010=corner(0,1,0);n110=corner(1,1,0)
    n001=corner(0,0,1);n101=corner(1,0,1);n011=corner(0,1,1);n111=corner(1,1,1)
    l=lambda a,b,t:a+(b-a)*t
    x0=l(n000,n100,u[...,0]);x1=l(n010,n110,u[...,0]);x2=l(n001,n101,u[...,0]);x3=l(n011,n111,u[...,0])
    return l(l(x0,x1,u[...,1]),l(x2,x3,u[...,1]),u[...,2])
def fbm(p,oct=4,seed=0):
    s=0;a=0.5;n=0
    for o in range(oct):
        s+=a*perlin(p*(2**o),seed+o*7); n+=a; a*=0.5
    return s/n
def worley(p,seed=0):
    i=np.floor(p).astype(np.int64)
    F1=np.full(p.shape[:-1],9.);F2=np.full(p.shape[:-1],9.);ID=np.zeros(p.shape[:-1])
    for dx in (-1,0,1):
        for dy in (-1,0,1):
            for dz in (-1,0,1):
                c=i+np.array([dx,dy,dz])
                j=np.stack([_rand(c[...,0],c[...,1],c[...,2],seed+k) for k in range(3)],-1)
                d=np.linalg.norm(c+0.15+0.7*j-p,axis=-1)
                cid=_rand(c[...,0],c[...,1],c[...,2],seed+11)
                m=d<F1
                F2=np.where(m,F1,np.minimum(F2,d)); ID=np.where(m,cid,ID); F1=np.where(m,d,F1)
    return F1,F2,ID
