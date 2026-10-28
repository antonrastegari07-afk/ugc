-- Loading script - LocalScript à mettre dans ReplicatedFirst
-- (et SUPPRIMER l'ancien "Screen LOADER" de StarterPlayer ▸ StarterPlayerScripts)
-- ✅ ANTI-FLASH : la fin du chargement est annoncée quand l'écran est encore 100 % noir.
--    Le How to Play s'ouvre (et UIFocusSystem cache les autres UI) AVANT que le noir s'enlève :
--    on ne voit plus toutes les UI apparaître puis disparaître.
-- ✅ VERSION REPLICATEDFIRST :
--    • le script démarre AVANT que le jeu soit chargé → l'écran Roblox disparaît tout de suite
--    • la CameraPart est attendue sans timeout court (le décor arrive plus tard ici)
--    • la caméra est forcée APRÈS le script caméra de Roblox (BindToRenderStep) → elle ne
--      repart plus sur le perso quand il apparaît
--    • workspace.CurrentCamera est relu à chaque image (Roblox peut le remplacer pendant le chargement)
--    • le bouton SKIP et la sortie attendent que le jeu soit vraiment chargé
local ReplicatedFirst = game:GetService("ReplicatedFirst")
-- 🚫 Enlève l'écran de chargement Roblox par défaut le plus tôt possible
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")
local player = Players.LocalPlayer
while not player do
	task.wait()
	player = Players.LocalPlayer
end
local playerGui = player:WaitForChild("PlayerGui")
-- ⚫ ÉCRAN NOIR INSTANTANÉ : créé AVANT toute attente → 1ère chose visible
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.Parent = playerGui
local instantCover = Instance.new("Frame")
instantCover.Name = "InstantCover"
instantCover.Size = UDim2.new(1, 0, 1, 0)
instantCover.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
instantCover.BorderSizePixel = 0
instantCover.ZIndex = 1000
instantCover.Parent = screenGui
-- ========================================
-- CONFIGURATION
-- ========================================
-- 📱 MODE LÉGER (téléphones / tablettes) : pas de vue 3D de l'île pendant le chargement,
--    pas de flou, et le serveur ne charge PAS la zone de la CameraPart en plus de celle du
--    spawn. Moins de mémoire et de GPU pendant le chargement → plus de crash sur iPad.
--    Mets false pour garder la vue de l'île partout.
local LITE_ON_TOUCH = true
local LITE_MODE = LITE_ON_TOUCH and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local GAME_TITLE = "Free UGC Grind 2"
local LOGO_IMAGE = "rbxassetid://123545186780825"
local CAMERA_PART_NAME = "CameraPart"
-- 🖼️ ASSETS À PRÉCHARGER
local PRELOAD_ASSETS = {
	LOGO_IMAGE,
	-- "rbxassetid://XXXXXXXX",
}
-- ⬆️ TAILLE DU LOGO (fraction de la hauteur d'écran, identique partout)
local LOGO_SCALE = 0.22 -- augmente pour un logo plus gros (ex: 0.30), diminue pour plus petit
-- 📏 UNDERLINE DU TITRE
local UNDERLINE_WIDTH = 1.0 -- 1 = largeur exacte du texte, 0.8 = 80% du texte, 1.1 = léger dépassement
local UNDERLINE_GAP = 4     -- pixels entre le bas du texte et la ligne
-- ⏳ Attente max (écran noir) que le How to Play se soit ouvert avant d'enlever le noir
local INTRO_WAIT_MAX = 4
local LOADING_STEPS = {
	"Connecting to server...",
	"Loading data...",
	"Loading checkpoints...",
	"Loading progression...",
	"Loading bonuses...",
	"Loading leaderboard...",
	"Preparing environment...",
	"Finalizing..."
}
local LOADING_TIPS = {
	"💡 Tip: Complete daily quests for bonus rewards!",
	"🎮 Tip: Each friend in game gets you a +10% point boost, invite them!",
	"⭐ Pro tip: Check the leaderboard to compete!",
	"🚀 New UGCs are added weekly!",
	"💎 Tip: Claim your daily reward every day!",
	"🎯 Hint: Every checkpoint gets you points!",
	"🌟 Tip: Join the group for a 10% Point Boost!",
	"🔥 Tip: Claim the +10000 pts rebirth reward at the end every time you rebirth!"
}
-- ========================================
-- 🎥 CAMÉRA
-- ========================================
-- ⚠️ Dans ReplicatedFirst, Roblox peut REMPLACER workspace.CurrentCamera pendant le chargement :
--    on ne garde jamais une vieille référence, on relit toujours workspace.CurrentCamera.
local camera = workspace.CurrentCamera
local cameraPart
local cameraBound = false
local CAMERA_BIND_NAME = "LoaderCameraLock"
local characterAddedConnection
local guiWatcherConnection
local progressConnection
local cameraChangedConnection
local exitStarted = false -- (utilisée aussi par la sortie du loader plus bas)
local function forceCameraOnPart()
	camera = workspace.CurrentCamera
	if camera and cameraPart and screenGui and screenGui.Parent then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cameraPart.CFrame
		camera.Focus = cameraPart.CFrame
	end
end
local function unbindCamera()
	if cameraBound then
		cameraBound = false
		pcall(function() RunService:UnbindFromRenderStep(CAMERA_BIND_NAME) end)
	end
end
cameraChangedConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
	if cameraBound then forceCameraOnPart() end
end)
-- ========================================
-- UI CREATION
-- ========================================
-- (Le ScreenGui + le fond noir instantané sont déjà créés tout en haut du script)
-- ⚫→ Le fond noir s'efface une fois la caméra posée sur le décor (révèle la scène)
local function revealScene()
	if instantCover and instantCover.Parent then
		TweenService:Create(instantCover, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 1
		}):Play()
		local cover = instantCover
		task.delay(0.45, function()
			if cover then cover:Destroy() end
		end)
	end
