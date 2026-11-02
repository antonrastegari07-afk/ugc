import bpy, sys
from mathutils import Vector
D=sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=D+'/geo.blend')
o=bpy.data.objects['ToonCrown_UGC']; me=o.data
vs=[v.co.copy() for v in me.vertices]; cen=Vector([(min(v[i] for v in vs)+max(v[i] for v in vs))/2 for i in range(3)])
for v in me.vertices: v.co-=cen
bpy.context.view_layer.objects.active=o; o.select_set(True)
bpy.ops.export_scene.fbx(filepath=D+'/ToonCrown_UGC.fbx',use_selection=True,axis_forward='Z',axis_up='Y',apply_unit_scale=True,global_scale=0.01,path_mode='STRIP',mesh_smooth_type='OFF')
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.import_scene.fbx(filepath=D+'/ToonCrown_UGC.fbx')
r=[x for x in bpy.data.objects if x.type=='MESH'][0]; print('studs',[round(v*100,3) for v in r.dimensions],'tris',len(r.data.polygons))
