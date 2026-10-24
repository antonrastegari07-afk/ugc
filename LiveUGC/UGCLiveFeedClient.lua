-- UGCLiveFeedClient.lua  (LocalScript)
-- 📍 StarterPlayer > StarterPlayerScripts
-- Nécessite : ReplicatedStorage > LeaderboardCore (ModuleScript)
--             ServerScriptService > UGCLiveFeedServer (Script)
--
-- Board « LIVE UGC REDEEMS » : qui a récupéré quel UGC, avec l'image.
-- Même style que les leaderboards (Core) : VIP doré, halo du joueur local,
-- clic → fiche profil. Chaque nouveau redeem arrive en haut, en douceur.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local Core = require(ReplicatedStorage:WaitForChild("LeaderboardCore"))
local LocalPlayer = Players.LocalPlayer

--==============================================================================
-- CONFIG
--==============================================================================
local CFG = {
	boardNames   = { "UGCLiveBoard", "UGCLiveBoard2" },
	title        = "LIVE UGC REDEEMS",
	verb         = "redeemed",
	emptyText    = "No redeems yet... be the first!",
	footerText   = "Updates live  •  latest redeems",
	loadingIcon  = "✦",

	maxShown     = 20,
	entryHeight  = 84,
	resyncDelay  = 300,   -- s : relecture silencieuse (le live passe par l'event)

	-- 🪧 Titre flottant au-dessus du panneau (style « LIVE NOW! » du shop)
	billboard = {
		widthScale  = 0.85,   -- largeur = 85 % de la largeur du panneau
		heightRatio = 0.16,   -- hauteur = 16 % de la largeur
		gap         = 0.6,    -- studs entre le haut du panneau et le titre
		maxDistance = 200,
		gradient    = {       -- haut → bas
			Color3.fromRGB(255, 190, 50),
			Color3.fromRGB(255, 85, 150),
		},
		outline     = Color3.fromRGB(22, 15, 22),
	},

	palette = {
		bg          = Color3.fromRGB(16, 10, 22),
		bgA         = Color3.fromRGB(22, 12, 32),
		bgB         = Color3.fromRGB(10, 6, 16),
		panel       = Color3.fromRGB(26, 16, 38),
		footer      = Color3.fromRGB(20, 12, 30),
		entry       = Color3.fromRGB(13, 8, 20),
		entryEdge   = Color3.fromRGB(30, 16, 44),
		entryStroke = Color3.fromRGB(78, 50, 108),
		tileA       = Color3.fromRGB(250, 248, 255),   -- clair : les UGC noirs restent lisibles
		tileB       = Color3.fromRGB(222, 214, 238),
		ugcName     = Color3.fromRGB(172, 116, 251),   -- même violet que [UGC REDEEM] dans le chat
		accent1     = Color3.fromRGB(255, 95, 190),    -- rose
		accent2     = Color3.fromRGB(185, 125, 255),   -- violet
		stroke      = Color3.fromRGB(110, 70, 150),
		muted       = Color3.fromRGB(165, 145, 190),
		white       = Color3.fromRGB(255, 255, 255),
		live        = Color3.fromRGB(255, 70, 90),
	},
}

local GOLD       = Color3.fromRGB(255, 210, 60)
local GOLD_SOFT  = Color3.fromRGB(255, 236, 160)
local GOLD_DEEP  = Color3.fromRGB(190, 130, 15)
local GOLD_NAME  = Color3.fromRGB(255, 236, 175)
local SELF_BLUE  = Color3.fromRGB(120, 205, 255)
local VIP_ICON   = "rbxassetid://93460778559039"
local VIP_ICON_RATIO = 1.20
local PROFILE_ICON = "rbxassetid://78515108577271"

local P = CFG.palette

--==============================================================================
-- ANIMATEUR — réutilise la boucle unique du Core si elle est exposée
--==============================================================================
local anims, animConn = {}, nil
local function registerAnim(obj, state, fn)
	if Core.registerAnim then return Core.registerAnim(obj, state, fn) end
	table.insert(anims, { obj = obj, state = state, fn = fn })
	if animConn then return end
	animConn = RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for i = #anims, 1, -1 do
			local a = anims[i]
			if not a.obj or not a.obj.Parent then table.remove(anims, i)
			else a.fn(t, a.state, a.obj) end
		end
	end)
end

local function tween(obj, info, props)
	local tw = TweenService:Create(obj, info, props)
	tw:Play()
	return tw
end

