-- ════════════════════════════════════════════════════════════════════════
-- ⭐ DEMANDE DE FAVORI — Script dans ServerScriptService (remplace tout le script)  v2
--
--  Réglages : ADMIN PANEL ▸ 🔔 POPUPS ▸ « ⭐ Demande de favori »
--
--  1re DEMANDE : quand le joueur ATTEINT le checkpoint choisi (défaut 4) — ou plus loin
--               (avant : uniquement en touchant CE checkpoint, donc un ancien joueur
--               déjà plus loin n'était jamais sollicité… ou l'était à chaque passage).
--  S'IL REFUSE : plus rien pendant cette session. Redemandé dans une PROCHAINE session,
--               au bon moment :
--                 • au moins RetryDays jours après (délai qui DOUBLE à chaque refus :
--                   2 j → 4 j → 8 j…) ;
--                 • seulement quand il joue déjà depuis MinSessionMinutes (joueur « chaud ») ;
--                 • seulement juste après avoir PROGRESSÉ (nouveau checkpoint), jamais en arène ;
--                 • au maximum MaxAsks fois au total.
--  S'IL ACCEPTE : plus jamais.
--
--  DataStore « GameFavorited_v1 » (même clé qu'avant, ancien format « true » compris) :
--    1 lecture par session, 1 écriture par demande, 1 écriture si accepté.
--  🔐 Une réponse du client n'est acceptée QUE si on vient de lui poser la question
--     (impossible de spammer des écritures).
-- ════════════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local favoriteStore = DataStoreService:GetDataStore("GameFavorited_v1")
local POPUP_ID = "favorite"
local JOIN_DELAY = 10            -- aucune opération DataStore avant 10 s (comme avant)
local ANSWER_TIMEOUT = 120       -- s : au-delà, une réponse n'est plus acceptée

local function getOrCreateRemote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end
local promptFavoriteEvent   = getOrCreateRemote("PromptFavorite")    -- serveur -> client
local favoriteResponseEvent = getOrCreateRemote("FavoriteResponse")  -- client -> serveur

local state = {}   -- [userId] = { ready, fav, n, t, joinedAt, askedThisSession, pendingAt, maxStage }

local function setting(key, default)
	local pc = _G.PopupControl
	if pc and pc.Get then
		local v = pc.Get(POPUP_ID, key)
		if v ~= nil then return v end
	end
	return default
end
local function enabled()
	local pc = _G.PopupControl
	if pc and pc.IsOn then return pc.IsOn(POPUP_ID) end
	return true
end

local function inArena(player)
	return (_G.PlayersInArena and _G.PlayersInArena[player.UserId]) or player:GetAttribute("InArena") == true
end

-- Peut-on demander MAINTENANT ? (appelé seulement quand le joueur progresse)
local function canAsk(player, s, stage)
	if not s.ready or s.fav or s.askedThisSession or s.pendingAt then return false end
	if not enabled() or inArena(player) then return false end
	local firstCp = tonumber(setting("Checkpoint", 4)) or 4
	if stage < firstCp then return false end
	local n = s.n or 0
	if n == 0 then return true end                                   -- jamais demandé
	if n >= (tonumber(setting("MaxAsks", 4)) or 4) then return false end
	local wait = (tonumber(setting("RetryDays", 2)) or 2) * 86400 * (2 ^ (n - 1))
	if os.time() - (s.t or 0) < wait then return false end
	local minPlay = (tonumber(setting("MinSessionMinutes", 10)) or 10) * 60
	return os.clock() - s.joinedAt >= minPlay
end

local function ask(player, s)
	s.askedThisSession = true
	s.pendingAt = os.clock()
	s.n = (s.n or 0) + 1
	s.t = os.time()
	local uid = player.UserId
	-- la demande est notée TOUT DE SUITE (même s'il quitte sans répondre)
	task.spawn(function()
		pcall(function()
			favoriteStore:UpdateAsync(tostring(uid), function(old)
				if old == true or (type(old) == "table" and old.f) then return nil end -- déjà favori
				old = type(old) == "table" and old or {}
				old.n = (tonumber(old.n) or 0) + 1
				old.t = os.time()
				return old
			end)
		end)
	end)
	local es = _G.EngageStats
	if es and es.PopupShown then pcall(es.PopupShown, player, POPUP_ID) end
	pcall(function() promptFavoriteEvent:FireClient(player) end)
end

local function onStage(player, value)
	local s = state[player.UserId]
	if not s then return end
	value = tonumber(value) or 0
	if value <= (s.maxStage or 0) then return end   -- pas une progression (chargement, retour en arrière…)
	s.maxStage = value
	if canAsk(player, s, value) then ask(player, s) end
end

local function onPlayerAdded(player)
	local uid = player.UserId
	local s = { ready = false, joinedAt = os.clock(), maxStage = 0 }
	state[uid] = s

	-- suivre la progression (valeur « Stage » du leaderboard)
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 60)
		local stage = ls and ls:WaitForChild("Stage", 60)
		if not stage or state[uid] ~= s then return end
		stage.Changed:Connect(function(v) onStage(player, v) end)
		-- base : là où il en est quand ses données sont prêtes (pas une progression)
		while state[uid] == s and not s.ready do task.wait(1) end
		s.maxStage = math.max(s.maxStage, tonumber(stage.Value) or 0)
	end)

	task.spawn(function()
		task.wait(JOIN_DELAY)
		if not player.Parent or state[uid] ~= s then return end
		local ok, data
		for attempt = 1, 3 do
			ok, data = pcall(function() return favoriteStore:GetAsync(tostring(uid)) end)
			if ok then break end
			task.wait(2 * attempt)
		end
		if not ok then return end   -- lecture ratée : on ne demande rien cette session
		if data == true or (type(data) == "table" and data.f) then
			s.fav = true
		elseif type(data) == "table" then
			s.n, s.t = tonumber(data.n) or 0, tonumber(data.t) or 0
		end
		s.ready = true
	end)
end

favoriteResponseEvent.OnServerEvent:Connect(function(player, favorited)
	local s = state[player.UserId]
	-- 🔐 seulement une réponse à NOTRE question, une seule fois
	if not s or not s.pendingAt or os.clock() - s.pendingAt > ANSWER_TIMEOUT then return end
	s.pendingAt = nil
	if favorited ~= true then return end   -- refus : déjà noté au moment de la demande
	s.fav = true
	local uid = player.UserId
	task.spawn(function()
		pcall(function()
			favoriteStore:UpdateAsync(tostring(uid), function(old)
				old = type(old) == "table" and old or {}
				old.f = true
				return old
			end)
		end)
	end)
	local es = _G.EngageStats
	if es and es.Hit then pcall(es.Hit, "fav_yes") end
	print(string.format("⭐ %s a mis le jeu en favori", player.Name))
end)

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
Players.PlayerRemoving:Connect(function(player) state[player.UserId] = nil end)

print("✅ Demande de favori v2 chargée")
