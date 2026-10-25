# GhostVac UGC - geometry (Blender bpy). Units = studs, Z up, character front = -Y, torso centered at origin (2x2x1).
import bpy, bmesh, math, numpy as np, sys
from mathutils import Vector, Matrix
OUT=sys.argv[-1]
TEX=1024; PAD=8/TEX
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
TY=1.10  # tank axis y (caps sit on the back plate)
R={
 'ghost':(0.0,0.5,0.5,1.0),'ghost_cap':(0.5,0.875,0.625,1.0),'outline':(0.625,0.875,0.75,1.0),
 'jamb':(0.75,0.875,0.875,1.0),'bubble':(0.875,0.0,1.0,0.0625),'conn':(0.875,0.875,1.0,1.0),
 'top':(0.5,0.5,1.0,0.6875),'bottom':(0.5,0.6875,1.0,0.875),'bars':(0.75,0.875,0.875,1.0),
 'inner':(0.0,0.25,0.5,0.5),'cloud':(0.5,0.25,0.75,0.5),'smokewall':(0.75,0.375,1.0,0.5),'plate':(0.75,0.25,1.0,0.375),
 'hose':(0.0,0.0,0.5,0.125),
 'strapL':(0.0,0.125,0.25,0.25),'strapR':(0.25,0.125,0.5,0.25),
 'stock':(0.5,0.125,0.625,0.25),'gunbody':(0.625,0.125,0.75,0.25),'barrel':(0.75,0.125,0.875,0.25),'fins':(0.875,0.125,1.0,0.25),'funnel':(0.5,0.0,0.625,0.125),
 'handle':(0.625,0.0,0.75,0.125),'clips':(0.75,0.0,0.875,0.125),'chest':(0.875,0.0,1.0,0.125),
}
NAMES=['inner','smokewall','cloud','outline','ghost','top','bottom','bars','hose','conn','stock','gunbody','barrel','fins','funnel','handle','clips','strapL','strapR','chest','plate','bubble','thandle','collar']
PID={k:i for i,k in enumerate(NAMES)}
def rmap(rect,u,v):
    u0,v0,u1,v1=rect
    return (u0+PAD+(u1-u0-2*PAD)*u, v0+PAD+(v1-v0-2*PAD)*v)
def coll(name):
    c=bpy.data.collections.new(name); scene.collection.children.link(c); return c
C={n:coll(n) for n in ['Tank','Tank_Inner_Inverted','Smoke','Ghost','Ghost_Outline_Inverted','Hose','Gun','Straps','Lights','GhostVac_UGC','Preview_Mannequin']}
def mkobj(name,col,bm):
    me=bpy.data.meshes.new(name); bmesh.ops.triangulate(bm,faces=bm.faces[:]); bm.to_mesh(me); bm.free()
    ob=bpy.data.objects.new(name,me); C[col].objects.link(ob); return ob
def new_bm():
    bm=bmesh.new(); uvl=bm.loops.layers.uv.new('UVMap'); return bm,uvl

# ---------- generic lathe (axis vertical through (cx,cy)), theta measured from +Y toward +X ----------
def lathe(bm,uvl,profile,N,rect,cx=0.0,cy=0.0,invert=False,deform=None,skip=None,theta0=-math.pi,uflip=False,smooth=True):
    L=[0]
    for a,b in zip(profile[:-1],profile[1:]): L.append(L[-1]+math.hypot(b[0]-a[0],b[1]-a[1]))
    L=[x/L[-1] for x in L]
    dz=profile[-1][1]-profile[0][1]
    up=(dz>0) if abs(dz)>1e-9 else (profile[1][1]>profile[0][1])
    flip=not (invert!=up)   # theta runs clockwise seen from above here
    rings=[]
    for i,(r,z) in enumerate(profile):
        if r==0: rings.append([bm.verts.new((cx,cy,z))]); continue
        ring=[]
        for j in range(N):
            th=theta0+2*math.pi*j/N; rr,zz=r,z
            if deform: rr,zz=deform(th,i,r,z)
            ring.append(bm.verts.new((cx+rr*math.sin(th),cy+rr*math.cos(th),zz)))
        rings.append(ring)
    faces=[]
    def face(vs,uvs,key):
        if skip and skip(*key): return
        if flip: vs=vs[::-1]; uvs=uvs[::-1]
        f=bm.faces.new(vs); f.smooth=smooth
        for lp,uv in zip(f.loops,uvs): lp[uvl].uv=rmap(rect,*uv)
        faces.append(f)
    for i in range(len(rings)-1):
        A,B=rings[i],rings[i+1]; va,vb=L[i],L[i+1]
        for j in range(N):
            u0=j/N; u1=(j+1)/N; j1=(j+1)%N
            if len(A)==1: face([A[0],B[j],B[j1]],[((u0+u1)/2,va),(u0,vb),(u1,vb)],(i,j))
            elif len(B)==1: face([A[j],B[0],A[j1]],[(u0,va),((u0+u1)/2,vb),(u1,va)],(i,j))
            else: face([A[j],B[j],B[j1],A[j1]],[(u0,va),(u0,vb),(u1,vb),(u1,va)],(i,j))
    return rings

