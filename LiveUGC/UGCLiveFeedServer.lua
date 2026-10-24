--════════════════════════════════════════════════════════════
-- 📡 UGC LIVE FEED — SERVEUR
-- 📍 ServerScriptService > UGCLiveFeedServer (Script)
--
-- Alimente le board « LIVE UGC REDEEMS » : les derniers UGC récupérés,
-- QUI les a récupérés et QUOI (avec l'image). Aucune heure n'est envoyée.
--
-- Branché sur le UGC REDEEM LOG via UNE ligne (voir README) :
--     if _G.UGCLiveFeed_Push then task.spawn(_G.UGCLiveFeed_Push, entry) end
--
-- 💾 Coût : 1 UpdateAsync + 1 PublishAsync par redeem (rare).
--    Live inter-serveurs via MessagingService, filet de sécurité :
--    relecture du DataStore toutes les RESYNC_INTERVAL secondes.
--════════════════════════════════════════════════════════════
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local DataStoreService   = game:GetService("DataStoreService")
local MessagingService   = game:GetService("MessagingService")
local HttpService        = game:GetService("HttpService")

-- 🔧 RÉGLAGES
local MAX_FEED         = 25      -- nombre de redeems gardés / affichés
local RESYNC_INTERVAL  = 180     -- s entre deux relectures du DataStore
local USE_CONFIG_IMAGE = false   -- true = ImageId du UGC_CONFIG, false = miniature catalogue Roblox
-- Voies qui n'apparaissent PAS sur le board public
local HIDDEN_SOURCES = {
	exploit  = true,   -- anti-exploit : jamais public
	external = true,   -- audit de possession : pas un vrai redeem en jeu
}

local UGC_CONFIG = require(ReplicatedStorage:WaitForChild("UGC_CONFIG"))

local FEED_STORE = DataStoreService:GetDataStore("UGCLiveFeed_v1")
local FEED_KEY   = "feed"
local TOPIC      = "UGCLiveFeed_v1"

local function mk(name, class)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new(class); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end
local getFeed = mk("GetUGCLiveFeed", "RemoteFunction")
local newEvt  = mk("UGCLiveFeedNew", "RemoteEvent")

-- ── état mémoire ──
local feed = {}   -- plus récent en premier : { id, u, n, a, an }
local seen = {}   -- [id] = true

-- ════════════════════════════════════════════════════════════
-- FORMAT
-- ════════════════════════════════════════════════════════════
local function imageFor(assetId)
	if USE_CONFIG_IMAGE then
		local cfg = UGC_CONFIG.GetByAssetId(assetId)
		local img = cfg and cfg.ImageId
		if type(img) == "string" and img:find("://") then return img end
		if tonumber(img) then return "rbxassetid://" .. tonumber(img) end
	end
	return string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", assetId)
end

-- Ce que le client reçoit : PAS d'heure, pas de prix, pas de source.
local function toClient(e)
	return { id = e.id, u = e.u, n = e.n, a = e.a, an = e.an, img = imageFor(e.a) }
end

local function clientList()
	local out = {}
	for i, e in ipairs(feed) do out[i] = toClient(e) end
	return out
end

local function valid(e)
	return type(e) == "table" and type(e.id) == "string"
		and tonumber(e.u) and tonumber(e.a)
end

local function sanitize(e)
	return {
		id = e.id, u = tonumber(e.u), a = tonumber(e.a),
		n  = tostring(e.n or ("Player_" .. tostring(e.u))),
		an = tostring(e.an or ("UGC " .. tostring(e.a))),
	}
end

-- ════════════════════════════════════════════════════════════
-- FEED LOCAL
-- ════════════════════════════════════════════════════════════
local function addLocal(item)
	if seen[item.id] then return false end
	seen[item.id] = true
	table.insert(feed, 1, item)
	while #feed > MAX_FEED do
		local r = table.remove(feed)
		seen[r.id] = nil
	end
	newEvt:FireAllClients(toClient(item))
	return true
end

local function signature(list)
	local parts = {}
	for i, e in ipairs(list) do parts[i] = e.id end
	return table.concat(parts, "|")
end

-- Relit le DataStore : rattrape un message MessagingService perdu.
-- Les items locaux pas encore écrits (écriture en vol) restent en tête.
local function resync(broadcast)
	local ok, data = pcall(function() return FEED_STORE:GetAsync(FEED_KEY) end)
	if not ok or type(data) ~= "table" then return false end

	local merged, ids = {}, {}
	local stored = {}
	for _, e in ipairs(data) do
		if valid(e) then stored[e.id] = true end
	end
	for _, e in ipairs(feed) do
		if not stored[e.id] and not ids[e.id] then
			ids[e.id] = true
			table.insert(merged, e)
		end
	end
	for _, e in ipairs(data) do
		if valid(e) and not ids[e.id] then
			ids[e.id] = true
			table.insert(merged, sanitize(e))
		end
	end
	while #merged > MAX_FEED do table.remove(merged) end

	if signature(merged) == signature(feed) then return true end
	feed, seen = merged, ids
	if broadcast then newEvt:FireAllClients({ full = clientList() }) end
	return true
end

local function persist(item)
	pcall(function()
		FEED_STORE:UpdateAsync(FEED_KEY, function(old)
			if type(old) ~= "table" then old = {} end
			for _, e in ipairs(old) do
				if type(e) == "table" and e.id == item.id then return nil end
			end
			table.insert(old, 1, item)
			while #old > MAX_FEED do table.remove(old) end
			return old
		end)
	end)
end

-- ════════════════════════════════════════════════════════════
-- 🔌 API (appelée par le UGC REDEEM LOG)
-- ════════════════════════════════════════════════════════════
local function resolveName(userId, entry)
	if entry and entry.d then return entry.d end
	local pl = Players:GetPlayerByUserId(userId)
	if pl then return pl.DisplayName end
	-- ⚠️ entry.n peut contenir le nom du UGC quand le joueur est parti :
	--    on ne s'y fie pas, on demande à Roblox.
	local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	return (ok and name) or ("Player_" .. userId)
end

_G.UGCLiveFeed_Push = function(entry, opts)
	if type(entry) ~= "table" then return end
	if HIDDEN_SOURCES[tostring(entry.s)] then return end
	local uid, aid = tonumber(entry.u), tonumber(entry.a)
	if not uid or not aid then return end
	opts = opts or {}

	local item = {
		id = entry.id or HttpService:GenerateGUID(false),
		u  = uid,
		n  = resolveName(uid, entry),
		a  = aid,
		an = entry.an or ("UGC " .. aid),
	}
	if not addLocal(item) then return end
	if opts.localOnly then return end

	persist(item)
	pcall(function() MessagingService:PublishAsync(TOPIC, item) end)
end

-- 🗑️ Retire un redeem du board (ex: test, erreur)
_G.UGCLiveFeed_Remove = function(id)
	for i = #feed, 1, -1 do
		if feed[i].id == id then table.remove(feed, i) end
	end
	seen[id] = nil
	pcall(function()
		FEED_STORE:UpdateAsync(FEED_KEY, function(old)
			if type(old) ~= "table" then return nil end
			for i = #old, 1, -1 do
				if type(old[i]) == "table" and old[i].id == id then table.remove(old, i) end
			end
			return old
		end)
	end)
	newEvt:FireAllClients({ full = clientList() })
end

-- 🧹 Vide complètement le board (ce serveur ; les autres au prochain resync)
_G.UGCLiveFeed_Clear = function()
	feed, seen = {}, {}
	pcall(function() FEED_STORE:SetAsync(FEED_KEY, {}) end)
	newEvt:FireAllClients({ full = {} })
	print("🧹 UGC Live Feed vidé")
end

-- 🧪 Test en Studio : _G.UGCLiveFeed_Test()  (n'écrit rien, ce serveur seulement)
_G.UGCLiveFeed_Test = function(userId, assetId)
	local pl = Players:GetPlayers()[1]
	userId = tonumber(userId) or (pl and pl.UserId) or 1
	local items = UGC_CONFIG.Items or {}
	local cfg = assetId and UGC_CONFIG.GetByAssetId(tonumber(assetId))
		or items[math.random(1, math.max(1, #items))]
	if not cfg then warn("UGC_CONFIG vide"); return end
	_G.UGCLiveFeed_Push({
		u = userId, a = cfg.AssetId, an = cfg.Name, s = "test",
	}, { localOnly = true })
	print("🧪 Redeem de test envoyé : " .. tostring(cfg.Name))
end

-- ════════════════════════════════════════════════════════════
-- REMOTES / LIVE INTER-SERVEURS
-- ════════════════════════════════════════════════════════════
getFeed.OnServerInvoke = function()
	return clientList()
end

task.spawn(function()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(msg)
			local e = msg and msg.Data
			if valid(e) then addLocal(sanitize(e)) end
		end)
	end)
	if not ok then warn("⚠️ UGC Live Feed : MessagingService indisponible (" .. tostring(err) .. ")") end
end)

task.spawn(function()
	for attempt = 1, 3 do
		if resync(true) then break end
		task.wait(5 * attempt)
	end
	while true do
		task.wait(RESYNC_INTERVAL)
		resync(true)
	end
end)

print("✅ UGC LIVE FEED chargé | test : _G.UGCLiveFeed_Test()")
