"""Collect the files to use into VERSION_ACTUELLE/ (one folder, one version, no mix-up) with a short README."""
import os, sys, shutil, json, subprocess, datetime

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else '.')
VERSION = sys.argv[2] if len(sys.argv) > 2 else 'v1.0'
OUT = os.path.join(ROOT, 'VERSION_ACTUELLE')
if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(os.path.join(OUT, 'videos')); os.makedirs(os.path.join(OUT, 'images'))

files = ['AnimeDynamicHead_Blocky.fbx', 'HeadTexture.png', 'HeadTexture_Emissive.png', 'HeadTexture_Roughness.png',
         'HeadTexture_Metalness.png', 'HeadTexture_Normal.png']
for f in files:
    shutil.copy2(os.path.join(ROOT, f), os.path.join(OUT, f))
V = os.path.join(ROOT, 'previews', 'videos')
vids = sorted(f for f in os.listdir(V) if f.endswith('.mp4')) if os.path.isdir(V) else []
for f in vids:
    shutil.copy2(os.path.join(V, f), os.path.join(OUT, 'videos', f))
P = os.path.join(ROOT, 'previews')
imgs = [f for f in ('sheet_angles.png', 'sheet_angles_mobile.png', 'sheet_views.png', 'sheet_close.png', 'sheet_blink.png',
                    'sheet_poses.png', 'sheet_mouth.png', 'sheet_brows.png', 'sheet_skins.png', 'sheet_weights.png')
        if os.path.exists(os.path.join(P, f))]
for f in imgs:
    shutil.copy2(os.path.join(P, f), os.path.join(OUT, 'images', f))

fm = json.load(open(os.path.join(ROOT, 'build', 'facs_map.json')))
check = json.load(open(os.path.join(ROOT, 'build', 'mesh_check.json'))) if os.path.exists(os.path.join(ROOT, 'build', 'mesh_check.json')) else {}
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
lines = [f'# Tête dynamique anime — VERSION ACTUELLE : {VERSION}', '',
         f'**Date : {today} · commit `{commit}` · branche `claude/wizardly-davinci-uu4kjc`**', '',
         '> Ce dossier contient **uniquement** les fichiers de la version actuelle. Utilise ceux-là et rien d\'autre ;',
         '> à chaque nouvelle version ce dossier est entièrement remplacé (le numéro ci-dessus change).', '',
         '## À importer dans Roblox Studio',
         '| Fichier | Rôle |', '|---|---|',
         '| `AnimeDynamicHead_Blocky.fbx` | la tête dynamique (avec le corps Blocky R15, cages, attachments) |',
         '| `HeadTexture.png` | ColorMap du SurfaceAppearance (AlphaMode = Overlay → peau recoloriable) |',
         '| `HeadTexture_Emissive.png` | EmissiveMaskContent (EmissiveStrength ≈ 1) |',
         '| `HeadTexture_Roughness.png` / `_Metalness.png` / `_Normal.png` | RoughnessMap / MetalnessMap / NormalMap |', '',
         f'Contenu : {fm["triangles"]} triangles (max 4000), {len(fm["frames"])} frames FACS.', '',
         '## Vidéos (`videos/`)', '| Fichier | Contenu |', '|---|---|']
for f in vids:
    lines.append(f'| `{f}` | {desc.get(f, "")} |')
lines += ['', '## Images (`images/`)', '| Fichier | Contenu |', '|---|---|']
idesc = {'sheet_angles.png': '18 vues tout autour (hauteur des yeux, dessous, dessus)',
         'sheet_angles_mobile.png': 'les mêmes 18 vues, format téléphone',
         'sheet_views.png': 'vues générales', 'sheet_close.png': 'gros plans des yeux (poses, côtés)',
         'sheet_blink.png': 'clignement 0-25-50-75-100 % (face, dessous, côté)', 'sheet_poses.png': 'expressions',
         'sheet_mouth.png': 'bouche', 'sheet_brows.png': 'sourcils', 'sheet_skins.png': 'couleurs de peau',
         'sheet_weights.png': 'carte des poids (weight painting)'}
for f in imgs:
    lines.append(f'| `{f}` | {idesc.get(f, "")} |')
lines += ['', '## Voir les vidéos sur téléphone',
          '1. Dans l\'appli GitHub (ou github.com sur le navigateur du téléphone), ouvre ce dossier puis `videos/`.',
          '2. Touche un fichier `..._mobile.mp4` (format portrait), puis **View raw** / **Télécharger** : la vidéo se lit',
          '   dans le lecteur du téléphone et peut être enregistrée dans la galerie.',
          '3. Les fichiers sans `_mobile` sont en paysage : tourne le téléphone.', '',
          'Le détail technique (construction, poses, vérifications) est dans `../README.md`.', '']
open(os.path.join(OUT, 'README.md'), 'w').write('\n'.join(lines))
print('release', VERSION, 'files', len(files), 'videos', len(vids), 'images', len(imgs))
