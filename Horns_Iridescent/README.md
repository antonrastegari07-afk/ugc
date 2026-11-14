# Horns Iridescent — effet "change de couleur selon l'angle"

Chaque face des cornes reçoit une couleur selon la direction vers laquelle elle pointe.
Quand on tourne autour, ce ne sont pas les mêmes faces qui sont visibles → la couleur change.
Aucun triangle ajouté : **3 982 triangles** (identique à l'original).

Parties qui changent : les 2 cornes + les 2 bases cristal.
Parties fixes : trou noir (disque, sphère, noyau) + chaînes → gardent la texture d'origine.

## Variantes
| Dossier | Couleurs |
|---|---|
| `galaxy/`  | cyan → bleu → violet → rose (recommandé, garde ton thème violet) |
| `toxic/`   | vert fluo → turquoise → bleu → violet |
| `inferno/` | rouge → orange → or → rose |
| `holo/`    | arc-en-ciel complet |

Chaque dossier : `Horns_<nom>.fbx`, `Horns_<nom>.obj` (secours), `Horns_<nom>_Color.png`, `turntable.gif`.

## Dans Roblox Studio
1. Importe `Horns_<nom>.fbx` avec le 3D Importer (même échelle et orientation que ton FBX d'origine).
2. Dans le SurfaceAppearance : **ColorMap = `Horns_<nom>_Color.png`**.
3. Garde tes anciennes MetalnessMap, RoughnessMap et NormalMap : la zone des nouvelles couleurs
   (coin bas-droite de la texture) est noire dans ces cartes, donc non métallique.
4. Ne PAS mettre de MetalnessMap blanche sur les cornes : le métal assombrit les couleurs.
