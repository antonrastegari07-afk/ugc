-- ============================================================
-- PlaytimeRewards - LocalScript v6
-- + ExclamationPoint3 sur open button, bouton PlaytimeReward,
--   ET sur chaque ButtonFrame individuellement
-- ============================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainFrame = script.Parent

-- ⚙️ AFFICHAGE
--   NEW_LOOK = false → l'ancien affichage revient EXACTEMENT (cadres noirs, « COOLDOWN » dans la 1re carte…)
--   NEW_LOOK = true  →
--     • temps restant au format court (4:59 / 1:02:10) sur une bande noire semi-transparente
--       aux bords en fondu (comme le Rookie Guide), sans petit cadre noir
--     • récompense prête : « CLAIM! » blanc avec contour vert, sans fond
--     • tout récupéré : une bande au milieu de la grille « All rewards claimed! / New rewards in 5:12:03 »
--       (plus de texte caché par le check de la 1re carte)
--     • chaque carte a son FOND dessiné par le script (carré bleu arrondi, comme l'ancienne image) :
--       bleu = pas encore prête · VERT = prête à récupérer · GRIS = récupérée.
--       → les images peuvent n'avoir QUE les pièces, sans fond.
--     • récompense prête : le dégradé animé derrière la carte passe au VERT clair
--   SHOW_CLAIM_ALL = true → bouton « Claim all (N) » quand au moins 2 récompenses sont prêtes
--   TILE_BACKGROUND = false → pas de fond dessiné (si tes images ont encore leur fond)
local NEW_LOOK        = true
local SHOW_CLAIM_ALL  = false
local TILE_BACKGROUND = true
-- fond des cartes pas encore prêtes : "blue" (défaut) ou "gold" pour une carte précise
local TILE_STYLE = { pt_4 = "gold", pt_9 = "gold" }
-- images des récompenses (pièces SANS fond) : la carte dessine le fond derrière
local REWARD_IMAGES = {
	default = "rbxassetid://121462779250924",   -- x500
	pt_4    = "rbxassetid://122148400972593",   -- x1000 (coffre)
	pt_9    = "rbxassetid://122148400972593",   -- x1000 (coffre)
}
local TOASTS            = true      -- petites notifications quand on clique sur une récompense pas disponible
local TOAST_TIME        = 2.2       -- secondes à l'écran
local TAP_HAND_IMAGE    = "rbxassetid://78515108577271"   -- main ("" = jamais)
local TAP_HAND_DELAY    = 3         -- la main apparaît après X s sans clic, menu ouvert, sur UNE carte prête
local TAP_HAND_ROTATION = -18       -- inclinaison vers la gauche (degrés)
local HOVER_TIME        = 1.1       -- « CLAIM! » : secondes pour monter (puis autant pour redescendre)
local HOVER_HEIGHT      = 0.05      -- hauteur du flottement (en part de la carte)
local HOVER_GROW        = 0.15      -- « CLAIM! » grossit de 15 % en montant, revient à sa taille en redescendant
local TILE_SCALE        = 1        -- taille du fond par rapport au bouton image (1 = exactement le bouton, comme l'ancienne image)
local RAYS_IMAGE        = "rbxassetid://79497376602630"   -- rayons derrière les coffres ("" = aucun)
local RAYS_TRANSPARENCY = 0.35                             -- 0 = rayons pleins, 1 = invisibles
local RAYS_TURN_TIME    = 30                               -- secondes pour un tour complet (lent)
local BAND_TRANSPARENCY = 0.35      -- bande noire : 0 = noir plein, 1 = invisible
local BANNER_AREA = "ImageLabel"     -- le fond à rayons des récompenses (DailyTool ▸ ImageLabel)

local REWARDS_CONFIG = {
	{id = "pt_1", buttonName = "ButtonFrame1", minutes = 1,  points = 500},
	{id = "pt_2", buttonName = "ButtonFrame2", minutes = 5,  points = 500},
	{id = "pt_3", buttonName = "ButtonFrame3", minutes = 10, points = 500},
	{id = "pt_4", buttonName = "ButtonFrame4", minutes = 15, points = 1000},
	{id = "pt_5", buttonName = "ButtonFrame5", minutes = 20, points = 500},
	{id = "pt_6", buttonName = "ButtonFrame6", minutes = 30, points = 500},
	{id = "pt_7", buttonName = "ButtonFrame7", minutes = 40, points = 500},
	{id = "pt_8", buttonName = "ButtonFrame8", minutes = 50, points = 500},
	{id = "pt_9", buttonName = "ButtonFrame9", minutes = 60, points = 1000},
}

local serverState = nil
local clientReceiveTime  = tick()
local buttonCache        = {}
local heartbeatTweens    = {}
local originalSizes      = {}
local originalGradients  = {}
local activeConfetti     = {}
local isRunning          = true
local updateConnection   = nil

local playtimeClaimEvent   = nil
local playtimeUpdateEvent  = nil
local playtimeGetDataEvent = nil

local previousClaimedIds = {}
local isFirstUpdate      = true

local lastRequestTime = 0
local lastClaimSent   = 0

-- Références aux icônes d'exclamation globales
local exclamationPoint3   = nil   -- dans "open button"
local playtimeExclamation = nil   -- sur le bouton PlaytimeReward dans la frame DailyTool

-- ============================================================
-- UTILITAIRES
-- ============================================================

local function formatTime(seconds)
	seconds = math.floor(seconds)
	local hours   = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs    = seconds % 60
	if hours > 0 then
		return string.format("%dh %dm %ds", hours, minutes, secs)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	else
		return string.format("%ds", secs)
	end
end

local function formatShort(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h, m, sec = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
	return string.format("%d:%02d", m, sec)
end

-- bande noire aux bords en fondu (même style que le Rookie Guide)
local function fadeBand(parent, name, zIndex)
	local band = Instance.new("Frame")
	band.Name = name
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BackgroundTransparency = 0
	band.BorderSizePixel = 0
	band.Active = false
	band.ZIndex = zIndex
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, BAND_TRANSPARENCY),
		NumberSequenceKeypoint.new(0.78, BAND_TRANSPARENCY),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = band
	band.Parent = parent
	return band
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

-- ============================================================
-- 🔔 PETITE NOTIFICATION (bande noire en fondu, descend du haut)
--    Même interface pour Playtime et Daily ("RewardToastGui"). Le mot « Toast »
--    dans son nom la garde visible au-dessus du menu ouvert (UIFocus).
--    S'adapte à tous les écrans : largeur en % de l'écran, bornée en pixels.
-- ============================================================
local function rewardToast(title, sub)
	if not TOASTS then return end
	local gui = playerGui:FindFirstChild("RewardToastGui")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "RewardToastGui"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = false
		gui.DisplayOrder = 50
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = playerGui
	end
	-- une seule à la fois : la précédente remonte et disparaît
	for _, old in ipairs(gui:GetChildren()) do
		if old:IsA("Frame") and old.Name == "Toast" then
			old.Name = "ToastOut"
			TweenService:Create(old, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.new(0.5, 0, 0, -10), BackgroundTransparency = 1 }):Play()
			for _, d in ipairs(old:GetDescendants()) do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, TweenInfo.new(0.2), { Transparency = 1 }):Play()
				end
			end
			task.delay(0.22, function() old:Destroy() end)
		end
	end
	local hasSub = sub ~= nil and sub ~= ""
	local f = Instance.new("Frame")
	f.Name = "Toast"
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 0, -10)
	f.Size = UDim2.new(0.6, 0, 0, hasSub and 62 or 44)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 0
	f.BorderSizePixel = 0
	f.Active = false
	local sc = Instance.new("UISizeConstraint")
	sc.MinSize = Vector2.new(260, 0)
	sc.MaxSize = Vector2.new(620, 200)
	sc.Parent = f
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.3),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	local function line(text, y, h, size, color)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, y)
		t.Size = UDim2.fromScale(0.7, h)
		t.Font = Enum.Font.FredokaOne
		t.Text = text
		t.TextScaled = true
		t.TextColor3 = color
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = size
		c.Parent = t
		local st = Instance.new("UIStroke")
		st.Thickness = 1.5
		st.Parent = t
		t.Parent = f
	end
	if hasSub then
		line(title, 0.33, 0.48, 26, Color3.fromRGB(255, 255, 255))
		line(sub, 0.75, 0.34, 19, Color3.fromRGB(255, 220, 90))
	else
		line(title, 0.5, 0.7, 26, Color3.fromRGB(255, 255, 255))
	end
	f.Parent = gui
	-- descend du haut, petit rebond
	TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14) }):Play()
	task.delay(TOAST_TIME, function()
		if f.Parent and f.Name == "Toast" then
			f.Name = "ToastOut"
			local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(f, info, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -10) }):Play()
			task.delay(0.32, function() f:Destroy() end)
		end
	end)
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

