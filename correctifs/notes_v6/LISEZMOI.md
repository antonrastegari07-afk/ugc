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

## 2. 🛒 Shop : « Restocked weekly! »

LocalScript `RestockInfo_SHOP.lua` **dans StarterGui ▸ UGCshop ▸ ShopFrame** (remplace l'ancienne version si tu l'avais mise).
- Le texte est **blanc, droit, sans emoji**, avec un contour noir.
- Horizontalement, il est **centré sur la colonne du milieu** des UGC (calculé sur les vraies cartes).
- Verticalement, il est **centré entre le haut du cadre principal et le haut de la liste**.

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

## 4. 🎽 UGC redeemed dans les profils + page « STATS & UGCS » des Settings

### Fiche profil
**StarterPlayerScripts ▸ PlayerProfileHover** (celui qui est **activé**) : remplace **tout** par `PlayerProfileHover_COMPLET.lua`.
- **En haut :** « UGC Redeemed · N » avec les **4 derniers UGC**, sans mini-défilement, et une carte **« See all (N) »**.
- **See all :** la grille de **tous** les UGC (4 par ligne, défilement vertical) s'affiche à la place des stats. « ← Back » revient à la fiche.
- **Couleurs :** le cadre a les couleurs de la fiche. Il est **doré seulement si le joueur est VIP**.
- **Stats :** dessous, comme avant.
- **Icône :** pour en mettre une devant « UGC Redeemed », écris `UGC_ICON = "rbxassetid://TON_ID"` en haut de la section.

### Settings : le bouton STATS devient « STATS & UGCS »
⚠️ Si tu avais déjà fait l'ancienne étape (onglet « Profile » + `buildButton`), **annule-la d'abord** : remets SettingsConfig et SettingsUI comme avant.

**ReplicatedStorage ▸ SettingsConfig** :

Cherche :
```lua
	stats    = { name = "STATS",    title = "Stats" },
```
Remplace par :
```lua
	stats    = { name = "STATS & UGCS",    title = "Stats & UGCs" },
```

**StarterPlayerScripts ▸ SettingsUI**, 5 changements :

1. Cherche `	local p = statCard("PROGRESSION", 2)` et remplace par `	local p = statCard("PROGRESSION", 3)`.
2. Cherche `	local s = statCard("STREAK", 3)` et remplace par `	local s = statCard("STREAK", 4)`.
3. Cherche `	local l = statCard("RIGHT NOW", 4)` et remplace par `	local l = statCard("RIGHT NOW", 5)`.
4. Cherche `local function fmtNum(n)`, colle **juste au-dessus** tout le contenu de `SettingsUI_UGC_SNIPPET.lua`, puis laisse la ligne `local function fmtNum(n)` en place.
5. Cherche :
   ```lua
   		refreshStats()
   		if reqCp then pcall(function() reqCp:FireServer() end) end
   ```
   Remplace par :
   ```lua
   		refreshStats()
   		loadMyUGCs()
   		if reqCp then pcall(function() reqCp:FireServer() end) end
   ```

Résultat : Settings ▸ **STATS & UGCS** ouvre la page Stats avec, en premier, **UGC REDEEMED** (« 12 UGCs redeemed » + la grille de tous tes UGC, 4 par ligne), puis Progression, Streak et Right now.

---

## Tests en Play
1. Redeem une UGC : le message violet arrive tout de suite dans le chat, une seule fois. Teste aussi avec 2 serveurs (Team Test).
2. Ouvre le shop UGC : le texte « UGCs restocked weekly! » est à droite du titre, sur PC et en émulateur téléphone.
3. Invite un ami, ferme le prompt, regarde une pub, puis attends 60 s en jeu publié : l'admin panel ▸ 📨 INVITES & PUBS affiche les compteurs. En Studio, rien n'est écrit, c'est normal.
4. Ouvre la fiche d'un autre joueur : 4 UGC en haut, « See all », puis Back. Le cadre est doré seulement pour un VIP.
5. Settings ▸ STATS & UGCS : tes UGC en premier, puis les stats.
