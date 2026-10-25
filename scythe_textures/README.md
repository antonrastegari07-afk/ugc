# Textures Scythe — style or orné lumineux

Textures PBR 1024×1024 générées sur les UVs de `save obj SCYTHE.obj`, pour le `SurfaceAppearance` de `scythe .rbxm`.

| Fichier | Propriété SurfaceAppearance |
|---|---|
| `Scythe_Color.png` | ColorMap |
| `Scythe_Normal.png` | NormalMap (format OpenGL, +Y) |
| `Scythe_Metalness.png` | MetalnessMap |
| `Scythe_Roughness.png` | RoughnessMap |
| `Scythe_Emissive.png` | EmissiveMaskContent |

Dans `scythe .rbxm`, `EmissiveTint` est passé en doré (255, 190, 70). `EmissiveStrength` est inchangé (40).

## Mise en place dans Studio
1. Importer les 5 PNG (Asset Manager / Creator Hub).
2. Sur le `SurfaceAppearance` : **vider `TexturePack`** (il référence les anciennes textures et peut prendre le dessus sur les maps individuelles), puis assigner les 5 maps ci-dessus.
3. Ajuster `EmissiveStrength` si la lueur est trop forte ou trop faible.

`tools/` contient les scripts Python qui ont généré les textures (`bake.py` → `ao.py` → `gen.py`, `render.py` pour l'aperçu).
