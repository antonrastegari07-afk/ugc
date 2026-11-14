import struct, zlib, sys, numpy as np
def parse(path):
    d=open(path,'rb').read()
    ver=struct.unpack_from('<I',d,23)[0]
    big = ver>=7500
    def rprop(o):
        t=chr(d[o]);o+=1
        if t in 'YCILFD':
            f={'Y':'<h','C':'<?','I':'<i','L':'<q','F':'<f','D':'<d'}[t]
            v=struct.unpack_from(f,d,o)[0];return v,o+struct.calcsize(f)
        if t in 'fdlib':
            n,enc,cl=struct.unpack_from('<III',d,o);o+=12
            raw=d[o:o+cl];o+=cl
            if enc: raw=zlib.decompress(raw)
            dt={'f':'<f4','d':'<f8','l':'<i8','i':'<i4','b':'u1'}[t]
            return np.frombuffer(raw,dtype=dt,count=n),o
        if t in 'SR':
            n=struct.unpack_from('<I',d,o)[0];o+=4
            v=d[o:o+n];o+=n
            return (v.decode('utf8','replace') if t=='S' else v),o
        raise Exception('bad type '+t)
    def rnode(o):
        if big: end,np_,pl=struct.unpack_from('<QQQ',d,o);o+=24
        else: end,np_,pl=struct.unpack_from('<III',d,o);o+=12
        nl=d[o];o+=1
        name=d[o:o+nl].decode();o+=nl
        if end==0: return None,o
        props=[]
        for _ in range(np_):
            v,o=rprop(o);props.append(v)
        kids=[]
        while o<end:
            k,o=rnode(o)
            if k is None: break
            kids.append(k)
        return {'name':name,'props':props,'kids':kids},end
    o=27;nodes=[]
    while o<len(d)-200:
        n,o=rnode(o)
        if n is None: break
        nodes.append(n)
    return ver,nodes
def find(n,name):
    return [k for k in n['kids'] if k['name']==name]
