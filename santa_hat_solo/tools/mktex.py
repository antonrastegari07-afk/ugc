import bpy,sys
D=sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=D+'/geo_uv.blend'); o=bpy.data.objects['SantaHat']; me=o.data
m=bpy.data.materials.new('SantaHair'); m.use_nodes=True; N=m.node_tree.nodes; L=m.node_tree.links; bs=N['Principled BSDF']
def t(n,cs): i=bpy.data.images.load(f'{D}/SantaHair_{n}.png'); i.colorspace_settings.name=cs; x=N.new('ShaderNodeTexImage'); x.image=i; return x
c=t('Color','sRGB'); r=t('Roughness','Non-Color'); nm=t('Normal','Non-Color'); nn=N.new('ShaderNodeNormalMap')
L.new(c.outputs['Color'],bs.inputs['Base Color']); L.new(r.outputs['Color'],bs.inputs['Roughness']); L.new(nm.outputs['Color'],nn.inputs['Color']); L.new(nn.outputs['Normal'],bs.inputs['Normal'])
geo=N.new('ShaderNodeNewGeometry'); tr=N.new('ShaderNodeBsdfTransparent'); mx=N.new('ShaderNodeMixShader'); out=N['Material Output']
at=N.new('ShaderNodeAttribute'); at.attribute_name='part'; lt=N.new('ShaderNodeMath'); lt.operation='LESS_THAN'; lt.inputs[1].default_value=4.5
mu=N.new('ShaderNodeMath'); mu.operation='MULTIPLY'; L.new(at.outputs['Fac'],lt.inputs[0]); L.new(lt.outputs[0],mu.inputs[0]); L.new(geo.outputs['Backfacing'],mu.inputs[1]); L.new(mu.outputs[0],mx.inputs['Fac']); L.new(bs.outputs['BSDF'],mx.inputs[1]); L.new(tr.outputs['BSDF'],mx.inputs[2]); L.new(mx.outputs['Shader'],out.inputs['Surface'])
me.materials.clear(); me.materials.append(m)
bpy.ops.wm.save_as_mainfile(filepath=D+'/tex.blend')
