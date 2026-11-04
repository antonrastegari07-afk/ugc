-- ============================================================
--  TutorialInventoryManager — Script (ServerScriptService)
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─────────────────────────────────────────────────────────────
-- REMOTES
-- S'assure que le dossier Remotes et les events existent
-- ─────────────────────────────────────────────────────────────
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name   = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local function getOrCreate(className, name)
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(className)
	obj.Name   = name
	obj.Parent = Remotes
	return obj
end

local evSaveInventory    = getOrCreate("RemoteEvent",    "TutorialSaveInventory")
local evRestoreInventory = getOrCreate("RemoteEvent",    "TutorialRestoreInventory")
local evTutorialStarted  = getOrCreate("RemoteEvent",    "TutorialStarted")
local evTutorialSeen     = getOrCreate("RemoteEvent",    "TutorialSeen")
local checkFirstJoin     = getOrCreate("RemoteFunction", "TutorialCheckFirstJoin")

-- ─────────────────────────────────────────────────────────────
-- STOCKAGE : inventaire sauvegardé par joueur
-- savedInventories[player] = { {tool = Instance, parent = Instance}, ... }
-- ─────────────────────────────────────────────────────────────
local savedInventories = {}

-- 🧰 pour SessionToolCarry : les outils mis de côté pendant le tutoriel
_G.GetTutorialSavedTools = function(player)
	local t = {}
	for _, e in ipairs(savedInventories[player] or {}) do table.insert(t, e.tool) end
	return t
end

-- ─────────────────────────────────────────────────────────────
-- STOCKAGE : joueurs ayant déjà vu le tuto
-- (en mémoire seulement — remplace par DataStore si tu veux persister)
-- ─────────────────────────────────────────────────────────────
local seenTutorial = {}

-- ─────────────────────────────────────────────────────────────
-- HELPER : trouver le Backpack et StarterGear du joueur
-- ─────────────────────────────────────────────────────────────
local function getBackpack(player)
	return player:FindFirstChildOfClass("Backpack")
end

local function getCharacterTools(player)
	-- Les outils équipés sont dans le Character
	local char = player.Character
	if not char then return {} end
	local tools = {}
	for _, obj in ipairs(char:GetChildren()) do
		if obj:IsA("Tool") then
			table.insert(tools, obj)
		end
	end
	return tools
end

-- ─────────────────────────────────────────────────────────────
-- SAUVEGARDER L'INVENTAIRE ET VIDER
-- ─────────────────────────────────────────────────────────────
local function saveAndClearInventory(player)
	local backpack = getBackpack(player)
	if not backpack then
		warn("[TutorialInventory] Backpack introuvable pour", player.Name)
		return
	end

	local saved = {}

	-- Sauvegarder et retirer les outils du Backpack
	for _, tool in ipairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then
			table.insert(saved, {
				tool   = tool,
				parent = backpack,
			})
			tool.Parent = nil  -- Sortir de l'inventaire sans détruire
		end
	end

	-- Sauvegarder et retirer les outils équipés (dans le Character)
	for _, tool in ipairs(getCharacterTools(player)) do
		table.insert(saved, {
			tool   = tool,
			parent = backpack,  -- On les remettra dans le backpack à la fin
		})
		tool.Parent = nil
	end

	--  tutoriel relancé : on AJOUTE à la sauvegarde au lieu de l'écraser
	--  (avant, la 2e sauvegarde était vide et les outils étaient perdus)
	local prev = savedInventories[player]
	if prev then
		for _, e in ipairs(saved) do table.insert(prev, e) end
		saved = prev
	end
	savedInventories[player] = saved

	if #saved > 0 then
		print(("[TutorialInventory] %s : %d outil(s) sauvegardé(s) et retirés"):format(player.Name, #saved))
	else
		print(("[TutorialInventory] %s : inventaire déjà vide"):format(player.Name))
	end
end

-- ─────────────────────────────────────────────────────────────
-- RESTAURER L'INVENTAIRE
-- ─────────────────────────────────────────────────────────────
local function restoreInventory(player)
	local saved = savedInventories[player]
	if not saved then
		warn("[TutorialInventory] Aucune sauvegarde pour", player.Name)
		return
	end

	local backpack = getBackpack(player)
	if not backpack then
		warn("[TutorialInventory] Backpack introuvable pour restauration :", player.Name)
		return
	end

	local restored = 0
	for _, entry in ipairs(saved) do
		local tool = entry.tool
		-- Vérifier que l'outil existe toujours (pas détruit entre-temps)
		if tool and tool.Parent == nil then
			tool.Parent = backpack
			restored += 1
		elseif tool and tool.Parent ~= nil then
			-- L'outil a été re-parenté ailleurs (rare), on le replace quand même
			tool.Parent = backpack
			restored += 1
		end
	end

	savedInventories[player] = nil

	print(("[TutorialInventory] %s : %d outil(s) restauré(s)"):format(player.Name, restored))
end

-- ─────────────────────────────────────────────────────────────
-- REMOTE : TutorialSaveInventory (FireServer depuis le client)
-- Appelé quand le joueur accepte de faire le tutoriel
-- ─────────────────────────────────────────────────────────────
evSaveInventory.OnServerEvent:Connect(function(player)
	print(("[TutorialInventory] Demande de sauvegarde pour %s"):format(player.Name))
	saveAndClearInventory(player)
end)

-- ─────────────────────────────────────────────────────────────
-- REMOTE : TutorialRestoreInventory (FireServer depuis le client)
-- Appelé quand le joueur termine ou quitte le tutoriel
-- ─────────────────────────────────────────────────────────────
evRestoreInventory.OnServerEvent:Connect(function(player)
	print(("[TutorialInventory] Demande de restauration pour %s"):format(player.Name))
	restoreInventory(player)
end)

-- ─────────────────────────────────────────────────────────────
-- REMOTE : TutorialStarted
-- ─────────────────────────────────────────────────────────────
evTutorialStarted.OnServerEvent:Connect(function(player)
	print(("[Tutorial] %s a démarré le tutoriel"):format(player.Name))
end)

-- ─────────────────────────────────────────────────────────────
-- REMOTE : TutorialSeen
-- ─────────────────────────────────────────────────────────────
evTutorialSeen.OnServerEvent:Connect(function(player)
	seenTutorial[player] = true
	print(("[Tutorial] %s a vu le popup tutoriel"):format(player.Name))
end)

-- ─────────────────────────────────────────────────────────────
-- REMOTE FUNCTION : TutorialCheckFirstJoin
-- Retourne true si le joueur n'a PAS encore vu le tutoriel
-- ─────────────────────────────────────────────────────────────
checkFirstJoin.OnServerInvoke = function(player)
	return seenTutorial[player] ~= true
end

-- ─────────────────────────────────────────────────────────────
-- NETTOYAGE : quand un joueur quitte, restaurer son inventaire
-- si le tutoriel était en cours (au cas où il quitte pendant le tuto)
-- ─────────────────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	if savedInventories[player] then
		-- Le joueur a quitté pendant le tuto : nettoyer la mémoire
		-- (les outils sont de toute façon détruits avec le joueur)
		savedInventories[player] = nil
		print(("[TutorialInventory] Nettoyage mémoire pour %s (déconnexion)"):format(player.Name))
	end
	seenTutorial[player] = nil
end)