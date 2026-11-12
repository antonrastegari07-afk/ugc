import bpy,sys
D=sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=D+'/geo_uv.blend'); o=bpy.data.objects['SantaHat']; me=o.data
m=bpy.data.materials.new('SantaHair'); m.use_nodes=True; N=m.node_tree.nodes; L=m.node_tree.links; bs=N['Principled BSDF']
def t(n,cs): i=bpy.data.images.load(f'{D}/SantaHair_{n}.png'); i.colorspace_settings.name=cs; x=N.new('ShaderNodeTexImage'); x.image=i; return x
c=t('Color','sRGB'); r=t('Roughness','Non-Color'); nm=t('Normal','Non-Color'); nn=N.new('ShaderNodeNormalMap')
L.new(c.outputs['Color'],bs.inputs['Base Color']); L.new(r.outputs['Color'],bs.inputs['Roughness']); L.new(nm.outputs['Color'],nn.inputs['Color']); L.new(nn.outputs['Normal'],bs.inputs['Normal'])
geo=N.new('ShaderNodeNewGeometry'); tr=N.new('ShaderNodeBsdfTransparent'); mx=N.new('ShaderNodeMixShader'); out=N['Material Output']
L.new(geo.outputs['Backfacing'],mx.inputs['Fac']); L.new(bs.outputs['BSDF'],mx.inputs[1]); L.new(tr.outputs['BSDF'],mx.inputs[2]); L.new(mx.outputs['Shader'],out.inputs['Surface'])
me.materials.clear(); me.materials.append(m)
bpy.ops.wm.save_as_mainfile(filepath=D+'/tex.blend')
