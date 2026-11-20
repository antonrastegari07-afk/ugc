"""2D face design proposals (front view) for the anime dynamic head."""
import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont
SS = 3                      # supersampling
W = H = 900
PX = W / 1.55               # pixels per stud
def P(x, z):                # stud coords (x right on screen, z up) -> canvas px (supersampled)
    return ((W / 2 + x * PX) * SS, (H / 2 - z * PX) * SS)

def head_mask():
    m = Image.new('L', (W * SS, H * SS), 0)
    pts = []
    for i in range(720):
        a = 2 * math.pi * i / 720
        c, s = math.cos(a), math.sin(a)
        n = 3.3
        z = 0.60 * math.copysign(abs(s) ** (2 / n), s)
        A = 0.59 * (1 - 0.07 * max(0, -z / 0.6) ** 2)
        x = A * math.copysign(abs(c) ** (2 / n), c)
        pts.append(P(x, z))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m

def layer():
    return Image.new('RGBA', (W * SS, H * SS), (0, 0, 0, 0))

def curve(f, a, b, n=80):
    return [f(a + (b - a) * i / n) for i in range(n + 1)]

def eye_shape(v, side):
    """returns (opening polygon pts in studs, top curve fn, bottom curve fn, u->x map)"""
    ex, ez, a = v['ex'], v['ez'], v['ea']
    def X(s): return side * (ex + (-a + 2 * a * s))
    top = lambda s: (X(s), ez + v['top'](s))
    bot = lambda s: (X(s), ez + v['bot'](s))
    poly = curve(top, 0, 1) + curve(bot, 1, 0)
    return poly, top, bot, X

def stroke_band(curve_pts_in, thick, offset_dir=1):
    """band polygon above (offset_dir=1) a curve list of (x,z,thickness)"""
    up = [(x, z + offset_dir * t) for (x, z, t) in curve_pts_in]
    base = [(x, z) for (x, z, t) in curve_pts_in]
    return base + up[::-1]