local function formatPoints(pts)
	if pts >= 1000000 then
		return string.format("%.1fM", pts / 1000000)
	elseif pts >= 1000 then
		return string.format("%.0fk", pts / 1000)
	end
	return tostring(pts)
end

-- ============================================================
-- ICÔNES EXCLAMATION GLOBALES (open button + PlaytimeReward)
-- ============================================================

local function updateGlobalExclamationIcons()
	if not serverState then
		if exclamationPoint3   then exclamationPoint3.Visible   = false end
		if playtimeExclamation then playtimeExclamation.Visible = false end
		return
	end

	local hasClaimable = false

	local elapsed        = tick() - clientReceiveTime
	local resetRemaining = math.max(0, (serverState.resetTimeRemaining or 0) - elapsed)
	local allClaimed     = serverState.allClaimed and resetRemaining > 0

	if not allClaimed then
		for _, r in ipairs(serverState.rewards or {}) do
			if not r.isClaimed then
				local adjLeft  = math.max(0, (r.minutesLeft or 0) - (elapsed / 60))
				local canClaim = r.canClaim or adjLeft <= 0
				if canClaim then
					hasClaimable = true
					break
				end
			end
		end
	end

	if exclamationPoint3   then exclamationPoint3.Visible   = hasClaimable end
	if playtimeExclamation then playtimeExclamation.Visible = hasClaimable end
end

-- ============================================================
-- ANIMATIONS
-- ============================================================

