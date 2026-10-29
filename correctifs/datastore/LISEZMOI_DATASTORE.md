# Données remises à 0 après une lecture DataStore ratée

Analysé sur « final final ready publish » : **70 scripts** qui lisent et écrivent des DataStores, tous relus.
Chaque « Cherche » existe exactement le nombre de fois indiqué dans ton script actuel.

## Déjà sûrs (rien à faire)
- **Points, stage, rebirths, checkpoints, quêtes de kills, avertissements** (`time`) : si la lecture échoue, le joueur est **kické avant toute sauvegarde**. `isAllSecondaryLoaded` et `LossGuard` bloquent aussi toute écriture tant que tout n'est pas chargé. Le temps de jeu ne peut jamais baisser (`UpdateAsync` qui garde le maximum).
- **Les ~20 scripts qui créent `_G.tempsJoueurs[userId] = {base = 0}`** : sans danger. Le vrai chargement remplace toujours ce 0, et rien n'est sauvegardé avant.
- Boosts temporaires et permanents, streak, daily spin, daily tools, armes possédées, codes, cadeaux, QuestHub et toutes les quêtes (Kill500, NoDeath, EggHunt, Feedback, Group, Rebirth, Discord), Jack, Halloween, stock UGC, escrow UGC, dons (total), Top Gifters, bans, anti-cheat, économie, VIP : tout passe par des retries, un drapeau « chargé », ou `UpdateAsync` / `IncrementAsync` qui partent de la valeur en base.

## Petits défauts sans perte pour le joueur (laissés tels quels)
- Cooldown 24 h de la quête kills : si la lecture rate, le joueur peut réclamer un peu plus tôt.
- Pass Starter / Expert Pack, cooldown du Fusion Coil : si la lecture rate, la récompense peut être redonnée.
- Nombre de dons affiché sur le tableau : peut afficher 0 jusqu'au prochain chargement réussi (le total, lui, est sûr).
- Classement et mémoire des bots d'arène : repartent du niveau de départ.

## Les 5 corrections

### 1. ServerScriptService ▸ time
**Bug :** Total de kills à vie (classement Kills) remis à 0 puis écrasé au 1er kill.

**Remplacement 1/2**

Cherche :
```lua
	-- ✅ NOUVEAU : Charger le total lifetime des kills
	local okTotal, storedTotal = pcall(function()
		return totalKillStore:GetAsync(tostring(userId))
	end)
	playerTotalKills[userId] = (okTotal and storedTotal) or 0

	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:SetAttribute("TotalKills", playerTotalKills[userId])
	end

	print(string.format("📊 Total kills chargé: UserID %d → %d kills lifetime", userId, playerTotalKills[userId]))
```
Remplace par :
```lua
	-- ✅ NOUVEAU : Charger le total lifetime des kills
	-- 🛡️ Lecture ratée → on laisse nil : les kills ne s'ajoutent pas et RIEN n'est écrit,
	--    puis on relit toutes les 30 s. Avant : 0 → le 1er kill écrivait 1 par-dessus le vrai total.
	local function loadTotalKills()
		local okTotal, storedTotal
		for attempt = 1, 3 do
			okTotal, storedTotal = pcall(function()
				return totalKillStore:GetAsync(tostring(userId))
			end)
			if okTotal then break end
			task.wait(0.6 * attempt)
		end
		if not okTotal then
			warn(string.format("🚨 Total kills illisible pour %d — compteur en pause, relecture dans 30 s", userId))
			task.delay(30, function()
				if Players:GetPlayerByUserId(userId) and playerTotalKills[userId] == nil then loadTotalKills() end
			end)
			return
		end
		playerTotalKills[userId] = tonumber(storedTotal) or 0

		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:SetAttribute("TotalKills", playerTotalKills[userId])
		end

		print(string.format("📊 Total kills chargé: UserID %d → %d kills lifetime", userId, playerTotalKills[userId]))
	end
	loadTotalKills()
```

**Remplacement 2/2**

Cherche :
```lua
		player.Name, finalPoints, playerKillCount[userId], MAX_KILLS, playerTotalKills[userId]))
```
Remplace par :
```lua
		player.Name, finalPoints, playerKillCount[userId], MAX_KILLS, playerTotalKills[userId] or 0))
```

### 2. ServerScriptService ▸ Playtime reward
**Bug :** Récompenses de temps de jeu déjà prises + temps accumulé effacés.

**Remplacement 1/2**

Cherche :
```lua
	local success, data = pcall(function()
		return PlaytimeStore:GetAsync(key)
	end)

	if success and data and type(data) == "table" then
```
Remplace par :
```lua
	-- 🛡️ 3 essais. Si tout échoue : on ne crée PAS de données vides (elles seraient
	--    sauvegardées et effaceraient les récompenses déjà prises) → relecture dans 30 s.
	local success, data
	for attempt = 1, 3 do
		success, data = pcall(function()
			return PlaytimeStore:GetAsync(key)
		end)
		if success then break end
		task.wait(0.6 * attempt)
	end
	if not success then
		warn(string.format("🚨 PlaytimeRewards illisible pour %d — rien n'est sauvegardé, relecture dans 30 s", userId))
		task.delay(30, function()
			if Players:GetPlayerByUserId(userId) and not playerPlaytimeData[userId] then loadData(userId) end
		end)
		return
	end

	if success and data and type(data) == "table" then
```

**Remplacement 2/2** (présent **2 fois** : remplace les 2)

Cherche :
```lua
(playerPlaytimeData[userId].accumulatedSeconds or 0) / 60))
```
Remplace par :
```lua
((playerPlaytimeData[userId] or {}).accumulatedSeconds or 0) / 60))
```

