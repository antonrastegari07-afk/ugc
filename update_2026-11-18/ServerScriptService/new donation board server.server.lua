--[[
	TopDonatorsServer.lua  —  v3
	============================================================================
	Uniquement les correctifs SERVEUR pertinents. Aucune donnée d'affichage
	supplémentaire, aucun nouveau remote : ton UI actuelle et ton ProcessReceipt
	fonctionnent sans la moindre modification.

	🔴 CE QUI EST CORRIGÉ vs ta version

	1. flushProfiles() perdait des profils
	   `profileDirty = {}` était exécuté AVANT l'UpdateAsync. Si l'écriture
	   échouait (throttle, coupure), les noms/compteurs étaient perdus pour de
	   bon et le classement réaffichait "Joueur #123456".
	   → La file est restaurée en cas d'échec et retentée au flush suivant.

	2. Le blob profil grandissait à l'infini
	   Chaque donateur historique restait dans la clé `profiles`. Au-delà de
	   ~4 MB par clé, l'UpdateAsync échoue et le blob cesse silencieusement de
	   se mettre à jour.
	   → Élagage au top 50 + joueurs en ligne, avec un garde-fou : on n'élague
	     JAMAIS si le scan global a échoué (sinon le blob serait vidé).

	3. leaderboardStore:SetAsync n'était pas retryé
	   L'UpdateAsync du total avait 5 tentatives, mais l'écriture dans
	   l'OrderedDataStore aucune. En cas d'échec, le total était correct en
	   base mais le joueur DISPARAISSAIT du classement jusqu'à son prochain
	   achat. Et un OrderedDataStore n'accepte QUE des entiers.
	   → setOrdered() : 3 tentatives + backoff + math.floor.

	4. resetAllDonations() faisait ~4 requêtes DataStore par joueur
	   dont un UpdateAsync COMPLET du blob à chaque itération (50 joueurs =
	   50 réécritures de la même clé).
	   → Suppression en lot : 1 seul UpdateAsync du blob à la fin.

	5. INITIAL_DELAY = 8 s pour rien
	   Le budget DataStore est plein au démarrage du serveur.
	   → 2 s.

	⚡ OPTIMISATION INVISIBLE
	   UpdateLeaderboard transporte maintenant la liste dans son payload.
	   Un client qui l'utilise évite un InvokeServer ; un client qui l'ignore
	   (le tien aujourd'hui) fonctionne exactement pareil. 100 % rétro-compatible.

	INTERFACE STRICTEMENT IDENTIQUE :
	  _G.RecordDonation(userId, playerName, amount, productId)
	  GetLeaderboardData, UpdateLeaderboard, DonationSuccess, ChatNotifDonation,
	  ResetDonations, ResetPlayerDonations, AddDonationManually
--]]

local Players            = game:GetService("Players")
local DataStoreService   = game:GetService("DataStoreService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local SoundService       = game:GetService("SoundService")
local RT                 = Enum.DataStoreRequestType

-- ========================================================================
-- CONFIG
-- ========================================================================
local TOP_COUNT                 = 50
local INITIAL_DELAY             = 2     -- ✅ était 8
local GLOBAL_REFRESH_INTERVAL   = 600
local AUTO_SAVE_INTERVAL        = 900
local SAVE_THROTTLE             = 0.3
local UPDATE_BROADCAST_DEBOUNCE = 2
local ADMIN_USER_ID             = 11017023724
local PROFILE_STORE_NAME        = "DonationProfiles_v1"
local PROFILE_BLOB_KEY          = "profiles"

local IS_STUDIO = RunService:IsStudio()

-- ========================================================================
-- DATASTORES
-- ========================================================================
local donationStore    = DataStoreService:GetDataStore("TopDonatorsV1")
local leaderboardStore = DataStoreService:GetOrderedDataStore("TopDonatorsLeaderboard")
local profileStore     = DataStoreService:GetDataStore(PROFILE_STORE_NAME)

local function playerKey(userId) return "Donation_" .. userId end

-- ========================================================================
-- REMOTES (noms identiques, aucun ajout)
-- ========================================================================
local function getOrCreate(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local getLeaderboardData     = getOrCreate("GetLeaderboardData", "RemoteFunction")
local updateLeaderboardEvent = getOrCreate("UpdateLeaderboard")
local donationSuccessEvent   = getOrCreate("DonationSuccess")
local chatNotifDonationEvent = getOrCreate("ChatNotifDonation")
local resetDonationsEvent    = getOrCreate("ResetDonations")
local resetPlayerEvent       = getOrCreate("ResetPlayerDonations")
local addDonationEvent       = getOrCreate("AddDonationManually")

-- ========================================================================
-- ÉTAT MÉMOIRE
-- ========================================================================
local playerDonations   = {}   -- [userId] = {total,count,name}
local lastSavedTotal    = {}   -- [userId] = total
local profileCache      = {}   -- [userId] = {name,count}
local profileDirty      = {}   -- [userId] = true
local globalSnapshot    = {}   -- {userId,total} du dernier GetSortedAsync
local cachedTop         = {}   -- liste renvoyée au client
local globalDataLoaded  = false
local systemReady       = false
local lastGlobalRefresh = 0
local lastBroadcast     = 0

local function isAdmin(player) return player.UserId == ADMIN_USER_ID end
local function markDirty(userId) profileDirty[userId] = true end

local function budgetOK(reqType)
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(reqType)
	end)
	return (not ok) or (budget == nil) or (budget > 0)
end

-- ========================================================================
-- ✅ CORRECTIF 3 : écriture OrderedDataStore fiabilisée
-- ========================================================================
local function setOrdered(userId, total)
	local value = math.floor(tonumber(total) or 0)   -- ⚠️ entiers uniquement
	if value <= 0 then
		pcall(function() leaderboardStore:RemoveAsync(tostring(userId)) end)
		return true
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			leaderboardStore:SetAsync(tostring(userId), value)
		end)
		if ok then return true end
		warn(string.format("⚠️ SetAsync ordered %d/3 (userId %s) : %s",
			attempt, tostring(userId), tostring(err)))
		task.wait(0.5 * attempt)
	end
	warn("❌ Classement global non mis à jour pour userId " .. tostring(userId))
	return false
end

-- ========================================================================
-- NOTIFS
-- ========================================================================
local function formatNumberForChat(num)
	local formatted = tostring(num)
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then break end
	end
	return formatted
end

local function sendDonationChatNotification(player, amount)
	if not player then return end

	-- 📢 Délégué au hub de notifs : il choisit tout seul
	--    SERVER (< seuil) ou GLOBAL cross-server (>= seuil)
	if _G.NotifyDonation then
		pcall(function() _G.NotifyDonation(player.Name, amount) end)
		return
	end

	-- Fallback si ChatNotifServer n'est pas encore chargé
	local message = string.format("[DONATION] %s donated %s R$! 💚",
		player.Name, formatNumberForChat(amount))
	for _, plr in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			pcall(function() chatNotifDonationEvent:FireClient(plr, message) end)
		end)
	end