local function startHeartbeat(imageButton)
	if heartbeatTweens[imageButton] then
		heartbeatTweens[imageButton]:Cancel()
	end
	if not originalSizes[imageButton] then
		originalSizes[imageButton] = imageButton.Size
	end
	imageButton.AnchorPoint = Vector2.new(0.5, 0.5)
	imageButton.Position    = UDim2.new(0.5, 0, 0.5, 0)

	local orig = originalSizes[imageButton]
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local t    = TweenService:Create(imageButton, info, {
		Size = UDim2.new(orig.X.Scale * 1.04, 0, orig.Y.Scale * 1.04, 0)
	})
	heartbeatTweens[imageButton] = t
	t:Play()
end

local function stopHeartbeat(imageButton)
	if heartbeatTweens[imageButton] then
		heartbeatTweens[imageButton]:Cancel()
		heartbeatTweens[imageButton] = nil
		if originalSizes[imageButton] then
			local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(imageButton, info, {Size = originalSizes[imageButton]}):Play()
		end
	end
end

local READY_GRADIENT = ColorSequence.new({        -- même motif que le bleu animé, en vert clair
	ColorSequenceKeypoint.new(0,    Color3.fromRGB(0, 185, 80)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(205, 255, 215)),
	ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(0, 185, 80)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(195, 255, 205)),
	ColorSequenceKeypoint.new(1,    Color3.fromRGB(0, 185, 80)),
})

local function setGradientGreen(cache, isReady)
	local g = cache.gradient
	if NEW_LOOK and (not g or not g.Parent) then
		-- le dégradé animé est créé par le script de la carte, parfois APRÈS celui-ci
		g = cache.frame:FindFirstChildOfClass("UIGradient")
		cache.gradient = g
	end
	if not g then return end
	if NEW_LOOK then
		if not originalGradients[cache.frame] then originalGradients[cache.frame] = g.Color end
		g.Color = isReady and READY_GRADIENT or originalGradients[cache.frame]
		return
	end
	if not originalGradients[cache.frame] then
		originalGradients[cache.frame] = g.Color
	end
	if isReady then
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 200, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 255, 100)),
		})
	else
		g.Color = originalGradients[cache.frame]
	end
end

local function setGradientClaimed(cache)
	local frame = cache.frame
	local existing = frame:FindFirstChildOfClass("UIGradient")
	if existing then existing:Destroy() end

	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 80, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 120, 120)),
	})
	g.Rotation = 90
	g.Parent = frame
end

local function createConfetti(imageButton)
	local screenGui = imageButton:FindFirstAncestorOfClass("ScreenGui")
	if not screenGui then return end
	local absPos  = imageButton.AbsolutePosition
	local absSize = imageButton.AbsoluteSize
	for _ = 1, 15 do
		local c = Instance.new("Frame")
		c.Size             = UDim2.new(0, math.random(5, 15), 0, math.random(5, 15))
		c.Position         = UDim2.fromOffset(absPos.X + absSize.X / 2, absPos.Y + absSize.Y / 2)
		c.AnchorPoint      = Vector2.new(0.5, 0.5)
		c.BackgroundColor3 = Color3.fromHSV(math.random(), 1, 1)
		c.BorderSizePixel  = 0
		c.Parent           = screenGui
		table.insert(activeConfetti, c)

		local angle = math.random() * math.pi * 2
		local dist  = math.random(100, 300)
		TweenService:Create(c, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(
				absPos.X + absSize.X / 2 + math.cos(angle) * dist,
				absPos.Y + absSize.Y / 2 + math.sin(angle) * dist
			),
			Rotation               = math.random(-180, 180),
			BackgroundTransparency = 1,
		}):Play()
		Debris:AddItem(c, 1.1)
		task.delay(1.1, function()
			local idx = table.find(activeConfetti, c)
			if idx then table.remove(activeConfetti, idx) end
		end)
	end
end

-- ============================================================
-- NOTIFICATION POINTS
-- ============================================================