local function toHex(c)
	return string.format("#%02X%02X%02X",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function escape(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function thumbUrl(userId)
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

--==============================================================================
-- FONDU GÉNÉRIQUE (toutes les transparences d'une entry d'un coup)
--==============================================================================
local FADE_PROPS = {
	TextLabel  = { "TextTransparency", "BackgroundTransparency" },
	ImageLabel = { "ImageTransparency", "BackgroundTransparency" },
	Frame      = { "BackgroundTransparency" },
	UIStroke   = { "Transparency" },
}

local function collectFade(root)
	local out = {}
	local function add(inst)
		if inst:GetAttribute("NoFade") then return end
		local props = FADE_PROPS[inst.ClassName]
		if props then
			for _, p in ipairs(props) do table.insert(out, { inst, p }) end
		end
	end
	add(root)
	for _, d in ipairs(root:GetDescendants()) do
		local skip, a = false, d
		while a and a ~= root do
			if a:GetAttribute("NoFade") then skip = true break end
			a = a.Parent
		end
		if not skip then add(d) end
	end
	return out
end

local function fadeIn(E, delay, info)
	local list = collectFade(E.body)
	local targets = {}
	for i, f in ipairs(list) do
		targets[i] = f[1][f[2]]
		f[1][f[2]] = 1
	end
	task.delay(delay, function()
		if not E.body.Parent then return end
		for i, f in ipairs(list) do
			if targets[i] < 1 then tween(f[1], info, { [f[2]] = targets[i] }) end
		end
	end)
end

--==============================================================================
-- ENTRY
--   Holder (layout, hauteur animée)
--     └─ Body : [barre] [avatar] Nom (+VIP)          [tuile UGC]
--                                redeemed  <UGC>
--==============================================================================
local INTRO_INFO = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local GROW_INFO  = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP_INFO   = TweenInfo.new(0.55, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local FLASH_INFO = TweenInfo.new(1.6,  Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local OUT_INFO   = TweenInfo.new(0.35, Enum.EasingStyle.Quad,  Enum.EasingDirection.In)
local HOVER_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)

local function buildEntry(parent, item)
	local H     = CFG.entryHeight
	local avS   = math.floor(H * 0.66)
	local tileS = math.floor(H * 0.80)
	local textX = 18 + avS + 14
	local rightW = tileS + 24
	local E = { item = item }

	local holder = Instance.new("Frame")
	holder.Name                   = "Redeem"
	holder.Size                   = UDim2.new(1, 0, 0, H)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel        = 0
	holder.Parent                 = parent
	E.holder = holder

	local body = Instance.new("Frame")
	body.Name             = "Body"
	body.Size             = UDim2.new(1, 0, 0, H)   -- hauteur fixe : rien ne s'écrase pendant le grow
	body.BackgroundColor3 = Color3.new(1, 1, 1)     -- le dégradé fait la couleur
	body.BorderSizePixel  = 0
	body.ZIndex           = 2
	body.Parent           = holder
	Instance.new("UICorner", body).CornerRadius = UDim.new(0, 8)
	E.body = body

	local bg = Instance.new("UIGradient")
	bg.Parent = body
	E.bg = bg

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Parent    = body
	E.stroke = stroke

	local bar = Instance.new("Frame")
	bar.Name            = "Bar"
	bar.Size            = UDim2.new(0, 4, 1, 0)
	bar.BorderSizePixel = 0
	bar.ZIndex          = 3
	bar.Parent          = body
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
	E.bar = bar

	-- avatar
	local avatar = Instance.new("ImageLabel")
	avatar.Name             = "Avatar"
	avatar.Size             = UDim2.new(0, avS, 0, avS)
	avatar.Position         = UDim2.new(0, 18, 0.5, -avS / 2)
	avatar.BackgroundColor3 = P.panel
	avatar.BorderSizePixel  = 0
	avatar.Image            = thumbUrl(item.u)
	avatar.ZIndex           = 5
	avatar.Parent           = body
	Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)

	local avStroke = Instance.new("UIStroke")
	avStroke.Thickness = 2
	avStroke.Parent    = avatar
	E.avStroke = avStroke

	local avGrad = Instance.new("UIGradient")
	avGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, GOLD_SOFT),
		ColorSequenceKeypoint.new(0.5, GOLD_DEEP),
		ColorSequenceKeypoint.new(1.0, GOLD_SOFT),
	})
	avGrad.Rotation = 45
	avGrad.Enabled  = false
	avGrad.Parent   = avStroke
	E.avGrad = avGrad

	-- nom
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name                   = "PlayerName"
	nameLbl.Position               = UDim2.new(0, textX, 0.10, 0)
	nameLbl.Size                   = UDim2.new(1, -(textX + rightW + 12), 0.42, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text                   = item.n or ("Player_" .. item.u)
	nameLbl.TextScaled             = true
	nameLbl.Font                   = Enum.Font.FredokaOne
	nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
	nameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
	nameLbl.ZIndex                 = 5
	nameLbl.Parent                 = body
	local nc = Instance.new("UITextSizeConstraint", nameLbl)
	nc.MaxTextSize = math.floor(H * 0.30); nc.MinTextSize = 8
	E.nameLbl = nameLbl
	E.nameFullW = nameLbl.Size

	-- icône VIP, collée après le nom (largeur réelle du texte)
	local iconH = math.floor(H * 0.34)
	local vipIcon = Instance.new("ImageLabel")
	vipIcon.Name                   = "VipIcon"
	vipIcon.AnchorPoint            = Vector2.new(0, 0.5)
	vipIcon.Size                   = UDim2.new(0, math.floor(iconH * VIP_ICON_RATIO), 0, iconH)
	vipIcon.BackgroundTransparency = 1
	vipIcon.Image                  = VIP_ICON
	vipIcon.ScaleType              = Enum.ScaleType.Fit
	vipIcon.Visible                = false
	vipIcon.ZIndex                 = 6
	vipIcon.Parent                 = body
	E.vipIcon = vipIcon
	E.nameVipW = UDim2.new(1, -(textX + rightW + 20 + vipIcon.Size.X.Offset), 0.42, 0)

	-- « redeemed <UGC> »
	local ugcLbl = Instance.new("TextLabel")
	ugcLbl.Name                   = "UGC"
	ugcLbl.Position               = UDim2.new(0, textX, 0.56, 0)
	ugcLbl.Size                   = UDim2.new(1, -(textX + rightW + 12), 0.32, 0)
	ugcLbl.BackgroundTransparency = 1
	ugcLbl.RichText               = true
	ugcLbl.Text                   = string.format('<font color="%s">%s</font>  <font color="%s">%s</font>',
		toHex(P.muted), CFG.verb, toHex(P.ugcName), escape(item.an or "UGC"))
	ugcLbl.TextColor3             = P.white
	ugcLbl.TextScaled             = true
	ugcLbl.Font                   = Enum.Font.FredokaOne
	ugcLbl.TextXAlignment         = Enum.TextXAlignment.Left
	ugcLbl.TextTruncate           = Enum.TextTruncate.AtEnd
	ugcLbl.ZIndex                 = 5
	ugcLbl.Parent                 = body
	local uc = Instance.new("UITextSizeConstraint", ugcLbl)
	uc.MaxTextSize = math.floor(H * 0.24); uc.MinTextSize = 7

	-- tuile UGC
	local tile = Instance.new("Frame")
	tile.Name             = "UGCTile"
	tile.AnchorPoint      = Vector2.new(1, 0.5)
	tile.Size             = UDim2.new(0, tileS, 0, tileS)
	tile.Position         = UDim2.new(1, -12, 0.5, 0)
	tile.BackgroundColor3 = Color3.new(1, 1, 1)
	tile.BorderSizePixel  = 0
	tile.ZIndex           = 5
	tile.Parent           = body
	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 10)
	local tGrad = Instance.new("UIGradient")
	tGrad.Color    = ColorSequence.new(P.tileA, P.tileB)
	tGrad.Rotation = 90
	tGrad.Parent   = tile
	local tStroke = Instance.new("UIStroke")
	tStroke.Color        = P.accent2
	tStroke.Thickness    = 1.5
	tStroke.Transparency = 0.45
	tStroke.Parent       = tile
	local tScale = Instance.new("UIScale")
	tScale.Parent = tile
	E.tileScale = tScale

	local ugcImg = Instance.new("ImageLabel")
	ugcImg.Name                   = "Image"
	ugcImg.AnchorPoint            = Vector2.new(0.5, 0.5)
	ugcImg.Position               = UDim2.fromScale(0.5, 0.5)
	ugcImg.Size                   = UDim2.fromScale(0.88, 0.88)
	ugcImg.BackgroundTransparency = 1
	ugcImg.Image                  = item.img or ""
	ugcImg.ScaleType              = Enum.ScaleType.Fit
	ugcImg.ZIndex                 = 6
	ugcImg.Parent                 = tile

	-- flash d'arrivée (nouveau redeem)
	local flash = Instance.new("Frame")
	flash.Name                   = "Flash"
	flash.Size                   = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3       = P.accent1
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel        = 0
	flash.ZIndex                 = 4
	flash:SetAttribute("NoFade", true)
	flash.Parent                 = body
	Instance.new("UICorner", flash).CornerRadius = UDim.new(0, 8)
	local fGrad = Instance.new("UIGradient")
	fGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 0),
		NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1.0, 1),
	})
	fGrad.Parent = flash
	E.flash = flash

	------------------------------------------------------------------
	-- 🖱️ survol + clic → fiche profil (comme les autres boards)
	------------------------------------------------------------------
	local hintH = math.floor(H * 0.26)
	local hint = Instance.new("Frame")
	hint.Name                   = "ProfileHint"
	hint.AnchorPoint            = Vector2.new(0, 0.5)
	hint.AutomaticSize          = Enum.AutomaticSize.X
	hint.Size                   = UDim2.new(0, 0, 0, hintH)
	hint.BackgroundColor3       = Color3.fromRGB(22, 30, 44)
	hint.BackgroundTransparency = 1
	hint.BorderSizePixel        = 0
	hint.Visible                = false
	hint.ZIndex                 = 16
	hint:SetAttribute("NoFade", true)
	hint.Parent                 = body
	Instance.new("UICorner", hint).CornerRadius = UDim.new(1, 0)
	local hStroke = Instance.new("UIStroke")
	hStroke.Color        = SELF_BLUE
	hStroke.Transparency = 1
	hStroke.Parent       = hint
	local hPad = Instance.new("UIPadding")
	hPad.PaddingLeft  = UDim.new(0, math.floor(hintH * 0.35))
	hPad.PaddingRight = UDim.new(0, math.floor(hintH * 0.45))
	hPad.Parent       = hint
	local hList = Instance.new("UIListLayout")
	hList.FillDirection     = Enum.FillDirection.Horizontal
	hList.VerticalAlignment = Enum.VerticalAlignment.Center
	hList.SortOrder         = Enum.SortOrder.LayoutOrder
	hList.Padding           = UDim.new(0, math.floor(hintH * 0.2))
	hList.Parent            = hint
	local hIcon = Instance.new("ImageLabel")
	hIcon.LayoutOrder            = 1
	hIcon.Size                   = UDim2.new(0, math.floor(hintH * 0.8), 0, math.floor(hintH * 0.8))
	hIcon.BackgroundTransparency = 1
	hIcon.Image                  = PROFILE_ICON
	hIcon.ScaleType              = Enum.ScaleType.Fit
	hIcon.ImageTransparency      = 1
	hIcon.ZIndex                 = 17
	hIcon.Parent                 = hint
	local hText = Instance.new("TextLabel")
	hText.LayoutOrder            = 2
	hText.AutomaticSize          = Enum.AutomaticSize.X
	hText.Size                   = UDim2.new(0, 0, 1, 0)
	hText.BackgroundTransparency = 1
	hText.Text                   = "View Profile"
	hText.Font                   = Enum.Font.FredokaOne
	hText.TextSize               = math.floor(hintH * 0.62)
	hText.TextColor3             = Color3.new(1, 1, 1)
	hText.TextTransparency       = 1
	hText.ZIndex                 = 17
	hText.Parent                 = hint

	local hit = Instance.new("TextButton")
	hit.Name                   = "Hit"
	hit.Size                   = UDim2.new(1, 0, 1, 0)
	hit.BackgroundTransparency = 1
	hit.Text                   = ""
	hit.AutoButtonColor        = false
	hit.Selectable             = false
	hit.ZIndex                 = 30
	hit:SetAttribute("NoFade", true)
	hit.Parent                 = body

	-- icône VIP puis « View Profile » placés juste après le nom
	local function placeAfterName()
		local x = nameLbl.AbsolutePosition.X - body.AbsolutePosition.X + nameLbl.TextBounds.X
		local y = nameLbl.AbsolutePosition.Y - body.AbsolutePosition.Y + nameLbl.AbsoluteSize.Y / 2
		local gap = math.floor(H * 0.08)
		if vipIcon.Visible then
			vipIcon.Position = UDim2.fromOffset(x + gap, y)
			x = x + gap + vipIcon.AbsoluteSize.X
		end
		local maxX = body.AbsoluteSize.X - rightW - hint.AbsoluteSize.X
		hint.Position = UDim2.fromOffset(math.max(0, math.min(x + gap, maxX)), y)
	end
	E.placeAfterName = placeAfterName
	nameLbl:GetPropertyChangedSignal("TextBounds"):Connect(placeAfterName)
	nameLbl:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeAfterName)

	function E.setHover(on)
		if E.hovered == on then return end
		E.hovered = on
		if on then hint.Visible = true; placeAfterName() end
		local tr = on and 0 or 1
		tween(hint,    HOVER_INFO, { BackgroundTransparency = on and 0.15 or 1 })
		tween(hStroke, HOVER_INFO, { Transparency = on and 0.35 or 1 })
		tween(hIcon,   HOVER_INFO, { ImageTransparency = tr })
		tween(tStroke, HOVER_INFO, { Transparency = on and 0.1 or 0.45 })
		local tw = tween(hText, HOVER_INFO, { TextTransparency = tr })
		if not on then
			tw.Completed:Connect(function()
				if not E.hovered then hint.Visible = false end
			end)
		end
	end
	hit.MouseEnter:Connect(function() E.setHover(true) end)
	hit.MouseLeave:Connect(function() E.setHover(false) end)
	hit.Activated:Connect(function()
		Core.openProfile(item.u, { name = item.n })
	end)

	return E
