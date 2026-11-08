-- LocalScript COMBINÉ pour gérer les boutons ENTER et EXIT
-- À placer dans StarterPlayerScripts

-- ========================================
-- SERVICES
-- ========================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Attendre les RemoteEvents
local enterArenaEvent = ReplicatedStorage:WaitForChild("EnterArena")
local exitArenaEvent = ReplicatedStorage:WaitForChild("ExitArena")
local uiToggleEvent = ReplicatedStorage:WaitForChild("ArenaUIToggle")

local WeaponSharedState = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponSharedState"))

-- Détecter mobile
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Cooldown local
local lastClick = 0
local COOLDOWN = 1.0

-- Configuration du positionnement
local EDGE_SPACING_SCALE_PC = 0.007
local EDGE_SPACING_SCALE_MOBILE = 0.007
local EDGE_SPACING_SCALE = isMobile and EDGE_SPACING_SCALE_MOBILE or EDGE_SPACING_SCALE_PC

-- ========================================
-- TROUVER LE BOUTON ENTER EXISTANT
-- ========================================

local function findEnterButton()
	local screenGui1v1 = playerGui:WaitForChild("1v1button", 10)
	if not screenGui1v1 then
		warn("⚠️ ScreenGui '1v1button' introuvable!")
		return nil
	end

	local frame = nil
	for _, child in ipairs(screenGui1v1:GetChildren()) do
		if child:IsA("Frame") then
			frame = child
			break
		end
	end

	if not frame then
		warn("⚠️ Frame introuvable dans 1v1button!")
		return nil
	end


	local enterButton = frame:FindFirstChildWhichIsA("TextButton")

	if not enterButton then
		warn("⚠️ TextButton introuvable dans la Frame!")
		return nil
	end

	return {frame = frame, button = enterButton}
end

-- ========================================
-- CRÉER LE BOUTON EXIT RECTANGULAIRE AMÉLIORÉ
-- ========================================

-- Créer le ScreenGui pour Exit
local exitScreenGui = Instance.new("ScreenGui")
exitScreenGui.Name = "ExitArenaGui"
exitScreenGui.ResetOnSpawn = false
exitScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
exitScreenGui.Parent = playerGui

-- Créer la Frame parent pour Exit (RECTANGULAIRE)
local exitFrame = Instance.new("Frame")
exitFrame.Name = "ExitFrame"
exitFrame.BackgroundTransparency = 1

-- Tailles adaptées - PLUS PETIT SUR MOBILE, PLUS GRAND SUR PC
if isMobile then
	exitFrame.Size = UDim2.new(0, 70, 0, 40) -- RÉDUIT sur mobile
else
	exitFrame.Size = UDim2.new(0, 150, 0, 70) -- AGRANDI sur PC
end

-- Position PARFAITEMENT CENTRÉE à droite de l'écran
exitFrame.Position = UDim2.new(1 - EDGE_SPACING_SCALE, 0, isMobile and 0.38 or 0.5, 0) -- 0.5 = milieu exact
exitFrame.AnchorPoint = Vector2.new(1, 0.5) -- Ancre au milieu verticalement (0.5)
exitFrame.Visible = false
exitFrame.Parent = exitScreenGui

-- [Combat X1] bouton Exit dans le style des UI du haut de l'arène (ArenaHUD) : panneau rouge brillant, bord épais
-- foncé dessous, contour foncé, textes Fredoka One à gros contour ; il s'ENFONCE quand on clique (comme le bouton +)
local FREDOKA = Font.fromEnum(Enum.Font.FredokaOne)
local EX_HI, EX_LO = Color3.fromRGB(255, 108, 100), Color3.fromRGB(212, 36, 44)
local EX_EDGE, EX_RIM = Color3.fromRGB(128, 16, 26), Color3.fromRGB(255, 200, 194)
local EX_OUT = Color3.fromRGB(58, 8, 14)
local EX_DEPTH = isMobile and 3 or 5
local EX_RADIUS = isMobile and 8 or 12