def draw_variant(v, skin=(128, 128, 126)):
    img = Image.new('RGBA', (W * SS, H * SS), (33, 35, 41, 255))
    hm = head_mask()
    # head shading: vertical + radial gradient
    shade = Image.new('RGBA', (W * SS, H * SS))
    sd = ImageDraw.Draw(shade)
    for i in range(0, H * SS, 4):
        t = i / (H * SS)
        k = 1.10 - 0.25 * t
        col = tuple(int(min(255, c * k)) for c in skin) + (255,)
        sd.rectangle([0, i, W * SS, i + 4], fill=col)
    img.paste(shade, (0, 0), hm)
    # right-side rim light + edge darkening
    edge = hm.filter(ImageFilter.GaussianBlur(40 * SS))
    dark = Image.new('RGBA', img.size, (0, 0, 0, 255))
    em = ImageChops.subtract(hm, edge).point(lambda p: min(255, int(p * 0.9)))
    img = Image.composite(dark, img, em.point(lambda p: int(p * 0.5)))
    d = ImageDraw.Draw(img)
    S = lambda pts: [P(*p) for p in pts]
    INK = v.get('ink', (22, 18, 20, 255))

    for side in (1, -1):
        poly, top, bot, X = eye_shape(v, side)
        om = Image.new('L', img.size, 0)
        ImageDraw.Draw(om).polygon(S(poly), fill=255)
        # socket interior: sclera
        sc = layer(); sdr = ImageDraw.Draw(sc)
        sdr.rectangle([0, 0, W * SS, H * SS], fill=v.get('sclera', (236, 233, 228, 255)))
        # iris
        ix, iz = side * (v['ex'] + v.get('iris_dx', 0) * side), v['ez'] + v.get('iris_dz', 0)
        r = v['iris_r']
        for k in range(24):              # radial gradient iris
            t = k / 23
            rr = r * (1 - t)
            c0, c1 = v['iris_out'], v['iris_in']
            col = tuple(int(c0[j] + (c1[j] - c0[j]) * t ** 0.8) for j in range(3)) + (255,)
            (x0, y0), (x1, y1) = P(ix - rr, iz + rr * v.get('iris_sq', 1.0)), P(ix + rr, iz - rr * v.get('iris_sq', 1.0))
            sdr.ellipse([x0, y0, x1, y1], fill=col)
        # iris ring
        (x0, y0), (x1, y1) = P(ix - r, iz + r * v.get('iris_sq', 1.0)), P(ix + r, iz - r * v.get('iris_sq', 1.0))
        sdr.ellipse([x0, y0, x1, y1], outline=v.get('ring', (20, 20, 24, 255)), width=int(0.007 * PX * SS))
        # pupil
        pr = v['pupil_r']
        (x0, y0), (x1, y1) = P(ix - pr * v.get('pupil_w', 1), iz + pr), P(ix + pr * v.get('pupil_w', 1), iz - pr)
        sdr.ellipse([x0, y0, x1, y1], fill=(10, 10, 12, 255))
        # highlights
        for (hx, hz, hr) in v['hl']:
            (x0, y0), (x1, y1) = P(ix + side * 0 + hx * (1 if side > 0 else 1), iz + hz + hr), P(ix + hx + hr * 1.0, iz + hz - hr)
            x0c, y0c = P(ix + hx - hr, iz + hz + hr); x1c, y1c = P(ix + hx + hr, iz + hz - hr)
            sdr.ellipse([x0c, y0c, x1c, y1c], fill=(255, 255, 255, 235))
        # lid shadow on top of the socket (carved look)
        shm = Image.new('L', img.size, 0)
        tops = curve(top, 0, 1)
        ImageDraw.Draw(shm).polygon(S(tops + [(x, z - v['lid_shadow']) for (x, z) in tops[::-1]]), fill=150)
        shm = shm.filter(ImageFilter.GaussianBlur(8 * SS))
        sc = Image.composite(Image.new('RGBA', img.size, (40, 38, 45, 255)), sc, shm)
        # inner rim darkening (depth)
        rim = ImageChops.subtract(om, om.filter(ImageFilter.GaussianBlur(6 * SS)).point(lambda p: 255 if p > 250 else 0))
        sc = Image.composite(Image.new('RGBA', img.size, (25, 25, 30, 255)), sc, rim.point(lambda p: int(p * 0.7)))
        img.paste(sc, (0, 0), om)
        d = ImageDraw.Draw(img)
        # upper lash line
        lt = v['lash_t']
        pts = [(top(s)[0], top(s)[1], lt(s)) for s in [i / 80 for i in range(81)]]
        band = stroke_band(pts, None)
        # outer flick
        fx, fz = top(1.0)
        flick = v['flick']
        band_poly = band
        d.polygon(S(band_poly), fill=INK)
        d.polygon(S([(fx, fz + lt(1.0)), (fx + side * flick[0], fz + flick[1]), (fx, fz - 0.002), (top(0.93)[0], top(0.93)[1])]), fill=INK)
        # lower lash mark (outer part)
        if v.get('lower'):
            a0, a1, th = v['lower']
            pts = [(bot(s)[0], bot(s)[1], th * math.sin(math.pi * (s - a0) / (a1 - a0))) for s in [a0 + (a1 - a0) * i / 40 for i in range(41)]]
            d.polygon(S(stroke_band(pts, None, -1)), fill=INK)
        # crease
        if v.get('crease'):
            a0, a1, off, th = v['crease']
            pts = [(top(s)[0], top(s)[1] + off + 0.01 * math.sin(math.pi * s), th * math.sin(math.pi * (s - a0) / (a1 - a0))) for s in [a0 + (a1 - a0) * i / 40 for i in range(41)]]
            d.polygon(S(stroke_band(pts, None)), fill=INK[:3] + (200,))
        # under-eye tired line
        if v.get('bags'):
            a0, a1, off, alpha = v['bags']
            pts = [P(bot(s)[0], bot(s)[1] - off - 0.006 * math.sin(math.pi * s)) for s in [a0 + (a1 - a0) * i / 30 for i in range(31)]]
            bl = layer(); ImageDraw.Draw(bl).line(pts, fill=(60, 50, 55, alpha), width=int(0.005 * PX * SS))
            img.alpha_composite(bl)
            d = ImageDraw.Draw(img)
        # brow
        bi, bo, bt = v['brow']
        bx0, bz0 = bi; bx1, bz1 = bo
        def bc(s):
            x = side * (bx0 + (bx1 - bx0) * s)
            z = bz0 + (bz1 - bz0) * s + v.get('brow_arch', 0) * math.sin(math.pi * s)
            return x, z
        up = [(bc(s)[0], bc(s)[1] + bt(s) / 2) for s in [i / 60 for i in range(61)]]
        dn = [(bc(s)[0], bc(s)[1] - bt(s) / 2) for s in [i / 60 for i in range(61)]]
        d.polygon(S(up + dn[::-1]), fill=INK)
        # mole
        if v.get('mole') and side == v['mole'][0]:
            mx, mz, mr = v['mole'][1:]
            x0, y0 = P(side * mx - mr, mz + mr); x1, y1 = P(side * mx + mr, mz - mr)
            d.ellipse([x0, y0, x1, y1], fill=INK)
    # nose
    if v.get('nose'):
        d.line([P(*p) for p in v['nose']], fill=INK[:3] + (170,), width=int(0.006 * PX * SS))
    # mouth
    mz, mw, smirk, th = v['mouth']
    pts = []
    for i in range(41):
        x = -mw + 2 * mw * i / 40
        t = x / mw
        z = mz + smirk * max(0, t) ** 2 + v.get('mouth_curve', -0.004) * t * t
        pts.append((x, z, th * (1 - abs(t) ** 4) ** 0.5 + 0.0015))
    up = [(x, z + t / 2) for x, z, t in pts]; dn = [(x, z - t / 2) for x, z, t in pts]
    d.polygon(S(up + dn[::-1]), fill=INK)
    if v.get('mouth_dash'):
        d.line([P(*p) for p in v['mouth_dash']], fill=INK, width=int(0.006 * PX * SS))
    img = img.resize((W, H), Image.LANCZOS)
    return img

