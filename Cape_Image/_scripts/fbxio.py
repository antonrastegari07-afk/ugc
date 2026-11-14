# lossless binary FBX (7.x) read/write keeping property type codes
import struct, zlib, numpy as np
DT={'f':'<f4','d':'<f8','l':'<i8','i':'<i4','b':'u1'}
SC={'Y':'<h','C':'<?','I':'<i','L':'<q','F':'<f','D':'<d'}
def read(path):
    d=open(path,'rb').read(); ver=struct.unpack_from('<I',d,23)[0]; big=ver>=7500
    def rprop(o):
        t=chr(d[o]);o+=1
        if t in SC: v=struct.unpack_from(SC[t],d,o)[0];return (t,v),o+struct.calcsize(SC[t])
        if t in DT:
            n,enc,cl=struct.unpack_from('<III',d,o);o+=12;raw=d[o:o+cl];o+=cl
            if enc: raw=zlib.decompress(raw)
            return (t,np.frombuffer(raw,dtype=DT[t],count=n).copy()),o
        n=struct.unpack_from('<I',d,o)[0];o+=4;return (t,d[o:o+n]),o+n
    def rnode(o):
        end,np_,pl=struct.unpack_from('<QQQ' if big else '<III',d,o);o+=24 if big else 12
        nl=d[o];o+=1;name=d[o:o+nl].decode();o+=nl
        if end==0: return None,o
        props=[]
        for _ in range(np_): v,o=rprop(o);props.append(v)
        kids=[]
        while o<end:
            k,o=rnode(o)
            if k is None: break
            kids.append(k)
        return [name,props,kids],end
    o=27;nodes=[]
    while True:
        n,o=rnode(o)
        if n is None: break
        nodes.append(n)
    return ver,nodes,d[:27],d[o:]
def write(path,ver,nodes,header,footer):
    big=ver>=7500; hs=24 if big else 12; out=bytearray(header)
    def wprop(t,v):
        b=bytearray(t.encode())
        if t in SC: b+=struct.pack(SC[t],v)
        elif t in DT:
            raw=np.ascontiguousarray(v,dtype=DT[t]).tobytes(); c=zlib.compress(raw)
            b+=struct.pack('<III',len(v),1,len(c))+c
        else: b+=struct.pack('<I',len(v))+v
        return b
    def wnode(n):
        name,props,kids=n; start=len(out)
        out.extend(b'\0'*hs); out.append(len(name)); out.extend(name.encode())
        p0=len(out)
        for t,v in props: out.extend(wprop(t,v))
        pl=len(out)-p0
        if kids:
            for k in kids: wnode(k)
            out.extend(b'\0'*(hs+1))
        struct.pack_into('<QQQ' if big else '<III',out,start,len(out),len(props),pl)
    for n in nodes: wnode(n)
    out.extend(b'\0'*(hs+1))
    # footer: keep original footer id, recompute alignment padding
    fid=footer[:16] if len(footer)>=16 else b'\xfa\xbc\xab\x09\xd0\xc8\xd4\x66\xb1\x76\xfb\x83\x1c\xf7\x26\x7e'
    out.extend(fid); out.extend(b'\0'*4)
    pad=(16-(len(out)%16))%16
    if pad==0: pad=16
    out.extend(b'\0'*pad); out.extend(struct.pack('<I',ver)); out.extend(b'\0'*120)
    out.extend(b'\xf8\x5a\x8c\x6a\xde\xf5\xd9\x7e\xec\xe9\x0c\xe3\x75\x8f\x29\x0b')
    open(path,'wb').write(out)
def child(n,name): return [k for k in n[2] if k[0]==name]