-- bord épais foncé (le « dessous » du bouton) + contour foncé. Il ne couvre que la partie BASSE : quand le bouton
-- s'enfonce, il le recouvre entièrement (le bord disparaît) et rien de sombre n'apparaît au-dessus du bouton
local exitEdge = Instance.new("Frame")
exitEdge.Name = "Edge"
exitEdge.Size = UDim2.new(1, 0, 1, -EX_DEPTH)
exitEdge.Position = UDim2.fromOffset(0, EX_DEPTH)
exitEdge.BackgroundColor3 = EX_EDGE
exitEdge.BorderSizePixel = 0
exitEdge.ZIndex = 1
exitEdge.Parent = exitFrame
Instance.new("UICorner", exitEdge).CornerRadius = UDim.new(0, EX_RADIUS)
local edgeStroke = Instance.new("UIStroke", exitEdge)
edgeStroke.Color = EX_OUT
edgeStroke.Thickness = isMobile and 1.5 or 2
edgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- le dessus du bouton
local exitButton = Instance.new("TextButton")
exitButton.Name = "ExitButton"
exitButton.BackgroundColor3 = Color3.new(1, 1, 1)
exitButton.BorderSizePixel = 0
exitButton.AutoButtonColor = false
exitButton.Text = ""
exitButton.ClipsDescendants = false
exitButton.Size = UDim2.new(1, 0, 1, -EX_DEPTH)
exitButton.Position = UDim2.new(0, 0, 0, 0)
exitButton.ZIndex = 2
exitButton.Parent = exitFrame
Instance.new("UICorner", exitButton).CornerRadius = UDim.new(0, EX_RADIUS)
local faceStroke = Instance.new("UIStroke", exitButton)   -- contour foncé du dessus (gardé quand il est enfoncé)
faceStroke.Color = EX_OUT
faceStroke.Thickness = isMobile and 1.5 or 2
faceStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
local btnGradient = Instance.new("UIGradient", exitButton)
btnGradient.Color = ColorSequence.new(EX_HI, EX_LO)
btnGradient.Rotation = 90

-- reflet brillant sur la moitié haute
local inset = isMobile and 2 or 3
local innerGlow = Instance.new("Frame", exitButton)
innerGlow.Name = "Gloss"
innerGlow.BackgroundColor3 = Color3.new(1, 1, 1)
innerGlow.BorderSizePixel = 0
innerGlow.Position = UDim2.fromOffset(inset, inset)
innerGlow.Size = UDim2.new(1, -2 * inset, 0.45, 0)
Instance.new("UICorner", innerGlow).CornerRadius = UDim.new(0, math.max(2, EX_RADIUS - inset))
local glossGrad = Instance.new("UIGradient", innerGlow)
glossGrad.Rotation = 90
glossGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.62), NumberSequenceKeypoint.new(1, 0.95) })

-- liseré clair à l'intérieur (c'est lui qui « pulse » doucement)
local rim = Instance.new("Frame", exitButton)
rim.Name = "Rim"
rim.AnchorPoint = Vector2.new(0.5, 0.5)
rim.Position = UDim2.fromScale(0.5, 0.5)
rim.Size = UDim2.new(1, -inset, 1, -inset)
rim.BackgroundTransparency = 1
Instance.new("UICorner", rim).CornerRadius = UDim.new(0, math.max(2, EX_RADIUS - 1))
local btnStroke = Instance.new("UIStroke", rim)
btnStroke.Color = EX_RIM
btnStroke.Thickness = isMobile and 1 or 1.6
btnStroke.Transparency = 0.2
btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local function exText(parent, txt, size)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = txt
	l.FontFace = FREDOKA
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextSize = size
	l.ZIndex = 3
	local st = Instance.new("UIStroke", l)
	st.Color = EX_OUT
	st.Thickness = isMobile and 1.2 or 2.2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.LineJoinMode = Enum.LineJoinMode.Round
	l.Parent = parent
	return l
end

-- icône ✖ à gauche
local iconLabel = exText(exitButton, "✖", isMobile and 11 or 20)
iconLabel.Name = "Icon"
iconLabel.Size = UDim2.new(0, isMobile and 14 or 24, 0, isMobile and 14 or 24)
iconLabel.Position = UDim2.new(0, isMobile and 4 or 11, 0.5, 0)
iconLabel.AnchorPoint = Vector2.new(0, 0.5)

