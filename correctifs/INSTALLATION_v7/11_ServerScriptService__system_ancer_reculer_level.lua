-- SYSTÈME NAVIGATION STAGE (SERVEUR) - ServerScriptService
-- Gère les demandes de navigation entre checkpoints depuis le client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configuration
local CHECKPOINT_PREFIX = "Checkpoint"

-- Tables externes (synchronisation avec le script checkpoint principal)
_G.StageNavigation = _G.StageNavigation or {}

-- RemoteEvent pour la navigation
local stageNavigationEvent = ReplicatedStorage:FindFirstChild("StageNavigationEvent")
if not stageNavigationEvent then
	stageNavigationEvent = Instance.new("RemoteEvent")
	stageNavigationEvent.Name = "StageNavigationEvent"
	stageNavigationEvent.Parent = ReplicatedStorage
end

-- ✅ Attendre ou créer l'événement CheckpointUpdated
local checkpointEvent = ReplicatedStorage:FindFirstChild("CheckpointUpdated")
if not checkpointEvent then
	-- Si l'événement n'existe pas encore, le créer
	checkpointEvent = Instance.new("RemoteEvent")
	checkpointEvent.Name = "CheckpointUpdated"
	checkpointEvent.Parent = ReplicatedStorage
	warn("⚠️ CheckpointUpdated créé par StageNavigation (devrait être créé par le script checkpoint principal)")
end

print("🎮 SYSTÈME NAVIGATION STAGE (SERVEUR) DÉMARRÉ")

-- ========================================
-- 📍 CACHE DES CHECKPOINTS
-- ========================================
local checkpointCache = {} -- [number] = BasePart
local checkpointsLoaded = false

-- Charger tous les checkpoints
task.spawn(function()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Name:lower():match("^" .. CHECKPOINT_PREFIX:lower()) then
			local num = tonumber(string.match(obj.Name, "%d+"))
			if num then
				checkpointCache[num] = obj
			end
		end
	end

	checkpointsLoaded = true
	print(string.format("✅ Navigation: %d checkpoints chargés", #checkpointCache))
end)

-- Écouter les nouveaux checkpoints
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") and obj.Name:lower():match("^" .. CHECKPOINT_PREFIX:lower()) then
		task.wait(0.05)
		local num = tonumber(string.match(obj.Name, "%d+"))
		if num then
			checkpointCache[num] = obj
		end
	end
end)

workspace.DescendantRemoving:Connect(function(obj)
	if obj:IsA("BasePart") then
		local num = tonumber(string.match(obj.Name, "%d+"))
		if num and checkpointCache[num] == obj then
			checkpointCache[num] = nil
		end
	end
end)

-- ========================================
-- 🎯 FONCTION DE TÉLÉPORTATION
-- ========================================
local function teleportToStage(player, targetStage)
	local userId = player.UserId

	-- Vérifier que le joueur n'est pas en arène
	if _G.PlayersInArena and _G.PlayersInArena[userId] then
		warn(string.format("⚠️ %s est en arène, navigation impossible", player.Name))
		return false
	end

	-- Vérifier que le stage existe
	local targetCheckpoint = checkpointCache[targetStage]

	if not targetCheckpoint or not targetCheckpoint.Parent then
		warn(string.format("⚠️ Checkpoint%d non trouvé pour %s", targetStage, player.Name))
		return false
	end

	-- Récupérer le personnage
	local character = player.Character
	if not character then
		warn(string.format("⚠️ %s n'a pas de personnage", player.Name))
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not hrp or not humanoid or humanoid.Health <= 0 then
		warn(string.format("⚠️ %s - HRP ou Humanoid invalide", player.Name))
		return false
	end

	-- Téléporter
	pcall(function()
		character:PivotTo(targetCheckpoint.CFrame * CFrame.new(0, 3, 0))
		hrp.AssemblyLinearVelocity = Vector3.zero
	end)

	-- Mettre à jour les données du système checkpoint principal
	-- (Utiliser les tables globales si elles existent)
	if _G.SessionCheckpoints then
		_G.SessionCheckpoints[userId] = "Checkpoint" .. targetStage
	end

	if _G.PlayerCheckpoints then
		_G.PlayerCheckpoints[userId] = targetStage
	end

	pcall(function() player:SetAttribute("StageNow", targetStage) end)

	-- Mettre à jour le leaderboard
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local stageValue = leaderstats:FindFirstChild("Stage")
		if stageValue then
			stageValue.Value = targetStage
		end
	end

	-- ✅ NOUVEAU: Notifier le client pour mettre à jour l'UI
	if checkpointEvent then
		task.spawn(function()
			pcall(function()
				checkpointEvent:FireClient(player, "Checkpoint" .. targetStage)
			end)
		end)
	end

	print(string.format("✅ %s téléporté au Stage %d", player.Name, targetStage))
	return true
end

-- ========================================
-- 📡 ÉCOUTE DES DEMANDES CLIENT
-- ========================================
-- 🔒 Le SERVEUR décide : il part du checkpoint ACTUEL du joueur (pas de ce que dit le client)
--    et refuse tout ce qui dépasse le plus haut checkpoint atteint (_G.StageMaxReached).
--    Avant, un exploiteur pouvait envoyer « 125 » et sauter tout l'obby.
local lastNav = {} -- [userId] = os.clock()
Players.PlayerRemoving:Connect(function(p) lastNav[p.UserId] = nil end)

stageNavigationEvent.OnServerEvent:Connect(function(player, request)
	local userId = player.UserId
	local t = os.clock()
	if t - (lastNav[userId] or 0) < 0.2 then return end   -- anti-spam
	lastNav[userId] = t

	local cur = _G.PlayerCheckpoints and _G.PlayerCheckpoints[userId]
	local maxReached = _G.StageMaxReached and _G.StageMaxReached[userId]
	if type(cur) ~= "number" or type(maxReached) ~= "number" then
		-- progression pas encore chargée : on ne bouge personne
		return
	end

	local targetStage
	if request == "up" then
		targetStage = cur + 1
	elseif request == "down" then
		targetStage = cur - 1
	elseif type(request) == "number" and request == request then
		targetStage = math.floor(request)   -- ancien client : accepté, mais vérifié pareil
	else
		return
	end

	if targetStage < 1 then
		warn(string.format("⚠️ %s - Stage %d trop bas (min: 1)", player.Name, targetStage))
		return
	end
	if targetStage > maxReached then
		-- jamais au-delà de ce qui a été atteint (le skip payant passe par SkipLevelEvent)
		return
	end

	-- Attendre que les checkpoints soient chargés
	if not checkpointsLoaded then
		local waited = 0
		while not checkpointsLoaded and waited < 10 do
			task.wait(0.5)
			waited = waited + 0.5
		end

		if not checkpointsLoaded then
			warn(string.format("⚠️ Checkpoints non chargés pour %s", player.Name))
			return
		end
	end

	-- Téléporter
	teleportToStage(player, targetStage)
end)

print("✅ Système Navigation Stage (Serveur) chargé")