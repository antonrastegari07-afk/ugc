-- ============================================================
-- POPUP DE DÉPART (Exit Intent) - Script (ServerScriptService)
-- ============================================================
-- Quand le joueur ouvre le menu Roblox pour quitter (Escape sur PC,
-- bouton Roblox sur mobile), on affiche un overlay qui lui propose
-- une récompense pour rester.
--
--   • S'affiche UNE SEULE FOIS PAR JOUEUR (jamais deux fois, même
--     entre plusieurs parties) -> enregistré dans un DataStore.
--   • Récompense CLAIM = tool "FusionCoil" (ServerStorage) donné
--     pour toute la SESSION : conservé aux respawns (StarterGear),
--     perdu au rejoin (non sauvegardé).
--
-- ⚠️ Roblox ne permet PAS de bloquer le vrai bouton "Leave" ni de
-- fermer le menu Roblox. L'overlay dissuade mais ne peut pas
-- empêcher physiquement le départ.
-- ============================================================

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- DataStore dédié (mémorise que le popup a déjà été proposé)
local leavePopupStore = DataStoreService:GetDataStore("LeavePopupShown_v8")

-- Configuration
local REWARD_TOOL_NAME = "FusionCoil" -- Nom du Tool dans ServerStorage

-- ============================================================
-- REMOTEEVENTS
-- ============================================================
local function getOrCreateRemote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local requestLeavePopup = getOrCreateRemote("RequestLeavePopup") -- client -> serveur (le menu s'est ouvert)
local showLeavePopup    = getOrCreateRemote("ShowLeavePopup")    -- serveur -> client (afficher l'overlay)
local claimRewardEvent  = getOrCreateRemote("ClaimLeaveReward")  -- client -> serveur (bouton CLAIM)

-- ============================================================
-- TABLES
-- ============================================================
local hasShownEver     = {} -- [userId] = true  déjà proposé (chargé du DataStore)
local dataReady        = {} -- [userId] = true  DataStore lu
local shownThisSession = {} -- [userId] = true  overlay affiché durant cette session
local claimed          = {} -- [userId] = true  récompense déjà réclamée cette session
local lastReminder     = {} -- [userId] = os.clock() du dernier rappel rouge
local REMINDER_COOLDOWN = 600 -- secondes entre 2 rappels (10 min)

print("🚪 SYSTÈME POPUP DE DÉPART démarré")

-- ============================================================
-- CHARGEMENT DU STATUT AU JOIN
-- ============================================================
local function loadStatus(player)
	local userId = player.UserId
	task.spawn(function()
		local ok, result = pcall(function()
			return leavePopupStore:GetAsync(tostring(userId))
		end)
		if ok and result == true then
			hasShownEver[userId] = true
		end
		dataReady[userId] = true
	end)
end

-- ============================================================
-- DEMANDE D'AFFICHAGE (menu ouvert côté client)
-- ============================================================
requestLeavePopup.OnServerEvent:Connect(function(player)
	local userId = player.UserId

	-- Tant que le DataStore n'est pas lu, on ne montre rien (évite un double affichage)
	if not dataReady[userId] then return end

	-- Déjà proposé (cette session ou une session précédente) -> ne plus jamais montrer
	if hasShownEver[userId] or shownThisSession[userId] then
		-- déjà proposé : plus de Fusion Coil, mais un rappel rouge (au plus 1 fois / 10 min)
		local now = os.clock()
		if not lastReminder[userId] or now - lastReminder[userId] >= REMINDER_COOLDOWN then
			lastReminder[userId] = now
			pcall(function() showLeavePopup:FireClient(player, "reminder") end)
		end
		return
	end

	-- Marquer immédiatement (session + persistant)
	hasShownEver[userId] = true
	shownThisSession[userId] = true

	-- Sauvegarder qu'on a proposé (une seule écriture)
	task.spawn(function()
		pcall(function()
			leavePopupStore:SetAsync(tostring(userId), true)
		end)
	end)

	-- Afficher l'overlay
	pcall(function()
		showLeavePopup:FireClient(player)
	end)

	print(string.format("🚪 Popup de départ affiché à %s (première et seule fois)", player.Name))
end)

-- ============================================================
-- RÉCOMPENSE : donner le tool FusionCoil pour la session
-- ============================================================
local function giveFusionCoil(player)
	local template = ServerStorage:FindFirstChild(REWARD_TOOL_NAME)
	if not template then
		warn(string.format("❌ Tool '%s' introuvable dans ServerStorage", REWARD_TOOL_NAME))
		return false
	end

	-- StarterGear -> le tool est re-donné à chaque respawn (durant la session)
	local starterGear = player:FindFirstChild("StarterGear")
	if starterGear and not starterGear:FindFirstChild(REWARD_TOOL_NAME) then
		template:Clone().Parent = starterGear
	end

	-- Backpack -> disponible tout de suite sans attendre un respawn
	local backpack = player:FindFirstChild("Backpack")
	if backpack and not backpack:FindFirstChild(REWARD_TOOL_NAME)
		and not (player.Character and player.Character:FindFirstChild(REWARD_TOOL_NAME)) then   -- déjà en main : pas de doublon
		template:Clone().Parent = backpack
	end

	return true
end

claimRewardEvent.OnServerEvent:Connect(function(player)
	local userId = player.UserId

	-- Autoriser seulement si l'overlay a été affiché cette session et pas déjà réclamé
	if not shownThisSession[userId] then return end
	if claimed[userId] then return end

	claimed[userId] = true

	if giveFusionCoil(player) then
		print(string.format("🎁 %s a réclamé FusionCoil (session)", player.Name))
	end
end)

-- ============================================================
-- ÉVÉNEMENTS JOUEURS
-- ============================================================
Players.PlayerAdded:Connect(function(player)
	loadStatus(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	-- Nettoyage mémoire uniquement (aucune sauvegarde ici)
	hasShownEver[userId] = nil
	dataReady[userId] = nil
	shownThisSession[userId] = nil
	claimed[userId] = nil
	lastReminder[userId] = nil
end)

print("✅ Système Popup de départ chargé")