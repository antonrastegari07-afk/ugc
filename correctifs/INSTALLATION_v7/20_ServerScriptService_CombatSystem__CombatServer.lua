--[[
	CombatServer  (Script)
	Emplacement : ServerScriptService > CombatSystem > CombatServer

	• Respawn géré (toutes les morts gardent ton temps normal ; mort en arène tuée par un joueur :
	  vue du tueur pendant Death.SpectateTime, ou moins si le joueur appuie sur une touche)
	• Ragdoll à la mort (module Ragdoll)
	• Kills de la MANCHE : classement, killfeed
	• 🔥 Multi-kills : la série continue tant que le joueur ne meurt pas (plus aucun délai)
	• 🏆 Gagnant de la manche (le plus de kills à la fin du compte à rebours de la map) :
	    +1 win (OrderedDataStore, attribut « ArenaWins » sur le joueur), modèle de son perso publié dans
	    ReplicatedStorage/CombatRoundWinner pour l'écran de vote, avec dans la main l'arme avec laquelle
	    il a fait le plus de kills pendant la manche
	• Relais de la vue du tueur vers la victime (images, manifeste de son arme 1re personne, effets)

	🗺️ MANCHES : ton MapManager appelle
	      _G.CombatRoundStart()  au début de chaque compte à rebours  → kills de la manche remis à 0
	      _G.CombatRoundEnd()    à la fin du compte à rebours         → gagnant désigné
	   (filet : si ces appels manquent, un changement de map remet quand même les kills à 0)
	   Les messages « MapStart » des clients ne remettent rien à zéro : le serveur leur renvoie le classement.

	Ne touche à AUCUN de tes scripts : ton arène (tp1v1) reçoit le respawn comme d'habitude.
	Réglages : ReplicatedStorage/WeaponSystem/CombatSettings
]]

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService   = game:GetService("DataStoreService")
local ServerStorage      = game:GetService("ServerStorage")

local S = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("CombatSettings"))
local Ragdoll = require(script.Parent:WaitForChild("Ragdoll"))
require(script.Parent:WaitForChild("HitValidator"))   -- démarre l'historique des positions dès le lancement

local function on(section)
	local t = S[section]
	return S.Enabled ~= false and type(t) == "table" and t.Enabled ~= false
end

---------------------------------------------------------------------
-- 📡 remotes
---------------------------------------------------------------------
local folder = ReplicatedStorage:FindFirstChild("CombatRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "CombatRemotes"
	folder.Parent = ReplicatedStorage
end
local function ensure(name, class)
	local r = folder:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = folder
	end
	return r
end
local CombatEvent   = ensure("CombatEvent", "RemoteEvent")          -- serveur → clients
local CombatRequest = ensure("CombatRequest", "RemoteEvent")        -- clients → serveur
local Stream        = ensure("SpectateStream", "UnreliableRemoteEvent")

---------------------------------------------------------------------
-- 👑 VIP (même logique que ton profil : attribut IsVIP, _G.IsVIP ou gamepass)
---------------------------------------------------------------------
local vipCache = {}
local function isVip(p)
	if p:GetAttribute("IsVIP") == true then return true end
	if type(_G.IsVIP) == "function" then
		local ok, r = pcall(_G.IsVIP, p.UserId)
		if ok and r then return true end
	end
	local c = vipCache[p.UserId]
	if c ~= nil then return c end
	local pass = S.Death and S.Death.Frame and S.Death.Frame.VipPassId
	if not pass then return false end
	local ok, r = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, p.UserId, pass)
	vipCache[p.UserId] = ok and r or false
	return vipCache[p.UserId]
end

---------------------------------------------------------------------
-- ♻️ RESPAWN GÉRÉ
---------------------------------------------------------------------
local manage = S.Enabled ~= false and S.Respawn and S.Respawn.Manage ~= false and Players.CharacterAutoLoads
local normalTime = (S.Respawn and S.Respawn.NormalTime) or Players.RespawnTime
if manage then
	-- on prend la main : Roblox ne relance plus le perso tout seul (sinon double respawn quand on
	-- relance plus tôt). Chaque mort est relancée par nous après le bon délai.
	Players.RespawnTime = 1e6
