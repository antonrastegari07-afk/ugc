-- LocalScript dans le Frame principal qui contient tous les ButtonFrame
-- VERSION CORRIGÉE v4 (7 JOURS) :
--   • Passage de 5 à 7 jours
--   • Rewards : 1=SpeedCoil, 2=5k pts, 3=Gravity Coil, 4=FusionCoil, 5=5k pts, 6=SpeedCoil, 7=Jetpack
--   • Fix Bug #2 : Outils alignés avec le serveur
--   • + ExclamationPoint2 sur bouton DailyReward + sur chaque ButtonFrame
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainFrame = script.Parent
local giveToolEvent = ReplicatedStorage:WaitForChild("GiveToolEvent", 10)
local getDailyDataEvent = ReplicatedStorage:WaitForChild("GetDailyDataEvent", 10)
local claimDailyRewardEvent = ReplicatedStorage:WaitForChild("ClaimDailyRewardEvent", 10)
if not giveToolEvent then warn("GiveToolEvent not found!") end
if not getDailyDataEvent then warn("GetDailyDataEvent not found!") end
if not claimDailyRewardEvent then warn("ClaimDailyRewardEvent not found!") end
-- ========================================
-- ⚠️ CONFIG ALIGNÉE AVEC LE SERVEUR (7 jours)
-- ========================================
local REWARDS_CONFIG = {
	{ buttonName = "ButtonFrame1", day = 1, toolName = "SpeedCoil",    isPoints = false },
	{ buttonName = "ButtonFrame2", day = 2, toolName = nil,            isPoints = true, points = 5000 },
	{ buttonName = "ButtonFrame3", day = 3, toolName = "Gravity Coil", isPoints = false },
	{ buttonName = "ButtonFrame4", day = 4, toolName = "FusionCoil",   isPoints = false },
	{ buttonName = "ButtonFrame5", day = 5, toolName = nil,            isPoints = true, points = 5000 },
	{ buttonName = "ButtonFrame6", day = 6, toolName = "SpeedCoil",    isPoints = false },
	{ buttonName = "ButtonFrame7", day = 7, toolName = "Jetpack",      isPoints = false },
}
local TOTAL_DAYS = #REWARDS_CONFIG

-- ⚙️ AFFICHAGE (même style que les Playtime Rewards)
--   NEW_LOOK = false → l'ancien affichage revient EXACTEMENT
--   NEW_LOOK = true  →
--     • temps restant au format court (4:59 / 12:03:44) sur une bande noire semi-transparente
--       aux bords en fondu (comme le Rookie Guide), sans petit cadre noir
--     • récompense prête : « CLAIM! » blanc avec contour vert, sans fond
--     • récompense prête : le dégradé animé derrière la carte passe au VERT clair
--       (avant il restait bleu : le script ne trouvait pas ce dégradé, créé plus tard)
--     • chaque carte a son FOND dessiné par le script (bleu / or) : les images n'ont plus de fond.
--       VERT = prête à récupérer · GRIS = récupérée. Cartes en or : rayons qui tournent derrière.
local NEW_LOOK          = true
local BAND_TRANSPARENCY = 0.35      -- bande noire : 0 = noir plein, 1 = invisible
local TILE_BACKGROUND   = true      -- false = pas de fond dessiné (si tes images ont encore leur fond)
local TOASTS            = true      -- petites notifications quand on clique sur une récompense pas disponible
local TOAST_TIME        = 2.2       -- secondes à l'écran
local TAP_HAND_IMAGE    = "rbxassetid://78515108577271"   -- main ("" = jamais)
local TAP_HAND_DELAY    = 3         -- la main apparaît après X s sans clic, menu ouvert, sur UNE carte prête
local TAP_HAND_ROTATION = -18       -- inclinaison vers la gauche (degrés)
local HOVER_TIME        = 1.1       -- « CLAIM! » : secondes pour monter (puis autant pour redescendre)
local HOVER_HEIGHT      = 0.05      -- hauteur du flottement (en part de la carte)
local HOVER_GROW        = 0.15      -- « CLAIM! » grossit de 15 % en montant, revient à sa taille en redescendant
local TILE_SCALE        = 1         -- taille du fond par rapport au bouton image (1 = exactement le bouton)
-- jour → image (carrée, SANS fond) et style du fond ("blue" ou "gold")
local DAY_LOOK = {
	[1] = { image = "rbxassetid://75626092982039",  style = "blue" },   -- Speed Coil
	[2] = { image = "rbxassetid://94792225645523",  style = "gold" },   -- 5 000 points
	[3] = { image = "rbxassetid://85739633916759",  style = "blue" },   -- Gravity Coil
	[4] = { image = "rbxassetid://131042216755824", style = "blue" },   -- Fusion Coil
	[5] = { image = "rbxassetid://94792225645523",  style = "gold" },   -- 5 000 points
	[6] = { image = "rbxassetid://75626092982039",  style = "blue" },   -- Speed Coil
	[7] = { image = "rbxassetid://71325292424561",  style = "gold" },   -- Jetpack
}
local RAYS_IMAGE        = "rbxassetid://79497376602630"   -- rayons derrière les cartes en or ("" = aucun)
local RAYS_TRANSPARENCY = 0.35
local RAYS_TURN_TIME    = 30                               -- secondes pour un tour complet

