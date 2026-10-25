# Ghost Jar — UGC accessoire

- `GhostJar_UGC.obj` / `.fbx` : mesh final (1 seul mesh, 1 seul matériau), 3 152 triangles, ~0,86 × 1,19 × 0,86 studs, visage du fantôme vers l'avant Roblox (-Z).
- `GhostJar_UGC.blend` : scène Blender (textures intégrées). Les pièces séparées sont dans des collections masquées (Jar_Outer, Jar_Inner_Inverted, Ghost, Ghost_Outline_Inverted, Smoke_Layers, Cork, Sparkles) ; l'objet final est `GhostJar_UGC`.
- Textures 1024×1024 pour le SurfaceAppearance :

| Fichier | Propriété |
|---|---|
| `GhostJar_Color.png` (RGB, 100 % opaque) | ColorMap |
| `GhostJar_Normal.png` (OpenGL +Y) | NormalMap |
| `GhostJar_Metalness.png` | MetalnessMap |
| `GhostJar_Roughness.png` | RoughnessMap |
| `GhostJar_Emissive.png` | EmissiveMaskContent |

Réglages : `AlphaMode = Overlay` (défaut), `EmissiveTint = (127, 232, 255)`, `EmissiveStrength` entre 2 et 5 (max autorisé : 40). MeshPart : `Material = Plastic`, `Transparency = 0`.

Aucune transparence : le bocal entier est une seule paroi en mesh inversé (on voit toujours la face intérieure du fond, peinte comme du verre) + un fond fermé en dessous + goulot en verre droit qui monte jusqu’au rebord, avec le bouchon cylindrique visible à travers le verre et qui dépasse au-dessus.


`tools/` : scripts de génération (`build.py` puis `bake.py` puis `finish.py`, avec le module Python `bpy`).
