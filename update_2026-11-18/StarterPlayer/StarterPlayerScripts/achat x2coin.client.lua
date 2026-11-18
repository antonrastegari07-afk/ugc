local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = require(game.ReplicatedStorage.MarketplaceServiceFX)

local remote = ReplicatedStorage:WaitForChild("x2cointouch")

local Gate = require(game:GetService("ReplicatedStorage"):WaitForChild("PopupGate"))   -- 🔔 admin ▸ POPUPS ▸ « Pads d'achat »

remote.OnClientEvent:Connect(function(gamepassId)
	if not Gate.Enabled("touch_pads") then return end   -- désactivé dans l'admin
	local player = game.Players.LocalPlayer
	MarketplaceService:PromptGamePassPurchase(player, gamepassId)
end)