# Horns Iridescent v4: cornes + halo en tranches verticales, piques fixes

## Ce qu'il y a dans le modèle
| Partie | Change de couleur ? | Détail |
|---|---|---|
| Cornes | oui | Volume des cornes d'origine coupé en **tranches verticales régulières** (plans X et Y, espacement 0,044) |
| Halo (remplace le trou noir) | oui | Anneau fin (rayon 0,30, épaisseur 0,042), **même centre et même inclinaison** que le trou noir, coupé avec la même grille de tranches |
| Contour du halo | non | Contour noir (technique « inverted hull » : copie un peu plus grande aux faces retournées) |
| Piques cristal (6 par corne) | non | Corps sombre + **contour néon**, plantés sur le côté extérieur des cornes et inclinés vers le haut |

Chaînes : supprimées. **3 860 triangles** au total.

## Couleurs
Chaque tranche = 2 faces d'un seul côté (avant/arrière), chacune avec sa couleur.
Chaque direction (droite, gauche, arrière, avant) a un **dégradé de 2 couleurs** (haut → bas), soit **8 couleurs** en tournant.

| Dossier | Couleurs | Contour des piques |
|---|---|---|
| `holo/`    | arc-en-ciel : cyan/bleu, orange/rouge, jaune/vert, rose/violet | cyan |
| `galaxy/`  | cyan/bleu, rose/violet, lavande/bleu ciel, rose/violet foncé | violet |
| `toxic/`   | turquoise/bleu, jaune/lime, lime/vert, vert/sarcelle | vert |
| `inferno/` | jaune/orange, rose/rouge, or/orange vif, rouge/orange | orange |

## Roblox Studio
1. Importe `Horns_<nom>.fbx` avec le 3D Importer.
2. SurfaceAppearance → ColorMap = `Horns_<nom>_Color.png` (la texture contient tout, plus besoin des anciennes cartes).
3. **DoubleSided désactivé** (par défaut), sinon l'effet et les contours disparaissent.

`_scripts/` : `field.py` (volume des cornes), `build5.py` (géométrie), `export5.py` (FBX, OBJ, texture).
