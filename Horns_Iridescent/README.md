# Horns Iridescent v14

## Contenu du modèle
| Partie | Change de couleur ? | Détail |
|---|---|---|
| Cornes | oui | Volume de ton modèle d'origine, **lissé sur toute la longueur** (piques irrégulières retirées, bosse de la base et pointe conservées), coupé en **tranches verticales régulières** (plans X et Y) |
| Contour des cornes | non | **Noir pur (#000000), 100 % mat, non métallique, aucune émission** (inverted hull) |
| Halo | oui | Anneau fin à la place du trou noir, **parfaitement horizontal**, mêmes tranches verticales |
| Contour du halo | non | Noir pur, 100 % mat, non métallique, aucune émission |

Piques, chaînes et trou noir : supprimés.

## Deux versions du modèle (mêmes textures)
| Fichier | Contour noir sur les cornes | Triangles |
|---|---|---|
| `Horns_<nom>.fbx` | **contour noir partout** (cornes + halo) | 3 986 |
| `Horns_<nom>_NoOutline.fbx` | **aucun contour** (ni cornes ni halo) ; tranches un peu plus serrées | 3 864 |

## Taille
Mise à l'échelle **sans déformation** : environ **1,2 × 0,68 × 0,46** (largeur × hauteur × profondeur).
Si Studio affiche une taille très différente (100× trop grand ou trop petit), règle l'unité d'échelle dans les réglages de fichier du 3D Importer.

## Textures (SurfaceAppearance)
- `Horns_<nom>_Color.png` → ColorMap
- `Horns_<nom>_Roughness.png` → RoughnessMap (contours 100 % mats)
- `Horns_<nom>_Metalness.png` → MetalnessMap (tout noir)
- `Horns_<nom>_Emissive.png` → masque d'émission en niveaux de gris, **équilibré** : les couleurs déjà lumineuses (cyan, rose, jaune) brillent un peu moins et les plus sombres un peu plus, pour que toutes ressortent pareil. Noir sur les contours. À mettre dans le masque d'émission du SurfaceAppearance, avec la teinte et l'intensité d'émission réglées dans Studio.
- `Horns_<nom>_EmissiveColor.png` → même chose en couleur, pour les outils qui utilisent une émission colorée.

À vérifier : l'émission dans le SurfaceAppearance est une fonction récente de Roblox ; contrôle dans Studio qu'elle est disponible et acceptée pour un accessoire UGC.

Laisse **DoubleSided désactivé** (par défaut), sinon l'effet et les contours disparaissent.

## Variantes
`holo/`, `galaxy/`, `toxic/`, `inferno/` : chaque direction a un **dégradé de 3 couleurs** (haut, milieu, bas), soit 12 teintes en tournant. Toutes les couleurs sont vives : plus de bas de dégradé sombre.

`_scripts/` : `field.py`, `build10.py` (géométrie), `export10.py` (FBX, OBJ, textures).
