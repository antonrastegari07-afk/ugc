--════════════════════════════════════════════════════════════════════════════
-- 🟢 Presence_Server — Script dans ServerScriptService   (NOUVEAU)
--
--  Sert la fiche profil (visible par tout le monde) : 🟢 Online / ⚫ Offline,
--  même si le joueur est sur un AUTRE serveur.
--
--  Comment : chaque serveur note ses joueurs en ligne dans une MemoryStore
--  (pas un DataStore : rien n'est sauvegardé à vie). Une écriture par joueur
--  et par minute, avec une expiration de 150 s : un joueur qui part ou un
--  serveur qui plante disparaît tout seul.
--  Lecture : 1 appel / 1,5 s par joueur (protège le quota MemoryStore du jeu),
--  résultat gardé 15 s. Un vrai joueur ouvre une fiche à la fois : il ne voit rien.
--════════════════════════════════════════════════════════════════════════════
local Players            = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")

local map = MemoryStoreService:GetSortedMap("OnlinePresence_v1")
local TTL, REFRESH = 150, 60
local IS_STUDIO = RunService:IsStudio()

local function mark(p)
	if IS_STUDIO then return end
	pcall(function() map:SetAsync(tostring(p.UserId), 1, TTL) end)
end

Players.PlayerAdded:Connect(mark)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(mark, p) end
Players.PlayerRemoving:Connect(function(p)
	if IS_STUDIO then return end
	task.spawn(function() pcall(function() map:RemoveAsync(tostring(p.UserId)) end) end)
end)
-- rafraîchissement, étalé sur la minute (pas tout le monde à la même seconde)
task.spawn(function()
	while true do
		task.wait(REFRESH)
		local list = Players:GetPlayers()
		local gap = #list > 0 and math.min(1, (REFRESH * 0.8) / #list) or 1
		for _, p in ipairs(list) do
			if p.Parent then mark(p) end
			task.wait(gap)
		end
	end
end)

local remote = ReplicatedStorage:FindFirstChild("GetPlayerPresence")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "GetPlayerPresence"
	remote.Parent = ReplicatedStorage
end
local cache, last = {}, {}
remote.OnServerInvoke = function(player, userId)
	userId = tonumber(userId)
	if not userId or userId <= 0 or userId ~= math.floor(userId) then return nil end
	if Players:GetPlayerByUserId(userId) then return "here" end
	local now = os.clock()
	local c = cache[userId]
	if c and now - c.at < 15 then return c.v end
	if last[player.UserId] and now - last[player.UserId] < 1.5 then return nil end   -- quota MemoryStore protégé
	last[player.UserId] = now
	local ok, v = pcall(function() return map:GetAsync(tostring(userId)) end)
	if not ok then return nil end
	local res = (v ~= nil) and "online" or "offline"
	cache[userId] = { v = res, at = now }
	return res
end
Players.PlayerRemoving:Connect(function(p) last[p.UserId] = nil end)
task.spawn(function()
	while true do
		task.wait(120)
		local now = os.clock()
		for id, c in pairs(cache) do if now - c.at > 30 then cache[id] = nil end end
	end
end)
