# Panne DataStore au chargement : nouveaux essais au lieu du kick

## Pourquoi c'est sûr
Pendant les nouveaux essais, `dataLoading` reste actif. Les **5 chemins de sauvegarde des points** refusent déjà d'écrire dans ce cas : `secureSave`, l'autosave, le départ du joueur, la fermeture du serveur et le reload AFK. Les vrais points ne peuvent donc pas être écrasés. Le compteur passif est en pause, et les récompenses gratuites (daily, streak, temps de jeu, codes, quêtes, cadeaux, pubs, parrainage) attendent déjà la fin du chargement.

**Seule exception, corrigée ici :** les achats de points en Robux. Ils créditaient même pendant le chargement, et le chargement remplaçait ensuite ces points. Ce bug existait déjà dans les premières secondes de chaque connexion.

## 1. ServerScriptService ▸ time
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
		--    Avant : kick immédiat. Maintenant : NOUVEL ESSAI toutes les 15 s pendant ~5 min, avec un
		--    message à l'écran. dataLoading RESTE actif pendant ce temps → aucune sauvegarde n'est
		--    possible (secureSave, départ du joueur, fermeture du serveur et reload la refusent déjà),
		--    donc rien ne peut écraser ses vrais points. Kick seulement en dernier recours.
		if totalSeconds == nil then
			warn(string.format("🚨 Chargement impossible pour %s → nouvel essai toutes les 15 s (pas de kick)", player.Name))
			local RETRY_EVERY, MAX_TRIES = 15, 20   -- 20 essais × 15 s ≈ 5 min
			local notice = Instance.new("ScreenGui")
			notice.Name = "DataRetryNotice"
			notice.ResetOnSpawn = false
			notice.DisplayOrder = 1000
			local label = Instance.new("TextLabel")
			label.AnchorPoint = Vector2.new(0.5, 0)
			label.Position = UDim2.new(0.5, 0, 0, 70)
			label.Size = UDim2.new(0.7, 0, 0, 40)
			label.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
			label.BackgroundTransparency = 0.2
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.Text = "⏳ Loading your data… your progress is safe"
			label.Parent = notice
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 10)
			corner.Parent = label
			local playerGui = player:FindFirstChildOfClass("PlayerGui")
			if playerGui then notice.Parent = playerGui end

			local tries = 0
			while totalSeconds == nil and player.Parent and tries < MAX_TRIES do
				tries += 1
				for s = RETRY_EVERY, 1, -1 do
					if not player.Parent then break end
					label.Text = string.format("⏳ Loading your data… retrying in %ds (your progress is safe)", s)
					task.wait(1)
				end
				if not player.Parent then break end
				label.Text = "⏳ Loading your data…"
				totalSeconds = secureLoad(userId)
			end
			notice:Destroy()

			if totalSeconds == nil then
				-- ≈ 5 min sans DataStore, ou joueur parti : même nettoyage qu'avant
				warn(string.format("🚨 Chargement toujours impossible pour %s après %d essais", player.Name, tries))
				local current = Players:GetPlayerByUserId(userId)
				if current == nil or current == player then  -- pas de nouvelle session de ce joueur
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

## 2. ServerScriptService ▸ Z New Process receip handler time et dono (suite time)
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

## Ce que voit le joueur
- Un bandeau en haut de l'écran : « ⏳ Loading your data… retrying in 15s (your progress is safe) ».
- Ses points affichent 0 en attendant, puis sa vraie valeur dès que la lecture réussit. Rien n'est sauvegardé entre-temps.
- Après ≈ 5 min sans DataStore : kick, comme avant (dernier recours).
- Un achat de points pendant l'attente n'est pas perdu : Roblox le renvoie au prochain achat ou à la prochaine connexion.