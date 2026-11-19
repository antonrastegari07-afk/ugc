--════════════════════════════════════════════════════════════════════════════
-- 👥 FriendsBoard_Server — Script dans ServerScriptService   (NOUVEAU)
--
--  Onglet FRIENDS des leaderboards : donne le score des amis qui ne sont PAS
--  dans le top 100 (ils s'affichent avec « -- » à la place de leur rang).
--
--  Lecture seule, dans les MÊMES classements que les boards (OrderedDataStore,
--  clé = UserId). Garde-fous :
--   • 🔒 SEULEMENT tes VRAIS amis (liste demandée à Roblox par le serveur, gardée
--     10 min) + toi : un tricheur ne peut pas faire lire des milliers de joueurs
--     au hasard pour épuiser le budget DataStore du serveur ;
--   • 50 amis max par demande, 1 demande / 3 s par joueur, et 300 lectures
--     au maximum par joueur toutes les 10 min ;
--   • cache serveur de 5 min PARTAGÉ (les amis communs ne sont lus qu'une fois) ;
--   • si le budget de lectures DataStore est bas, on s'arrête (le client affiche « -- »).
--════════════════════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STORES = {   -- même nom que dans « Leaderboards unifed » et « new donation board server »
	Points    = "GlobalLeaderboard_Points_v3",
	Rebirths  = "GlobalLeaderboard_Rebirths_v1",
	Streak    = "GlobalLeaderboard_Streak_v1",
	Kills     = "GlobalLeaderboard_Kills_v1",
	Donations = "TopDonatorsLeaderboard",
}
local MAX_IDS      = 50
local CACHE_TTL    = 300
local COOLDOWN     = 3
local MIN_BUDGET   = 25   -- on laisse toujours ce nombre de lectures aux autres scripts
local FRIENDS_TTL  = 600  -- liste d'amis gardée 10 min
local QUOTA, QUOTA_WINDOW = 300, 600   -- lectures DataStore max par joueur / fenêtre (s)

local stores, cache = {}, {}
for k, name in pairs(STORES) do
	stores[k] = DataStoreService:GetOrderedDataStore(name)
	cache[k] = {}
end
local lastCall = {}
local friendsOf = {}   -- [userId] = { set = { [id] = true }, at = os.clock() }
local quota = {}       -- [userId] = { n = lectures, t0 = début de fenêtre }

-- 👥 vrais amis du joueur, demandés à Roblox par le SERVEUR (jamais la liste du client)
local function friendSet(player)
	local uid = player.UserId
	local c = friendsOf[uid]
	if c and os.clock() - c.at < FRIENDS_TTL then return c.set end
	local set = { [uid] = true }
	local ok = pcall(function()
		local pages = Players:GetFriendsAsync(uid)
		for _ = 1, 10 do   -- 10 pages max (Roblox : 200 amis au maximum)
			for _, f in ipairs(pages:GetCurrentPage()) do set[f.Id] = true end
			if pages.IsFinished then break end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if ok then friendsOf[uid] = { set = set, at = os.clock() }
	elseif c then return c.set end   -- Roblox injoignable : on garde l'ancienne liste
	return set
end

local remote = ReplicatedStorage:FindFirstChild("GetFriendsBoardValues")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "GetFriendsBoardValues"
	remote.Parent = ReplicatedStorage
end

local function budget()
	local ok, b = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return ok and b or 0
end

remote.OnServerInvoke = function(player, board, ids)
	if type(board) ~= "string" or not stores[board] or type(ids) ~= "table" then return {} end
	local now = os.clock()
	if lastCall[player.UserId] and now - lastCall[player.UserId] < COOLDOWN then return { throttled = true } end
	lastCall[player.UserId] = now

	local friends = friendSet(player)
	local out, need, seen = {}, {}, {}
	for i = 1, math.min(#ids, MAX_IDS) do
		local id = tonumber(ids[i])
		if id and id > 0 and id == math.floor(id) and not seen[id] and friends[id] then
			seen[id] = true
			local c = cache[board][id]
			if c and now - c.at < CACHE_TTL then out[tostring(id)] = c.v
			else table.insert(need, id) end
		end
	end
	local store = stores[board]
	local q = quota[player.UserId]
	if not q or os.clock() - q.t0 > QUOTA_WINDOW then q = { n = 0, t0 = os.clock() } ; quota[player.UserId] = q end
	for _, id in ipairs(need) do
		if budget() < MIN_BUDGET or q.n >= QUOTA then break end
		q.n += 1
		local ok, v = pcall(function() return store:GetAsync(tostring(id)) end)
		if ok then
			v = tonumber(v) or 0
			cache[board][id] = { v = v, at = os.clock() }
			out[tostring(id)] = v
		end
	end
	return out
end

Players.PlayerRemoving:Connect(function(p)
	lastCall[p.UserId], friendsOf[p.UserId], quota[p.UserId] = nil, nil, nil
end)

-- ménage du cache (les entrées expirées ne servent plus)
task.spawn(function()
	while true do
		task.wait(600)
		local now = os.clock()
		for _, t in pairs(cache) do
			for id, c in pairs(t) do if now - c.at > CACHE_TTL then t[id] = nil end end
		end
	end
end)
