# Tête dynamique anime (yeux creusés, recoloriable)

Ton visage (`in/face_ref.webp`) monté en **dynamic head Roblox animée**, posée sur le **corps Blocky officiel de
Roblox** (rig R15, cages, attachments). La tête reprend la forme du *white face mask*, à la taille standard d'une tête
(1,18 × 1,18 × 1,20 stud).

## Fichiers à utiliser

| Fichier | Rôle |
|---|---|
| `AnimeDynamicHead_Blocky.fbx` | Le personnage complet à importer dans Studio (tête dynamique + corps Blocky R15 + cages + attachments) |
| `HeadTexture.png` | Texture couleur de la tête. **La peau est transparente** : c'est elle qui rend la tête recoloriable |
| `HeadTexture_Emissive.png` | Masque émissif : l'intérieur des yeux (blanc, parois du creux, iris) est un « blanc profond », plat, qui ne prend pas l'ombre |
| `HeadTexture_Roughness.png` | Rugosité : 1 (aucun reflet) sur les yeux, les cils et l'encre ; 0,6 sur la peau |
| `HeadTexture_Metalness.png`, `HeadTexture_Normal.png` | Métal 0 et normale plate (à brancher pour un SurfaceAppearance complet) |

## Import dans Studio

1. **Avatar → Import 3D** (ou File → Import 3D), choisis `AnimeDynamicHead_Blocky.fbx`.
   Rig General → **Rig Type : R15**. Laisse l'importeur reconnaître les attachments (`*_Att`) et les cages (`*_OuterCage`).
2. Sur la MeshPart **Head**, ajoute un **SurfaceAppearance** :
   - `ColorMap` = `HeadTexture.png`, **`AlphaMode` = `Overlay`** → la peau prend la couleur de la tête (Body Colors / teint)
   - `RoughnessMap` = `HeadTexture_Roughness.png`, `MetalnessMap` = `HeadTexture_Metalness.png`, `NormalMap` = `HeadTexture_Normal.png`
   - `EmissiveMaskContent` = `HeadTexture_Emissive.png`, `EmissiveTint` = blanc, `EmissiveStrength` ≈ 1,5 à 2
     (c'est ce qui donne le blanc pur, sans ombrage, au fond des yeux)
   - Version simple sans SurfaceAppearance : `TextureID` = `HeadTexture.png` (toujours recoloriable, mais sans le blanc émissif)
3. MeshPart : `Material` = **Plastic**, `Transparency` = 0, `VertexColor` = 1,1,1 (exigences Marketplace).
4. Test : **Avatar → Animation Editor → Face Editor**, ou fais varier les curseurs de `Head → FaceControls`.

## Ce qui est animé (36 frames : Neutral + 31 poses + 4 correctifs)

- **Les 17 poses obligatoires Roblox** : LeftEyeClosed, RightEyeClosed, EyesLookDown, JawDrop, Pucker,
  Left/RightLipCornerPuller, ChinRaiser, ChinRaiserUpperLip, Left/RightCheekRaiser, Left/RightInnerBrowRaiser,
  Left/RightLipCornerDown, Left/RightLowerLipDepressor.
- En plus : EyesLookLeft/Right/Up, LipsTogether, Left/RightLipStretcher, Left/RightUpperLipRaiser,
  Left/RightBrowLowerer, Left/RightOuterBrowRaiser, Left/RightEyeUpperLidRaiser.
- Correctifs (même nommage que la tête Blocky officielle) : `LeftEyeClosed_EyesLookDown`, `RightEyeClosed_EyesLookDown`,
  `LeftEyeClosed_EyesLookUp`, `RightEyeClosed_EyesLookUp` : l'œil fermé reste exactement fermé quand le regard bouge
  (la paupière suit un peu le regard vers le bas / le haut).
- Mapping fait comme dans la doc Roblox : propriétés `RootFaceJoint = DynamicHead` et `Frame0 … Frame35` sur `Head_Geo`,
  `Frame0 = Neutral`, os du visage sous `Head → DynamicHead`, clés uniquement sur les os du visage.

### Les yeux
- **Œil 3D sphérique** : chaque œil est une **sphère complète vue de l'intérieur** (mesh inversé, rayon 0,125 ; sa
  moitié avant, vue de dos, est invisible) sur laquelle est projetée **ta texture d'œil d'origine** : blanc pur + ton
  **iris dessiné** (anneaux, reflet), **la pupille dessinée retirée**. La **pupille** est une **vraie boule 3D noir
  profond** (mesh normal) placée **exactement au centre de la sphère**. Plus proche que l'iris peint au fond, elle se
  décale vers celui qui regarde quand il tourne autour : l'œil le suit. La sphère est placée assez profond pour rester
  derrière la peau (et derrière la paupière fermée) dans toutes les positions.
- **PBR** : tout le noir de l'œil est un noir profond sans reflet (rugosité 1, métal 0, aucune émission) ; tous les
  blancs sont entièrement émissifs (un blanc plat identique sur la sphère et les parois, sans ombre ni ligne).
