# GhostVac — sac à dos aspirateur à fantômes (UGC accessoire de dos)

- `GhostVac_UGC.obj` / `.fbx` : mesh final, 1 seul mesh, 1 seul matériau, **3 838 triangles**, environ 2,0 × 2,4 × 2,3 studs.
- `GhostVac_UGC.blend` : scène Blender (textures intégrées, mannequin Blocky de preview dans `Preview_Mannequin`, pièces séparées dans les collections Tank, Tank_Inner_Inverted, Smoke, Ghost, Ghost_Outline_Inverted, Hose, Gun, Straps ; objet final `GhostVac_UGC`).
- Textures 1024×1024 :

| Fichier | Propriété SurfaceAppearance |
|---|---|
| `GhostVac_Color.png` (RGB, sans alpha) | ColorMap |
| `GhostVac_Normal.png` (OpenGL +Y) | NormalMap |
| `GhostVac_Metalness.png` | MetalnessMap |
| `GhostVac_Roughness.png` | RoughnessMap |
| `GhostVac_Emissive.png` | EmissiveMaskContent |

Réglages : MeshPart `Material = Plastic`, `Transparency = 0` ; SurfaceAppearance `AlphaMode = Overlay`, `EmissiveTint = (127, 232, 255)`, `EmissiveStrength` ≈ 2 à 3 (max 40). Attachment : `BodyBackAttachment` (placer avec l'Accessory Fitting Tool).

Aucune transparence : le verre est une coque intérieure inversée peinte (dégradé bleu), visible tout autour entre les deux blocs.
Bretelles style sac à dos Roblox : du haut du réservoir, sur l’épaule, le long du torse devant, puis retour dans le torse sous le bras vers le bas du réservoir (comme la référence).

`tools/` : `build.py` → `bake.py` → `finish.py --render` → `post.py` (module Python `bpy`).
