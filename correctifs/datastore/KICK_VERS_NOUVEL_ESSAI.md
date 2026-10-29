# Panne DataStore au chargement : nouveaux essais au lieu du kick (v2, sans écran)

Remplace la version précédente de ce fichier.

## Ce que voit le joueur
- Son billboard affiche **« Loading... »** avec les points animés. C'est déjà prévu dans `PointsBillboardClient`, tant que l'attribut `Points` n'existe pas. Il n'y a aucun écran en plus.
- Nouvel essai toutes les 15 s, pendant environ 5 min. Dès que ça marche, sa vraie valeur s'affiche.
- Après environ 5 min sans DataStore : kick, comme avant, en dernier recours.

## Pourquoi c'est sûr pendant l'attente
- **Rien n'est écrit :** les 5 chemins de sauvegarde des points (`secureSave`, autosave, départ du joueur, fermeture du serveur, reload AFK) refusent déjà d'écrire pendant `dataLoading`.
- **Classements :** ils n'écrivent jamais une valeur à 0, et l'index de temps de jeu n'écrit rien tant que la session n'a pas démarré (elle démarre après le chargement).
- **Rien n'est gagné, donc rien n'est perdu :** le compteur passif, les récompenses des autres scripts (daily, streak, temps de jeu, codes, cadeaux, pubs, parrainage, quêtes) et l'achat d'UGC avec des points attendaient déjà la fin du chargement. Les 5 autres gains du script `time` sont maintenant bloqués aussi (correctifs 2 à 6). Une part à points touchée pendant l'attente pourra être retouchée après.
- **Achats Robux :** mis en attente (correctif 8). Roblox les renvoie plus tard, aucun point payé n'est perdu. Ce bug existait déjà pendant les premières secondes de chaque connexion.
- **Le joueur quitte, ou revient sur le même serveur pendant l'attente :** rien n'est sauvegardé, et l'ancienne boucle ne touche pas à sa nouvelle session.

## ServerScriptService ▸ time (7 remplacements)

### 1. Le kick devient de nouveaux essais
Cherche :
```lua
		-- ✅ NEW: si secureLoad a retourné nil, c'est une panne DataStore totale
		-- → kick préventif au lieu d'écraser les points avec 0
		if totalSeconds == nil then
			warn(string.format("🚨 Chargement impossible pour %s → kick préventif (évite perte de points)", player.Name))
			dataLoading[userId] = nil
			tempsJoueurs[userId] = nil  -- éviter que PlayerRemoving sauvegarde {base=0}
			activeConnections[userId] = nil
			if player and player.Parent then
				player:Kick("⚠️ Server data temporarily unavailable. Please reconnect in 30 seconds. Your progress is safe.")
			end
			return
		end
```
Remplace par :
```lua
		-- 🛡️ secureLoad a retourné nil = DataStore en panne (fréquent juste après un reset de serveur).
		--    Avant : kick immédiat. Maintenant : NOUVEL ESSAI toutes les 15 s pendant ~5 min.
		--    • dataLoading RESTE actif → aucune sauvegarde possible (secureSave, autosave, départ,
		--      fermeture du serveur et reload la refusent) et aucun gain de points.
		--    • l'attribut "Points" n'est pas encore posé → le billboard affiche « Loading... ».
		--    Kick seulement en dernier recours, comme avant.
		if totalSeconds == nil then
			warn(string.format("🚨 Chargement impossible pour %s → nouvel essai toutes les 15 s (pas de kick)", player.Name))
			local RETRY_EVERY, MAX_TRIES = 15, 20   -- 20 essais × 15 s ≈ 5 min
			local tries = 0
			while totalSeconds == nil and player.Parent and tries < MAX_TRIES do
				tries += 1
				local waited = 0
				while waited < RETRY_EVERY and player.Parent do
					task.wait(1)
					waited += 1
				end
				if not player.Parent then break end
				totalSeconds = secureLoad(userId)
			end

			if totalSeconds == nil then
				-- ≈ 5 min sans DataStore, ou joueur parti : même nettoyage qu'avant
				warn(string.format("🚨 Chargement toujours impossible pour %s après %d essais", player.Name, tries))
				local current = Players:GetPlayerByUserId(userId)
				if current == nil or current == player then  -- pas une nouvelle session de ce joueur
					dataLoading[userId] = nil
					tempsJoueurs[userId] = nil  -- éviter que PlayerRemoving sauvegarde {base=0}
					activeConnections[userId] = nil
				end
				if player.Parent then
					player:Kick("⚠️ Server data temporarily unavailable. Please reconnect in 30 seconds. Your progress is safe.")
				end
				return
			end
			print(string.format("✅ Données de %s chargées après %d nouvel(s) essai(s)", player.Name, tries))
		end
```