- **Creux évasé vers le haut et vers le bas** (comme une grotte plus grande que son entrée) : on voit **la boule ronde
  en entier** avec le blanc tout autour, sans plafond plat qui le coupe. Le creux garde la forme exacte de l'ouverture
  sur les 4 premiers mm (paupière et eyeliner), puis s'élargit vers le haut derrière la peau.
- **Regard** (EyesLook*) : la sphère tourne (l'iris dessiné se déplace de 3,5 cm sur les côtés, 2 cm en haut / en bas)
  et la pupille suit exactement.
- **Cils du haut en vrai relief 3D** : ils dépassent de la peau et cachent le haut du trou.
- **Clignement naturel** : une seule paupière de peau et le trait de cils 3D sont pilotés par **le même os**. Au repos
  la paupière est rangée derrière la peau au-dessus de l'œil ; en se fermant elle **glisse** vers le bas le long du
  visage (qui est vertical autour des yeux), collée au trait de cils à chaque instant : un demi-clignement est une vraie
  paupière à moitié fermée. Comme elle glisse sans tourner, ses normales restent exactement celles de la peau :
  **même teinte que la peau à chaque instant** (plus d'effet « plaque » plus claire). Elle affleure la vraie peau au
  bord du trou (pas de marche, pas de liseré blanc), et ses coins descendent assez bas pour ne jamais découvrir un coin
  de l'œil pendant le mouvement. Fermé, le trait de cils garde la forme de ton eyeliner, descendu sur le bas de l'œil.

### Poids (weight painting)
Chaque point du visage a un « poids » par os (0 = ne bouge pas, 1 = suit l'os complètement) ; c'est ce que l'on
« peint » dans Blender. Ici les poids sont calculés pour être lisses et cohérents (`previews/sheet_weights.png`,
bleu = 0 → rouge = 1) :
- **Sourcils** : chaque sourcil bouge **d'un bloc** (part « intérieur » + part « extérieur » = 1 sur tout le sourcil),
  avec un passage progressif de l'intérieur vers l'extérieur et une décroissance douce vers le front : froncer, lever
  l'intérieur (air triste) ou l'extérieur (arqué) garde la forme du sourcil (`previews/sheet_brows.png`).
- Sous les yeux / joues : décroissance vers les coins des yeux (pas de pli au coin) ; bouche : mâchoire, lèvres et
  coins partagés de façon à ne jamais croiser ; paupière + eyeliner : 100 % sur leur os.

### Recoloriable
Tout ce qui est peau (tête, paupières) est transparent dans la texture → couleur de la tête. Les yeux, les cils, les
sourcils et l'intérieur de la bouche sont opaques, donc **non recoloriables**.

## Vérifications faites
`tools/check_mesh.py` (relancé après chaque modification) :
- chaque pose à **25 / 50 / 75 / 100 %** (translations + rotations interpolées comme FaceControls) et les combinaisons
  des tests de validation Roblox (clignements + regard, bouche ouverte, joie, tristesse…) : aucun morceau qui traverse la
  peau, aucun triangle retourné, aucun étirement anormal ;
- au repos, la paupière rangée n'est visible **sous aucun angle** (face, dessous, dessus, côtés) ;
- œil fermé : l'ouverture est **entièrement couverte** sous tous ces angles ;
- on ne voit **jamais l'intérieur de l'œil hors des ouvertures** (le creux ne perce la peau nulle part) ;
- **aucune face vue de dos** (= trou dans Roblox) depuis 5 angles de caméra, pour toutes les poses à 50 / 100 % ;
- aucun triangle de peau qui se plie (> 35°) ;
- pas de double couche de peau, pas de trou, aucune face qui prend une texture d'œil ou de bouche hors de sa place
  (ni à l'arrière de la tête), et l'arrière de la tête n'est piloté par aucun os du visage.
**Résultat : 0 problème sur 151 cas + 7 tests globaux.** Mesh 100 % triangles (3982 / 4000 max), 4 influences d'os max,
aucun sommet sans poids, FBX aux mêmes axes / unités que le Blocky officiel de Roblox.

## Limites honnêtes
- **Pas pu tester dans Studio d'ici** (pas d'accès à Roblox depuis cet environnement). Si l'import ou la validation
  râle, envoie-moi le message exact.
- **Cage** : c'est la cage officielle de la tête Blocky (même topologie/UV donc mêmes repères yeux/bouche), recalée sur
  ce visage. Si la validation Marketplace refuse les repères de la cage, l'outil **Avatar Setup** de Studio peut
  régénérer la cage seule.
- Pas de dents ni de langue (style anime, bouche en trait). La doc Roblox les recommande mais la validation ne les exige
  pas.

## Reconstruire
```bash
VENV=<python avec bpy, numpy, pillow, opencv-python-headless, scipy>
$VENV tools/extract_face.py in/face_ref.webp build    # texture + données du visage
cp build/HeadTexture*.png .
$VENV tools/build_head.py .                           # géométrie, rig, poses, corps Blocky, export FBX
$VENV tools/check_mesh.py .                           # contrôle automatique des déformations
$VENV tools/render_previews.py . && $VENV tools/render_previews.py . close && $VENV tools/render_previews.py . blinkseq
$VENV tools/make_sheets.py .                          # planches previews/sheet_*.png
$VENV tools/render_weights.py .                       # carte des poids previews/sheet_weights.png
```
