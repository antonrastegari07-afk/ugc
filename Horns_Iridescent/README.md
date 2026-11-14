# Horns Iridescent v2 — technique "cartes lenticulaires" (comme la référence)

## Principe
Les cornes cristal sont remplacées par un **treillis de cartes plates, d'un seul côté**, qui remplit le volume de tes cornes :
- 3 familles de plans **verticaux et parallèles**, à 60° les unes des autres.
- Chaque plan est rempli de **triangles collés les uns aux autres** (motif pyramide, avec une pointe brillante).
- Chaque carte = 2 faces dos à dos. Chaque face a **sa propre couleur** selon sa direction, soit 6 couleurs autour de la corne.
- Roblox ne dessine pas l'arrière d'une face. Selon l'angle, tu vois donc surtout UNE famille de couleur, et elle change progressivement quand on tourne.
- Les cartes sont verticales : **vu de dessus, on voit presque à travers**, comme dans la vidéo.

Parties fixes : le trou noir (disque, sphère, noyau) et les chaînes, avec la texture d'origine.
Correction : une chaîne était **dupliquée à 0,0008 près** dans le modèle d'origine, ce qui causait du z-fighting (scintillement). Le doublon est supprimé.

**3 966 triangles** au total, sous la limite UGC.

## Variantes (6 couleurs dans l'ordre en tournant)
| Dossier | Couleurs |
|---|---|
| `holo/`    | violet → rouge → jaune → vert → cyan → bleu (le plus proche de la référence) |
| `galaxy/`  | violet → rose → bleu → cyan |
| `toxic/`   | vert fluo → turquoise → bleu |
| `inferno/` | rouge → orange → or → rose |

Chaque dossier : `.fbx`, `.obj` (secours), `_Color.png`, `turntable.gif`, `top_view.png`.

## Roblox Studio
1. Importe le `.fbx` avec le 3D Importer.
2. SurfaceAppearance → **ColorMap = `Horns_<nom>_Color.png`**.
3. Pas de MetalnessMap sur les cornes : le métal assombrit les couleurs. Tu peux garder tes anciennes cartes pour le trou noir.
4. Vérifie que **DoubleSided est désactivé** (par défaut), sinon l'effet disparaît.

`_scripts/` : scripts de génération (pour régénérer avec d'autres couleurs ou une autre densité).