# ---------- MACHINE BLOCKS (octagonal, flat faces, a flat face toward +Y) ----------
OCT0=-math.pi+math.pi/8
TOP=[(0.47,0.44),(0.49,0.455),(0.525,0.50),(0.525,0.60),(0.50,0.64),(0.525,0.68),(0.525,0.72),(0.47,0.77),(0.32,0.80),(0.14,0.82),(0,0.82)]
BOT=[(0,-0.90),(0.30,-0.90),(0.50,-0.87),(0.55,-0.82),(0.55,-0.70),(0.52,-0.665),(0.55,-0.63),(0.55,-0.53),(0.52,-0.475),(0.47,-0.455)]
def top_fn():
    bm,uvl=new_bm(); lathe(bm,uvl,TOP[::-1],8,R['top'],cy=TY,theta0=OCT0,smooth=False); return mkobj('Block_Top','Tank',bm)
def bottom_fn():
    bm,uvl=new_bm(); lathe(bm,uvl,BOT,8,R['bottom'],cy=TY,theta0=OCT0,smooth=False); return mkobj('Block_Bottom','Tank',bm)
RIN=0.42
def collars_fn():   # round rings where the round glass meets the octagonal blocks
    bm,uvl=new_bm()
    for z0,z1 in ((-0.475,-0.425),(0.425,0.465)):
        lathe(bm,uvl,[(RIN,z0),(0.48,z0),(0.48,z1),(RIN,z1),(RIN,z0)],24,R['jamb'],cy=TY,invert=True)
    return mkobj('Glass_Collars','Tank',bm)
def bars_fn():
    bm,uvl=new_bm()
    for sx in (-1,1):
        box(bm,uvl,(sx*0.457,TY,0.0),(0.05,0.10,0.96),R['bars'])          # stays outside the glass (r=0.42)
        for zc in (-0.40,0.40): box(bm,uvl,(sx*0.470,TY,zc),(0.06,0.15,0.07),R['bars'])
    return mkobj('Glass_Bars','Tank',bm)
parts=[]
def ghost_part(): pass
# ---------- INNER inverted shell ----------
def handle_top_fn():
    bm,uvl=new_bm()
    pts=[(x_,TY+0.30,0.80+0.16*math.sin(math.pi*(x_+0.30)/0.60)) for x_ in np.linspace(-0.30,0.30,9)]
    pts=[(-0.30,TY+0.30,0.74)]+pts+[(0.30,TY+0.30,0.74)]
    sweep(bm,uvl,pts,circle(0.03,6),R['bars'],ref=Vector((0,1,0)))
    return mkobj('Top_Handle','Tank',bm)
def bubbles_fn():
    bm,uvl=new_bm()
    for (ang,rad,zc,sz) in ((55,0.31,-0.12,0.035),(-60,0.30,0.05,0.028),(30,0.34,0.24,0.022),(-35,0.33,-0.26,0.03)):
        a_=math.radians(ang); cx,cy=math.sin(a_)*rad,TY+math.cos(a_)*rad
        lathe(bm,uvl,[(0,zc+sz),(sz*0.87,zc+sz*0.5),(sz*0.87,zc-sz*0.5),(0,zc-sz)],6,R['bubble'],cx=cx,cy=cy)
    return mkobj('Bubbles','Smoke',bm)
def inner_fn():
    bm,uvl=new_bm()
    lathe(bm,uvl,[(0,-0.52),(RIN,-0.52),(RIN,-0.1),(RIN,0.52),(0,0.52)],28,R['inner'],cy=TY,invert=True)
    return mkobj('Tank_Inner_Inverted','Tank_Inner_Inverted',bm)