local READY_GRADIENT = ColorSequence.new({        -- même motif que le bleu animé, en vert clair
	ColorSequenceKeypoint.new(0,    Color3.fromRGB(0, 185, 80)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(205, 255, 215)),
	ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(0, 185, 80)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(195, 255, 205)),
	ColorSequenceKeypoint.new(1,    Color3.fromRGB(0, 185, 80)),
})
local playerData = {
	currentDay = 1, lastClaimTime = 0, claimedToday = false,
	timeRemaining = 0, serverTime = 0,
}
local firstJoinData = {
	active = false, timeRemaining = 0, clientStartTime = tick(),
}
local heartbeatTweens = {}
local originalSizes = {}
local originalGradientColors = {}
local clientStartTime = tick()
local buttonCache = {}
local updateCoroutine = nil
local isRunning = true
local activeConfetti = {}
local needsUpdate = false
local claimDebounce = false
local exclamationIcon = nil
local dailyRewardExclamation = nil
-- ========================================
-- NOTIFICATION
-- ========================================
local function showNotification(message)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PointsNotificationGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 450, 0, 120)
	frame.Position = UDim2.new(0.5, -225, 0.35, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 15)
	uiCorner.Parent = frame
	local border = Instance.new("UIStroke")
	border.Color = Color3.fromRGB(85, 255, 127)
	border.Thickness = 3
	border.Parent = frame
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, -20, 1, -20)
	textLabel.Position = UDim2.new(0, 10, 0, 10)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = message
	textLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
	textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	textLabel.TextStrokeTransparency = 0.5
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 24
	textLabel.TextWrapped = true
	textLabel.Parent = frame
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.35, 0)
	frame.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 450, 0, 120)
	}):Play()
	task.delay(2.5, function()
		local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fadeTween = TweenService:Create(frame, fadeInfo, {
			BackgroundTransparency = 1, Size = UDim2.new(0, 450, 0, 80)
		})
		TweenService:Create(textLabel, fadeInfo, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		TweenService:Create(border, fadeInfo, {Transparency = 1}):Play()
		fadeTween:Play()
		fadeTween.Completed:Connect(function() screenGui:Destroy() end)
	end)
end
-- ========================================
-- UTILITAIRES UI
-- ========================================
local function formatTime(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = math.floor(seconds % 60)
	if hours > 0 then return string.format("%dh %dm %ds", hours, minutes, secs)
	elseif minutes > 0 then return string.format("%dm %ds", minutes, secs)
	else return string.format("%ds", secs) end
end
local function formatShort(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h, m, sec = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
	return string.format("%d:%02d", m, sec)
end
-- la bande du compteur est découpée dans la forme arrondie du bouton (ne dépasse jamais)
local function bandClip(imageButton)
	local clip = imageButton:FindFirstChild("BandClip")
	if clip then return clip end
	clip = Instance.new("CanvasGroup")
	clip.Name = "BandClip"
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.Size = UDim2.fromScale(1, 1)
	clip.ZIndex = 2
	clip.Active = false
	local c = Instance.new("UICorner")
	local bc = imageButton:FindFirstChildOfClass("UICorner")
	c.CornerRadius = bc and bc.CornerRadius or UDim.new(0, 0)
	c.Parent = clip
	clip.Parent = imageButton
	return clip
end

-- ========================================
-- 🆕 FOND DES CARTES (NEW_LOOK + TILE_BACKGROUND) — même rendu que les Playtime Rewards
-- ========================================
local TILE_COLORS = {
	blue  = { Color3.fromRGB(82, 136, 245),  Color3.fromRGB(82, 136, 245) },
	gold  = { Color3.fromRGB(254, 223, 49),  Color3.fromRGB(241, 180, 40) },
	green = { Color3.fromRGB(95, 225, 115),  Color3.fromRGB(40, 185, 80) },
	grey  = { Color3.fromRGB(150, 150, 150), Color3.fromRGB(115, 115, 115) },
}
local function getTile(cache)
	if cache.tile and cache.tile.Parent then return cache.tile end
	local btn = cache.imageButton
	local look = DAY_LOOK[cache.config.day] or {}
	local tile = Instance.new("CanvasGroup")
	tile.Name = "TileBackground"
	tile.BorderSizePixel = 0
	tile.BackgroundTransparency = 1
	tile.ZIndex = math.max(btn.ZIndex - 1, 0)
	tile.Active = false
	local corner = Instance.new("UICorner")
	local fc = cache.frame:FindFirstChildOfClass("UICorner")
	corner.CornerRadius = fc and fc.CornerRadius or UDim.new(0.14, 0)
	corner.Parent = tile
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 1
	local grad = Instance.new("UIGradient")
	grad.Parent = fill
	fill.Parent = tile
	if look.style == "gold" and RAYS_IMAGE ~= "" then
		local rays = Instance.new("ImageLabel")
		rays.Name = "Rays"
		rays.BackgroundTransparency = 1
		rays.Image = RAYS_IMAGE
		rays.ImageTransparency = RAYS_TRANSPARENCY
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		rays.Size = UDim2.fromScale(1.6, 1.6)
		rays.ZIndex = 2
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = 1
		a.DominantAxis = Enum.DominantAxis.Width   -- carte large (jour 7) : les rayons couvrent toute la largeur
		a.Parent = rays
		rays.Parent = tile
		TweenService:Create(rays, TweenInfo.new(RAYS_TURN_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{ Rotation = 360 }):Play()
	end
	local function follow()
		local bs, ap = btn.Size, btn.AnchorPoint
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Position = btn.Position + UDim2.new(bs.X.Scale * (0.5 - ap.X), bs.X.Offset * (0.5 - ap.X),
			bs.Y.Scale * (0.5 - ap.Y), bs.Y.Offset * (0.5 - ap.Y))
		tile.Size = UDim2.new(bs.X.Scale * TILE_SCALE, bs.X.Offset * TILE_SCALE, bs.Y.Scale * TILE_SCALE, bs.Y.Offset * TILE_SCALE)
		-- même arrondi EN PIXELS que la carte
		local fs, ts = cache.frame.AbsoluteSize, btn.AbsoluteSize
		local tmin = math.min(ts.X, ts.Y)
		if fc and tmin > 1 then
			local px = fc.CornerRadius.Scale * math.min(fs.X, fs.Y) + fc.CornerRadius.Offset
			corner.CornerRadius = UDim.new(math.clamp(px / tmin, 0, 0.5), 0)
		end
		local clip = btn:FindFirstChild("BandClip")
		local cc = clip and clip:FindFirstChildOfClass("UICorner")
		if cc then cc.CornerRadius = corner.CornerRadius end
	end
	follow()
	for _, p in ipairs({ "Size", "Position", "AnchorPoint", "AbsoluteSize" }) do
		btn:GetPropertyChangedSignal(p):Connect(follow)
	end
	tile.Parent = btn.Parent
	cache.tile, cache.tileGrad = tile, grad
	return tile
end
local function styleTile(cache, mode)       -- "normal" | "ready" | "claimed"
	if not (NEW_LOOK and TILE_BACKGROUND) then return end
	if cache.tileMode == mode and cache.tile and cache.tile.Parent then return end
	getTile(cache)
	local look = DAY_LOOK[cache.config.day] or {}
	local key = (mode == "ready") and "green" or (mode == "claimed") and "grey" or (look.style or "blue")
	local c = TILE_COLORS[key] or TILE_COLORS.blue
	cache.tileGrad.Color = ColorSequence.new(c[1], c[2])
	cache.tileMode = mode
end

-- ============================================================
-- 🔔 PETITE NOTIFICATION (bande noire en fondu, descend du haut)
--    → ModuleScript ReplicatedStorage ▸ RewardToast (commun Playtime / Daily / Quêtes,
--      plus petit et collé en haut sur mobile)
-- ============================================================
local RewardToast = nil
do
	local m = ReplicatedStorage:WaitForChild("RewardToast", 10)
	if m then
		local ok, r = pcall(require, m)
		if ok then RewardToast = r else warn("[Rewards] RewardToast : " .. tostring(r)) end
	end
end
local function rewardToast(title, sub)
	if not TOASTS or not RewardToast then return end
	RewardToast.Show(title, sub, TOAST_TIME)
end

-- ============================================================
-- 👆 RÉCOMPENSE PRÊTE : « CLAIM! » qui flotte + main si le joueur ne réagit pas
-- ============================================================
local hoverTweens = {}
local readySet = {}            -- [bouton] = true : récompenses prêtes en ce moment
local tapHand                  -- la main (une seule, sur une seule carte)
local lastInput = os.clock()   -- dernier clic / toucher du joueur
local shownAt = os.clock()     -- ouverture du menu

-- « CLAIM! » : monte en grossissant un peu, redescend à sa taille, et recommence
local function setReadyFx(btn, label, on)
	if not NEW_LOOK then return end
	readySet[btn] = on and true or nil
	local active = label and label:GetAttribute("Hover")
	if on and label and not active then
		label:SetAttribute("Hover", true)
		local basePos, baseSize = label.Position, label.Size
		local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
		local baseMax = cap and cap.MaxTextSize or 20
		local alpha = Instance.new("NumberValue")
		alpha.Name = "HoverAlpha"
		alpha.Parent = label
		alpha.Changed:Connect(function(a)
			label.Position = UDim2.new(basePos.X.Scale, basePos.X.Offset, basePos.Y.Scale - HOVER_HEIGHT * a, basePos.Y.Offset)
			label.Size = UDim2.new(baseSize.X.Scale * (1 + HOVER_GROW * a), baseSize.X.Offset,
				baseSize.Y.Scale * (1 + HOVER_GROW * a), baseSize.Y.Offset)
			-- la taille du texte est plafonnée : on relève le plafond en même temps
			if cap then cap.MaxTextSize = math.floor(baseMax * (1 + HOVER_GROW * a) + 0.5) end
		end)
		local tw = TweenService:Create(alpha, TweenInfo.new(HOVER_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Value = 1 })
		hoverTweens[label] = { tw = tw, alpha = alpha, pos = basePos, size = baseSize, cap = cap, max = baseMax }
		tw:Play()
	elseif not on and active then
		local h = hoverTweens[label]
		hoverTweens[label] = nil
		label:SetAttribute("Hover", nil)
		if h then
			h.tw:Cancel()
			h.alpha:Destroy()
			label.Position, label.Size = h.pos, h.size
			if h.cap then h.cap.MaxTextSize = h.max end
		end
	end
end

-- 👆 La main n'apparaît que si le joueur ne réagit pas : une récompense est prête,
--    le menu est ouvert depuis TAP_HAND_DELAY s sans aucun clic → elle tape sur UNE
--    seule carte (la première prête). Au moindre clic, elle disparaît.
local function hideHand()
	if tapHand then tapHand:Destroy() tapHand = nil end
end
UserInputService.InputBegan:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
		or t == Enum.UserInputType.Gamepad1 then
		lastInput = os.clock()
		hideHand()
	end
end)
local function onScreen(obj)
	local o = obj
	while o and not o:IsA("ScreenGui") do
		if o:IsA("GuiObject") and not o.Visible then return false end
		o = o.Parent
	end
	return o ~= nil and o.Enabled
end
local wasShown = false
local function updateHand()
	if not NEW_LOOK or TAP_HAND_IMAGE == "" then hideHand() return end
	local shown = onScreen(mainFrame)
	if shown and not wasShown then shownAt = os.clock() end
	wasShown = shown
	-- la première carte prête (en haut à gauche d'abord)
	local target
	for b in pairs(readySet) do
		if b.Parent and (not target or b.AbsolutePosition.Y < target.AbsolutePosition.Y - 2
			or (math.abs(b.AbsolutePosition.Y - target.AbsolutePosition.Y) <= 2 and b.AbsolutePosition.X < target.AbsolutePosition.X)) then
			target = b
		end
	end
	local idle = os.clock() - math.max(lastInput, shownAt)
	if not shown or not target or idle < TAP_HAND_DELAY then hideHand() return end
	if tapHand and tapHand.Parent == target then return end
	hideHand()
	local hand = Instance.new("ImageLabel")
	hand.Name = "TapHand"
	hand.BackgroundTransparency = 1
	hand.Image = TAP_HAND_IMAGE
	hand.ScaleType = Enum.ScaleType.Fit
	hand.AnchorPoint = Vector2.new(0.25, 0.1)          -- le bout du doigt
	-- coin en bas à droite, le doigt juste à droite du « CLAIM! »
	hand.Position = UDim2.fromScale(0.86, 0.88)
	hand.Size = UDim2.fromScale(0.46, 0.46)
	hand.Rotation = TAP_HAND_ROTATION
	hand.ZIndex = 4
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.Parent = hand
	hand.Parent = target
	TweenService:Create(hand, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromScale(0.82, 0.84), Size = UDim2.fromScale(0.42, 0.42), Rotation = TAP_HAND_ROTATION - 6 }):Play()
	tapHand = hand
end

local function createConfetti(button)
	local screenGui = button:FindFirstAncestorOfClass("ScreenGui")
	if not screenGui then return end
	local absolutePos = button.AbsolutePosition
	local absoluteSize = button.AbsoluteSize
	for i = 1, 15 do
		local confetti = Instance.new("Frame")
		confetti.Size = UDim2.new(0, math.random(5, 15), 0, math.random(5, 15))
		confetti.Position = UDim2.fromOffset(absolutePos.X + absoluteSize.X / 2, absolutePos.Y + absoluteSize.Y / 2)
		confetti.AnchorPoint = Vector2.new(0.5, 0.5)
		confetti.BackgroundColor3 = Color3.fromHSV(math.random(), 1, 1)
		confetti.BorderSizePixel = 0
		confetti.Parent = screenGui
		table.insert(activeConfetti, confetti)
		local angle = math.random() * math.pi * 2
		local distance = math.random(100, 300)
		local endX = math.cos(angle) * distance
		local endY = math.sin(angle) * distance
		TweenService:Create(confetti, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(absolutePos.X + absoluteSize.X / 2 + endX, absolutePos.Y + absoluteSize.Y / 2 + endY),
			Rotation = math.random(-180, 180), BackgroundTransparency = 1
		}):Play()
		Debris:AddItem(confetti, 1.1)
		task.delay(1.1, function()
			local index = table.find(activeConfetti, confetti)
			if index then table.remove(activeConfetti, index) end
		end)
	end
end
local function cleanupAllConfetti()
	for _, confetti in ipairs(activeConfetti) do
		if confetti and confetti.Parent then confetti:Destroy() end
	end
	table.clear(activeConfetti)
end
local function startHeartbeat(imageButton)
	if heartbeatTweens[imageButton] then heartbeatTweens[imageButton]:Cancel() end
	if not originalSizes[imageButton] then originalSizes[imageButton] = imageButton.Size end
	imageButton.AnchorPoint = Vector2.new(0.5, 0.5)
	imageButton.Position = UDim2.new(0.5, 0, 0.5, 0)
	local originalSize = originalSizes[imageButton]
	local tween = TweenService:Create(imageButton,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Size = UDim2.new(originalSize.X.Scale * 1.1, 0, originalSize.Y.Scale * 1.1, 0)
		})
	heartbeatTweens[imageButton] = tween
	tween:Play()
end
local function stopHeartbeat(imageButton)
	if heartbeatTweens[imageButton] then
		heartbeatTweens[imageButton]:Cancel()
		heartbeatTweens[imageButton] = nil
		if originalSizes[imageButton] then
			TweenService:Create(imageButton, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Size = originalSizes[imageButton]}):Play()
		end
	end
