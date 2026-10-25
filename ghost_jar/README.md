# Ghost Jar — UGC accessoire

- `GhostJar_UGC.obj` / `.fbx` : mesh final (1 seul mesh, 1 seul matériau), 3 748 triangles, ~0,86 × 1,19 × 0,86 studs, visage du fantôme vers l'avant Roblox (-Z).
- `GhostJar_UGC.blend` : scène Blender (textures intégrées). Les pièces séparées sont dans des collections masquées (Jar_Outer, Jar_Inner_Inverted, Ghost, Ghost_Outline_Inverted, Smoke_Layers, Glow_Dome_Inverted, Cork, Sparkles) ; l'objet final est `GhostJar_UGC`.
- Textures 1024×1024 pour le SurfaceAppearance :

| Fichier | Propriété |
|---|---|
| `GhostJar_Color.png` (RGBA) | ColorMap |
| `GhostJar_Normal.png` (OpenGL +Y) | NormalMap |
| `GhostJar_Metalness.png` | MetalnessMap |
| `GhostJar_Roughness.png` | RoughnessMap |
| `GhostJar_Emissive.png` | EmissiveMaskContent |

Réglages SurfaceAppearance : `AlphaMode = Transparency`, `EmissiveTint = (127, 232, 255)`, `EmissiveStrength` entre 2 et 5.

Les triangles sont rangés de l'arrière vers l'avant (verre intérieur, halo, fumée, outline, fantôme, étincelles, bouchon, verre extérieur) pour limiter les erreurs de tri de la transparence.

`tools/` : scripts de génération (`build.py` puis `bake.py` puis `finish.py`, avec le module Python `bpy`).