end

-- Style VIP / joueur local (réappliqué si la liste VIP change)
local function applyStyle(E)
	local uid    = E.item.u
	local isVip  = Core.isVip(uid)
	local isSelf = LocalPlayer and uid == LocalPlayer.UserId
	if E.styled == (isVip and "vip" or isSelf and "self" or "base") then return end
	E.styled = isVip and "vip" or isSelf and "self" or "base"

	if isVip then
		E.bg.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(12, 9, 3)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(24, 18, 5)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(78, 57, 12)),
		})
		E.stroke.Color, E.stroke.Thickness, E.stroke.Transparency = GOLD, 2.5, 0
		E.bar.BackgroundColor3 = GOLD
		E.nameLbl.TextColor3   = GOLD_NAME
		E.nameLbl.Size         = E.nameVipW
		E.avStroke.Color, E.avStroke.Thickness, E.avStroke.Transparency = Color3.new(1, 1, 1), 3, 0
		E.avGrad.Enabled       = true
	else
		E.bg.Color = ColorSequence.new(P.entry, P.entryEdge)
		E.stroke.Color        = isSelf and SELF_BLUE or P.entryStroke
		E.stroke.Thickness    = isSelf and 2 or 1
		E.stroke.Transparency = isSelf and 0.1 or 0.5
		E.bar.BackgroundColor3 = isSelf and SELF_BLUE or P.accent1
		E.nameLbl.TextColor3   = P.white
		E.nameLbl.Size         = E.nameFullW
		E.avStroke.Color, E.avStroke.Thickness, E.avStroke.Transparency = P.accent2, 2, 0.3
		E.avGrad.Enabled       = false
	end
	E.vipIcon.Visible = isVip
	task.defer(E.placeAfterName)
