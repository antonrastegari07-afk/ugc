# Tête dynamique anime — VERSION ACTUELLE : v1.0

**Date : 2026-11-20 · commit `afa3d29` · branche `claude/wizardly-davinci-uu4kjc`**

> Ce dossier contient **uniquement** les fichiers de la version actuelle. Utilise ceux-là et rien d'autre ;
> à chaque nouvelle version ce dossier est entièrement remplacé (le numéro ci-dessus change).

## À importer dans Roblox Studio
| Fichier | Rôle |
|---|---|
| `AnimeDynamicHead_Blocky.fbx` | la tête dynamique (avec le corps Blocky R15, cages, attachments) |
| `HeadTexture.png` | ColorMap du SurfaceAppearance (AlphaMode = Overlay → peau recoloriable) |
| `HeadTexture_Emissive.png` | EmissiveMaskContent (EmissiveStrength ≈ 1) |
| `HeadTexture_Roughness.png` / `_Metalness.png` / `_Normal.png` | RoughnessMap / MetalnessMap / NormalMap |

Contenu : 3788 triangles (max 4000), 34 frames FACS.

## Vidéos (`videos/`)
| Fichier | Contenu |
|---|---|
| `expressions_3_angles.mp4` | expressions, 3 angles |
| `expressions_6_angles.mp4` | expressions du visage, 6 angles (paysage) |
| `expressions_6_angles_mobile.mp4` | expressions du visage, 6 angles — **format téléphone (portrait)** |
| `orbite_yeux_qui_suivent.mp4` | caméra qui tourne autour : les yeux suivent |
| `yeux_4_angles.mp4` | animations des yeux, 4 angles |
| `yeux_6_angles.mp4` | animations des yeux, 6 angles (paysage) |
| `yeux_6_angles_mobile.mp4` | animations des yeux, 6 angles — **format téléphone (portrait)** |
| `yeux_face.mp4` | animations des yeux, de face |

## Images (`images/`)
| Fichier | Contenu |
|---|---|
| `sheet_angles.png` | 18 vues tout autour (hauteur des yeux, dessous, dessus) |
| `sheet_angles_mobile.png` | les mêmes 18 vues, format téléphone |
| `sheet_views.png` | vues générales |
| `sheet_close.png` | gros plans des yeux (poses, côtés) |
| `sheet_blink.png` | clignement 0-25-50-75-100 % (face, dessous, côté) |
| `sheet_poses.png` | expressions |
| `sheet_mouth.png` | bouche |
| `sheet_brows.png` | sourcils |
| `sheet_skins.png` | couleurs de peau |
| `sheet_weights.png` | carte des poids (weight painting) |

## Voir les vidéos sur téléphone
1. Dans l'appli GitHub (ou github.com sur le navigateur du téléphone), ouvre ce dossier puis `videos/`.
2. Touche un fichier `..._mobile.mp4` (format portrait), puis **View raw** / **Télécharger** : la vidéo se lit
   dans le lecteur du téléphone et peut être enregistrée dans la galerie.
3. Les fichiers sans `_mobile` sont en paysage : tourne le téléphone.

Le détail technique (construction, poses, vérifications) est dans `../README.md`.
