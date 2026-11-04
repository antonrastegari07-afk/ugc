-- ServerScript SÉCURISÉ à placer dans ServerScriptService
-- VERSION CORRIGÉE v4 (7 JOURS) :
--   • Passage de 5 à 7 jours
--   • Rewards : 1=SpeedCoil, 2=5k pts, 3=Gravity Coil, 4=FusionCoil, 5=5k pts, 6=SpeedCoil, 7=Jetpack
--   • Fix Bug #1 : DataStore failure ne reset plus à day 1
--   • Fix Bug #2 : Outils alignés (day 3 = Gravity Coil, day 4 = FusionCoil)
--   • Fix Bug #3 : Timer 10 min appliqué dès PlayerAdded (plus bypass possible)
--   • Fix Bug #4 : firstJoinAt persisté dans DataStore (timer survit aux rejoins)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
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
	CheckQuestCooldown = function() return true end,
}
-- DataStore
local DailyRewardsStore = DataStoreService:GetDataStore("DailyRewardsData_v2")
-- ========================================
-- CONFIG (7 jours)
-- ========================================
local REWARDS_CONFIG = {
	{day = 1, toolName = "SpeedCoil",    isPoints = false},
	{day = 2, toolName = nil,            isPoints = true, points = 5000},
	{day = 3, toolName = "Gravity Coil", isPoints = false},
	{day = 4, toolName = "FusionCoil",   isPoints = false},
	{day = 5, toolName = nil,            isPoints = true, points = 5000},
	{day = 6, toolName = "SpeedCoil",    isPoints = false},
	{day = 7, toolName = "Jetpack",      isPoints = false},
}
local TOTAL_DAYS = #REWARDS_CONFIG
local ADMIN_IDS = {11017023724, 8142402169}
local NOTIFICATION_DELAY = 25
local FIRST_JOIN_DELAY = 900 -- 10 minutes
local GroupId = 684717971
local playerTools = {}
local activeNotifications = {}
local dailyClaimCooldowns = {}
local dailyRewardClickCooldown = {}
local playerDataCache = {}
-- 🆕 Timer premier join (sync avec data.firstJoinAt dans DataStore)
local firstJoinTimers = {}
-- ========================================
-- 🛡️ DATASTORE LOAD/SAVE SÉCURISÉ (fix bug #1)
-- ========================================
local function loadPlayerData(player)
	local maxAttempts = 3
	for attempt = 1, maxAttempts do
		local success, data = pcall(function()
			return DailyRewardsStore:GetAsync("Player_" .. player.UserId)
		end)
		if success then
			if data then
				if data.firstJoinAt == nil then data.firstJoinAt = 0 end
				return data, true
			else
				return {
					currentDay    = 1,
					lastClaimDate = "",
					claimedToday  = false,
					firstJoinAt   = 0,
				}, true
			end
		else
			warn(string.format("⚠️ DailyRewards: load tentative %d échouée pour %s : %s",
				attempt, player.Name, tostring(data)))
			if attempt < maxAttempts then task.wait(2) end
		end
	end
	-- Échec total → return nil (BLOQUE toute écriture)
	warn(string.format("❌ DailyRewards: impossible de charger %s, écritures bloquées", player.Name))
	return nil, false
end
local function savePlayerData(player, data)
	if not data then
		warn("⚠️ savePlayerData: data nil, save annulée pour " .. player.Name)
		return false
	end
	local success, err = pcall(function()
		DailyRewardsStore:SetAsync("Player_" .. player.UserId, data)
	end)
	if not success then
		warn("Failed to save data for " .. player.Name .. ": " .. tostring(err))
	end
	return success
end
-- ========================================
-- 🆕 PREMIER JOIN
-- ========================================
local function isFirstEverJoin(data)
	return data.currentDay == 1 and data.lastClaimDate == "" and not data.claimedToday
end
-- 🛡️ DÉFENSIF : si timer pas encore initialisé, on bloque par défaut (fix bug #3)
local function getFirstJoinTimeRemaining(userId)
	local joinTime = firstJoinTimers[userId]
	if not joinTime then
		return FIRST_JOIN_DELAY
	end
	local elapsed = os.time() - joinTime
	local remaining = FIRST_JOIN_DELAY - elapsed
	return math.max(0, remaining)
end
-- ========================================
-- 🛡️ FONCTION SÉCURISÉE POINTS (jours 2 & 5)
-- ========================================
local function giveDailyPoints(player, pointsAmount)
	if not player or not player.Parent then return false end
	local userId = player.UserId
	local rawPoints = pointsAmount or 5000
	-- ✅ FIX FAUX-BAN : plus de CheckQuestCooldown / CheckRemoteCall ici.
	-- La vraie protection anti-farm est data.claimedToday (vérifié dans le handler
	-- AVANT d'arriver ici) : 1 seul claim par jour calendaire, côté serveur/DataStore.
	-- CheckQuestCooldown bannissait sur un simple re-claim (bug UI / save raté) sans
	-- rien protéger de plus. L'anti-spam local 5s ci-dessous reste en place.
	local now = os.time()
	if dailyClaimCooldowns[userId] and (now - dailyClaimCooldowns[userId]) < 5 then
		warn(player.Name .. " spam détecté sur Daily Rewards")
		return false
	end
	dailyClaimCooldowns[userId] = now
	if not _G.tempsJoueurs then warn("❌ tempsJoueurs not initialized!") return false end
	if type(_G.tempsJoueurs[userId]) ~= "table" then
		_G.tempsJoueurs[userId] = {base = 0, future = 0, lastSaved = 0}
	end
	task.spawn(function()
		SmartAntiCheat.ExpectGain(userId, rawPoints, "DailyRewardPoints")
	end)
	_G.tempsJoueurs[userId].future = _G.tempsJoueurs[userId].future + rawPoints
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
	task.spawn(function() SmartAntiCheat.RecordGain(player, rawPoints, "DailyRewardPoints") end)
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
	print(string.format("✅ DAILY POINTS: %s a reçu %d points (bruts) → %d affichés",
		player.Name, rawPoints, pointsStat and pointsStat.Value or 0))
	return true
end
-- ========================================
-- UTILITAIRES
-- ========================================
local function getTimezoneOffset(player)
	local LocalizationService = game:GetService("LocalizationService")
	local success, result = pcall(function()
		return LocalizationService:GetCountryRegionForPlayerAsync(player)
	end)
	if not success or not result then return 0 end
	if result == "US" or result == "CA" or result == "MX" then return -5 * 3600
	elseif result == "GB" or result == "FR" or result == "DE" or result == "ES" or result == "IT" then return 1 * 3600
	elseif result == "JP" or result == "KR" then return 9 * 3600
	elseif result == "AU" then return 10 * 3600
	elseif result == "BR" then return -3 * 3600
	end
	return 0
end
local function getMidnightTodayForPlayer(player)
	local timezoneOffset = getTimezoneOffset(player)
	local localTime = os.time() + timezoneOffset
	local localDateTable = os.date("!*t", localTime)
	localDateTable.hour, localDateTable.min, localDateTable.sec = 0, 0, 0
	return os.time(localDateTable) - timezoneOffset
end
local function getNextMidnightForPlayer(player)
	return getMidnightTodayForPlayer(player) + 86400
end
local function getCurrentDateForPlayer(player)
	local localTime = os.time() + getTimezoneOffset(player)
	return os.date("!%Y-%m-%d", localTime)
end
local function isAdmin(player)
	if player.UserId == game.CreatorId then return true end
	for _, adminId in ipairs(ADMIN_IDS) do
		if player.UserId == adminId then return true end
	end
	return false
end
local function giveTool(player, toolName)
	local tool = ServerStorage:FindFirstChild(toolName)
	if not tool then warn("Tool not found in ServerStorage: " .. toolName) return false end
	if not playerTools[player.UserId] then playerTools[player.UserId] = {} end
	if table.find(playerTools[player.UserId], toolName) then return true end
	table.insert(playerTools[player.UserId], toolName)
	--  pas de 2e copie s'il l'a déjà (gamepass, en main…)
	local bpD = player:FindFirstChild("Backpack")
	if bpD and not bpD:FindFirstChild(toolName)
		and not (player.Character and player.Character:FindFirstChild(toolName)) then
		local clonedTool = tool:Clone()
		clonedTool.Parent = bpD
	end
	local starterGear = player:FindFirstChild("StarterGear")
	if not starterGear then
		starterGear = Instance.new("Folder")
		starterGear.Name = "StarterGear"
		starterGear.Parent = player
	end
	if not starterGear:FindFirstChild(toolName) then
		local starterTool = tool:Clone()
		starterTool.Parent = starterGear
	end
	return true
end
local function checkAndUpdateNewDay(player, data)
	local currentDate = getCurrentDateForPlayer(player)
	if data.lastClaimDate == "" or data.lastClaimDate ~= currentDate then
		data.claimedToday = false
		return true
	end
	return false
end
local function startNotificationTimer(player, currentDay)
	if activeNotifications[player.UserId] then
		task.cancel(activeNotifications[player.UserId])
		activeNotifications[player.UserId] = nil
	end
	local timerThread = task.delay(NOTIFICATION_DELAY, function()
		if not player or not player.Parent then
			activeNotifications[player.UserId] = nil
			return
		end
		local data, ok = loadPlayerData(player)
		if ok and data and not data.claimedToday then
			local showDailyNotificationEvent = ReplicatedStorage:FindFirstChild("ShowDailyNotificationEvent")
			if showDailyNotificationEvent then
				pcall(function() showDailyNotificationEvent:FireClient(player, currentDay) end)
			end
		end
		activeNotifications[player.UserId] = nil
	end)
	activeNotifications[player.UserId] = timerThread
end
local function cancelNotificationTimer(player)
	if activeNotifications[player.UserId] then
		task.cancel(activeNotifications[player.UserId])
		activeNotifications[player.UserId] = nil
		local cancelDailyNotificationEvent = ReplicatedStorage:FindFirstChild("CancelDailyNotificationEvent")
		if cancelDailyNotificationEvent then
			pcall(function() cancelDailyNotificationEvent:FireClient(player) end)
		end
	end
end
local function resetPlayerData(player)
	local now = os.time()
	local defaultData = {
		currentDay    = 1,
		lastClaimDate = "",
		claimedToday  = false,
		firstJoinAt   = now,  -- 🆕 reset = nouveau premier join
	}
	local success = savePlayerData(player, defaultData)
	if not success then
		warn("Failed to reset data for player: " .. player.Name)
		return false
	end
	cancelNotificationTimer(player)
	firstJoinTimers[player.UserId] = now
	playerDataCache[player.UserId] = {data = defaultData, loadedAt = now}
	local nextMidnight = getNextMidnightForPlayer(player)
	local timeRemaining = nextMidnight - now
	local dataToSend = {
		currentDay = 1, lastClaimDate = "", claimedToday = false,
		timeRemaining = timeRemaining, nextMidnight = nextMidnight, serverTime = now,
		isFirstJoin = true, firstJoinTimeRemaining = FIRST_JOIN_DELAY,
	}
	local getDailyDataEvent = ReplicatedStorage:FindFirstChild("GetDailyDataEvent")
	if getDailyDataEvent then
		getDailyDataEvent:FireClient(player, dataToSend)
	end
	return true
end
local function unlockDay2(player)
	if not isAdmin(player) then return false end
	local data, loadOk = loadPlayerData(player)
	if not loadOk or not data then
		warn("⚠️ unlockDay2: load échoué pour " .. player.Name)
		return false
	end
	data.currentDay = 2
	data.claimedToday = false
	data.lastClaimDate = ""
	if not savePlayerData(player, data) then
		warn("Failed to unlock day 2 for player: " .. player.Name)
		return false
	end
	cancelNotificationTimer(player)
	playerDataCache[player.UserId] = {data = data, loadedAt = os.time()}
	local nextMidnight = getNextMidnightForPlayer(player)
	local dataToSend = {
		currentDay = 2, lastClaimDate = "", claimedToday = false,
		timeRemaining = 0, nextMidnight = nextMidnight, serverTime = os.time(),
	}
	local getDailyDataEvent = ReplicatedStorage:FindFirstChild("GetDailyDataEvent")
	if getDailyDataEvent then getDailyDataEvent:FireClient(player, dataToSend) end
	return true
end
-- ========================================
-- REMOTE EVENTS
-- ========================================
local function getOrCreateRemote(name, className)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className or "RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end
local giveToolEvent = getOrCreateRemote("GiveToolEvent")
local getDailyDataEvent = getOrCreateRemote("GetDailyDataEvent")
local claimDailyRewardEvent = getOrCreateRemote("ClaimDailyRewardEvent")
local resetDailyDataEvent = getOrCreateRemote("ResetDailyDataEvent")
local showDailyNotificationEvent = getOrCreateRemote("ShowDailyNotificationEvent")
local cancelDailyNotificationEvent = getOrCreateRemote("CancelDailyNotificationEvent")
-- ========================================
-- HANDLER : getDailyDataEvent
-- ========================================
getDailyDataEvent.OnServerEvent:Connect(function(player)
	local now = os.time()
	local cached = playerDataCache[player.UserId]
	local data
	if cached and (now - cached.loadedAt) < 30 then
		data = cached.data
	else
		local loadOk
		data, loadOk = loadPlayerData(player)
		if not loadOk or not data then
			-- 🛡️ Load échoué : on ne touche RIEN, on n'envoie pas non plus pour éviter de tromper le client
			warn("⚠️ getDailyData: load échoué pour " .. player.Name .. ", aucune réponse envoyée")
			return
		end
		playerDataCache[player.UserId] = {data = data, loadedAt = now}
	end
	local isNewDay = checkAndUpdateNewDay(player, data)
	if isNewDay then savePlayerData(player, data) end
	local nextMidnight = getNextMidnightForPlayer(player)
	local timeRemaining = 0
	-- Détection premier join
	local isFirstJoin = isFirstEverJoin(data)
	local firstJoinTimeRemaining = 0
	if isFirstJoin then
		firstJoinTimeRemaining = getFirstJoinTimeRemaining(player.UserId)
		if firstJoinTimeRemaining > 0 then
			local dataToSend = {
				currentDay = data.currentDay, lastClaimDate = data.lastClaimDate,
				claimedToday = false, timeRemaining = 0, nextMidnight = nextMidnight,
				serverTime = os.time(), isFirstJoin = true,
				firstJoinTimeRemaining = firstJoinTimeRemaining,
			}
			getDailyDataEvent:FireClient(player, dataToSend)
			return
		end
	end
	if data.claimedToday then
		timeRemaining = nextMidnight - os.time()
		if timeRemaining < 0 then timeRemaining = 0 end
	else
		if not isFirstJoin then
			task.wait(1)
			startNotificationTimer(player, data.currentDay)
		end
	end
	local dataToSend = {
		currentDay = data.currentDay, lastClaimDate = data.lastClaimDate,
		claimedToday = data.claimedToday, timeRemaining = timeRemaining,
		nextMidnight = nextMidnight, serverTime = os.time(),
		isFirstJoin = isFirstJoin, firstJoinTimeRemaining = firstJoinTimeRemaining,
	}
	getDailyDataEvent:FireClient(player, dataToSend)
end)
-- ========================================
-- HANDLER : claimDailyRewardEvent
-- ========================================
claimDailyRewardEvent.OnServerEvent:Connect(function(player)

	-- ✅ FIX #7
	if _G.recentReloads and _G.recentReloads[player.UserId] then return end
	if _G.dataLoading and _G.dataLoading[player.UserId] then return end

	local now_click = os.time()
	if dailyRewardClickCooldown[player.UserId] and (now_click - dailyRewardClickCooldown[player.UserId]) < 3 then
		return
	end
	dailyRewardClickCooldown[player.UserId] = now_click
	local data, loadOk = loadPlayerData(player)
	if not loadOk or not data then
		warn("⚠️ claim: load échoué pour " .. player.Name .. ", refus")
		claimDailyRewardEvent:FireClient(player, false, nil)
		return
	end
	checkAndUpdateNewDay(player, data)
	if data.claimedToday then
		warn(player.Name .. " tried to claim but already claimed today")
		claimDailyRewardEvent:FireClient(player, false, nil)
		return
	end
	-- Vérification premier join
	if isFirstEverJoin(data) then
		local remaining = getFirstJoinTimeRemaining(player.UserId)
		if remaining > 0 then
			warn(player.Name .. " tente claim Jour 1 avant fin timer ("
				.. math.ceil(remaining) .. "s restantes)")
			claimDailyRewardEvent:FireClient(player, false, {
				firstJoinBlocked = true,
				firstJoinTimeRemaining = remaining,
			})
			return
		end
	end
	local rewardConfig = nil
	for _, config in ipairs(REWARDS_CONFIG) do
		if config.day == data.currentDay then rewardConfig = config break end
	end
	if not rewardConfig then
		warn("No reward config found for day " .. data.currentDay)
		claimDailyRewardEvent:FireClient(player, false, nil)
		return
	end
	local success = false
	if rewardConfig.isPoints then
		success = giveDailyPoints(player, rewardConfig.points)
	else
		success = giveTool(player, rewardConfig.toolName)
	end
	if success then
		cancelNotificationTimer(player)
		data.claimedToday = true
		data.lastClaimDate = getCurrentDateForPlayer(player)
		data.currentDay = data.currentDay + 1
		if data.currentDay > TOTAL_DAYS then data.currentDay = 1 end
		if not savePlayerData(player, data) then
			-- Save échoué : on ne crash pas, mais log
			warn("⚠️ Save échoué après claim pour " .. player.Name)
		end
		playerDataCache[player.UserId] = {data = data, loadedAt = os.time()}
		local nextMidnight = getNextMidnightForPlayer(player)
		local dataToSend = {
			currentDay = data.currentDay, lastClaimDate = data.lastClaimDate,
			claimedToday = data.claimedToday, timeRemaining = nextMidnight - os.time(),
			nextMidnight = nextMidnight, serverTime = os.time(),
		}
		claimDailyRewardEvent:FireClient(player, true, dataToSend)
	else
		claimDailyRewardEvent:FireClient(player, false, nil)
	end
end)
-- 🔒 FAILLE FERMÉE : un client pouvait demander N'IMPORTE QUEL outil de ServerStorage par son nom.
--    Aucun script n'utilise ce signal (la récompense Daily est donnée par le serveur au claim).
giveToolEvent.OnServerEvent:Connect(function(player, toolName)
	warn(("🚫 GiveToolEvent refusé pour %s (%s)"):format(player.Name, tostring(toolName)))
end)
resetDailyDataEvent.OnServerEvent:Connect(function(player)
	if isAdmin(player) then resetPlayerData(player)
	else warn(player.Name .. " tried to reset daily data without permission!") end
end)
-- ========================================
-- 🆕 PLAYER ADDED (fix bug #3 + #4)
-- ========================================
Players.PlayerAdded:Connect(function(player)
	-- 🛡️ TIMER DÉFENSIF IMMÉDIAT (fix bug #3 : plus de bypass possible)
	-- Sera corrigé après le load avec la vraie valeur persistée
	firstJoinTimers[player.UserId] = os.time()
	task.spawn(function()
		local data, loadOk = loadPlayerData(player)
		if not loadOk or not data then
			warn("⚠️ PlayerAdded load échoué pour " .. player.Name .. ", timer défensif maintenu")
			return
		end
		if isFirstEverJoin(data) then
			-- 🆕 Persistance firstJoinAt (fix bug #4)
			if (data.firstJoinAt or 0) == 0 then
				data.firstJoinAt = os.time()
				savePlayerData(player, data)
				print(string.format("🆕 PREMIER JOIN ABSOLU pour %s → Timer 10 min démarré", player.Name))
			else
				print(string.format("🆕 REJOIN durant timer 10 min pour %s (%d s déjà écoulées)",
					player.Name, os.time() - data.firstJoinAt))
			end
			-- Synchroniser le cache mémoire avec la vraie valeur persistée
			firstJoinTimers[player.UserId] = data.firstJoinAt
			-- Notif quand le timer est écoulé
			local remaining = getFirstJoinTimeRemaining(player.UserId)
			if remaining > 0 then
				task.delay(remaining, function()
					if not player or not player.Parent then return end
					local currentData, ok = loadPlayerData(player)
					if not ok or not currentData then return end
					if not currentData.claimedToday and currentData.currentDay == 1 and currentData.lastClaimDate == "" then
						local showDailyNotif = ReplicatedStorage:FindFirstChild("ShowDailyNotificationEvent")
						if showDailyNotif then
							pcall(function() showDailyNotif:FireClient(player, 1) end)
						end
						print(string.format("🔔 Timer 10 min écoulé pour %s → Notif Jour 1", player.Name))
					end
				end)
			end
		else
			-- Pas un premier join → annuler le timer défensif
			firstJoinTimers[player.UserId] = nil
		end
	end)
	-- Commandes chat
	player.Chatted:Connect(function(message)
		local lowerMsg = message:lower()
		if lowerMsg == "/resetdaily" then
			if isAdmin(player) then
				resetPlayerData(player)
				local hint = Instance.new("Hint")
				hint.Text = "Daily rewards data has been reset!"
				hint.Parent = workspace
				task.delay(3, function() hint:Destroy() end)
			end
		elseif lowerMsg == "/unlockday2" then
			if unlockDay2(player) then
				local hint = Instance.new("Hint")
				hint.Text = "✅ Jour 2 débloqué!"
				hint.Parent = workspace
				task.delay(3, function() hint:Destroy() end)
			end
		end
	end)
end)
-- ========================================
-- CLEANUP
-- ========================================
Players.PlayerRemoving:Connect(function(player)
	cancelNotificationTimer(player)
	playerDataCache[player.UserId] = nil
	local starterGear = player:FindFirstChild("StarterGear")
	if starterGear then starterGear:ClearAllChildren() end
	playerTools[player.UserId] = nil
	dailyClaimCooldowns[player.UserId] = nil
	firstJoinTimers[player.UserId] = nil
end)
print("✅ DailyRewards SERVEUR v4 chargé (7 jours, fixes #1-4 appliqués)")
-- Commandes admin: /resetdaily, /unlockday2