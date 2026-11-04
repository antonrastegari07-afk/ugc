--════════════════════════════════════════════════════════════════════════════
-- 👤 PUBLIC PROFILE — SERVEUR
--  📍 Script (serveur) dans ServerScriptService. Nouveau fichier.
--
--  Donne à la fiche profil les stats d'un joueur qui n'est PAS sur ce serveur
--  (fiche ouverte depuis un leaderboard). Lecture seule, et uniquement des
--  valeurs déjà publiques : ce que tes leaderboards affichent déjà.
--    points · rebirths · streak · kills · points offerts en gift · 🏆 wins d'arène
--    ⚡ boost (x2.20…) : le même que sur son billboard, mémorisé quand il
--      joue (DataStore PublicBoost_v1) pour être visible même hors ligne.
--
--  Aucune donnée sensible (bans, warnings, anticheat, Robux dépensés…).
--  Cache 60 s par joueur + 1 appel / 0,5 s par joueur qui demande.
--════════════════════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STORES = {
	points    = "GlobalLeaderboard_Points_v3",
	rebirths  = "GlobalLeaderboard_Rebirths_v1",
	streak    = "GlobalLeaderboard_Streak_v1",
	kills     = "TotalKills_v1",
	boardKills = "GlobalLeaderboard_Kills_v1",   -- repli si TotalKills est vide
	gifted    = "GiftTop_SentPts_v1",
	wins      = "ArenaWins_v1",   -- 🏆 manches PvP gagnées (écrit par CombatServer, même nom que CombatSettings.RoundWinner.WinsStore)
}
local CACHE_TTL = 60

local handles = {}
for k, name in pairs(STORES) do handles[k] = DataStoreService:GetOrderedDataStore(name) end

--══════════════════════════════════════════════════════════════════
-- ⚡ BOOST MÉMORISÉ
--   Le billboard lit l'attribut PointsMultiplier (posé par ton script de
--   points). On l'écrit ici toutes les 10 min, SEULEMENT s'il a changé
--   depuis la dernière écriture. Rien au leave, rien au shutdown : le boost
--   change très rarement, et tes requêtes de départ restent intactes.
--══════════════════════════════════════════════════════════════════
local boostStore = DataStoreService:GetDataStore("PublicBoost_v1")
local BOOST_SAVE_EVERY = 600
local boostWritten = {}   -- [userId] = dernière valeur écrite

local function saveBoost(player)
	local m = player:GetAttribute("PointsMultiplier")
	if type(m) ~= "number" or m <= 0 then return end
	m = math.floor(m * 100 + 0.5) / 100
	local uid = player.UserId
	if boostWritten[uid] == m then return end
	boostWritten[uid] = m
	task.spawn(function()
		local ok = pcall(function()
			boostStore:SetAsync(tostring(uid), { m = m, t = os.time() })
		end)
		if not ok then boostWritten[uid] = nil end   -- on réessaiera
	end)
end

task.spawn(function()
	while true do
		task.wait(BOOST_SAVE_EVERY)
		for _, p in ipairs(Players:GetPlayers()) do
			saveBoost(p)
			task.wait(0.2)
		end
	end
end)

--══════════════════════════════════════════════════════════════════
-- 🏅 BADGES DU PROFIL : 👑 VIP + ⚡ boosts PERMANENTS x2 / x5 / x10
--   Un boost compte qu'il soit ACHETÉ (gamepass) ou OFFERT (cadeau, admin).
--   Le VIP compte qu'il soit acheté ou offert.
--   Calculé ici, côté serveur : avant, la fiche ne regardait que les
--   gamepass, depuis le client → les boosts offerts n'apparaissaient jamais.
--   • joueurs connectés : attribut "ProfileBadges" = "vip,2,5,10"
--   • hors ligne : champs isVip / b2 / b5 / b10 de GetPublicProfile
--══════════════════════════════════════════════════════════════════
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage      = game:GetService("ServerStorage")
local cache, busy, last = {}, {}, {}
local BADGE = {
	passes = { [1891007119] = 2, [1893682680] = 5, [1891475116] = 10 },   -- mêmes IDs que ton script time
	vipPass = 1891589121,
	own = {},   -- [uid] = { t, set = { [passId] = bool } } : 5 min
}
function BADGE.owns(uid, id)
	local c = BADGE.own[uid]
	if not c or os.clock() - c.t > 300 then c = { t = os.clock(), set = {} } ; BADGE.own[uid] = c end
	if c.set[id] == nil then
		local ok, r = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(uid, id) end)
		if not ok then return false end   -- lecture ratée : on réessaiera au prochain calcul
		c.set[id] = r == true
	end
	return c.set[id]
