-- ============================================================
-- PlaytimeRewards - ServerScript
-- À placer dans ServerScriptService
--
-- 🆕 v3 : plus de « 1 claim par seconde ». On peut récupérer toutes les
--   récompenses prêtes d'affilée. Sécurité gardée :
--   • la récompense est marquée « prise » AVANT de donner les points, sans
--     aucune attente entre la vérification et la marque → impossible de la
--     prendre deux fois, même en spammant le remote ;
--   • anti-flood : 12 demandes d'un coup max, puis 2 par seconde ;
--   • le pays du joueur (fuseau horaire) est lu UNE fois par session
--     au lieu de 2 appels web à chaque claim → claims instantanés.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- ⏳ ATTENDRE QUE LE SCRIPT PRINCIPAL SOIT CHARGÉ
local maxWait = 100
local waited = 0
while (not _G.tempsJoueurs or not _G.SmartAntiCheat) and waited < maxWait do
	task.wait(0.1)
	waited = waited + 1
end

if not _G.tempsJoueurs or not _G.SmartAntiCheat then
	error("❌ ERREUR CRITIQUE: Script principal non chargé!")
end

local SmartAntiCheat = _G.SmartAntiCheat
local AntiExploit = _G.AntiExploit or {
	CheckRemoteCall = function() return true end,
	HandleSuspiciousActivity = function() end,
}

-- ============================================================
-- ✅ CONFIGURATION
-- ============================================================

local PLAYTIME_REWARDS = {
	{id = "pt_1",  minutes = 1,  points = 500},
	{id = "pt_2",  minutes = 5,  points = 500},
	{id = "pt_3",  minutes = 10, points = 500},
	{id = "pt_4",  minutes = 15, points = 1000},
	{id = "pt_5",  minutes = 20, points = 500},
	{id = "pt_6",  minutes = 30, points = 500},
	{id = "pt_7",  minutes = 40, points = 500},
	{id = "pt_8",  minutes = 50, points = 500},
	{id = "pt_9",  minutes = 60, points = 1000},
}

-- 🆕 SUPPRIMÉ : RESET_COOLDOWN = 24 * 60 * 60
-- Le reset se fait maintenant à minuit (comme le Daily)

-- ============================================================
-- DATASTORES & TABLES
-- ============================================================

local PlaytimeStore = DataStoreService:GetDataStore("PlaytimeRewards_v2") -- 🆕 v2 pour éviter conflits de données

local playerSessionStart = {}
local playerPlaytimeData = {}
local claimCooldowns = {}

-- ============================================================
-- 🆕 FONCTIONS MINUIT (copiées du script Daily)
-- ============================================================

