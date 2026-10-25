import numpy as np
def load(path):
    V=[];T=[];N=[];F=[]
    for line in open(path):
        p=line.split()
        if not p: continue
        if p[0]=='v': V.append([float(x) for x in p[1:4]])
        elif p[0]=='vt': T.append([float(x) for x in p[1:3]])
        elif p[0]=='vn': N.append([float(x) for x in p[1:4]])
        elif p[0]=='f': F.append([[int(i)-1 for i in q.split('/')] for q in p[1:4]])
    F=np.array(F)
    return np.array(V),np.array(T),np.array(N),F
