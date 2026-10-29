# Liste exacte de ce que le convertisseur touche

**1177 Scripts, tous dans le Workspace.** Rien dans ServerScriptService, StarterPlayer, StarterGui, ReplicatedStorage ou ServerStorage.

Pour chacun : le Script est **déplacé** dans `ServerStorage ▸ WorkspaceScriptsBackup` (rien n'est supprimé). Sa part reçoit un Tag `WSM_…` et des attributs `WSM_…` qui contiennent ses réglages.

En plus :
- **8 ParticleEmitter** de `Workspace.DonationEffect2` sont enregistrés `Enabled = false` (tes scripts de dons les éteignent déjà 5 s après le démarrage, et les rallument pendant un don).
- Pour les **13 danseurs** : leur `Animation` est copiée dans le modèle sous le nom `WSM_DanceAnimation`.

Les chemins sont ceux de l'Explorer : beaucoup d'objets portent le même nom (`Part`, `Model`…), d'où les « ×N ».

## Kill brick (tue au toucher) — 416 scripts

- `Workspace.Boutonplate10.Part.Script` ×2
- `Workspace.Boutonplate16.Part.Script` ×3
- `Workspace.Boutonplate5.Part.Script` ×3
- `Workspace.Level laser.Part.Script` ×21
- `Workspace.Model.Model.Part.Script` ×18
- `Workspace.Model.Part.Script` ×90
- `Workspace.Model.Part10.Script` ×48
- `Workspace.Model.Part21.Script` ×24
- `Workspace.Model.Part22.Script` ×24
- `Workspace.Model.Part9.Script` ×6
- `Workspace.Model12.Part.Script` ×20
- `Workspace.MovingPlatform.Part9.Script` ×2
- `Workspace.Part.Script` ×88
- `Workspace.Part10.Script`
- `Workspace.Part21.Script`
- `Workspace.Part22.Script`
- `Workspace.Part23.Script`
- `Workspace.Part7.Script`
- `Workspace.Part8.Script`
- `Workspace.Part9.Script` ×40
- `Workspace.Undermapkill.Script` ×13
- `Workspace.spiketrap.piegepiques.Part.Script` ×8

## Drop part (disparaît puis revient) — 400 scripts

- `Workspace.Boutonplate14.Part.Script` — DisappearDelay = 0.05 ×21
- `Workspace.Model.Model.Part.Script` — DisappearDelay = 0.25
- `Workspace.Model.Obby Stair.Script` — DisappearDelay = 0.05 ×18
- `Workspace.Model.Part.Script` — DisappearDelay = 0.05 ×234
- `Workspace.Model.Part.Script` — DisappearDelay = 0.5 ×9
- `Workspace.Model.Part.Script` — DisappearDelay = 1 ×3
- `Workspace.Model.Part1.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part1.Script` — DisappearDelay = 0.5
- `Workspace.Model.Part10.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part11.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part2.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part2.Script` — DisappearDelay = 0.5
- `Workspace.Model.Part3.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part3.Script` — DisappearDelay = 0.5
- `Workspace.Model.Part4.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part4.Script` — DisappearDelay = 0.5
- `Workspace.Model.Part5.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part5.Script` — DisappearDelay = 0.5
- `Workspace.Model.Part6.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part6.Script` — DisappearDelay = 0.5
- `Workspace.Model.Part7.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part7.Script` — DisappearDelay = 0.5
- `Workspace.Model.Part8.Script` — DisappearDelay = 0.05
- `Workspace.Model.Part8.Script` — DisappearDelay = 0.5
- `Workspace.Model.Part9.Script` — DisappearDelay = 0.05
- `Workspace.Model9.Part.Script` — DisappearDelay = 0.5 ×9
- `Workspace.Part.Script` — DisappearDelay = 0.05 ×52
- `Workspace.Part24.Script` — DisappearDelay = 0.05
- `Workspace.Part6.Script` — DisappearDelay = 0.05
- `Workspace.drop part.Script` — DisappearDelay = 0.05 ×29
- `Workspace.drop part1.Script` — DisappearDelay = 0.05
- `Workspace.drop part2.Script` — DisappearDelay = 0.05
- `Workspace.drop part3.Script` — DisappearDelay = 0.05

## Bloc de dégâts — 99 scripts

- `Workspace.Damage Block.damage` — Damage = 20, WaitTime = 0.05 ×2
- `Workspace.Damage Block.damage` — Damage = 20, WaitTime = 1 ×24
- `Workspace.Model.Damage Block.damage` — Damage = 20, WaitTime = 0.04
- `Workspace.Model.Damage Block.damage` — Damage = 20, WaitTime = 0.5
- `Workspace.Model.Damage Block.damage` — Damage = 20, WaitTime = 1 ×19
- `Workspace.Model.Damage Block.damage` — Damage = 49, WaitTime = 1 ×2
- `Workspace.Model.Model.Damage Block.damage` — Damage = 10, WaitTime = 1 ×23
- `Workspace.Model.Model.Damage Block.damage` — Damage = 25, WaitTime = 1
- `Workspace.Model3.Model.Damage Block.damage` — Damage = 10, WaitTime = 1 ×12
- `Workspace.Model7.Model.Damage Block.damage` — Damage = 10, WaitTime = 1 ×11
- `Workspace.Model7.Model.Damage Block.damage` — Damage = 25, WaitTime = 1
- `Workspace.Plateforme.Damage Block.damage` — Damage = 34, WaitTime = 0.5 ×2

## Achat au toucher (coils) — 60 scripts

- `Workspace.FusionCoil(UNGROUP).coilbaseGravity.touchpass` — GamepassId = 1889975133, RemoteName = FenetreachatFUSIONCOIL ×7
- `Workspace.GravityCoil (UNGROUP).coilbaseGravity.touchpass` — GamepassId = 1890875059, RemoteName = fenetreachatGRAVITYCOIL ×7
- `Workspace.SpeedCoil (UNGROUP).coilbaseSpeed.touchpass` — GamepassId = 1890659135, RemoteName = fenetredachatSPEEDCOIL ×7
- `Workspace.achat presenter + effects.purshase offers coil and x2coin.FusionCoil(UNGROUP).coilbaseGravity.touchpass` — GamepassId = 1889975133, RemoteName = FenetreachatFUSIONCOIL ×13
- `Workspace.achat presenter + effects.purshase offers coil and x2coin.GravityCoil (UNGROUP).coilbaseGravity.touchpass` — GamepassId = 1890875059, RemoteName = fenetreachatGRAVITYCOIL ×13
- `Workspace.achat presenter + effects.purshase offers coil and x2coin.SpeedCoil (UNGROUP).coilbaseSpeed.touchpass` — GamepassId = 1890659135, RemoteName = fenetredachatSPEEDCOIL ×13

## Projection / bounce pad — 47 scripts

- `Workspace.Boutonplate13.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 30, ForceHaut = 90
- `Workspace.Boutonplate9.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 100, ForceHaut = 80
- `Workspace.Level laser.BouncePad.LaunchScript` — Cooldown = 0.3, ForceAvant = 0, ForceHaut = 80
- `Workspace.Model.BouncePad.LaunchScript` — Cooldown = 0.3, ForceAvant = 0, ForceHaut = 160
- `Workspace.Model.BouncePad.LaunchScript` — Cooldown = 0.3, ForceAvant = 0, ForceHaut = 175
- `Workspace.Model.BouncePad.LaunchScript` — Cooldown = 0.3, ForceAvant = 40, ForceHaut = 120 ×4
- `Workspace.Model.BouncePad.LaunchScript` — Cooldown = 0.3, ForceAvant = 40, ForceHaut = 80 ×2
- `Workspace.Model.Champignon.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 20, ForceHaut = 100
- `Workspace.Model.Champignon.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 20, ForceHaut = 130
- `Workspace.Model.Champignon.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 30, ForceHaut = 70
- `Workspace.Model.Champignon.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 50, ForceHaut = 100
- `Workspace.Model.Part.Script` — Cooldown = 0.3, ForceAvant = 48, ForceHaut = 75 ×5
- `Workspace.Model.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 100, ForceHaut = 80
- `Workspace.Model.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 125, ForceHaut = 75
- `Workspace.Model.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 135, ForceHaut = 80
- `Workspace.Model.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 150, ForceHaut = 170
- `Workspace.Model.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 20, ForceHaut = 150
- `Workspace.Model.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 40, ForceHaut = 40
- `Workspace.Model.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 50, ForceHaut = 80
- `Workspace.Model.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 80, ForceHaut = -170
- `Workspace.partzone3.apparitionpart.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 50, ForceHaut = 50
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 0, ForceHaut = 100 ×7
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 0, ForceHaut = 175
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 0, ForceHaut = 50
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 100, ForceHaut = 0 ×2
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 100, ForceHaut = 150
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 100, ForceHaut = 80
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 20, ForceHaut = 60
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 200, ForceHaut = 100
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 50, ForceHaut = 100
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 85, ForceHaut = 80
- `Workspace.projection bloc.Script` — Cooldown = 0.3, ForceAvant = 95, ForceHaut = 80

## Fondu au toucher — 43 scripts

- `Workspace.Part.Script` ×43

## Spot qui clignote (passe côté joueur) — 32 scripts

- `Workspace.Boutonplate12.Portails.Portail1.Part.Attachment.SpotLight.Script` ×2
- `Workspace.Boutonplate12.Portails.Portail2.Part.Attachment.SpotLight.Script`
- `Workspace.Boutonplate14.Portails.Portail1.Part.Attachment.SpotLight.Script` ×2
- `Workspace.Boutonplate14.Portails.Portail2.Part.Attachment.SpotLight.Script`
- `Workspace.Boutonplate17.Portail1.Part.Attachment.SpotLight.Script` ×2
- `Workspace.Boutonplate17.Portail2.Part.Attachment.SpotLight.Script`
- `Workspace.Portails.Portail1.Part.Attachment.SpotLight.Script` ×15
- `Workspace.Portails.Portail2.Part.Attachment.SpotLight.Script` ×8

## Achat au toucher (x2 coins) — 20 scripts

- `Workspace.Model.x2coinbase.detecte le touch = remote event au local pour declancher achat` — GamepassId = 1891007119
- `Workspace.achat presenter + effects.purshase offers coil and x2coin.x2coinbase.detecte le touch = remote event au local pour declancher achat` — GamepassId = 1891007119 ×13
- `Workspace.x2coinbase.detecte le touch = remote event au local pour declancher achat` — GamepassId = 1891007119 ×6

## Son de bouton — 19 scripts

- `Workspace.Bouton1.bouton son`
- `Workspace.Bouton10.bouton son`
- `Workspace.Bouton11.bouton son`
- `Workspace.Bouton12.bouton son`
- `Workspace.Bouton13.bouton son`
- `Workspace.Bouton14.bouton son`
- `Workspace.Bouton15.bouton son`
- `Workspace.Bouton16.bouton son`
- `Workspace.Bouton17.bouton son`
- `Workspace.Bouton18.bouton son`
- `Workspace.Bouton19.bouton son`
- `Workspace.Bouton2.bouton son`
- `Workspace.Bouton3.bouton son`
- `Workspace.Bouton4.bouton son`
- `Workspace.Bouton5.bouton son`
- `Workspace.Bouton6.bouton son`
- `Workspace.Bouton7.bouton son`
- `Workspace.Bouton8.bouton son`
- `Workspace.Bouton9.bouton son`

## Tapis roulant (Hard obby) — 13 scripts

- `Workspace.Hard obby part.Script` ×7
- `Workspace.Model.Hard obby part.Script` ×6

## Danseur — 13 scripts

- `Workspace.dancing rig with message..Script` ×13

## Portail — 11 scripts

- `Workspace.Boutonplate12.Portails.Script`
- `Workspace.Boutonplate14.Portails.Script`
- `Workspace.Boutonplate17.Script`
- `Workspace.Portails.Script` ×8

## Flashing Brick (passe côté joueur) — 4 scripts

- `Workspace.Model.Flashing Brick.Script` ×2
- `Workspace.Model.Model.Flashing Brick.Script` ×2
