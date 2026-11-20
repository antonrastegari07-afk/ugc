"""Collect the files to use into VERSION_ACTUELLE/ (one folder, one version, no mix-up) with a short README."""
import os, sys, shutil, json, subprocess, datetime

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else '.')
VERSION = sys.argv[2] if len(sys.argv) > 2 else 'v1.0'
# variants: folder name -> build root (the second one, flat eyes, is built in another folder with EYE_STYLE=flat)
VARIANTS = [('A_yeux_3D', ROOT)] + ([('B_yeux_plats', os.path.abspath(sys.argv[3]))] if len(sys.argv) > 3 else [])
OUT = os.path.join(ROOT, 'VERSION_ACTUELLE')
if os.path.isdir(OUT):
    shutil.rmtree(OUT)
files = ['AnimeDynamicHead_Blocky.fbx', 'HeadTexture.png', 'HeadTexture_Emissive.png', 'HeadTexture_Roughness.png',
         'HeadTexture_Metalness.png', 'HeadTexture_Normal.png']
IMGS = ('sheet_angles.png', 'sheet_angles_mobile.png', 'sheet_views.png', 'sheet_close.png', 'sheet_blink.png',
        'sheet_poses.png', 'sheet_mouth.png', 'sheet_brows.png', 'sheet_skins.png', 'sheet_weights.png')
info = {}
for name, src in VARIANTS:
    D = os.path.join(OUT, name) if len(VARIANTS) > 1 else OUT
    os.makedirs(os.path.join(D, 'videos')); os.makedirs(os.path.join(D, 'images'))
    for f in files:
        shutil.copy2(os.path.join(src, f), os.path.join(D, f))
    V = os.path.join(src, 'previews', 'videos')
    vids = sorted(f for f in os.listdir(V) if f.endswith('.mp4')) if os.path.isdir(V) else []
    for f in vids:
        shutil.copy2(os.path.join(V, f), os.path.join(D, 'videos', f))
    P = os.path.join(src, 'previews')
    imgs = [f for f in IMGS if os.path.exists(os.path.join(P, f))]
    for f in imgs:
        shutil.copy2(os.path.join(P, f), os.path.join(D, 'images', f))
    fm = json.load(open(os.path.join(src, 'build', 'facs_map.json')))
    info[name] = (vids, imgs, fm)
commit = subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip()
today = datetime.date.today().isoformat()
desc = {
    'yeux_6_angles.mp4': 'animations des yeux, 6 angles (paysage)',
    'yeux_6_angles_mobile.mp4': 'animations des yeux, 6 angles — **format téléphone (portrait)**',
    'expressions_6_angles.mp4': 'expressions du visage, 6 angles (paysage)',
    'expressions_6_angles_mobile.mp4': 'expressions du visage, 6 angles — **format téléphone (portrait)**',
    'orbite_yeux_qui_suivent.mp4': 'caméra qui tourne autour : les yeux suivent',
    'yeux_4_angles.mp4': 'animations des yeux, 4 angles',
    'yeux_face.mp4': 'animations des yeux, de face',
    'expressions_3_angles.mp4': 'expressions, 3 angles',
}
VDESC = {
    'A_yeux_3D': 'yeux 3D : l\'iris est une sphère vue de l\'intérieur avec ton iris dessiné, la pupille est une boule '
                 'noire 3D au centre ; eyeliner 3D raccourci',
    'B_yeux_plats': 'yeux plats : ton œil dessiné (iris + pupille) sur un disque plat collé au fond du trou blanc, '
                    'comme avant, pour un effet « les yeux te suivent » plus marqué ; eyeliner 3D raccourci',
}
idesc = {'sheet_angles.png': '18 vues tout autour (hauteur des yeux, dessous, dessus)',
         'sheet_angles_mobile.png': 'les mêmes 18 vues, format téléphone',
         'sheet_views.png': 'vues générales', 'sheet_close.png': 'gros plans des yeux (poses, côtés)',
         'sheet_blink.png': 'clignement 0-25-50-75-100 % (face, dessous, côté)', 'sheet_poses.png': 'expressions',
         'sheet_mouth.png': 'bouche', 'sheet_brows.png': 'sourcils', 'sheet_skins.png': 'couleurs de peau',
         'sheet_weights.png': 'carte des poids (weight painting)'}
multi = len(VARIANTS) > 1
lines = [f'# Tête dynamique anime — VERSION ACTUELLE : {VERSION}', '',
         f'**Date : {today} · commit `{commit}` · branche `claude/wizardly-davinci-uu4kjc`**', '',
         '> Ce dossier contient **uniquement** les fichiers de la version actuelle. Utilise ceux-là et rien d\'autre ;',
         '> à chaque nouvelle version ce dossier est entièrement remplacé (le numéro ci-dessus change).', '']
if multi:
    lines += ['## Deux variantes au choix (même tête, mêmes animations, seuls les yeux changent)', '',
              '| Dossier | Yeux | Triangles |', '|---|---|---|']
    for name, _ in VARIANTS:
        lines.append(f'| [`{name}/`]({name}/) | {VDESC[name]} | {info[name][2]["triangles"]} |')
    lines += ['', 'Chaque dossier est complet : importe le FBX **et** les textures **du même dossier** (les textures '
              'des yeux ne sont pas les mêmes d\'une variante à l\'autre).', '']
lines += ['## À importer dans Roblox Studio (dans chaque dossier)',
          '| Fichier | Rôle |', '|---|---|',
          '| `AnimeDynamicHead_Blocky.fbx` | la tête dynamique (avec le corps Blocky R15, cages, attachments) |',
          '| `HeadTexture.png` | ColorMap du SurfaceAppearance (AlphaMode = Overlay → peau recoloriable) |',
          '| `HeadTexture_Emissive.png` | EmissiveMaskContent (EmissiveStrength ≈ 1) |',
          '| `HeadTexture_Roughness.png` / `_Metalness.png` / `_Normal.png` | RoughnessMap / MetalnessMap / NormalMap |', '',
          f'{len(info[VARIANTS[0][0]][2]["frames"])} frames FACS (max 4000 triangles).', '']
for name, _ in VARIANTS:
    vids, imgs, fm = info[name]
    pre = f'{name}/' if multi else ''
    if multi:
        lines += [f'## {name}', VDESC[name], '']
    lines += [f'### Vidéos (`{pre}videos/`)', '| Fichier | Contenu |', '|---|---|']
    lines += [f'| `{f}` | {desc.get(f, "")} |' for f in vids]
    lines += ['', f'### Images (`{pre}images/`)', '| Fichier | Contenu |', '|---|---|']
    lines += [f'| `{f}` | {idesc.get(f, "")} |' for f in imgs]
    lines.append('')
lines += ['## Voir les vidéos sur téléphone',
          '1. Dans l\'appli GitHub (ou github.com sur le navigateur du téléphone), ouvre ce dossier, la variante, puis `videos/`.',
          '2. Touche un fichier `..._mobile.mp4` (format portrait), puis **View raw** / **Télécharger** : la vidéo se lit',
          '   dans le lecteur du téléphone et peut être enregistrée dans la galerie.',
          '3. Les fichiers sans `_mobile` sont en paysage : tourne le téléphone.', '',
          'Le détail technique (construction, poses, vérifications) est dans `../README.md`.', '']
open(os.path.join(OUT, 'README.md'), 'w').write('\n'.join(lines))
print('release', VERSION, {n: (len(i[0]), len(i[1])) for n, i in info.items()})
