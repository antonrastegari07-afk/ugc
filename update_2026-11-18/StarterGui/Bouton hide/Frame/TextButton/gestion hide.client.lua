local button = script.Parent
local frame = button.Parent
local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 📐 La place du bouton est donnée par ReplicatedStorage ▸ HudLayout (mêmes écarts
--    sur tous les formats d'écran). Avant, ce script forçait une position en % de la
--    largeur, et le bouton se décollait des autres.
local HL = require(ReplicatedStorage:WaitForChild("HudLayout"))

local isHidden = false
local textLabel = button:FindFirstChild("TextLabel") or button

local guisToHide = {
	{screenGui = "Shop", buttonName = "Frame"},
	{screenGui = "PointsShop", buttonName = "Frame"},
	{screenGui = "Rebirth", buttonName = "Frame"},
	{screenGui = "Quest", buttonName = "Frame"},
	{screenGui = "Daily tool", buttonName = "open button"},
	{screenGui = "# Stage", buttonName = "Frame"},    -- checkpoints (hors PVP)
	{screenGui = "# Stage", buttonName = "Frame2"},   -- kills (en PVP)
	{screenGui = "Skip Obby", buttonName = "Frameskiplevel"},
	{screenGui = "Skip Level", buttonName = "Frameskiplevel"},
	--{screenGui = "invites", buttonName = "Frame"},
}

local originalFrameSize = frame.Size
local originalFramePosition = frame.Position

local TweenService = game:GetService("TweenService")
local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local colorTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Linear)

local gradient = button:FindFirstChildOfClass("UIGradient")
if not gradient then
	gradient = Instance.new("UIGradient")
	gradient.Parent = button
end

local stroke = button:FindFirstChildOfClass("UIStroke")
if not stroke then
	stroke = Instance.new("UIStroke")
	stroke.Parent = button
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local gradientOff = ColorSequence.new{
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 100)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 0, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80))
}

local gradientOn = ColorSequence.new{
	ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 255, 100)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 200, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 255, 120))
}

local strokeColorOff = Color3.fromRGB(180, 0, 0)
local strokeColorOn = Color3.fromRGB(0, 180, 0)

local function animateGradient(targetGradient, targetStrokeColor)
	gradient.Color = targetGradient
	TweenService:Create(gradient, colorTweenInfo, {
		Rotation = gradient.Rotation + 360
	}):Play()
	TweenService:Create(stroke, colorTweenInfo, {
		Color = targetStrokeColor
	}):Play()
end

local function getScaledSizeAndPosition(originalSize, originalPosition, scale)
	local newSize = UDim2.new(
		originalSize.X.Scale * scale,
		originalSize.X.Offset * scale,
		originalSize.Y.Scale * scale,
		originalSize.Y.Offset * scale
	)
	local anchorPoint = frame.AnchorPoint
	if anchorPoint.X == 0.5 and anchorPoint.Y == 0.5 then
		return newSize, originalPosition
	else
		local newPosition = UDim2.new(
			originalPosition.X.Scale + (originalSize.X.Scale * (1 - scale) / 2),
			originalPosition.X.Offset + (originalSize.X.Offset * (1 - scale) / 2),
			originalPosition.Y.Scale + (originalSize.Y.Scale * (1 - scale) / 2),
			originalPosition.Y.Offset + (originalSize.Y.Offset * (1 - scale) / 2)
		)
		return newSize, newPosition
	end
end

-- ✅ Fonction centrale : applique un état précis sans toggle
-- 🔧 Frames exclusives à un mode. Clé = "NomDuScreenGui|NomDeLaFrame".
local PVP_ONLY  = { ["# Stage|Frame2"] = true }   -- visible UNIQUEMENT en PVP (kills)
local OBBY_ONLY = { ["# Stage|Frame"]  = true }   -- visible UNIQUEMENT hors PVP (checkpoints)
-- 🔧 JAMAIS visible tant que le joueur est en PVP, même si le hide est sur OFF
local FORCE_HIDDEN_IN_PVP = { ["Skip Obby"] = true, ["Skip Level"] = true }

local function isInArena()
	return player:GetAttribute("InArena") == true
end

local function applyHiddenState(hidden, autoPvp)
	isHidden = hidden
	local inArena = isInArena()
	for _, guiData in ipairs(guisToHide) do
		local screenGui = playerGui:FindFirstChild(guiData.screenGui)
		if screenGui then
			local buttonToHide = screenGui:FindFirstChild(guiData.buttonName)
			if buttonToHide then
				local key = guiData.screenGui .. "|" .. guiData.buttonName
				local visible = not isHidden

				-- en ENTRANT en arène, la frame kills reste à l'écran
				if autoPvp and PVP_ONLY[key] then visible = true end

				-- chaque frame n'existe que dans son mode
				if inArena and OBBY_ONLY[key] then visible = false end
				if (not inArena) and PVP_ONLY[key] then visible = false end

				-- skip level / skip obby : jamais en PVP
				if inArena and FORCE_HIDDEN_IN_PVP[guiData.screenGui] then
					visible = false
				end

				buttonToHide.Visible = visible
			else
				warn("Bouton '" .. guiData.buttonName .. "' non trouvé dans " .. guiData.screenGui)
			end
		else
			warn("ScreenGui '" .. guiData.screenGui .. "' non trouvé")
		end
	end
	if isHidden then
		animateGradient(gradientOn, strokeColorOn)
		if textLabel then textLabel.Text = "ON" end
	else
		animateGradient(gradientOff, strokeColorOff)
		if textLabel then textLabel.Text = "OFF" end
	end
end

-- ✅ Toggle manuel via clic
local function toggleGuis()
	applyHiddenState(not isHidden)
end

-- Initialisation
gradient.Color = gradientOff
gradient.Rotation = 90
stroke.Color = strokeColorOff
if textLabel then textLabel.Text = "OFF" end

-- ✅ Écouter l'événement dédié depuis le serveur
local hideUIEvent = ReplicatedStorage:WaitForChild("HideUIEvent", 10)
if hideUIEvent then
	hideUIEvent.OnClientEvent:Connect(function(shouldHide)
		-- shouldHide = true  → entré en arène, forcer ON (tout cacher)
		-- shouldHide = false → sorti d'arène, forcer OFF (tout réafficher)
		applyHiddenState(shouldHide, shouldHide)
	end)
	-- 🔁 Resynchronise si InArena change (l'ordre d'arrivée avec HideUIEvent n'est pas garanti)
	player:GetAttributeChangedSignal("InArena"):Connect(function()
		applyHiddenState(isHidden, isInArena())
	end)

	-- ▶️ État initial au spawn : sinon Frame et Frame2 gardent leur Visible de
	--    Studio et les deux peuvent s'afficher en même temps.
	task.spawn(function()
		task.wait(1)
		applyHiddenState(isHidden, isInArena())
	end)
end

-- Hover (même effet qu'avant, à partir de la place donnée par HudLayout)
HL.Hover(button, frame)

button.MouseButton1Click:Connect(function()
	toggleGuis()
end)