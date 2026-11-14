# Hair + Santa hat : refait depuis le modèle d'origine

## Ce qui a été fait
1. **Emboîtement circulaire, rien d'autre** : seule la paroi intérieure des cheveux (la partie qui touche la tête) est recalée sur un cercle. C'est le cercle le plus proche de ton emboîtement, agrandi de 4 %. Plus un point est loin de cette paroi, moins il bouge : au-delà de 7 cm, rien ne bouge. Les mèches extérieures, la frange, le bonnet et le pompon sont comme dans ton modèle d'origine. 15 % des vertices ont bougé, de 2,5 cm en moyenne.
2. **Ajusté sur la tête du rig R6** : la tête du rig est un cylindre de rayon 0,6. L'emboîtement fait 0,62 (2 cm de marge) et il est centré sur la tête, avec le bonnet posé dessus. Les deux yeux restent visibles.
3. **Même repère que le rig** : mêmes axes, unités et transformation de nœud que `r6_rigged.fbx`. Importés ensemble, ils s'alignent.
4. **Pénétrations** : les pointes de mèches qui rentraient dans la tête ont été ressorties de 2 cm.
5. **Triangles** : 8 167 → **3 949** (limite UGC : 4 000), UV reprojetées.
6. **Taille** : environ 2,4 × 2,3 × 2,1 studs.
7. **Origine au centre du volume** : le pivot du mesh est au centre de sa boîte englobante. Le nœud FBX garde le décalage (0,209 ; 2,179 ; −0,041 studs depuis l'origine du rig), donc importé avec le rig, il reste bien placé sur la tête. Le `.obj` est centré et ce décalage est noté dans son en-tête.

## Fichiers
- `Hair_SantaHat.fbx` : modèle final, la texture attendue s'appelle `Hair_Color.png`.
- `Hair_SantaHat.obj` : secours, en studs, Y vers le haut.
- `previews/` : avant/après vu de dessous, ton original comparé au nouveau sous 4 angles, ajusté sur la tête avec le visage, et chargé avec ton rig (damier = contrôle des UV).

## Texture
- `Hair_Color.png` (2048×2048) : texture corrigée, à mettre en ColorMap. Elle vient du GLB Tripo (mêmes UV que le modèle, vérifiées à l'identique).
  - Rouge du bonnet plus profond et moins saturé (plus aucun pixel au-dessus de 80 % de saturation, contre 17,5 % avant).
  - Blancs adoucis (luminosité moyenne 0,93 → 0,80) et légèrement chauds, avec le détail des mèches et de la fourrure récupéré.
- `Hair_Color_original_tripo.jpg` : la texture d'origine, pour comparer.
- `previews/texture_before_after.png` : avant/après sur le rig.
