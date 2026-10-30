--[[
	📜 QuestSystem ▸ FeedbackQuest   (ModuleScript, enfant du Script « QuestSystem »)
	Ancien script : « Feedback quest » — même logique, mêmes DataStores, mêmes remotes.
--]]
--════════════════════════════════════════════════════════════
-- 🎁 FEEDBACK QUEST — SERVEUR  (v2 DURCIE)
-- Récompense UNIQUE de 1000 pts après l'envoi d'un feedback.
--
-- 🔐 MODÈLE DE SÉCURITÉ
--   La SEULE source de vérité est le DataStore, via UpdateAsync avec
--   garde sur l'ancienne valeur. La mémoire n'est qu'un cache d'affichage :
--   même corrompue, forgée ou périmée, elle ne peut PAS créer de points.
--   Transitions autorisées, atomiques et cross-serveur :  0 → 1 → 2
--     0 = rien | 1 = feedback envoyé | 2 = récompense réclamée
--
--   Ordre d'opérations : WRITE (atomique) → GRANT → si grant impossible,
--   ROLLBACK atomique. Il n'existe aucun chemin où les points sont donnés
--   deux fois, ni où l'état redescend sous 2 après une livraison réussie.
--════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local REWARD   = 1000

-- 🔘 QUÊTE ACTIVE ? Lu dans QUEST_SYSTEM_CONFIG ▸ Board ▸ Feedback ▸ Enabled.
--    false = quête retirée : AUCUN point ne peut être réclamé (même en appelant le
--    remote à la main) et l'envoi d'un feedback ne la débloque plus.
--    Remets true pour la réactiver : la progression des joueurs est gardée.
local QUEST_CFG
pcall(function() QUEST_CFG = require(ReplicatedStorage:WaitForChild("QUEST_SYSTEM_CONFIG", 10)) end)
local function questOn()
	local b = QUEST_CFG and QUEST_CFG.Board and QUEST_CFG.Board.Feedback
	return not (b and b.Enabled == false)
end
local SRC_NAME = "QuestFeedback"
local STORE    = DataStoreService:GetDataStore("FeedbackQuest_v1")

-- ⚠️ ORDRE OBLIGATOIRE : readState doit être déclaré AVANT transition et
-- ensureLoaded, sinon ces closures capturent un global nil.
local JOB = (game.JobId ~= "" and game.JobId)
	or ("studio_" .. tostring(math.random(1, 1000000)))

-- Lit les deux formats : nombre (legacy) ou reçu {s=, by=, t=}
local function readState(data)
	if type(data) == "number" then
		return math.clamp(math.floor(data), 0, 2), nil
	elseif type(data) == "table" then
		return math.clamp(math.floor(tonumber(data.s) or 0), 0, 2), data.by
	end
	return 0, nil
end