end

local pending = {}   -- [player] = { char = mortCharacter, at = os.clock(), done = false, spectate = bool }
local loading = {}   -- [player] = true pendant LoadCharacter (le filet de sécurité attend)

local function load(p)
	if loading[p] then return end
	loading[p] = true
	local ok, err = pcall(p.LoadCharacter, p)
	loading[p] = nil
	if not ok then warn("[CombatSystem] respawn de " .. p.Name .. " : " .. tostring(err)) end
end

local function respawn(p)
	local st = pending[p]
	if not st or st.done then return end
	st.done = true
	if p.Parent and p.Character == st.char then
		load(p)
	end
	if pending[p] == st then pending[p] = nil end
end

local function schedule(p, char, delay, spectate)
	if not manage then return end
	local st = { char = char, at = os.clock(), done = false, spectate = spectate }
	pending[p] = st
	task.delay(delay, function()
		if pending[p] == st then respawn(p) end
	end)
end

-- filet de sécurité : un perso mort sans respawn prévu est relancé après le délai normal
if manage then
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in ipairs(Players:GetPlayers()) do
				local ch = p.Character
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				-- perso détruit sans mourir (tombé dans le vide…) : traité comme une mort
				if loading[p] or pending[p] then
					-- respawn déjà en cours / prévu
				elseif ch and ch.Parent == nil then
					local t = ch:GetAttribute("CombatDeadAt")
					if not t then
						ch:SetAttribute("CombatDeadAt", os.clock())
					elseif os.clock() - t >= normalTime then
						task.spawn(load, p)
					end
				elseif hum and hum.Health <= 0 then
					local t = ch:GetAttribute("CombatDeadAt")
					if not t then
						ch:SetAttribute("CombatDeadAt", os.clock())
					elseif os.clock() - t >= normalTime + 1 then
						task.spawn(load, p)
					end
				end
			end
		end
	end)
end

---------------------------------------------------------------------
-- 🏆 KILLS DE LA MANCHE (sur ce serveur)
---------------------------------------------------------------------
local kills = {}          -- [userId] = kills de la manche en cours
local deaths = {}         -- [userId] = morts en arène pendant la manche
local heads = {}          -- [userId] = kills en headshot pendant la manche
local roundBest = {}      -- [userId] = meilleure série pendant la manche
local reachedAt = {}      -- [userId] = os.clock() du dernier kill (départage les égalités)
local roundWeap = {}      -- [userId] = { [nom du Tool] = kills } pendant la manche
local weapLabel = {}      -- [nom du Tool] = nom affiché de l'arme (AK47, Scar…)
local mapResetAt = 0
local roundId = 0
local roundHooked = false -- true dès que le MapManager appelle les manches

local streak = {}         -- [userId] = kills d'affilée SANS mourir (survit aux manches)
local lastKillAt = {}     -- [userId] = os.clock() (ancien mode à fenêtre, si ResetOnDeath = false)

local function boardPacket()
	local list = {}
	for uid, k in pairs(kills) do
		local p = Players:GetPlayerByUserId(uid)
		if p then table.insert(list, { u = uid, k = k }) end
	end
	return list
end
local function pushBoard() CombatEvent:FireAllClients("Board", boardPacket()) end
local function hudOn() return on("ArenaHUD") or on("Leaderboard") end
local function sendBoard(p)
	if hudOn() and p.Parent then CombatEvent:FireClient(p, "Board", boardPacket()) end
end

local function clearRound()
	mapResetAt = os.clock()
	table.clear(kills)
	table.clear(deaths)
	table.clear(heads)
	table.clear(roundBest)
	table.clear(reachedAt)
	table.clear(roundWeap)
	if hudOn() then pushBoard() end
end

---------------------------------------------------------------------
-- 🏆 WINS (persistants) + GAGNANT DE MANCHE
---------------------------------------------------------------------
local RW = S.RoundWinner or {}
local winsStore = DataStoreService:GetOrderedDataStore(RW.WinsStore or "ArenaWins_v1")
local winsPending = {}    -- [userId] = wins gagnées pas encore écrites

