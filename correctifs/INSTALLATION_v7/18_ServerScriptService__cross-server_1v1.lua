-- ServerBrowserServer (ServerScriptService)
-- Registre cross-server (MemoryStore) + liste + join (téléport) + arrivée en arène

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local serverRegion       = "…"   -- résolu une fois au démarrage

local PLACE_ID = game.PlaceId
local JOB_ID   = game.JobId

-- === Config ===
local MAP_NAME      = "ArenaServers_v1"
local HEARTBEAT     = 10   -- publie l'état toutes les X s
local ENTRY_TTL     = 30   -- l'entrée expire si pas refresh (doit être > HEARTBEAT)
local MAX_AVATARS   = 15   -- nb d'avatars stockés par serveur
local LIST_LIMIT    = 100  -- nb max de serveurs renvoyés
local CACHE_TTL     = 3    -- cache serveur pour limiter les lectures MemoryStore
local JOIN_COOLDOWN = 3

local serverMap = MemoryStoreService:GetSortedMap(MAP_NAME)

-- === Remotes ===
local function ensureRemote(class, name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local getServersFn    = ensureRemote("RemoteFunction", "GetArenaServers")
local joinServerEvent = ensureRemote("RemoteEvent",    "JoinArenaServer")
local joinFailedEvent = ensureRemote("RemoteEvent",    "ArenaJoinFailed")

-- 🆕 config des maps (pour MapImage / MapName par serveur)
local MapConfig = require(ReplicatedStorage:WaitForChild("MapConfig"))

_G.PlayersInArena = _G.PlayersInArena or {}

-- === Lister les joueurs en arène de CE serveur ===
local function getArenaPlayers()
	local list = {}
	for uid in pairs(_G.PlayersInArena) do
		local pl = Players:GetPlayerByUserId(uid)
		if pl then
			table.insert(list, { id = uid, name = pl.Name })
		end
	end
	return list
end

-- === Publication de l'état du serveur ===
local function publish()
	if JOB_ID == "" then return end -- Studio : pas de JobId

	local arenaPlayers = getArenaPlayers()
	local trimmed = {}
	for i = 1, math.min(#arenaPlayers, MAX_AVATARS) do
		trimmed[i] = arenaPlayers[i]
	end

	local data = {
		jobId   = JOB_ID,
		placeId = PLACE_ID,
		total   = #Players:GetPlayers(),
		arena   = #arenaPlayers,
		players = trimmed,
		region  = serverRegion,   -- 🆕
		map     = _G.CurrentMap or "PVP",   -- 🆕 clé de map lue par le display
		t       = os.time(),
	}

	-- sortKey = nb de joueurs en arène → tri décroissant à la lecture
	-- 🩹 un échec (quota MemoryStore) n'est plus avalé en silence : 2e essai 1 s plus tard,
	--    sinon le serveur disparaissait de la liste au bout de 30 s.
	for attempt = 1, 2 do
		local ok = pcall(function()
			serverMap:SetAsync(JOB_ID, data, ENTRY_TTL, #arenaPlayers)
		end)
		if ok then break end
		if attempt == 1 then task.wait(1) end
	end
end

-- 🆕 publie TOUT DE SUITE quand le nombre de joueurs change (entrée / sortie d'arène,
--    arrivée / départ du serveur), au lieu d'attendre le prochain battement de 10 s.
--    Au plus une écriture toutes les 5 s (quota MemoryStore, côté serveur uniquement).
local lastSig, lastPub, pubQueued = nil, 0, false
local function signature()
	return #Players:GetPlayers() .. ":" .. #getArenaPlayers()
end
local function publishNow()
	lastSig, lastPub = signature(), os.clock()
	publish()
end
local function requestPublish()
	if pubQueued or JOB_ID == "" then return end
	pubQueued = true
	task.delay(math.max(0, 5 - (os.clock() - lastPub)), function()
		pubQueued = false
		if signature() ~= lastSig then publishNow() end
	end)
end

-- 🆕 Région du serveur (géoloc IP, 1 seule fois)
task.spawn(function()
	if JOB_ID == "" then serverRegion = "STUDIO"; return end
	local ok, body = pcall(function()
		return HttpService:GetAsync("http://ip-api.com/json/?fields=countryCode")
	end)
	if ok and body then
		local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
		if ok2 and type(data) == "table" and data.countryCode and data.countryCode ~= "" then
			serverRegion = data.countryCode    -- ex: "US", "CA", "FR"
			print("🌍 Région serveur:", serverRegion)
			publishNow()                       -- re-publie tout de suite avec la région
			return
		end
	end
	warn("[ServerBrowser] Géoloc échouée (HttpService activé ?) — région inconnue")
	serverRegion = "??"
end)

task.spawn(function()
	task.wait(2) -- laisser les autres systèmes démarrer
	local nextBeat = 0
	while true do
		if os.clock() >= nextBeat then
			publishNow()
			nextBeat = os.clock() + HEARTBEAT
		elseif signature() ~= lastSig then
			requestPublish()   -- quelqu'un est entré / sorti de l'arène
		end
		task.wait(1)
	end
end)
Players.PlayerAdded:Connect(requestPublish)
Players.PlayerRemoving:Connect(function() task.defer(requestPublish) end)

game:BindToClose(function()
	if JOB_ID ~= "" then
		pcall(function() serverMap:RemoveAsync(JOB_ID) end)
	end
end)

-- === Lecture de la liste (avec cache pour économiser le quota) ===
local cache = { data = {}, t = -math.huge }

local function fetchServers()
	local result = {}
	local ok, items = pcall(function()
		return serverMap:GetRangeAsync(Enum.SortDirection.Descending, LIST_LIMIT)
	end)
	if ok and items then
		for _, item in ipairs(items) do
			local v = item.value or item
			if type(v) == "table" and v.jobId and v.jobId ~= JOB_ID then
				-- ⚡ RÉSEAU : on n'envoie au joueur que ce que la carte affiche (6 photos, juste
				--    l'id) au lieu de 15 joueurs avec leur nom → ~3× moins de données qu'avant.
				local pls = {}
				if type(v.players) == "table" then
					for i = 1, math.min(#v.players, 6) do
						local pp = v.players[i]
						if type(pp) == "table" and pp.id then pls[i] = { id = pp.id } end
					end
				end
				table.insert(result, {   -- exclut le serveur courant
					jobId = v.jobId, total = v.total, arena = v.arena,
					region = v.region, map = v.map, players = pls,
				})
			end
		end
	end
	return result
end

getServersFn.OnServerInvoke = function(player)
	if os.clock() - cache.t < CACHE_TTL then
		return cache.data
	end
	cache.data = fetchServers()
	cache.t    = os.clock()
	return cache.data
end

-- === Join : téléport vers le serveur choisi ===
local joinDebounce = {}

joinServerEvent.OnServerEvent:Connect(function(player, targetJobId)
	if typeof(targetJobId) ~= "string" or targetJobId == "" then return end
	if targetJobId == JOB_ID then return end

	local now = os.clock()
	if joinDebounce[player.UserId] and now - joinDebounce[player.UserId] < JOIN_COOLDOWN then
		return
	end
	joinDebounce[player.UserId] = now

	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = targetJobId
	options:SetTeleportData({ joinArena = true })

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(PLACE_ID, { player }, options)
	end)

	if not ok then
		warn("[ServerBrowser] Téléport échoué:", err)
		joinFailedEvent:FireClient(player)
	end
end)

TeleportService.TeleportInitFailed:Connect(function(player, result, message)
	warn("[ServerBrowser] TeleportInitFailed:", result, message)
	if player and player.Parent then
		joinFailedEvent:FireClient(player)
	end
end)

-- === Arrivée par téléportation → entrée directe en arène ===
local function handleArrival(player)
	local joinData = player:GetJoinData()
	local td = joinData and joinData.TeleportData
	if not (td and td.joinArena) then return end

	-- ⚠️ Marquer TÔT (synchrone) pour que le système de checkpoint ignore ce spawn
	_G.PlayersInArena[player.UserId] = true

	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("HumanoidRootPart", 10)

		-- Attendre que la fonction d'entrée du script d'arène soit dispo
		local t = 0
		while not _G.ForceEnterArena and t < 10 do
			task.wait(0.1)
			t += 0.1
		end

		if _G.ForceEnterArena then
			_G.ForceEnterArena(player)
		else
			warn("[ServerBrowser] _G.ForceEnterArena introuvable (script d'arène non patché ?)")
		end
	end)
end

Players.PlayerAdded:Connect(handleArrival)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(handleArrival, pl)
end

Players.PlayerRemoving:Connect(function(player)
	joinDebounce[player.UserId] = nil
end)

-- === 📍 Positions des displays (pour le client, à l'abri du streaming) ===
-- Le serveur voit TOUS les displays taggés, même loin des joueurs. Il publie
-- leur position dans ReplicatedStorage (jamais streamé) ; le client y pose
-- son prompt sur une part locale. Swap de map → mis à jour tout seul.
do
	local CollectionService = game:GetService("CollectionService")
	local DISPLAY_TAG = "ServerBrowserDisplay"

	local anchorsFolder = ReplicatedStorage:FindFirstChild("ServerBrowserAnchors")
	if not anchorsFolder then
		anchorsFolder = Instance.new("Folder")
		anchorsFolder.Name = "ServerBrowserAnchors"
		anchorsFolder.Parent = ReplicatedStorage
	end
	anchorsFolder:ClearAllChildren()

	local anchorValues = {} -- [display] = CFrameValue
	local nextId = 0

	local function resolveAnchor(inst)
		if inst:IsA("BasePart") then return inst end
		if inst:IsA("Model") and inst.PrimaryPart then return inst.PrimaryPart end
		return inst:FindFirstChildWhichIsA("BasePart", true)
	end

	local function removeDisplay(inst)
		local v = anchorValues[inst]
		if v then v:Destroy() end
		anchorValues[inst] = nil
	end

	local function addDisplay(inst)
		if anchorValues[inst] then return end
		if not inst:IsDescendantOf(workspace) then return end -- ignore les maps sources (ServerStorage)
		local part = resolveAnchor(inst)
		if not part then
			warn("[ServerBrowser] Display sans part :", inst:GetFullName())
			return
		end
		nextId += 1
		local v = Instance.new("CFrameValue")
		v.Name   = "Display" .. nextId
		v.Value  = part.CFrame
		v.Parent = anchorsFolder
		anchorValues[inst] = v
	end

	CollectionService:GetInstanceAddedSignal(DISPLAY_TAG):Connect(addDisplay)
	CollectionService:GetInstanceRemovedSignal(DISPLAY_TAG):Connect(removeDisplay)
	for _, inst in ipairs(CollectionService:GetTagged(DISPLAY_TAG)) do
		addDisplay(inst)
	end
end

print("✅ ServerBrowser serveur chargé")