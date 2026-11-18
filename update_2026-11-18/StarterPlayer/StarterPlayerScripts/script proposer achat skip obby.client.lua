local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local player = Players.LocalPlayer

-- ID du GamePass
local PASS_2 = 1894006285 -- toutes les 20 min

-- Fonction pour vérifier si le joueur possède un gamepass
local function hasGamepass(player, passId)
	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if success then
		return hasPass
	else
		warn("Erreur lors de la vérification du gamepass " .. passId)
		return false
	end
end

-- Fonction pour lancer un prompt sans erreur
local function promptPass(player, passId)
	-- Vérifier si le joueur possède déjà le pass
	if hasGamepass(player, passId) then
		return -- Ne rien faire si le joueur a déjà le pass
	end
	local success, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, passId)
	end)
	if not success then
		warn("Erreur lors du prompt du pass " .. passId .. ": " .. tostring(err))
	end
end

-- ⏱️ Fréquence + activation : ADMIN PANEL ▸ 🔔 POPUPS ▸ « ⏭️ Pass Skip Obby » (défaut 20 min)
local Gate = require(game:GetService("ReplicatedStorage"):WaitForChild("PopupGate"))
local POPUP_ID = "skip_obby_auto"
local ownsPass2 = false

task.spawn(function()
	while not ownsPass2 do
		Gate.WaitMinutes(POPUP_ID, "IntervalMin")
		if Gate.WaitTurn(POPUP_ID) then
			if hasGamepass(player, PASS_2) then
				ownsPass2 = true   -- déjà acheté : plus jamais de vérification
			else
				Gate.Shown(POPUP_ID)   -- avant la fenêtre : l'achat est attribué à ce popup dans les stats
				promptPass(player, PASS_2)
			end
		end
	end
end)