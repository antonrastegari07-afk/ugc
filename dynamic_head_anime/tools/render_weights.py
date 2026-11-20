"""Weight-paint view of the face joints (blue 0 -> red 1), like Blender's weight paint: previews/sheet_weights.png"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_ARG = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].endswith('.py') else '.'
sys.argv = [sys.argv[0], ROOT_ARG, 'blinkseq']
src = open(os.path.join(HERE, 'render_previews.py')).read()
src = src[:src.index("if 'blinkseq' in args:")]
exec(compile(src, 'rp', 'exec'))
OUTD = OUT
me = head.data
GROUPS = [('Sourcils', ['LeftInnerBrow', 'LeftOuterBrow', 'RightInnerBrow', 'RightOuterBrow']),
          ('Paupieres', ['LeftUpperEyelid', 'RightUpperEyelid']),
          ('Sous_les_yeux', ['LeftUnderEye', 'RightUnderEye']),
          ('Joues', ['LeftCheek', 'RightCheek']),
          ('Machoire', ['Jaw']),
          ('Levres_coins', ['LeftLipCorner', 'RightLipCorner', 'LeftUpperLip', 'RightUpperLip', 'LeftLowerLip', 'RightLowerLip'])]
idx = {g.name: g.index for g in head.vertex_groups}
def heat(w):
    # blue (0) -> green -> yellow -> red (1), like Blender's weight paint
    stops = [(0.0, (0.0, 0.0, 0.6)), (0.25, (0.0, 0.6, 1.0)), (0.5, (0.0, 0.9, 0.2)), (0.75, (1.0, 0.9, 0.0)), (1.0, (1.0, 0.05, 0.0))]
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if w <= b:
            t = (w - a) / (b - a)
            return tuple(ca[i] + (cb[i] - ca[i]) * t for i in range(3))
    return stops[-1][1]
attr = me.color_attributes.new('wviz', 'FLOAT_COLOR', 'POINT')
mat2 = bpy.data.materials.new('wviz'); mat2.use_nodes = True
nt2 = mat2.node_tree; nt2.nodes.clear()
ca = nt2.nodes.new('ShaderNodeVertexColor'); ca.layer_name = 'wviz'
em2 = nt2.nodes.new('ShaderNodeEmission'); nt2.links.new(ca.outputs['Color'], em2.inputs['Color'])
o2 = nt2.nodes.new('ShaderNodeOutputMaterial'); nt2.links.new(em2.outputs[0], o2.inputs[0])
head.data.materials.clear(); head.data.materials.append(mat2)
scn.render.resolution_x, scn.render.resolution_y = 520, 520
apply([])
for title, gs in GROUPS:
    gi = {idx[g] for g in gs if g in idx}
    for v in me.vertices:
        w = sum(g.weight for g in v.groups if g.group in gi)
        attr.data[v.index].color = (*heat(min(1.0, w)), 1.0)
    place(-12, 4, 0.036)
    render(os.path.join(OUTD, f'w_{title}.png'))

from PIL import Image, ImageDraw, ImageFont
try:
    font = ImageFont.truetype('DejaVuSans.ttf', 18)
except Exception:
    try: font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 18)
    except Exception: font = ImageFont.load_default()
labels = {'Sourcils': 'Sourcils', 'Paupieres': 'Paupières + eyeliner', 'Sous_les_yeux': 'Sous les yeux',
          'Joues': 'Joues', 'Machoire': 'Mâchoire', 'Levres_coins': 'Lèvres / coins'}
w, h = 520, 520
sheet = Image.new('RGB', (w * 3, (h + 30) * 2), (30, 31, 36)); d = ImageDraw.Draw(sheet)
for i, (title, _) in enumerate(GROUPS):
    x, y = (i % 3) * w, (i // 3) * (h + 30)
    fn = os.path.join(OUTD, f'w_{title}.png')
    sheet.paste(Image.open(fn).convert('RGB'), (x, y + 30)); os.remove(fn)
    d.text((x + 8, y + 5), labels[title], fill=(230, 230, 230), font=font)
sheet.save(os.path.join(OUTD, 'sheet_weights.png'))
print('sheet weights')
