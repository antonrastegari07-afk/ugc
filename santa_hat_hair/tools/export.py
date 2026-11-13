import bpy, sys, numpy as np
from mathutils import Vector
D=sys.argv[-1]
import os
NAME=os.environ.get('NAME','SantaHatHair_UGC')
bpy.ops.wm.open_mainfile(filepath=D+'/tex.blend'); sc=bpy.context.scene
o=bpy.data.objects['SantaHat']; o.name=NAME; o.data.name=NAME; me=o.data
co=np.array([v.co for v in me.vertices]); c=(co.min(0)+co.max(0))/2
print('bbox studs',(co.max(0)-co.min(0)).round(3),'centre',c.round(3),'offset from head centre (x,y,z-up)',(c-np.array([0,0,1.6])).round(3))
for v in me.vertices: v.co-=Vector(c)
# plain material for export
m=bpy.data.materials.new('SantaHatHair'); me.materials.clear(); me.materials.append(m)
for x in list(bpy.data.objects):
    if x!=o: bpy.data.objects.remove(x)
bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
for a in ('part','cn'):
    if a in me.attributes: me.attributes.remove(me.attributes[a])
bpy.ops.export_scene.fbx(filepath=D+'/'+NAME+'.fbx',use_selection=True,axis_forward='Z',axis_up='Y',apply_unit_scale=True,global_scale=0.01,mesh_smooth_type='OFF',bake_anim=False,add_leaf_bones=False)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=D+'/'+NAME+'.fbx')
for x in bpy.data.objects:
    if x.type=='MESH':
        x.data.calc_loop_triangles()
        print('REIMPORT',x.name,'studs',[round(v*100,3) for v in x.dimensions],'tris',len(x.data.loop_triangles),'mats',len(x.data.materials),'uv',len(x.data.uv_layers),'meshes',len([q for q in bpy.data.objects if q.type=='MESH']))
