-- ========================================
-- 🎁 REFERRAL SYSTEM — version corrigee
-- À placer dans ServerScriptService (remplace l'ancien script)
-- ========================================
--[[
CORRECTIONS APPORTEES :
  1. Anti-alt : le parrain n'est credite que si le filleul a un compte
     de MIN_ACCOUNT_AGE jours ou plus (le filleul, lui, touche toujours).
  2. UpdateAsync atomique partout (claim / compteur / pending) :
     plus de lost update, plus de double-claim, cap de 10 non contournable.
  3. Le claim est reserve AVANT paiement, mais si le paiement echoue
     (joueur parti, data pas chargee), les points partent dans la file
     "pending" -> livres au prochain login. Rien n'est perdu.
  4. Les joueurs deja connectes au demarrage du script sont traites
     (avant : ils etaient ignores a cause du repeat/until).
  5. giveReferralPoints abandonne proprement si le chargement principal
     n'est pas fini -> plus de points ecrases par le loader.
  6. ReferralReceivedEvent n'est envoye que si le filleul va vraiment
     recevoir quelque chose.
  7. Cache du compteur avec TTL + purge (plus de fuite memoire ni de
     valeur perimee entre serveurs).
  8. Debounce sur PromptInvite (anti spam FireServer).
]]

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ========================================
-- CONFIG
-- ========================================
local REFERRAL_REWARD      = 3000
local REFERRAL_MAX_INVITES = 10

-- 🛡️ ANTI-ALT : age minimum du compte du FILLEUL (en jours) pour que
-- le PARRAIN soit credite. Le filleul touche sa recompense dans tous les cas.
-- Mets 0 pour desactiver.
local MIN_ACCOUNT_AGE = 7

-- 🆕 VRAI NOUVEAU JOUEUR OBLIGATOIRE (personne n'est payé sinon)
--   Avant : n'importe quel joueur qui n'avait JAMAIS été « filleul » comptait, même
--   avec 100 h de jeu. Deux amis pouvaient s'inviter l'un l'autre à des jours
--   différents (A invite B, puis B invite A) : 12 000 pts pour les mêmes amis.
--   Maintenant le filleul doit arriver pour la PREMIÈRE fois dans le jeu :
--     • moins de NEW_MAX_PLAYTIME s de jeu enregistrées AVANT cette session
--     • et (si connue) 1re arrivée il y a moins de NEW_MAX_FIRSTJOIN_AGE s
local NEW_MAX_PLAYTIME      = 600    -- 10 min
local NEW_MAX_FIRSTJOIN_AGE = 1800   -- 30 min

local MAX_PENDING          = 999999999
local COUNT_CACHE_TTL      = 60    -- s
local LOAD_WAIT_TIMEOUT    = 15    -- s d'attente max du chargement principal
local PROMPT_INVITE_COOLDOWN = 2   -- s, anti spam client

-- ========================================
-- ATTENTE DU SCRIPT PRINCIPAL
-- ========================================
repeat task.wait(0.1) until _G.tempsJoueurs
	and _G.SmartAntiCheat
	and _G.AntiExploit
	and _G.secureSave
	and _G.applyAllBonuses
	and _G.calculatePoints
	and _G.buyGamePassEvent

print("✅ ReferralSystem: Script principal détecté, démarrage...")

local SmartAntiCheat   = _G.SmartAntiCheat
local AntiExploit      = _G.AntiExploit
local secureSave       = _G.secureSave
local applyAllBonuses  = _G.applyAllBonuses
local calculatePoints  = _G.calculatePoints
local buyGamePassEvent = _G.buyGamePassEvent
-- ⚠️ tempsJoueurs / dataLoading sont lus via _G a chaque usage :
--    si le script principal les reassigne, on ne garde pas une ref morte.

-- ========================================
-- DATASTORES
-- ========================================
local referralClaimedStore = DataStoreService:GetDataStore("ReferralClaimed_v2")
local referralPendingStore = DataStoreService:GetDataStore("ReferralPending_v2")
local referralCountStore   = DataStoreService:GetDataStore("ReferralInviteCount_v1")

-- ========================================
-- REMOTE EVENTS
-- ========================================
local function getOrCreateRemote(name, className)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(className or "RemoteEvent")
		r.Name   = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local referralRewardEvent   = getOrCreateRemote("ReferralRewardNotify")
local referralReceivedEvent = getOrCreateRemote("ReferralReceivedEvent")
local promptInviteEvent     = getOrCreateRemote("PromptInvite")

-- ========================================
-- HELPER : UpdateAsync avec retries
-- ========================================
local function safeUpdate(store, key, transform, label)
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:UpdateAsync(key, transform)
		end)
		if ok then return true end
		warn(string.format("⚠️ [REFERRAL] %s UpdateAsync %d/3 : %s",
			label or key, attempt, tostring(err)))
		task.wait(attempt)
	end
	return false
end

-- ========================================
-- CACHE COMPTEUR D'INVITES (avec TTL)
-- ========================================
local referralInviteCountCache = {}  -- [userId] = {value = n, at = os.time()}

local function setCountCache(userId, value)
	referralInviteCountCache[userId] = { value = value, at = os.time() }
end

local function getReferralCount(referrerId)
	local c = referralInviteCountCache[referrerId]
	if c and (os.time() - c.at) < COUNT_CACHE_TTL then
		return c.value
	end
	local ok, val = pcall(function()
		return referralCountStore:GetAsync("count_" .. referrerId)
	end)
	local count = (ok and type(val) == "number") and val or 0
	setCountCache(referrerId, count)
	return count
end

-- Purge periodique du cache
task.spawn(function()
	while true do
		task.wait(300)
		local now = os.time()
		for id, c in pairs(referralInviteCountCache) do
			if (now - c.at) > COUNT_CACHE_TTL * 5 then
				referralInviteCountCache[id] = nil
			end
		end
	end
end)

-- ========================================
-- ⚛️ CONSOMMER UNE INVITE (atomique, respecte le cap)
-- retourne : granted(boolean), count(number), capped(boolean), dsFailed(boolean)
-- ========================================
local function tryConsumeInvite(referrerId)
	local newCount, capped = 0, false

	local ok = safeUpdate(referralCountStore, "count_" .. referrerId, function(old)
		local c = (type(old) == "number") and old or 0
		if c >= REFERRAL_MAX_INVITES then
			capped   = true
			newCount = c
			return nil   -- annule l'ecriture
		end
		newCount = c + 1
		capped   = false
		return newCount
	end, "count_" .. referrerId)

	if not ok then
		return false, 0, false, true
	end

	setCountCache(referrerId, newCount)
	return (not capped), newCount, capped, false
end

-- ========================================
-- ⚛️ RESERVER LA RECOMPENSE DU FILLEUL (atomique, anti double-claim)
-- retourne : reserved(boolean), dsFailed(boolean)
-- ========================================
local function tryReserveInviteeClaim(userId)
	local reserved = false

	local ok = safeUpdate(referralClaimedStore, "invitee_" .. userId, function(old)
		-- compat ancien format (booleen true)
		local alreadyClaimed = (old == true)
			or (type(old) == "table" and old.claimed == true)
		if alreadyClaimed then
			reserved = false
			return nil   -- annule l'ecriture
		end
		reserved = true
		return { claimed = true, at = os.time() }
	end, "invitee_" .. userId)

	if not ok then return false, true end
	return reserved, false
end

-- ========================================
-- ⚛️ FILE D'ATTENTE HORS-LIGNE (atomique)
-- ========================================
local function queueReferralOffline(userId, amount)
	if amount <= 0 then return end
	local total = 0
	local ok = safeUpdate(referralPendingStore, "pending_" .. userId, function(old)
		local cur = (type(old) == "number") and old or 0
		total = math.min(cur + amount, MAX_PENDING)
		return total
	end, "pending_" .. userId)

	if ok then
		print(string.format("💾 Referral offline: UserID %d → +%d pts stockés (total: %d)",
			userId, amount, total))
	else
		warn(string.format("❌ [REFERRAL] Impossible de stocker %d pts pour UserID %d",
			amount, userId))
	end
end

-- ========================================
-- DONNER DES POINTS
-- retourne true si les points ont bien ete credites
-- ========================================
local function giveReferralPoints(player, amount, source)
	if not player or not player.Parent then return false end
	local userId = player.UserId

	-- Attendre la fin du chargement principal
	local waited = 0
	while _G.dataLoading and _G.dataLoading[userId] and waited < LOAD_WAIT_TIMEOUT * 10 do
		task.wait(0.1)
		waited += 1
	end

	-- ⚠️ Timeout : on N'ECRIT PAS (le loader ecraserait les points ensuite)
	if _G.dataLoading and _G.dataLoading[userId] then
		warn(string.format("⚠️ [REFERRAL] Chargement toujours en cours pour %s → mise en attente",
			player.Name))
		return false
	end

	if not player.Parent then return false end

	local tempsJoueurs = _G.tempsJoueurs
	if not tempsJoueurs then return false end

	if type(tempsJoueurs[userId]) ~= "table" then
		tempsJoueurs[userId] = { base = 0, future = 0, lastSaved = 0 }
	end

	SmartAntiCheat.ExpectGain(userId, amount, source)
	tempsJoueurs[userId].future = tempsJoueurs[userId].future + amount

	local leaderstats = player:FindFirstChild("leaderstats")
	local pointsStat  = leaderstats and leaderstats:FindFirstChild("Points")
	if pointsStat then
		local totalPoints = tempsJoueurs[userId].base + tempsJoueurs[userId].future
		pointsStat.Value  = applyAllBonuses(calculatePoints(totalPoints), player)
		player:SetAttribute("Points", pointsStat.Value)
	end

	task.spawn(function()
		SmartAntiCheat.RecordGain(player, amount, source)
		local tj = _G.tempsJoueurs
		if tj and tj[userId] then
			secureSave(userId, tj[userId].base + tj[userId].future)
		end
	end)

	AntiExploit.questHistory[userId] = AntiExploit.questHistory[userId] or {}

	pcall(function()
		referralRewardEvent:FireClient(player, amount, source)
		buyGamePassEvent:FireClient(player)
	end)

	if _G.EngageStats then pcall(_G.EngageStats.Referral, userId, amount, source) end
	print(string.format("🎁 REFERRAL: %s → +%d pts (%s)", player.Name, amount, source))
	return true
end

-- Paie si possible, sinon met en file d'attente. Ne perd jamais les points.
local function payOrQueue(userId, amount, source)
	local player = Players:GetPlayerByUserId(userId)
	if player and player.Parent then
		if giveReferralPoints(player, amount, source) then
			return true
		end
	end
	queueReferralOffline(userId, amount)
	return false
end

-- ========================================
-- DISTRIBUER LES POINTS EN ATTENTE AU LOGIN (atomique)
-- ========================================
local function claimPendingReferral(player)
	local userId = player.UserId
	local key    = "pending_" .. userId

	local waited = 0
	while _G.dataLoading and _G.dataLoading[userId] and waited < LOAD_WAIT_TIMEOUT * 10 do
		task.wait(0.1)
		waited += 1
	end
	task.wait(0.5)
	if not player.Parent then return end

	-- Prend le montant ET remet a 0 en une seule operation atomique
	local taken = 0
	local ok = safeUpdate(referralPendingStore, key, function(old)
		local cur = (type(old) == "number") and old or 0
		if cur <= 0 then
			taken = 0
			return nil   -- rien a faire, pas d'ecriture
		end
		taken = cur
		return 0
	end, key)

	if not ok or taken <= 0 then return end

	if giveReferralPoints(player, taken, "Referral_Pending") then
		print(string.format("🎁 Points referral en attente livrés à %s: +%d pts",
			player.Name, taken))
	else
		-- Paiement impossible -> on remet dans la file, rien n'est perdu
		queueReferralOffline(userId, taken)
	end
end

-- ========================================
-- 🆕 LE FILLEUL EST-IL UN VRAI NOUVEAU JOUEUR ?
-- true = nouveau · false = a déjà joué · nil = impossible à savoir (on ne paie pas)
-- ========================================
local ServerScriptService = game:GetService("ServerScriptService")
local function isGenuinelyNew(player)
	-- temps de jeu enregistré AVANT cette session (posé par le script principal au chargement)
	local pt
	local t0 = os.clock()
	while player.Parent and os.clock() - t0 < 20 do
		pt = player:GetAttribute("PlaytimeSeconds")
		if pt ~= nil then break end
		task.wait(0.5)
	end
	if type(pt) ~= "number" then return nil end
	if pt > NEW_MAX_PLAYTIME then return false end
	-- 2e signal : date de 1re arrivée (sécurité supplémentaire), si elle est connue
	local okB, bridge = pcall(function()
		return require(ServerScriptService:FindFirstChild("CapFirstJoinBridge"))
	end)
	if okB and type(bridge) == "table" and type(bridge.get) == "function" then
		local fj
		local t1 = os.clock()
		while player.Parent and os.clock() - t1 < 15 do
			fj = bridge.get(player.UserId)
			if fj then break end
			task.wait(0.5)
		end
		if type(fj) == "number" and os.time() - fj > NEW_MAX_FIRSTJOIN_AGE then return false end
	end
	return true
end

-- ========================================
-- TRAITER LE REFERRAL AU JOIN
-- ========================================
local function handleReferral(player)
	local userId = player.UserId

	local joinData
	local ok = pcall(function() joinData = player:GetJoinData() end)
	if not ok or not joinData then return end

	local referrerId = joinData.ReferredByPlayerId
	if not referrerId or referrerId == 0 or referrerId == userId then return end

	print(string.format("🔗 Referral: %s (ID:%d, compte %d j) invité par UserID %d",
		player.Name, userId, player.AccountAge, referrerId))

	-- ── 0. Seulement pour un joueur qui découvre le jeu ─────────────
	local isNew = isGenuinelyNew(player)
	if isNew ~= true then
		print(string.format("⛔ Referral ignoré : %s %s → personne n'est payé", player.Name,
			isNew == false and "a déjà joué au jeu" or "(données non chargées)"))
		if isNew == false then
			local referrerPlayer = Players:GetPlayerByUserId(referrerId)
			if referrerPlayer and referrerPlayer.Parent then
				pcall(function() referralRewardEvent:FireClient(referrerPlayer, 0, "Referral_NotNew") end)
			end
		end
		return
	end

	-- ── 1. Recompense du filleul (reservation atomique) ──────────────
	local reserved, dsFailed = tryReserveInviteeClaim(userId)

	if dsFailed then
		warn(string.format("⚠️ [REFERRAL] DataStore indisponible pour %s, réessai au prochain join",
			player.Name))
		return
	end

	if reserved then
		pcall(function()
			referralReceivedEvent:FireClient(player, referrerId)
		end)
		-- payOrQueue : si le joueur part ou que sa data n'est pas prête,
		-- les points sont stockés et livrés au prochain login.
		payOrQueue(userId, REFERRAL_REWARD, "Referral_Invitee")
	else
		print(string.format("ℹ️ %s a déjà sa récompense referral", player.Name))
	end

	-- ── 2. Recompense du parrain ─────────────────────────────────────
	if AntiExploit.bannedPlayers[referrerId] then
		warn(string.format("🚫 Referrer banni ignoré: %d", referrerId))
		return
	end

	-- 🛡️ ANTI-ALT : compte du filleul trop récent
	if MIN_ACCOUNT_AGE > 0 and player.AccountAge < MIN_ACCOUNT_AGE then
		warn(string.format("🛡️ Anti-alt: compte de %s trop récent (%d j < %d j) → parrain %d non crédité",
			player.Name, player.AccountAge, MIN_ACCOUNT_AGE, referrerId))
		local referrerPlayer = Players:GetPlayerByUserId(referrerId)
		if referrerPlayer and referrerPlayer.Parent then
			pcall(function()
				referralRewardEvent:FireClient(referrerPlayer, 0, "Referral_TooNew")
			end)
		end
		return
	end

	-- Le filleul n'a jamais compté pour personne ? (evite qu'un meme
	-- filleul credite plusieurs parrains via plusieurs liens)
	if not reserved then
		print(string.format("ℹ️ %s a déjà été compté comme filleul → parrain non crédité",
			player.Name))
		return
	end

	-- Incremente le compteur du parrain de facon atomique (cap respecte)
	local granted, newCount, capped, countFailed = tryConsumeInvite(referrerId)

	if countFailed then
		warn(string.format("⚠️ [REFERRAL] Compteur indisponible pour UserID %d → parrain non crédité",
			referrerId))
		return
	end

	if capped or not granted then
		print(string.format("⛔ Limite atteinte pour UserID %d (%d/%d), parrain non récompensé",
			referrerId, newCount, REFERRAL_MAX_INVITES))
		local referrerPlayer = Players:GetPlayerByUserId(referrerId)
		if referrerPlayer and referrerPlayer.Parent then
			pcall(function()
				referralRewardEvent:FireClient(referrerPlayer, 0, "Referral_CapReached")
			end)
		end
		return
	end

	print(string.format("✅ Parrain UserID %d → invite #%d/%d",
		referrerId, newCount, REFERRAL_MAX_INVITES))

	payOrQueue(referrerId, REFERRAL_REWARD, "Referral_Inviter")