end
-- le dégradé animé est créé par le script de la carte, parfois APRÈS celui-ci
local function frameGradient(cache)
	if NEW_LOOK and (not cache.gradient or not cache.gradient.Parent) then
		cache.gradient = cache.frame:FindFirstChildOfClass("UIGradient")
	end
	return cache.gradient
end
local function setFrameGradientGreen(cache, isReady)
	styleTile(cache, isReady and "ready" or "normal")
	setReadyFx(cache.imageButton, cache.textLabel, isReady and cache.textLabel and cache.textLabel.Visible)
	local gradient = frameGradient(cache)
	if gradient and NEW_LOOK then
		if not originalGradientColors[cache.frame] then originalGradientColors[cache.frame] = gradient.Color end
		gradient.Color = isReady and READY_GRADIENT or originalGradientColors[cache.frame]
		return
	end
	if gradient then
		if not originalGradientColors[cache.frame] then
			originalGradientColors[cache.frame] = gradient.Color
		end
		if isReady then
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 200, 50)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 255, 100))
			})
		else
			gradient.Color = originalGradientColors[cache.frame]
		end
	end
end
local function setFrameGradientClaimed(cache)
	styleTile(cache, "claimed")
	setReadyFx(cache.imageButton, cache.textLabel, false)
	local gradient = frameGradient(cache)
	if gradient and NEW_LOOK and not originalGradientColors[cache.frame] then
		originalGradientColors[cache.frame] = gradient.Color
	end
	if gradient then
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 80, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 120, 120)),
		})
	end
