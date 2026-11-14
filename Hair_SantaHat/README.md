# Hair + Santa hat : ajusté sur la tête du rig R6

## Ce qui a été fait
- **Repère identique au rig** : même axe (Y vers le haut), mêmes unités, même transformation de nœud que le mesh du rig (`r6_rigged.fbx`). Importés ensemble, les cheveux tombent pile sur la tête.
- **Échelle** : ×1,9 environ ; largeur totale environ 2,3 studs (pompon compris), hauteur environ 2,3 studs.
- **Intérieur adapté à la tête** : l'intérieur des cheveux était ovale et la tête R6 est un cube arrondi. Chaque direction autour de la tête a été recalée pour que l'intérieur colle à la tête avec 3 cm de marge (4,5 cm devant le visage pour la frange). L'épaisseur des mèches est conservée.
- **Pénétrations** : aucune visible. Il reste au plus 7 mm sur le côté près de l'oreille, et jusqu'à 2 cm sous le bonnet, invisibles car à l'intérieur du bonnet plein.
- **Épaules** : 4 pointes de mèches qui touchaient le torse ont été relevées.
- **Triangles** : 8 167 → **3 949** (limite UGC : 4 000). UV reprojetées sur la forme d'origine.

## Fichiers
- `Hair_SantaHat.fbx` : modèle final, la texture attendue s'appelle `Hair_Color.png`.
- `Hair_SantaHat.obj` : secours, en studs.
- `previews/` : rendus sur le rig.

## Texture
Le FBX Tripo ne contenait pas la texture (lien vers un fichier externe seulement).
Script prêt : `_scripts/texfix.py` (saturation −38 %, hautes lumières adoucies).