local winnerFolder = ReplicatedStorage:FindFirstChild("CombatRoundWinner")
if not winnerFolder then
	winnerFolder = Instance.new("Folder")
	winnerFolder.Name = "CombatRoundWinner"
	winnerFolder.Parent = ReplicatedStorage
end
if winnerFolder:GetAttribute("Round") == nil then
	winnerFolder:SetAttribute("WinnerId", 0)
	winnerFolder:SetAttribute("Round", 0)
end

local function loadWins(p)
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, v = pcall(function() return winsStore:GetAsync(tostring(p.UserId)) end)
			if ok then
				if p.Parent then
					p:SetAttribute("ArenaWins", (tonumber(v) or 0) + (winsPending[p.UserId] or 0))
				end
				return
			end
			task.wait(2 * attempt)
		end
	end)
end

local function saveWin(uid)
	for attempt = 1, 5 do
		local ok, newV = pcall(function() return winsStore:IncrementAsync(tostring(uid), 1) end)
		if ok then
			winsPending[uid] = math.max(0, (winsPending[uid] or 1) - 1)
			local p = Players:GetPlayerByUserId(uid)
			if p and type(newV) == "number" then
				p:SetAttribute("ArenaWins", newV + (winsPending[uid] or 0))
			end
			if (winsPending[uid] or 0) == 0 then winsPending[uid] = nil end
			return
		end
		task.wait(3 * attempt)
	end
	warn("[CombatSystem] win non enregistrée pour " .. tostring(uid) .. " (DataStore indisponible)")
end

-- arme favorite de la manche (le Tool avec le plus de kills ; égalité = la première atteinte)
local function favouriteTool(uid)
	local best, bestN
	for name, n in pairs(roundWeap[uid] or {}) do
		if not best or n > bestN then best, bestN = name, n end
	end
	return best
end

local function findToolTemplate(toolName, p)
	if type(toolName) ~= "string" or toolName == "" then return nil end
	local t = ServerStorage:FindFirstChild(toolName)
	if t and t:IsA("Tool") then return t end
	for _, holder in ipairs({ p and p.Character, p and p:FindFirstChildOfClass("Backpack") }) do
		local c = holder and holder:FindFirstChild(toolName)
		if c and c:IsA("Tool") then return c end
	end
	local base = toolName:match("^([^_]+)_")   -- skin introuvable : l'arme de base
	t = base and ServerStorage:FindFirstChild(base)
	if t and t:IsA("Tool") then return t end
	return nil
end

-- 🔫 l'arme dans la main droite du modèle (prise Roblox classique : Right Arm → Handle, tool.Grip)
local STRIP = { "LuaSourceContainer", "Sound", "RemoteEvent", "RemoteFunction", "UnreliableRemoteEvent", "BindableEvent",
	"BindableFunction", "ParticleEmitter", "Light", "Beam", "Trail", "BillboardGui", "SurfaceGui", "ProximityPrompt",
	"ValueBase", "JointInstance", "WeldConstraint", "Constraint", "Attachment", "Fire", "Smoke", "Sparkles", "Highlight" }
local function attachWeapon(model, toolName, p)
	local arm = model:FindFirstChild("Right Arm")
	local src = findToolTemplate(toolName, p)
	if not (arm and src) then return end
	local arch = src.Archivable
	src.Archivable = true
	local ok, tool = pcall(function() return src:Clone() end)
	src.Archivable = arch
	if not ok or not tool then return end
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then tool:Destroy() return end
	local grip = tool.Grip
	for _, d in ipairs(tool:GetDescendants()) do
		for _, cls in ipairs(STRIP) do
			if d:IsA(cls) then pcall(function() d:Destroy() end) break end
		end
	end
	-- chaque pièce soudée au Handle à sa place d'origine (aucune physique dans l'écran de vote)
	local hcf = handle.CFrame
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true
			if d ~= handle then
				local w = Instance.new("Weld")
				w.Name = "WinnerHold"; w.Part0 = handle; w.Part1 = d
				w.C0 = hcf:ToObjectSpace(d.CFrame)
				w.Parent = handle
			end
		end
	end
	local weap = Instance.new("Model")
	weap.Name = "WinnerWeapon"
	for _, c in ipairs(tool:GetChildren()) do c.Parent = weap end
	tool:Destroy()
	weap.PrimaryPart = handle
	local g = Instance.new("Weld")
	g.Name = "RightGrip"; g.Part0 = arm; g.Part1 = handle
	g.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	g.C1 = grip
	g.Parent = arm
	weap.Parent = model
