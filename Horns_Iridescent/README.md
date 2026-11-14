# Horns Iridescent v10

## Contenu du modèle
| Partie | Change de couleur ? | Détail |
|---|---|---|
| Cornes | oui | Volume de ton modèle d'origine, **lissé sur toute la longueur** (piques irrégulières retirées, pointe conservée), coupé en **tranches verticales régulières** (plans X et Y) |
| Contour des cornes | non | **Noir, mat** (inverted hull) |
| Halo | oui | Anneau fin à la place du trou noir, **parfaitement horizontal**, mêmes tranches verticales |
| Contour du halo | non | Noir, mat |

Piques, chaînes et trou noir : supprimés. **3 986 triangles**.

## Taille
Mise à l'échelle **sans déformation** : environ **1,2 × 0,68 × 0,46** (largeur × hauteur × profondeur).
Si Studio affiche une taille très différente (100× trop grand ou trop petit), règle l'unité d'échelle dans les réglages de fichier du 3D Importer.

## Textures (SurfaceAppearance)
- `Horns_<nom>_Color.png` → ColorMap
- `Horns_<nom>_Roughness.png` → RoughnessMap (contours 100 % mats)
- `Horns_<nom>_Metalness.png` → MetalnessMap (tout noir)
- `Horns_<nom>_Emissive.png` → masque d'émission en noir et blanc (blanc = les tranches qui changent de couleur brillent, noir = les contours ne brillent pas). À mettre dans le masque d'émission du SurfaceAppearance, avec la teinte et l'intensité d'émission réglées dans Studio.
- `Horns_<nom>_EmissiveColor.png` → même chose en couleur, pour les outils qui utilisent une émission colorée.

À vérifier : l'émission dans le SurfaceAppearance est une fonction récente de Roblox ; contrôle dans Studio qu'elle est disponible et acceptée pour un accessoire UGC.

Laisse **DoubleSided désactivé** (par défaut), sinon l'effet et les contours disparaissent.

## Variantes
`holo/`, `galaxy/`, `toxic/`, `inferno/` : chaque direction a un **dégradé de 3 couleurs** (haut, milieu, bas), soit 12 teintes en tournant.

`_scripts/` : `field.py`, `build10.py` (géométrie), `export10.py` (FBX, OBJ, textures).
