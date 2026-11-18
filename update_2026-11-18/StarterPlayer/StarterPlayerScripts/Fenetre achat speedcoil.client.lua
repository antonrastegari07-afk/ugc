-- LocalScript dans StarterPlayerScripts
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = require(game.ReplicatedStorage.MarketplaceServiceFX)
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local Gate = require(game:GetService("ReplicatedStorage"):WaitForChild("PopupGate"))   -- 🔔 admin ▸ POPUPS ▸ « Pads d'achat »
local remote = ReplicatedStorage:WaitForChild("fenetredachatSPEEDCOIL")

remote.OnClientEvent:Connect(function(gamepassId)
	if not Gate.Enabled("touch_pads") then return end   -- désactivé dans l'admin
	if typeof(gamepassId) ~= "number" then
		warn("PromptGamepassPurchase reçu un id invalide :", gamepassId)
		return
	end

	-- ✅ Ouvre la fenêtre d'achat correctement :
	MarketplaceService:PromptGamePassPurchase(player, gamepassId)
end)