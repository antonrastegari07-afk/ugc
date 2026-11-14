import numpy as np, collections
def components(V,F):
    par=np.arange(len(V))
    def f(x):
        while par[x]!=x: par[x]=par[par[x]]; x=par[x]
        return x
    for a,b,c in F:
        for u,v in((a,b),(b,c)):
            ru,rv=f(u),f(v)
            if ru!=rv: par[ru]=rv
    comp=np.array([f(F[i,0]) for i in range(len(F))])
    ids={c:i for i,(c,_) in enumerate(collections.Counter(comp).most_common())}
    return np.array([ids[c] for c in comp])
