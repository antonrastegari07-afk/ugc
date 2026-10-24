# UIFocusSystem + Rookie Guide — corrections

Les fichiers de ce dossier (et `RookieGuide/RookieGuide.lua`) sont les scripts
extraits de tes `.rbxm`, corrigés. Dans Studio, ouvre le script du même nom et
**remplace tout son contenu** par celui du fichier.

| Fichier | Où dans Studio |
|---|---|
| `SceneEffects.lua` | StarterGui ▸ UIFocusSystem ▸ SceneEffects |
| `FocusEngine.lua` | StarterGui ▸ UIFocusSystem ▸ FocusEngine |
| `UIFocusClient.lua` | StarterGui ▸ UIFocusSystem ▸ UIFocusClient |
| `UI_FOCUS_CONFIG.lua` | StarterGui ▸ UIFocusSystem ▸ UI_FOCUS_CONFIG |
| `Client_try_ugc.lua` | StarterGui ▸ UGCshop ▸ ShopFrame ▸ TRYUGCFrame ▸ TryUGC ▸ **Client try ugc** |
| `../RookieGuide/RookieGuide.lua` | StarterPlayer ▸ StarterPlayerScripts ▸ RookieGuide |

## Ce qui est corrigé

**FOV qui reste plus haut après la fermeture.**
À l'ouverture d'un menu, `SceneEffects` lisait le FOV de la caméra à cet
instant et le prenait pour le FOV « normal ». Si le FOV était provisoirement
plus haut à ce moment-là (coup de FOV du dash de la faux, tween d'un autre
script pas fini…), cette valeur devenait le normal : à la fermeture, le FOV
revenait dessus et restait comme ça jusqu'à ce que le joueur rejoigne.
Maintenant le FOV normal est appris au repos : celui du départ, mis à jour
seulement quand aucun menu n'est ouvert et que le FOV n'a pas bougé pendant 1 s.

`Client_try_ugc` avait encore son propre zoom + flou (−10 de FOV, flou 24),
en plus de UIFocusSystem : deux scripts propriétaires du FOV. Ses fonctions
`applyCameraEffects` / `removeCameraEffects` sont maintenant vides ; UIFocus
gère déjà la fenêtre TRY (menu `UGCTry`).

**Flou pendant la partie jouable du Rookie Guide.**
Pendant la phase jouable (`RookieGuidePhase = "play"`), tous les `BlurEffect`
sous la caméra et dans `Lighting` sont coupés, quelle que soit leur origine,
puis remis exactement comme avant à la fin de la phase.

**Flou quand le joueur ouvre la boutique UGC pendant le guide.**
Le menu RookieGuide prête maintenant ses effets caméra à la boutique UGC
(`CameraEffectsFrom = { "UGCshop" }` dans UI_FOCUS_CONFIG) : boutique ouverte
→ flou + zoom ; le reste du guide → rien.

**Texte du guide plus lisible.**
Un fond noir semi-transparent, arrondi, qui s'efface en dégradé sur les deux
côtés, derrière le texte. Opacité réglable : ajoute
`BackdropTransparency = 0.45` dans `Style` de RookieConfig (0 = noir plein,
1 = invisible).

## À vérifier dans ton jeu

- Le ScreenGui `ancien UGCshop (PAs SUPPRIMER…` contient une vieille copie de
  `Client try ugc` avec le même zoom. Désactive ce script-là
  (Properties ▸ Enabled décoché) : ancien UGCshop ▸ ShopFrame ▸ TRYUGCFrame ▸
  TryUGC ▸ Client try ugc.
- `JackCinematics` et `NpcDialog_Client` ne sont pas dans les fichiers fournis.
  S'ils changent le FOV, ils doivent le remettre eux-mêmes à la fin.