def sin(s, p=1): return max(0.0, math.sin(math.pi * s)) ** p

VARIANTS = {
 'A': dict(name='A  "Flemme"', ex=0.275, ez=-0.035, ea=0.168,
     top=lambda s: 0.048 * sin(s, 0.55) * (0.80 + 0.40 * s) - 0.005 * (1 - s),
     bot=lambda s: -0.060 * sin(s, 0.75) * (1.05 - 0.15 * s) - 0.005 * (1 - s),
     lash_t=lambda s: 0.009 + 0.024 * sin(min(1, s * 1.15), 0.6) + 0.008 * s,
     flick=(0.05, -0.035), lower=(0.62, 0.97, 0.007), crease=(0.35, 0.95, 0.04, 0.005),
     bags=(0.25, 0.75, 0.026, 90),
     iris_r=0.074, iris_out=(46, 62, 70), iris_in=(110, 140, 145), ring=(16, 20, 24, 255),
     iris_dz=0.0, pupil_r=0.028, hl=[(0.026, 0.026, 0.014), (-0.024, -0.03, 0.007)], lid_shadow=0.035,
     brow=((0.11, 0.115), (0.44, 0.14), lambda s: 0.032 * (1 - s) ** 0.6 + 0.007), brow_arch=0.014,
     nose=[(0.0, -0.12), (0.012, -0.135)], mouth=(-0.285, 0.085, 0.016, 0.006)),
 'B': dict(name='B  "Froid"', ex=0.27, ez=-0.03, ea=0.162,
     top=lambda s: 0.040 * sin(s, 0.6) * (0.7 + 0.6 * s) + 0.014 * s,
     bot=lambda s: -0.050 * sin(s, 0.9) * (1.1 - 0.4 * s) + 0.012 * s,
     lash_t=lambda s: 0.008 + 0.020 * sin(min(1, s * 1.1), 0.5) + 0.009 * s,
     flick=(0.05, 0.012), lower=(0.70, 0.98, 0.006), crease=None, bags=None,
     iris_r=0.066, iris_out=(70, 78, 90), iris_in=(175, 190, 205), ring=(25, 28, 38, 255),
     iris_dz=0.006, pupil_r=0.025, pupil_w=0.55, hl=[(0.024, 0.024, 0.013)], lid_shadow=0.028,
     brow=((0.14, 0.12), (0.42, 0.15), lambda s: 0.02 * (1 - s) ** 0.5 + 0.005), brow_arch=0.0,
     mole=(-1, 0.36, -0.115, 0.009),
     nose=None, mouth=(-0.29, 0.06, 0.0, 0.005), mouth_curve=0.0,
     mouth_dash=[(0.085, -0.278), (0.105, -0.27)]),
 'C': dict(name='C  "Endormi"', ex=0.275, ez=-0.04, ea=0.165,
     top=lambda s: 0.030 * sin(s, 0.5) * (1.0 - 0.1 * s) - 0.012 * s,
     bot=lambda s: -0.062 * sin(s, 0.7) - 0.012 * s,
     lash_t=lambda s: 0.014 + 0.022 * sin(s, 0.5),
     flick=(0.03, -0.045), lower=None, crease=(0.15, 0.85, 0.04, 0.005),
     bags=(0.15, 0.85, 0.02, 120),
     iris_r=0.072, iris_out=(60, 45, 40), iris_in=(150, 110, 85), ring=(30, 20, 18, 255),
     iris_dz=-0.004, pupil_r=0.026, hl=[(0.024, 0.014, 0.012), (-0.022, -0.036, 0.006)], lid_shadow=0.025,
     brow=((0.13, 0.115), (0.40, 0.105), lambda s: 0.036 * (1 - 0.6 * s)), brow_arch=0.018,
     nose=[(-0.005, -0.13), (0.008, -0.14)], mouth=(-0.28, 0.05, 0.004, 0.006), mouth_curve=0.006),
}

if __name__ == '__main__':
    out = sys.argv[1]
    tiles = []
    for k, v in VARIANTS.items():
        im = draw_variant(v)
        im.save(f'{out}/design_{k}.png')
        tiles.append((v['name'], im))
    sheet = Image.new('RGB', (W * 3, H + 90), (24, 25, 30))
    dr = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 48)
    except Exception:
        font = ImageFont.load_default()
    for i, (n, im) in enumerate(tiles):
        sheet.paste(im.convert('RGB'), (i * W, 90))
        dr.text((i * W + 40, 20), n, fill=(230, 230, 235), font=font)
    sheet.save(f'{out}/design_sheet.png')
    print('ok')
