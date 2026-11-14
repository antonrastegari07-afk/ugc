# Cape avec image

## Le modèle (`Cape.fbx`, `.obj` de secours)
- Plaque en trapèze de 5 cm d'épaisseur : 1,9 stud de large en haut, 2,4 en bas, environ 2,9 de long. Elle part du haut du dos et s'écarte un peu des jambes vers le bas.
- **12 triangles**. Placée dans le repère du rig R6, avec l'origine au centre du volume.
- 3 zones de texture :
  - **face extérieure** : ton image, sans déformation (le trapèze est découpé dans l'image, rien n'est étiré) ;
  - **face côté dos** : la même image en miroir, floutée et assombrie, pour que les couleurs correspondent ;
  - **tranche** : couleur moyenne de l'image, assombrie.

## Mettre une nouvelle image
```
python3 _scripts/cape.py tex mon_image.png
```
→ crée `Cape_Color.png`. L'image est recadrée au centre aux proportions de la cape (environ 4:5, portrait) : rien n'est étiré, seuls les bords qui dépassent sont coupés. Pour un rendu idéal, envoie une image en portrait avec le sujet au centre ; les coins du haut sont un peu coupés par la forme en trapèze.

`Cape_Color_example.png` : exemple avec le chat. `preview_on_rig.png` : aperçu sur le rig.