local function mkRemote(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local checkFn    = mkRemote("CheckFeedbackQuest",  "RemoteFunction")
local claimEvent = mkRemote("ClaimFeedbackQuest",  "RemoteEvent")
local updEvent   = mkRemote("FeedbackQuestUpdate", "RemoteEvent")

-- caches purement UI / anti-spam (jamais décisionnels)
local cache, loading, busy       = {}, {}, {}
local lastClaim, lastCheck       = {}, {}
local loadFailUntil, claimedSess = {}, {}

_G.FeedbackQuestPending = _G.FeedbackQuestPending or {}   -- rollbacks ratés (admin)

local function label(userId)
	local s = cache[userId]
	if s == nil then return "loading" end
	if s >= 2  then return "claimed" end
	if s == 1  then return "ready_to_claim" end
	return "todo"
end

local function push(player)
	if not player or not player.Parent then return end
	pcall(function() updEvent:FireClient(player, label(player.UserId)) end)
end

-- ════════════════════════════════════════════════════════════
-- TRANSITION ATOMIQUE  (le cœur de l'anti-farm)
-- Retourne : applied(bool), reason("ok" | "state" | "datastore")
-- UpdateAsync est atomique par clé sur TOUS les serveurs : deux claims
-- simultanés ne peuvent pas voir tous les deux old == 1.
-- ════════════════════════════════════════════════════════════
local function transition(userId, from, to)
	local key = tostring(userId)
	local applied = false
	local ok, err = pcall(function()
		STORE:UpdateAsync(key, function(old)
			local cur = readState(old)
			if cur ~= from then
				applied = false
				return nil                     -- annule : AUCUNE écriture
			end
			applied = true
			return { s = to, by = JOB, t = os.time() }   -- reçu signé
		end)
	end)

	if ok then
		return applied, applied and "ok" or "state"
	end

	-- ⚠️ ÉCRITURE AMBIGUË : l'erreur peut être survenue APRÈS le write.
	-- Le reçu nous dit si c'est bien nous qui avons gagné la transition.
	local okRead, data = pcall(function() return STORE:GetAsync(key) end)
	if okRead then
		local cur, by = readState(data)
		if cur == to and by == JOB then
			warn(("ℹ️ FeedbackQuest %d : write %d→%d confirmé par le reçu malgré l'erreur")
				:format(userId, from, to))
			return true, "ok"
		end
	end
	warn(("🚨 FeedbackQuest transition %d→%d KO pour %d : %s")
		:format(from, to, userId, tostring(err)))
	return false, "datastore"
end
-- lecture paresseuse, une fois par joueur/serveur, avec backoff en cas d'échec
local function ensureLoaded(userId)
	if cache[userId] ~= nil then return true end
	if loadFailUntil[userId] and os.clock() < loadFailUntil[userId] then return false end
	if loading[userId] then
		local t = 0
		while loading[userId] and t < 120 do task.wait(0.1); t += 1 end
		return cache[userId] ~= nil
	end
	loading[userId] = true
	local ok, data
	for attempt = 1, 3 do
		ok, data = pcall(function() return STORE:GetAsync(tostring(userId)) end)
		if ok then break end
		task.wait(0.5 * attempt)
	end
	loading[userId] = nil
	if not ok then
		loadFailUntil[userId] = os.clock() + 15
		warn(("🚨 FeedbackQuest : lecture impossible pour %d"):format(userId))
		return false
	end
	cache[userId] = readState(data)
	return true
end

-- ════════════════════════════════════════════════════════════
-- LIVRAISON DES POINTS (aucun yield avant la mutation mémoire)
-- ════════════════════════════════════════════════════════════
local function playerReady(userId, player)
	if not player or not player.Parent then return false end
	if _G.dataLoading   and _G.dataLoading[userId]   then return false end
	if _G.recentReloads and _G.recentReloads[userId] then return false end
	local tj = _G.tempsJoueurs
	if type(tj) ~= "table" then return false end
	local d = tj[userId]
	if type(d) ~= "table" or type(d.base) ~= "number" or type(d.future) ~= "number" then
		return false
	end
	-- garantit que secureSave ne sera pas bloqué → points réellement persistés
	if type(_G.isAllSecondaryLoaded) == "function" and not _G.isAllSecondaryLoaded(userId) then
		return false
	end
	return true
end

local function grantPoints(player, amount)
	local userId = player.UserId
	if not playerReady(userId, player) then return false end

	if _G.SmartAntiCheat and _G.SmartAntiCheat.ExpectGain then
		pcall(function() _G.SmartAntiCheat.ExpectGain(userId, amount, SRC_NAME) end)
	end

	-- ⚠️ aucun yield entre ici et la fin du bloc
	local d = _G.tempsJoueurs[userId]
	d.future = d.future + amount
	local total = d.base + d.future

	local ls  = player:FindFirstChild("leaderstats")
	local pts = ls and ls:FindFirstChild("Points")
	if pts then
		local v = total
		if _G.calculatePoints then v = _G.calculatePoints(v) end
		if _G.applyAllBonuses then v = _G.applyAllBonuses(v, player) end
		if type(v) == "number" and v == v then
			pts.Value = v
			player:SetAttribute("Points", v)
			local sd = _G.SmartAntiCheat and _G.SmartAntiCheat.playerData
				and _G.SmartAntiCheat.playerData[userId]
			if sd then
				sd.lastKnownPoints = v
				sd.lastCheckTime   = os.time()
				if sd.validationWindow then sd.validationWindow.expectedGains = {} end
			end
		end
	end

	task.spawn(function()
		if _G.SmartAntiCheat and _G.SmartAntiCheat.RecordGain then
			pcall(function() _G.SmartAntiCheat.RecordGain(player, amount, SRC_NAME) end)
		end
		-- persistance avec quelques tentatives (les points sont déjà en mémoire)
		if _G.secureSave then
			for i = 1, 3 do
				local dd = _G.tempsJoueurs and _G.tempsJoueurs[userId]
				if type(dd) ~= "table" then break end
				local okSave = false
				pcall(function() okSave = _G.secureSave(userId, dd.base + dd.future) end)
				if okSave then break end
				task.wait(1.5)
			end
		end
		if _G.buyGamePassEvent then
			pcall(function() _G.buyGamePassEvent:FireClient(player) end)
		end
	end)
	return true
end

-- ════════════════════════════════════════════════════════════
-- HOOK : appelé par FeedbackSystem_Server après un envoi RÉUSSI
-- ════════════════════════════════════════════════════════════
_G.FeedbackQuest_OnSubmitted = function(userId)
	userId = tonumber(userId)
	if not userId then return end
	if not questOn() then return end            -- 🔘 quête désactivée : rien ne se débloque

	-- charge le cache d'abord : évite un UpdateAsync inutile pour les
	-- joueurs qui ont déjà envoyé un feedback ou déjà réclamé
	ensureLoaded(userId)
	if cache[userId] == 1 or cache[userId] == 2 then
		local pl0 = Players:GetPlayerByUserId(userId)
		if pl0 then push(pl0) end
		return
	end

	local applied, reason = transition(userId, 0, 1)
	if applied then
		cache[userId] = 1
		print(("🎁 FeedbackQuest débloquée pour %d"):format(userId))
	elseif reason == "state" then
		cache[userId] = nil                                       -- cache périmé → relire
		ensureLoaded(userId)
	end
	local pl = Players:GetPlayerByUserId(userId)
	if pl then push(pl) end
end

-- ════════════════════════════════════════════════════════════
-- CHECK
-- ════════════════════════════════════════════════════════════
checkFn.OnServerInvoke = function(player)
	if not questOn() then return "claimed" end  -- 🔘 quête désactivée : bouton inactif
	local userId = player.UserId
	local now = os.clock()
	if lastCheck[userId] and (now - lastCheck[userId]) < 2 then
		return label(userId)          -- réponse cache, zéro DataStore
	end
	lastCheck[userId] = now
	ensureLoaded(userId)
	return label(userId)
end

-- ════════════════════════════════════════════════════════════
-- CLAIM
-- ════════════════════════════════════════════════════════════
claimEvent.OnServerEvent:Connect(function(player)
	local userId = player.UserId
	if not questOn() then return end            -- 🔘 quête désactivée : AUCUN point

	local now = os.clock()
	if lastClaim[userId] and (now - lastClaim[userId]) < 2 then return end
	lastClaim[userId] = now
	if busy[userId] then return end
	if claimedSess[userId] then return end
	busy[userId] = true          -- posé AVANT tout yield → aucune ré-entrée

	task.spawn(function()
		local success, err = pcall(function()
			-- pré-filtres mémoire (économisent des UpdateAsync inutiles ;
			-- ne remplacent PAS la garde atomique)
			if cache[userId] == 2 or cache[userId] == 0 then return end

			-- 1) attendre que le joueur soit pleinement chargé (max 15 s)
			local t = 0
			while t < 150 and not playerReady(userId, player) do
				if not player.Parent then return end
				task.wait(0.1); t += 1
			end
			if not playerReady(userId, player) then
				warn(("⚠️ FeedbackQuest : %s pas prêt, claim reporté (aucune écriture)")
					:format(player.Name))
				return
			end

			-- 2) TRANSITION ATOMIQUE 1 → 2 (un seul serveur peut réussir)
			local applied, reason = transition(userId, 1, 2)
			if not applied then
				if reason == "state" then
					cache[userId] = nil
					ensureLoaded(userId)      -- resync : déjà réclamé ailleurs
				end
				return
			end
			cache[userId] = 2
			claimedSess[userId] = true

			-- 3) LIVRAISON immédiate
			if grantPoints(player, REWARD) then
				print(("✅ FeedbackQuest réclamée : %s +%d pts"):format(player.Name, REWARD))
				return
			end

			-- 4) Livraison impossible (joueur parti pendant l'écriture) →
			--    ROLLBACK atomique 2 → 1, il pourra réclamer plus tard.
			local back = false
			for i = 1, 5 do
				back = transition(userId, 2, 1)
				if back then break end
				task.wait(1.5)
			end
			if back then
				cache[userId] = 1
				claimedSess[userId] = nil
				warn(("↩️ FeedbackQuest : rollback OK pour %d (claim non livré)"):format(userId))
			else
				_G.FeedbackQuestPending[userId] = os.time()
				warn(("🚨 FeedbackQuest : ROLLBACK IMPOSSIBLE pour %d — %d pts à créditer à la main")
					:format(userId, REWARD))
			end
		end)

		busy[userId] = nil
		if not success then
			warn("❌ FeedbackQuest claim erreur : " .. tostring(err))
		end
		if player.Parent then push(player) end
	end)