end
function BADGE.of(uid)
	local b = { vip = false, [2] = false, [5] = false, [10] = false }
	if _G.IsVIP then
		local ok, v = pcall(_G.IsVIP, uid)
		if ok and v == true then b.vip = true end
	end
	if not b.vip and BADGE.owns(uid, BADGE.vipPass) then b.vip = true end
	for id, m in pairs(BADGE.passes) do
		if BADGE.owns(uid, id) then b[m] = true end
	end
	--  boosts permanents OFFERTS (_PermBoosts.server)
	if _G.PermBoosts and _G.PermBoosts.peek then
		local ok, l = pcall(_G.PermBoosts.peek, uid)
		if ok and type(l) == "table" then
			for _, m in ipairs(l) do
				if b[tonumber(m)] ~= nil then b[tonumber(m)] = true end
			end
		end
	end
	return b
end
function BADGE.publish(p)
	if not (p and p.Parent) then return end
	local b = BADGE.of(p.UserId)
	local t = {}
	if b.vip then table.insert(t, "vip") end
	for _, m in ipairs({ 2, 5, 10 }) do if b[m] then table.insert(t, tostring(m)) end end
	if p.Parent then p:SetAttribute("ProfileBadges", table.concat(t, ",")) end
end
Players.PlayerAdded:Connect(function(p)
	task.delay(6, BADGE.publish, p)    -- après le chargement du VIP et des boosts
	task.delay(45, BADGE.publish, p)   -- 2e passage si un DataStore était lent
end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(BADGE.publish, p) end
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p, id, bought)
	if bought and (BADGE.passes[id] or id == BADGE.vipPass) then
		local c = BADGE.own[p.UserId]
		if c then c.set[id] = true end
		BADGE.publish(p)
	end
end)
--  boost offert / VIP donné ou retiré → mis à jour tout de suite
for _, evName in ipairs({ "PermBoostChanged", "VIPStatusChanged" }) do
	task.spawn(function()
		local ev = ServerStorage:WaitForChild(evName, 60)
		if not ev then return end
		ev.Event:Connect(function(uid)
			local p = Players:GetPlayerByUserId(tonumber(uid) or 0)
			if p then
				cache[p.UserId] = nil
				task.delay(1, BADGE.publish, p)
			end
		end)
	end)
end
Players.PlayerRemoving:Connect(function(p) BADGE.own[p.UserId] = nil end)

local remote = ReplicatedStorage:FindFirstChild("GetPublicProfile") or Instance.new("RemoteFunction")
remote.Name = "GetPublicProfile"
remote.Parent = ReplicatedStorage


local function read(uid)
	local hit = cache[uid]
	if hit and os.clock() - hit.t < CACHE_TTL then return hit.data end
	if busy[uid] then
		local t0 = os.clock()
		while busy[uid] and os.clock() - t0 < 8 do task.wait(0.05) end
		hit = cache[uid]
		return hit and hit.data or nil
	end
	busy[uid] = true

	local out, pending = {}, 0
	for k, store in pairs(handles) do
		pending += 1
		task.spawn(function()
			local ok, v = pcall(function() return store:GetAsync(tostring(uid)) end)
			if ok and type(v) == "number" then out[k] = v end
			pending -= 1
		end)
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 8 do task.wait(0.05) end

	-- ⚡ boost mémorisé (DataStore normal, lu à part)
	pending += 1
	task.spawn(function()
		local ok, v = pcall(function() return boostStore:GetAsync(tostring(uid)) end)
		if ok and type(v) == "table" and type(v.m) == "number" then
			out.boost, out.boostAt = v.m, tonumber(v.t)
		end
		pending -= 1
	end)
	t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 8 do task.wait(0.05) end

	--  🏅 badges (VIP + boosts permanents achetés OU offerts)
	local okB, b = pcall(BADGE.of, uid)
	if okB and type(b) == "table" then
		out.isVip = b.vip and 1 or 0
		out.b2, out.b5, out.b10 = b[2] and 1 or 0, b[5] and 1 or 0, b[10] and 1 or 0
	end

	if not out.kills and out.boardKills then out.kills = out.boardKills end
	out.boardKills = nil

	cache[uid] = { t = os.clock(), data = out }
	busy[uid] = nil
	return out
end

