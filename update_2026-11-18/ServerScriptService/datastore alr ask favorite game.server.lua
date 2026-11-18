-- ════════════════════════════════════════════════════════════════════════
-- ⭐ FAVORI D'OBJET (asset 107795556034608) — Script ServerScriptService (remplace tout)  v2
--   Va avec StarterCharacterScripts ▸ « ask favorite game » (demande UNE seule fois à vie).
--
--   🩹 AVANT : chaque appel du client = 1 lecture DataStore, sans limite.
--      Le LocalScript tourne à CHAQUE réapparition → une lecture par vie, et un
--      client tricheur pouvait vider le budget DataStore du serveur en boucle.
--   ✅ MAINTENANT : 1 lecture max par session (résultat gardé en mémoire),
--      1 écriture max par session, et 1 appel / 2 s par joueur.
-- ════════════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local favoriteDataStore = DataStoreService:GetDataStore("FavoritePromptData")
local DATASTORE_KEY = "FavoritePrompted_"

local function mk(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local checkFavoritePrompted = mk("CheckFavoritePrompted")
local saveFavoritePrompted = mk("SaveFavoritePrompted")

local prompted = {}   -- [userId] = true / false (lu une fois par session)
local reading = {}
local lastCall = {}

local function throttled(uid)
	local now = os.clock()
	if lastCall[uid] and now - lastCall[uid] < 2 then return true end
	lastCall[uid] = now
	return false
end

-- Déjà demandé ? (true = ne rien faire)
checkFavoritePrompted.OnServerInvoke = function(player)
	local uid = player.UserId
	if prompted[uid] ~= nil then return prompted[uid] end
	if throttled(uid) or reading[uid] then return true end   -- dans le doute : ne pas demander
	reading[uid] = true
	local ok, data = pcall(function()
		return favoriteDataStore:GetAsync(DATASTORE_KEY .. uid)
	end)
	reading[uid] = nil
	if not ok then return true end
	prompted[uid] = (data == true)
	return prompted[uid]
end

-- La demande a été affichée : on ne la refera plus jamais
saveFavoritePrompted.OnServerInvoke = function(player)
	local uid = player.UserId
	if prompted[uid] == true then return true end   -- déjà enregistré : aucune écriture
	if throttled(uid) then return false end
	prompted[uid] = true
	local ok = pcall(function()
		favoriteDataStore:SetAsync(DATASTORE_KEY .. uid, true)
	end)
	return ok
end

Players.PlayerRemoving:Connect(function(p)
	prompted[p.UserId] = nil
	reading[p.UserId] = nil
	lastCall[p.UserId] = nil
end)
