# Masque visage blanc (retexture de mask_halloween)

Même mesh que `mask_halloween.fbx` (aucune modification), nouvelles textures 1024 :
`WhiteFace_Color` → ColorMap, `WhiteFace_Normal` → NormalMap, `WhiteFace_Metalness`, `WhiteFace_Roughness`, `WhiteFace_Emissive` → EmissiveMaskContent.

Le visage blanc de la référence est projeté de face sur la tête (calé sur le visage orange d'origine), l'ancien visage orange est effacé.
Emissive : EmissiveTint = (255, 255, 255), EmissiveStrength ≈ 2–4.

`WhiteFace_Mask.fbx` : même mesh, réexporté pour s'importer directement à **1.227 × 1.252 × 1.227** studs (origine centrée) — ne pas redimensionner dans Studio.
