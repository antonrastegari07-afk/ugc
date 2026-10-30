# 📊 STATS v2 — achats par provenance, popups, 1re UGC gratuite

Le bouton **📨 INVITES & PUBS** devient **📊 STATS**. Mêmes DataStores : les compteurs déjà enregistrés sont gardés.

## Ce que tu vois (aujourd'hui / 7 j / 30 j)
- **👥 Joueurs :** uniques par jour, arrivées, % qui jouent avec au moins 1 ami.
- **💸 Achats — d'où ils viennent :**
  - fenêtres d'achat ouvertes, achats, conversion, Robux, % des joueurs qui achètent ;
  - puis **chaque provenance** (shop de points, shop ▸ armes / outils / crates, popup VIP, carrousel d'offres, offre après des morts, offre auto toutes les 20 min, coil touché sur la map, roue, streak, gifting, skip obby/level, rebirth, dons…) avec achats / fenêtres (%) et Robux ;
  - et, en dessous, **ses 6 objets principaux** (ex. « VIP : 3 / 40 (8 %) »).
- **🔔 Popups — valent-ils le coup ?**
  - popup VIP, bouton pub, popup de départ : affichages, joueurs, achats via ce popup, % des affichages, Robux ;
  - pour le bouton pub : pubs regardées.
- **🎽 1re UGC gratuite :**
  - pour les nouveaux joueurs qui n'ont **jamais rien payé** : temps de jeu (médiane, moyenne, 25 % → 75 %), jours de connexion et jours calendaires avant leur 1re UGC ;
  - seulement les joueurs arrivés **après l'installation**, sinon on ne connaît pas leur début.
- **📨 Invites & amis :** fenêtres d'invitation, % des joueurs qui invitent, amis arrivés par invitation, points de parrainage.
- **📺 Pubs :** lancées, regardées jusqu'au bout (%), % des joueurs, moyenne par joueur, points donnés.

**Les chiffres qui restaient à 0 ont été retirés :**
- « invitations envoyées / amis cochés » : Roblox ne donne pas cette liste au jeu ;
- « pubs interrompues / refusées » : quasi toujours 0.

## Comment on sait d'où vient un achat (rien n'est oublié)
- **Toutes les fenêtres d'achat sont comptées par Roblox lui-même** côté serveur, quel que soit le script qui les ouvre.
- **La provenance**, dans cet ordre :
  1. le script qui ouvre la fenêtre (via `MarketplaceServiceFX`, utilisé par la plupart de tes boutons) ;
  2. sinon le dernier bouton cliqué ;
  3. sinon le dernier popup affiché ;
  4. sinon l'objet proposé (coil, pack, offre de morts…) ;
  5. sinon « ⚙️ Auto / serveur ».
- **Les achats :** produits comptés au **reçu** (vrai paiement), gamepass quand Roblox confirme l'achat.
- **Une provenance inconnue** s'affiche avec son nom brut, préfixé par « ❔ ».

## Installation
1. **ServerScriptService ▸ ENGAGEMENT STATS** : remplace **tout** par `STATS_SERVEUR.lua`. Tu peux le renommer `STATS`.
2. **StarterPlayerScripts ▸ EngageTrack** : remplace **tout** par `EngageTrack_CLIENT.lua`.
3. **ReplicatedStorage ▸ MarketplaceServiceFX** : remplace **tout** par `MarketplaceServiceFX_COMPLET.lua`. Il signale seulement quel script ouvre la fenêtre ; l'achat ne change pas.
4. **ADMIN PANEL — CLIENT** : remplace l'ancien bloc 15 (de « 📨 BLOC 15 — INVITES & PUBS » à son `end)()`) par `ADMIN_BLOC15_STATS.lua`.
5. **ServerScriptService ▸ ECONOMY STATS**, 1 remplacement.

   Cherche :
   ```lua
   		if first then ev.f = 1 end
   	end
   	flushKey(push("d", ev))
   end
   ```
   Remplace par :
   ```lua
   		if first then ev.f = 1 end
   	end
   	-- 📊 STATS : d'où vient cet achat
   	if not isAd and _G.EngageStats and _G.EngageStats.Purchase then
   		task.spawn(pcall, _G.EngageStats.Purchase, uid, productId, r)
   	end
   	flushKey(push("d", ev))
   end
   ```
6. **ServerScriptService ▸ ugc redeems admin log**, 1 remplacement. C'est le bloc « Annonce chat » que tu as déjà ajouté.

   Cherche :
   ```lua
   	if _G.NotifyUGC and ANNOUNCE[entry.s] then
   		task.spawn(pcall, _G.NotifyUGC, userId, entry.n, entry.an, entry.p)
   	end
   ```
   Remplace par :
   ```lua
   	if _G.NotifyUGC and ANNOUNCE[entry.s] then
   		task.spawn(pcall, _G.NotifyUGC, userId, entry.n, entry.an, entry.p)
   	end
   	-- 📊 STATS : temps avant la 1re UGC gratuite
   	if _G.EngageStats and _G.EngageStats.UGCRedeemed and ANNOUNCE[entry.s] then
   		task.spawn(pcall, _G.EngageStats.UGCRedeemed, userId)
   	end
   ```

Les lignes déjà ajoutées dans **ads Rewards** et **server referal friend invite** (v1) restent valables. Ne les change pas.

## Tests (en jeu publié ; en Studio rien n'est écrit)
1. Achète quelque chose dans le shop de points, puis attends 60 s : 📊 STATS ▸ « 🛒 Shop de points » affiche 1 / 1.
2. Ouvre une fenêtre d'achat puis annule : la fenêtre est comptée, sans achat.
3. Le popup VIP s'affiche : « 🔔 Popup VIP » compte 1 affichage.
