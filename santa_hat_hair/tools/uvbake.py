import bpy, bmesh, sys, numpy as np
D=sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=D+'/geo.blend'); sc=bpy.context.scene
o=bpy.data.objects['SantaHat']; me=o.data
bpy.context.view_layer.objects.active=o; o.select_set(True)
part=np.array([a.value for a in me.attributes['part'].data])
uvd=me.uv_layers.active.data
for grp,(ua,ub) in (((0,),(0.004,0.300)),((1,2,4),(0.306,0.742))):
    for p in me.polygons: p.select=bool(part[p.index] in grp)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_mode(type='FACE')
    bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=0.02,area_weight=0.0,correct_aspect=True,scale_to_bounds=True)
    bpy.ops.object.mode_set(mode='OBJECT'); uvd=me.uv_layers.active.data
    for p in me.polygons:
        if part[p.index] in grp:
            for li in p.loop_indices: uvd[li].uv=(ua+uvd[li].uv[0]*(ub-ua),0.004+uvd[li].uv[1]*0.992)
# shade smooth normals for hat base
sc.render.engine='CYCLES'; sc.cycles.samples=128
S=1024
m=bpy.data.materials.new('b'); m.use_nodes=True; N=m.node_tree.nodes; L=m.node_tree.links
img=bpy.data.images.new('bk',S,S,float_buffer=True,is_data=True); tn=N.new('ShaderNodeTexImage'); tn.image=img; N.active=tn
em=N.new('ShaderNodeEmission'); geo=N.new('ShaderNodeNewGeometry'); at=N.new('ShaderNodeAttribute'); at.attribute_name='part'; out=N['Material Output']
me.materials.append(m)
sc.world=bpy.data.worlds.new('w')
def grab(): return np.array(img.pixels[:],dtype=np.float32).reshape(S,S,4)[::-1].copy()
sc.render.bake.margin=0
bpy.ops.object.bake(type='AO'); np.save(D+'/b_ao.npy',grab()[...,0])
L.new(em.outputs[0],out.inputs['Surface'])
sc.cycles.samples=1
L.new(geo.outputs['Position'],em.inputs['Color']); bpy.ops.object.bake(type='EMIT'); np.save(D+'/b_pos.npy',grab()[...,:3])
L.new(geo.outputs['Normal'],em.inputs['Color']); bpy.ops.object.bake(type='EMIT'); np.save(D+'/b_nrm.npy',grab()[...,:3])
L.new(at.outputs['Fac'],em.inputs['Color']); sc.render.bake.margin=0; bpy.ops.object.bake(type='EMIT'); g=grab(); np.save(D+'/b_part.npy',g[...,0])
em.inputs['Color'].default_value=(1,1,1,1); L.remove(em.inputs['Color'].links[0]); img.pixels.foreach_set(np.zeros(S*S*4,dtype=np.float32)); bpy.ops.object.bake(type='EMIT'); np.save(D+'/b_alpha.npy',grab()[...,0])
me.materials.clear()
bpy.ops.wm.save_as_mainfile(filepath=D+'/geo_uv.blend')