end

-- 🧍 POSE DES BRAS DE TON SYSTÈME D'ARMES : la même que WeaponWeld en jeu (épaules coupées,
--    bras soudés au Torso avec les C1 de l'arme → les DEUX mains tiennent l'arme).
--    Les C1 sont lus sur l'arme du joueur (attributs WeldLeftBaseC1 / WeldRightBaseC1 posés par
--    le Script « Weld » de l'arme). Arme de ServerStorage sans attribut : on fait tourner son Script
--    de weld UNE fois, seul (les autres scripts coupés), dans un dossier caché. Résultat mis en cache.
local armCache = {}
local function readArms(t)
	local l, r = t and t:GetAttribute("WeldLeftBaseC1"), t and t:GetAttribute("WeldRightBaseC1")
	if typeof(l) == "CFrame" and typeof(r) == "CFrame" then return { Left = l, Right = r } end
	return nil
end
local function armConfig(toolName, p)
	if type(toolName) ~= "string" then return nil end
	for _, holder in ipairs({ p and p.Character, p and p:FindFirstChildOfClass("Backpack") }) do
		local c = readArms(holder and holder:FindFirstChild(toolName))
		if c then armCache[toolName] = c; return c end
	end
	if armCache[toolName] ~= nil then return armCache[toolName] or nil end
	local src = findToolTemplate(toolName, p)
	local c = readArms(src)
	if not c and src then
		local arch = src.Archivable
		src.Archivable = true
		local okC, probe = pcall(function() return src:Clone() end)
		src.Archivable = arch
		if okC and probe then
			local hasWeld = false
			for _, d in ipairs(probe:GetDescendants()) do
				if d:IsA("BaseScript") then
					if d.ClassName == "Script" and string.find(string.lower(d.Name), "weld", 1, true) then
						hasWeld = true
					else
						d.Enabled = false
					end
				end
			end
			if hasWeld then
				local f = Instance.new("Folder")
				f.Name = "WinnerWeldProbe"
				probe.Parent = f
				f.Parent = game:GetService("ServerScriptService")
				local t0 = os.clock()
				while not c and os.clock() - t0 < 3 do
					task.wait(0.1)
					c = readArms(probe)
				end
				f:Destroy()
			else
				probe:Destroy()
			end
		end
	end
	armCache[toolName] = c or false
	return c
end
local function weldArms(model, cfg)
	local torso = model:FindFirstChild("Torso")
	local la, ra = model:FindFirstChild("Left Arm"), model:FindFirstChild("Right Arm")
	if not (cfg and torso and la and ra) then return end
	for _, n in ipairs({ "Left Shoulder", "Right Shoulder" }) do
		local j = torso:FindFirstChild(n)
		if j then j.Part1 = nil end
	end
	local function w(name, arm, c1)
		local x = Instance.new("Weld")
		x.Name = name; x.Part0 = torso; x.Part1 = arm; x.C1 = c1
		x.Parent = torso
	end
	w("LeftArmWeld", la, cfg.Left)
	w("RightArmWeld", ra, cfg.Right)
end

