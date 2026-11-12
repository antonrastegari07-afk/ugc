import bpy, bmesh, sys, numpy as np, math
from mathutils import Vector, Matrix
D=sys.argv[-1]; TARGET=int(sys.argv[-2])
bpy.ops.wm.open_mainfile(filepath=D+'/src.blend')
o=[x for x in bpy.data.objects if x.type=='MESH'][0]; me=o.data
bm=bmesh.new(); bm.from_mesh(me)
img=bpy.data.images['santa_hat_3d_model_basecolor']; W,H=img.size; px=np.array(img.pixels[:]).reshape(H,W,4)
uvl=bm.loops.layers.uv.active
for f in bm.faces:
    uv=np.mean([l[uvl].uv for l in f.loops],axis=0); c=px[int(uv[1]%1*H)%H,int(uv[0]%1*W)%W,:3]
    f.material_index=0 if c[0]>c[1]*1.6 else 1
bmesh.ops.remove_doubles(bm,verts=bm.verts[:],dist=1e-5)
# canonical frame: boundary plane -> z=0, normal up, bangs side -> -Y, studs
c=Vector((-0.05,0.018,0.587)); n=Vector((0.013,0.219,0.976)).normalized(); SC=1.78
R=n.rotation_difference(Vector((0,0,1))).to_matrix().to_4x4()
M=Matrix.Scale(SC,4)@Matrix.Rotation(math.pi,4,'Z')@R@Matrix.Translation(-c)
bmesh.ops.transform(bm,matrix=M,verts=bm.verts[:])
pc=M@Vector((0.384,0.042,0.286)); print('pompom centre',[round(v,3) for v in pc])
# drop tripo pompom (rebuilt later) and everything white under the band
pom=[f for f in bm.faces if f.material_index==1 and (f.calc_center_median()-pc).length<0.26]
print('pompom faces removed',len(pom)); bmesh.ops.delete(bm,geom=pom,context='FACES')
ZC=-0.27
wf=[f for f in bm.faces if f.material_index==1]
geom=wf+list({e for f in wf for e in f.edges})+list({v for f in wf for v in f.verts})
bmesh.ops.bisect_plane(bm,geom=geom,plane_co=(0,0,ZC),plane_no=(0,0,1),clear_inner=True,dist=1e-5)
# remove leftovers: small loose islands
bm.faces.ensure_lookup_table()
seen=set(); comps=[]
for f in bm.faces:
    if f in seen: continue
    st=[f]; seen.add(f); cc=[]
    while st:
        g=st.pop(); cc.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h not in seen: seen.add(h); st.append(h)
    comps.append(cc)
comps.sort(key=len,reverse=True); print('components',[len(x) for x in comps])
for cc in comps[1:]: bmesh.ops.delete(bm,geom=cc,context='FACES')
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
bm.to_mesh(me); bm.free()
o.matrix_world=Matrix.Identity(4)
ma=[bpy.data.materials.new('red'),bpy.data.materials.new('white')]; idx=[q.material_index for q in me.polygons]; me.materials.clear(); [me.materials.append(m) for m in ma]
for q,i in zip(me.polygons,idx): q.material_index=i
ma[0].diffuse_color=(0.7,0.05,0.04,1); ma[1].diffuse_color=(0.9,0.9,0.92,1)
me.calc_loop_triangles(); print('tris before',len(me.loop_triangles))
md=o.modifiers.new('d','DECIMATE'); md.ratio=TARGET/len(me.loop_triangles)
bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier='d')
me.calc_loop_triangles(); co=np.array([v.co for v in me.vertices])
print('tris after',len(me.loop_triangles),'min',co.min(0).round(3),'max',co.max(0).round(3))
o.name='HatBase'
bpy.ops.wm.save_as_mainfile(filepath=D+'/hatbase.blend')
