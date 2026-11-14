# Horns Iridescent v7

## Contenu du modèle
| Partie | Change de couleur ? | Détail |
|---|---|---|
| Cornes | oui | Volume de ton modèle d'origine, **lissé à la base** (les piques qui dépassaient sont retirées). Coupées en **tranches verticales régulières** (plans X et Y). |
| Halo | oui | Anneau fin à la place du trou noir (même centre), **parfaitement horizontal**, mêmes tranches verticales |
| Contour du halo | non | Noir, mat |
| Ailerons (4 par corne) | non | **Pointes de flèche plates traversées par la corne** : grande pointe vers l'extérieur et 2 barbes rabattues (avant/arrière). Légèrement inclinées vers le bas et vers l'avant pour bien se voir de face. Corps sombre + contour néon, mats |

Chaînes : supprimées. **3 912 triangles**.

## Textures (à mettre dans le SurfaceAppearance)
- `Horns_<nom>_Color.png` → ColorMap
- `Horns_<nom>_Roughness.png` → RoughnessMap (blanc = 100 % mat : **contours et ailerons ne reflètent rien**)
- `Horns_<nom>_Metalness.png` → MetalnessMap (tout noir = aucun métal)

Laisse **DoubleSided désactivé** (par défaut), sinon l'effet et les contours disparaissent.

## Variantes
`holo/`, `galaxy/`, `toxic/`, `inferno/` : chaque direction a un dégradé de 2 couleurs, soit 8 couleurs en tournant.

`_scripts/` : `field.py` (volume d'origine), `build9.py` (géométrie), `export9.py` (FBX, OBJ, textures).