end

-- ========================================
-- HOOK JOUEURS (+ ceux deja connectes)
-- ========================================
local handledPlayers = {}

local function onPlayerAdded(player)
	local userId = player.UserId
	if handledPlayers[userId] then return end
	handledPlayers[userId] = true

	task.spawn(function()
		local waited = 0
		while _G.dataLoading and _G.dataLoading[userId] and waited < 200 do
			task.wait(0.1)
			waited += 1
		end
		task.wait(0.5)
		if not player.Parent then return end

		task.spawn(function()
			local ok, err = pcall(claimPendingReferral, player)
			if not ok then warn("[REFERRAL] claimPending: " .. tostring(err)) end
		end)

		local ok, err = pcall(handleReferral, player)
		if not ok then warn("[REFERRAL] handleReferral: " .. tostring(err)) end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- ⚠️ Les joueurs arrivés PENDANT le repeat/until d'attente du script
-- principal étaient ignorés dans l'ancienne version.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	handledPlayers[player.UserId] = nil
end)

-- ========================================
-- PROMPT INVITE (avec debounce anti-spam)
-- ========================================
local lastPromptInvite = {}

promptInviteEvent.OnServerEvent:Connect(function(player)
	local now  = os.clock()
	local last = lastPromptInvite[player.UserId]
	if last and (now - last) < PROMPT_INVITE_COOLDOWN then return end
	lastPromptInvite[player.UserId] = now
	print(string.format("📨 %s a ouvert le prompt d'invitation", player.Name))
end)

