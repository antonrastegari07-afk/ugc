-- Script LocalScript à placer DANS ton bouton existant
-- Ce script s'active quand on clique sur le bouton
-- ⚠️ NÉCESSITE AUSSI LE SCRIPT SERVEUR (voir après)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local button = script.Parent

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Référence au ScreenGui UGCShop
local ugcShopGui = button:FindFirstAncestorOfClass("ScreenGui")

-- 🆕 Variables pour les effets de caméra
local camera = workspace.CurrentCamera
local originalFOV = camera.FieldOfView
local blurEffect = nil

-- 🆕 Variables pour le responsive
local BASE_WIDTH = 700
local BASE_HEIGHT = 500
local maxScreenPercent = {
	Mobile = 0.7,
	Tablet = 0.75,
	Desktop = 0.6
}

-- 🆕 Détection appareil
local function getDevice()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local vp = camera.ViewportSize
		return (vp.X < 600 or vp.Y < 600) and "Mobile" or "Tablet"
	end
	return "Desktop"
end

-- Attendre le RemoteEvent
local equipAccessoryEvent = ReplicatedStorage:WaitForChild("EquipAccessoryEvent", 10)

-- 🆕 Créer l'effet de flou
local function createBlurEffect()
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect")
		blurEffect.Size = 0
		blurEffect.Parent = camera
	end
	return blurEffect
end

-- 🆕 Appliquer les effets de caméra (zoom + flou)
local function applyCameraEffects()
	local blur = createBlurEffect()

	local zoomTween = TweenService:Create(
		camera,
		TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{FieldOfView = originalFOV - 10}
	)

	local blurTween = TweenService:Create(
		blur,
		TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{Size = 24}
	)

	zoomTween:Play()
	blurTween:Play()
end

-- 🆕 Retirer les effets de caméra
local function removeCameraEffects()
	local zoomTween = TweenService:Create(
		camera,
		TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{FieldOfView = originalFOV}
	)

	if blurEffect then
		local blurTween = TweenService:Create(
			blurEffect,
			TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{Size = 0}
		)
		blurTween:Play()
	end

	zoomTween:Play()
end

-- ========================================
-- CONFIGURATION DES UGC (REMPLACE PAR TES VRAIS IDs)
-- ========================================
local ugcItems = {
	{
		id = 72930549621453, -- ID de l'accessoire Roblox
		image = "rbxassetid://100372879645206", -- ID de l'image
		name = "Korblox Sword"
	},
	{
		id = 115365595809194,
		image = "rbxassetid://103323366980691",
		name = "Cyber Raven Wings"
	},
	{
		id = 107162947616062,
		image = "rbxassetid://91078798578483",
		name = "Korblox Dominus"
	},
	{
		id = 2222222222,
		image = "rbxassetid://22222222222",
		name = "Accessoire 4"
	},
	{
		id = 3333333333,
		image = "rbxassetid://33333333333",
		name = "Accessoire 5"
	},
	{
		id = 4444444444,
		image = "rbxassetid://44444444444",
		name = "Accessoire 6"
	}
	-- Ajoute autant d'items que tu veux
}

