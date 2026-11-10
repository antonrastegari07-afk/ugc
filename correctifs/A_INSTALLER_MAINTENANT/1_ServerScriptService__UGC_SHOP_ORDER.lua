--════════════════════════════════════════════════════════════════════════════
-- ↕️ UGC SHOP ORDER — SERVEUR
--  📍 Script (serveur) dans ServerScriptService. Nouveau fichier.
--
--  • Sauvegarde l'ordre du shop choisi dans le panneau admin (DataStore).
--  • Le publie à tous les joueurs via ReplicatedStorage.UGCShopOrder
--    (attributs Order / Version / By / At).
--  • Propage aux autres serveurs (MessagingService) + relecture toutes les 2 min.
--
--  ⚠️ Garde ADMIN_IDS identique à celui de AdminPanel_Server.
--════════════════════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")
local MessagingService  = game:GetService("MessagingService")

local ADMIN_IDS = {
	3203521470, 11017023724, 8456613930, 8142402169, 10420404767
}

local STORE_NAME = "UGCShopOrder_v1"
local STORE_KEY  = "order"
local TOPIC      = "UGCShopOrderChanged"
local RELOAD_EVERY = 120

local UGC_CONFIG = require(ReplicatedStorage:WaitForChild("UGC_CONFIG"))
local store = DataStoreService:GetDataStore(STORE_NAME)

local folder = ReplicatedStorage:FindFirstChild("UGCShopOrder") or Instance.new("Folder")
folder.Name = "UGCShopOrder"
folder.Parent = ReplicatedStorage

local remote = ReplicatedStorage:FindFirstChild("AdminSetShopOrder") or Instance.new("RemoteFunction")
remote.Name = "AdminSetShopOrder"
remote.Parent = ReplicatedStorage

local function isAdmin(userId)
	for _, id in ipairs(ADMIN_IDS) do
		if id == userId then return true end
	end
	return false
end

local function key(id)
	return string.format("%.0f", tonumber(id) or 0)
end

-- Ordre par défaut (Order ↓), même si le patch UGC_CONFIG n'est pas collé
local function defaultItems()
	local fn = UGC_CONFIG.GetDefaultSortedItems or UGC_CONFIG.GetSortedItems
	return fn()
end

-- Garde uniquement les ids qui existent dans UGC_CONFIG, sans doublon
local function sanitize(list)
	local valid = {}
	for _, it in ipairs(defaultItems()) do valid[key(it.AssetId)] = true end
	local out, seen = {}, {}
	if type(list) ~= "table" then return out end
	for _, id in ipairs(list) do
		local k = key(id)
		if valid[k] and not seen[k] then
			seen[k] = true
			table.insert(out, tonumber(k))
		end
	end
	return out
end

local function encode(ids)
	local parts = {}
	for i, id in ipairs(ids) do parts[i] = key(id) end
	return table.concat(parts, ",")
end

-- Ordre réellement affiché (ids non listés en premier, puis la liste)
local function effective(ids)
	local items
	if UGC_CONFIG.ApplyOrder then
		items = UGC_CONFIG.ApplyOrder(ids)
	else
		items = defaultItems()
	end
	local out = {}
	for i, it in ipairs(items) do out[i] = tonumber(key(it.AssetId)) end
	return out
end

local currentV = -1

local function applyRecord(rec)
	rec = type(rec) == "table" and rec or { ids = {}, v = 0 }
	local v = tonumber(rec.v) or 0
	if v < currentV then return false end
	currentV = v
	folder:SetAttribute("Order", encode(sanitize(rec.ids)))
	folder:SetAttribute("Version", v)
	folder:SetAttribute("By", rec.by and tostring(rec.by) or "")
	folder:SetAttribute("At", tonumber(rec.at) or 0)
	return true
end

-- ❤️ Réglages d'affichage du shop (clé séparée de l'ordre)
local SETTINGS_KEY = "settings"
local currentSV = -1

local function applySettings(rec)
	rec = type(rec) == "table" and rec or { v = 0 }
	local v = tonumber(rec.v) or 0
	if v < currentSV then return end
	currentSV = v
	folder:SetAttribute("ShowLikeCount", rec.showLikes == true)   -- défaut : caché
end
applySettings(nil)

-- 🆕 BADGES NEW (clé séparée) : liste d'assetIds publiée dans l'attribut « NewIds ».
--    Aucun enregistrement = attribut absent → le shop utilise IsNew de UGC_CONFIG.
local NEW_KEY = "newbadges"
local currentNV = -1
local function applyNew(rec)
	if type(rec) ~= "table" then return end
	local v = tonumber(rec.v) or 0
	if v < currentNV then return end
	currentNV = v
	folder:SetAttribute("NewIds", encode(sanitize(rec.ids)))
end
local function loadNew()
	local ok, rec = pcall(function() return store:GetAsync(NEW_KEY) end)
	if ok then applyNew(rec) else warn("[UGCShopOrder] lecture badges NEW échouée : " .. tostring(rec)) end
end
-- liste NEW actuelle (enregistrée, sinon celle de UGC_CONFIG)
local function currentNewIds()
	local s = folder:GetAttribute("NewIds")
	local out = {}
	if type(s) == "string" then
		for part in s:gmatch("[^,%s]+") do table.insert(out, tonumber(part)) end
	else
		for _, it in ipairs(UGC_CONFIG.Items) do
			if it.IsNew == true then table.insert(out, tonumber(key(it.AssetId))) end
		end
	end
	return out
end