end

-- 1re apparition : cascade, comme les leaderboards
local function playIntro(E, index)
	E.body.Position = UDim2.new(-0.07, 0, 0, 0)
	local d = math.min((index - 1) * 0.035, 1.2)
	fadeIn(E, d, INTRO_INFO)
	task.delay(d, function()
		if E.body.Parent then tween(E.body, INTRO_INFO, { Position = UDim2.new(0, 0, 0, 0) }) end
	end)
end

-- ✨ Nouveau redeem : la place s'ouvre, l'entry glisse, l'UGC « pop », flash doux
local function playNew(E)
	local H = CFG.entryHeight
	E.holder.ClipsDescendants = true
	E.holder.Size   = UDim2.new(1, 0, 0, 0)
	E.body.Position = UDim2.new(-0.05, 0, 0, 0)
	E.tileScale.Scale = 0.4
	tween(E.holder, GROW_INFO, { Size = UDim2.new(1, 0, 0, H) })
	fadeIn(E, 0.12, INTRO_INFO)
	task.delay(0.12, function()
		if not E.body.Parent then return end
		tween(E.body, INTRO_INFO, { Position = UDim2.new(0, 0, 0, 0) })
		tween(E.tileScale, POP_INFO, { Scale = 1 })
		E.flash.BackgroundTransparency = 0.55
		tween(E.flash, FLASH_INFO, { BackgroundTransparency = 1 })
	end)
	task.delay(0.6, function()
		if E.holder.Parent then E.holder.ClipsDescendants = false end
	end)