### 3. ServerScriptService ▸ AnimStudioServer
**Bug :** Animations d'armes publiées effacées à la prochaine publication admin.

Cherche :
```lua
	else
		LIVE.data = {}
		LIVE.meta = {}
		if not ok then warn("[AnimStudio] lecture des animations publiées impossible :", res) end
	end
	indexLiveSounds()
	LIVE.ready = true
```
Remplace par :
```lua
	elseif ok then
		LIVE.data = {}
		LIVE.meta = {}
	else
		-- 🛡️ Lecture ratée : PAS de liste vide (la prochaine publication effacerait toutes les
		--    autres armes). LIVE.ready reste false (publication refusée) → relecture dans 30 s.
		warn("[AnimStudio] lecture des animations publiées impossible, relecture dans 30 s :", res)
		task.delay(30, loadLive)
		return
	end
	indexLiveSounds()
	LIVE.ready = true
```

### 4. ServerScriptService ▸ Liking ugc system
**Bug :** Likes globaux d'un UGC remis à 0 par la sauvegarde des 10 min.

**Remplacement 1/3**

Cherche :
```lua
local globalLikeCounts   = {}
```
Remplace par :
```lua
local globalLikeCounts   = {}
local likesUntrusted     = {}  -- 🛡️ [assetKey] = true : vrai compte inconnu → jamais écrit en base
```

**Remplacement 2/3**

Cherche :
```lua
		if ok and type(data) == "table" then
			for k, v in pairs(data) do
				if type(v) == "number" and v >= 0 and globalLikeCounts[k] == nil then
```
Remplace par :
```lua
		if not ok then
			-- 🛡️ DataStore illisible : les UGC absents de la mémoire ont un compte inconnu
			for _, ugc in ipairs(UGC_CONFIG.Items) do
				local k = tostring(ugc.AssetId)
				if globalLikeCounts[k] == nil then likesUntrusted[k] = true end
			end
			warn("[LIKES] DataStore global illisible : les compteurs inconnus ne seront pas réécrits")
		end
		if ok and type(data) == "table" then
			for k, v in pairs(data) do
				if type(v) == "number" and v >= 0 and globalLikeCounts[k] == nil then
```

**Remplacement 3/3**

Cherche :
```lua
		if ok and type(value) == "number" then
			snapshot[k] = value
		else
			snapshot[k] = globalLikeCounts[k] or 0
		end
	end

	local writeOk = pcall(function()
		globalLikesStore:SetAsync(GLOBAL_KEY, snapshot)
	end)
```
Remplace par :
```lua
		if likesUntrusted[k] then
			-- 🛡️ compte réel inconnu (lecture ratée au démarrage) : on n'écrit rien pour cet UGC
		elseif ok and type(value) == "number" then
			snapshot[k] = value
		else
			snapshot[k] = globalLikeCounts[k] or 0
		end
	end

	-- 🛡️ UpdateAsync : seuls les UGC connus sont remplacés, les autres gardent leur valeur en base
	local writeOk = pcall(function()
		globalLikesStore:UpdateAsync(GLOBAL_KEY, function(old)
			old = (type(old) == "table") and old or {}
			for k, v in pairs(snapshot) do old[k] = v end
			return old
		end)
	end)
```

### 5. ServerScriptService ▸ AdminCommands_Extended time
**Bug :** Registre des joueurs avertis réécrit avec 1 seul joueur.

**Remplacement 1/2**

Cherche :
```lua
do
	local success, data = pcall(function()
		return warningsRegistryStore:GetAsync("all_warned_players")
	end)
	if success and data and type(data) == "table" then
		warningsRegistryArray = data
		for _, userId in ipairs(data) do
			warningsRegistrySet[userId] = true
		end
		print(string.format("📋 Registre chargé: %d joueurs", #warningsRegistryArray))
	else
		print("📋 Registre vide ou introuvable")
	end
end
```
Remplace par :
```lua
-- 🛡️ Lecture ratée → la liste n'est PAS réécrite tant qu'elle n'a pas été lue (relecture 30 s).
--    Avant : liste vide → le prochain avertissement réécrivait le registre avec 1 seul joueur.
local registryLoaded = false
local function loadRegistry()
	local success, data = pcall(function()
		return warningsRegistryStore:GetAsync("all_warned_players")
	end)
	if not success then
		warn("📋 Registre illisible, nouvel essai dans 30 s")
		task.delay(30, loadRegistry)
		return
	end
	if data and type(data) == "table" then
		for _, userId in ipairs(data) do
			if not warningsRegistrySet[userId] then
				warningsRegistrySet[userId] = true
				table.insert(warningsRegistryArray, userId)
			end
		end
		print(string.format("📋 Registre chargé: %d joueurs", #warningsRegistryArray))
	else
		print("📋 Registre vide ou introuvable")
	end
	registryLoaded = true
end
loadRegistry()
```

**Remplacement 2/2**

Cherche :
```lua
		task.wait(3)
		local ok, err = pcall(function()
			warningsRegistryStore:SetAsync("all_warned_players", warningsRegistryArray)
```
Remplace par :
```lua
		task.wait(3)
		while not registryLoaded do task.wait(5) end -- 🛡️ jamais d'écriture avant la lecture
		local ok, err = pcall(function()
			warningsRegistryStore:SetAsync("all_warned_players", warningsRegistryArray)
```

## Test
En Play, rien ne change. Le comportement corrigé n'apparaît que si Roblox refuse une lecture : un warn 🚨 s'affiche dans l'Output du serveur, et rien n'est écrasé.