# ---------- CLOUD + smoke side ----------
def cloud_h(x,y):
    rng=np.random.default_rng(11)
    blobs=[(0.0,0.0,0.24,0.10)]+[(r*math.cos(a),r*math.sin(a),rng.uniform(0.08,0.12),rng.uniform(0.05,0.085))
           for a,r in zip(np.linspace(0,2*math.pi,11,endpoint=False)+rng.uniform(-0.2,0.2,11),rng.uniform(0.15,0.32,11))]
    vals=[hh*max(0.0,1-((x-bx)**2+(y-by)**2)/br**2)**1.5 for bx,by,br,hh in blobs]
    return sum(v**6 for v in vals)**(1/6)
CB=-0.46; CR=0.415
def cloud_fn():
    bm,uvl=new_bm(); Nc=28; rings=5
    center=bm.verts.new((0,TY,CB+cloud_h(0,0))); allr=[]
    for k in range(1,rings+1):
        t=k/rings; ring=[]
        for j in range(Nc):
            th=2*math.pi*j/Nc; x,y=CR*t*math.cos(th),CR*t*math.sin(th)
            ring.append(bm.verts.new((x,TY+y,CB+cloud_h(x,y)*(1-t**6))))
        allr.append(ring)
    def setuv(f):
        f.smooth=True
        for lp in f.loops:
            p=lp.vert.co; lp[uvl].uv=rmap(R['cloud'],0.5+p.x/(2*CR),0.5+(p.y-TY)/(2*CR))
    for j in range(Nc): setuv(bm.faces.new([center,allr[0][j],allr[0][(j+1)%Nc]]))
    for k in range(rings-1):
        for j in range(Nc): setuv(bm.faces.new([allr[k][j],allr[k+1][j],allr[k+1][(j+1)%Nc],allr[k][(j+1)%Nc]]))
    return mkobj('Smoke_Cloud','Smoke',bm)
def smokewall_fn():
    bm,uvl=new_bm()
    lathe(bm,uvl,[(CR,CB),(CR,-0.55),(CR,-0.66)],28,R['smokewall'],cy=TY,theta0=-math.pi)
    return mkobj('Smoke_Side','Smoke',bm)
# ---------- GHOST + OUTLINE ----------
GH=[(0,0.635),(0.06,0.627),(0.105,0.605),(0.138,0.57),(0.155,0.53),(0.158,0.49),(0.153,0.45),(0.145,0.41),(0.138,0.37),(0.133,0.33),(0.130,0.295),(0.128,0.265)]
GS=1.5; GZ0=-0.385  # world z of the hem
def ghost_deform(th,i,r,z):
    # lathe theta from +Y; here local front is +Y (theta=0)
    x=math.sin(th); y=math.cos(th); side=abs(x)
    arm=math.exp(-((math.atan2(abs(y),side))/0.45)**2)*math.exp(-((z-0.43)/0.06)**2)
    rr=r+0.085*arm; zz=z-0.02*arm
    if i==len(GH)-1: zz+=0.022*math.sin(5*th)
    elif i==len(GH)-2: zz+=0.008*math.sin(5*th)
    rr*=1-0.06*abs(y)*(z>0.45)
    return rr,zz
def ghost_geo(bm,uvl,rect,cap_rect,Ng,cap=True):
    rings=lathe(bm,uvl,GH,Ng,rect,deform=ghost_deform)   # front (+Y) at u=0.5
    if cap:
        c=bm.verts.new((0,0,0.29)); ring=rings[-1]
        for j in range(len(ring)):
            f=bm.faces.new([c,ring[j],ring[(j+1)%len(ring)]]); f.smooth=True
            for lp in f.loops:
                p=lp.vert.co; lp[uvl].uv=rmap(cap_rect,0.5+p.x/0.4,0.5+p.y/0.4)
    for v in bm.verts:
        v.co=Vector((v.co.x*GS,TY+v.co.y*GS,GZ0+(v.co.z-0.265)*GS))
def ghost_fn():
    bm,uvl=new_bm(); ghost_geo(bm,uvl,R['ghost'],R['ghost_cap'],26); return mkobj('Ghost','Ghost',bm)