end

local function removeEntry(E, animate)
	if not animate then E.holder:Destroy() return end
	E.holder.LayoutOrder = 1e6         -- reste en bas pendant qu'il s'efface
	E.holder.ClipsDescendants = true
	for _, f in ipairs(collectFade(E.body)) do
		tween(f[1], OUT_INFO, { [f[2]] = 1 })
	end
	tween(E.holder, OUT_INFO, { Size = UDim2.new(1, 0, 0, 0) }).Completed:Connect(function()
		E.holder:Destroy()
	end)
end

--==============================================================================
-- VUE (une par board) — entries identifiées par l'id du redeem
--==============================================================================
local View = {}
View.__index = View

function View.new(scroll, msgLbl)
	return setmetatable({ scroll = scroll, msg = msgLbl, byId = {}, loaded = false }, View)
end

function View:sync(list)
	if not self.scroll.Parent then return end
	local keep, firstLoad = {}, not self.loaded
	local n = math.min(#list, CFG.maxShown)
	for i = 1, n do
		local item = list[i]
		keep[item.id] = true
		local E = self.byId[item.id]
		if not E then
			E = buildEntry(self.scroll, item)
			self.byId[item.id] = E
			E.holder.LayoutOrder = i
			applyStyle(E)
			if firstLoad then playIntro(E, i) else playNew(E) end
		end
		E.holder.LayoutOrder = i
	end
	for id, E in pairs(self.byId) do
		if not keep[id] then
			self.byId[id] = nil
			removeEntry(E, not firstLoad)
		end
	end
	self.loaded = true
	self.msg.Visible = (n == 0)
end

function View:restyle()
	for _, E in pairs(self.byId) do applyStyle(E) end
end

function View:destroy()
	for id, E in pairs(self.byId) do E.holder:Destroy(); self.byId[id] = nil end
end

--==============================================================================
-- 🪧 TITRE FLOTTANT (BillboardGui au-dessus du panneau)
--   ● LIVE UGC REDEEMS — texte épais, dégradé vertical, contour sombre.
--   Taille en studs : il grossit / rapetisse avec la distance, comme un objet.
--==============================================================================
local function buildBillboard(part, src)
	local B = CFG.billboard
	local sideways = (src.Face == Enum.NormalId.Left or src.Face == Enum.NormalId.Right)
	local w = (sideways and part.Size.Z or part.Size.X) * B.widthScale
	local h = w * B.heightRatio

	local bb = Instance.new("BillboardGui")
	bb.Name                  = "LiveTitle_" .. part.Name
	bb.Adornee               = part
	bb.Size                  = UDim2.new(w, 0, h, 0)
	bb.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + h / 2 + B.gap, 0)
	bb.LightInfluence        = 0
	bb.MaxDistance           = B.maxDistance
	bb.ResetOnSpawn          = false
	bb.ZIndexBehavior        = Enum.ZIndexBehavior.Sibling
	bb.Parent                = LocalPlayer:WaitForChild("PlayerGui")

	local title = Instance.new("TextLabel")
	title.AnchorPoint            = Vector2.new(0.5, 0.5)
	title.Position               = UDim2.fromScale(0.5, 0.5)
	title.Size                   = UDim2.fromScale(0.88, 1)
	title.BackgroundTransparency = 1
	title.Text                   = CFG.title
	title.TextColor3             = Color3.new(1, 1, 1)   -- le dégradé fait la couleur
	title.TextScaled             = true
	title.Font                   = Enum.Font.FredokaOne
	title.ZIndex                 = 2
	title.Parent                 = bb
	local tGrad = Instance.new("UIGradient")
	tGrad.Color    = ColorSequence.new(B.gradient[1], B.gradient[2])
	tGrad.Rotation = 90
	tGrad.Parent   = title
	local tStroke = Instance.new("UIStroke")
	tStroke.Color         = B.outline
	tStroke.LineJoinMode  = Enum.LineJoinMode.Round
	tStroke.Parent        = title

	-- ● point rouge juste à gauche de « LIVE »
	local dotHolder = Instance.new("Frame")
	dotHolder.AnchorPoint            = Vector2.new(0.5, 0.5)
	dotHolder.Size                   = UDim2.fromScale(0.36, 0.36)
	dotHolder.SizeConstraint         = Enum.SizeConstraint.RelativeYY
	dotHolder.BackgroundTransparency = 1
	dotHolder.ZIndex                 = 2
	dotHolder.Parent                 = bb

	local ring = Instance.new("Frame")
	ring.AnchorPoint            = Vector2.new(0.5, 0.5)
	ring.Position               = UDim2.fromScale(0.5, 0.5)
	ring.Size                   = UDim2.fromScale(1, 1)
	ring.BackgroundColor3       = P.live
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel        = 0
	ring.ZIndex                 = 2
	ring.Parent                 = dotHolder
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)

	local dot = Instance.new("Frame")
	dot.AnchorPoint      = Vector2.new(0.5, 0.5)
	dot.Position         = UDim2.fromScale(0.5, 0.5)
	dot.Size             = UDim2.fromScale(1, 1)
	dot.BackgroundColor3 = P.live
	dot.BorderSizePixel  = 0
	dot.ZIndex           = 3
	dot.Parent           = dotHolder
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	local dStroke = Instance.new("UIStroke")
	dStroke.Color  = B.outline
	dStroke.Parent = dot
	registerAnim(dot, {}, function(t, _, d)
		d.BackgroundTransparency = 0.35 * (0.5 + 0.5 * math.sin(t * 3))
	end)

	-- Le groupe « ● + texte » reste centré ; le contour suit la distance.
	local function layout()
		local H  = bb.AbsoluteSize.Y
		local d  = dotHolder.AbsoluteSize.X
		local gap = d * 0.5
		local th = math.clamp(H * 0.07, 1, 8)
		tStroke.Thickness = th
		dStroke.Thickness = math.max(1, th * 0.7)
		title.Position = UDim2.new(0.5, (d + gap) / 2, 0.5, 0)
		local textLeft = bb.AbsoluteSize.X / 2 + (d + gap) / 2 - title.TextBounds.X / 2
		dotHolder.Position = UDim2.new(0, textLeft - gap - d / 2, 0.5, 0)
	end
	bb:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	title:GetPropertyChangedSignal("TextBounds"):Connect(layout)
	task.defer(layout)

	-- onde autour du point rouge à chaque nouveau redeem
	local PING_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function ping()
		ring.Size = UDim2.fromScale(1, 1)
		ring.BackgroundTransparency = 0.2
		tween(ring, PING_INFO, { Size = UDim2.fromScale(2.8, 2.8), BackgroundTransparency = 1 })
	end

	return bb, ping