Players.PlayerRemoving:Connect(function(player)
	lastPromptInvite[player.UserId] = nil
end)

-- ========================================
-- COMMANDES DEBUG
-- ========================================
_G.DebugReferral = function(userId)
	task.spawn(function()
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print("🎁 DEBUG REFERRAL UserID:", userId)
		print(string.format("  Limite: %d invites max | Âge compte min: %d j",
			REFERRAL_MAX_INVITES, MIN_ACCOUNT_AGE))

		local s1, c = pcall(function()
			return referralClaimedStore:GetAsync("invitee_" .. userId)
		end)
		local claimed = (c == true) or (type(c) == "table" and c.claimed == true)
		print("  Récompense filleul réclamée:", (s1 and claimed) and "✅ OUI" or "❌ NON")

		local s2, p = pcall(function()
			return referralPendingStore:GetAsync("pending_" .. userId)
		end)
		print("  Points parrain en attente:",
			(s2 and type(p) == "number" and p > 0) and (tostring(p) .. " pts") or "Aucun")

		local count = getReferralCount(userId)
		print(string.format("  Invites effectuées: %d/%d", count, REFERRAL_MAX_INVITES))
		print(string.format("  Limite atteinte: %s",
			count >= REFERRAL_MAX_INVITES and "✅ OUI" or "❌ NON"))

		local plr = Players:GetPlayerByUserId(userId)
		if plr then
			print(string.format("  Âge du compte: %d j (%s)", plr.AccountAge,
				plr.AccountAge >= MIN_ACCOUNT_AGE and "✅ OK" or "🛡️ trop récent"))
		end
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	end)
end

