# Cornes + trou noir (UGC tête)

- `HornsBlackHole_UGC.fbx` : à importer (s'importe à la bonne taille, ~2,0 × 1,0 × 1,3 studs — ne pas redimensionner). 3 982 triangles, 1 mesh, 1 matériau, origine centrée.
- Textures 1024 (SurfaceAppearance) : `Horns_Color` → ColorMap, `Horns_Normal` → NormalMap, `Horns_Metalness`, `Horns_Roughness`, `Horns_Emissive` → EmissiveMaskContent.
- Réglages : AlphaMode = Overlay, EmissiveTint = (220, 210, 255) (lavande), EmissiveStrength ≈ 3–5. Attachment : HatAttachment.

Cornes : modèle Tripo d’origine (forme et écartement inchangés, pas d’allègement ; seuls les petits débris flottants et le pendentif droit cassé ont été corrigés), textures refaites : corne noire, parties blanches passées en mauve pâle du trou noir.
Trou noir (style Gargantua) : boule noire mate (aucune lumière), coque sphérique aux normales inversées autour (on ne voit que sa paroi du fond, juste derrière la boule : c'est le halo qui englobe le trou sous tous les angles), disque d'accrétion fin à stries concentriques, un côté plus lumineux, touches blanc / mauve clair.

## Version sans emissive (`no_emissive/`)
Même mesh (`HornsBlackHole_UGC.fbx`). Textures `HornsNoEmissive_Color/Normal/Metalness/Roughness` pensées pour être belles sous l'éclairage normal : disque et halo blanc-mauve satinés à stries contrastées, pointes lavande, pendentifs cristal brillant, boule et cornes noir absolu. Pas d'EmissiveMask (laisser vide, EmissiveStrength = 0).
