# Horns Iridescent : 6 couleurs selon l'angle, 13 thèmes

## Le modèle
- **Cornes** : volume de ton modèle d'origine, lissé (piques irrégulières retirées, bosse de la base et pointe conservées).
- **Halo** : anneau fin, parfaitement horizontal, à la place du trou noir.
- **Effet** : 3 séries de tranches **verticales** (pivotées de 60° l'une par rapport à l'autre, rien de penché ni d'horizontal).
  Chaque tranche a 2 faces d'un seul côté, ce qui donne **6 directions = 6 couleurs différentes** en tournant autour (une tous les 60°, dont une pile de face).
  Vu de dessus, on voit à travers.
- Taille : environ **1,2 × 0,68 × 0,46 studs**, sans déformation.

## Deux versions (mêmes textures)
| Fichier | Contour | Triangles |
|---|---|---|
| `Horns_<thème>.fbx` | contour noir partout (cornes + halo) | 3 948 |
| `Horns_<thème>_NoOutline.fbx` | aucun contour ; tranches un peu plus serrées | 3 800 |

Un `.obj` de secours est fourni pour chaque version.

## Textures (dans chaque dossier de thème)
| Fichier | Où le mettre (SurfaceAppearance) |
|---|---|
| `Horns_<thème>_Color.png` | ColorMap |
| `Horns_<thème>_Roughness.png` | RoughnessMap (contours 100 % mats) |
| `Horns_<thème>_Metalness.png` | MetalnessMap (noir partout sauf les veines dorées de Royal) |
| `Horns_<thème>_Emissive.png` | masque d'émission (régler la teinte et l'intensité dans Studio) |
| `Horns_<thème>_EmissiveColor.png` | version colorée de l'émission, si besoin |

Contours : noir pur, mats, non métalliques, aucune émission.
Laisse **DoubleSided désactivé** (par défaut), sinon l'effet et les contours disparaissent.
À vérifier : l'émission dans le SurfaceAppearance est récente sur Roblox, contrôle qu'elle est acceptée pour un accessoire UGC.

## Les 13 thèmes (6 couleurs différentes chacun)
| Dossier | Texture | Les 6 couleurs | Ce qui brille |
|---|---|---|---|
| `holo/` | dégradé + hachures | cyan, bleu, rose, rouge, jaune, vert | tout, équilibré |
| `galaxy/` | dégradé + hachures | cyan, bleu, violet, magenta, corail, or | tout, équilibré |
| `toxic/` | dégradé + hachures | vert, jaune, orange, violet, cyan, menthe | tout, équilibré |
| `inferno/` | dégradé + hachures | jaune, orange, rouge, rose, violet, bleu flamme | tout, équilibré |
| `nebula/` | nuages de gaz + étoiles | magenta, cyan, orange, violet, émeraude, rouge | étoiles + cœurs des nuages |
| `ocean/` | eau en volutes + reflets | azur, turquoise, vert d'eau, blanc nacré, corail, indigo | reflets + eau claire |
| `lava/` | roche sombre + veines lumineuses | jaune, orange, rouge, rose, violet, bleu | les veines seulement |
| `frost/` | givre + cristaux + paillettes | bleu glacier, argent, lavande, menthe, bleu roi, rose | cristaux + paillettes |
| `radioactive/` | liquide toxique + bulles | vert, jaune, cyan, violet, orange, rose | le liquide + bulles |
| `vaporwave/` | coucher de soleil + lignes de scan + grille | rose, bleu, violet, jaune, menthe, orange | dégradé + grille |
| `void/` | fumée noire + fissures néon | violet, rouge, cyan, vert, or, rose | les fissures néon seulement |
| `candy/` | barbe à papa pastel + paillettes | rose, menthe, lavande, bleu bébé, pêche, citron | doux partout + paillettes |
| `royal/` | marbre + veines dorées métalliques | or, ivoire, violet royal, noir, émeraude, rubis | veines dorées |

Aperçus : `turntable.gif` / `turntable_NoOutline.gif` dans chaque dossier, et `OVERVIEW_all_themes.png` (chaque thème vu sous 6 angles).

## Scripts (`_scripts/`)
`field.py` (volume d'origine), `build11.py` (géométrie 6 directions ; `NOOL=1` pour la version sans contour), `all_themes.py` (textures + FBX/OBJ de tous les thèmes).
