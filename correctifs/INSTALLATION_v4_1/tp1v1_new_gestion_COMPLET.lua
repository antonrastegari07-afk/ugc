local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- RemoteEvents
local enterArenaEvent = ReplicatedStorage:FindFirstChild("EnterArena") or Instance.new("RemoteEvent")
enterArenaEvent.Name = "EnterArena"
enterArenaEvent.Parent = ReplicatedStorage

local exitArenaEvent = ReplicatedStorage:FindFirstChild("ExitArena") or Instance.new("RemoteEvent")
exitArenaEvent.Name = "ExitArena"
exitArenaEvent.Parent = ReplicatedStorage

local uiToggleEvent = ReplicatedStorage:FindFirstChild("ArenaUIToggle") or Instance.new("RemoteEvent")
uiToggleEvent.Name = "ArenaUIToggle"
uiToggleEvent.Parent = ReplicatedStorage

-- ✅ Nouvel événement dédié pour le bouton hide
local hideUIEvent = ReplicatedStorage:FindFirstChild("HideUIEvent") or Instance.new("RemoteEvent")
hideUIEvent.Name = "HideUIEvent"
hideUIEvent.Parent = ReplicatedStorage

-- Configuration
local BASE_GUNS = {"Sniper"}
local GAMEPASS_1 = {id = 1889945094, guns = {"RPG"}}
local GAMEPASS_2 = {id = 1891589121, guns = {"Scar"}}   -- 👑 VIP → Scar
local GAMEPASS_AK47 = {id = 1891019055, guns = {"AK47"}}
local GAMEPASS_SHOTGUN = {id = 1889765109, guns = {"ShotGun"}}
local GAMEPASS_MINIGUN = {id = 1890101132, guns = {"Minigun"}}
local GROUP_ID = 684717971
local GROUP_GUN = "Deagle"
local COOLDOWN = 1.0

local playerStates = {}
local playerOriginalSpawns = {}
local playerCheckpointPositions = {}
local playerSavedTools = {}
local debounce = {}
local playerFromTeleport = {}    -- 🆕 arrivés via ServerBrowser (aucun checkpoint obby)

-- ❤️ PV EN ARÈNE (PVP) ⬅ AJOUTÉ (1/6)
local ARENA_HEALTH  = 195    -- PV max tant que le joueur est en arène
local NORMAL_HEALTH = 100    -- PV max hors arène (secours si rien n'a été mémorisé)
local playerOriginalHealth = {}   -- [userId] = MaxHealth d'avant l'arène

-- ✅ CACHE gamepass (5 min) : giveGuns tourne à CHAQUE respawn en arène,
-- 5 UserOwnsGamePassAsync par respawn = lag "spawn sans arme"
local arenaPassCache = {}  -- [userId] = {t = os.time(), owns = {[passId] = bool}}

local function ownsPass(userId, passId)
	-- 👑 VIP offert par un admin : donne le même accès que le gamepass VIP
	if passId == GAMEPASS_2.id and _G.IsVIP and _G.IsVIP(userId) then
		return true
	end
	local c = arenaPassCache[userId]
	if not c or os.time() - c.t > 300 then
		c = { t = os.time(), owns = {} }
		arenaPassCache[userId] = c
	end
	if c.owns[passId] == nil then
		local ok, r = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
		end)
		c.owns[passId] = (ok and r) or false
	end
	return c.owns[passId]
end

_G.PlayersInArena = _G.PlayersInArena or {}

-- APRÈS
local arenaSpawnsCache = nil
local lastCachedMapKey = nil   -- ← pour détecter un changement de map