-- ⌨️🎮 À LA PLACE DU ✖ : la touche pour quitter (PC = L · manette = flèche de droite).
--    Utile en mode lock, où le curseur ne bouge pas. Mobile : le ✖ reste.
local GuiService = game:GetService("GuiService")
local IS_CONSOLE = false
pcall(function() IS_CONSOLE = GuiService:IsTenFootInterface() end)
local padIcon = Instance.new("ImageLabel")
padIcon.Name = "PadIcon"
padIcon.BackgroundTransparency = 1
padIcon.Size = iconLabel.Size
padIcon.Position = iconLabel.Position
padIcon.AnchorPoint = iconLabel.AnchorPoint
padIcon.ScaleType = Enum.ScaleType.Fit
padIcon.ZIndex = 3
padIcon.Visible = false
padIcon.Parent = exitButton
pcall(function() padIcon.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.DPadRight) end)
-- ⌨️ PC : une vraie TOUCHE DE CLAVIER « L » (touche claire, bord foncé en dessous)
local KEY = 26
local keycap = Instance.new("Frame")
keycap.Name = "KeyCap"
keycap.AnchorPoint = Vector2.new(0, 0.5)
keycap.Position = UDim2.new(0, 9, 0.5, 0)
keycap.Size = UDim2.fromOffset(KEY, KEY)
keycap.BackgroundColor3 = Color3.fromRGB(70, 20, 20)          -- bord foncé (épaisseur de la touche)
keycap.BorderSizePixel = 0
keycap.ZIndex = 3
keycap.Visible = false
keycap.Parent = exitButton
Instance.new("UICorner", keycap).CornerRadius = UDim.new(0, 6)
local keyTop = Instance.new("Frame")
keyTop.Name = "Top"
keyTop.Size = UDim2.new(1, 0, 1, -4)                           -- le dessus, un peu plus haut que le bord
keyTop.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
keyTop.BorderSizePixel = 0
keyTop.ZIndex = 4
keyTop.Parent = keycap
Instance.new("UICorner", keyTop).CornerRadius = UDim.new(0, 6)
local keyStroke = Instance.new("UIStroke", keyTop)
keyStroke.Color = Color3.fromRGB(70, 20, 20)
keyStroke.Thickness = 1.5
keyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
local keyLetter = Instance.new("TextLabel")
keyLetter.Name = "Letter"
keyLetter.BackgroundTransparency = 1
keyLetter.Size = UDim2.fromScale(1, 1)
keyLetter.FontFace = FREDOKA
keyLetter.Text = "L"
keyLetter.TextSize = 18
keyLetter.TextColor3 = Color3.fromRGB(40, 40, 40)
keyLetter.ZIndex = 5
keyLetter.Parent = keyTop
local function usingGamepad()
	if IS_CONSOLE then return true end
	local t = UserInputService:GetLastInputType()
	return t ~= nil and string.sub(t.Name, 1, 7) == "Gamepad"
end
local function refreshExitKey()
	if isMobile then return end
	if usingGamepad() then
		keycap.Visible = false
		if padIcon.Image ~= "" then
			padIcon.Visible, iconLabel.Visible = true, false      -- 🎮 le signe de la manette (comme pour les armes)
		else
			padIcon.Visible, iconLabel.Visible = false, true
			iconLabel.Text = "▶"
		end
	else
		padIcon.Visible, iconLabel.Visible = false, false
		keycap.Visible = true                                     -- ⌨️ la touche L
	end
end
refreshExitKey()
UserInputService.LastInputTypeChanged:Connect(refreshExitKey)

-- « Exit » / « Arena » sur 2 lignes
local textContainer = Instance.new("Frame", exitButton)
textContainer.Name = "TextContainer"
textContainer.BackgroundTransparency = 1
textContainer.Size = UDim2.new(1, isMobile and -20 or -38, 1, 0)
textContainer.Position = UDim2.new(0, isMobile and 20 or 38, 0, 0)
textContainer.ZIndex = 3
local exitText = exText(textContainer, "Exit", isMobile and 13 or 24)
exitText.Name = "ExitText"
exitText.Size = UDim2.new(1, 0, 0.5, 0)
exitText.Position = UDim2.new(0, 0, 0, isMobile and 1 or 2)
exitText.TextYAlignment = Enum.TextYAlignment.Bottom
local arenaText = exText(textContainer, "Arena", isMobile and 11 or 20)
arenaText.Name = "ArenaText"
arenaText.Size = UDim2.new(1, 0, 0.5, 0)
arenaText.Position = UDim2.new(0, 0, 0.5, 0)
arenaText.TextYAlignment = Enum.TextYAlignment.Top

-- ========================================
-- ENFONCEMENT (PC + mobile) : le dessus descend sur le bord foncé, comme le bouton +
-- ========================================
local function press(down)
	exitButton.Position = down and UDim2.fromOffset(0, EX_DEPTH) or UDim2.new(0, 0, 0, 0)
end
exitButton.MouseButton1Down:Connect(function() press(true) end)
exitButton.MouseButton1Up:Connect(function() press(false) end)
exitButton.MouseLeave:Connect(function()
	press(false)
	glossGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.62), NumberSequenceKeypoint.new(1, 0.95) })
end)
exitButton.MouseEnter:Connect(function()
	if isMobile then return end
	-- survol : le reflet s'éclaire un peu
	glossGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.9) })
end)
exitButton.Activated:Connect(function() task.delay(0.08, press, false) end)

-- ========================================
-- PARTICULES POUR EXIT
-- ========================================
local particlesRunning = false
local activeParticles = 0
local MAX_PARTICLES = isMobile and 1 or 2

local particleContainer = Instance.new("Frame")
particleContainer.Name = "ParticleContainer"
particleContainer.Size = UDim2.fromScale(1, 1)
particleContainer.BackgroundTransparency = 1
particleContainer.ZIndex = 5
particleContainer.Parent = exitButton