remote.OnServerInvoke = function(player, userId)
	userId = tonumber(userId)
	if not userId or userId <= 0 or userId ~= math.floor(userId) then return nil end
	local now = os.clock()
	if last[player.UserId] and now - last[player.UserId] < 0.5 then return { throttled = true } end
	last[player.UserId] = now
	return read(userId)
end

Players.PlayerRemoving:Connect(function(p)
	last[p.UserId] = nil
	boostWritten[p.UserId] = nil   -- mémoire seulement : aucune requête au leave
end)

--══════════════════════════════════════════════════════════════════
-- 🎽 UGC RÉCUPÉRÉS (section en bas de la fiche profil)
--   Lu dans ton UGCRedeemLog_Server via _G.UGCRedeem_GetPlayer (même
--   fiche que ton admin panel). On ne renvoie que ce qui est public :
--   l'UGC et son image. Jamais la date, la source, le prix payé, ni les
--   lignes « exploit / hors shop ».
--══════════════════════════════════════════════════════════════════
-- 🔘 true = la section « UGC Redeemed » s'affiche dans les fiches profil
--    false = section cachée pour tout le monde (et plus aucune donnée envoyée)
local SHOW_UGC_REDEEMED = true

local UGC_CFG
pcall(function() UGC_CFG = require(ReplicatedStorage:WaitForChild("UGC_CONFIG", 10)) end)
local HIDDEN_SRC = { exploit = true, external = true }

local ugcRemote = ReplicatedStorage:FindFirstChild("GetPublicUGCs") or Instance.new("RemoteFunction")
ugcRemote.Name = "GetPublicUGCs"
ugcRemote.Parent = ReplicatedStorage
ugcRemote:SetAttribute("Enabled", SHOW_UGC_REDEEMED)   -- lu par la fiche profil

local ugcCache, ugcLast = {}, {}

local function cfgItem(assetId)
	if not UGC_CFG or type(UGC_CFG.Items) ~= "table" then return nil end
	for _, it in pairs(UGC_CFG.Items) do
		if type(it) == "table" and tostring(it.AssetId) == tostring(assetId) then return it end
	end
	return nil
end

local function readUGCs(uid)
	local hit = ugcCache[uid]
	if hit and os.clock() - hit.t < CACHE_TTL then return hit.data end
	if type(_G.UGCRedeem_GetPlayer) ~= "function" then return { ok = false } end

	local ok, rec = pcall(function() return _G.UGCRedeem_GetPlayer(uid) end)
	if not ok then return { ok = false } end

	local list = {}
	if type(rec) == "table" and type(rec.it) == "table" then
		for _, e in ipairs(rec.it) do          -- du plus ancien au plus récent
			if type(e) == "table" and e.a and not HIDDEN_SRC[tostring(e.s)] then
				local c = cfgItem(e.a)
				local img
				if c and c.ImageId then
					img = tostring(c.ImageId)
					if not img:find("://") then img = "rbxassetid://" .. img end
				else
					img = "rbxthumb://type=Asset&id=" .. tostring(e.a) .. "&w=150&h=150"
				end
				table.insert(list, {
					n   = tostring((c and c.Name) or e.an or "UGC"),
					img = img,
				})
			end
		end
	end
	local out = { ok = true, list = list, total = type(rec) == "table" and tonumber(rec.c) or #list }
	ugcCache[uid] = { t = os.clock(), data = out }
	return out
end

ugcRemote.OnServerInvoke = function(player, userId)
	if not SHOW_UGC_REDEEMED then return { ok = false, disabled = true } end
	userId = tonumber(userId)
	if not userId or userId <= 0 or userId ~= math.floor(userId) then return nil end
	local now = os.clock()
	if ugcLast[player.UserId] and now - ugcLast[player.UserId] < 0.5 then return { throttled = true } end
	ugcLast[player.UserId] = now
	return readUGCs(userId)
end

Players.PlayerRemoving:Connect(function(p) ugcLast[p.UserId] = nil end)

-- ménage du cache
task.spawn(function()
	while true do
		task.wait(300)
		for uid, hit in pairs(cache) do
			if os.clock() - hit.t > CACHE_TTL then cache[uid] = nil end
		end
		for uid, c in pairs(BADGE.own) do
			if os.clock() - c.t > 300 and not Players:GetPlayerByUserId(uid) then BADGE.own[uid] = nil end
		end
		for uid, hit in pairs(ugcCache) do
			if os.clock() - hit.t > CACHE_TTL then ugcCache[uid] = nil end
		end
	end
end)