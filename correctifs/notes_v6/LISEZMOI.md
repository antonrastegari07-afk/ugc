# Notes v6 — « final published after all performance fix »

Fais une copie du jeu avant. Chaque « Cherche » ci-dessous existe **une seule fois** dans le script indiqué (vérifié sur ce fichier de jeu).

---

## 1. 📢 Annonces UGC dans le chat (pas toujours affichées)

**Causes :**
1. Une UGC n'était annoncée que si `PromptPurchaseFinished` répondait « acheté ». Les redeems confirmés autrement n'étaient jamais annoncés : vérifiés après coup, achat tardif, confirmés au retour du joueur, par l'admin…
2. L'annonce passait **uniquement** par MessagingService, sans réessai. Si l'envoi ou l'abonnement ratait, même les joueurs du serveur ne voyaient rien. Les petits achats de points, eux, sont envoyés directement : c'est pour ça qu'ils passaient toujours.
3. Un nom d'UGC avec `&`, `<` ou `>` cassait le texte enrichi du chat, et le message ne s'affichait pas.

**Installation :**
- **ServerScriptService ▸ notif chat** : remplace **tout** par `notif_chat_SERVEUR.lua`.
  - Affichage immédiat sur le serveur d'origine.
  - L'écho de MessagingService est ignoré (jamais en double).
  - L'envoi réessaie 3 fois.
  - L'abonnement réessaie jusqu'à réussir.
  - Anti-doublon de 5 min par joueur et par UGC.
  - Les annonces globales d'achats, de gifts et de donations profitent aussi de la même fiabilité.
- **StarterPlayerScripts ▸ suite notif chat** : remplace **tout** par `suite_notif_chat_CLIENT.lua`.
  - Échappe `& < > " '`.
  - Attend le canal du chat 10 s au lieu de 2.
- **ServerScriptService ▸ ugc redeems admin log**, une seule ligne à remplacer.

  Cherche :
  ```lua
  	if _G.UGCLiveFeed_Push then task.spawn(_G.UGCLiveFeed_Push, entry) end
  ```
  Remplace par :
  ```lua
  	if _G.UGCLiveFeed_Push then task.spawn(_G.UGCLiveFeed_Push, entry) end

  	-- 📢 Annonce chat pour TOUS les redeems confirmés (pas seulement l'achat direct)
  	local ANNOUNCE = { shop = true, late = true, verified_delivered = true, parked_late = true,
  		parked_confirmed = true, rejoin_confirmed = true, rejoin_recheck = true,
  		admin_confirm = true, admin_park_confirm = true, free = true }
  	if _G.NotifyUGC and ANNOUNCE[entry.s] then
  		task.spawn(pcall, _G.NotifyUGC, userId, entry.n, entry.an, entry.p)
  	end
  ```

  L'appel `_G.NotifyUGC` déjà présent dans `time` peut rester : l'anti-doublon empêche le double message. Les lignes « exploit » et « hors shop » ne sont jamais annoncées.

---

## 2. 🛒 Shop : « UGCs restocked weekly! »

Ajoute le LocalScript `RestockInfo_SHOP.lua` **dans StarterGui ▸ UGCshop ▸ ShopFrame**.

Il crée le texte à droite du titre « UGCs », entre le titre et le bouton X, avec la police du titre. La position se recalcule toute seule (PC, mobile, tablette).

Pour changer le texte ou la couleur, modifie `TEXT` / `COLOR` en haut du script.

---

## 3. 📨📺 Stats des invites et des pubs (admin panel)