end

-- ⚡ payload joint (rétro-compatible : ton client actuel ignore l'argument)
local function broadcastUpdate(force)
	local now = tick()
	if not force and (now - lastBroadcast) < UPDATE_BROADCAST_DEBOUNCE then return end
	lastBroadcast = now
	pcall(function()
		updateLeaderboardEvent:FireAllClients({ top = cachedTop })
	end)
end

-- ========================================================================
-- 🎉 EFFETS GLOBAUX (inchangés)
-- ========================================================================
local PARTICLE_PART_NAMES = {"DonationEffect", "DonationEffect2"}
local PARTICLE_DURATION   = 7
local FADE_DURATION       = 1
local FADE_STEPS          = 20
local MAX_SOUND_DISTANCE  = 300
local particleParts       = {}
local donationSoundTemplate = nil
local effectsReady        = false

local function initializeDonationEffects()
	donationSoundTemplate = SoundService:FindFirstChild("Donation")
	if not donationSoundTemplate then
		warn("⚠️ Son 'Donation' introuvable dans SoundService!")
	end
	for _, partName in ipairs(PARTICLE_PART_NAMES) do
		local part = workspace:FindFirstChild(partName)
		if part then
			part.Transparency = 1
			local emitters = {}
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("ParticleEmitter") then
					child.Enabled = false
					table.insert(emitters, {emitter = child, originalRate = child.Rate})
				end
			end
			table.insert(particleParts, {part = part, emitters = emitters})
		else
			warn("⚠️ Part '" .. partName .. "' introuvable dans Workspace!")
		end
	end
	effectsReady = true
	print("✅ Effets de donation initialisés!")
end

local lastEffectAt = -1e9
local EFFECT_MIN_GAP = 3   -- s : une rafale de dons ne relance pas l'effet 10 fois de suite
local function playGlobalDonationEffects()
	if not effectsReady then return end
	local nowFx = os.clock()
	if nowFx - lastEffectAt < EFFECT_MIN_GAP then return end
	lastEffectAt = nowFx
	if donationSoundTemplate and #particleParts > 0 then
		for _, partData in ipairs(particleParts) do
			task.spawn(function()
				local sound = donationSoundTemplate:Clone()
				sound.Parent = partData.part
				sound.RollOffMode = Enum.RollOffMode.Linear
				sound.RollOffMaxDistance = MAX_SOUND_DISTANCE
				sound.RollOffMinDistance = 10
				sound.EmitterSize = 10
				local originalVolume = sound.Volume
				sound:Play()
				task.delay(PARTICLE_DURATION - FADE_DURATION, function()
					local fadeDelay = FADE_DURATION / FADE_STEPS
					for i = 1, FADE_STEPS do
						if sound and sound.Parent then
							sound.Volume = originalVolume * (1 - (i / FADE_STEPS))
							task.wait(fadeDelay)
						end
					end
					if sound and sound.Parent then sound:Stop() end
				end)
				task.delay(PARTICLE_DURATION + 2, function()
					if sound and sound.Parent then sound:Destroy() end
				end)
			end)
		end
	end
	if #particleParts > 0 then
		task.spawn(function()
			for _, partData in ipairs(particleParts) do
				for _, e in ipairs(partData.emitters) do e.emitter.Enabled = true end
			end
			task.delay(PARTICLE_DURATION - FADE_DURATION, function()
				local fadeDelay = FADE_DURATION / FADE_STEPS
				for i = 1, FADE_STEPS do
					for _, partData in ipairs(particleParts) do
						for _, e in ipairs(partData.emitters) do
							e.emitter.Rate = e.originalRate * (1 - (i / FADE_STEPS))
						end
					end
					task.wait(fadeDelay)
				end
				for _, partData in ipairs(particleParts) do
					for _, e in ipairs(partData.emitters) do
						e.emitter.Enabled = false
						e.emitter.Rate = e.originalRate
					end
				end
			end)
		end)
	end
end

task.spawn(function()
	task.wait(5)
	initializeDonationEffects()
end)

-- ========================================================================
-- PROFIL BLOB
-- ========================================================================
local function loadProfileBlob()
	local ok, stored = pcall(function() return profileStore:GetAsync(PROFILE_BLOB_KEY) end)
	if ok and type(stored) == "table" then
		for k, v in pairs(stored) do
			local id = tonumber(k)
			if id and type(v) == "table" then
				profileCache[id] = profileCache[id] or v
			end
		end
	end
end

-- ✅ CORRECTIF 1 (perte de profils) + CORRECTIF 2 (croissance infinie)
local function flushProfiles()
	if next(profileDirty) == nil then return end
	if not budgetOK(RT.UpdateAsync) then return end

	local batch, queued = {}, {}
	for id in pairs(profileDirty) do
		if profileCache[id] then
			batch[tostring(id)] = profileCache[id]
			table.insert(queued, id)
		end
	end
	if next(batch) == nil then profileDirty = {}; return end
	profileDirty = {}

	-- Qui survit à l'élagage : le top affiché + les joueurs en ligne
	-- + tout ce qu'on est en train d'écrire.
	local keep = {}
	for _, e in ipairs(globalSnapshot) do keep[tostring(e.userId)] = true end
	for _, p in ipairs(Players:GetPlayers()) do keep[tostring(p.UserId)] = true end
	for k in pairs(batch) do keep[k] = true end

	-- 🛡️ Garde-fou indispensable : si le GetSortedAsync a échoué,
	-- globalSnapshot est vide → élaguer VIDERAIT le blob entier.
	local canPrune = (#globalSnapshot >= TOP_COUNT)

	local ok, err = pcall(function()
		profileStore:UpdateAsync(PROFILE_BLOB_KEY, function(old)
			old = (type(old) == "table") and old or {}
			for k, v in pairs(batch) do old[k] = v end
			if canPrune then
				for k in pairs(old) do
					if not keep[k] then old[k] = nil end
				end
			end
			return old
		end)
	end)

	if not ok then
		-- ✅ RESTAURATION : rien n'est perdu, retenté au prochain flush
		for _, id in ipairs(queued) do profileDirty[id] = true end
		warn("⚠️ flushProfiles échoué (" .. tostring(err) .. ") — "
			.. #queued .. " profils remis en file d'attente")
	end
end

-- ✅ CORRECTIF 4 : suppression en LOT (1 requête au lieu de N)
local function removeProfilesFromBlob(ids)
	if type(ids) ~= "table" or #ids == 0 then return end
	pcall(function()
		profileStore:UpdateAsync(PROFILE_BLOB_KEY, function(old)
			if type(old) ~= "table" then return old end
			for _, id in ipairs(ids) do old[tostring(id)] = nil end
			return old
		end)
	end)
end

local function resolveProfile(userId)
	local prof = profileCache[userId]
	if prof and prof.name then return prof end

	local online = Players:GetPlayerByUserId(userId)
	if online then
		prof = { name = online.Name, count = (prof and prof.count) or 0 }
		profileCache[userId] = prof; markDirty(userId)
		return prof
	end

	local ok, data = pcall(function() return donationStore:GetAsync(playerKey(userId)) end)
	if ok and type(data) == "table" and data.name then
		prof = { name = data.name, count = data.count or 0 }
		profileCache[userId] = prof; markDirty(userId)
		return prof
	end

	local ok2, uname = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	prof = { name = (ok2 and uname) or ("Joueur #" .. userId), count = 0 }
	profileCache[userId] = prof; markDirty(userId)
	return prof
end

-- ========================================================================
-- CONSTRUIRE LE TOP
-- ========================================================================
local function buildCachedTop()
	local merged, seen = {}, {}

	for _, p in ipairs(Players:GetPlayers()) do
		local d = playerDonations[p.UserId]
		if d and d.total > 0 and not seen[p.UserId] then
			seen[p.UserId] = true
			table.insert(merged, {
				userId = p.UserId, total = d.total, count = d.count, name = p.Name,
			})
		end
	end

	for _, e in ipairs(globalSnapshot) do
		if e.total and e.total > 0 and not seen[e.userId] then
			seen[e.userId] = true
			local prof = profileCache[e.userId]
			table.insert(merged, {
				userId = e.userId,
				total  = e.total,
				count  = (prof and prof.count) or 0,
				name   = (prof and prof.name) or ("Joueur #" .. e.userId),
			})
		end
	end

	table.sort(merged, function(a, b) return a.total > b.total end)

	local result = {}
	for i = 1, math.min(TOP_COUNT, #merged) do result[i] = merged[i] end
	cachedTop = result
end

-- ========================================================================
-- REFRESH GLOBAL (1 GetSortedAsync + 1 blob)
-- ========================================================================
local function loadAllGlobalDonators(isStartup)
	local now = os.time()
	if globalDataLoaded and lastGlobalRefresh > 0
		and (now - lastGlobalRefresh) < GLOBAL_REFRESH_INTERVAL then
		return
	end
	if not budgetOK(RT.GetSortedAsync) then return end

	local ok, pages = pcall(function()
		return leaderboardStore:GetSortedAsync(false, TOP_COUNT)
	end)
	if not ok or not pages then
		warn("⚠️ Impossible de charger le top global")
		globalDataLoaded = true; lastGlobalRefresh = now
		return
	end

	local entries = pages:GetCurrentPage()
	loadProfileBlob()

	globalSnapshot = {}
	local unknown = {}
	for _, entry in ipairs(entries) do
		local userId = tonumber(entry.key)
		local total  = entry.value
		if userId and total and total > 0 then
			table.insert(globalSnapshot, { userId = userId, total = total })
			if not (profileCache[userId] and profileCache[userId].name) then
				table.insert(unknown, userId)
			end
		end
	end

	for _, userId in ipairs(unknown) do
		if not budgetOK(RT.GetAsync) then break end
		resolveProfile(userId)
		task.wait(isStartup and 0.15 or 0.25)
	end

	flushProfiles()
	buildCachedTop()
	globalDataLoaded  = true
	lastGlobalRefresh = now
end

-- ========================================================================
-- CHARGER UN JOUEUR
-- ========================================================================
local function loadPlayerData(userId, playerName)
	local ok, data = pcall(function() return donationStore:GetAsync(playerKey(userId)) end)
	if ok and type(data) == "table" then
		playerDonations[userId] = {
			total = data.total or 0,
			count = data.count or 0,
			name  = playerName or data.name,
		}
	else
		playerDonations[userId] = { total = 0, count = 0, name = playerName }
	end
	lastSavedTotal[userId] = playerDonations[userId].total
	profileCache[userId] = {
		name  = playerDonations[userId].name,
		count = playerDonations[userId].count,
	}
	markDirty(userId)
end

-- ========================================================================
-- DELTA ATOMIQUE
-- ========================================================================
local function applyDonationDelta(userId, playerName, amount)
	local newTotal, newCount
	local saved = false

	for attempt = 1, 5 do
		local ok = pcall(function()
			donationStore:UpdateAsync(playerKey(userId), function(old)
				old = (type(old) == "table") and old or { total = 0, count = 0 }
				old.total     = (old.total or 0) + amount
				old.count     = (old.count or 0) + 1
				old.name      = playerName
				old.timestamp = os.time()
				newTotal = old.total
				newCount = old.count
				return old
			end)
		end)
		if ok and newTotal then
			saved = true
			break
		end
		warn(string.format("⚠️ Tentative %d/5 UpdateAsync échouée pour %s",
			attempt, tostring(playerName)))
		task.wait(1)
	end

	if not saved then
		warn(string.format("❌ ÉCHEC CRITIQUE : donation de %s non sauvegardée!",
			tostring(playerName)))
		return nil
	end

	playerDonations[userId] = { total = newTotal, count = newCount, name = playerName }
	lastSavedTotal[userId]  = newTotal
	profileCache[userId]    = { name = playerName, count = newCount }
	markDirty(userId)

	setOrdered(userId, newTotal)   -- ✅ retryé

	-- maintien du snapshot local (évite d'attendre le prochain scan global)
	local found = false
	for _, e in ipairs(globalSnapshot) do
		if e.userId == userId then e.total = newTotal; found = true; break end
	end
	if not found then
		table.insert(globalSnapshot, { userId = userId, total = newTotal })
	end
	table.sort(globalSnapshot, function(a, b) return a.total > b.total end)
	while #globalSnapshot > TOP_COUNT do table.remove(globalSnapshot) end

	buildCachedTop()
	return newTotal
end

-- ========================================================================
-- 🌍 CROSS-SERVER : effet + son + board mis à jour sur TOUS les serveurs
--   Le serveur qui reçoit le don publie un petit message ; les autres jouent
--   l'effet du board et mettent leur classement à jour tout de suite
--   (avant : effet uniquement sur le serveur du don, board des autres serveurs
--   mis à jour seulement toutes les 10 min).
--   Coût : 1 PublishAsync par don (rare), aucune requête DataStore en plus.
-- ========================================================================
local MessagingService = game:GetService("MessagingService")
local XS_TOPIC = "DonationBoardFX_v1"
local XS_JOB   = game.JobId

local function publishDonationXS(userId, name, amount, total, count)
	if IS_STUDIO then return end
	task.spawn(function()
		local msg = { u = userId, n = tostring(name or ""):sub(1, 40), a = amount,
			t = total, c = count, j = XS_JOB }
		for attempt = 1, 3 do
			local ok = pcall(function() MessagingService:PublishAsync(XS_TOPIC, msg) end)
			if ok then return end
			task.wait(attempt)
		end
		warn("⚠️ Donation : effet cross-server non publié")
	end)
end

local function onDonationXS(message)
	local d = type(message) == "table" and message.Data
	if type(d) ~= "table" or d.j == XS_JOB then return end   -- notre propre écho : déjà joué
	local userId, total = tonumber(d.u), tonumber(d.t)
	if not userId or userId <= 0 or not total or total <= 0 or total ~= total then return end
	total = math.floor(total)
	local count = math.max(0, math.floor(tonumber(d.c) or 0))
	local name = (type(d.n) == "string" and d.n ~= "") and d.n or nil

	-- classement : on ne fait que MONTER (un message en retard ne fait jamais reculer un total)
	local found = false
	for _, e in ipairs(globalSnapshot) do
		if e.userId == userId then
			found = true
			if total > (e.total or 0) then e.total = total end
			break
		end
	end
	if not found then table.insert(globalSnapshot, { userId = userId, total = total }) end
	table.sort(globalSnapshot, function(x, y) return x.total > y.total end)
	while #globalSnapshot > TOP_COUNT do table.remove(globalSnapshot) end
	if name then
		local prof = profileCache[userId]
		profileCache[userId] = { name = name, count = math.max(count, (prof and prof.count) or 0) }
	end
	if systemReady then
		buildCachedTop()
		broadcastUpdate(true)
	end
	playGlobalDonationEffects()
end

task.spawn(function()
	if IS_STUDIO then return end
	for attempt = 1, 10 do
		local ok, err = pcall(function() MessagingService:SubscribeAsync(XS_TOPIC, onDonationXS) end)
		if ok then return end
		warn("⚠️ Donation cross-server : abonnement échoué (" .. tostring(err) .. "), nouvel essai")
		task.wait(math.min(60, 5 * attempt))
	end
end)

-- ========================================================================
-- ENREGISTRER UNE DONATION (appelée par ton ProcessReceipt externe)
-- ========================================================================
local function recordDonation(userId, playerName, amount, productId)
	if type(amount) ~= "number" or amount <= 0 then
		warn("❌ Montant invalide:", amount)
		return false
	end

	local newTotal = applyDonationDelta(userId, playerName, amount)
	if not newTotal then return false end

	print(string.format("✅ DONATION: %s (+%d R$) → total %d", playerName, amount, newTotal))
	local pd = playerDonations[userId]
	publishDonationXS(userId, playerName, amount, newTotal, pd and pd.count or 0)

	task.spawn(function()
		local player = Players:GetPlayerByUserId(userId)
		if player then
			pcall(function() donationSuccessEvent:FireClient(player, amount) end)
			sendDonationChatNotification(player, amount)
		end
		playGlobalDonationEffects()
	end)

	broadcastUpdate(false)
	return true
end

_G.RecordDonation = recordDonation

-- ========================================================================
-- DONATION MANUELLE (admin)
-- ========================================================================
local function addManualDonation(targetUserId, amount, targetName)
	if type(amount) ~= "number" or amount <= 0 then
		return false, "Montant invalide"
	end

	local newTotal = applyDonationDelta(targetUserId, targetName, amount)
	if not newTotal then return false, "Échec de sauvegarde" end

	print(string.format("✅ DONATION MANUELLE: %s (+%d R$) → total %d",
		targetName, amount, newTotal))
	local pdm = playerDonations[targetUserId]
	publishDonationXS(targetUserId, targetName, amount, newTotal, pdm and pdm.count or 0)
	task.spawn(function() playGlobalDonationEffects() end)

	local player = Players:GetPlayerByUserId(targetUserId)
	if player then
		task.spawn(function()
			pcall(function() donationSuccessEvent:FireClient(player, amount) end)
			sendDonationChatNotification(player, amount)
		end)
	end

	broadcastUpdate(true)
	return true, string.format("Donation de %d R$ ajoutée avec succès!", amount)
end

-- ========================================================================
-- RESET D'UN JOUEUR
--   deferBlob = true → le lot s'occupera du blob (utilisé par resetAll)
-- ========================================================================
local function resetPlayerDonations(targetUserId, targetName, deferBlob)
	local resetData = { total = 0, count = 0, name = targetName, timestamp = os.time() }

	playerDonations[targetUserId] = { total = 0, count = 0, name = targetName }
	lastSavedTotal[targetUserId]  = 0

	pcall(function() donationStore:SetAsync(playerKey(targetUserId), resetData) end)
	task.wait(SAVE_THROTTLE)
	pcall(function() leaderboardStore:RemoveAsync(tostring(targetUserId)) end)

	profileCache[targetUserId] = nil
	profileDirty[targetUserId] = nil
	if not deferBlob then
		removeProfilesFromBlob({ targetUserId })
	end

	for i = #globalSnapshot, 1, -1 do
		if globalSnapshot[i].userId == targetUserId then table.remove(globalSnapshot, i) end
	end

	if not deferBlob then
		buildCachedTop()
		broadcastUpdate(true)
	end
	return true
end

-- ========================================================================
-- ✅ CORRECTIF 4 : RESET COMPLET — 1 seul UpdateAsync du blob
-- ========================================================================
local function resetAllDonations()
	local ids, seen = {}, {}

	local ok, pages = pcall(function()
		return leaderboardStore:GetSortedAsync(false, TOP_COUNT)
	end)
	if ok and pages then
		for _, entry in ipairs(pages:GetCurrentPage()) do
			local id = tonumber(entry.key)
			if id and not seen[id] then seen[id] = true; table.insert(ids, id) end
		end
	end
	for id in pairs(playerDonations) do
		if not seen[id] then seen[id] = true; table.insert(ids, id) end
	end

	local count = 0
	for i, id in ipairs(ids) do
		local name = (playerDonations[id] and playerDonations[id].name) or ("Joueur #" .. id)
		resetPlayerDonations(id, name, true)   -- ⬅️ blob différé
		count = count + 1
		if i % 5 == 0 then task.wait(0.5) end
	end

	removeProfilesFromBlob(ids)   -- ✅ une seule requête pour tout le monde

	globalSnapshot    = {}
	cachedTop         = {}
	globalDataLoaded  = false
	lastGlobalRefresh = 0

	broadcastUpdate(true)
	print(string.format("🗑️ Reset complet : %d donateurs effacés", count))
	return count
end

-- ========================================================================
-- SUPPRIMER LE DONATEUR À UN RANG
-- ========================================================================
local function deleteDonatorAtRank(targetRank)
	targetRank = tonumber(targetRank)
	if not targetRank or targetRank < 1 or targetRank > TOP_COUNT then
		return false, "Rang invalide (1-" .. TOP_COUNT .. ")"
	end
	local target = cachedTop[targetRank]
	if not target then return false, "Aucun donateur à la place " .. targetRank end

	resetPlayerDonations(target.userId, target.name)
	print(string.format("🗑️ Place #%d supprimée : %s (userId %d)",
		targetRank, target.name, target.userId))
	return true, string.format("Place #%d (%s) supprimée!", targetRank, target.name)
end

-- ========================================================================
-- SAUVEGARDE (dirty-tracking)
-- ========================================================================
local function savePlayerIfDirty(userId)
	local d = playerDonations[userId]
	if not d then return end
	if lastSavedTotal[userId] == d.total then return end

	pcall(function()
		donationStore:SetAsync(playerKey(userId), {
			total = d.total, count = d.count, name = d.name, timestamp = os.time(),
		})
	end)
	setOrdered(userId, d.total)
	lastSavedTotal[userId] = d.total
end

-- ========================================================================
-- EVENTS ADMIN
-- ========================================================================
resetDonationsEvent.OnServerEvent:Connect(function(player)
	if not isAdmin(player) then player:Kick("Action non autorisée"); return end
	local n = resetAllDonations()
	pcall(function() resetDonationsEvent:FireClient(player, true, n) end)
end)

resetPlayerEvent.OnServerEvent:Connect(function(player, targetUserId)
	if not isAdmin(player) then player:Kick("Action non autorisée"); return end
	targetUserId = tonumber(targetUserId)
	if not targetUserId then
		pcall(function() resetPlayerEvent:FireClient(player, false, "UserId invalide") end)
		return
	end
	local targetName = "Joueur #" .. targetUserId
	local tp = Players:GetPlayerByUserId(targetUserId)
	if tp then targetName = tp.Name
	elseif playerDonations[targetUserId] then targetName = playerDonations[targetUserId].name end

	local ok = resetPlayerDonations(targetUserId, targetName)
	pcall(function() resetPlayerEvent:FireClient(player, ok, targetName) end)
end)

addDonationEvent.OnServerEvent:Connect(function(player, targetUserId, amount)
	if not isAdmin(player) then player:Kick("Action non autorisée"); return end
	targetUserId = tonumber(targetUserId); amount = tonumber(amount)
	if not targetUserId then
		pcall(function() addDonationEvent:FireClient(player, false, "UserId invalide") end); return
	end
	if not amount or amount <= 0 then
		pcall(function() addDonationEvent:FireClient(player, false, "Montant invalide") end); return
	end

	local targetName = "Joueur #" .. targetUserId
	local tp = Players:GetPlayerByUserId(targetUserId)
	if tp then targetName = tp.Name
	elseif playerDonations[targetUserId] then targetName = playerDonations[targetUserId].name
	else
		local ok, res = pcall(function() return Players:GetNameFromUserIdAsync(targetUserId) end)
		if ok and res then targetName = res end
	end

	local ok, msg = addManualDonation(targetUserId, amount, targetName)
	pcall(function() addDonationEvent:FireClient(player, ok, msg) end)
end)

-- ========================================================================
-- JOUEUR REJOINT
-- ========================================================================
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		while not systemReady do task.wait(0.5) end
		task.wait(math.random(1, 2))
		loadPlayerData(player.UserId, player.Name)
		buildCachedTop()
		broadcastUpdate(false)
	end)

	if player.UserId == ADMIN_USER_ID then
		player.Chatted:Connect(function(message)
			local lower = string.lower(message)
			if lower == "/resetdonations" then
				resetAllDonations()
				task.wait(1)
				globalDataLoaded = false; lastGlobalRefresh = 0
				loadAllGlobalDonators(false)
			elseif string.sub(lower, 1, 12) == "/resetplayer" then
				local id = tonumber(string.sub(message, 14))
				if id then
					local name = "Joueur #" .. id
					local tp = Players:GetPlayerByUserId(id)
					if tp then name = tp.Name elseif playerDonations[id] then name = playerDonations[id].name end
					resetPlayerDonations(id, name)
				end
			elseif string.sub(lower, 1, 12) == "/deleteplace" then
				local rank = tonumber(string.sub(message, 14))
				if rank then
					local ok, msg = deleteDonatorAtRank(rank)
					print((ok and "✅ " or "❌ ") .. tostring(msg))
				else
					warn("❌ Format: /deleteplace [rang]")
				end
			elseif string.sub(lower, 1, 12) == "/adddonation" then
				local args = string.split(message, " ")
				if #args == 3 then
					local id = tonumber(args[2]); local amt = tonumber(args[3])
					if id and amt and amt > 0 then
						local name = "Joueur #" .. id
						local tp = Players:GetPlayerByUserId(id)
						if tp then name = tp.Name
						elseif playerDonations[id] then name = playerDonations[id].name
						else
							local ok, res = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
							if ok and res then name = res end
						end
						local ok, msg = addManualDonation(id, amt, name)
						print((ok and "✅ " or "❌ ") .. tostring(msg))
					else
						warn("❌ Format: /adddonation UserId Amount")
					end
				else
					warn("❌ Format: /adddonation UserId Amount")
				end
			end
		end)
	end
end)

-- ========================================================================
-- JOUEUR QUITTE
-- ========================================================================
Players.PlayerRemoving:Connect(function(player)
	task.spawn(function()
		savePlayerIfDirty(player.UserId)
		flushProfiles()
		playerDonations[player.UserId] = nil
		lastSavedTotal[player.UserId]  = nil
	end)
end)

-- ========================================================================
-- INIT
-- ========================================================================
if IS_STUDIO then warn("🧪 MODE STUDIO") end

task.spawn(function()
	task.wait(INITIAL_DELAY)          -- ✅ 2 s
	loadAllGlobalDonators(true)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function() loadPlayerData(player.UserId, player.Name) end)
		task.wait(0.1)
	end

	task.wait(1)
	buildCachedTop()
	systemReady = true
	broadcastUpdate(true)
	print("✅ Système de donations initialisé!")
end)

-- ========================================================================
-- REFRESH GLOBAL PÉRIODIQUE
-- ========================================================================
task.spawn(function()
	while true do
		task.wait(GLOBAL_REFRESH_INTERVAL)
		if #Players:GetPlayers() > 0 then
			globalDataLoaded = false
			loadAllGlobalDonators(false)
			broadcastUpdate(true)
		end
	end
end)

-- ========================================================================
-- AUTO-SAVE
-- ========================================================================
task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayerIfDirty(player.UserId)
			task.wait(SAVE_THROTTLE)
		end
		flushProfiles()
	end
end)

-- ========================================================================
-- FERMETURE
-- ========================================================================
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerIfDirty(player.UserId)
	end
	flushProfiles()
	task.wait(2)
end)

-- ========================================================================
-- BRIDGE UI (forme de données identique : {userId,total,count,name})
-- ========================================================================
getLeaderboardData.OnServerInvoke = function()
	if not globalDataLoaded or not systemReady then return {} end
	return cachedTop
end

print("✅ TopDonators Server v3 chargé — UI/ProcessReceipt inchangés")