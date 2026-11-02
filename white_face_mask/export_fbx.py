import bpy, sys
from mathutils import Vector
D=sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=D+'/in/mask.fbx')
o=[x for x in bpy.data.objects if x.type=='MESH'][0]
for x in list(bpy.data.objects):
    if x is not o: bpy.data.objects.remove(x)
bpy.context.view_layer.objects.active=o; o.select_set(True)
bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
me=o.data
vs=[v.co.copy() for v in me.vertices]
cen=Vector([(min(v[i] for v in vs)+max(v[i] for v in vs))/2 for i in range(3)])
dims=[max(v[i] for v in vs)-min(v[i] for v in vs) for i in range(3)]
TARGET=(1.227,1.227,1.252)     # studs: width, depth, height (Roblox X, Z, Y)
s=TARGET[2]/(dims[2]*100)       # Roblox reads this FBX in cm: 1 stud = 0.01 Blender unit
for v in me.vertices: v.co=(v.co-cen)*s
o.location=(0,0,0)
bpy.ops.export_scene.fbx(filepath=D+'/out/WhiteFace_Mask.fbx',use_selection=True,axis_forward='Z',axis_up='Y',apply_unit_scale=True,global_scale=1.0,path_mode='STRIP',mesh_smooth_type='OFF')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=D+'/out/WhiteFace_Mask.fbx')
r=[x for x in bpy.data.objects if x.type=='MESH'][0]
print('reimport studs (x, depth, up):',[round(v*100,3) for v in r.dimensions],'tris',sum(len(p.vertices)-2 for p in r.data.polygons))