OFF=0.012
def outline_fn():
    bm,uvl=new_bm(); ghost_geo(bm,uvl,R['outline'],R['outline'],26,cap=False)
    bm.normal_update()
    for v in bm.verts: v.co=v.co+v.normal*OFF
    bmesh.ops.reverse_faces(bm,faces=bm.faces[:])
    cu=rmap(R['outline'],0.5,0.5)
    for f in bm.faces:
        for lp in f.loops: lp[uvl].uv=cu
    return mkobj('Ghost_Outline','Ghost_Outline_Inverted',bm)
# ---------- sweep along a polyline (tube or rectangle section) ----------
def sweep(bm,uvl,pts,section,rect,ref=Vector((1,0,0)),caps=True,umul=1.0,normal_fn=None,closed=False):
    pts=[Vector(p) for p in pts]; n=len(pts)
    L=[0]
    for a,b in zip(pts[:-1],pts[1:]): L.append(L[-1]+(b-a).length)
    rings=[]
    if closed: L.append(L[-1]+(pts[0]-pts[-1]).length)
    for i,p in enumerate(pts):
        t=((pts[(i+1)%n]-pts[(i-1)%n]) if closed else (pts[min(i+1,n-1)]-pts[max(i-1,0)])).normalized()
        if normal_fn:
            side=t.cross(normal_fn(p))
        else:
            side=(ref-ref.dot(t)*t)
            if side.length<1e-6: side=Vector((0,1,0))-Vector((0,1,0)).dot(t)*t
        side.normalize(); nor=t.cross(side)
        rings.append([bm.verts.new(p+side*sx+nor*sy) for sx,sy in section])
    m=len(section)
    for i in range(n if closed else n-1):
        i1=(i+1)%n
        for k in range(m):
            k1=(k+1)%m
            f=bm.faces.new([rings[i][k],rings[i][k1],rings[i1][k1],rings[i1][k]]); f.smooth=(m>4)
            for lp,(u,v) in zip(f.loops,[(L[i],k),(L[i],k+1),(L[i+1],k+1),(L[i+1],k)]):
                lp[uvl].uv=rmap(rect,u/L[-1],v/m)
    if caps and not closed:
        for ring,rev in ((rings[0],True),(rings[-1],False)):
            c=bm.verts.new(sum((v.co for v in ring),Vector())/m)
            for k in range(m):
                vs=[c,ring[k],ring[(k+1)%m]]
                if rev: vs=vs[::-1]
                f=bm.faces.new(vs)
                for lp in f.loops: lp[uvl].uv=rmap(rect,0.0 if rev else 1.0,0.5)
    return rings
def bezier(P,n):
    P=[Vector(p) for p in P]; out=[]
    for i in range(n+1):
        t=i/n; out.append(P[0]*(1-t)**3+P[1]*3*t*(1-t)**2+P[2]*3*t*t*(1-t)+P[3]*t**3)
    return out
def circle(r,m): return [(r*math.cos(2*math.pi*k/m),r*math.sin(2*math.pi*k/m)) for k in range(m)]
# ---------- HOSE + connectors ----------
GX=-0.84  # gun axis x (character's right side, front is -Y)
HOSE_C=[(0,TY,0.86),(0,TY+0.02,1.12),(-0.16,TY+0.14,1.30),(-0.42,TY+0.36,1.12),(-0.52,TY+0.46,0.66),(-0.58,TY+0.48,0.26),
        (-0.72,TY+0.46,0.10),(-0.86,TY+0.42,0.30),(-0.92,TY+0.38,0.80),(-0.92,TY+0.26,1.16),(-0.88,TY+0.10,1.30),(GX,TY+0.02,1.22),(GX,TY,1.10),(GX,TY,1.02)]
def hose_fn():
    bm,uvl=new_bm(); sweep(bm,uvl,catmull(HOSE_C,2),circle(0.07,6),R['hose'],ref=Vector((0,1,0)))
    return mkobj('Hose','Hose',bm)
def box(bm,uvl,center,size,rect,rot=None):
    cx,cy,cz=center; sx,sy,sz=[s/2 for s in size]
    V=[Vector((x,y,z)) for x in (-sx,sx) for y in (-sy,sy) for z in (-sz,sz)]
    if rot: V=[rot@v for v in V]
    vs=[bm.verts.new(Vector(center)+v) for v in V]
    F=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
    for fi,fc in enumerate(F):
        f=bm.faces.new([vs[i] for i in fc])
        for lp,(u,v) in zip(f.loops,[(0,0),(1,0),(1,1),(0,1)]):
            cu,cv=(fi%3)/3,(fi//3)/2
            lp[uvl].uv=rmap(rect,cu+u/3*0.9,cv+v/2*0.9)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces[-6:])