local function loadSettings()
	local ok, rec = pcall(function() return store:GetAsync(SETTINGS_KEY) end)
	if ok then applySettings(rec) else warn("[UGCShopOrder] lecture réglages échouée : " .. tostring(rec)) end
end

local function loadFromStore()
	loadSettings()
	loadNew()
	for attempt = 1, 3 do
		local ok, rec = pcall(function() return store:GetAsync(STORE_KEY) end)
		if ok then
			applyRecord(rec)
			return true
		end
		warn("[UGCShopOrder] lecture DataStore échouée (" .. attempt .. "/3) : " .. tostring(rec))
		task.wait(2 * attempt)
	end
	return false
end

-- ── Cross-server : le message ne porte que la version (limite 1 Ko) ──
task.spawn(function()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(msg)
			local d = type(msg.Data) == "table" and msg.Data or {}
			local v = tonumber(d.v)
			if d.kind == "settings" then
				if v and v > currentSV then loadSettings() end
			elseif d.kind == "new" then
				if v and v > currentNV then loadNew() end
			elseif v and v > currentV then
				loadFromStore()
			end
		end)
	end)
	if not ok then warn("[UGCShopOrder] MessagingService indisponible : " .. tostring(err)) end
end)

-- ── Remote admin ──
local lastCall = {}

remote.OnServerInvoke = function(player, action, payload)
	if not isAdmin(player.UserId) then
		return { ok = false, msg = "🚫 Refusé : tu n'es pas admin." }
	end
	local now = os.clock()
	if lastCall[player.UserId] and now - lastCall[player.UserId] < 1 then
		return { ok = false, msg = "⏳ Doucement, réessaie dans une seconde." }
	end
	lastCall[player.UserId] = now

	if action == "get" then
		local custom = UGC_CONFIG.GetCustomOrder and UGC_CONFIG.GetCustomOrder() or nil
		return { ok = true, order = effective(sanitize(custom)) }
	end

	-- 🆕 cocher / décocher le badge NEW d'un UGC (enregistré tout de suite, tous les serveurs)
	if action == "setnew" then
		local id = type(payload) == "table" and tonumber(payload.assetId) or nil
		local on = type(payload) == "table" and payload.on == true
		if not id or #sanitize({ id }) == 0 then return { ok = false, msg = "UGC inconnu." } end
		local k = key(id)
		local saved
		local ok, err = pcall(function()
			store:UpdateAsync(NEW_KEY, function(old)
				local base = (type(old) == "table" and type(old.ids) == "table") and old.ids or currentNewIds()
				local ids, seen = {}, {}
				for _, x in ipairs(base) do
					local kx = key(x)
					if kx ~= k and not seen[kx] then seen[kx] = true; table.insert(ids, tonumber(kx)) end
				end
				if on then table.insert(ids, 1, tonumber(k)) end
				local v = (type(old) == "table" and tonumber(old.v) or 0) + 1
				saved = { ids = ids, v = v, by = player.Name, at = os.time() }
				return saved
			end)
		end)
		if not ok or not saved then
			return { ok = false, msg = "❌ Sauvegarde impossible : " .. tostring(err) }
		end
		applyNew(saved)
		task.spawn(function()
			pcall(function() MessagingService:PublishAsync(TOPIC, { kind = "new", v = saved.v }) end)
		end)
		return { ok = true, msg = on and "🆕 Badge NEW affiché" or "Badge NEW retiré", on = on }
	end

	if action == "likes" then
		local show = type(payload) == "table" and payload.show == true
		local saved
		local ok, err = pcall(function()
			store:UpdateAsync(SETTINGS_KEY, function(old)
				local v = (type(old) == "table" and tonumber(old.v) or 0) + 1
				saved = { v = v, showLikes = show, by = player.Name, at = os.time() }
				return saved
			end)
		end)
		if not ok or not saved then
			return { ok = false, msg = "❌ Sauvegarde impossible : " .. tostring(err) }
		end
		applySettings(saved)
		task.spawn(function()
			pcall(function() MessagingService:PublishAsync(TOPIC, { kind = "settings", v = saved.v }) end)
		end)
		return { ok = true, msg = show and "❤️ Nombre de likes affiché" or "🔇 Nombre de likes caché", show = show }
	end

	local ids
	if action == "set" then
		ids = sanitize(type(payload) == "table" and payload.order or nil)
		if #ids == 0 then return { ok = false, msg = "Liste vide." } end
	elseif action == "reset" then
		ids = {}
	else
		return { ok = false, msg = "Action inconnue." }
	end

	local saved
	local ok, err = pcall(function()
		store:UpdateAsync(STORE_KEY, function(old)
			local v = (type(old) == "table" and tonumber(old.v) or 0) + 1
			saved = { ids = ids, v = v, by = player.Name, bi = player.UserId, at = os.time() }
			return saved
		end)
	end)
	if not ok or not saved then
		return { ok = false, msg = "❌ Sauvegarde impossible : " .. tostring(err) }
	end

	applyRecord(saved)
	task.spawn(function()
		pcall(function() MessagingService:PublishAsync(TOPIC, { v = saved.v }) end)
	end)

	return {
		ok = true,
		msg = (action == "reset") and "♻️ Ordre par défaut rétabli" or "💾 Ordre du shop enregistré",
		order = effective(ids),
		v = saved.v,
	}
end

Players.PlayerRemoving:Connect(function(p) lastCall[p.UserId] = nil end)

-- ── Démarrage + relecture périodique (filet de sécurité) ──
loadFromStore()
task.spawn(function()
	while true do
		task.wait(RELOAD_EVERY)
		loadFromStore()
	end
end)

print("✅ UGCShopOrder_Server prêt")