end
-- 🎥 Caméra : on attend la CameraPart en arrière-plan (sans bloquer l'UI).
--    Le décor arrive APRÈS le démarrage du script quand il est dans ReplicatedFirst.
task.spawn(function()
	-- 📱 mode léger : pas de vue 3D, le fond reste sombre jusqu'à la fin du chargement
	if LITE_MODE then return end
	-- Demande au serveur de charger aussi le décor autour de la CameraPart (PC / console seulement)
	task.spawn(function()
		local ev = ReplicatedStorage:WaitForChild("LoaderWantFocus", 30)
		if ev then pcall(function() ev:FireServer() end) end
	end)
	local camModel = workspace:WaitForChild("CameraPartModel", 60)
	cameraPart = camModel and camModel:WaitForChild(CAMERA_PART_NAME, 30)
	if not cameraPart then
		warn("⚠️ Partie '" .. CAMERA_PART_NAME .. "' introuvable dans le Workspace!")
		revealScene()
		return
	end
	if exitStarted or not screenGui.Parent then return end
	camera = workspace.CurrentCamera
	if camera then camera.FieldOfView = 70 end
	-- Priorité Camera+1 = on passe APRÈS le script caméra de Roblox à chaque image :
	-- même quand le personnage apparaît, la caméra reste sur la CameraPart.
	RunService:BindToRenderStep(CAMERA_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, forceCameraOnPart)
	cameraBound = true
	forceCameraOnPart()
	-- On laisse au décor autour de la CameraPart le temps d'arriver avant d'enlever le noir
	local t0 = os.clock()
	while not game:IsLoaded() and os.clock() - t0 < 10 do
		task.wait(0.1)
	end
	task.wait(0.3)
	revealScene()
end)
-- Sécurité : si rien n'est trouvé du tout, on n'affiche pas un écran noir indéfiniment
if not LITE_MODE then task.delay(20, revealScene) end
characterAddedConnection = player.CharacterAdded:Connect(function(character)
	if screenGui and screenGui.Parent and cameraBound then
		task.wait()
		forceCameraOnPart()
	end
end)
-- ========================================
-- 🚫 CACHER LES AUTRES SCREENGUIS
-- ========================================
local hiddenGuis = {}
local loadingActive = true
for _, gui in pairs(playerGui:GetChildren()) do
	if gui:IsA("ScreenGui") and gui ~= screenGui and gui.Enabled then
		table.insert(hiddenGuis, gui)
		gui.Enabled = false
	end
end
guiWatcherConnection = playerGui.ChildAdded:Connect(function(gui)
	if loadingActive and gui:IsA("ScreenGui") and gui ~= screenGui then
		task.defer(function()
			if loadingActive and gui.Enabled then
				table.insert(hiddenGuis, gui)
				gui.Enabled = false
			end
		end)
	end
end)
local clickBlocker = Instance.new("Frame")
clickBlocker.Size = UDim2.new(1, 0, 1, 0)
clickBlocker.BackgroundTransparency = 1
clickBlocker.ZIndex = 998
clickBlocker.Active = true
clickBlocker.Parent = screenGui
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(1, 0, 1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
mainFrame.BackgroundTransparency = 1
mainFrame.BorderSizePixel = 0
mainFrame.ZIndex = 999
mainFrame.Parent = screenGui
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.3
overlay.BorderSizePixel = 0
overlay.ZIndex = 1001
overlay.Parent = mainFrame
-- Flou du décor derrière le loader (inutile en mode léger : il n'y a pas de décor affiché)
if not LITE_MODE then
	local blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "LoadingBlur"
	blurEffect.Size = 0
	blurEffect.Parent = game.Lighting
	TweenService:Create(blurEffect, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = 15
	}):Play()
end
local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, 0, 1, 0)
contentFrame.Position = UDim2.new(0, 0, 0, 0)
contentFrame.BackgroundTransparency = 1
contentFrame.ZIndex = 1003
contentFrame.Parent = mainFrame
-- ========================================
-- 📦 STACK CENTRÉ (logo + titre + barre + status)
-- Tout est empilé et centré automatiquement -> proportions identiques sur tous les appareils
-- ========================================
local stack = Instance.new("Frame")
stack.Name = "LoaderStack"
stack.Size = UDim2.new(1, 0, 1, 0)
stack.Position = UDim2.new(0.5, 0, 0.5, 0)
stack.AnchorPoint = Vector2.new(0.5, 0.5)
stack.BackgroundTransparency = 1
stack.ZIndex = 1004
stack.Parent = contentFrame
local stackLayout = Instance.new("UIListLayout")
stackLayout.FillDirection = Enum.FillDirection.Vertical
stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
stackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
stackLayout.Padding = UDim.new(0.03, 0) -- écart entre éléments (en scale = proportionnel)
stackLayout.Parent = stack
-- ========================================
-- 🎮 LOGO CARRÉ (statique, pas de rotation ni breathing)
-- ========================================
local logoContainer = Instance.new("Frame")
logoContainer.LayoutOrder = 1
logoContainer.Size = UDim2.new(LOGO_SCALE, 0, LOGO_SCALE, 0)
logoContainer.BackgroundTransparency = 1
logoContainer.ZIndex = 1004
logoContainer.Parent = stack
-- 🔲 Garde le logo parfaitement carré, dimensionné par la hauteur d'écran
local logoAspect = Instance.new("UIAspectRatioConstraint")
logoAspect.AspectRatio = 1
logoAspect.DominantAxis = Enum.DominantAxis.Height
logoAspect.Parent = logoContainer
local logoImage = Instance.new("ImageLabel")
logoImage.Size = UDim2.new(0, 0, 0, 0) -- démarre à 0 pour le bounce d'entrée
logoImage.Position = UDim2.new(0.5, 0, 0.5, 0)
logoImage.AnchorPoint = Vector2.new(0.5, 0.5)
logoImage.BackgroundTransparency = 1
logoImage.Image = LOGO_IMAGE
logoImage.ScaleType = Enum.ScaleType.Fit
logoImage.ZIndex = 1005
logoImage.Parent = logoContainer
local logoCorner = Instance.new("UICorner")
logoCorner.CornerRadius = UDim.new(0.18, 0) -- coins d'icône d'app; mets 0 si ton image a déjà ses coins
logoCorner.Parent = logoImage
local logoGlow = Instance.new("UIStroke")
logoGlow.Color = Color3.fromRGB(100, 150, 255)
logoGlow.Thickness = 6
logoGlow.Transparency = 0.5
logoGlow.Parent = logoImage
-- Bounce d'entrée sur l'IMAGE (le container reste fixe -> pas de reflow du stack)
task.spawn(function()
	task.wait(0.3)
	TweenService:Create(logoImage, TweenInfo.new(0.8, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 1, 0)
	}):Play()
end)
-- Glow pulsant (un seul tween infini)
task.spawn(function()
	task.wait(1)
	if logoGlow.Parent then
		TweenService:Create(logoGlow, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Transparency = 0.8,
			Thickness = 8
		}):Play()
	end
