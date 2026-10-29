# Vérification des scripts time + ProcessReceipt envoyés

Les 8 correctifs précédents sont bien recopiés, et les correctifs DataStore aussi.
Ci-dessous : les points complémentaires trouvés en relisant les deux scripts entiers.

## À faire aussi dans Studio
- **Désactive `ServerScriptService ▸ DevProductsHandler`** (décoche Enabled). C'est un ancien gestionnaire d'achats. Il attend `_G.ProcessProductPurchase`, qui n'existe nulle part : il ne s'active donc jamais. Mais si un jour quelque chose crée ce nom, il remplacerait ton `ProcessReceipt` et volerait tous les achats.
- `10 died = offer 2500 points` : son `ProcessReceipt` est en commentaire. C'est OK.

## ServerScriptService ▸ Z New Process receip handler time et dono (suite time)

**1/3** Cherche :
```lua
	if d.dataLoading and d.dataLoading[userId] then
		warn(string.format("⏳ Achat %s de %d mis en attente : données pas encore chargées", tostring(productId), userId))
```
Remplace par :
```lua
	--    Même chose si sa table de points n'existe pas (reload AFK en cours) : on ne la recrée pas.
	if (d.dataLoading and d.dataLoading[userId]) or type(d.tempsJoueurs[userId]) ~= "table" then
		warn(string.format("⏳ Achat %s de %d mis en attente : données pas encore chargées", tostring(productId), userId))
```

**2/3** Cherche :
```lua
	if productId == REBIRTH_RESET_PRODUCT_ID then
		local player = Players:GetPlayerByUserId(userId)
		if _G.ResetRebirthCooldown then
			_G.ResetRebirthCooldown(userId)
		else
			print("[RESET COOLDOWN] Acheté par " .. (player and player.Name or tostring(userId)))
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
```
Remplace par :
```lua
	if productId == REBIRTH_RESET_PRODUCT_ID then
		-- 🛡️ Accordé SEULEMENT si le reset est vraiment écrit. Avant : accordé même si le
		--    script rebirth n'était pas prêt ou si le DataStore échouait → payé pour rien.
		if type(_G.ResetRebirthCooldown) ~= "function" then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if _G.ResetRebirthCooldown(userId) == false then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
```

**3/3** Cherche :
```lua
	if productId == 3606598373 then
		if _G.FlameRecover then
			_G.FlameRecover(userId)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
```
Remplace par :
```lua
	if productId == 3606598373 then
		-- 🛡️ Même principe : si la flamme n'a pas pu être lue (DataStore), Roblox réessaiera.
		if type(_G.FlameRecover) ~= "function" then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if _G.FlameRecover(userId) == false then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
```

## ServerScriptService ▸ time

**1/3** Cherche :
```lua
		-- ✅ NOUVEAU : Attendre que secureLoad ait fini (il peut déjà avoir setté playerRebirthCount)
		local waited = 0
		while dataLoading[userId] and waited < 100 do
			task.wait(0.1)
			waited = waited + 1
		end
```
Remplace par :
```lua
		-- ✅ NOUVEAU : Attendre que secureLoad ait fini (il peut déjà avoir setté playerRebirthCount)
		-- 🛡️ sans limite de 10 s : si le chargement prend plus longtemps (nouveaux essais après
		--    une panne DataStore), on attend le VRAI nombre de rebirths au lieu d'afficher 0.
		local waited = 0
		while dataLoading[userId] and player.Parent do
			task.wait(0.1)
			waited = waited + 1
		end
		if not player.Parent then return end
```

**2/3** Cherche :
```lua
		while dataLoading[userId] and waitedForLoad < 100 do
			task.wait(0.1)
			waitedForLoad = waitedForLoad + 1
		end
```
Remplace par :
```lua
		-- 🛡️ sans limite de 10 s : même raison (l'ordre unifié → stores dédiés doit être respecté)
		while dataLoading[userId] and player.Parent do
			task.wait(0.1)
			waitedForLoad = waitedForLoad + 1
		end
		if not player.Parent then return end
```

**3/3** Cherche :
```lua
	rebirthAuthorized[userId] = nil   -- usage unique
```
Remplace par :
```lua
	if dataLoading[userId] then return end -- 🛡️ points pas encore chargés : l'autorisation reste valable

	rebirthAuthorized[userId] = nil   -- usage unique
```

## ServerScriptService ▸ Streak system (+rewards)

**1/1** Cherche :
```lua
	if not rec then
		if player then player:SetAttribute("FlameRecoverResult", "not_eligible") end
		return
	end

	if rec.recoverDeadline
```
Remplace par :
```lua
	if not rec then
		-- 🛡️ flamme illisible (DataStore) : on renvoie false → l'achat n'est PAS consommé
		if player then player:SetAttribute("FlameRecoverResult", "not_eligible") end
		return false
	end

	if rec.recoverDeadline
```

## ServerScriptService ▸ rebirth server system

**1/1** Cherche :
```lua
local function resetRebirthCooldown(userId)
	pcall(function()
		rebirthCountDailyStore:SetAsync("DailyRebirthCount_" .. userId,
			{count = 0, resetAt = 0, lastRebirthAt = 0})
	end)
```
Remplace par :
```lua
local function resetRebirthCooldown(userId)
	-- 🛡️ renvoie false si l'écriture échoue → l'achat n'est PAS consommé (Roblox réessaiera)
	local ok = pcall(function()
		rebirthCountDailyStore:SetAsync("DailyRebirthCount_" .. userId,
			{count = 0, resetAt = 0, lastRebirthAt = 0})
	end)
	if not ok then return false end
```
