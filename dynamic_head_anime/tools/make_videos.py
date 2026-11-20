"""Assemble the frames of render_anim.py into videos (previews/videos/*.mp4 and *.gif) with ffmpeg."""
import os, sys, subprocess

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
ONLY = set(sys.argv[2].split(',')) if len(sys.argv) > 2 else {'eyes', 'expressions', 'orbit'}
A = os.path.join(ROOT, 'previews', 'anim')
V = os.path.join(ROOT, 'previews', 'videos'); os.makedirs(V, exist_ok=True)
FPS = 20


def run(cmd):
    print(' '.join(cmd[:6]), '...'); subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def inputs(dirs):
    out = []
    for d in dirs:
        out += ['-framerate', str(FPS), '-i', os.path.join(A, d, '%04d.png')]
    return out


def mp4(name, dirs, layout):
    """layout: 'hstack' | 'grid2'"""
    n = len(dirs)
    if n == 1:
        flt = '[0:v]format=yuv420p[v]'
    elif layout == 'grid2':
        flt = '[0:v][1:v]hstack=2[t];[2:v][3:v]hstack=2[b];[t][b]vstack=2,format=yuv420p[v]'
    else:
        flt = ''.join(f'[{i}:v]' for i in range(n)) + f'hstack={n},format=yuv420p[v]'
    out = os.path.join(V, name + '.mp4')
    run(['ffmpeg', '-y'] + inputs(dirs) + ['-filter_complex', flt, '-map', '[v]', '-c:v', 'libx264', '-crf', '20',
                                           '-preset', 'slow', '-movflags', '+faststart', out])
    return out


def gif(src_mp4, name, width):
    out = os.path.join(V, name + '.gif')
    pal = os.path.join(V, '_pal.png')
    run(['ffmpeg', '-y', '-i', src_mp4, '-vf', f'fps=15,scale={width}:-1:flags=lanczos,palettegen=stats_mode=diff', pal])
    run(['ffmpeg', '-y', '-i', src_mp4, '-i', pal, '-lavfi',
         f'fps=15,scale={width}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4', out])
    os.remove(pal)


have = lambda d: os.path.isdir(os.path.join(A, d))
if 'eyes' in ONLY and all(have(f'eyes_{a}') for a in ('face', 'gauche35', 'droite35', 'dessous')):
    m = mp4('yeux_4_angles', ['eyes_face', 'eyes_gauche35', 'eyes_droite35', 'eyes_dessous'], 'grid2')
    gif(m, 'yeux_4_angles', 720)
    gif(mp4('yeux_face', ['eyes_face'], ''), 'yeux_face', 480)
if 'expressions' in ONLY and all(have(f'expressions_{a}') for a in ('face', 'gauche35', 'droite35')):
    m = mp4('expressions_3_angles', ['expressions_face', 'expressions_gauche35', 'expressions_droite35'], 'hstack')
    gif(m, 'expressions_3_angles', 900)
if 'orbit' in ONLY and have('orbit_orbite'):
    gif(mp4('orbite_yeux_qui_suivent', ['orbit_orbite'], ''), 'orbite_yeux_qui_suivent', 480)
for f in sorted(os.listdir(V)):
    print(f, round(os.path.getsize(os.path.join(V, f)) / 1e6, 2), 'MB')