Un nouveau bouton **📨 INVITES & PUBS** apparaît à l'accueil de l'admin panel, avec 3 périodes (aujourd'hui, 7 jours, 30 jours) et des graphiques par jour.

| Section | Ce qui est affiché |
|---|---|
| **👥 Joueurs** | Joueurs uniques par jour (moyenne), arrivées. |
| **📨 Invites** | Prompts ouverts (tous : bouton, carrousel d'offres, PNJ) et par combien de joueurs ; % des joueurs qui ouvrent l'invite ; invitations envoyées (amis cochés) ; joueurs qui ont envoyé ; moyenne d'amis invités par joueur ; % des prompts avec au moins 1 ami ; amis arrivés par invitation ; conversion arrivés / envoyés ; points donnés par le referral (parrains / filleuls). |
| **📺 Pubs** | Pubs lancées ; regardées jusqu'au bout (%) ; interrompues ; refusées (quota, pas prête…) ; % des joueurs qui regardent ; moyenne par joueur ; récompenses et points donnés. |

**Installation (4 ajouts + 4 petites lignes) :**

1. **ServerScriptService** : nouveau Script `ENGAGEMENT STATS` ← `ENGAGEMENT_STATS_SERVEUR.lua`.
2. **StarterPlayer ▸ StarterPlayerScripts** : nouveau LocalScript `EngageTrack` ← `EngageTrack_CLIENT.lua`. Il compte **chaque** prompt d'invitation, quelle que soit la façon dont il a été ouvert, via `SocialService.GameInvitePromptClosed`.
3. **ADMIN PANEL — CLIENT** : colle `ADMIN_BLOC15_INVITES_PUBS.lua` **juste avant** le bloc « 📜 BLOC 11 — CONSERVER LA POSITION DE DÉFILEMENT », c'est-à-dire après le `end)()` du BLOC 14.
4. **ServerScriptService ▸ ads Rewards** (celui qui est activé, V5), 3 remplacements :

   Cherche :
   ```lua
   	if player.Parent==Players then resultEvent:FireClient(player,success,reason,token) end
   ```
   Remplace par :
   ```lua
   	if player.Parent==Players then resultEvent:FireClient(player,success,reason,token) end
   	if _G.EngageStats then pcall(_G.EngageStats.AdResult,player.UserId,success,reason) end
   ```

   Cherche :
   ```lua
   	if DEBUG_ADS then print("[Ads] Demande de lecture : " .. player.Name) end
   ```
   Remplace par :
   ```lua
   	if DEBUG_ADS then print("[Ads] Demande de lecture : " .. player.Name) end
   	if _G.EngageStats then pcall(_G.EngageStats.AdShown,userId) end
   ```

   Cherche :
   ```lua
   	print(string.format("✅ PUB RÉCOMPENSÉE : %s +%d pts (%d/%d)",player.Name,AD_REWARD_POINTS,daily.count,AD_MAX_PER_DAY))
   ```
   Remplace par :
   ```lua
   	if _G.EngageStats then pcall(_G.EngageStats.AdReward,userId,AD_REWARD_POINTS) end
   	print(string.format("✅ PUB RÉCOMPENSÉE : %s +%d pts (%d/%d)",player.Name,AD_REWARD_POINTS,daily.count,AD_MAX_PER_DAY))
   ```
5. **ServerScriptService ▸ server referal friend invite**, 1 remplacement :

   Cherche :
   ```lua
   	print(string.format("🎁 REFERRAL: %s → +%d pts (%s)", player.Name, amount, source))
   ```
   Remplace par :
   ```lua
   	if _G.EngageStats then pcall(_G.EngageStats.Referral, userId, amount, source) end
   	print(string.format("🎁 REFERRAL: %s → +%d pts (%s)", player.Name, amount, source))
   ```

**Comment ça marche :**
- **Coût en requêtes faible.** Les compteurs sont gardés en mémoire et écrits **toutes les 60 s** (additions avec UpdateAsync : plusieurs serveurs ne s'écrasent jamais), plus à la fermeture du serveur. Aucune requête par clic.
- **Studio :** lecture seule, rien n'est écrit (comme 💸 REVENUS).
- **Sécurité :** le client peut seulement dire « j'ai fermé un prompt avec N amis ». N est plafonné à 50, avec un anti-spam (10 prompts par minute). Ce ne sont que des stats : aucun point n'est donné.
- **Les compteurs démarrent à l'installation :** il n'y a pas d'historique avant.

---

## 4. 🎽 UGC redeemed en premier dans les profils + « My UGCs & Stats »

### Fiche profil (la tienne et celle des autres)
**StarterPlayerScripts ▸ PlayerProfileHover** (celui qui est **activé** ; l'autre copie est désactivée) : remplace **tout** par `PlayerProfileHover_COMPLET.lua`.
- Les UGC récupérés sont maintenant **tout en haut**, dans un cadre doré : « 🎽 UGC Redeemed · N ».
- Les UGC s'affichent dans un bandeau de cartes (image, nom, #numéro) qui défile de gauche à droite, la plus récente à gauche.
- Les stats sont en dessous, sous un titre « Stats », dans le même style qu'avant.
- Le reste ne change pas : bouton Gift, VIP, fiche ouverte depuis un leaderboard…
- Nouveau : `_G.OpenMyProfile()` ouvre **ta propre fiche**.

### Settings : onglet « Profile » avec un bouton
**ReplicatedStorage ▸ SettingsConfig**, cherche :
```lua
C.Categories = {
```
Remplace par :
```lua
C.Categories = {
	{
		id = "profile", name = "Profile",
		items = {
			{ type = "button", label = "🎽 My UGCs & Stats", button = "Open", action = "myProfile" },
		},
	},
```

**StarterPlayerScripts ▸ SettingsUI**, 3 remplacements :

Cherche :
```lua
local function isPointer(input)
```
Remplace par :
```lua
-- 🆕 Ligne avec un bouton (ex. « My UGCs & Stats » → ouvre ta fiche profil)
local BUTTON_ACTIONS = {
	myProfile = function()
		if _G.OpenMyProfile then return _G.OpenMyProfile() end
		return false
	end,
}
local function buildButton(parent, item, order)
	local f = card(parent, order, 60)
	cardText(f, item, 150, true)
	local holder = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(140, 42), BackgroundTransparency = 1 }, f)
	local btn = button3D(holder, item.button or "Open", COL.blue, UDim2.fromScale(1, 1), 17)
	btn.Activated:Connect(function()
		local fn = BUTTON_ACTIONS[item.action]
		if fn then pcall(fn) end
	end)
	return f
end

local function isPointer(input)
```

Cherche :
```lua
		elseif item.type == "advanced" then
```
Remplace par :
```lua
		elseif item.type == "button" then
			fr = buildButton(body, item, nextOrder())
		elseif item.type == "advanced" then
```

Cherche :
```lua
	corner(rb, 7)
```
Remplace par :
```lua
	corner(rb, 7)
	-- pas de bouton Reset dans une section sans réglage (ex. Profile)
	local hasKey = false
	for _, item in ipairs(cat.items) do if item.key then hasKey = true end end
	rb.Visible = hasKey
```

« Profile » devient le 1er onglet des Settings. Le bouton ouvre ta fiche par-dessus les Settings ; quand tu la fermes, tu reviens aux Settings. La fiche ne s'ouvre pas en arène PvP, comme les autres fiches.

---

## Tests en Play
1. Redeem une UGC : le message violet arrive tout de suite dans le chat, une seule fois. Teste aussi avec 2 serveurs (Team Test).
2. Ouvre le shop UGC : le texte « UGCs restocked weekly! » est à droite du titre, sur PC et en émulateur téléphone.
3. Invite un ami, ferme le prompt, regarde une pub, puis attends 60 s en jeu publié : l'admin panel ▸ 📨 INVITES & PUBS affiche les compteurs. En Studio, rien n'est écrit, c'est normal.
4. Ouvre la fiche d'un autre joueur : les UGC sont en haut, les stats en dessous.
5. Settings ▸ Profile ▸ Open : ta fiche s'ouvre avec tes UGC.
