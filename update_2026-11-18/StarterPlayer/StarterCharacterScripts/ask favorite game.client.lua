local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local assetId = 107795556034608
local assetType = Enum.AvatarItemType.Asset

-- Attendre que les RemoteFunctions soient créées
local checkFavoritePrompted = ReplicatedStorage:WaitForChild("CheckFavoritePrompted", 10)
local saveFavoritePrompted = ReplicatedStorage:WaitForChild("SaveFavoritePrompted", 10)

if not checkFavoritePrompted or not saveFavoritePrompted then
	warn("RemoteFunctions non trouvées")
	return
end

-- 🔔 coupé avec « ⭐ Demande de favori » (ADMIN PANEL ▸ 🔔 POPUPS)
local Gate = require(ReplicatedStorage:WaitForChild("PopupGate"))

local function promptFavorite()
	if not Gate.Enabled("favorite") then return end
	if player:GetAttribute("InArena") == true then return end   -- jamais en plein combat
	-- Vérifier si déjà demandé via le serveur
	local success, alreadyPrompted = pcall(function()
		return checkFavoritePrompted:InvokeServer()
	end)

	if not success or alreadyPrompted then
		return -- Ne rien faire si déjà demandé ou erreur
	end

	-- Proposer le favori
	local promptSuccess, err = pcall(function()
		AvatarEditorService:PromptSetFavorite(assetId, assetType, true)
	end)

	if promptSuccess then
		-- Sauvegarder dans le DataStore via le serveur
		pcall(function()
			saveFavoritePrompted:InvokeServer()
		end)
	else
		warn("Erreur favori : " .. tostring(err))
	end
end

local function waitForDeath()
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")

	-- Attendre que le joueur meure
	humanoid.Died:Wait()

	-- Attendre 1 seconde après la mort pour proposer
	task.wait(1)
	promptFavorite()
end

-- Attendre 60 secondes
task.wait(60)

-- Ensuite attendre la mort du joueur
waitForDeath()