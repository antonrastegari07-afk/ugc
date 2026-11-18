-- LocalScript à placer dans votre ScreenGui
local screenGui = script.Parent
local frame = screenGui:WaitForChild("PopupFrame")

-- ⏱️ Fréquence + activation : ADMIN PANEL ▸ 🔔 POPUPS ▸ « 👑 Popup VIP » (défaut 13 min)
local Gate = require(game:GetService("ReplicatedStorage"):WaitForChild("PopupGate"))
local POPUP_ID = "vip_offer"
local GAMEPASS_ID = 1891589121

local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local originalSize = frame.Size

local ownsPass = false
local activeTween

frame.Visible = false

-- Vérification avec le service officiel Roblox
local function hasGamepass()
	if ownsPass then
		return true
	end

	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(
			player.UserId,
			GAMEPASS_ID
		)
	end)

	if not success then
		warn("Impossible de vérifier le gamepass : popup ignoré.")
		return nil
	end

	-- Conserver la possession une fois confirmée
	if result then
		ownsPass = true
	end

	return ownsPass
end

local function hideFrame()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end

	frame.Visible = false
	frame.Size = originalSize
end

local function showFrame()
	if ownsPass or frame.Visible then
		return
	end

	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.new(0, 0, 0, 0)
	frame.Visible = true

	activeTween = TweenService:Create(
		frame,
		TweenInfo.new(
			0.8,
			Enum.EasingStyle.Elastic,
			Enum.EasingDirection.Out
		),
		{ Size = originalSize }
	)

	activeTween:Play()
end

-- Si le joueur achète le pass pendant la partie
local purchaseConnection =
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(purchasingPlayer, passId, wasPurchased)
			if purchasingPlayer == player
				and passId == GAMEPASS_ID
				and wasPurchased then

				ownsPass = true
				hideFrame()
			end
		end
	)

-- Vérifier dès le lancement
hasGamepass()

-- Afficher uniquement aux joueurs sans le pass
while not ownsPass do
	Gate.WaitMinutes(POPUP_ID, "IntervalMin")   -- suit l'intervalle réglé dans l'admin

	if ownsPass then
		break
	end

	-- désactivé → on ne montre rien et on attend le prochain tour ;
	-- mode « inactif » / pause mini → on attend le bon moment
	if Gate.WaitTurn(POPUP_ID) and not ownsPass then
		-- nil (erreur) ne déclenche pas le popup
		if hasGamepass() == false then
			showFrame()
			Gate.Shown(POPUP_ID)
		end
	end
end

purchaseConnection:Disconnect()
hideFrame()