end
local function createCountdownLabel(imageButton)
	if NEW_LOOK then
		-- bande noire aux bords en fondu + texte sans fond par-dessus
		local band = Instance.new("Frame")
		band.Name = "CountdownBand"
		band.BackgroundColor3 = Color3.new(0, 0, 0)
		band.BorderSizePixel = 0
		band.Active = false
		band.ZIndex = 2
		band.AnchorPoint = Vector2.new(0.5, 0.5)
		band.Position = UDim2.new(0.5, 0, 0.86, 0)
		band.Size = UDim2.new(1, 0, 0.26, 0)      -- largeur du bouton : ne déborde pas sur la carte
		band.Visible = false
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.22, BAND_TRANSPARENCY),
			NumberSequenceKeypoint.new(0.78, BAND_TRANSPARENCY),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = band
		band.Parent = bandClip(imageButton)
		local label = Instance.new("TextLabel")
		label.Name = "CountdownLabel"
		label.Size = UDim2.new(0.9, 0, 0.22, 0)
		label.Position = UDim2.new(0.5, 0, 0.86, 0)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.BackgroundTransparency = 1
		label.Text = ""
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.ZIndex = 3
		label.Parent = imageButton
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = 20
		c.MinTextSize = 8
		c.Parent = label
		local st = Instance.new("UIStroke")
		st.Name = "TextStroke"
		st.Color = Color3.fromRGB(0, 0, 0)
		st.Thickness = 1.5
		st.Parent = label
		label:GetPropertyChangedSignal("Visible"):Connect(function()
			if not label.Visible then band.Visible = false end
		end)
		return label
	end
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "CountdownLabel"
	textLabel.Size = UDim2.new(0.85, 0, 0.22, 0)
	textLabel.Position = UDim2.new(0.5, 0, 0.88, 0)
	textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	textLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	textLabel.BackgroundTransparency = 0.3
	textLabel.Text = ""
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextXAlignment = Enum.TextXAlignment.Center
	textLabel.TextYAlignment = Enum.TextYAlignment.Center
	textLabel.Parent = imageButton
	local textSizeConstraint = Instance.new("UITextSizeConstraint")
	textSizeConstraint.MaxTextSize = 18
	textSizeConstraint.MinTextSize = 8
	textSizeConstraint.Parent = textLabel
	Instance.new("UICorner", textLabel).CornerRadius = UDim.new(0.2, 0)
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 1
	textStroke.Parent = textLabel
	return textLabel
