# Horns Iridescent v5

## Contenu du modèle
| Partie | Change de couleur ? | Détail |
|---|---|---|
| Cornes | oui | Forme mi-chemin entre la référence (segment bas épais coupé net, haut fin jusqu'à une pointe) et ton modèle d'origine (même trajectoire, un peu de son volume cristal). Coupées en **tranches verticales régulières** (plans X et Y). |
| Halo | oui | Anneau fin à la place du trou noir (même centre, même inclinaison), mêmes tranches verticales |
| Contour du halo | non | Noir, mat |
| Ailerons (6 par corne) | non | **Bracelet autour de la corne + lame verticale en pointe de flèche** sur le côté extérieur (pointe légèrement vers le haut). Corps sombre + contour néon, mats |

Chaînes : supprimées. **3 854 triangles**.

## Textures (à mettre dans le SurfaceAppearance)
- `Horns_<nom>_Color.png` → ColorMap
- `Horns_<nom>_Roughness.png` → RoughnessMap (blanc = 100 % mat : **contours et ailerons ne reflètent rien**)
- `Horns_<nom>_Metalness.png` → MetalnessMap (tout noir = aucun métal)

Laisse **DoubleSided désactivé** (par défaut), sinon l'effet et les contours disparaissent.

## Variantes
`holo/`, `galaxy/`, `toxic/`, `inferno/` : chaque direction a un dégradé de 2 couleurs, soit 8 couleurs en tournant.

`_scripts/` : `field.py` (volume d'origine), `build7.py` (géométrie), `export7.py` (FBX, OBJ, textures).
