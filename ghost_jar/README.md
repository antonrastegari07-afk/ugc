# Ghost Jar — UGC accessoire

- `GhostJar_UGC.obj` / `.fbx` : mesh final (1 seul mesh, 1 seul matériau), 3 708 triangles, ~0,86 × 1,19 × 0,86 studs, visage du fantôme vers l'avant Roblox (-Z).
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

Aucune transparence : il n'y a pas de verre devant. On voit l'intérieur par l'ouverture, et la paroi du fond (mesh inversé) est peinte comme du verre.


`tools/` : scripts de génération (`build.py` puis `bake.py` puis `finish.py`, avec le module Python `bpy`).