local function createParticle()
	if activeParticles >= MAX_PARTICLES then return end
	if not particlesRunning then return end
	if not exitButton or not exitButton.Parent then return end

	activeParticles = activeParticles + 1

	local particle = Instance.new("Frame")
	particle.Size = UDim2.new(0, math.random(3, 5), 0, math.random(3, 5))
	particle.Position = UDim2.fromScale(math.random(20, 80) / 100, math.random(70, 95) / 100)
	particle.BackgroundColor3 = Color3.fromRGB(255, 205, 200)
	particle.BorderSizePixel = 0
	particle.Parent = particleContainer

	local corner = Instance.new("UICorner", particle)
	corner.CornerRadius = UDim.new(1, 0)

	local endPos = particle.Position + UDim2.fromScale(math.random(-10, 10) / 100, -0.4)
	local tween = TweenService:Create(particle, TweenInfo.new(1.5, Enum.EasingStyle.Linear), {
		Position = endPos,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 1, 0, 1)
	})
	tween:Play()

	task.delay(1.5, function()
		activeParticles = activeParticles - 1
		if particle then particle:Destroy() end
	end)
end

local function startParticles()
	particlesRunning = true
	task.spawn(function()
		while particlesRunning do
			createParticle()
			task.wait(isMobile and 1.2 or 0.8)
		end
	end)
end

local function stopParticles()
	particlesRunning = false
end

-- ========================================
-- EFFET DE PULSATION SUBTILE
-- ========================================
local pulseRunning = false

local function startPulse()
	pulseRunning = true
	task.spawn(function()
		while pulseRunning do
			if exitFrame.Visible then
				TweenService:Create(btnStroke, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Transparency = 0
				}):Play()
				task.wait(1.5)
				if pulseRunning then
					TweenService:Create(btnStroke, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
						Transparency = 0.2
					}):Play()
					task.wait(1.5)
				end
			else
				task.wait(0.5)
			end
		end
	end)
end

startPulse()

-- ========================================
-- GESTION DE LA VISIBILITÉ
-- ========================================

local enterElements = nil

local function setEnterFrameVisible(visible)
	if not enterElements then 
		warn("⚠️ enterElements n'est pas initialisé!")
		return 
	end

	enterElements.frame.Visible = visible
end

local function setExitFrameVisible(visible)
	if visible then
		exitFrame.Visible = true
		exitFrame.Size = UDim2.new(0, 0, 0, 0)

		local targetSize = isMobile and UDim2.new(0, 70, 0, 40) or UDim2.new(0, 150, 0, 70)
		TweenService:Create(exitFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = targetSize
		}):Play()

		startParticles()
	else
		stopParticles()

		local fadeOut = TweenService:Create(exitFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0)
		})

		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			exitFrame.Visible = false
		end)
	end
end

uiToggleEvent.OnClientEvent:Connect(function(buttonType, visible)
	if buttonType == "enter" then
		setEnterFrameVisible(visible)
	elseif buttonType == "exit" then
		setExitFrameVisible(visible)
	end
end)

-- ========================================
-- GESTION DES CLICS
-- ========================================

local function setupEnterButton()
	enterElements = findEnterButton()

	if not enterElements then
		warn("⚠️ Impossible de configurer le bouton Enter!")
		return
	end

	enterElements.button.MouseButton1Click:Connect(function()
		if _G.TutorialActive then return end -- 🔒 jamais d'entrée en arène pendant le tuto
		local now = tick()
		if now - lastClick < COOLDOWN then return end
		lastClick = now
		WeaponSharedState.SetNoShiftLockZone(true) -- 🆕 prédiction client, pas besoin d'attendre le serveur
		enterArenaEvent:FireServer()
	end)
end

exitButton.MouseButton1Click:Connect(function()

	local now = tick()
	if now - lastClick < COOLDOWN then
		return
	end
	lastClick = now
	exitArenaEvent:FireServer()
end)

-- ⌨️🎮 touche pour quitter l'arène : L (PC) · flèche de droite (manette)
--    seulement quand le bouton Exit est affiché, jamais en tapant dans le chat
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or isMobile then return end
	if input.KeyCode ~= Enum.KeyCode.L and input.KeyCode ~= Enum.KeyCode.DPadRight then return end
	if not exitFrame.Visible or UserInputService:GetFocusedTextBox() then return end
	if workspace:GetAttribute("AnimEditorFreeze") then return end   -- l'Anim Studio admin utilise L
	local now = tick()
	if now - lastClick < COOLDOWN then return end
	lastClick = now
	press(true)
	task.delay(0.12, press, false)
	exitArenaEvent:FireServer()
end)

-- ========================================
-- INITIALISATION
-- ========================================

if not game:IsLoaded() then
	game.Loaded:Wait()
end

task.spawn(function()
	setupEnterButton()
end)

exitButton.Destroying:Connect(function()
	particlesRunning = false
	pulseRunning = false
end)