def conn_fn():
    bm,uvl=new_bm()
    lathe(bm,uvl,[(0,0.88),(0.10,0.88),(0.10,0.81),(0,0.81)],8,R['conn'],cy=TY)
    lathe(bm,uvl,[(0,1.05),(0.10,1.05),(0.10,0.95),(0,0.95)],8,R['conn'],cx=GX,cy=TY)
    lathe(bm,uvl,[(0,0.52),(0.045,0.52),(0.045,0.0),(0,0.0)],6,R['conn'],cx=GX-0.20,cy=TY+0.10)   # side energy cell
    lathe(bm,uvl,[(0,0.20),(0.05,0.20),(0.05,0.13),(0,0.13)],6,R['conn'],cx=GX-0.10,cy=TY+0.215)   # dial knob
    lathe(bm,uvl,[(0,-0.62),(0.06,-0.62),(0.06,-0.66),(0,-0.66)],6,R['conn'],cx=0.0,cy=TY+0.53)    # tank: pressure valve body (front of bottom block)
    return mkobj('Hose_Connectors','Hose',bm)
# ---------- GUN (proton blaster, ~2 studs long, stowed vertically, emitter down) ----------
def stock_fn():     # rear power block
    bm,uvl=new_bm()
    lathe(bm,uvl,[(0,0.97),(0.15,0.97),(0.20,0.93),(0.20,0.62),(0.17,0.58),(0,0.58)],8,R['stock'],cx=GX,cy=TY,theta0=OCT0,smooth=False)
    return mkobj('Gun_Stock','Gun',bm)
def gunbody_fn():   # main body
    bm,uvl=new_bm()
    lathe(bm,uvl,[(0,0.60),(0.19,0.60),(0.215,0.56),(0.215,0.06),(0.18,0.0),(0,0.0)],8,R['gunbody'],cx=GX,cy=TY,theta0=OCT0,smooth=False)
    return mkobj('Gun_Body','Gun',bm)
def barrel_fn():    # inner barrel tube
    bm,uvl=new_bm()
    lathe(bm,uvl,[(0,0.02),(0.09,0.02),(0.09,-0.78),(0,-0.78)],8,R['barrel'],cx=GX,cy=TY,theta0=OCT0,smooth=False)
    return mkobj('Gun_Barrel','Gun',bm)
def fins_fn():      # heat-sink fins on the barrel
    bm,uvl=new_bm()
    for zt in (-0.14,-0.34,-0.54):
        lathe(bm,uvl,[(0.088,zt),(0.15,zt-0.01),(0.15,zt-0.07),(0.088,zt-0.08)],8,R['fins'],cx=GX,cy=TY,theta0=OCT0,smooth=False)
    return mkobj('Gun_Fins','Gun',bm)
def funnel_fn():    # emitter head
    bm,uvl=new_bm()
    lathe(bm,uvl,[(0,-0.74),(0.12,-0.74),(0.17,-0.80),(0.18,-0.96),(0.15,-1.01),(0.10,-1.01),(0.08,-0.97),(0,-0.97)][::-1],8,R['funnel'],cx=GX,cy=TY,theta0=OCT0,smooth=False)
    return mkobj('Gun_Emitter','Gun',bm)
def handle_fn():    # pistol grip, front grip, trigger, trigger guard
    bm,uvl=new_bm()
    box(bm,uvl,(GX-0.29,TY,0.74),(0.30,0.11,0.13),R['handle'],Matrix.Rotation(math.radians(22),3,'Y'))
    box(bm,uvl,(GX-0.29,TY,0.10),(0.26,0.10,0.11),R['handle'])
    box(bm,uvl,(GX-0.22,TY,0.62),(0.07,0.03,0.08),R['handle'])
    box(bm,uvl,(GX-0.25,TY,0.565),(0.14,0.03,0.025),R['handle'])
    return mkobj('Gun_Grips','Gun',bm)