-- modèle du perso du gagnant (R6) pour l'écran de vote : construit ici, cloné par les clients
local function buildWinnerModel(id, uid, p, toolName)
	local model
	local okD, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(uid) end)
	if okD and desc then
		local okM, m = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
		end)
		if okM then model = m end
	end
	if not model and p and p.Character then
		local ch = p.Character
		local arch = ch.Archivable
		ch.Archivable = true
		local okC, c = pcall(function() return ch:Clone() end)
		ch.Archivable = arch
		if okC then model = c end
	end
	if not model then return end
	if id ~= roundId then model:Destroy() return end   -- une manche plus récente est déjà passée

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("ForceField") or d:IsA("Sound")
			or d:IsA("BillboardGui") or d:IsA("Highlight") or d:IsA("ParticleEmitter") or d:IsA("Light")
			or d:IsA("ProximityPrompt") or d:IsA("Constraint") then
			pcall(function() d:Destroy() end)
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		if not hum:FindFirstChildOfClass("Animator") then Instance.new("Animator").Parent = hum end
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.Anchored = true; hrp.Transparency = 1 end
	if RW.HoldWeapon ~= false then
		pcall(weldArms, model, armConfig(toolName, p))   -- avant l'arme : la prise suit le bras soudé
		pcall(attachWeapon, model, toolName, p)
	end
	if id ~= roundId then model:Destroy() return end   -- (le weld a pu attendre jusqu'à 3 s)
	model.Name = "Winner"
	model.Archivable = true
	model:SetAttribute("Round", id)

	local old = winnerFolder:FindFirstChild("Winner")
	if old then old:Destroy() end
	model.Parent = winnerFolder
end

local function pickWinner()
	local best, bestK, bestAt
	local minK = tonumber(RW.MinKills) or 1
	for uid, k in pairs(kills) do
		local p = Players:GetPlayerByUserId(uid)
		if p and k >= minK then
			local at = reachedAt[uid] or 0
			if not best or k > bestK or (k == bestK and at < bestAt) then
				best, bestK, bestAt = p, k, at   -- égalité : celui qui y est arrivé en premier
			end
		end
	end
	return best, bestK
end

-- début d'une manche (début du compte à rebours de la map)
_G.CombatRoundStart = function()
	roundHooked = true
	clearRound()
end
-- compatibilité avec l'ancien patch du MapManager (swapTo)
_G.CombatMapStart = _G.CombatRoundStart

-- fin d'une manche (fin du compte à rebours) : désigne le gagnant
_G.CombatRoundEnd = function()
	roundHooked = true
	if not on("RoundWinner") then return nil end
	roundId += 1
	local id = roundId
	local p, k = pickWinner()
	if not p then
		winnerFolder:SetAttribute("WinnerId", 0)
		winnerFolder:SetAttribute("Round", id)
		local old = winnerFolder:FindFirstChild("Winner")
		if old then old:Destroy() end
		return nil
	end

	local uid = p.UserId
	local wins = (tonumber(p:GetAttribute("ArenaWins")) or 0) + 1
	p:SetAttribute("ArenaWins", wins)
	winsPending[uid] = (winsPending[uid] or 0) + 1
	task.spawn(saveWin, uid)

	local favTool = favouriteTool(uid)
	local info = {
		round = id, userId = uid, name = p.Name, displayName = p.DisplayName,
		kills = k, deaths = deaths[uid] or 0, headshots = heads[uid] or 0,
		best = roundBest[uid] or 0, wins = wins, map = _G.CurrentMap,
		totalKills = tonumber(p:GetAttribute("TotalKills")) or 0,   -- total de kills de son profil
		tool = favTool, weapon = favTool and (weapLabel[favTool] or favTool:match("^([^_]+)_") or favTool) or nil,
	}
	winnerFolder:SetAttribute("WinnerId", uid)
	winnerFolder:SetAttribute("Name", info.name)
	winnerFolder:SetAttribute("DisplayName", info.displayName)
	winnerFolder:SetAttribute("Kills", info.kills)
	winnerFolder:SetAttribute("Deaths", info.deaths)
	winnerFolder:SetAttribute("Headshots", info.headshots)
	winnerFolder:SetAttribute("BestStreak", info.best)
	winnerFolder:SetAttribute("Wins", info.wins)
	winnerFolder:SetAttribute("MapKey", tostring(info.map or ""))
	winnerFolder:SetAttribute("Round", id)   -- en dernier : les clients relisent tout quand il change
	CombatEvent:FireAllClients("RoundWinner", info)
	task.spawn(buildWinnerModel, id, uid, p, favTool)
	print(("🏆 Manche %d : %s gagne avec %d kills (%d wins)"):format(id, p.Name, k, wins))
	return info
end

---------------------------------------------------------------------
-- 🗺️ FILET : changement de map sans les appels de manche du MapManager
---------------------------------------------------------------------
local function mapIdentity()
	if type(_G.GetCurrentMapInfo) == "function" then
		local ok, info = pcall(_G.GetCurrentMapInfo)
		if ok and type(info) == "table" then
			for _, k in ipairs({ "model", "Model", "map", "Map", "instance", "Instance" }) do
				if typeof(info[k]) == "Instance" then return info[k] end
			end
		end
	end
	return _G.CurrentMap
end

task.spawn(function()
	local lastMap = mapIdentity()
	while true do
		task.wait(1)
		local id = mapIdentity()
		if id ~= nil and id ~= lastMap then
			local first = (lastMap == nil)
			lastMap = id
			if not first and not roundHooked and os.clock() - mapResetAt > 5 then clearRound() end
		end
	end
end)

---------------------------------------------------------------------
-- 👁️ VUE DU TUEUR : qui regarde qui
---------------------------------------------------------------------
local watchers = {}        -- [killer] = { [victim] = expire }
local lastManifest = {}     -- [killer] = dernier manifeste (une 2e victime le reçoit tout de suite)
local function stopWatch(killer, victim)
	local w = watchers[killer]
	if not w then return end
	w[victim] = nil
	if next(w) == nil then
		watchers[killer] = nil
		lastManifest[killer] = nil
		if killer.Parent then CombatEvent:FireClient(killer, "StreamStop") end
	end
end

-- envoie à toutes les victimes qui regardent ce tueur
local function relay(killer, fn)
	local w = watchers[killer]
	if not w then return end
	local now = os.clock()
	for victim, expire in pairs(w) do
		if now > expire or not victim.Parent then
			stopWatch(killer, victim)
		else
			fn(victim)
		end
	end
end

-- limite d'envois par seconde (anti-spam)
local budget = {}
local function allow(killer, kind, max)
	local key = kind .. killer.UserId
	local b = budget[key]
	local now = os.clock()
	if not b or now - b.t >= 1 then b = { t = now, n = 0 }; budget[key] = b end
	b.n += 1
	return b.n <= max
end

-- images de la vue (buffer compact, non fiable, ~30 / s)
Stream.OnServerEvent:Connect(function(killer, packet)
	if not watchers[killer] or typeof(packet) ~= "buffer" or buffer.len(packet) > 900 then return end
	if not allow(killer, "img", 70) then return end
	relay(killer, function(victim) Stream:FireClient(victim, killer, packet) end)
end)

---------------------------------------------------------------------
-- 💀 MORT
---------------------------------------------------------------------
local function killerOf(hum)
	local tag = hum:FindFirstChild("creator")
	local k = tag and tag:IsA("ObjectValue") and tag.Value
	if k and k:IsA("Player") then return k end
	local uid = hum:GetAttribute("CombatLastHitBy")
	local at = hum:GetAttribute("CombatLastAt")
	if uid and at and os.clock() - at < 5 then
		return Players:GetPlayerByUserId(uid)
	end
	return nil
end

local function onDied(p, char, hum)
	if pending[p] and pending[p].char == char then return end
	-- un tueur qui meurt arrête d'envoyer sa vue (échange de kills)
	if watchers[p] then
		for v in pairs(watchers[p]) do stopWatch(p, v) end
	end
	local inArena = p:GetAttribute("InArena") == true
	local killer = killerOf(hum)
	if killer == p then killer = nil end

	-- 🔥 la série de la victime s'arrête à sa mort
	local M = S.MultiKill or {}
	if M.ResetOnDeath ~= false then streak[p.UserId] = nil end
	if inArena then deaths[p.UserId] = (deaths[p.UserId] or 0) + 1 end

	local victimRoot = char:FindFirstChild("HumanoidRootPart")
	local kChar = killer and killer.Character
	local kRoot = kChar and kChar:FindFirstChild("HumanoidRootPart")
	local kHum = kChar and kChar:FindFirstChildOfClass("Humanoid")
	local head = hum:GetAttribute("CombatLastHead") == true
	local weapon = hum:GetAttribute("CombatLastWeapon")
	local toolName = hum:GetAttribute("CombatLastTool")
	if (not weapon) and kChar then
		local t = kChar:FindFirstChildOfClass("Tool")
		if t then weapon = t.Name:match("^([^_]+)_") or t.Name; toolName = t.Name end
	end
	local dist = hum:GetAttribute("CombatLastDist")
	if (not dist) and kRoot and victimRoot then dist = (kRoot.Position - victimRoot.Position).Magnitude end

	-- 🪆 ragdoll
	if on("Ragdoll") and (not S.Ragdoll.OnlyInArena or inArena) then
		local push = Vector3.zero
		if kRoot and victimRoot then
			local dir = victimRoot.Position - kRoot.Position
			dir = Vector3.new(dir.X, 0, dir.Z)
			if dir.Magnitude > 0.01 then
				local R = S.Ragdoll
				push = dir.Unit * (head and (R.HeadshotImpulse or 52) or (R.Impulse or 38)) + Vector3.new(0, R.UpImpulse or 10, 0)
			end
		end
		pcall(Ragdoll.Apply, char, push)
	elseif on("Ragdoll") then
		pcall(Ragdoll.Break, char)   -- pas de ragdoll ici : le corps tombe en morceaux comme avant
	end

	-- 🏆 kills d'arène : classement, killfeed, multi-kill, stats de manche
	if killer and inArena then
		local uid = killer.UserId
		local now = os.clock()
		kills[uid] = (kills[uid] or 0) + 1
		reachedAt[uid] = now
		if head then heads[uid] = (heads[uid] or 0) + 1 end
		local tk = (toolName ~= nil and toolName ~= "") and toolName or weapon
		if tk and tk ~= "" then
			roundWeap[uid] = roundWeap[uid] or {}
			roundWeap[uid][tk] = (roundWeap[uid][tk] or 0) + 1
			weapLabel[tk] = weapon or weapLabel[tk]
		end
		if hudOn() then pushBoard() end
		if on("Killfeed") or on("ArenaHUD") then
			CombatEvent:FireAllClients("Feed", { k = killer.UserId, v = p.UserId, w = weapon or "", h = head, t = toolName or "" })
		end

		-- 🔥 série : tant que le tueur ne meurt pas (ou ancien mode à fenêtre)
		local n = streak[uid] or 0
		if M.ResetOnDeath == false and lastKillAt[uid] and now - lastKillAt[uid] > (M.Window or 4) then n = 0 end
		n += 1
		streak[uid] = n
		lastKillAt[uid] = now
		if n > (roundBest[uid] or 0) then roundBest[uid] = n end
		if on("MultiKill") and n >= 2 then CombatEvent:FireClient(killer, "MultiKill", n) end
	end

	-- 👁️ vue du tueur (+ bande d'infos)
	local spectate = killer ~= nil and killer.Parent ~= nil and on("Death")
		and kHum ~= nil and kHum.Health > 0
		and (not S.Death.OnlyInArena or inArena)
	if spectate then
		local D = S.Death
		local info = {
			killer = killer,
			weapon = weapon or "",
			tool = toolName or "",
			head = head,
			dist = dist and math.floor(dist + 0.5) or nil,
			hp = kHum and math.max(0, math.ceil(kHum.Health)) or nil,
			maxHp = kHum and math.ceil(kHum.MaxHealth) or nil,
			vip = false,
			time = D.SpectateTime or 5,
			body = char,   -- ton corps (ragdoll) : la victime l'affiche pendant la vue du tueur
		}
		info.vip = isVip(killer)
		CombatEvent:FireClient(p, "Spectate", info)
		watchers[killer] = watchers[killer] or {}
		watchers[killer][p] = os.clock() + (D.SpectateTime or 5) + 1
		if lastManifest[killer] then CombatEvent:FireClient(p, "KVM", killer, lastManifest[killer]) end
		CombatEvent:FireClient(killer, "StreamStart", p)
		-- monde chargé autour du tueur (StreamingEnabled) : sa vue est complète
		pcall(function() p.ReplicationFocus = kRoot end)
		schedule(p, char, D.SpectateTime or 5, true)
	else
		schedule(p, char, normalTime, false)
	end
end

local function onCharacter(p, char)
	-- fin d'une vue du tueur : on libère le tueur
	for killer, w in pairs(watchers) do
		if w[p] then stopWatch(killer, p) end
	end
	if pending[p] and pending[p].char ~= char then pending[p] = nil end
	pcall(function() p.ReplicationFocus = nil end)
	if on("Ragdoll") then Ragdoll.Prepare(char) end
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if not hum then return end
	if on("Ragdoll") then Ragdoll.Prepare(char) end
	hum.Died:Connect(function()
		char:SetAttribute("CombatDeadAt", os.clock())
		onDied(p, char, hum)
	end)
end

local function onPlayer(p)
	p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
	if p.Character then task.spawn(onCharacter, p, p.Character) end
	loadWins(p)
	-- entrée dans l'arène : top kills ACTUEL de la manche ; sortie : la série s'arrête
	p:GetAttributeChangedSignal("InArena"):Connect(function()
		if p:GetAttribute("InArena") == true then
			task.delay(0.5, function() sendBoard(p) end)
		elseif (S.MultiKill or {}).ResetOnLeaveArena ~= false then
			streak[p.UserId] = nil
		end
	end)
	if hudOn() then task.delay(2, function() sendBoard(p) end) end
end
for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerAdded:Connect(onPlayer)

Players.PlayerRemoving:Connect(function(p)
	pending[p] = nil
	-- (kills / stats de manche GARDÉS : s'il revient pendant la même manche il retrouve son score)
	streak[p.UserId] = nil
	lastKillAt[p.UserId] = nil
	vipCache[p.UserId] = nil
	budget["img" .. p.UserId], budget["kve" .. p.UserId], budget["kvm" .. p.UserId], budget["kvq" .. p.UserId] = nil, nil, nil, nil
	budget["brd" .. p.UserId] = nil
	lastManifest[p] = nil
	watchers[p] = nil
	for killer, w in pairs(watchers) do
		if w[p] then stopWatch(killer, p) end
	end
	if hudOn() then pushBoard() end
end)

---------------------------------------------------------------------
-- 📨 requêtes des clients (vue du tueur, classement, skip)
---------------------------------------------------------------------
CombatRequest.OnServerEvent:Connect(function(p, action, data)
	if action == "KVM" then
		-- manifeste de la vue du tueur : les pièces de son arme 1re personne
		if not watchers[p] or type(data) ~= "table" or type(data.list) ~= "table" or #data.list > 250 then return end
		lastManifest[p] = data   -- gardé même si l'envoi est limité : la victime peut le redemander
		if not allow(p, "kvm", 6) then return end
		relay(p, function(victim) CombatEvent:FireClient(victim, "KVM", p, data) end)
		return
	elseif action == "KVReq" then
		-- la victime n'a pas reçu le manifeste : on lui renvoie le dernier
		local killer = data
		if typeof(killer) ~= "Instance" or not killer:IsA("Player") then return end
		local w = watchers[killer]
		if not w or not w[p] or not lastManifest[killer] then return end
		if not allow(p, "kvq", 3) then return end
		CombatEvent:FireClient(p, "KVM", killer, lastManifest[killer])
		return
	elseif action == "KVE" then
		-- effets du tueur (flash, douilles, hitmarkers, sons…)
		if not watchers[p] or type(data) ~= "table" or #data > 64 then return end
		if not allow(p, "kve", 70) then return end
		relay(p, function(victim) CombatEvent:FireClient(victim, "KVE", p, data) end)
		return
	end
	if action == "MapStart" then
		-- un client ne remet JAMAIS rien à zéro : on lui renvoie juste le classement actuel
		if allow(p, "brd", 2) then sendBoard(p) end
		return
	end
	if action == "Respawn" then
		local st = pending[p]
		if not st or not st.spectate then return end
		if os.clock() - st.at < (S.Death.SkipDelay or 0.4) - 0.1 then return end
		respawn(p)
	end
end)

print(("✅ CombatSystem serveur prêt (respawn géré : %s, temps normal %.1f s)"):format(tostring(manage), normalTime))