local function getArenaSpawns()
	local currentMapKey = _G.CurrentMap or "PVP"

	-- Invalider le cache si la map a changé
	if lastCachedMapKey ~= currentMapKey then
		arenaSpawnsCache = nil
		lastCachedMapKey = currentMapKey
		print("🔄 Map changée vers '" .. currentMapKey .. "', cache de spawns invalidé")
	end

	if not arenaSpawnsCache then
		arenaSpawnsCache = {}

		-- Lire les noms de spawns depuis MapConfig
		local MapConfig = require(ReplicatedStorage:FindFirstChild("MapConfig"))
		local mapData = MapConfig.getByKey(currentMapKey)

		if mapData and mapData.Spawns and #mapData.Spawns > 0 then
			-- Chercher les SpawnLocations dans le Workspace par nom de mapData.Spawns
			for _, obj in ipairs(Workspace:GetDescendants()) do
				if obj:IsA("SpawnLocation") then
					for _, spawnName in ipairs(mapData.Spawns) do
						if string.find(obj.Name, spawnName) then
							table.insert(arenaSpawnsCache, obj)
							break
						end
					end
				end
			end
		else
			-- Fallback : auto-détection si Spawns est vide dans MapConfig
			for _, obj in ipairs(Workspace:GetDescendants()) do
				if obj:IsA("SpawnLocation") then
					table.insert(arenaSpawnsCache, obj)
				end
			end
		end

		print("✅ " .. #arenaSpawnsCache .. " spawns trouvés pour la map '" .. currentMapKey .. "'")
	end
	return arenaSpawnsCache
end

local function assignRandomArenaSpawn(player)
	local spawns = getArenaSpawns()
	if #spawns == 0 then
		warn("❌ Aucun spawn d'arène trouvé!")
		return false
	end

	local randomSpawn = spawns[math.random(1, #spawns)]
	player.RespawnLocation = randomSpawn
	print("🎲 " .. player.Name .. " assigné au spawn: " .. randomSpawn.Name)
	return true
end

-- 🗺️ ZONE PVP : un spawn / une position de l'arène ne sert JAMAIS de point de retour
local function isArenaSpawn(sp)
	if typeof(sp) ~= "Instance" then return false end
	local live = Workspace:FindFirstChild("CurrentMap")
	if live and sp:IsDescendantOf(live) then return true end
	if sp.Name:lower():match("^checkpoint") or sp.Name == "FirstSpawn" then return false end
	return table.find(getArenaSpawns(), sp) ~= nil
end

local function isInPvpZone(pos)
	if typeof(pos) ~= "Vector3" then return false end
	local live = Workspace:FindFirstChild("CurrentMap")
	if live then
		for _, m in ipairs(live:GetChildren()) do
			if m:IsA("Model") then
				local cf, size = m:GetBoundingBox()
				local p = cf:PointToObjectSpace(pos)
				local h = size / 2 + Vector3.new(10, 30, 10)
				if math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z then return true end
			end
		end
	end
	for _, sp in ipairs(getArenaSpawns()) do
		if isArenaSpawn(sp) and (sp.Position - pos).Magnitude < 40 then return true end
	end
	return false
end

--════════════════════════════════════════════════════════════════════════════
-- 🎒 OUTILS PENDANT LE PVP — mis de côté, puis rendus TELS QUELS
--
--  Avant : à l'entrée on notait les NOMS des outils et on les détruisait ; à la
--  sortie on recréait des copies depuis ServerStorage. Résultat :
--    • les outils rangés ailleurs (Admin Abuse, Halloween, quête Noob…) étaient perdus ;
--    • les attributs étaient perdus (prêts admin, outils de session, skins…) ;
--    • un outil reçu PENDANT le PvP (gamepass au respawn, Daily, prêt admin…)
--      arrivait au milieu des armes, puis était détruit à la sortie.
--  Maintenant : les vrais outils sont retirés du sac (Parent = nil, comme le
--  tutoriel), gardés en mémoire, et TOUT outil non-PvP qui arrive pendant
--  l'arène est mis de côté lui aussi. À la sortie, on les rend (sans doublons,
--  sans les prêts expirés ni les outils d'un Admin Abuse terminé).
--  La faux de Jack (JackScythe) n'est jamais touchée : elle reste en PvP.
--════════════════════════════════════════════════════════════════════════════
local arenaStash = {}   -- [uid] = { Tool, … }  (Parent = nil)
--  🆕 StarterGear : pendant l'arène, il ne contient QUE les armes PvP.
--     Roblox recopie le StarterGear dans le sac à chaque réapparition :
--     avant, il recopiait les coils / le jetpack de l'obby (visibles une
--     demi-seconde avant les armes). Maintenant il recopie directement les
--     armes : le joueur réapparaît avec ses armes, tout de suite.
local gearStash = {}    -- [uid] = { Tool, … } outils de l'obby sortis du StarterGear
local playerSavedGear = {}

local function isArenaTool(t)
	return t:GetAttribute("ArenaWeapon") == true or t:GetAttribute("JackScythe") ~= nil
end

local function stashTool(player, tool)
	if not (tool and tool:IsA("Tool")) or isArenaTool(tool) then return end
	local uid = player.UserId
	arenaStash[uid] = arenaStash[uid] or {}
	for _, t in ipairs(arenaStash[uid]) do if t == tool then return end end
	table.insert(arenaStash[uid], tool)
	tool.Parent = nil
	playerSavedTools[uid] = playerSavedTools[uid] or {}
	table.insert(playerSavedTools[uid], tool.Name)
end

local function stashGear(player, tool)
	if not (tool and tool:IsA("Tool")) or isArenaTool(tool) then return end
	local uid = player.UserId
	gearStash[uid] = gearStash[uid] or {}
	for _, t in ipairs(gearStash[uid]) do if t == tool then return end end
	table.insert(gearStash[uid], tool)
	tool.Parent = nil
	playerSavedGear[uid] = playerSavedGear[uid] or {}
	table.insert(playerSavedGear[uid], tool.Name)
end

local function stashAll(player)
	local sg = player:FindFirstChild("StarterGear")
	if sg then
		for _, t in ipairs(sg:GetChildren()) do
			if t:IsA("Tool") and not isArenaTool(t) then stashGear(player, t) end
		end
	end
	for _, holder in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if holder then
			for _, t in ipairs(holder:GetChildren()) do
				if t:IsA("Tool") and not isArenaTool(t) then stashTool(player, t) end
			end
		end
	end
end

local function savePlayerTools(player)
	local uid = player.UserId
	playerSavedTools[uid] = playerSavedTools[uid] or {}
	stashAll(player)
	if #playerSavedTools[uid] > 0 then
		print("✅ Tools mis de côté pour " .. player.Name .. ": " .. table.concat(playerSavedTools[uid], ", "))
	end
end

local function keepAfterArena(tool, now)
	local exp = tonumber(tool:GetAttribute("AdminLoanExpiresAt")) or tonumber(tool:GetAttribute("CarryExpiresAt"))
	if exp and exp <= now then return false end                          -- prêt terminé pendant le PvP
	local aa = tool:GetAttribute("AAEventTool")
	if aa ~= nil then                                                    -- Admin Abuse terminé entre-temps
		local AA = _G.AdminAbuse
		local active = AA and AA.Active and AA.Active()
		local run = AA and AA.RunId and tostring(AA.RunId())
		if not active or (run and run ~= tostring(aa)) then return false end
	end
	return true
end

local function restoreGear(player)
	local uid = player.UserId
	local list = gearStash[uid]
	gearStash[uid] = nil
	playerSavedGear[uid] = nil
	local sg = player:FindFirstChild("StarterGear")
	--  les armes PvP sortent du StarterGear
	if sg then
		for _, t in ipairs(sg:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("ArenaWeapon") == true then t:Destroy() end
		end
	end
	if not list then return end
	if not sg then for _, t in ipairs(list) do pcall(function() t:Destroy() end) end return end
	local have, now = {}, os.time()
	for _, t in ipairs(sg:GetChildren()) do if t:IsA("Tool") then have[t.Name] = true end end
	for _, tool in ipairs(list) do
		if have[tool.Name] or not keepAfterArena(tool, now) then
			pcall(function() tool:Destroy() end)
		else
			have[tool.Name] = true
			tool.Parent = sg
		end
	end
end

local function restorePlayerTools(player)
	restoreGear(player)
	local uid = player.UserId
	local list = arenaStash[uid]
	arenaStash[uid] = nil
	playerSavedTools[uid] = nil
	if not list or #list == 0 then return end
	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then
		for _, t in ipairs(list) do pcall(function() t:Destroy() end) end
		return
	end
	local have = {}
	for _, holder in ipairs({ bp, player.Character }) do
		if holder then
			for _, t in ipairs(holder:GetChildren()) do
				if t:IsA("Tool") then have[t.Name] = true end
			end
		end
	end
	local now = os.time()
	local AA = _G.AdminAbuse
	local restored = {}
	for _, tool in ipairs(list) do
		local drop = false
		local exp = tonumber(tool:GetAttribute("AdminLoanExpiresAt")) or tonumber(tool:GetAttribute("CarryExpiresAt"))
		if exp and exp <= now then drop = true end                       -- prêt terminé pendant le PvP
		local aa = tool:GetAttribute("AAEventTool")
		if aa ~= nil then                                                -- Admin Abuse terminé entre-temps
			local active = AA and AA.Active and AA.Active()
			local run = AA and AA.RunId and tostring(AA.RunId())
			if not active or (run and run ~= tostring(aa)) then drop = true end
		end
		if have[tool.Name] then drop = true end                          -- jamais de doublon
		if drop then
			pcall(function() tool:Destroy() end)
		else
			have[tool.Name] = true
			tool.Parent = bp
			table.insert(restored, tool.Name)
		end
	end
	if #restored > 0 then print("✅ Tools rendus à " .. player.Name .. ": " .. table.concat(restored, ", ")) end
end

--  Pendant l'arène, tout outil non-PvP qui arrive (copie de StarterGear au
--  respawn, gamepass, Daily, prêt admin…) est mis de côté immédiatement.
local function inArenaState(player)
	local st = playerStates[player.UserId]
	return st == true or st == "entering"
end
local function watchHolder(player, holder, isGear)
	local function take(t)
		if t.Parent ~= holder or not inArenaState(player) then return end
		if isGear then stashGear(player, t) else stashTool(player, t) end
	end
	holder.ChildAdded:Connect(function(t)
		if not t:IsA("Tool") or isArenaTool(t) then return end
		if not inArenaState(player) then return end
		task.defer(take, t)
	end)
	--  ce qui est déjà dedans (un sac neuf arrive parfois déjà rempli)
	if inArenaState(player) then
		for _, t in ipairs(holder:GetChildren()) do
			if t:IsA("Tool") and not isArenaTool(t) then task.defer(take, t) end
		end
	end
end
local function watchPlayerTools(player)
	local function onBackpack(c) if c:IsA("Backpack") then watchHolder(player, c) end end
	for _, c in ipairs(player:GetChildren()) do onBackpack(c) end
	player.ChildAdded:Connect(onBackpack)
	if player.Character then watchHolder(player, player.Character) end
	player.CharacterAdded:Connect(function(char) watchHolder(player, char) end)
	task.spawn(function()
		local sg = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 15)
		if sg then watchHolder(player, sg, true) end
	end)
end
Players.PlayerAdded:Connect(watchPlayerTools)
for _, p in ipairs(Players:GetPlayers()) do watchPlayerTools(p) end

_G.GetArenaSavedTools = function(uid) return playerSavedTools[uid] end
_G.GetArenaSavedGear = function(uid) return playerSavedGear[uid] end

local function giveGuns(player)
	local bp = player:FindFirstChild("Backpack")
	if not bp then return end

	-- 🔑 Déséquiper AVANT de détruire : sinon le coil équipé est détruit sans que
	-- son Unequipped ne se déclenche → son effet (speed / anti-gravité) reste collé.
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()   -- renvoie l'outil équipé au Backpack + déclenche Unequipped
	end
	task.wait()                   -- laisse Unequipped s'exécuter (le coil annule son effet)

	--  anciennes armes d'arène → détruites ; tout autre outil → mis de côté (jamais perdu)
	for _, holder in ipairs({ bp, char }) do
		if holder then
			for _, item in ipairs(holder:GetChildren()) do
				if item:IsA("Tool") then
					if item:GetAttribute("ArenaWeapon") == true then item:Destroy()
					elseif not item:GetAttribute("JackScythe") then stashTool(player, item) end
				end
			end
		end
	end

	local skinMap = _G.GetSelectedGunskins and _G.GetSelectedGunskins(player.UserId) or {}

	local function cloneGun(baseName)
		local skinId = skinMap[baseName]
		if skinId and skinId ~= "" then
			local skinnedName = baseName .. "_" .. skinId
			local skinnedTool = ServerStorage:FindFirstChild(skinnedName)
			if skinnedTool and skinnedTool:IsA("Tool") then
				return skinnedTool:Clone()
			end
			warn(string.format("⚠️ Skin tool '%s' introuvable, fallback sur '%s'", skinnedName, baseName))
		end
		local baseTool = ServerStorage:FindFirstChild(baseName)
		if baseTool and baseTool:IsA("Tool") then return baseTool:Clone() end
		warn(string.format("⚠️ Tool '%s' introuvable dans ServerStorage", baseName))
		return nil
	end

	local hasPassShotgun = ownsPass(player.UserId, GAMEPASS_SHOTGUN.id)
	local hasPass2       = ownsPass(player.UserId, GAMEPASS_2.id)      -- 👑 VIP (pass OU offert)
	local hasPassAK47    = ownsPass(player.UserId, GAMEPASS_AK47.id)
	local hasPass1       = ownsPass(player.UserId, GAMEPASS_1.id)
	local hasPassMinigun = ownsPass(player.UserId, GAMEPASS_MINIGUN.id)
	local inGroup = player:IsInGroup(GROUP_ID)

	local spinWeapons   = (_G.GetPlayerSpinWeapons   and _G.GetPlayerSpinWeapons(player.UserId))   or {}
	local streakWeapons = (_G.GetStreakTempWeapons   and _G.GetStreakTempWeapons(player.UserId))   or {}

	local orderedGuns = {}
	if hasPassShotgun then table.insert(orderedGuns, "ShotGun") end
	if hasPassAK47    then table.insert(orderedGuns, "AK47")    end
	--  👑 L'arme VIP est lue dans GAMEPASS_2.guns : pour changer d'arme VIP,
	--     c'est la seule ligne à modifier (en haut du script).
	if hasPass2 then
		for _, g in ipairs(GAMEPASS_2.guns) do table.insert(orderedGuns, g) end
	end
	if hasPassMinigun then table.insert(orderedGuns, "Minigun") end
	table.insert(orderedGuns, "Sniper")
	if hasPass1 then table.insert(orderedGuns, "RPG") end
	if inGroup  then table.insert(orderedGuns, GROUP_GUN) end

	local already = {}
	for _, n in ipairs(orderedGuns) do already[n] = true end
	for weaponName in pairs(spinWeapons) do
		if not already[weaponName] then
			table.insert(orderedGuns, weaponName)
			already[weaponName] = true
		end
	end

	-- 🔥 Armes temporaires de streak (1 jour) — uniquement en 1v1
	for weaponName in pairs(streakWeapons) do
		if not already[weaponName] then
			table.insert(orderedGuns, weaponName)
			already[weaponName] = true
		end
	end

	--  StarterGear : les anciennes armes partent, les outils de l'obby sont mis de côté
	local sg = player:FindFirstChild("StarterGear")
	if sg then
		for _, item in ipairs(sg:GetChildren()) do
			if item:IsA("Tool") then
				if item:GetAttribute("ArenaWeapon") == true then item:Destroy()
				elseif not item:GetAttribute("JackScythe") then stashGear(player, item) end
			end
		end
	end
	for _, name in ipairs(orderedGuns) do
		local tool = cloneGun(name)
		if tool then
			tool:SetAttribute("ArenaWeapon", true)   -- arme du PvP (détruite à la sortie)
			--  une copie dans le StarterGear : Roblox la redonne tout de suite à chaque réapparition
			if sg then
				local g = tool:Clone()
				g.Parent = sg
			end
			tool.Parent = bp
		end
	end

	local skinLog = {}
	for wpn, sid in pairs(skinMap) do table.insert(skinLog, wpn.."="..sid) end
	local spinLog = {}
	for w in pairs(spinWeapons) do table.insert(spinLog, w) end
	print(string.format("✅ Armes données à %s | Skins: [%s] | Spin: [%s]",
		player.Name,
		#skinLog > 0 and table.concat(skinLog, ", ") or "aucun",
		#spinLog > 0 and table.concat(spinLog, ", ") or "aucune"))
end

-- 🔄 Un admin donne / retire le VIP → la Scar apparaît ou disparaît tout de
--    suite pour ceux qui sont en arène. Les autres l'auront au prochain spawn.
task.spawn(function()
	local ev = game:GetService("ServerStorage"):WaitForChild("VIPStatusChanged", 60)
	if not ev then return end
	ev.Event:Connect(function(userId)
		arenaPassCache[userId] = nil          -- force une re-vérification propre
		if _G.PlayersInArena and _G.PlayersInArena[userId] then
			local p = Players:GetPlayerByUserId(userId)
			if p and p.Character then task.spawn(giveGuns, p) end
		end
	end)
end)

-- 🔫 Une arme permanente vient d'être chargée ou débloquée (spin, cadeau,
--    quête) → si le joueur est en arène et qu'elle lui manque, on la lui
--    donne tout de suite au lieu d'attendre son prochain respawn.
task.spawn(function()
	local ev = ServerStorage:WaitForChild("SpinWeaponsChanged", 60)
	if not ev then return end
	ev.Event:Connect(function(userId)
		if not (_G.PlayersInArena and _G.PlayersInArena[userId]) then return end
		local p = Players:GetPlayerByUserId(userId)
		if not (p and p.Character) then return end
		local bp = p:FindFirstChild("Backpack")
		local weapons = (_G.GetPlayerSpinWeapons and _G.GetPlayerSpinWeapons(userId)) or {}

		-- « AK47 » compte aussi sous sa version skinnée « AK47_<skin> »
		local function hasTool(name)
			for _, holder in ipairs({ bp, p.Character }) do
				if holder then
					for _, t in ipairs(holder:GetChildren()) do
						if t:IsA("Tool") and (t.Name == name or t.Name:sub(1, #name + 1) == name .. "_") then
							return true
						end
					end
				end
			end
			return false
		end

		for name in pairs(weapons) do
			if not hasTool(name) then
				task.spawn(giveGuns, p)   -- skins compris
				return
			end
		end
	end)
end)

local function removeAllWeapons(player)
	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid:UnequipTools()
	task.wait(0.1)

	--  seulement les armes du PvP ; un autre outil arrivé à la dernière seconde
	--  est mis de côté puis rendu avec les autres
	for _, holder in ipairs({ char, player:FindFirstChild("Backpack") }) do
		if holder then
			for _, item in ipairs(holder:GetChildren()) do
				if item:IsA("Tool") then
					if item:GetAttribute("ArenaWeapon") == true then item:Destroy()
					elseif not item:GetAttribute("JackScythe") then stashTool(player, item) end
				end
			end
		end
	end

	print("✅ Toutes les armes retirées de " .. player.Name)
end

-- 🧹 Annule les effets persistants des coils (speed / gravity / fusion) quand on
-- entre en arène et que giveGuns détruit les tools SANS passer par Unequipped.
local function sanitizeCoilEffects(player)
	local char = player.Character
	if not char then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		-- remet la vitesse de base à partir des attributs posés par les coils corrigés
		local fusionBase = hum:GetAttribute("FusionSpeed_Base")
		if fusionBase then hum.WalkSpeed = fusionBase end
		local speedBoost = hum:GetAttribute("SpeedCoil_Boost")
		if speedBoost then hum.WalkSpeed = math.max(0, hum.WalkSpeed - speedBoost) end
		hum:SetAttribute("FusionSpeed_Base", nil)
		hum:SetAttribute("FusionSpeed_Active", nil)
		hum:SetAttribute("SpeedCoil_Boost", nil)
	end

	-- retire les forces d'anti-gravité et la fumée laissées par les coils
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("BodyForce") and d.Name == "GravityCoilEffect")
			or (d:IsA("Smoke") and d.Name == "CoilSmoke") then
			d:Destroy()
		end
	end
end

-- ❤️ PV D'ARÈNE ⬅ AJOUTÉ (2/6)
-- À appeler à l'ENTRÉE et à CHAQUE RESPAWN en arène : un nouveau personnage
-- revient toujours à 100 PV, il faut donc réappliquer les 200.
local function applyArenaHealth(player, char)
	char = char or player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	if not hum then return false end

	local uid = player.UserId
	-- mémorise les PV d'origine UNE seule fois (avant le tout premier passage à 200)
	if playerOriginalHealth[uid] == nil and hum.MaxHealth ~= ARENA_HEALTH then
		playerOriginalHealth[uid] = hum.MaxHealth
	end

	hum.MaxHealth = ARENA_HEALTH
	hum.Health = ARENA_HEALTH
	print("❤️ " .. player.Name .. " → " .. ARENA_HEALTH .. " PV (arène)")
	return true
end

local function restoreNormalHealth(player)
	local uid = player.UserId
	local base = playerOriginalHealth[uid] or NORMAL_HEALTH
	playerOriginalHealth[uid] = nil

	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	hum.MaxHealth = base
	hum.Health = base   -- sort de l'arène en pleine vie.
	-- (Si tu préfères qu'il garde ses PV actuels, supprime la ligne ci-dessus :
	--  Roblox rabote tout seul Health à MaxHealth, aucun risque de mort.)
	print("❤️ " .. player.Name .. " → " .. base .. " PV (hors arène)")
end

local function teleportToArena(player)
	local char = player.Character
	if not char then return false end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local spawns = getArenaSpawns()
	if #spawns > 0 then
		local randomSpawn = spawns[math.random(1, #spawns)]
		_G.SafeTeleport(char, randomSpawn.CFrame * CFrame.new(0, 3, 0))
		print("✅ " .. player.Name .. " téléporté dans l'arène")
		return true
	else
		warn("⚠️ Aucun spawn d'arène trouvé!")
	end

	return false
end

-- Entrée dans l'arène
enterArenaEvent.OnServerEvent:Connect(function(player)
	print("🔵 Requête d'entrée en arène reçue de " .. player.Name)

	local uid = player.UserId

	if debounce[uid] and tick() - debounce[uid] < COOLDOWN then
		print("⏳ Cooldown actif pour " .. player.Name)
		return
	end
	debounce[uid] = tick()

	if playerStates[uid] then
		print("⚠️ " .. player.Name .. " est déjà en arène")
		return
	end
	playerStates[uid] = "entering"

	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp and not isInPvpZone(hrp.Position) then
			playerCheckpointPositions[uid] = hrp.CFrame
			print("💾 Position actuelle sauvegardée pour " .. player.Name)
		elseif hrp then
			-- déjà dans la zone PvP (arrivé par le cross-server) : la sortie le renverra à son checkpoint
			playerCheckpointPositions[uid] = nil
			playerFromTeleport[uid] = true
		end
	end

	if not isArenaSpawn(player.RespawnLocation) then
		playerOriginalSpawns[uid] = player.RespawnLocation
	end
	print("💾 RespawnLocation original sauvegardé pour " .. player.Name)

	savePlayerTools(player)

	if not assignRandomArenaSpawn(player) then
		print("❌ Impossible d'assigner un spawn d'arène")
		playerStates[uid] = nil
		restorePlayerTools(player)   -- entrée ratée : il récupère tout de suite ses outils
		return
	end

	if teleportToArena(player) then
		giveGuns(player)
		applyArenaHealth(player)   -- ⬅ AJOUTÉ (3/6) : 200 PV

		playerStates[uid] = true
		_G.PlayersInArena[uid] = true
		player:SetAttribute("InArena", true)

		-- ✅ Signal dédié : forcer ON (tout cacher)
		hideUIEvent:FireClient(player, true)
		uiToggleEvent:FireClient(player, "enter", false)
		uiToggleEvent:FireClient(player, "exit", true)

		print("✅ " .. player.Name .. " a rejoint l'arène")
	else
		playerStates[uid] = nil
		restorePlayerTools(player)   -- entrée ratée : il récupère tout de suite ses outils
		print("❌ Échec de l'entrée en arène pour " .. player.Name)
	end
end)

-- Sortie de l'arène
exitArenaEvent.OnServerEvent:Connect(function(player)
	print("🔴 Requête de sortie d'arène reçue de " .. player.Name)

	local uid = player.UserId

	if debounce[uid] and tick() - debounce[uid] < COOLDOWN then
		print("⏳ Cooldown actif pour " .. player.Name)
		return
	end
	debounce[uid] = tick()

	if not playerStates[uid] then
		print("⚠️ " .. player.Name .. " n'est pas en arène")
		return
	end

	playerStates[uid] = false
	_G.PlayersInArena[uid] = nil
	player:SetAttribute("InArena", false)
	print("✅ Statut d'arène retiré pour " .. player.Name)

	local originalSpawn = playerOriginalSpawns[uid]
	if isArenaSpawn(originalSpawn) then originalSpawn = nil end   -- jamais un spawn de l'arène
	player.RespawnLocation = originalSpawn   -- nil = le système de checkpoints gère le respawn
	print("♻️ RespawnLocation restauré pour " .. player.Name)

	removeAllWeapons(player)
	restoreNormalHealth(player)   -- ⬅ AJOUTÉ (4/6) : retour à 100 PV
	task.wait(0.15)

	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local savedPosition = playerCheckpointPositions[uid]

		if savedPosition and isInPvpZone(savedPosition.Position) then savedPosition = nil end
		if hrp and savedPosition then
			_G.SafeTeleport(char, savedPosition)
			print("✅ " .. player.Name .. " téléporté à la position sauvegardée")
		elseif hrp and (playerFromTeleport[uid] or not originalSpawn) then
			-- 🆕 arrivé via ServerBrowser : renvoie à SON checkpoint actuel (obby normal)
			local target = _G.GetCheckpointForExit and _G.GetCheckpointForExit(player)
			if target then
				_G.SafeTeleport(char, target.CFrame * CFrame.new(0, 3, 0))
				print("✅ " .. player.Name .. " renvoyé à son checkpoint (arrivé par téléport)")
			else
				warn("⚠️ Checkpoint introuvable pour " .. player.Name)
			end
		elseif hrp and originalSpawn then
			_G.SafeTeleport(char, originalSpawn.CFrame * CFrame.new(0, 3, 0))
			print("✅ " .. player.Name .. " téléporté au RespawnLocation (fallback)")
		end
	end

	task.wait(0.1)
	restorePlayerTools(player)

	playerOriginalSpawns[uid] = nil
	playerCheckpointPositions[uid] = nil
	playerFromTeleport[uid] = nil

	-- ✅ Signal dédié : forcer OFF (tout réafficher)
	hideUIEvent:FireClient(player, false)
	uiToggleEvent:FireClient(player, "enter", true)
	uiToggleEvent:FireClient(player, "exit", false)

	print("✅ " .. player.Name .. " a quitté l'arène")
end)

-- Nettoyage déconnexion
Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	playerStates[uid] = nil
	playerOriginalSpawns[uid] = nil
	playerCheckpointPositions[uid] = nil
	--  la liste des outils mis de côté reste lisible 30 s (SessionToolCarry la lit
	--  au départ du joueur pour les lui rendre s'il revient vite)
	task.delay(30, function()
		if not Players:GetPlayerByUserId(uid) then
			playerSavedTools[uid] = nil
			playerSavedGear[uid] = nil
			for _, t in ipairs(gearStash[uid] or {}) do pcall(function() t:Destroy() end) end
			gearStash[uid] = nil
			local l = arenaStash[uid]
			arenaStash[uid] = nil
			for _, t in ipairs(l or {}) do pcall(function() t:Destroy() end) end
		end
	end)
	debounce[uid] = nil
	arenaPassCache[uid] = nil
	playerFromTeleport[uid] = nil
	playerOriginalHealth[uid] = nil   -- ⬅ AJOUTÉ (5/6)
	_G.PlayersInArena[uid] = nil
end)

-- Respawn dans l'arène
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		local uid = player.UserId
		if playerStates[uid] and _G.PlayersInArena[uid] then
			task.wait(0.1)
			assignRandomArenaSpawn(player)
			--  les armes arrivent toutes seules par le StarterGear ; on ne les
			--  redonne que s'il en manque (StarterGear vide, ancien serveur…)
			local bp = player:FindFirstChildOfClass("Backpack")
			local hasGuns = false
			for _, holder in ipairs({ bp, char }) do
				if holder then
					for _, t in ipairs(holder:GetChildren()) do
						if t:IsA("Tool") and t:GetAttribute("ArenaWeapon") == true then hasGuns = true end
					end
				end
			end
			if not hasGuns then giveGuns(player) end
			sanitizeCoilEffects(player)
			applyArenaHealth(player, char)   -- ⬅ AJOUTÉ (6/6) : le respawn repart à 100 → on remet 200
			print("♻️ " .. player.Name .. " a respawn dans l'arène avec un nouveau spawn aléatoire")
		end
	end)
end)

-- 🆕 MOUVEMENT PVP : l'effet du double saut + les sons (saut, slide) sont relayés à tout le monde.
-- Le serveur vérifie seulement que le joueur est en arène, que l'effet est
-- à ses pieds et qu'il n'en envoie pas en rafale. Aucun impact gameplay.
local moveFXEvent = ReplicatedStorage:FindFirstChild("ArenaMoveFX") or Instance.new("RemoteEvent")
moveFXEvent.Name = "ArenaMoveFX"
moveFXEvent.Parent = ReplicatedStorage
local moveFXLast = {}
local MOVE_FX_GAP = { djump = 0.2, jump = 0.12, slide = 0.12, slideend = 0.05 }
moveFXEvent.OnServerEvent:Connect(function(player, kind, pos)
	local gap = MOVE_FX_GAP[kind]
	if not gap or typeof(pos) ~= "Vector3" or pos ~= pos then return end
	if not playerStates[player.UserId] then return end
	local now = os.clock()
	local last = moveFXLast[player]
	if not last then last = {}; moveFXLast[player] = last end
	if last[kind] and now - last[kind] < gap then return end
	last[kind] = now
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - pos).Magnitude > 12 then return end
	moveFXEvent:FireAllClients(player, kind, pos)
end)
Players.PlayerRemoving:Connect(function(p) moveFXLast[p] = nil end)

print("✅ Système d'arène 1v1 chargé avec succès!")

_G.ForceEnterArena = function(player)
	local uid = player.UserId
	if playerStates[uid] then return false end

	local char = player.Character
	if not char then return false end

	playerOriginalSpawns[uid] = (not isArenaSpawn(player.RespawnLocation)) and player.RespawnLocation or nil
	playerCheckpointPositions[uid] = nil
	savePlayerTools(player)

	if not assignRandomArenaSpawn(player) then restorePlayerTools(player) return false end

	if teleportToArena(player) then
		giveGuns(player)
		sanitizeCoilEffects(player)
		applyArenaHealth(player)   -- ⬅ AJOUTÉ (6/6 bis) : 200 PV aussi via téléport
		playerStates[uid] = true
		_G.PlayersInArena[uid] = true
		playerFromTeleport[uid] = true   -- 🆕 marque l'arrivée par téléport
		player:SetAttribute("InArena", true)

		hideUIEvent:FireClient(player, true)
		uiToggleEvent:FireClient(player, "enter", false)
		uiToggleEvent:FireClient(player, "exit", true)

		print("✅ " .. player.Name .. " entré en arène via téléport")
		return true
	end

	restorePlayerTools(player)
	return false
end