end)
-- ========================================
-- 📝 TITLE (avec underline en enfant, juste sous le titre)
-- ========================================
local titleLabel = Instance.new("TextLabel")
titleLabel.LayoutOrder = 2
titleLabel.Size = UDim2.new(0.9, 0, 0.13, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = GAME_TITLE
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.TextStrokeTransparency = 0.8
titleLabel.TextTransparency = 1
titleLabel.TextScaled = true
titleLabel.ZIndex = 1004
titleLabel.Parent = stack
local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MaxTextSize = 64
titleConstraint.MinTextSize = isMobile and 20 or 32
titleConstraint.Parent = titleLabel
local titleUnderline = Instance.new("Frame")
titleUnderline.Size = UDim2.new(0, 0, 0, isMobile and 2 or 3)
titleUnderline.Position = UDim2.new(0.5, 0, 0.5, 0)
titleUnderline.AnchorPoint = Vector2.new(0.5, 0)
titleUnderline.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
titleUnderline.BorderSizePixel = 0
titleUnderline.BackgroundTransparency = 1
titleUnderline.ZIndex = 1004
titleUnderline.Parent = titleLabel
-- 🔄 Colle l'underline sous le texte, à sa largeur exacte (TextBounds = taille rendue)
local underlineVisible = false
local function syncUnderline(animated)
	local bounds = titleLabel.TextBounds
	if bounds.X <= 0 then return end
	local targetSize = UDim2.new(0, bounds.X * UNDERLINE_WIDTH, 0, isMobile and 2 or 3)
	local targetPos = UDim2.new(0.5, 0, 0.5, bounds.Y / 2 + UNDERLINE_GAP)
	titleUnderline.Position = targetPos
	if animated then
		TweenService:Create(titleUnderline, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = targetSize,
			BackgroundTransparency = 0
		}):Play()
	elseif underlineVisible then
		titleUnderline.Size = targetSize
	end
end
-- Si le texte est re-mesuré (resize d'écran, rotation mobile), on re-sync
titleLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
	syncUnderline(false)
end)
task.spawn(function()
	task.wait(0.5)
	TweenService:Create(titleLabel, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0
	}):Play()
	task.wait(0.3)
	underlineVisible = true
	syncUnderline(true)