end
local function updateGlobalExclamationIcons()
	local isRewardAvailable = (playerData.currentDay >= 1 and playerData.currentDay <= TOTAL_DAYS) and not playerData.claimedToday
	if firstJoinData.active then
		local elapsed = tick() - firstJoinData.clientStartTime
		local remaining = firstJoinData.timeRemaining - elapsed
		if remaining > 0 then isRewardAvailable = false end
	end
	if exclamationIcon then exclamationIcon.Visible = isRewardAvailable end
	if dailyRewardExclamation then dailyRewardExclamation.Visible = isRewardAvailable end
end
local function getFirstJoinClientRemaining()
	if not firstJoinData.active then return 0 end
	local elapsed = tick() - firstJoinData.clientStartTime
	return math.max(0, firstJoinData.timeRemaining - elapsed)
end
-- ========================================
-- MISE À JOUR DU COUNTDOWN
-- ========================================
local function updateCountdown()
	local elapsedSinceServerUpdate = tick() - clientStartTime
	local currentTimeRemaining = playerData.timeRemaining - elapsedSinceServerUpdate
	if currentTimeRemaining < 0 then currentTimeRemaining = 0 end
	local firstJoinRemaining = getFirstJoinClientRemaining()
	if firstJoinData.active and firstJoinRemaining <= 0 then
		firstJoinData.active = false
	end
	for day, cache in pairs(buttonCache) do
		local config    = cache.config
		local btn       = cache.imageButton
		local lbl       = cache.textLabel
		local lock      = cache.lockImage
		local check     = cache.greenCheck
		local frameExcl = cache.frameExclamation
		if config.day == playerData.currentDay then
			if config.day == 1 and firstJoinData.active and firstJoinRemaining > 0 then
				lbl.Visible     = true
				lbl.Text        = NEW_LOOK and formatShort(firstJoinRemaining) or ("🕐 " .. formatTime(firstJoinRemaining))
				lbl.TextColor3  = Color3.fromRGB(255, 200, 50)
				btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
				if lock      then lock.Visible      = true  end
				if check     then check.Visible     = false end
				if frameExcl then frameExcl.Visible = false end
				setFrameGradientGreen(cache, false)
				stopHeartbeat(btn)
			elseif playerData.claimedToday then
				if currentTimeRemaining > 0 then
					lbl.Visible     = true
					lbl.Text        = NEW_LOOK and formatShort(currentTimeRemaining) or formatTime(currentTimeRemaining)
					lbl.TextColor3  = Color3.fromRGB(255, 255, 255)
					btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
					if lock      then lock.Visible      = true  end
					if check     then check.Visible     = false end
					if frameExcl then frameExcl.Visible = false end
					setFrameGradientGreen(cache, false)
					stopHeartbeat(btn)
				else
					lbl.Visible     = false
					btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
					if lock      then lock.Visible      = false end
					if check     then check.Visible     = false end
					if frameExcl then frameExcl.Visible = true  end
					setFrameGradientGreen(cache, true)
					startHeartbeat(btn)
					if not needsUpdate then
						needsUpdate = true
						task.delay(0.5, function()
							if getDailyDataEvent and needsUpdate then
								getDailyDataEvent:FireServer()
								needsUpdate = false
							end
						end)
					end
				end
			else
				lbl.Visible     = true
				lbl.Text        = NEW_LOOK and "CLAIM!" or "CLAIM"
				lbl.TextColor3  = Color3.fromRGB(100, 255, 130)
				btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
				if lock      then lock.Visible      = false end
				if check     then check.Visible     = false end
				if frameExcl then frameExcl.Visible = true  end
				setFrameGradientGreen(cache, true)
				startHeartbeat(btn)
			end
		elseif config.day < playerData.currentDay then
			lbl.Visible     = false
			btn.ImageColor3 = Color3.fromRGB(100, 100, 100)
			if lock      then lock.Visible      = false end
			if check     then check.Visible     = true  end
			if frameExcl then frameExcl.Visible = false end
			setFrameGradientClaimed(cache)
			stopHeartbeat(btn)
		else
			lbl.Visible     = false
			btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
			if lock      then lock.Visible      = true  end
			if check     then check.Visible     = false end
			if frameExcl then frameExcl.Visible = false end
			setFrameGradientGreen(cache, false)
			stopHeartbeat(btn)
		end
		if NEW_LOOK and lbl.Visible then
			-- « CLAIM! » : sans bande, contour vert · temps : blanc sur la bande en fondu
			local isClaim = lbl.Text == "CLAIM!"
			local band = btn:FindFirstChild("CountdownBand", true)
			local st = lbl:FindFirstChild("TextStroke")
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			if st then
				st.Color = isClaim and Color3.fromRGB(0, 140, 40) or Color3.fromRGB(0, 0, 0)
				st.Thickness = isClaim and 2 or 1.5
			end
			if band then band.Visible = not isClaim end
		end
	end
	updateGlobalExclamationIcons()
	updateHand()