-- 🆕 Décalage horaire du joueur : lu une seule fois (même règle qu'avant), puis gardé
local tzCache = {}
local function getTimezoneOffset(player)
	local cached = tzCache[player.UserId]
	if cached then return cached end
	local LocalizationService = game:GetService("LocalizationService")
	local success, result = pcall(function()
		return LocalizationService:GetCountryRegionForPlayerAsync(player)
	end)
	local timezoneOffset = 0
	if success and result then
		if result == "US" or result == "CA" or result == "MX" then
			timezoneOffset = -5 * 3600
		elseif result == "GB" or result == "FR" or result == "DE" or result == "ES" or result == "IT" then
			timezoneOffset = 1 * 3600
		elseif result == "JP" or result == "KR" then
			timezoneOffset = 9 * 3600
		elseif result == "AU" then
			timezoneOffset = 10 * 3600
		elseif result == "BR" then
			timezoneOffset = -3 * 3600
		end
		tzCache[player.UserId] = timezoneOffset   -- en cas d'échec : pas gardé, on réessaie
	end
	return timezoneOffset
end

local function getMidnightTodayForPlayer(player)
	local currentTime = os.time()
	local timezoneOffset = getTimezoneOffset(player)

	local localTime = currentTime + timezoneOffset
	local localDateTable = os.date("!*t", localTime)
	localDateTable.hour = 0
	localDateTable.min = 0
	localDateTable.sec = 0

	return os.time(localDateTable) - timezoneOffset
end

local function getNextMidnightForPlayer(player)
	return getMidnightTodayForPlayer(player) + 86400
end

local function getCurrentDateForPlayer(player)
	local timezoneOffset = getTimezoneOffset(player)

	local localTime = os.time() + timezoneOffset
	return os.date("!%Y-%m-%d", localTime)
end

-- ============================================================
-- REMOTE EVENTS
-- ============================================================

local function getOrCreateRemote(name, className)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className or "RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local playtimeClaimEvent   = getOrCreateRemote("PlaytimeRewardClaim")
local playtimeUpdateEvent  = getOrCreateRemote("PlaytimeRewardUpdate")
local playtimeGetDataEvent = getOrCreateRemote("PlaytimeRewardGetData")

-- ============================================================
-- CHARGEMENT / SAUVEGARDE
-- ============================================================

local function loadData(userId)
	local key = "pt2_" .. userId -- 🆕 Nouvelle clé pour v2
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
		if type(data.claimedIds) ~= "table" then data.claimedIds = {} end
		if type(data.accumulatedSeconds) ~= "number" then data.accumulatedSeconds = 0 end
		-- 🆕 Migration : si ancienne donnée avec allClaimedAt (timestamp), on ignore
		if data.allClaimedAt and type(data.allClaimedAt) == "number" then
			data.allClaimedAt = nil
		end
		-- 🆕 allClaimedDate est maintenant une string "YYYY-MM-DD" ou nil
		playerPlaytimeData[userId] = data
		print(string.format("✅ PlaytimeRewards chargé: UserID %d | %d réclamés | accumulé: %.1fmin | allClaimedDate=%s",
			userId, #data.claimedIds, data.accumulatedSeconds / 60, tostring(data.allClaimedDate)))
	else
		playerPlaytimeData[userId] = {claimedIds = {}, allClaimedDate = nil, accumulatedSeconds = 0}
		print(string.format("ℹ️ PlaytimeRewards nouveau joueur: UserID %d", userId))
	end
end

local function saveData(userId)
	task.spawn(function()
		local key = "pt2_" .. userId -- 🆕 Nouvelle clé pour v2
		local data = playerPlaytimeData[userId]
		if not data then return end

		local success, err = pcall(function()
			PlaytimeStore:SetAsync(key, data)
		end)

		if not success then
			warn(string.format("❌ Erreur sauvegarde PlaytimeRewards %d: %s", userId, tostring(err)))
		end
	end)
end

-- ============================================================
-- LOGIQUE PRINCIPALE
-- ============================================================

local function getSessionSeconds(userId)
	local start = playerSessionStart[userId]
	local sessionElapsed = start and (os.time() - start) or 0
	local data = playerPlaytimeData[userId]
	local accumulated = (data and data.accumulatedSeconds) or 0
	return accumulated + sessionElapsed
end

-- 🆕 checkAndApplyReset utilise maintenant la date courante du joueur (minuit)
local function checkAndApplyReset(player, userId)
	local data = playerPlaytimeData[userId]
	if not data then return end

	if data.allClaimedDate then
		-- Récupérer la date actuelle du joueur
		local currentDate = getCurrentDateForPlayer(player)
		-- Si on est un nouveau jour → reset
		if currentDate ~= data.allClaimedDate then
			data.claimedIds = {}
			data.allClaimedDate = nil
			data.accumulatedSeconds = 0
			saveData(userId)
			print(string.format("🔄 PlaytimeRewards RESET pour UserID %d (nouveau jour: %s → %s)",
				userId, data.allClaimedDate or "?", currentDate))
		end
	end
end

-- 🆕 Version sans player (pour BindToClose et contextes sans joueur connecté)
local function checkAndApplyResetNoPlayer(userId)
	local data = playerPlaytimeData[userId]
	if not data then return end
	-- Sans joueur on ne peut pas détecter le fuseau horaire, on ne reset pas
	-- Le reset se fera au prochain appel avec player
end

local function buildStateForClient(player, userId)
	local data = playerPlaytimeData[userId]
	if not data then return {} end

	-- 🆕 Passer le player pour le fuseau horaire
	checkAndApplyReset(player, userId)

	local sessionSeconds = getSessionSeconds(userId)
	local now = os.time()

	-- 🆕 Calcul du temps avant minuit (reset)
	local resetTimeRemaining = 0
	local allClaimed = false

	if data.allClaimedDate then
		local currentDate = getCurrentDateForPlayer(player)
		if currentDate == data.allClaimedDate then
			-- Même jour : on calcule le temps jusqu'à minuit
			local nextMidnight = getNextMidnightForPlayer(player)
			resetTimeRemaining = math.max(0, nextMidnight - now)
			allClaimed = resetTimeRemaining > 0
		end
		-- Si date différente : allClaimed reste false (reset au prochain checkAndApplyReset)
	end

	local rewards = {}
	for _, reward in ipairs(PLAYTIME_REWARDS) do
		local isClaimed = false
		for _, claimedId in ipairs(data.claimedIds) do
			if claimedId == reward.id then
				isClaimed = true
				break
			end
		end

		local sessionMinutes = sessionSeconds / 60
		local minutesLeft = math.max(0, reward.minutes - sessionMinutes)
		local canClaim = (not isClaimed) and (not allClaimed) and (sessionMinutes >= reward.minutes)

		table.insert(rewards, {
			id             = reward.id,
			minutes        = reward.minutes,
			points         = reward.points,
			isClaimed      = isClaimed,
			canClaim       = canClaim,
			minutesLeft    = minutesLeft,
			sessionMinutes = math.floor(sessionMinutes),
		})
	end

	return {
		rewards            = rewards,
		resetTimeRemaining = resetTimeRemaining,
		allClaimed         = allClaimed,
		serverTime         = now,
		-- 🆕 Envoyer la prochaine minuit pour que le client puisse afficher un countdown précis
		nextMidnight       = allClaimed and getNextMidnightForPlayer(player) or nil,
	}
end

-- ============================================================
-- ENVOI UI
-- ============================================================

local function sendUpdateToPlayer(player)
	if not player or not player.Parent then return end
	local state = buildStateForClient(player, player.UserId) -- 🆕 passer player
	pcall(function()
		playtimeUpdateEvent:FireClient(player, state)
	end)
end

-- ============================================================
-- CLAIM SÉCURISÉ
-- ============================================================

playtimeClaimEvent.OnServerEvent:Connect(function(player, rewardId)
	if not player or not player.Parent then return end

	local userId = player.UserId
	local now = os.time()
	
	-- ✅ FIX #7
	if _G.recentReloads and _G.recentReloads[userId] then return end
	if _G.dataLoading and _G.dataLoading[userId] then return end

	-- 🛡️ anti-flood (seau de jetons) : 12 demandes d'un coup, puis 2 par seconde.
	--    Il y a 9 récompenses : un joueur normal ne sera jamais bloqué.
	do
		local clk = os.clock()
		local b = claimCooldowns[userId]
		if not b then b = { tokens = 12, at = clk } ; claimCooldowns[userId] = b end
		b.tokens = math.min(12, b.tokens + (clk - b.at) * 2)
		b.at = clk
		if b.tokens < 1 then return end
		b.tokens -= 1
	end

	local reward = nil
	for _, r in ipairs(PLAYTIME_REWARDS) do
		if r.id == rewardId then
			reward = r
			break
		end
	end

	if not reward then
		warn(string.format("⚠️ PlaytimeReward: ID inconnu '%s' par %s", tostring(rewardId), player.Name))
		AntiExploit.HandleSuspiciousActivity(player, "PLAYTIME_INVALID_ID",
			string.format("ID inconnu: %s", tostring(rewardId)))
		return
	end

	local data = playerPlaytimeData[userId]
	if not data then
		warn(string.format("⚠️ PlaytimeReward: données non chargées pour %s", player.Name))
		return
	end

	checkAndApplyReset(player, userId)

	if data.allClaimedDate then
		local currentDate = getCurrentDateForPlayer(player)
		if currentDate == data.allClaimedDate then
			local nextMidnight = getNextMidnightForPlayer(player)
			local resetLeft = math.max(0, nextMidnight - now)
			warn(string.format("⚠️ PlaytimeReward: %s tente de claim pendant le cooldown reset (%.1fh restantes)",
				player.Name, resetLeft / 3600))
			sendUpdateToPlayer(player)
			return
		end
	end

	for _, claimedId in ipairs(data.claimedIds) do
		if claimedId == reward.id then
			sendUpdateToPlayer(player)
			return
		end
	end
	
	local sessionSeconds = getSessionSeconds(userId)
	local sessionMinutes = sessionSeconds / 60

	if sessionMinutes < reward.minutes then
		warn(string.format("⚠️ PlaytimeReward: %s tente de claim '%s' sans assez de temps (%.2f/%.0f min)",
			player.Name, reward.id, sessionMinutes, reward.minutes))
		sendUpdateToPlayer(player)
		return
	end

	-- 🔒 marquée « prise » tout de suite (aucune attente depuis la vérification juste au-dessus)
	table.insert(data.claimedIds, reward.id)

	if type(_G.tempsJoueurs[userId]) ~= "table" then
		_G.tempsJoueurs[userId] = {base = 0, future = 0, lastSaved = 0}
	end

	SmartAntiCheat.ExpectGain(userId, reward.points, "PlaytimeReward_" .. reward.id)
	_G.tempsJoueurs[userId].future = _G.tempsJoueurs[userId].future + reward.points

	local leaderstats = player:FindFirstChild("leaderstats")
	local pointsStat = leaderstats and leaderstats:FindFirstChild("Points")
	if pointsStat then
		local totalPoints = _G.tempsJoueurs[userId].base + _G.tempsJoueurs[userId].future
		if _G.applyAllBonuses and _G.calculatePoints then
			pointsStat.Value = _G.applyAllBonuses(_G.calculatePoints(totalPoints), player)
		else
			pointsStat.Value = totalPoints
		end
		player:SetAttribute("Points", pointsStat.Value)
	end

	task.spawn(function()
		SmartAntiCheat.RecordGain(player, reward.points, "PlaytimeReward_" .. reward.id)
	end)

	if _G.secureSave then
		task.spawn(function()
			local totalPoints = _G.tempsJoueurs[userId].base + _G.tempsJoueurs[userId].future
			_G.secureSave(userId, totalPoints)
		end)
	end

	local buyGamePassEvent = ReplicatedStorage:FindFirstChild("applepay")
	if buyGamePassEvent then
		pcall(function() buyGamePassEvent:FireClient(player) end)
	end

	if #data.claimedIds >= #PLAYTIME_REWARDS then
		data.allClaimedDate = getCurrentDateForPlayer(player)
		local nextMidnight = getNextMidnightForPlayer(player)
		print(string.format("🏁 PlaytimeRewards: %s a tout réclamé → reset à minuit (dans %.1fh)",
			player.Name, (nextMidnight - now) / 3600))
	end

	saveData(userId)
	sendUpdateToPlayer(player)

	print(string.format("✅ PLAYTIME REWARD: %s a réclamé '%s' → +%d pts (session: %.1f min)",
		player.Name, reward.id, reward.points, sessionMinutes))
end)

-- Demande de données depuis le client
playtimeGetDataEvent.OnServerEvent:Connect(function(player)
	local userId = player.UserId
	local waitedLocal = 0
	while not playerPlaytimeData[userId] and waitedLocal < 100 do
		task.wait(0.1)
		waitedLocal = waitedLocal + 1
	end
	if player and player.Parent then
		sendUpdateToPlayer(player)
	end
end)

-- ============================================================
-- JOUEUR REJOINT / QUITTE
-- ============================================================

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local userId = player.UserId

		local waitedForData = 0
		while waitedForData < 150 do
			if _G.tempsJoueurs and type(_G.tempsJoueurs[userId]) == "table" then
				break
			end
			task.wait(0.1)
			waitedForData = waitedForData + 1
		end

		if not _G.tempsJoueurs or type(_G.tempsJoueurs[userId]) ~= "table" then
			warn(string.format("⚠️ PlaytimeRewards: Données principales jamais chargées pour %s, démarrage quand même", player.Name))
			if _G.tempsJoueurs then
				_G.tempsJoueurs[userId] = {base = 0, future = 0, lastSaved = 0}
			end
		end

		if not player.Parent then return end

		loadData(userId)

		-- 🆕 Passer player à checkAndApplyReset
		checkAndApplyReset(player, userId)

		playerSessionStart[userId] = os.time()
		print(string.format("⏱️ PlaytimeRewards: Session démarrée pour %s | temps accumulé: %.1fmin",
			player.Name, ((playerPlaytimeData[userId] or {}).accumulatedSeconds or 0) / 60))

		task.wait(1)
		if player.Parent then
			sendUpdateToPlayer(player)
		end
		task.wait(2)
		if player.Parent then
			sendUpdateToPlayer(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId

	if playerPlaytimeData[userId] and playerSessionStart[userId] then
		local sessionElapsed = os.time() - playerSessionStart[userId]
		playerPlaytimeData[userId].accumulatedSeconds =
			(playerPlaytimeData[userId].accumulatedSeconds or 0) + sessionElapsed
		print(string.format("💾 PlaytimeRewards: %s quitte | temps total sauvegardé: %.1fmin",
			player.Name, playerPlaytimeData[userId].accumulatedSeconds / 60))
	end

	if playerPlaytimeData[userId] then
		saveData(userId)
	end

	playerSessionStart[userId] = nil
	playerPlaytimeData[userId] = nil
	claimCooldowns[userId] = nil
	tzCache[userId] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId
		if playerPlaytimeData[userId] then
			if playerSessionStart[userId] then
				local sessionElapsed = os.time() - playerSessionStart[userId]
				playerPlaytimeData[userId].accumulatedSeconds =
					(playerPlaytimeData[userId].accumulatedSeconds or 0) + sessionElapsed
			end
			pcall(function()
				PlaytimeStore:SetAsync("pt2_" .. userId, playerPlaytimeData[userId]) -- 🆕 clé v2
			end)
		end
	end
	task.wait(2)
end)

-- ============================================================
-- MISE À JOUR PÉRIODIQUE (toutes les 30s)
-- ============================================================

task.spawn(function()
	while true do
		task.wait(30)
		for _, player in ipairs(Players:GetPlayers()) do
			if player and player.Parent then
				sendUpdateToPlayer(player)
			end
		end
	end
end)

-- ============================================================
-- COMMANDES DEBUG
-- ============================================================

_G.DebugPlaytime = function(userId)
	local player = Players:GetPlayerByUserId(userId)
	if not player then print("❌ Joueur non trouvé") return end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("⏱️ DEBUG PLAYTIME:", player.Name)

	local sessionSeconds = getSessionSeconds(userId)
	print(string.format("   Session totale: %.1f min", sessionSeconds / 60))

	local data = playerPlaytimeData[userId]
	if data then
		print(string.format("   Accumulé sauvegardé: %.1f min", (data.accumulatedSeconds or 0) / 60))
		print(string.format("   Réclamés: %d/%d", #data.claimedIds, #PLAYTIME_REWARDS))
		-- 🆕 Afficher la date de claim complet et le temps jusqu'à minuit
		if data.allClaimedDate then
			local currentDate = getCurrentDateForPlayer(player)
			if currentDate == data.allClaimedDate then
				local nextMidnight = getNextMidnightForPlayer(player)
				local resetLeft = math.max(0, nextMidnight - os.time())
				print(string.format("   Reset à minuit dans: %.1fh (allClaimedDate=%s)", resetLeft / 3600, data.allClaimedDate))
			else
				print(string.format("   Reset disponible (allClaimedDate=%s, aujourd'hui=%s)", data.allClaimedDate, currentDate))
			end
		end
	end

	local state = buildStateForClient(player, userId)
	for _, r in ipairs(state.rewards) do
		local status = r.isClaimed and "✅ Réclamé"
			or r.canClaim and "🟢 CLAIMABLE"
			or string.format("⏳ %.1f min restantes", r.minutesLeft)
		print(string.format("   %dmin | %d pts | %s", r.minutes, r.points, status))
	end
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
end

_G.ResetPlaytime = function(userId)
	local player = Players:GetPlayerByUserId(userId)
	if not player then print("❌ Joueur non trouvé") return end

	playerPlaytimeData[userId] = {claimedIds = {}, allClaimedDate = nil, accumulatedSeconds = 0}
	playerSessionStart[userId] = os.time()
	saveData(userId)
	sendUpdateToPlayer(player)
	print(string.format("✅ PlaytimeRewards réinitialisé pour %s", player.Name))
end

_G.SimulatePlaytime = function(userId, minutes)
	if playerSessionStart[userId] then
		local data = playerPlaytimeData[userId]
		if data then
			data.accumulatedSeconds = (minutes * 60)
			playerSessionStart[userId] = os.time()
			local player = Players:GetPlayerByUserId(userId)
			if player then sendUpdateToPlayer(player) end
			print(string.format("✅ Session simulée à %d min pour UserID %d", minutes, userId))
		end
	else
		print("❌ Joueur non trouvé ou session pas démarrée")
	end
end

-- ============================================================
-- 🔧 FIX CRITIQUE : Gérer les joueurs déjà connectés au chargement du script
-- ============================================================
task.spawn(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if not playerSessionStart[player.UserId] then
			task.spawn(function()
				local userId = player.UserId

				local waitedForData = 0
				while waitedForData < 150 do
					if _G.tempsJoueurs and type(_G.tempsJoueurs[userId]) == "table" then
						break
					end
					task.wait(0.1)
					waitedForData = waitedForData + 1
				end

				if not player.Parent then return end

				loadData(userId)
				-- 🆕 Passer player
				checkAndApplyReset(player, userId)

				playerSessionStart[userId] = os.time()
				print(string.format("⏱️ PlaytimeRewards: Session démarrée (tardif) pour %s | accumulé: %.1fmin",
					player.Name, ((playerPlaytimeData[userId] or {}).accumulatedSeconds or 0) / 60))

				task.wait(0.5)
				if player.Parent then
					sendUpdateToPlayer(player)
				end
			end)
		end
	end
end)

print("✅ PLAYTIME REWARDS SERVER CHARGÉ")
print(string.format("📋 %d paliers | Reset à minuit (fuseau horaire du joueur)", #PLAYTIME_REWARDS))
print("📋 Commandes: _G.DebugPlaytime(id) | _G.ResetPlaytime(id) | _G.SimulatePlaytime(id, min)")