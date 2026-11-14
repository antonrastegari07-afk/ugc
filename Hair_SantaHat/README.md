# Hair + Santa hat : refait depuis le modèle d'origine

## Ce qui a été fait
1. **Emboîtement circulaire** : vu de dessous, l'intérieur des cheveux était ovale (plus long d'avant en arrière, les côtés de la frange partaient tout droit). Il est maintenant **circulaire** : rayon constant à ±5 % tout autour.
2. **Cheveux élargis** : les côtés sont écartés d'environ 20 % (épaisseur des mèches conservée), pour remplir le chapeau au lieu d'être plus étroits que lui. Le dôme du bonnet et le pompon ne sont pas modifiés.
3. **Ajusté sur la tête du rig R6** : la tête du rig est un cylindre de rayon 0,6. Le cercle intérieur fait 0,63 (3 cm de marge) et il est centré sur l'axe de la tête. Le bonnet est posé sur le haut de la tête, les deux yeux restent visibles.
4. **Même repère que le rig** : mêmes axes, unités et transformation de nœud que `r6_rigged.fbx`. Importés ensemble, ils s'alignent.
5. **Pénétrations** : les quelques pointes de mèches qui rentraient dans la tête ont été ressorties de 2 cm.
6. **Triangles** : 8 167 → **3 950** (limite UGC : 4 000), UV reprojetées.

## Fichiers
- `Hair_SantaHat.fbx` : modèle final, la texture attendue s'appelle `Hair_Color.png`.
- `Hair_SantaHat.obj` : secours, en studs, Y vers le haut.
- `previews/` : avant/après vu de dessous, ajusté sur la tête avec le visage, et chargé avec ton rig (damier = contrôle des UV).

## Texture
Ton FBX Tripo ne contient pas l'image de texture (seulement un lien vers un fichier externe).
Envoie l'image PNG `tripo_image_24749a36…` : `_scripts/texfix.py` baisse la saturation et adoucit les zones trop lumineuses.