end
-- ========================================
-- CLAIM
-- ========================================
local function claimReward(config, cache)
	if not claimDailyRewardEvent then return end
	if claimDebounce then return end
	if not NEW_LOOK then
		claimDebounce = true
		task.delay(2, function() claimDebounce = false end)
	end
	if config.day ~= playerData.currentDay then
		local cancelSound = SoundService:FindFirstChild("buycancel")
		if cancelSound then cancelSound:Play() end
		if config.day < playerData.currentDay then
			rewardToast("Already claimed!", "Come back every day for the next rewards")
		else
			local waitDays = config.day - playerData.currentDay
			rewardToast("Not available yet!", waitDays == 1 and "Unlocks tomorrow"
				or ("Unlocks in " .. waitDays .. " days"))
		end
		return
	end
	if config.day == 1 and firstJoinData.active and getFirstJoinClientRemaining() > 0 then
		local cancelSound = SoundService:FindFirstChild("buycancel")
		if cancelSound then cancelSound:Play() end
		rewardToast("Almost there!", "First reward in " .. formatShort(getFirstJoinClientRemaining()))
		return
	end
	if playerData.claimedToday then
		local elapsedSinceServerUpdate = tick() - clientStartTime
		local currentTimeRemaining = playerData.timeRemaining - elapsedSinceServerUpdate
		if currentTimeRemaining <= 0 then
			getDailyDataEvent:FireServer()
		else
			local cancelSound = SoundService:FindFirstChild("buycancel")
			if cancelSound then cancelSound:Play() end
			-- cette carte = la PROCHAINE récompense (celle d'aujourd'hui est déjà prise)
			rewardToast("Not ready yet!", "Available in " .. formatShort(currentTimeRemaining))
		end
		return
	end
	if NEW_LOOK then
		-- anti double-clic seulement sur un vrai claim (un clic sur une carte verrouillée
		-- ne bloque plus le clic suivant pendant 2 s)
		claimDebounce = true
		task.delay(2, function() claimDebounce = false end)
	end
	claimDailyRewardEvent:FireServer()
