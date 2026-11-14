# Horns Iridescent v6

## Contenu du modèle
| Partie | Change de couleur ? | Détail |
|---|---|---|
| Cornes | oui | Volume de ton modèle d'origine, **lissé à la base** (les piques qui dépassaient sont retirées). Coupées en **tranches verticales régulières** (plans X et Y). |
| Halo | oui | Anneau fin à la place du trou noir (même centre, même inclinaison), mêmes tranches verticales |
| Contour du halo | non | Noir, mat |
| Ailerons (4 par corne) | non | **Bracelet large qui serre la corne + double lame verticale** (2 pointes, une vers le haut et une vers le bas, encoche au milieu), accrochée sur toute la hauteur du bracelet. Corps sombre + contour néon, mats |

Chaînes : supprimées. **3 966 triangles**.

## Textures (à mettre dans le SurfaceAppearance)
- `Horns_<nom>_Color.png` → ColorMap
- `Horns_<nom>_Roughness.png` → RoughnessMap (blanc = 100 % mat : **contours et ailerons ne reflètent rien**)
- `Horns_<nom>_Metalness.png` → MetalnessMap (tout noir = aucun métal)

Laisse **DoubleSided désactivé** (par défaut), sinon l'effet et les contours disparaissent.

## Variantes
`holo/`, `galaxy/`, `toxic/`, `inferno/` : chaque direction a un dégradé de 2 couleurs, soit 8 couleurs en tournant.

`_scripts/` : `field.py` (volume d'origine), `build8.py` (géométrie), `export8.py` (FBX, OBJ, textures).
