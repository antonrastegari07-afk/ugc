# Horns Iridescent v3 — tranches verticales (technique de la référence)

## Comment c'est construit (automatique, pas à la main)
1. Le volume des cornes d'origine est reconstruit proprement : le modèle cristal n'était pas fermé (morceaux qui se chevauchent).
2. Ce volume est **coupé en tranches régulières**, comme un pain de mie, avec **des plans uniquement verticaux** :
   - une série de plans perpendiculaires à X (gauche/droite),
   - une série de plans perpendiculaires à Y (avant/arrière),
   - même espacement entre tous les plans (~0,037), aucune tranche horizontale ni diagonale.
3. Chaque tranche = la **coupe exacte** de la corne à cet endroit, triangulée proprement.
4. Chaque tranche = 2 faces **d'un seul côté**, dos à dos, chacune avec sa couleur :
   +X, −X, +Y, −Y → **4 couleurs** (droite, gauche, arrière, avant).
5. Roblox ne dessine pas l'arrière d'une face. Selon l'angle, tu vois donc une couleur, ou deux couleurs entrelacées à 45°.
   **Vu de dessus**, toutes les tranches sont vues par la tranche : on voit à travers.

Parties fixes : le trou noir (disque, sphère, noyau) avec sa texture d'origine, et les chaînes en lavande.
La chaîne dupliquée du modèle d'origine (z-fighting) est supprimée.
**3 936 triangles** au total, 44 tranches.

## Variantes
| Dossier | Couleurs |
|---|---|
| `holo/`    | vert, jaune, rose, bleu |
| `galaxy/`  | violet, rose, cyan, bleu |
| `toxic/`   | vert fluo, lime, cyan, bleu |
| `inferno/` | rouge, orange, or, rose |

## Roblox Studio
1. Importe le `.fbx` avec le 3D Importer.
2. SurfaceAppearance → ColorMap = `Horns_<nom>_Color.png`.
3. Pas de MetalnessMap. **DoubleSided désactivé** (par défaut), sinon l'effet disparaît.

`_scripts/` : scripts de génération (`field.py` pour le volume, `slice2.py` pour les tranches, `export4.py` pour le FBX et la texture).
