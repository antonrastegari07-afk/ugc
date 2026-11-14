# Horns Iridescent v8

## Contenu du modèle
| Partie | Change de couleur ? | Détail |
|---|---|---|
| Cornes | oui | Volume de ton modèle d'origine, lissé à la base, coupé en **tranches verticales régulières** (plans X et Y) |
| Contour des cornes | non | **Noir, mat** (inverted hull) |
| Halo | oui | Anneau fin à la place du trou noir, **parfaitement horizontal**, mêmes tranches verticales |
| Contour du halo | non | Noir, mat |

Piques, chaînes et trou noir : supprimés. **3 958 triangles**.

## Taille
Mise à l'échelle **sans déformation** : environ **1,2 × 0,70 × 0,44** (largeur × hauteur × profondeur).
Si Studio affiche une taille très différente (100× trop grand ou trop petit), règle l'unité d'échelle dans les réglages de fichier du 3D Importer.

## Textures (SurfaceAppearance)
- `Horns_<nom>_Color.png` → ColorMap
- `Horns_<nom>_Roughness.png` → RoughnessMap (contours 100 % mats)
- `Horns_<nom>_Metalness.png` → MetalnessMap (tout noir)

Laisse **DoubleSided désactivé** (par défaut), sinon l'effet et les contours disparaissent.

## Variantes
`holo/`, `galaxy/`, `toxic/`, `inferno/` : chaque direction a un dégradé de 2 couleurs, soit 8 couleurs en tournant.

`_scripts/` : `field.py`, `build10.py` (géométrie), `export10.py` (FBX, OBJ, textures).