local function showPointsNotification(points)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name           = "PlaytimeNotifGui"
	screenGui.ResetOnSpawn   = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent         = playerGui

	local frame = Instance.new("Frame")
	frame.AnchorPoint            = Vector2.new(0.5, 0.5)
	frame.Size                   = UDim2.new(0, 0, 0, 0)
	frame.Position               = UDim2.new(0.5, 0, 0.35, 0)
	frame.BackgroundColor3       = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel        = 0
	frame.Parent                 = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 15)
	corner.Parent = frame

	local border = Instance.new("UIStroke")
	border.Color     = Color3.fromRGB(85, 255, 127)
	border.Thickness = 3
	border.Parent    = frame

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, -20, 1, -20)
	label.Position               = UDim2.new(0, 10, 0, 10)
	label.BackgroundTransparency = 1
	label.Text = string.format("+%s pts", string.format("%d", points):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	label.TextColor3             = Color3.fromRGB(100, 255, 150)
	label.TextStrokeColor3       = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.5
	label.Font                   = Enum.Font.GothamBold
	label.TextSize               = 22
	label.TextWrapped            = true
	label.Parent                 = frame

	TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 420, 0, 110)
	}):Play()

	task.delay(2.5, function()
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(frame, info, {BackgroundTransparency = 1, Size = UDim2.new(0, 420, 0, 80)}):Play()
		TweenService:Create(label, info, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		TweenService:Create(border, info, {Transparency = 1}):Play()
		task.delay(0.35, function() screenGui:Destroy() end)
	end)
end

-- ============================================================
-- COUNTDOWN LABEL
-- ============================================================

local function createCountdownLabel(imageButton)
	local existing = imageButton:FindFirstChild("CountdownLabel")
	if existing then return existing end

	if NEW_LOOK then
		-- bande en fondu + texte par-dessus (sans fond)
		local band = fadeBand(bandClip(imageButton), "CountdownBand", 2)
		band.AnchorPoint = Vector2.new(0.5, 0.5)
		band.Position = UDim2.new(0.5, 0, 0.86, 0)
		band.Size = UDim2.new(1, 0, 0.26, 0)      -- largeur du bouton : ne déborde pas sur la carte
		band.Visible = false

		local label = Instance.new("TextLabel")
		label.Name                   = "CountdownLabel"
		label.Size                   = UDim2.new(0.9, 0, 0.22, 0)
		label.Position               = UDim2.new(0.5, 0, 0.86, 0)
		label.AnchorPoint            = Vector2.new(0.5, 0.5)
		label.BackgroundTransparency = 1
		label.TextColor3             = Color3.fromRGB(255, 255, 255)
		label.TextScaled             = true
		label.Font                   = Enum.Font.FredokaOne
		label.Text                   = ""
		label.Visible                = false
		label.ZIndex                 = 3
		label.Parent                 = imageButton
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = 20
		constraint.MinTextSize = 8
		constraint.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Name      = "TextStroke"
		stroke.Color     = Color3.fromRGB(0, 0, 0)
		stroke.Thickness = 1.5
		stroke.Parent    = label
		-- la bande suit la visibilité du texte (seulement pour le temps restant, voir updateUI)
		label:GetPropertyChangedSignal("Visible"):Connect(function()
			if not label.Visible then band.Visible = false end
		end)
		return label
	end

	local label = Instance.new("TextLabel")
	label.Name                   = "CountdownLabel"
	label.Size                   = UDim2.new(0.85, 0, 0.22, 0)
	label.Position               = UDim2.new(0.5, 0, 0.88, 0)
	label.AnchorPoint            = Vector2.new(0.5, 0.5)
	label.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	label.BackgroundTransparency = 0.3
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBold
	label.TextXAlignment         = Enum.TextXAlignment.Center
	label.TextYAlignment         = Enum.TextYAlignment.Center
	label.Text                   = ""
	label.Visible                = false
	label.Parent                 = imageButton

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 18
	constraint.MinTextSize = 8
	constraint.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color     = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 1
	stroke.Parent    = label

	return label
end

-- ============================================================
-- 🆕 BANDE « ALL CLAIMED » + BOUTON « CLAIM ALL »  (NEW_LOOK)
-- ============================================================

local resetBanner, resetTitle, resetTime
local function updateResetBanner(allClaimed, resetRemaining)
	if not resetBanner then
		resetBanner = fadeBand(mainFrame, "AllClaimedBanner", 20)
		resetBanner.AnchorPoint = Vector2.new(0.5, 0.5)
		resetBanner.Position = UDim2.fromScale(0.5, 0.5)
		resetBanner.Size = UDim2.fromScale(1, 0.3)
		resetBanner.Visible = false
		-- 📐 la bande reste DANS le rectangle des récompenses (l'image de fond à rayons),
		--    sans déborder sur la colonne des boutons Playtime / Daily
		local area = mainFrame.Parent and mainFrame.Parent:FindFirstChild(BANNER_AREA)
		if area and area:IsA("GuiObject") then
			local function fit()
				local ms, mp = mainFrame.AbsoluteSize, mainFrame.AbsolutePosition
				local as, ap = area.AbsoluteSize, area.AbsolutePosition
				if ms.X < 1 or ms.Y < 1 or as.X < 1 then return end
				local cx = (ap.X + as.X / 2 - mp.X) / ms.X
				resetBanner.Position = UDim2.fromScale(cx, 0.5)
				resetBanner.Size = UDim2.fromScale(as.X / ms.X, 0.3)
			end
			fit()
			for _, o in ipairs({ mainFrame, area }) do
				o:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
				o:GetPropertyChangedSignal("AbsolutePosition"):Connect(fit)
			end
		end
		local function line(name, y, h, size, color)
			local t = Instance.new("TextLabel")
			t.Name = name
			t.BackgroundTransparency = 1
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.fromScale(0.5, y)
			t.Size = UDim2.fromScale(0.8, h)
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextColor3 = color
			t.ZIndex = 21
			local c = Instance.new("UITextSizeConstraint")
			c.MaxTextSize = size
			c.Parent = t
			local st = Instance.new("UIStroke")
			st.Thickness = 1.5
			st.Parent = t
			t.Parent = resetBanner
			return t
		end
		resetTitle = line("Title", 0.33, 0.4, 34, Color3.fromRGB(255, 255, 255))
		resetTitle.Text = "All rewards claimed!"
		resetTime = line("Time", 0.72, 0.3, 24, Color3.fromRGB(255, 220, 90))
	end
	resetBanner.Visible = allClaimed
	if allClaimed then
		resetTime.Text = "New rewards in " .. formatShort(resetRemaining)
	end
end

local claimAllBtn, claimAllBusy = nil, false
local function updateClaimAll(readyCount)
	if not claimAllBtn then
		claimAllBtn = Instance.new("TextButton")
		claimAllBtn.Name = "ClaimAllButton"
		claimAllBtn.AnchorPoint = Vector2.new(0.5, 0.5)
		claimAllBtn.Position = UDim2.fromScale(0.5, 1.005)     -- à cheval sur le bas de la grille
		claimAllBtn.Size = UDim2.fromScale(0.34, 0.1)
		claimAllBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 90)
		claimAllBtn.AutoButtonColor = true
		claimAllBtn.Font = Enum.Font.FredokaOne
		claimAllBtn.TextScaled = true
		claimAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		claimAllBtn.ZIndex = 22
		claimAllBtn.Visible = false
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.3, 0)
		c.Parent = claimAllBtn
		local st = Instance.new("UIStroke")
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Thickness = 2
		st.Color = Color3.fromRGB(0, 90, 40)
		st.Parent = claimAllBtn
		local ts = Instance.new("UITextSizeConstraint")
		ts.MaxTextSize = 26
		ts.Parent = claimAllBtn
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0.15, 0), UDim.new(0.15, 0)
		pad.Parent = claimAllBtn
		claimAllBtn.Parent = mainFrame
		claimAllBtn.Activated:Connect(function()
			if claimAllBusy or not playtimeClaimEvent or not serverState then return end
			claimAllBusy = true
			local elapsed = tick() - clientReceiveTime
			for _, r in ipairs(serverState.rewards or {}) do
				local adjLeft = math.max(0, (r.minutesLeft or 0) - (elapsed / 60))
				if not r.isClaimed and not serverState.allClaimed and (r.canClaim or adjLeft <= 0) then
					playtimeClaimEvent:FireServer(r.id)
					task.wait(0.05)
				end
			end
			lastClaimSent = tick()
			task.delay(1, function() claimAllBusy = false end)
		end)
	end
	claimAllBtn.Visible = readyCount >= 2
	if readyCount >= 2 then claimAllBtn.Text = string.format("Claim all (%d)", readyCount) end