end)
-- ========================================
-- 📊 PROGRESS BAR (juste sous le titre)
-- ========================================
local barContainer = Instance.new("Frame")
barContainer.LayoutOrder = 3
barContainer.Size = UDim2.new(0.85, 0, 0, isMobile and 24 or 50)
barContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
barContainer.BackgroundTransparency = 1
barContainer.BorderSizePixel = 0
barContainer.ZIndex = 1004
barContainer.Parent = stack
local barSizeConstraint = Instance.new("UISizeConstraint")
barSizeConstraint.MaxSize = Vector2.new(isMobile and 300 or 600, 50)
barSizeConstraint.MinSize = Vector2.new(150, 24)
barSizeConstraint.Parent = barContainer
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 8)
barCorner.Parent = barContainer
local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(50, 50, 60)
barStroke.Thickness = 1
barStroke.Transparency = 1
barStroke.Parent = barContainer
task.spawn(function()
	task.wait(0.9)
	local barTween = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(barContainer, barTween, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(barStroke, barTween, { Transparency = 0 }):Play()
end)
local progressBar = Instance.new("Frame")
progressBar.Size = UDim2.new(0, 0, 1, 0)
progressBar.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
progressBar.BorderSizePixel = 0
progressBar.ZIndex = 1005
progressBar.Parent = barContainer
local progressCorner = Instance.new("UICorner")
progressCorner.CornerRadius = UDim.new(0, 8)
progressCorner.Parent = progressBar
local percentLabel = Instance.new("TextLabel")
percentLabel.Size = UDim2.new(1, 0, 1, 0)
percentLabel.BackgroundTransparency = 1
percentLabel.Text = "0%"
percentLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
percentLabel.Font = Enum.Font.FredokaOne
percentLabel.TextTransparency = 1
percentLabel.TextScaled = true
percentLabel.ZIndex = 1007
percentLabel.Parent = barContainer
local percentConstraint = Instance.new("UITextSizeConstraint")
percentConstraint.MaxTextSize = isMobile and 14 or 28
percentConstraint.MinTextSize = isMobile and 11 or 18
percentConstraint.Parent = percentLabel
task.spawn(function()
	task.wait(0.9)
	TweenService:Create(percentLabel, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
end)
-- ========================================
-- 📝 STATUS LABEL
-- ========================================
local statusLabel = Instance.new("TextLabel")
statusLabel.LayoutOrder = 4
statusLabel.Size = UDim2.new(0.9, 0, 0.045, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Initializing..."
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextTransparency = 1
statusLabel.TextScaled = true
statusLabel.ZIndex = 1004
statusLabel.Parent = stack
local statusConstraint = Instance.new("UITextSizeConstraint")
statusConstraint.MaxTextSize = isMobile and 14 or 18
statusConstraint.MinTextSize = isMobile and 9 or 12
statusConstraint.Parent = statusLabel
task.spawn(function()
	task.wait(1.1)
	TweenService:Create(statusLabel, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
end)
local dotsActive = true
task.spawn(function()
	task.wait(1.1)
	local dots = ""
	while statusLabel.Parent and dotsActive do
		for i = 1, 3 do
			if not statusLabel.Parent or not dotsActive then break end
			dots = string.rep(".", i)
			local baseText = statusLabel.Text:gsub("%.+$", "")
			statusLabel.Text = baseText .. dots
			task.wait(0.4)
		end
		dots = ""
		if statusLabel.Parent and dotsActive then
			statusLabel.Text = statusLabel.Text:gsub("%.+$", "")
			task.wait(0.4)
		end
	end
end)
-- ========================================
-- 💡 TIPS LABEL (footer, reste en bas de l'écran)
-- ========================================
local tipsLabel = Instance.new("TextLabel")
tipsLabel.Size = UDim2.new(0.85, 0, 0.05, 0)
tipsLabel.Position = UDim2.new(0.5, 0, 0.9, 0)
tipsLabel.AnchorPoint = Vector2.new(0.5, 0.5)
tipsLabel.BackgroundTransparency = 1
tipsLabel.Text = LOADING_TIPS[math.random(1, #LOADING_TIPS)]
tipsLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
tipsLabel.Font = Enum.Font.GothamMedium
tipsLabel.TextTransparency = 1
tipsLabel.TextScaled = true
tipsLabel.ZIndex = 1004
tipsLabel.Parent = contentFrame
local tipsConstraint = Instance.new("UITextSizeConstraint")
tipsConstraint.MaxTextSize = isMobile and 12 or 18
tipsConstraint.MinTextSize = isMobile and 9 or 14
tipsConstraint.Parent = tipsLabel
task.spawn(function()
	task.wait(0.5)
	TweenService:Create(tipsLabel, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	while tipsLabel.Parent do
		task.wait(4)
		if not tipsLabel.Parent then break end
		TweenService:Create(tipsLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		task.wait(0.3)
		if not tipsLabel.Parent then break end
		tipsLabel.Text = LOADING_TIPS[math.random(1, #LOADING_TIPS)]
		TweenService:Create(tipsLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	end
end)
-- ========================================
-- ✨ PARTICULES FLOTTANTES (fond)
-- ========================================
local function createFloatingParticles()
	for i = 1, 12 do
		local particle = Instance.new("Frame")
		local size = math.random(4, 7)
		particle.Size = UDim2.new(0, size, 0, size)
		particle.Position = UDim2.new(math.random(0, 100) / 100, 0, math.random(67, 100) / 100, 0)
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		particle.BackgroundTransparency = math.random(30, 60) / 100
		particle.BorderSizePixel = 0
		particle.ZIndex = 1002
		particle.Parent = mainFrame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = particle
		task.spawn(function()
			local baseSpeed = math.random(10, 16)
			while particle.Parent do
				local startX = particle.Position.X.Scale
				local startY = particle.Position.Y.Scale
				local numSteps = math.random(1)
				for step = 1, numSteps do
					if not particle.Parent then break end
					local randomX = startX + (math.random(-20, 20) / 100)
					randomX = math.clamp(randomX, 0.05, 0.95)
					local stepDistance = 0.25 / numSteps
					local targetY = startY - stepDistance
					local stepDuration = baseSpeed / numSteps
					TweenService:Create(particle, TweenInfo.new(stepDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
						Position = UDim2.new(randomX, 0, targetY, 0)
					}):Play()
					task.wait(stepDuration)
					startX = randomX
					startY = targetY
				end
				if particle.Position.Y.Scale < 0.67 then
					local fadeOutTween = TweenService:Create(particle, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
						BackgroundTransparency = 1
					})
					fadeOutTween:Play()
					fadeOutTween.Completed:Wait()
					particle.Position = UDim2.new(math.random(0, 100) / 100, 0, math.random(95, 100) / 100, 0)
					TweenService:Create(particle, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
						BackgroundTransparency = math.random(30, 60) / 100
					}):Play()
					task.wait(0.5)
				end
			end
		end)
		task.spawn(function()
			local pulseSpeed = math.random(20, 30) / 10
			while particle.Parent do
				TweenService:Create(particle, TweenInfo.new(pulseSpeed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					BackgroundTransparency = math.random(20, 45) / 100
				}):Play()
				task.wait(pulseSpeed)
				TweenService:Create(particle, TweenInfo.new(pulseSpeed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					BackgroundTransparency = math.random(55, 75) / 100
				}):Play()
				task.wait(pulseSpeed)
			end
		end)
	end
end
task.spawn(createFloatingParticles)
-- ========================================
-- 🖼️ PRÉLOAD
-- ========================================
local assetsPreloaded = false
task.spawn(function()
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(PRELOAD_ASSETS)
	end)
	if not ok then
		warn("⚠️ PreloadAsync a échoué: " .. tostring(err))
	end
	assetsPreloaded = true
end)
-- ========================================
-- 🎬 STATUS TRANSITION (fade only, pas de position)
-- ========================================
local function updateStatusWithTransition(newText)
	if not statusLabel.Parent then return end
	dotsActive = false
	local baseText = newText:gsub("%.+$", "")
	local fadeOut = TweenService:Create(statusLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1
	})
	fadeOut:Play()
	fadeOut.Completed:Wait()
	statusLabel.Text = baseText
	dotsActive = true
	TweenService:Create(statusLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0
	}):Play()
end
-- ========================================
-- LOGIC
-- ========================================
local currentProgress = 0
local targetProgress = 0
local function updateProgress(newProgress, statusText)
	targetProgress = math.clamp(newProgress, 0, 100)
	if statusText then
		updateStatusWithTransition(statusText)
	end
end
progressConnection = RunService.RenderStepped:Connect(function(dt)
	if currentProgress < targetProgress then
		currentProgress = currentProgress + (targetProgress - currentProgress) * dt * 3
		currentProgress = math.min(currentProgress, targetProgress)
		progressBar.Size = UDim2.new(currentProgress / 100, 0, 1, 0)
		percentLabel.Text = math.floor(currentProgress) .. "%"
	end
end)
local loadingEvents = {
	dataLoaded = false,
	checkpointLoaded = false,
	friendsLoaded = false,
	questsLoaded = false,
	donationsLoaded = false,
	characterReady = false
}
-- ========================================
-- ⏭️ SKIP BUTTON (vert plein, texte blanc + outline)
-- ========================================
local skipRequested = false
local skipVisible   = false
local startExit -- assignée plus bas : déclenche la sortie du loader
local SKIP_GREEN       = Color3.fromRGB(60, 195, 100)
local SKIP_GREEN_HOVER = Color3.fromRGB(76, 215, 118)
local SKIP_GREEN_PRESS = Color3.fromRGB(48, 170, 86)
local SKIP_GREEN_DARK  = Color3.fromRGB(35, 130, 65)
local skipHolder = Instance.new("Frame")
skipHolder.Name = "SkipHolder"
skipHolder.AnchorPoint = Vector2.new(0.5, 0)
skipHolder.Position = UDim2.new(0.5, 0, 0.72, 0)
skipHolder.Size = UDim2.new(0, isMobile and 148 or 235, 0, isMobile and 36 or 54)
skipHolder.BackgroundTransparency = 1
skipHolder.Visible = false
skipHolder.ZIndex = 1010
skipHolder.Parent = contentFrame


local skipBtn = Instance.new("TextButton")
skipBtn.AnchorPoint = Vector2.new(0.5, 0.5)
skipBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
skipBtn.Size = UDim2.new(1, 0, 1, 0)
skipBtn.BackgroundColor3 = SKIP_GREEN
skipBtn.BackgroundTransparency = 1
skipBtn.AutoButtonColor = false
skipBtn.BorderSizePixel = 0
skipBtn.Text = ""
skipBtn.Active = false
skipBtn.ZIndex = 1010
skipBtn.Parent = skipHolder
local skipCorner = Instance.new("UICorner")
skipCorner.CornerRadius = UDim.new(0, 10)
skipCorner.Parent = skipBtn
local skipStroke = Instance.new("UIStroke")
skipStroke.Color = SKIP_GREEN_DARK
skipStroke.Thickness = 2
skipStroke.Transparency = 1
skipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
skipStroke.Parent = skipBtn
local skipScale = Instance.new("UIScale")
skipScale.Scale = 0.85
skipScale.Parent = skipBtn
local skipLabel = Instance.new("TextLabel")
skipLabel.Size = UDim2.new(1, 0, 1, 0)
skipLabel.BackgroundTransparency = 1
skipLabel.Text = "SKIP"
skipLabel.Font = Enum.Font.FredokaOne
skipLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
skipLabel.TextSize = isMobile and 16 or 25
skipLabel.TextTransparency = 1
skipLabel.ZIndex = 1011
skipLabel.Parent = skipBtn
local skipLabelStroke = Instance.new("UIStroke")
skipLabelStroke.Color = SKIP_GREEN_DARK
skipLabelStroke.Thickness = 2
skipLabelStroke.Transparency = 1
skipLabelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
skipLabelStroke.Parent = skipLabel

-- 🫧 Respiration douce et uniforme : le halo pulse (aucun scale → aucun saut de pixel)
local SKIP_STROKE_PULSE = Color3.fromRGB(120, 245, 165)
local skipBreathTween = TweenService:Create(
	skipStroke,
	TweenInfo.new(1.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Thickness = 3.5, Color = SKIP_STROKE_PULSE }
)

-- ✨ GLOW VERT ARRONDI — chaque couche démarre à transparence 1 (invisible),
-- et n'est révélée QUE pendant le survol (curseur ou doigt).
local SKIP_GLOW_ENABLED = true   -- 🔘 mets false pour désactiver complètement le glow
local GLOW_COLOR     = Color3.fromRGB(90, 255, 140)
local GLOW_SIZE      = isMobile and 14 or 20   -- portée du halo (px)
local GLOW_LAYERS    = 12                      -- nb de couches (plus = plus doux)
local GLOW_INTENSITY = 0.15                    -- force globale
local GLOW_FALLOFF   = 1.7                     -- >1 = halo concentré près du bouton
local GLOW_RADIUS    = 10                      -- = le CornerRadius du bouton

local skipGlowLayers = {}   -- { {frame = Frame, target = number}, ... }

for i = GLOW_LAYERS, 1, -1 do
	if not SKIP_GLOW_ENABLED then break end
	local t = i / GLOW_LAYERS
	local spread = GLOW_SIZE * (t ^ (1 / GLOW_FALLOFF))
	local layer = Instance.new("Frame")
	layer.Name = "SkipGlowLayer_" .. i
	layer.BackgroundColor3 = GLOW_COLOR
	layer.BackgroundTransparency = 1        -- ⬅️ invisible au repos
	layer.BorderSizePixel = 0
	layer.Active = false
	layer.ZIndex = 1008                     -- derrière le bouton (1010)
	layer.Size = UDim2.new(1, spread * 2, 1, spread * 2)
	layer.Position = UDim2.new(0, -spread, 0, -spread)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, GLOW_RADIUS + math.floor(spread))
	c.Parent = layer
	layer.Parent = skipHolder

	local a = (GLOW_INTENSITY * (1 - t * 0.6)) / GLOW_LAYERS * 2.5
	table.insert(skipGlowLayers, {
		frame  = layer,
		target = math.clamp(1 - a, 0, 1),
	})
end

local function setSkipGlow(on)
	if not SKIP_GLOW_ENABLED then return end
	local info = TweenInfo.new(on and 0.22 or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, L in ipairs(skipGlowLayers) do
		if L.frame and L.frame.Parent then
			TweenService:Create(L.frame, info, {
				BackgroundTransparency = on and L.target or 1
			}):Play()
		end
	end
end
local function positionSkipUnderStatus()
	if not statusLabel or not statusLabel.Parent then return end
	local gap = isMobile and 10 or 14
	local y = (statusLabel.AbsolutePosition.Y + statusLabel.AbsoluteSize.Y)
	- contentFrame.AbsolutePosition.Y + gap
	skipHolder.Position = UDim2.new(0.5, 0, 0, y)

	-- 📱 MOBILE : on pousse les tips juste SOUS le bouton (sinon il les recouvre)
	if isMobile and tipsLabel and tipsLabel.Parent then
		local screenH   = contentFrame.AbsoluteSize.Y
		if screenH <= 0 then return end
		local btnBottom = y + skipHolder.Size.Y.Offset
		local tipsH     = screenH * 0.05
		local wantedY   = btnBottom + 14 + tipsH / 2
		local defaultY  = screenH * 0.9
		-- jamais plus haut que sa position d'origine, jamais hors écran
		local finalY = math.clamp(math.max(wantedY, defaultY), 0, screenH - tipsH / 2 - 4)
		tipsLabel.Position = UDim2.new(0.5, 0, 0, finalY)
	end
end
statusLabel:GetPropertyChangedSignal("AbsolutePosition"):Connect(positionSkipUnderStatus)
statusLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionSkipUnderStatus)
local function skipScaleTo(scale, duration)
	TweenService:Create(skipScale,
		TweenInfo.new(duration or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = scale }):Play()
end
skipBtn.MouseEnter:Connect(function()
	if not skipVisible then return end
	skipScaleTo(1.04, 0.15)
	TweenService:Create(skipBtn, TweenInfo.new(0.15), { BackgroundColor3 = SKIP_GREEN_HOVER }):Play()
	setSkipGlow(true)
end)
skipBtn.MouseLeave:Connect(function()
	if not skipVisible then return end
	skipScaleTo(1, 0.15)
	TweenService:Create(skipBtn, TweenInfo.new(0.15), { BackgroundColor3 = SKIP_GREEN }):Play()
	setSkipGlow(false)
end)
skipBtn.MouseButton1Down:Connect(function()
	if not skipVisible then return end
	skipScaleTo(0.96, 0.08)
	TweenService:Create(skipBtn, TweenInfo.new(0.08), { BackgroundColor3 = SKIP_GREEN_PRESS }):Play()
end)

-- 📱 Doigt posé sur le bouton = même effet que le hover souris
skipBtn.InputBegan:Connect(function(input)
	if not skipVisible then return end
	if input.UserInputType == Enum.UserInputType.Touch then
		setSkipGlow(true)
		skipScaleTo(1.04, 0.12)
		TweenService:Create(skipBtn, TweenInfo.new(0.12), { BackgroundColor3 = SKIP_GREEN_HOVER }):Play()
	end
end)

skipBtn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		setSkipGlow(false)
		skipScaleTo(1, 0.15)
		TweenService:Create(skipBtn, TweenInfo.new(0.15), { BackgroundColor3 = SKIP_GREEN }):Play()
	end
end)
local function showSkipButton()
	if skipVisible or skipRequested or not screenGui.Parent then return end
	skipVisible = true
	skipHolder.Visible = true
	skipBtn.Active = true
	positionSkipUnderStatus()
	TweenService:Create(skipScale,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	local fade = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(skipBtn, fade, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(skipStroke, fade, { Transparency = 0 }):Play()
	TweenService:Create(skipLabel, fade, { TextTransparency = 0 }):Play()
	TweenService:Create(skipLabelStroke, fade, { Transparency = 0 }):Play()
	skipBreathTween:Play()
end
local function hideSkipButton()
	if not skipVisible then return end
	skipVisible = false
	skipBtn.Active = false
	local fade = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(skipBtn, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(skipStroke, fade, { Transparency = 1 }):Play()
	TweenService:Create(skipLabel, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(skipLabelStroke, fade, { Transparency = 1 }):Play()
	TweenService:Create(skipScale, fade, { Scale = 0.9 }):Play()
	skipBreathTween:Cancel()
	skipStroke.Thickness = 2
	skipStroke.Color = SKIP_GREEN_DARK
	setSkipGlow(false)
	task.delay(0.22, function()
		if skipHolder and skipHolder.Parent then
			skipHolder.Visible = false
		end
	end)
end
-- ✅ Le clic déclenche IMMÉDIATEMENT la sortie (version rapide)
skipBtn.MouseButton1Click:Connect(function()
	if skipRequested or not skipVisible then return end
	skipRequested = true
	skipLabel.Text = "SKIPPING"
	hideSkipButton()
	if startExit then
		task.spawn(function() startExit(true) end)
	end
end)
-- ✅ Apparition rapide : dès 1.5s si le personnage existe, sinon 5s max
task.spawn(function()
	local startClock = os.clock()
	while screenGui.Parent do
		task.wait(0.15)
		if skipRequested then return end
		local elapsed = os.clock() - startClock
		-- ReplicatedFirst : pas de SKIP tant que le jeu n'est pas entièrement chargé
		if game:IsLoaded() and ((elapsed >= 1.5 and player.Character) or elapsed >= 5) then
			showSkipButton()
			return
		end
	end
end)
-- ReplicatedFirst : les RemoteEvents de ReplicatedStorage arrivent APRÈS le démarrage du script.
-- On les attend chacun en arrière-plan (sans bloquer le reste) et on se branche dès qu'ils arrivent.
local function onEvent(eventName, callback)
	task.spawn(function()
		local event = ReplicatedStorage:WaitForChild(eventName, 60)
		if not event then
			warn("⚠️ Event " .. eventName .. " not found")
			return
		end
		event.OnClientEvent:Connect(callback)
	end)
end
onEvent("DataLoaded", function()
	loadingEvents.dataLoaded = true
	updateProgress(35, LOADING_STEPS[2])
end)
onEvent("CheckpointLoaded", function()
	loadingEvents.checkpointLoaded = true
	updateProgress(55, LOADING_STEPS[3])
end)
onEvent("FriendsLoaded", function()
	loadingEvents.friendsLoaded = true
	updateProgress(75, LOADING_STEPS[5])
end)
onEvent("QuestsLoaded", function()
	loadingEvents.questsLoaded = true
	updateProgress(85, LOADING_STEPS[6])
end)
onEvent("DonationsLoaded", function()
	loadingEvents.donationsLoaded = true
end)
player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		loadingEvents.characterReady = true
		updateProgress(95, LOADING_STEPS[7])
	end
end)
if player.Character then
	local humanoid = player.Character:FindFirstChild("Humanoid")
	if humanoid then
		loadingEvents.characterReady = true
		updateProgress(95, LOADING_STEPS[7])
	end
end
-- ========================================
-- 🎬 SORTIE DU LOADER (normale ou skip rapide)
-- ========================================
startExit = function(fast)
	if exitStarted then return end
	exitStarted = true
	skipRequested = true
	hideSkipButton()
	-- Sécurité ReplicatedFirst : on ne rend jamais la main avant que le jeu soit chargé
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	if fast then
		targetProgress   = 100
		currentProgress  = 100
		progressBar.Size = UDim2.new(1, 0, 1, 0)
		percentLabel.Text = "100%"
	end
	dotsActive = false
	statusLabel.Text = "Ready"
	task.wait(fast and 0.05 or 0.3)
	local vignette = Instance.new("Frame")
	vignette.Size = UDim2.new(1, 0, 1, 0)
	vignette.Position = UDim2.new(0.5, 0, 0.5, 0)
	vignette.AnchorPoint = Vector2.new(0.5, 0.5)
	vignette.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.ZIndex = 2000
	vignette.Parent = screenGui
	local closeDur    = fast and 0.35 or 1.2
	local fadeInTween = TweenInfo.new(closeDur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local fadeTween   = TweenInfo.new(closeDur * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(logoImage, fadeTween, { Size = UDim2.new(0, 0, 0, 0) }):Play()
	TweenService:Create(titleLabel, fadeTween, { TextTransparency = 1 }):Play()
	TweenService:Create(titleUnderline, fadeTween, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(barContainer, fadeTween, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(barStroke, fadeTween, { Transparency = 1 }):Play()
	TweenService:Create(progressBar, fadeTween, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(percentLabel, fadeTween, { TextTransparency = 1 }):Play()
	TweenService:Create(statusLabel, fadeTween, { TextTransparency = 1 }):Play()
	TweenService:Create(tipsLabel, fadeTween, { TextTransparency = 1 }):Play()
	local vignetteClose = TweenService:Create(vignette, fadeInTween, { BackgroundTransparency = 0 })
	vignetteClose:Play()
	vignetteClose.Completed:Wait()
	-- ⬛ ÉCRAN 100% NOIR → on coupe TOUT le contenu du loader d'un coup.
	-- (tips + bouton skip inclus : plus rien ne peut réapparaître pendant le fade-out)
	contentFrame.Visible = false
	-- 📱 mode léger : le fond sombre est resté jusqu'ici ; on l'enlève sous le noir
	if instantCover and instantCover.Parent then instantCover:Destroy() end
	if overlay then overlay.BackgroundTransparency = 1 end
	mainFrame.BackgroundTransparency = 1
	unbindCamera()
	if cameraChangedConnection then
		cameraChangedConnection:Disconnect()
		cameraChangedConnection = nil
	end
	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end
	loadingActive = false
	if guiWatcherConnection then
		guiWatcherConnection:Disconnect()
		guiWatcherConnection = nil
	end
	local function restoreCamera()
		camera = workspace.CurrentCamera
		if not camera then return end
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		if not character then
			local waited = 0
			while not player.Character and waited < 5 do
				task.wait(0.1)
				waited = waited + 0.1
			end
			character = player.Character
		end
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 2)
		local hrp = character:FindFirstChild("HumanoidRootPart")
			or character:WaitForChild("HumanoidRootPart", 2)
		if humanoid then
			camera.CameraSubject = humanoid
		end
		if hrp then
			local lookVector = hrp.CFrame.LookVector
			local position = hrp.Position
			local cameraPosition = position - (lookVector * 8) + Vector3.new(0, 2, 0)
			camera.CFrame = CFrame.new(cameraPosition, position + lookVector * 10)
		end
	end
	restoreCamera()
	task.wait(fast and 0.1 or 0.3)
	restoreCamera()
	task.spawn(function()
		local checkTime = 0
		while checkTime < 2 do
			task.wait(0.1)
			checkTime = checkTime + 0.1
			camera = workspace.CurrentCamera
			if camera and camera.CameraType == Enum.CameraType.Scriptable then
				restoreCamera()
			end
		end
	end)
	-- Les UI sont rallumées SOUS le noir (personne ne les voit)
	for _, gui in pairs(hiddenGuis) do
		if gui then
			gui.Enabled = true
		end
	end
	-- 📣 FIN DU CHARGEMENT ANNONCÉE MAINTENANT (écran encore noir) :
	--    le How to Play s'ouvre ici et UIFocusSystem cache les autres UI AVANT la révélation.
	local loadingCompleteFlag = ReplicatedStorage:FindFirstChild("LoadingCompleteFlag")
	if not loadingCompleteFlag then
		loadingCompleteFlag = Instance.new("BoolValue")
		loadingCompleteFlag.Name = "LoadingCompleteFlag"
		loadingCompleteFlag.Value = false
		loadingCompleteFlag.Parent = ReplicatedStorage
	end
	loadingCompleteFlag.Value = true
	local existingBlur = game.Lighting:FindFirstChild("LoadingBlur")
	if existingBlur then
		local blurOut = TweenService:Create(existingBlur,
			TweenInfo.new(fast and 0.2 or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = 0 })
		blurOut:Play()
		blurOut.Completed:Wait()
		existingBlur:Destroy()
	end
	-- ⏳ Le How to Play s'est-il ouvert ? (il met PlayerGui.IntroHowToPlay = "waiting" puis "shown"/"later")
	--    Pas de script How to Play → aucune attente. Sécurité : INTRO_WAIT_MAX secondes au plus.
	local introStart = os.clock()
	while playerGui:GetAttribute("IntroHowToPlay") == "waiting" and os.clock() - introStart < INTRO_WAIT_MAX do
		task.wait(0.05)
	end
	-- 2 images : UIFocusSystem applique son masquage avant le rendu (aucune UI ne clignote)
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	task.wait(fast and 0.05 or 0.5)
	local vignetteOpen = TweenService:Create(vignette,
		TweenInfo.new(fast and 0.45 or 1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ BackgroundTransparency = 1 })
	-- 🎬 le noir commence à s'enlever : le How to Play peut jouer son animation d'entrée
	playerGui:SetAttribute("LoaderRevealed", true)
	vignetteOpen:Play()
	vignetteOpen.Completed:Wait()
	if progressConnection then
		progressConnection:Disconnect()
		progressConnection = nil
	end
	screenGui:Destroy()
	-- 📡 fin du loader (après l'écran noir) → le serveur relâche le décor de la CameraPart
	task.spawn(function()
		local ev = ReplicatedStorage:WaitForChild("LoaderFocusDone", 10)
		if ev then pcall(function() ev:FireServer() end) end
	end)
end
-- ========================================
-- SÉQUENCE DE CHARGEMENT NORMALE
-- ========================================
task.spawn(function()
	task.wait(1.2)
	if skipRequested then return end
	updateProgress(10, LOADING_STEPS[1])
	task.wait(0.3)
	-- 🌍 ReplicatedFirst : vrai chargement du jeu (avant, c'était l'écran Roblox qui l'affichait).
	--    La barre avance doucement jusqu'à 30 % tant que le jeu n'est pas chargé.
	while not game:IsLoaded() do
		if skipRequested then return end
		updateProgress(math.min(targetProgress + 0.4, 30))
		task.wait(0.1)
	end
	if skipRequested then return end
	local dataWait = 0
	while not loadingEvents.dataLoaded and dataWait < 5 and not skipRequested do
		task.wait(0.1)
		dataWait = dataWait + 0.1
	end
	if skipRequested then return end
	if not loadingEvents.dataLoaded then
		updateProgress(35, LOADING_STEPS[2])
		task.wait(0.3)
	end
	if skipRequested then return end
	local checkpointWait = 0
	while not loadingEvents.checkpointLoaded and checkpointWait < 3 and not skipRequested do
		task.wait(0.1)
		checkpointWait = checkpointWait + 0.1
	end
	if skipRequested then return end
	if not loadingEvents.checkpointLoaded then
		updateProgress(55, LOADING_STEPS[3])
		task.wait(0.3)
	end
	if skipRequested then return end
	updateProgress(65, LOADING_STEPS[4])
	task.wait(0.3)
	if skipRequested then return end
	local extraWait = 0
	while (not loadingEvents.friendsLoaded or not loadingEvents.questsLoaded)
		and extraWait < 3 and not skipRequested do
		task.wait(0.1)
		extraWait = extraWait + 0.1
	end
	if skipRequested then return end
	if not loadingEvents.friendsLoaded then
		updateProgress(75, LOADING_STEPS[5])
		task.wait(0.2)
	end
	if skipRequested then return end
	if not loadingEvents.questsLoaded then
		updateProgress(85, LOADING_STEPS[6])
		task.wait(0.2)
	end
	if skipRequested then return end
	local charWait = 0
	while not loadingEvents.characterReady and charWait < 3 and not skipRequested do
		task.wait(0.1)
		charWait = charWait + 0.1
	end
	if skipRequested then return end
	if not loadingEvents.characterReady then
		updateProgress(95, LOADING_STEPS[7])
		task.wait(0.2)
	end
	if skipRequested then return end
	local preloadWait = 0
	while not assetsPreloaded and preloadWait < 3 and not skipRequested do
		task.wait(0.1)
		preloadWait = preloadWait + 0.1
	end
	if skipRequested then return end
	updateProgress(100, "Complete")
	task.wait(0.5)
	startExit(false)
end)