def clips_fn():     # tank clips + top rail + sight
    bm,uvl=new_bm()
    for z in (0.40,-0.30):
        box(bm,uvl,(-0.555,TY,z),(0.14,0.12,0.08),R['clips'])
    box(bm,uvl,(GX,TY+0.225,0.30),(0.08,0.04,0.56),R['clips'])                 # rail on the visible face
    box(bm,uvl,(GX,TY+0.27,0.42),(0.07,0.06,0.16),R['clips'])                  # sight
    box(bm,uvl,(GX+0.205,TY+0.06,0.30),(0.04,0.20,0.40),R['clips'])            # side armour plate (tank side)
    for k_ in range(3):                                                         # emitter prongs
        a_=math.radians(90+k_*120); ox,oy=math.sin(a_)*0.135,math.cos(a_)*0.135
        box(bm,uvl,(GX+ox,TY+oy,-1.06),(0.045,0.045,0.15),R['clips'])            # sunk into the emitter rim
    return mkobj('Gun_Rail_Clips','Gun',bm)
# ---------- STRAPS (backpack style: over the shoulder, down the front, back under the arm) ----------
D=0.12    # strap centre-line distance from the torso surface (loose fit for other body types)
CA=0.15   # shoulder rounding: arc centre inset from the torso edge
def arc(c,rad,a0,a1,nseg,x):
    return [(x,c[0]+rad*math.cos(a),c[1]+rad*math.sin(a)) for a in np.linspace(a0,a1,nseg)]
def catmull(P,sub=3):
    P=[Vector(p) for p in P]; P=[P[0]]+P+[P[-1]]; out=[]
    for i in range(1,len(P)-2):
        p0,p1,p2,p3=P[i-1],P[i],P[i+1],P[i+2]
        for k in range(sub):
            t=k/sub
            out.append(0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t**3))
    out.append(P[-2]); return out
# backpack straps (reference: classic Roblox backpack): leave the top of the pack, go forward over the shoulder,
# round the front edge, run down the chest, round the bottom corner and go back under the arm to the bottom of the pack
SD=0.045; SX=0.71
Y0=-0.5-SD; ZT=1.0+SD; ZB=-0.58; CR_=0.13
def strap_path(x):
    sx=math.copysign(1,x)
    ctrl=[(sx*0.34,0.84,0.93),(sx*0.50,0.72,0.97),(sx*0.68,0.60,1.02),(x,0.42,ZT),(x,0.15,ZT),(x,-0.10,ZT)]
    ctrl+=[(x,Y0+CR_-CR_*math.sin(t),ZT-CR_+CR_*math.cos(t)) for t in np.linspace(0,math.pi/2,4)]   # front-top corner
    ctrl+=[(x,Y0,0.55),(x,Y0,0.25)]
    ctrl+=[(x,Y0+CR_-CR_*math.cos(t),ZB+CR_-CR_*math.sin(t)) for t in np.linspace(0,math.pi/2,4)]   # bottom-front corner
    ctrl+=[(x,0.10,ZB),(x,0.45,ZB),(sx*0.56,0.62,-0.46),(sx*0.44,0.74,-0.38),(sx*0.34,0.84,-0.36)]
    out=[]; 
    for p in ctrl:
        if not out or (Vector(p)-Vector(out[-1])).length>0.02: out.append(p)
    return catmull(out,1)
def strap_normal(p):
    # flat side of the strap faces away from the shoulder/torso
    q=Vector((0,min(max(p.y,-0.5+CR_),0.5),min(max(p.z,ZB+CR_),1.0-CR_)))
    d=Vector((0,p.y-q.y,p.z-q.z))
    if p.y>0.5 and p.z<0.9: d=Vector((0,0.2,-1.0))
    return d.normalized() if d.length>1e-6 else Vector((0,0,1))
def rsec(w,t,m=8):
    out=[]
    for k in range(m):
        a=2*math.pi*k/m; cx=w/2-t/2
        out.append((math.copysign(cx,math.cos(a))+t/2*math.cos(a) if abs(math.cos(a))>1e-6 else t/2*math.cos(a), t/2*math.sin(a)))
    return out
SEC=rsec(0.17,0.04,6)
def torso_normal(p):
    q=Vector((min(max(p.x,-1),1),min(max(p.y,-0.5),0.5),min(max(p.z,-1),1)))
    d=p-q
    return d.normalized() if d.length>1e-6 else Vector((0,1,0))
def strap_fn(name,x,rect):
    bm,uvl=new_bm()
    sweep(bm,uvl,strap_path(x),SEC,rect,normal_fn=strap_normal)
    return mkobj(name,'Straps',bm)
