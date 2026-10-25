import struct, sys, lz4.block, zstandard
def read_chunks(data):
    assert data[:8]==b'<roblox!', data[:8]
    pos=32; chunks=[]
    while pos < len(data):
        name=data[pos:pos+4]; clen,ulen,_=struct.unpack('<III',data[pos+4:pos+16]); pos+=16
        if clen==0: body=data[pos:pos+ulen]; raw=body; pos+=ulen
        else:
            raw=data[pos:pos+clen]; pos+=clen
            if raw[:4]==b'\x28\xb5\x2f\xfd': body=zstandard.ZstdDecompressor().decompress(raw,max_output_size=ulen)
            else: body=lz4.block.decompress(raw,uncompressed_size=ulen)
        chunks.append([name,body,clen,ulen])
        if name==b'END\x00': break
    return chunks