### 2. Récompense de la quête checkpoints
Cherche :
```lua
	-- Vérifier cooldown depuis RAM (chargé depuis DataStore au join)
```
Remplace par :
```lua
	if dataLoading[userId] then return end -- 🛡️ points pas encore chargés : rien ne doit changer (sinon perdu au chargement)

	-- Vérifier cooldown depuis RAM (chargé depuis DataStore au join)
```

### 3. Points de kill
Cherche :
```lua
	if playerKillCount[userId] == nil then
		warn(string.format("⚠️ Kill data pas encore chargée pour %s, skip", player.Name))
		return
	end
```
Remplace par :
```lua
	if playerKillCount[userId] == nil then
		warn(string.format("⚠️ Kill data pas encore chargée pour %s, skip", player.Name))
		return
	end
	if dataLoading[userId] then return end -- 🛡️ points pas encore chargés : rien ne doit changer (sinon perdu au chargement)
```

### 4. Parts qui donnent des points
Cherche :
```lua
	if playerEarnedPointLevels[userId] == nil then return end
```
Remplace par :
```lua
	if playerEarnedPointLevels[userId] == nil or dataLoading[userId] then return end -- 🛡️ points pas encore chargés : rien ne doit changer (sinon perdu au chargement)
```

### 5. Récompense de la quête kills
Cherche :
```lua
	if playerKillCount[userId] == nil or killQuestCooldowns[userId] == nil then
		warn(string.format("⚠️ %s tente de claim KillQuest avant chargement"
```
Remplace par :
```lua
	if playerKillCount[userId] == nil or killQuestCooldowns[userId] == nil or dataLoading[userId] then
		warn(string.format("⚠️ %s tente de claim KillQuest avant chargement"
```

### 6. Récompenses de quêtes
Cherche :
```lua
	-- Attendre que les cooldowns soient chargés (max 5 secondes)
```
Remplace par :
```lua
	if dataLoading[userId] then return end -- 🛡️ points pas encore chargés : rien ne doit changer (sinon perdu au chargement)

	-- Attendre que les cooldowns soient chargés (max 5 secondes)
```

### 7. Gamepass multiplicateur acheté pendant le chargement
Cherche :
```lua
		local newMultiplier = getHighestGamePassMultiplier(player)
		local data = tempsJoueurs[player.UserId]
		if data then
```
Remplace par :
```lua
		local newMultiplier = getHighestGamePassMultiplier(player)
		local data = tempsJoueurs[player.UserId]
		if data and not dataLoading[player.UserId] then -- 🛡️ pendant le chargement le billboard garde « Loading... »
```

## ServerScriptService ▸ Z New Process receip handler time et dono (suite time)
### 8. Achats de points en attente pendant le chargement
Cherche :
```lua
		warn("⚠️ Dépendances _G indisponibles → NotProcessedYet (aucun point perdu)")
		processingPurchases[purchaseId]    = nil
		activePurchases[activePurchaseKey] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
```
Remplace par :
```lua
		warn("⚠️ Dépendances _G indisponibles → NotProcessedYet (aucun point perdu)")
		processingPurchases[purchaseId]    = nil
		activePurchases[activePurchaseKey] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 🛡️ Points du joueur pas encore chargés (chargement normal, ou nouvel essai après une panne
	--    DataStore) : le chargement REMPLACE la table des points, donc des points ajoutés maintenant
	--    seraient perdus alors que l'achat est payé. On ne crédite rien : Roblox renverra l'achat
	--    plus tard (prochain achat ou prochaine connexion) → aucun point payé perdu.
	if d.dataLoading and d.dataLoading[userId] then
		warn(string.format("⏳ Achat %s de %d mis en attente : données pas encore chargées", tostring(productId), userId))
		processingPurchases[purchaseId]    = nil
		activePurchases[activePurchaseKey] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
```