def chest_fn():
    bm,uvl=new_bm()
    box(bm,uvl,(0,Y0-0.03,0.62),(1.36,0.02,0.05),R['chest'])
    box(bm,uvl,(0,Y0-0.045,0.62),(0.10,0.03,0.08),R['chest'])
    return mkobj('Chest_Strap','Straps',bm)

order=[('inner',inner_fn),('cloud',cloud_fn),('bubble',bubbles_fn),('outline',outline_fn),('ghost',ghost_fn),
       ('top',top_fn),('bottom',bottom_fn),('collar',collars_fn),('bars',bars_fn),('hose',hose_fn),('conn',conn_fn),('stock',stock_fn),('gunbody',gunbody_fn),('barrel',barrel_fn),('fins',fins_fn),('funnel',funnel_fn),
       ('handle',handle_fn),('clips',clips_fn),('strapL',lambda:strap_fn('Strap_L',-SX,R['strapL'])),
       ('strapR',lambda:strap_fn('Strap_R',SX,R['strapR']))]
objs=[(k,fn()) for k,fn in order]
# ---------- raise the whole machine higher on the back (straps are built in place) ----------
DZ=0.30
for k_,ob in objs:
    if k_ not in ('strapL','strapR'):
        for v in ob.data.vertices: v.co.z+=DZ
# ---------- fuse ----------
me=bpy.data.meshes.new('GhostVac_UGC'); fin=bpy.data.objects.new('GhostVac_UGC',me); C['GhostVac_UGC'].objects.link(fin)
bm=bmesh.new(); pid=[]
for k,ob in objs:
    n0=len(bm.faces); bm.from_mesh(ob.data); bm.faces.ensure_lookup_table()
    key='jamb' if False else k
    pid+=[PID[k]]*(len(bm.faces)-n0)
bm.to_mesh(me); bm.free()
pid=np.array(pid)
uvd=me.uv_layers[0].data
P=np.array([v.co[:] for v in me.vertices]); tri=np.array([list(p.vertices) for p in me.polygons])
uv=np.array([[uvd[l].uv[:] for l in p.loop_indices] for p in me.polygons])
ln=np.array([me.corner_normals[l].vector[:] for p in me.polygons for l in p.loop_indices]).reshape(-1,3,3)
np.savez(OUT+'/geo.npz',P=P[tri],UV=uv,N=ln,pid=pid)
inv={v:k for k,v in PID.items()}
for k in sorted(set(pid)):
    t=P[tri[pid==k]]; vol=(np.einsum('ij,ij->i',t[:,0],np.cross(t[:,1],t[:,2]))).sum()/6
    print('%-10s tris %4d signed_vol %+.4f'%(inv[k],(pid==k).sum(),vol))
fn=np.cross(P[tri][:,1]-P[tri][:,0],P[tri][:,2]-P[tri][:,0]); fc=P[tri].mean(1)
m=pid==PID['cloud']; print('cloud normals up:',np.mean(fn[m][:,2]>0))
m=(pid==PID['ghost'])&(fc[:,2]<GZ0+0.02*GS)&(np.hypot(fc[:,0],fc[:,1]-TY)<0.12); print('ghost cap faces down:',np.mean(fn[m][:,2]<0),m.sum())
print('TOTAL TRIS',len(me.polygons)); print('BBOX',P.min(0).round(3),P.max(0).round(3),'SIZE',(P.max(0)-P.min(0)).round(3))
# ---------- preview mannequin (not exported) ----------
def mbox(name,c,s):
    bm=bmesh.new(); bmesh.ops.create_cube(bm,size=1.0)
    for v in bm.verts: v.co=Vector((v.co.x*s[0]+c[0],v.co.y*s[1]+c[1],v.co.z*s[2]+c[2]))
    me=bpy.data.meshes.new(name); bm.to_mesh(me); bm.free(); o=bpy.data.objects.new(name,me); C['Preview_Mannequin'].objects.link(o)
mbox('Torso',(0,0,0),(2,1,2)); mbox('ArmL',(-1.5,0,0),(1,1,2)); mbox('ArmR',(1.5,0,0),(1,1,2))
mbox('LegL',(-0.5,0,-2),(1,1,2)); mbox('LegR',(0.5,0,-2),(1,1,2)); mbox('Head',(0,0,1.6),(1.2,1.2,1.2))
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/GhostVac_geo.blend')