end

-- ============================================================
-- 🆕 FOND DES CARTES (NEW_LOOK + TILE_BACKGROUND)
--    Carré arrondi avec contour foncé et dégradé, derrière l'image (qui suit ses
--    animations). bleu / or = pas prête · vert = prête · grisé = récupérée
-- ============================================================
-- couleurs des fonds : { gauche, droite } (dégradé horizontal) — tes 2 modèles bleu et or
local TILE_COLORS = {
	blue  = { Color3.fromRGB(82, 136, 245),  Color3.fromRGB(82, 136, 245) },
	gold  = { Color3.fromRGB(254, 223, 49),  Color3.fromRGB(241, 180, 40) },
	green = { Color3.fromRGB(95, 225, 115),  Color3.fromRGB(40, 185, 80) },
	grey  = { Color3.fromRGB(150, 150, 150), Color3.fromRGB(115, 115, 115) },
}

-- Le fond est un CanvasGroup arrondi : les rayons qui tournent dedans ne dépassent jamais
-- du bouton (coins arrondis compris).
local function getTile(cache)
	if cache.tile and cache.tile.Parent then return cache.tile end
	local btn = cache.imageButton
	local tile = Instance.new("CanvasGroup")
	tile.Name = "TileBackground"
	tile.BorderSizePixel = 0
	tile.BackgroundTransparency = 1
	tile.ZIndex = math.max(btn.ZIndex - 1, 0)
	tile.Active = false
	-- même arrondi que la carte (le UICorner du ButtonFrame)
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
	grad.Rotation = 0
	grad.Parent = fill
	fill.Parent = tile
	-- 🌟 rayons qui tournent lentement (cartes en or seulement)
	if (TILE_STYLE[cache.config.id] or "blue") == "gold" and RAYS_IMAGE ~= "" then
		local rays = Instance.new("ImageLabel")
		rays.Name = "Rays"
		rays.BackgroundTransparency = 1
		rays.Image = RAYS_IMAGE
		rays.ImageTransparency = RAYS_TRANSPARENCY
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(0.5, 0.5)
		rays.Size = UDim2.fromScale(1.6, 1.6)      -- plus grand que la carte : les coins restent couverts en tournant
		rays.ZIndex = 2
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = 1
		a.DominantAxis = Enum.DominantAxis.Width
		a.Parent = rays
		rays.Parent = tile
		TweenService:Create(rays, TweenInfo.new(RAYS_TURN_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{ Rotation = 360 }):Play()
	end
	local function follow()
		-- même centre que le bouton, taille = bouton × TILE_SCALE
		local bs, ap = btn.Size, btn.AnchorPoint
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Position = btn.Position + UDim2.new(bs.X.Scale * (0.5 - ap.X), bs.X.Offset * (0.5 - ap.X),
			bs.Y.Scale * (0.5 - ap.Y), bs.Y.Offset * (0.5 - ap.Y))
		tile.Size = UDim2.new(bs.X.Scale * TILE_SCALE, bs.X.Offset * TILE_SCALE, bs.Y.Scale * TILE_SCALE, bs.Y.Offset * TILE_SCALE)
		-- arrondi identique EN PIXELS à celui de la carte (même si la carte est plus grande)
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
	btn:GetPropertyChangedSignal("Size"):Connect(follow)
	btn:GetPropertyChangedSignal("Position"):Connect(follow)
	btn:GetPropertyChangedSignal("AnchorPoint"):Connect(follow)
	btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
	tile.Parent = btn.Parent
	cache.tile, cache.tileGrad = tile, grad
	return tile
end

local function styleTile(cache, mode)       -- "normal" | "ready" | "claimed"
	if not (NEW_LOOK and TILE_BACKGROUND) then return end
	if cache.tileMode == mode and cache.tile and cache.tile.Parent then return end
	getTile(cache)
	local key = (mode == "ready") and "green" or (mode == "claimed") and "grey" or (TILE_STYLE[cache.config.id] or "blue")
	local c = TILE_COLORS[key] or TILE_COLORS.blue
	cache.tileGrad.Color = ColorSequence.new(c[1], c[2])
	cache.tileMode = mode
end

-- ============================================================
-- UPDATE UI
-- ============================================================

local function updateUI()
	if not serverState then
		for _, cache in pairs(buttonCache) do
			if cache.textLabel then
				cache.textLabel.Visible    = true
				cache.textLabel.Text       = "..."
				cache.textLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
			end
			if cache.frameExclamation then
				cache.frameExclamation.Visible = false
			end
		end
		return
	end
	if not next(buttonCache) then return end

	local elapsed        = tick() - clientReceiveTime
	local resetRemaining = math.max(0, (serverState.resetTimeRemaining or 0) - elapsed)
	local allClaimed     = serverState.allClaimed and resetRemaining > 0

	local rewardStates = {}
	for _, r in ipairs(serverState.rewards or {}) do
		local adjLeft  = math.max(0, (r.minutesLeft or 0) - (elapsed / 60))
		local canClaim = (not r.isClaimed) and (not allClaimed) and (r.canClaim or adjLeft <= 0)
		rewardStates[r.id] = {
			isClaimed   = r.isClaimed,
			canClaim    = canClaim,
			minutesLeft = adjLeft,
			points      = r.points,
			minutes     = r.minutes,
		}
	end

	for _, cache in pairs(buttonCache) do
		local cfg      = cache.config
		local state    = rewardStates[cfg.id]
		if not state then continue end

		local btn      = cache.imageButton
		local lbl      = cache.textLabel
		local lock     = cache.lockImage
		local check    = cache.greenCheck
		local frameExcl = cache.frameExclamation  -- ExclamationPoint3 du ButtonFrame

		local band = btn:FindFirstChild("CountdownBand", true)
		local lblStroke = lbl:FindFirstChild("TextStroke")
		if NEW_LOOK and allClaimed then
			-- tout récupéré : chaque carte = check ; le temps est dans la bande du milieu
			lbl.Visible = false
			btn.ImageColor3 = Color3.fromRGB(100, 100, 100)
			if lock      then lock.Visible      = false end
			if check     then check.Visible     = true  end
			if frameExcl then frameExcl.Visible = false end
			setGradientClaimed(cache)
			stopHeartbeat(btn)

		elseif NEW_LOOK and state.canClaim then
			lbl.Visible     = true
			lbl.Text        = "CLAIM!"
			lbl.TextColor3  = Color3.fromRGB(255, 255, 255)
			if lblStroke then lblStroke.Color = Color3.fromRGB(0, 140, 40) lblStroke.Thickness = 2 end
			if band then band.Visible = false end
			btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
			if lock      then lock.Visible      = false end
			if check     then check.Visible     = false end
			if frameExcl then frameExcl.Visible = true  end
			setGradientGreen(cache, true)
			startHeartbeat(btn)

		elseif NEW_LOOK and not state.isClaimed then
			local secsLeft = state.minutesLeft * 60
			lbl.Visible     = true
			lbl.Text        = secsLeft > 0 and formatShort(secsLeft) or "Soon"
			lbl.TextColor3  = Color3.fromRGB(255, 255, 255)
			if lblStroke then lblStroke.Color = Color3.fromRGB(0, 0, 0) lblStroke.Thickness = 1.5 end
			if band then band.Visible = true end
			btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
			if lock      then lock.Visible      = true  end
			if check     then check.Visible     = false end
			if frameExcl then frameExcl.Visible = false end
			setGradientGreen(cache, false)
			stopHeartbeat(btn)

		elseif allClaimed then
			if cfg.id == "pt_1" then
				lbl.Visible    = true
				lbl.Text       = "COOLDOWN\n" .. formatTime(resetRemaining)
				lbl.TextColor3 = Color3.fromRGB(255, 200, 50)
			else
				lbl.Visible = false
			end
			btn.ImageColor3 = Color3.fromRGB(130, 130, 130)
			if lock      then lock.Visible      = false end
			if check     then check.Visible     = true  end
			if frameExcl then frameExcl.Visible = false end  -- tout réclamé → caché
			setGradientClaimed(cache)
			stopHeartbeat(btn)

		elseif state.isClaimed then
			lbl.Visible     = false
			btn.ImageColor3 = Color3.fromRGB(100, 100, 100)
			if lock      then lock.Visible      = false end
			if check     then check.Visible     = true  end
			if frameExcl then frameExcl.Visible = false end  -- réclamé → caché
			setGradientClaimed(cache)
			stopHeartbeat(btn)

		elseif state.canClaim then
			lbl.Visible     = true
			lbl.Text        = "CLAIM"
			lbl.TextColor3  = Color3.fromRGB(100, 255, 130)
			btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
			if lock      then lock.Visible      = false end
			if check     then check.Visible     = false end
			if frameExcl then frameExcl.Visible = true  end  -- claimable → visible !
			setGradientGreen(cache, true)
			startHeartbeat(btn)

		else
			local secsLeft = state.minutesLeft * 60
			lbl.Visible     = true
			lbl.Text        = secsLeft > 0 and formatTime(secsLeft) or "Bientôt..."
			lbl.TextColor3  = Color3.fromRGB(255, 255, 255)
			btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
			if lock      then lock.Visible      = true  end
			if check     then check.Visible     = false end
			if frameExcl then frameExcl.Visible = false end  -- pas encore dispo → caché
			setGradientGreen(cache, false)
			stopHeartbeat(btn)
		end
		styleTile(cache, (allClaimed or state.isClaimed) and "claimed" or (state.canClaim and "ready") or "normal")
		setReadyFx(btn, lbl, (not allClaimed) and (not state.isClaimed) and state.canClaim)
	end

	if NEW_LOOK then
		updateResetBanner(allClaimed, resetRemaining)
	end
	if NEW_LOOK and SHOW_CLAIM_ALL then
		local n = 0
		for _, st in pairs(rewardStates) do if st.canClaim then n += 1 end end
		updateClaimAll(n)
	end

	-- Mettre à jour les icônes globales (open button + PlaytimeReward)
	updateGlobalExclamationIcons()
	updateHand()
end

-- ============================================================
-- CLIC BOUTON
-- ============================================================

local function onButtonClicked(cfg)
	if not playtimeClaimEvent then return end
	if not serverState then
		rewardToast("Loading...", "Try again in a second")
		return
	end

	local now = tick()
	if (now - lastClaimSent) < 0.1 then return end

	local rewardState = nil
	for _, r in ipairs(serverState.rewards or {}) do
		if r.id == cfg.id then rewardState = r; break end
	end
	if not rewardState then return end

	if rewardState.isClaimed or serverState.allClaimed then
		local s = SoundService:FindFirstChild("buycancel")
		if s then s:Play() end
		local el = tick() - clientReceiveTime
		local resetLeft = math.max(0, (serverState.resetTimeRemaining or 0) - el)
		if serverState.allClaimed and resetLeft > 0 then
			rewardToast("All rewards claimed!", "New rewards in " .. formatShort(resetLeft))
		else
			rewardToast("Already claimed!", "Play more to unlock the next rewards")
		end
		return
	end

	local elapsed  = tick() - clientReceiveTime
	local adjLeft  = math.max(0, (rewardState.minutesLeft or 0) - (elapsed / 60))
	local canClaim = rewardState.canClaim or adjLeft <= 0
	if not canClaim then
		local s = SoundService:FindFirstChild("buycancel")
		if s then s:Play() end
		rewardToast("Not ready yet!", "Keep playing: available in " .. formatShort(adjLeft * 60))
		return
	end

	lastClaimSent = now
	playtimeClaimEvent:FireServer(cfg.id)
end

-- ============================================================
-- INIT BOUTONS
-- ============================================================

local function initButtons()
	buttonCache       = {}
	originalSizes     = {}
	originalGradients = {}

	-- Récupérer les icônes d'exclamation globales
	local dailyToolGui = playerGui:WaitForChild("Daily tool", 5)
	if dailyToolGui then
		local openButton = dailyToolGui:FindFirstChild("open button")
		if openButton then
			exclamationPoint3 = openButton:FindFirstChild("ExclamationPoint3")
			if exclamationPoint3 then
				exclamationPoint3.Visible = false
			else
				warn("ExclamationPoint3 not found in 'open button'")
			end
		else
			warn("'open button' not found in Daily tool ScreenGui")
		end

		local dailyToolFrame = dailyToolGui:FindFirstChild("DailyTool")
		if dailyToolFrame then
			local playtimeBtn = dailyToolFrame:FindFirstChild("PlaytimeReward")
			if playtimeBtn then
				playtimeExclamation = playtimeBtn:FindFirstChild("ExclamationPoint3")
				if playtimeExclamation then
					playtimeExclamation.Visible = false
				else
					warn("ExclamationPoint3 not found in PlaytimeReward button")
				end
			else
				warn("PlaytimeReward button not found in DailyTool frame")
			end
		else
			warn("DailyTool frame not found in Daily tool ScreenGui")
		end
	else
		warn("'Daily tool' ScreenGui not found")
	end

	-- Initialiser les boutons
	for _, cfg in ipairs(REWARDS_CONFIG) do
		local frame = mainFrame:FindFirstChild(cfg.buttonName)
		if not frame then
			warn("❌ PlaytimeRewards: Frame introuvable → " .. cfg.buttonName)
			continue
		end
		local btn = frame:FindFirstChildOfClass("ImageButton")
		if not btn then
			warn("❌ PlaytimeRewards: ImageButton introuvable dans " .. cfg.buttonName)
			continue
		end

		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position    = UDim2.new(0.5, 0, 0.5, 0)
		originalSizes[btn] = btn.Size
		if NEW_LOOK and TILE_BACKGROUND then
			btn.Image = REWARD_IMAGES[cfg.id] or REWARD_IMAGES.default
			btn.BackgroundTransparency = 1
		end

		local textLabel = createCountdownLabel(btn)

		-- ExclamationPoint3 dans le ButtonFrame lui-même
		local frameExcl = frame:FindFirstChild("ExclamationPoint3")
		if frameExcl then
			frameExcl.Visible = false
		else
			warn("ExclamationPoint3 not found in " .. cfg.buttonName)
		end

		local cache = {
			frame             = frame,
			imageButton       = btn,
			textLabel         = textLabel,
			lockImage         = btn:FindFirstChild("Lock"),
			greenCheck        = frame:FindFirstChild("GreenCheck"),
			frameExclamation  = frameExcl,  -- ← ExclamationPoint3 du ButtonFrame
			gradient          = frame:FindFirstChildOfClass("UIGradient"),
			config            = cfg,
		}

		if cache.greenCheck then cache.greenCheck.Visible = false end
		buttonCache[cfg.id] = cache

		btn.Activated:Connect(function()
			onButtonClicked(cfg)
		end)
	end

	updateUI()

	task.spawn(function()
		while isRunning do
			task.wait(1)
			updateUI()
		end
	end)
end

-- ============================================================
-- DÉTECTION NOUVEAUX CLAIMS
-- ============================================================

local function checkNewClaims()
	if not serverState then return end
	local current = {}
	for _, r in ipairs(serverState.rewards or {}) do
		if r.isClaimed then current[r.id] = true end
	end

	if isFirstUpdate then
		isFirstUpdate      = false
		previousClaimedIds = current
		updateGlobalExclamationIcons()
		return
	end

	for id in pairs(current) do
		if not previousClaimedIds[id] then
			local cache = buttonCache[id]
			if cache then
				cache.imageButton.ImageColor3 = Color3.fromRGB(100, 100, 100)
				cache.textLabel.Visible       = false
				if cache.lockImage        then cache.lockImage.Visible        = false end
				if cache.greenCheck       then cache.greenCheck.Visible       = true  end
				if cache.frameExclamation then cache.frameExclamation.Visible = false end  -- caché après claim
				setGradientClaimed(cache)
				stopHeartbeat(cache.imageButton)
				styleTile(cache, "claimed")

				createConfetti(cache.imageButton)
				for _, r in ipairs(serverState.rewards or {}) do
					if r.id == id then
						--showPointsNotification(r.points)
						break
					end
				end
			end
		end
	end

	previousClaimedIds = current

	-- Mettre à jour les icônes globales après chaque vérification
	updateGlobalExclamationIcons()
end

-- ============================================================
-- NETTOYAGE
-- ============================================================

local function cleanup()
	isRunning = false

	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	for _, t in pairs(heartbeatTweens) do if t then t:Cancel() end end
	for _, c in ipairs(activeConfetti) do if c and c.Parent then c:Destroy() end end
	heartbeatTweens = {}
	buttonCache     = {}
	activeConfetti  = {}
end

Players.PlayerRemoving:Connect(function(removingPlayer)
	if removingPlayer == player then cleanup() end
end)

script.Destroying:Connect(cleanup)

-- ============================================================
-- DÉMARRAGE
-- ============================================================

task.spawn(function()

	playtimeClaimEvent   = ReplicatedStorage:WaitForChild("PlaytimeRewardClaim",   30)
	playtimeUpdateEvent  = ReplicatedStorage:WaitForChild("PlaytimeRewardUpdate",  30)
	playtimeGetDataEvent = ReplicatedStorage:WaitForChild("PlaytimeRewardGetData", 30)

	if not playtimeClaimEvent or not playtimeUpdateEvent or not playtimeGetDataEvent then
		warn("❌ PlaytimeRewards: RemoteEvents introuvables après 30s, abandon")
		return
	end

	for _, cfg in ipairs(REWARDS_CONFIG) do
		local frame = mainFrame:WaitForChild(cfg.buttonName, 15)
		if not frame then
			warn("❌ PlaytimeRewards: " .. cfg.buttonName .. " introuvable après 15s, abandon")
			return
		end
		frame:WaitForChild("ImageButton", 10)
	end

	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	previousClaimedIds = {}
	isFirstUpdate      = true

	updateConnection = playtimeUpdateEvent.OnClientEvent:Connect(function(state)
		if not state then return end
		serverState       = state
		clientReceiveTime = tick()
		updateUI()
		task.defer(checkNewClaims)
	end)

	isRunning = true
	initButtons()

	task.spawn(function()
		local retryDelays = {0, 2, 5, 10, 15, 20, 30, 45, 60}
		for _, delay in ipairs(retryDelays) do
			if delay > 0 then task.wait(delay) end
			if not isRunning then break end
			if serverState then
				break
			end
			playtimeGetDataEvent:FireServer()
		end

		if not serverState then
			warn("❌ PlaytimeRewards: Aucune réponse serveur après 60s — vérifier le ServerScript et les DataStores")
		end
	end)

end)