end
-- ========================================
-- INIT BOUTONS
-- ========================================
local function initializeButtons()
	local dailyToolGui = playerGui:WaitForChild("Daily tool", 5)
	if dailyToolGui then
		local frameInGui = dailyToolGui:FindFirstChild("open button")
		if frameInGui then
			exclamationIcon = frameInGui:FindFirstChild("ExclamationPoint2")
			if exclamationIcon then exclamationIcon.Visible = false end
		end
		local dailyToolFrame = dailyToolGui:FindFirstChild("DailyTool")
		if dailyToolFrame then
			local dailyRewardBtn = dailyToolFrame:FindFirstChild("DailyReward")
			if dailyRewardBtn then
				dailyRewardExclamation = dailyRewardBtn:FindFirstChild("ExclamationPoint2")
				if dailyRewardExclamation then dailyRewardExclamation.Visible = false end
			end
		end
	end
	for i, config in ipairs(REWARDS_CONFIG) do
		local buttonFrame = mainFrame:FindFirstChild(config.buttonName)
		if buttonFrame then
			local imageButton = buttonFrame:FindFirstChildOfClass("ImageButton")
			if imageButton then
				imageButton.AnchorPoint = Vector2.new(0.5, 0.5)
				imageButton.Position = UDim2.new(0.5, 0, 0.5, 0)
				originalSizes[imageButton] = imageButton.Size
				local look = DAY_LOOK[config.day]
				if NEW_LOOK and TILE_BACKGROUND and look then
					imageButton.Image = look.image
					imageButton.ScaleType = Enum.ScaleType.Fit     -- image carrée : jamais déformée (carte large du jour 7)
					imageButton.BackgroundTransparency = 1
				end
				local textLabel = imageButton:FindFirstChild("CountdownLabel") or createCountdownLabel(imageButton)
				local greenCheck = buttonFrame:FindFirstChild("GreenCheck")
				if greenCheck then greenCheck.Visible = false end
				local frameExcl = buttonFrame:FindFirstChild("ExclamationPoint2")
				if frameExcl then frameExcl.Visible = false end
				buttonCache[config.day] = {
					frame            = buttonFrame,
					imageButton      = imageButton,
					textLabel        = textLabel,
					lockImage        = imageButton:FindFirstChild("Lock"),
					greenCheck       = greenCheck,
					frameExclamation = frameExcl,
					gradient         = buttonFrame:FindFirstChildOfClass("UIGradient"),
					config           = config,
				}
				imageButton.Activated:Connect(function()
					claimReward(config, buttonCache[config.day])
				end)
			end
		end
	end
	updateCoroutine = task.spawn(function()
		while isRunning and task.wait(1) do updateCountdown() end
	end)
	updateCountdown()