-- ========================================
-- CRÉER LE SCREENGUI ET LA FRAME
-- ========================================
local function createUGCShop()
	-- Vérifier si le GUI existe déjà
	local existingGui = playerGui:FindFirstChild("UGCShopGui")
	if existingGui then
		local frame = existingGui:FindFirstChild("ShopFrame")
		if frame then
			frame.Visible = not frame.Visible

			-- Gérer les effets de caméra
			if frame.Visible then
				applyCameraEffects()
			else
				removeCameraEffects()
			end

			-- Gérer la visibilité de ShopFrame dans UGCShop
			if ugcShopGui then
				local ugcShopFrame = ugcShopGui:FindFirstChild("ShopFrame")
				if ugcShopFrame and ugcShopFrame:IsA("Frame") then
					ugcShopFrame.Visible = not frame.Visible
				end
			end

			return
		end
	end

	-- Cacher ShopFrame dans UGCShop quand on ouvre la frame Try
	if ugcShopGui then
		local ugcShopFrame = ugcShopGui:FindFirstChild("ShopFrame")
		if ugcShopFrame and ugcShopFrame:IsA("Frame") then
			ugcShopFrame.Visible = false
		end
	end

	-- 🆕 Appliquer les effets de caméra à l'ouverture
	applyCameraEffects()

	-- Créer le ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UGCShopGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 999
	screenGui.Parent = playerGui

	-- 🆕 Calculer la taille responsive
	local device = getDevice()
	local vp = camera.ViewportSize
	local screenWidth = math.max(vp.X, vp.Y)
	local screenHeight = math.min(vp.X, vp.Y)
	local maxPercent = maxScreenPercent[device]
	local aspectRatio = BASE_WIDTH / BASE_HEIGHT
	local maxWidth = screenWidth * maxPercent
	local maxHeight = screenHeight * maxPercent

	local finalWidth, finalHeight
	if maxWidth / aspectRatio <= maxHeight then
		finalWidth = maxWidth
		finalHeight = maxWidth / aspectRatio
	else
		finalHeight = maxHeight
		finalWidth = maxHeight * aspectRatio
	end

	-- Frame principale (style donation system)
	local shopFrame = Instance.new("Frame")
	shopFrame.Name = "ShopFrame"
	shopFrame.Size = UDim2.new(0, finalWidth, 0, finalHeight)
	shopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	shopFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	shopFrame.BorderSizePixel = 0
	shopFrame.Visible = true
	shopFrame.Parent = screenGui

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 15)
	frameCorner.Parent = shopFrame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(50, 50, 60)
	frameStroke.Thickness = 2
	frameStroke.Parent = shopFrame

	-- Titre
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.new(0, 0, 0, -5)
	title.BackgroundTransparency = 1
	title.Text = "TRY UGC"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 2
	title.Parent = shopFrame

	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MaxTextSize = 28
	titleConstraint.MinTextSize = 18
	titleConstraint.Parent = title

	-- Bouton de fermeture (style donation system)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = isMobile and UDim2.new(0, 45, 0, 45) or UDim2.new(0, 50, 0, 50)
	closeBtn.Position = UDim2.new(1, -50, 0, -10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "×"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextScaled = true
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.ZIndex = 3
	closeBtn.Parent = shopFrame

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0.2, 0)
	closeBtnCorner.Parent = closeBtn

	local closeBtnConstraint = Instance.new("UITextSizeConstraint")
	closeBtnConstraint.MaxTextSize = 32
	closeBtnConstraint.MinTextSize = 20
	closeBtnConstraint.Parent = closeBtn

	local closeBtnStroke = Instance.new("UIStroke")
	closeBtnStroke.Color = Color3.fromRGB(0, 0, 0)
	closeBtnStroke.Thickness = 3
	closeBtnStroke.Transparency = 0.3
	closeBtnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeBtnStroke.Parent = closeBtn

	if not isMobile then
		closeBtn.MouseEnter:Connect(function()
			TweenService:Create(closeBtn, TweenInfo.new(0.2), {
				BackgroundColor3 = Color3.fromRGB(255, 70, 70),
				Size = UDim2.new(0, 55, 0, 55)
			}):Play()
			TweenService:Create(closeBtnStroke, TweenInfo.new(0.2), {Transparency = 0}):Play()
		end)

		closeBtn.MouseLeave:Connect(function()
			TweenService:Create(closeBtn, TweenInfo.new(0.2), {
				BackgroundColor3 = Color3.fromRGB(200, 50, 50),
				Size = UDim2.new(0, 50, 0, 50)
			}):Play()
			TweenService:Create(closeBtnStroke, TweenInfo.new(0.2), {Transparency = 0.3}):Play()
		end)
	end

	-- Section des items (style donation system)
	local itemsSection = Instance.new("Frame")
	itemsSection.Name = "ItemsSection"
	itemsSection.Size = UDim2.new(0.96, 0, 0.86, 0)
	itemsSection.Position = UDim2.new(0.02, 0, 0.12, 0)
	itemsSection.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	itemsSection.BorderSizePixel = 0
	itemsSection.Parent = shopFrame

	local sectionCorner = Instance.new("UICorner")
	sectionCorner.CornerRadius = UDim.new(0, 12)
	sectionCorner.Parent = itemsSection

	-- ScrollingFrame
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemsScroll"
	scrollFrame.Size = UDim2.new(0.96, 0, 0.95, 0)
	scrollFrame.Position = UDim2.new(0.02, 0, 0.03, 0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 255)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = itemsSection

	-- GridLayout pour organiser les items
	local gridLayout = Instance.new("UIGridLayout")
	if isMobile then
		gridLayout.CellSize = UDim2.new(0.31, 0, 0, 140)
		gridLayout.CellPadding = UDim2.new(0.02, 0, 0, 10)
	else
		gridLayout.CellSize = UDim2.fromOffset(130, 160)
		gridLayout.CellPadding = UDim2.fromOffset(10, 10)
	end
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 5)
	padding.PaddingRight = UDim.new(0, 5)
	padding.Parent = scrollFrame

	-- Bouton "Stop Trying" (style amélioré)
	local stopButton = Instance.new("TextButton")
	stopButton.Name = "StopTryingButton"

	-- 🆕 Position responsive pour mobile
	if isMobile then
		local vp = camera.ViewportSize
		stopButton.Size = UDim2.new(0, 160, 0, 45)
		stopButton.Position = UDim2.new(1, -170, 0, 50)
	else
		stopButton.Size = UDim2.new(0, 200, 0, 50)
		stopButton.Position = UDim2.new(0.5, -100, 0, 80)
	end

	stopButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	stopButton.Text = ""
	stopButton.TextScaled = true
	stopButton.Font = Enum.Font.FredokaOne
	stopButton.Visible = false
	stopButton.ZIndex = 1000
	stopButton.Parent = screenGui

	local stopCorner = Instance.new("UICorner")
	stopCorner.CornerRadius = UDim.new(0, 12)
	stopCorner.Parent = stopButton

	local stopStroke = Instance.new("UIStroke")
	stopStroke.Color = Color3.fromRGB(0, 0, 0)
	stopStroke.Thickness = 3
	stopStroke.Transparency = 0.3
	stopStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stopStroke.Parent = stopButton

	local stopGradient = Instance.new("UIGradient")
	stopGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 60, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 40, 40))
	})
	stopGradient.Rotation = 90
	stopGradient.Parent = stopButton

	-- Texte séparé pour éviter le gradient
	local stopButtonText = Instance.new("TextLabel")
	stopButtonText.Size = UDim2.new(1, 0, 1, 0)
	stopButtonText.Position = UDim2.new(0, 0, 0, 0)
	stopButtonText.BackgroundTransparency = 1
	stopButtonText.Text = "Remove Accessory"
	stopButtonText.TextColor3 = Color3.fromRGB(255, 255, 255)
	stopButtonText.TextScaled = true
	stopButtonText.Font = Enum.Font.FredokaOne
	stopButtonText.ZIndex = 1001
	stopButtonText.Parent = stopButton

	local stopTextConstraint2 = Instance.new("UITextSizeConstraint")
	stopTextConstraint2.MaxTextSize = 20
	stopTextConstraint2.MinTextSize = 14
	stopTextConstraint2.Parent = stopButtonText

	-- Fonction pour équiper un accessoire (envoie au serveur)
	local function equipAccessory(accessoryId)
		if not equipAccessoryEvent then
			warn("❌ RemoteEvent 'EquipAccessoryEvent' non trouvé!")
			return
		end

		--print("🎯 Envoi de la demande au serveur pour l'accessoire ID: " .. accessoryId)
		equipAccessoryEvent:FireServer(accessoryId)
	end

	-- Fonction pour retirer tous les accessoires
	local function removeAllAccessories()
		if not equipAccessoryEvent then
			warn("❌ RemoteEvent 'EquipAccessoryEvent' non trouvé!")
			return
		end

		--print("🗑️ Demande de suppression des accessoires")
		equipAccessoryEvent:FireServer("REMOVE_ALL")
	end

	-- Créer les items UGC
	for i, item in ipairs(ugcItems) do
		local itemFrame = Instance.new("Frame")
		itemFrame.Name = "Item_" .. i
		itemFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
		itemFrame.BorderSizePixel = 0
		itemFrame.LayoutOrder = i
		itemFrame.Parent = scrollFrame

		local itemCorner = Instance.new("UICorner")
		itemCorner.CornerRadius = UDim.new(0, 10)
		itemCorner.Parent = itemFrame

		local itemStroke = Instance.new("UIStroke")
		itemStroke.Color = Color3.fromRGB(135, 206, 235)
		itemStroke.Thickness = 2
		itemStroke.Transparency = 0.5
		itemStroke.Parent = itemFrame

		-- Bouton avec image
		local itemButton = Instance.new("ImageButton")
		itemButton.Name = "ItemButton"
		itemButton.Size = UDim2.new(0.9, 0, 0, 100)
		itemButton.Position = UDim2.new(0.05, 0, 0.05, 0)
		itemButton.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
		itemButton.BorderSizePixel = 0
		itemButton.Image = item.image
		itemButton.ScaleType = Enum.ScaleType.Fit
		itemButton.AutoButtonColor = false
		itemButton.Parent = itemFrame

		local imgCorner = Instance.new("UICorner")
		imgCorner.CornerRadius = UDim.new(0, 8)
		imgCorner.Parent = itemButton

		-- Bouton invisible par-dessus tout le itemFrame pour capturer les clics
		local clickArea = Instance.new("TextButton")
		clickArea.Name = "ClickArea"
		clickArea.Size = UDim2.new(1, 0, 1, 0)
		clickArea.Position = UDim2.new(0, 0, 0, 0)
		clickArea.BackgroundTransparency = 1
		clickArea.Text = ""
		clickArea.ZIndex = 10
		clickArea.Parent = itemFrame

		-- Nom de l'item
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.9, 0, 0, 40)
		nameLabel.Position = UDim2.new(0.05, 0, 0.7, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = item.name
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextScaled = true
		nameLabel.Font = Enum.Font.FredokaOne
		nameLabel.TextWrapped = true
		nameLabel.Parent = itemFrame

		local nameConstraint = Instance.new("UITextSizeConstraint")
		nameConstraint.MaxTextSize = 14
		nameConstraint.MinTextSize = 10
		nameConstraint.Parent = nameLabel

		-- Effet hover (PC seulement)
		if not isMobile then
			clickArea.MouseEnter:Connect(function()
				TweenService:Create(itemFrame, TweenInfo.new(0.2), {
					BackgroundColor3 = Color3.fromRGB(40, 40, 50)
				}):Play()
				TweenService:Create(itemStroke, TweenInfo.new(0.2), {
					Transparency = 0,
					Thickness = 3
				}):Play()
			end)

			clickArea.MouseLeave:Connect(function()
				TweenService:Create(itemFrame, TweenInfo.new(0.2), {
					BackgroundColor3 = Color3.fromRGB(30, 30, 35)
				}):Play()
				TweenService:Create(itemStroke, TweenInfo.new(0.2), {
					Transparency = 0.5,
					Thickness = 2
				}):Play()
			end)
		end

		-- Événement de clic sur la zone cliquable
		clickArea.MouseButton1Click:Connect(function()
			--print("🎯 Tentative d'équiper l'accessoire ID: " .. item.id)
			equipAccessory(item.id)

			-- Fermer la frame de la boutique UGC
			shopFrame.Visible = false

			-- 🆕 Retirer les effets de caméra
			removeCameraEffects()

			-- Fermer aussi ShopFrame dans UGCShop si elle existe
			if ugcShopGui then
				local shopFrameToClose = ugcShopGui:FindFirstChild("ShopFrame")
				if shopFrameToClose and shopFrameToClose:IsA("Frame") and shopFrameToClose ~= shopFrame then
					shopFrameToClose.Visible = false
				end
			end

			-- Afficher le bouton "Remove Accessory"
			stopButton.Visible = true

			-- Le bouton reste visible jusqu'à ce qu'on clique dessus
		end)
	end

	-- 🆕 Fermer la frame et réouvrir ShopFrame dans UGCShop
	closeBtn.MouseButton1Click:Connect(function()
		shopFrame.Visible = false

		-- 🆕 Retirer les effets de caméra
		removeCameraEffects()

		-- Réouvrir ShopFrame dans UGCShop
		if ugcShopGui then
			local ugcShopFrame = ugcShopGui:FindFirstChild("ShopFrame")
			if ugcShopFrame and ugcShopFrame:IsA("Frame") then
				ugcShopFrame.Visible = true
			end
		end
	end)

	-- Cacher le bouton "Stop Trying"
	stopButton.MouseButton1Click:Connect(function()
		removeAllAccessories()
		stopButton.Visible = false

		-- 🆕 Réouvrir la frame Try
		shopFrame.Visible = true
		applyCameraEffects()
	end)
end

-- ========================================
-- ÉVÉNEMENT DU BOUTON
-- ========================================
button.MouseButton1Click:Connect(function()
	createUGCShop()
end)