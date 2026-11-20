"""18 still views all around the head (yaw x pitch) -> previews/sheet_angles.png"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT_ARG = sys.argv[1] if len(sys.argv) > 1 else '.'
sys.argv = [sys.argv[0], ROOT_ARG, 'blinkseq']
src = open(os.path.join(HERE, 'render_previews.py')).read()
src = src[:src.index("if 'blinkseq' in args:")]
exec(compile(src, 'render_previews', 'exec'))
from PIL import Image, ImageDraw, ImageFont
scn.render.resolution_x, scn.render.resolution_y = 420, 420
scn.cycles.samples = 24
apply([])
cells = []
for pitch, pn in ((0, 'hauteur des yeux'), (-30, 'dessous'), (30, 'dessus')):
    for yaw in (-90, -60, -30, 0, 30, 60) if pitch == 0 else (-60, -30, 0, 30, 60, 90):
        pt, pl = pitch, pn
        if pitch < 0 and abs(yaw) >= 90:      # full side from -30° puts the camera inside the shoulder
            pt, pl = -12, 'un peu dessous'
        place(yaw, pt, 0.036); cam.data.lens = 70
        fn = os.path.join(OUT, f'_angle_{pt}_{yaw}.png'); render(os.path.basename(fn))
        cells.append((fn, f'{pl}, {"face" if yaw == 0 else ("%d° %s" % (abs(yaw), "droite" if yaw < 0 else "gauche"))}'))
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 17)
except Exception:
    font = ImageFont.load_default()
W, H = 420, 420
sheet = Image.new('RGB', (W * 6, (H + 28) * 3), (30, 31, 36)); d = ImageDraw.Draw(sheet)
for i, (fn, lab) in enumerate(cells):
    x, y = (i % 6) * W, (i // 6) * (H + 28)
    sheet.paste(Image.open(fn).convert('RGB'), (x, y + 28)); d.text((x + 8, y + 5), lab, fill=(230, 230, 230), font=font)
    os.remove(fn)
sheet.save(os.path.join(OUT, 'sheet_angles.png'))
# phone-friendly copy (portrait, 3 columns)
ph = Image.new('RGB', (W * 3, (H + 28) * 6), (30, 31, 36)); d = ImageDraw.Draw(ph)
for i in range(18):
    src_x, src_y = (i % 6) * W, (i // 6) * (H + 28)
    tile = sheet.crop((src_x, src_y, src_x + W, src_y + H + 28))
    ph.paste(tile, ((i % 3) * W, (i // 3) * (H + 28)))
ph.save(os.path.join(OUT, 'sheet_angles_mobile.png'))
print('sheet angles')