_G.ResetReferral = function(userId)
	task.spawn(function()
		pcall(function() referralClaimedStore:RemoveAsync("invitee_" .. userId) end)
		pcall(function() referralPendingStore:RemoveAsync("pending_" .. userId) end)
		pcall(function() referralCountStore:SetAsync("count_" .. userId, 0) end)
		setCountCache(userId, 0)
		print(string.format("✅ Referral reset complet pour UserID %d", userId))
	end)
end

_G.ResetReferralCount = function(userId)
	task.spawn(function()
		pcall(function() referralCountStore:SetAsync("count_" .. userId, 0) end)
		setCountCache(userId, 0)
		print(string.format("✅ Compteur invites remis à 0 pour UserID %d", userId))
	end)
end

_G.SetReferralCap = function(newCap)
	if type(newCap) ~= "number" or newCap < 1 then
		print("❌ Usage: _G.SetReferralCap(10)")
		return
	end
	REFERRAL_MAX_INVITES = math.floor(newCap)
	print(string.format("✅ Nouvelle limite: %d invites max", REFERRAL_MAX_INVITES))
end

_G.SetReferralMinAccountAge = function(days)
	if type(days) ~= "number" or days < 0 then
		print("❌ Usage: _G.SetReferralMinAccountAge(7)  — 0 pour désactiver")
		return
	end
	MIN_ACCOUNT_AGE = math.floor(days)
	print(string.format("✅ Âge de compte minimum du filleul: %d jour(s)", MIN_ACCOUNT_AGE))
end

print("✅ REFERRAL SYSTEM CHARGÉ")
print(string.format("   Récompense: %d pts | Limite: %d invites | Âge compte min: %d j",
	REFERRAL_REWARD, REFERRAL_MAX_INVITES, MIN_ACCOUNT_AGE))
print("   _G.DebugReferral(userId)")
print("   _G.ResetReferral(userId)")
print("   _G.ResetReferralCount(userId)")
print("   _G.SetReferralCap(n)")
print("   _G.SetReferralMinAccountAge(n)")