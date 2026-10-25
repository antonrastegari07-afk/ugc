-- Script LocalScript à mettre dans la Frame parente (doit être dans StarterGui)
-- How to Play/HtpButton2 : s'affiche après le loading ET après le Rookie Guide.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local frame = script.Parent
local button = frame:FindFirstChild("ShopToggle", true)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Position centrale
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)

-- Caché tant qu'on n'a pas décidé de l'afficher (sinon UIFocusSystem le
-- considère ouvert sous le guide : flou + FOV 60)
frame.Visible = false

-- Variable pour éviter l'affichage multiple
local hasShownOnce = false

-- Fonction pour afficher le How to Play (avec l'animation d'entrée)
local function ShowShop()
	if hasShownOnce then return end
	hasShownOnce = true

	frame.Visible = true
	-- Relance l'animation de rebond du panneau intérieur (script "animations")
	local inner = frame:FindFirstChild("HtpButton")
	if inner and inner:IsA("GuiObject") then
		inner.Visible = false
		task.delay(0.05, function()
			if inner.Parent then inner.Visible = true end
		end)
	end
end

-- 🎓 ATTENDRE LA FIN DU ROOKIE GUIDE
-- Le guide publie PlayerGui.RookieGuideState : "pending" -> "running" -> "done".
local function waitRookieGuide()
	-- Laisse au guide le temps de se déclarer (s'il n'est pas installé : on n'attend pas plus)
	local t = 0
	while playerGui:GetAttribute("RookieGuideState") == nil and t < 5 do
		task.wait(0.1)
		t = t + 0.1
	end
	-- "pending" = vérification serveur en cours (sécurité : 60 s max)
	t = 0
	while playerGui:GetAttribute("RookieGuideState") == "pending" and t < 60 do
		task.wait(0.2)
		t = t + 0.2
	end
	-- "running" = le joueur fait le guide : on attend la fin, sans limite
	while playerGui:GetAttribute("RookieGuideState") == "running" do
		playerGui:GetAttributeChangedSignal("RookieGuideState"):Wait()
	end
end

-- 🔍 ATTENDRE LE FLAG DE FIN DU LOADING SCREEN
task.spawn(function()
	-- Attendre que le flag existe (max 30 secondes)
	local loadingCompleteFlag = ReplicatedStorage:WaitForChild("LoadingCompleteFlag", 30)

	if loadingCompleteFlag then
		-- Si le flag n'est pas encore true, attendre qu'il le devienne
		while loadingCompleteFlag.Value ~= true do
			loadingCompleteFlag.Changed:Wait()
		end
	else
		-- Fallback si le flag n'existe pas
		warn("⚠️ LoadingCompleteFlag introuvable après 30 secondes, utilisation du fallback")
		if not player.Character then player.CharacterAdded:Wait() end
		task.wait(2)
	end

	waitRookieGuide()
	task.wait(0.3)
	ShowShop()
end)

-- Bouton de fermeture
if button then
	button.MouseButton1Click:Connect(function()
		frame.Visible = false
	end)
else
	warn("Bouton ShopToggle introuvable dans les descendants de la frame")
end
