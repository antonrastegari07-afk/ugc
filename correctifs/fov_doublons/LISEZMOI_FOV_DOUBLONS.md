# Doublons FOV / zoom : causes et correctifs

Analysé sur ta version « whole game after all little script part unity ». **Fais une copie du jeu avant.**

## La cause commune

Plusieurs scripts **mémorisent le FOV « de l'instant »**, puis le remettent à la fin de leur effet. Si à cet instant le FOV n'était pas normal (fin d'un zoom de menu, sprint, visée, boost…), c'est **cette mauvaise valeur** qui est remise.

UIFocus aggravait le problème : il **« apprenait »** comme nouveau FOV normal n'importe quel FOV resté stable 1 s.
- **Valeur un peu en dessous du normal :** UIFocus la corrigeait. C'est le zoom puis dézoom que tu vois.
- **Valeur au-dessus du normal, ou très en dessous :** elle devenait le nouveau normal. Le joueur restait bloqué dessus jusqu'au rejoin.

## Les bugs trouvés

| # | Script | Ce qu'il faisait | Résultat |
|---|---|---|---|
| 1 | **DeathCam** | Mémorise le FOV **au moment de la mort**, puis le remet au respawn. | Mort en sprintant (≈ 78) ou en visant (65), puis respawn sans arme : **bloqué**. |
| 2 | **RobuxPromptFX ▸ UIZoomController** (zoom du prompt d'achat) | UIFocus « corrigeait » son zoom au bout d'1 s, alors que le prompt était encore ouvert. Et si le prompt s'ouvrait pendant un menu, il gardait le FOV zoomé du menu comme base. | Zoom puis dézoom ; FOV parfois laissé à 60. |
| 3 | **UIFocus ▸ SceneEffects** | Apprenait comme normal tout FOV stable 1 s : boost de jetpack tenu, caméra de dialogue… | **Bloqué** sur ce FOV, et les menus y revenaient aussi. |
| 4 | **jetpack gestion** (2 copies) | Mémorise le FOV à l'équipement (par exemple 78 si tu passes d'une arme en sprint au jetpack). | Remis à la fin du boost et au déséquipement. |
| 5 | **ZiplineClient** | Mémorise le FOV à l'accroche. | Remis en descendant de la zipline. |
| 6 | **NpcDialog_Client** et **HideoutSpectate** | Mémorisent le FOV au début. | Remis à la fin. |
| 7 | **WeaponMechanics** | Dès qu'une arme est **dans le sac**, il ramène le FOV à 70 **à chaque image**, en doublon d'UIFocus. | Il se bat avec le zoom d'achat, le boost du jetpack et la zipline : zoom / dézoom, effets à moitié visibles. |

## La correction

- **Un seul FOV normal, fixe : 70.** C'est déjà le `HipFOV` des armes et du sprint. UIFocus le publie sur la caméra (attribut `UIFocusNormalFOV`), et **tous les scripts reviennent à cette valeur** au lieu de celle de l'instant.
- **Chaque script qui pilote le FOV le signale** pendant son effet :
  - `ZiplineFOVAdd` et `InArena` (déjà là) ;
  - `UIZoomActive` (zoom d'achat) ;
  - `JetpackFOV` (sur le perso) ;
  - `MechanicsFOVActive` (sprint) ;
  - `InNpcDialog` (déjà là) ;
  - une caméra non `Custom` (killcam, dialogue, spectate).
- **Filet de sécurité dans UIFocus** : si le FOV reste différent de 70 plus d'1 s et que **personne** ne le pilote, il est remis à 70 en douceur. Aucun bug restant ne peut donc bloquer le FOV.
- **WeaponMechanics** n'écrit plus le FOV que pendant son propre effet (sprint / vitesse) et le temps de revenir à 70.

Les menus gardent leur zoom et leur flou, et les armes gardent visée, sprint et zipline : ces scripts-là ne sont pas modifiés.

## Installation (9 scripts)

### 1. StarterGui ▸ UIFocusSystem ▸ SceneEffects
Remplace **tout** le contenu par `fov_doublons/SceneEffects_COMPLET.lua`.

### 2. ReplicatedStorage ▸ RobuxPromptFX ▸ UIZoomController
Remplace **tout** le contenu par `fov_doublons/UIZoomController_COMPLET.lua`.

### 3. ServerStorage ▸ Jetpack ▸ jetpack gestion **ET** ServerStorage ▸ AdminAbuseTools ▸ Jetpack ▸ jetpack gestion (les 2 copies, mêmes remplacements)

**Remplacement 1/2**

Cherche (Ctrl+F) :
```lua
	originalFOV = cam().FieldOfView
```
Remplace par :
```lua
	-- 🩹 FOV normal (UIFocus) au lieu du FOV de l'instant (sprint, fin de menu, boost…)
	originalFOV = cam():GetAttribute("UIFocusNormalFOV") or 70
	character:SetAttribute("JetpackFOV", true)   -- UIFocus ne touche pas au FOV tant que le jetpack est en main
```

**Remplacement 2/2**

Cherche (Ctrl+F) :
```lua
	if originalFOV then cam().FieldOfView = originalFOV end
end
```
Remplace par :
```lua
	if originalFOV then cam().FieldOfView = originalFOV end
	if character then character:SetAttribute("JetpackFOV", nil) end
end
```

### 4. StarterPlayerScripts ▸ ZiplineClient

Cherche (Ctrl+F) :
```lua
		baseFOV = Config.Camera.FOVBase or camera.FieldOfView,
```
Remplace par :
```lua
		baseFOV = Config.Camera.FOVBase or camera:GetAttribute("UIFocusNormalFOV") or 70,  -- 🩹 FOV normal, pas celui de l'instant
```

### 5. StarterPlayerScripts ▸ DeathCam

Cherche (Ctrl+F) :
```lua
		fov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView,
```
Remplace par :
```lua
		-- 🩹 au respawn on remet le FOV NORMAL, pas celui du moment de la mort (visée, sprint…)
		fov = workspace.CurrentCamera and (workspace.CurrentCamera:GetAttribute("UIFocusNormalFOV") or 70),
```

### 6. StarterPlayerScripts ▸ NpcDialog_Client

Cherche (Ctrl+F) :
```lua
	camSaved = camRestore or { type = cam.CameraType, cf = cam.CFrame, fov = cam.FieldOfView, subject = cam.CameraSubject }
```
Remplace par :
```lua
	-- 🩹 fin du dialogue : retour au FOV NORMAL, pas à celui de l'instant où il a commencé
	camSaved = camRestore or { type = cam.CameraType, cf = cam.CFrame, fov = cam:GetAttribute("UIFocusNormalFOV") or cam.FieldOfView, subject = cam.CameraSubject }
```

### 7. ReplicatedStorage ▸ HideoutSpectate

Cherche (Ctrl+F) :
```lua
		fov = camera and camera.FieldOfView, mouseIcon = UIS.MouseIconEnabled,
```
Remplace par :
```lua
		fov = camera and (camera:GetAttribute("UIFocusNormalFOV") or camera.FieldOfView), mouseIcon = UIS.MouseIconEnabled,  -- 🩹 FOV normal
```

### 8. ReplicatedStorage ▸ WeaponSystem ▸ WeaponMechanics

**Remplacement 1/3**

Cherche (Ctrl+F) :
```lua
	local sprintAlpha  = 0
```
Remplace par :
```lua
	local sprintAlpha  = 0
	local mechFOVActive = false   -- 🩹 ce script pilote le FOV (sprint / vitesse) en ce moment
```

**Remplacement 2/3**

Cherche (Ctrl+F) :
```lua
			WeaponSharedState.PublishMoveFOV(sprintAlpha * cfg.Sprint.FOVKick)
```
Remplace par :
```lua
			WeaponSharedState.PublishMoveFOV(sprintAlpha * cfg.Sprint.FOVKick)
			if mechFOVActive then mechFOVActive = false; player:SetAttribute("MechanicsFOVActive", nil) end
```

**Remplacement 3/3**

Cherche (Ctrl+F) :
```lua
			local target = cfg.Sprint.HipFOV + fovKick
			camera.FieldOfView += (target - camera.FieldOfView) * math.clamp(dt * 10, 0, 1)
```
Remplace par :
```lua
			local target = cfg.Sprint.HipFOV + fovKick
			-- 🩹 On n'écrit le FOV que pendant NOTRE effet (sprint / vitesse) et le temps de revenir.
			--    Avant : ramené à 70 à CHAQUE image dès qu'une arme était dans le sac → ça se battait
			--    avec le zoom d'achat, le boost du jetpack et la zipline (zoom / dézoom).
			local cam = workspace.CurrentCamera
			if cam and (fovKick > 0.01 or mechFOVActive) then
				cam.FieldOfView += (target - cam.FieldOfView) * math.clamp(dt * 10, 0, 1)
				local still = fovKick > 0.01 or math.abs(target - cam.FieldOfView) > 0.05
				if not still then cam.FieldOfView = target end
				if still ~= mechFOVActive then
					mechFOVActive = still
					player:SetAttribute("MechanicsFOVActive", still or nil)
				end
			end
```

## Peut être supprimé (inutile, ne tourne pas)
- `ReplicatedStorage ▸ RobuxPromptFX (old one)` : aucun script ne le charge.
- `StarterPlayerScripts ▸ test effeect screen robux` et `StarterPlayerScripts ▸ test` : désactivés.
- Dans les armes de ServerStorage (AK47, Deagle, Sniper, Minigun, ShotGun, AutoPistol, RPG), les anciens scripts désactivés (`ak47`, `sniper`, `Clienttest`, `deagle 2.0`…) changeaient le FOV eux-mêmes. Ils sont **désactivés** et ne posent pas de problème. Seuls les `new …` tournent, et ils passent par le WeaponController.

## Gardés tels quels (pas de doublon)
- **WeaponController** : FOV des armes en main ; UIFocus ne le corrige pas, le patch FOV précédent est déjà installé.
- **JackScythe_Client** : coup de FOV du dash ; il revient déjà au FOV normal d'UIFocus.
- **WeaponDeathCleanup** : remet 70 si la lunette est restée après la mort ; filet utile.
- **Loading screen** : met 70 au chargement.
- **camera behind** : remet la caméra derrière le perso au spawn ; ne touche pas au FOV.
- **Flou :** les flous du popup « leave » et du 1v1 cross server sont à eux et sont retirés à la fermeture. Celui d'Halloween est déjà coupé (`BlurSize = 0`). Aucun doublon de flou trouvé.

## Tests à faire en Play
1. Ouvre et ferme le shop plusieurs fois, vite : retour net à 70.
2. Achat Robux hors menu : zoom pendant tout le prompt, **sans dézoom au milieu**, puis retour à 70.
3. Achat Robux depuis le shop, puis ferme le shop : 70.
4. En PvP, meurs en sprintant ou en visant, puis respawn : 70.
5. Jetpack : boost tenu 3 s, puis déséquipe : 70.
6. Zipline juste après avoir fermé un menu : 70 en descendant.
7. Dialogue PNJ : 70 à la fin.
8. Avec une arme dans le sac : sprint, puis jetpack et zipline : plus de saccade de FOV.