end)

-- ════════════════════════════════════════════════════════════
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		task.wait(1 + math.random() * 2)      -- étale les lectures au join
		if not player.Parent then return end
		ensureLoaded(player.UserId)
		push(player)
	end)
end)

Players.PlayerRemoving:Connect(function(p)
	local id = p.UserId
	cache[id], loading[id], busy[id] = nil, nil, nil
	lastClaim[id], lastCheck[id]     = nil, nil
	loadFailUntil[id], claimedSess[id] = nil, nil
end)

-- ── Debug console serveur ──
_G.DebugFeedbackQuest = function(userId)
	userId = tonumber(userId)
	local ok, v = pcall(function() return STORE:GetAsync(tostring(userId)) end)
	local s, by = readState(ok and v or nil)
	print(("🎁 FeedbackQuest %d | store=%s (by=%s) | cache=%s | busy=%s")
		:format(userId, ok and tostring(s) or "ERR", tostring(by),
			tostring(cache[userId]), tostring(busy[userId])))
end

_G.ResetFeedbackQuest = function(userId)
	userId = tonumber(userId)
	if not userId then return end
	local ok = pcall(function()
		STORE:SetAsync(tostring(userId), { s = 0, by = JOB, t = os.time() })
	end)
	if ok then
		cache[userId], claimedSess[userId] = 0, nil
		local pl = Players:GetPlayerByUserId(userId)
		if pl then push(pl) end
		print("✅ FeedbackQuest reset pour " .. userId)
	end
end

print("✅ FEEDBACK QUEST v2 chargée (UpdateAsync atomique, rollback, anti-farm)")

return true