end
-- ========================================
-- ÉCOUTE SERVEUR
-- ========================================
if getDailyDataEvent then
	getDailyDataEvent.OnClientEvent:Connect(function(data)
		if data then
			playerData.currentDay     = data.currentDay or 1
			playerData.lastClaimTime  = data.lastClaimTime or 0
			playerData.claimedToday   = data.claimedToday or false
			playerData.timeRemaining  = data.timeRemaining or 0
			playerData.serverTime     = data.serverTime or 0
			clientStartTime = tick()
			needsUpdate = false
			if data.isFirstJoin and data.firstJoinTimeRemaining and data.firstJoinTimeRemaining > 0 then
				firstJoinData.active          = true
				firstJoinData.timeRemaining   = data.firstJoinTimeRemaining
				firstJoinData.clientStartTime = tick()
			else
				firstJoinData.active = false
			end
			updateGlobalExclamationIcons()
		end
	end)
end
if claimDailyRewardEvent then
	claimDailyRewardEvent.OnClientEvent:Connect(function(success, newData)
		if success and newData then
			playerData.currentDay    = newData.currentDay
			playerData.lastClaimTime = newData.lastClaimTime
			playerData.claimedToday  = newData.claimedToday
			playerData.timeRemaining = newData.timeRemaining or 0
			playerData.serverTime    = newData.serverTime or 0
			clientStartTime = tick()
			firstJoinData.active = false
			if exclamationIcon then exclamationIcon.Visible = false end
			if dailyRewardExclamation then dailyRewardExclamation.Visible = false end
			local claimedDay = newData.currentDay - 1
			if claimedDay < 1 then claimedDay = TOTAL_DAYS end
			for _, cache in pairs(buttonCache) do
				if cache.config.day == claimedDay then
					if cache.greenCheck then cache.greenCheck.Visible = true end
					if cache.frameExclamation then cache.frameExclamation.Visible = false end
					setFrameGradientClaimed(cache)
					if cache.config.isPoints then
						--showNotification("🎉 Congrats! You got +5,000 points!")
					else
						local sound = SoundService:FindFirstChild("DailyTool")
						if sound then sound:Play() end
					end
					createConfetti(cache.imageButton)
					break
				end
			end
		else
			if newData and newData.firstJoinBlocked and newData.firstJoinTimeRemaining then
				firstJoinData.active          = true
				firstJoinData.timeRemaining   = newData.firstJoinTimeRemaining
				firstJoinData.clientStartTime = tick()
			end
			local cancelSound = SoundService:FindFirstChild("buycancel")
			if cancelSound then cancelSound:Play() end
			if newData and newData.firstJoinBlocked and newData.firstJoinTimeRemaining then
				rewardToast("Almost there!", "First reward in " .. formatShort(newData.firstJoinTimeRemaining))
			else
				rewardToast("Couldn't claim", "Please try again in a moment")
			end
		end
	end)
end
-- ========================================
-- CLEANUP
-- ========================================
Players.PlayerRemoving:Connect(function(removingPlayer)
	if removingPlayer == player then
		isRunning = false
		for _, tween in pairs(heartbeatTweens) do
			if tween then tween:Cancel() end
		end
		cleanupAllConfetti()
		heartbeatTweens = {}
		buttonCache = {}
	end
end)
script.Destroying:Connect(function()
	isRunning = false
	for _, tween in pairs(heartbeatTweens) do
		if tween then tween:Cancel() end
	end
	cleanupAllConfetti()
	heartbeatTweens = {}
	buttonCache = {}
end)
task.wait(1)
if getDailyDataEvent then getDailyDataEvent:FireServer() end
initializeButtons()