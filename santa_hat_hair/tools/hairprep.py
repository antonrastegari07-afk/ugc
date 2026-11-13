import bpy, bmesh, sys, numpy as np, math
from mathutils import Matrix, Vector
a=sys.argv[sys.argv.index('--')+1:]; F=a[0]; D=a[1]; OFF=Vector((float(a[2]),float(a[3]),float(a[4])))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=F)
o=[x for x in bpy.data.objects if x.type=='MESH'][0]; me=o.data
bm=bmesh.new(); bm.from_mesh(me)
R=o.matrix_world.to_3x3().normalized().to_4x4()
bm.transform(Matrix.Translation(OFF)@Matrix.Rotation(math.pi,4,'Z')@R)
bm.to_mesh(me); bm.free(); o.matrix_world=Matrix.Identity(4); o.name='HairBase'
m=bpy.data.materials.new('h'); m.use_nodes=True; m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(0.85,0.86,0.9,1); me.materials.clear(); me.materials.append(m)
bpy.ops.wm.save_as_mainfile(filepath=D+'/hairbase.blend')
