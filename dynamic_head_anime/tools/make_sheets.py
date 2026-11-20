"""Assemble the preview renders (previews/*.png) into contact sheets (previews/sheet_*.png)."""
import os, sys, glob
from PIL import Image, ImageDraw

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
P = os.path.join(ROOT, 'previews')


def sheet(name, files, cols, cell=None):
    files = [f for f in files if os.path.exists(f)]
    if not files:
        return
    ims = [Image.open(f).convert('RGB') for f in files]
    w, h = cell or ims[0].size
    rows = (len(ims) + cols - 1) // cols
    out = Image.new('RGB', (cols * w, rows * (h + 22)), (30, 31, 36))
    d = ImageDraw.Draw(out)
    for i, (f, im) in enumerate(zip(files, ims)):
        x, y = (i % cols) * w, (i // cols) * (h + 22)
        out.paste(im.resize((w, h)), (x, y + 22))
        d.text((x + 6, y + 5), os.path.splitext(os.path.basename(f))[0], fill=(220, 220, 220))
    out.save(os.path.join(P, f'sheet_{name}.png'))
    print('sheet', name, len(ims))


sheet('views', [os.path.join(P, f'view_{n}.png') for n in ('front', 'left35', 'right35', 'side70', 'below', 'above')], 3)
sheet('poses', sorted(glob.glob(os.path.join(P, 'pose_*.png'))), 4)
sheet('skins', [os.path.join(P, 'view_front.png')] + sorted(glob.glob(os.path.join(P, 'skin_*.png'))), 4)
sheet('close', sorted(f for f in glob.glob(os.path.join(P, 'close_*.png')) if '_m_' not in f), 3)
sheet('mouth', sorted(glob.glob(os.path.join(P, 'close_pose_m_*.png'))), 3)
sheet('blink', [os.path.join(P, f'blink_{v}_{k:03d}.png') for v in ('front', 'below', 'side') for k in (0, 25, 50, 75, 100)], 5)