end

--==============================================================================
-- UI D'UN BOARD (même squelette que LeaderboardCore, sans header :
-- le titre est un BillboardGui qui flotte au-dessus du panneau)
--==============================================================================
local function buildBoardUI(sg)
	for _, c in ipairs(sg:GetChildren()) do c:Destroy() end

	local main = Instance.new("Frame")
	main.Name             = "MainFrame"
	main.Size             = UDim2.new(1, 0, 1, 0)
	main.BackgroundColor3 = P.bg
	main.BorderSizePixel  = 0
	main.Parent           = sg
	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color    = ColorSequence.new(P.bgA, P.bgB)
	bgGrad.Rotation = 135
	bgGrad.Parent   = main


	local content = Instance.new("Frame")
	content.Name             = "ContentFrame"
	content.Size             = UDim2.new(0.96, 0, 0.895, 0)
	content.Position         = UDim2.new(0.02, 0, 0.03, 0)
	content.BackgroundColor3 = P.panel
	content.BorderSizePixel  = 0
	content.ClipsDescendants = true
	content.Parent           = main
	Instance.new("UICorner", content).CornerRadius = UDim.new(0, 12)
	local cStroke = Instance.new("UIStroke")
	cStroke.Color        = P.stroke
	cStroke.Thickness    = 1
	cStroke.Transparency = 0.5
	cStroke.Parent       = content

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                   = "ScrollingFrame"
	scroll.Size                   = UDim2.new(0.97, 0, 0.97, 0)
	scroll.Position               = UDim2.new(0.015, 0, 0.015, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel        = 0
	scroll.ScrollBarThickness     = 5
	scroll.ScrollBarImageColor3   = P.accent2
	scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	scroll.Parent                 = content
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding   = UDim.new(0, 8)
	list.Parent    = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft   = UDim.new(0, 16)
	pad.PaddingRight  = UDim.new(0, 16)
	pad.Parent        = scroll

	local msg = Instance.new("TextLabel")
	msg.Name                   = "Message"
	msg.Size                   = UDim2.new(1, 0, 0, 50)
	msg.BackgroundTransparency = 1
	msg.Text                   = CFG.emptyText
	msg.TextColor3             = P.muted
	msg.TextScaled             = true
	msg.Font                   = Enum.Font.Gotham
	msg.LayoutOrder            = 1e7
	msg.Visible                = false
	msg.Parent                 = scroll
	local mc = Instance.new("UITextSizeConstraint", msg)
	mc.MaxTextSize = 20; mc.MinTextSize = 10

	local footer = Instance.new("Frame")
	footer.Name             = "Footer"
	footer.Size             = UDim2.new(0.96, 0, 0.047, 0)
	footer.Position         = UDim2.new(0.02, 0, 0.943, 0)
	footer.BackgroundColor3 = P.footer
	footer.BorderSizePixel  = 0
	footer.Parent           = main
	Instance.new("UICorner", footer).CornerRadius = UDim.new(0, 8)
	local fStroke = Instance.new("UIStroke")
	fStroke.Color        = P.stroke
	fStroke.Thickness    = 1
	fStroke.Transparency = 0.5
	fStroke.Parent       = footer
	local fLbl = Instance.new("TextLabel")
	fLbl.Size                   = UDim2.new(1, 0, 1, 0)
	fLbl.BackgroundTransparency = 1
	fLbl.Text                   = CFG.footerText
	fLbl.TextColor3             = P.muted
	fLbl.TextScaled             = true
	fLbl.Font                   = Enum.Font.Gotham
	fLbl.Parent                 = footer
	local flc = Instance.new("UITextSizeConstraint", fLbl)
	flc.MaxTextSize = 16; flc.MinTextSize = 8

	return { content = content, scroll = scroll, msg = msg }
end

--==============================================================================
-- DONNÉES
--==============================================================================
local boards = {}
local feed, loaded = {}, false

local getFn  = ReplicatedStorage:WaitForChild("GetUGCLiveFeed", 30)
local newEvt = ReplicatedStorage:WaitForChild("UGCLiveFeedNew", 30)

local function validItem(e)
	return typeof(e) == "table" and type(e.id) == "string" and tonumber(e.u) ~= nil
end

local function pushToBoards(isNew)
	for _, b in ipairs(boards) do
		if b.loader then b.loader:Destroy(); b.loader = nil end
		b.view:sync(feed)
		if isNew then b.ping() end
	end
end

local function fetch()
	if not getFn then return false end
	local ok, res = pcall(function() return getFn:InvokeServer() end)
	if not ok or typeof(res) ~= "table" then return false end
	local clean = {}
	for _, e in ipairs(res) do
		if validItem(e) then table.insert(clean, e) end
	end
	feed, loaded = clean, true
	pushToBoards(false)
	return true
end

if newEvt then
	newEvt.OnClientEvent:Connect(function(msg)
		if typeof(msg) ~= "table" then return end
		if typeof(msg.full) == "table" then
			local clean = {}
			for _, e in ipairs(msg.full) do
				if validItem(e) then table.insert(clean, e) end
			end
			feed, loaded = clean, true
			pushToBoards(false)
			return
		end
		if not validItem(msg) then return end
		for _, e in ipairs(feed) do
			if e.id == msg.id then return end
		end
		table.insert(feed, 1, msg)
		while #feed > CFG.maxShown do table.remove(feed) end
		loaded = true
		pushToBoards(true)
	end)
end

--==============================================================================
-- BOARDS (même détection que LeaderboardCore : SurfaceGui recopiée dans le
-- PlayerGui avec Adornee → survol et clic fonctionnent)
--==============================================================================
local nameSet = {}
for _, n in ipairs(CFG.boardNames) do nameSet[n] = true end

local function initBoard(part)
	local src = part:FindFirstChildOfClass("SurfaceGui")
	if not src then return end
	for _, b in ipairs(boards) do
		if b.part == part then return end
	end

	local sg = Instance.new("SurfaceGui")
	sg.Name             = "LB_" .. part.Name
	sg.Face             = src.Face
	sg.SizingMode       = src.SizingMode
	sg.PixelsPerStud    = src.PixelsPerStud
	sg.AlwaysOnTop      = src.AlwaysOnTop
	sg.ZOffset          = src.ZOffset
	sg.MaxDistance      = src.MaxDistance
	sg.ClipsDescendants = src.ClipsDescendants
	sg.ResetOnSpawn     = false
	sg.Adornee          = part
	sg.CanvasSize       = Vector2.new(1920, 1080)
	sg.LightInfluence   = 0
	sg.Brightness       = 1
	sg.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
	sg.Parent           = LocalPlayer:WaitForChild("PlayerGui")
	src.Enabled         = false

	local ui = buildBoardUI(sg)
	local billboard, ping = buildBillboard(part, src)
	local b = {
		part = part, src = src, surfaceGui = sg,
		scroll = ui.scroll, ping = ping, billboard = billboard,
		view = View.new(ui.scroll, ui.msg),
	}
	table.insert(boards, b)

	if loaded then
		b.view:sync(feed)
	else
		b.loader = Core.createLoader(ui.content, CFG)
	end
end

local function isBoard(d)
	return d:IsA("BasePart") and nameSet[d.Name] == true
end

task.spawn(function()
	task.wait(2)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if isBoard(d) then initBoard(d) end
	end
	for attempt = 1, 5 do
		if fetch() then break end
		task.wait(2 * attempt)
	end
	if not loaded then
		loaded = true
		pushToBoards(false)   -- affiche « No redeems yet » au lieu d'un loader infini
	end
end)

Workspace.DescendantAdded:Connect(function(d)
	if isBoard(d) then
		task.wait(0.3)
		initBoard(d)
	end
end)

-- entretien : boards détruits, VIP qui changent, resync lent
task.spawn(function()
	local lastSync = os.clock()
	while true do
		task.wait(5)
		for i = #boards, 1, -1 do
			local b = boards[i]
			if not (b.surfaceGui.Parent and b.scroll.Parent and b.part:IsDescendantOf(Workspace)) then
				b.view:destroy()
				b.surfaceGui:Destroy()
				b.billboard:Destroy()
				if b.src and b.src.Parent then b.src.Enabled = true end
				table.remove(boards, i)
			else
				b.view:restyle()
			end
		end
		if #boards > 0 and os.clock() - lastSync >= CFG.resyncDelay then
			lastSync = os.clock()
			task.spawn(fetch)
		end
	end
end)
