-- SYSTÈME NAVIGATION STAGE (+1/-1) - LocalScript dans StarterPlayerScripts
-- Permet de naviguer entre les checkpoints avec restrictions intelligentes

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = require(game.ReplicatedStorage.MarketplaceServiceFX)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Configuration
local SKIP_PRODUCT_ID = 3606598301
local DEBOUNCE_TIME = 0.2

-- RemoteEvents
local stageNavigationEvent = ReplicatedStorage:WaitForChild("StageNavigationEvent", 10)
local checkpointEvent = ReplicatedStorage:WaitForChild("CheckpointUpdated", 10)

if not stageNavigationEvent then
	warn("⚠️ StageNavigationEvent non trouvé dans ReplicatedStorage!")
end

-- Variables de session
local currentStage = 1
local maxStageReached = 1
local lastClickTime = 0
local isProcessing = false

-- ========================================
-- 📊 RÉCUPÉRATION DES BOUTONS
-- ========================================
local function getStageButtons()
	local stageGui = playerGui:WaitForChild("# Stage", 10)
	if not stageGui then
		warn("⚠️ ScreenGui '# Stage' non trouvé!")
		return nil, nil
	end

	local frame = stageGui:FindFirstChild("Frame")
	if not frame then
		warn("⚠️ Frame non trouvée dans '# Stage'!")
		return nil, nil
	end

	local stageFrame = frame:FindFirstChild("stageFrame")
	if not stageFrame then
		warn("⚠️ Frame 'stageFrame' non trouvée dans Frame!")
		return nil, nil
	end

	local plusButton = stageFrame:FindFirstChild("+1 level")
	local minusButton = stageFrame:FindFirstChild("-1 level")

	if not plusButton then
		warn("⚠️ Bouton '+1 level' non trouvé dans stageFrame!")
	end

	if not minusButton then
		warn("⚠️ Bouton '-1 level' non trouvé dans stageFrame!")
	end

	return plusButton, minusButton
end

local function getRebirthButton()
	local rebirthGui = playerGui:WaitForChild("Rebirth", 10)
	if not rebirthGui then return nil end

	local shopFrame = rebirthGui:FindFirstChild("ShopFrame")
	if not shopFrame then return nil end

	return shopFrame:FindFirstChild("Yesrebirth")
end

-- ========================================
-- 📊 MISE À JOUR DU STAGE ACTUEL
-- ========================================
local function updateCurrentStage()
	-- 🧭 valeurs du SERVEUR en priorité (attributs StageNow / StageMax) : leaderstats peut être
	--    recréé après le chargement et rester à 1 → c'était le « impossible de descendre ».
	local sNow, sMax = player:GetAttribute("StageNow"), player:GetAttribute("StageMax")
	if type(sNow) == "number" and type(sMax) == "number" then
		currentStage = sNow
		maxStageReached = sMax
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local stageValue = leaderstats:FindFirstChild("Stage")
		if stageValue then
			currentStage = stageValue.Value

			if currentStage > maxStageReached then
				maxStageReached = currentStage
			end
		end
	end
end

local function setupStageListener()
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local stageValue = leaderstats:WaitForChild("Stage", 10)
		if stageValue then
			currentStage = stageValue.Value
			maxStageReached = currentStage

			stageValue.Changed:Connect(function(newValue)
				currentStage = newValue

				if currentStage > maxStageReached then
					maxStageReached = currentStage
				end
			end)
		end
	end
end

-- ========================================
-- 🎯 NAVIGATION STAGE
-- ========================================
local function navigateStage(direction)
	local now = tick()
	if now - lastClickTime < DEBOUNCE_TIME then
		return
	end

	if isProcessing then
		return
	end

	lastClickTime = now

	updateCurrentStage()

	local targetStage = currentStage + direction

	if direction == 1 then
		if targetStage > maxStageReached then
			isProcessing = true

			local success, err = pcall(function()
				MarketplaceService:PromptProductPurchase(player, SKIP_PRODUCT_ID)
			end)

			if not success then
				warn("⚠️ Erreur lors de l'affichage du produit skip:", err)
			end

			task.wait(1)
			isProcessing = false
			return
		end

	elseif direction == -1 then
		if targetStage < 1 then
			warn("⚠️ Impossible de descendre en dessous du Stage 1")
			return
		end
	end

	if stageNavigationEvent then
		isProcessing = true

		-- le serveur calcule lui-même la cible depuis ton checkpoint actuel
		stageNavigationEvent:FireServer(direction == 1 and "up" or "down")

		task.wait(0.3)
		isProcessing = false
	else
		warn("⚠️ StageNavigationEvent non disponible!")
	end
end

-- ========================================
-- 🔄 GESTION DU REBIRTH
-- ========================================
local function setupRebirthListener()
	local rebirthButton = getRebirthButton()

	if rebirthButton and rebirthButton:IsA("GuiButton") then
		rebirthButton.MouseButton1Click:Connect(function()
			task.wait(1)

			updateCurrentStage()
			maxStageReached = currentStage
		end)
	else
		warn("⚠️ Bouton Rebirth non trouvé ou invalide")
	end
end

-- ========================================
-- 🎮 CONNEXION DES BOUTONS
-- ========================================
local function setupButtons()
	local plusButton, minusButton = getStageButtons()

	if plusButton and plusButton:IsA("GuiButton") then
		plusButton.MouseButton1Click:Connect(function()
			navigateStage(1)
		end)
	else
		warn("⚠️ Bouton +1 level invalide ou non trouvé")
	end

	if minusButton and minusButton:IsA("GuiButton") then
		minusButton.MouseButton1Click:Connect(function()
			navigateStage(-1)
		end)
	else
		warn("⚠️ Bouton -1 level invalide ou non trouvé")
	end

	setupRebirthListener()
end

-- ========================================
-- 📡 ÉCOUTE DES MISES À JOUR DU SERVEUR
-- ========================================
if checkpointEvent then
	checkpointEvent.OnClientEvent:Connect(function(checkpointName)
		local checkpointNum = tonumber(string.match(checkpointName, "%d+"))

		if checkpointNum then
			currentStage = checkpointNum

			if checkpointNum > maxStageReached then
				maxStageReached = checkpointNum
			end
		end
	end)
end

-- ========================================
-- 📡 RESET DU STAGE (Rebirth)
-- ========================================
local stageResetEvent = ReplicatedStorage:WaitForChild("StageReset", 10)
if stageResetEvent then
	stageResetEvent.OnClientEvent:Connect(function()
		currentStage    = 1
		maxStageReached = 1
		print("🔄 Stage reset reçu du serveur (rebirth)")
	end)
end

-- ========================================
-- 🚀 INITIALISATION
-- ========================================
task.spawn(function()
	task.wait(2)

	setupStageListener()

	setupButtons()
end)