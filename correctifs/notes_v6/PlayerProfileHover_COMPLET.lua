--[[
	PlayerProfileHover  (LocalScript)  — v2
	Emplacement : StarterPlayer > StarterPlayerScripts

	- Survol d'un joueur (PC)  → contour blanc + petit billboard "Player Profile" au centre du perso
	- Clic sur le joueur OU sur le billboard → fiche profil (même style que PartyPadUI)
	- Mobile : 1er tap = sélection (contour + billboard), 2e tap / tap sur le billboard = ouvre la fiche
	- Désactivé quand tu tiens un Tool (sinon chaque tir ouvrirait une fiche)

	🆕 v2
	- Tes icônes de leaderboard (+ leurs couleurs) à la place des emojis
	- Badges : VIP + boosts gamepass (x2 / x5 / x10) possédés par le joueur
	- Nouvelles infos : Points/sec, Kills Today, Stage, Points Gifted (+ rang Top Gifters),
	  Robux Donated (+ rang Top Donors, via ton serveur TopDonators existant)

	🔒 Que des infos PUBLIQUES (ce qu'un joueur voit déjà sur les leaderboards / la leaderstats).
	   Jamais : warnings, bans, anticheat, Robux dépensés, etc.
	   Lecture seule : attributs répliqués + remotes DÉJÀ existants
	   (GetTopGifters, GetLeaderboardData / UpdateLeaderboard). Aucun script serveur à ajouter.
]]

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- ⚙️ Réglages
---------------------------------------------------------------------
local ICON_ID  = "rbxassetid://78515108577271"  -- icône du billboard "Player Profile"
local MAX_DIST = 120                            -- portée du rayon souris (studs)
local PROFILE_RANGE = 25                        -- 👈 distance max entre les 2 persos pour voir un profil (studs)
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

-- 🎨 Tes icônes + couleurs de leaderboard
local LB = {
	points    = { icon = "rbxassetid://97693677869695",  base = Color3.fromRGB(241, 216, 66),  grad = Color3.fromRGB(247, 246, 147), stroke = Color3.fromRGB(18, 40, 80) },
	kills     = { icon = "rbxassetid://75683389639373",  base = Color3.fromRGB(83, 133, 228),  grad = Color3.fromRGB(141, 222, 243), stroke = Color3.fromRGB(90, 20, 20) },
	rebirths  = { icon = "rbxassetid://90150030286895",  base = Color3.fromRGB(148, 193, 220), grad = Color3.fromRGB(101, 193, 220), stroke = Color3.fromRGB(70, 20, 80) },
	donations = { icon = "rbxassetid://130511639534455", base = Color3.fromRGB(126, 211, 136), grad = Color3.fromRGB(204, 238, 195), stroke = Color3.fromRGB(15, 70, 35) },
	gifters   = { icon = "rbxassetid://89484685021021",  base = Color3.fromRGB(220, 173, 211), grad = Color3.fromRGB(255, 173, 214), stroke = Color3.fromRGB(80, 20, 60) },
	streak    = { icon = "rbxassetid://86471920262687",  base = Color3.fromRGB(255, 160, 30),  grad = Color3.fromRGB(255, 210, 90),  stroke = Color3.fromRGB(90, 50, 0) },
	-- Pas d'icône fournie → emoji sur une pastille neutre (mets un rbxassetid ici si tu en as une)
	neutral   = { icon = nil, base = Color3.fromRGB(60, 70, 90), grad = Color3.fromRGB(96, 110, 138), stroke = Color3.fromRGB(18, 22, 32) },
}
local BADGE_ICON = {
	vip     = "rbxassetid://126388892716858",
	boost2  = "rbxassetid://77796745547590",
	boost5  = "rbxassetid://76885721001015",
	boost10 = "rbxassetid://111717758049355",
	boost25 = "rbxassetid://123961835925963",
}
-- Gamepass (mêmes IDs que ton script serveur principal → gamePassMultipliers)
local PASS = {
	{ id = 1891007119, badge = "boost2",  label = "x2" },
	{ id = 1893682680, badge = "boost5",  label = "x5" },
	{ id = 1891475116, badge = "boost10", label = "x10" },
}
local VIP_PASS_ID = 1891589121

-- 🚫 Profil désactivé en PVP : attribut "InArena" posé par ton serveur d'arène
local function inArena(p) return p:GetAttribute("InArena") == true end

-- Distance entre mon perso et le sien
local function distanceTo(p)
	local a = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local b = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not a or not b then return math.huge end
	return (a.Position - b.Position).Magnitude
end

-- Le profil de p peut-il être vu MAINTENANT ?
local function canView(p)
	if not p or not p.Parent or p == player then return false end
	if inArena(player) or inArena(p) then return false end
	return distanceTo(p) <= PROFILE_RANGE
end

---------------------------------------------------------------------
-- Style (repris de PartyPadUI)
---------------------------------------------------------------------
local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
local F = {
	Heavy  = Font.new(FAMILY, Enum.FontWeight.ExtraBold),
	Bold   = Font.new(FAMILY, Enum.FontWeight.Bold),
	Medium = Font.new(FAMILY, Enum.FontWeight.Medium),
}
local C = {
	Glass      = Color3.fromRGB(12, 15, 22),
	GlassAlpha = 0.22,
	White      = Color3.fromRGB(255, 255, 255),
	Sub        = Color3.fromRGB(150, 162, 182),
	Accent     = Color3.fromRGB(88, 208, 255),
	AccentDeep = Color3.fromRGB(40, 130, 220),
	Tile       = Color3.fromRGB(30, 36, 50),
	Gold       = Color3.fromRGB(255, 205, 70),
	Red        = Color3.fromRGB(222, 64, 64),
	RedBase    = Color3.fromRGB(124, 28, 32),
}

local QUICK   = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SOFT    = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local BACK    = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POP     = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS   = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function tween(o, info, props)
	local t = TweenService:Create(o, info, props)
	t:Play()
	return t
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end

local function corner(p, r) return new("UICorner", { CornerRadius = r or UDim.new(0, 12) }, p) end

local function stroke(p, color, transp, thick)
	return new("UIStroke", {
		Color = color, Transparency = transp, Thickness = thick or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, p)
end

local function text(parent, str, font, color, maxSize, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, FontFace = font, Text = str,
		TextColor3 = color, TextScaled = true,
	}, parent)
	new("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8 }, l)
	for k, v in props or {} do l[k] = v end
	return l
end

-- Bouton 3D identique à PartyPadUI
local function button3D(parent, props, color, baseColor, content, maxText, depth)
	depth = depth or 6
	local pressDepth = math.max(2, math.floor(depth * 0.65 + 0.5))
	local b = new("TextButton", {
		AutoButtonColor = false, Text = "", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, parent)
	for k, v in props do b[k] = v end

	local shadow = new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.65, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -depth), Position = UDim2.fromOffset(0, depth + 3),
	}, b)
	corner(shadow)
	local base = new("Frame", {
		BackgroundColor3 = baseColor, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -depth), Position = UDim2.fromOffset(0, depth),
	}, b)
	corner(base)
	local face = new("Frame", {
		Name = "Face", BackgroundColor3 = color, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -depth),
	}, b)
	corner(face)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
	}, face)
	stroke(face, baseColor, 0.2, 1.5)

	if typeof(content) == "string" then
		text(face, content, F.Heavy, C.White, maxText, {
			Size = UDim2.fromScale(0.8, 0.46), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
	elseif typeof(content) == "function" then
		content(face)
	end

	local hoverColor = color:Lerp(C.White, 0.1)
	local pressColor = color:Lerp(Color3.new(0, 0, 0), 0.1)
	local hovering, pressed = false, false
	local function release()
		if not pressed then return end
		pressed = false
		tween(face, RELEASE, { Position = UDim2.fromOffset(0, 0), BackgroundColor3 = hovering and hoverColor or color })
		tween(shadow, RELEASE, { Position = UDim2.fromOffset(0, depth + 3) })
	end
	b.MouseEnter:Connect(function()
		hovering = true
		if not pressed then tween(face, QUICK, { BackgroundColor3 = hoverColor }) end
	end)
	b.MouseLeave:Connect(function()
		hovering = false
		release()
		tween(face, QUICK, { BackgroundColor3 = color })
	end)
	b.MouseButton1Down:Connect(function()
		pressed = true
		tween(face, PRESS, { Position = UDim2.fromOffset(0, pressDepth), BackgroundColor3 = pressColor })
		tween(shadow, PRESS, { Position = UDim2.fromOffset(0, depth + 2) })
	end)
	b.MouseButton1Up:Connect(release)
	return b
end

---------------------------------------------------------------------
-- Formatage
---------------------------------------------------------------------
local function fmtNum(n)
	n = tonumber(n) or 0
	if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

local function fmtRate(n)
	n = tonumber(n) or 0
	if n >= 1e3 then return fmtNum(n) end
	if n == math.floor(n) then return tostring(n) end
	return string.format("%.1f", n)
end

local function fmtTime(sec)
	sec = math.floor(tonumber(sec) or 0)
	if sec <= 0 then return "0m" end
	local d, h, m = sec // 86400, (sec % 86400) // 3600, (sec % 3600) // 60
	if d > 0 then return string.format("%dd %dh", d, h) end
	if h > 0 then return string.format("%dh %dm", h, m) end
	return string.format("%dm", m)
end

---------------------------------------------------------------------
-- ✨ Contour blanc (1 seul Highlight réutilisé)
---------------------------------------------------------------------
local outline = new("Highlight", {
	Name = "ProfileHoverOutline",
	FillTransparency = 1,
	OutlineColor = C.White,
	OutlineTransparency = 0.55,   -- 👈 0 = blanc franc, 1 = invisible
	DepthMode = Enum.HighlightDepthMode.Occluded,
	Enabled = false,
}, workspace)

---------------------------------------------------------------------
-- 🏷️ Billboard "Player Profile"
---------------------------------------------------------------------
local tag = new("BillboardGui", {
	Name = "ProfileHoverTag",
	Size = UDim2.fromOffset(IS_TOUCH and 150 or 170, IS_TOUCH and 40 or 44),
	AlwaysOnTop = true, LightInfluence = 0, Active = true,
	ResetOnSpawn = false, Enabled = false,
}, playerGui)

local tagBtn = new("TextButton", {
	Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false,
	BackgroundColor3 = C.Glass, BackgroundTransparency = C.GlassAlpha,
}, tag)
corner(tagBtn, UDim.new(1, 0))
stroke(tagBtn, C.White, 0.15, 1.5)
local tagScale = new("UIScale", { Scale = 1 }, tagBtn)

local tagIcon = new("ImageLabel", {
	BackgroundTransparency = 1, Image = ICON_ID, ScaleType = Enum.ScaleType.Fit,
	Size = UDim2.fromScale(0.62, 0.62), AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 8, 0.5, 0),
}, tagBtn)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, tagIcon)

text(tagBtn, "Player Profile", F.Heavy, C.White, 18, {
	Size = UDim2.new(1, -52, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 44, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Left,
})

---------------------------------------------------------------------
-- 🪪 Fiche profil (style PartyPadUI)
---------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "PlayerProfileUI", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 20,
}, playerGui)

local dim = new("TextButton", {
	Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false,
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Visible = false,
}, gui)

local panel = new("CanvasGroup", {
	Name = "Profile",
	Size = UDim2.fromScale(0.9, 0.8),
	Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = C.Glass, BackgroundTransparency = C.GlassAlpha,
	GroupTransparency = 1, Visible = false,
}, gui)
corner(panel, UDim.new(0, 18))
new("UIAspectRatioConstraint", { AspectRatio = 0.92 }, panel)
new("UISizeConstraint", { MinSize = Vector2.new(290, 315), MaxSize = Vector2.new(520, 565) }, panel)
local pStroke = stroke(panel, C.White, 0, 1.5)
new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.72, 0.92) }, pStroke)
local panelScale = new("UIScale", { Scale = 0.94 }, panel)

-- Filet d'accent
local accent = new("Frame", {
	BackgroundColor3 = C.White, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3),
}, panel)
new("UIGradient", {
	Color = ColorSequence.new(C.AccentDeep, C.Accent),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	}),
}, accent)

-- En-tête : avatar + noms + badges
local avatar = new("ImageLabel", {
	BackgroundColor3 = Color3.fromRGB(20, 24, 34), Size = UDim2.fromScale(0.19, 0.19),
	Position = UDim2.fromScale(0.06, 0.055),
}, panel)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, avatar)
corner(avatar, UDim.new(1, 0))
local avStroke = stroke(avatar, C.Accent, 0, 2)

local nameLbl = text(panel, "", F.Heavy, C.White, 30, {
	Size = UDim2.fromScale(0.42, 0.07), Position = UDim2.fromScale(0.29, 0.06),
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})
local userLbl = text(panel, "", F.Medium, C.Sub, 16, {
	Size = UDim2.fromScale(0.42, 0.042), Position = UDim2.fromScale(0.29, 0.132),
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})

-- Rangée de badges (VIP, x2, x5, x10)
local badgeRow = new("Frame", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(0.66, 0.052),
	Position = UDim2.fromScale(0.29, 0.188),
}, panel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
}, badgeRow)

local function makeBadge(order, iconId, label, color)
	local pill = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(24, 29, 40), BackgroundTransparency = 0.1,
		Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order, Visible = false,
	}, badgeRow)
	corner(pill, UDim.new(1, 0))
	stroke(pill, color, 0.25, 1.5)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 9) }, pill)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, pill)
	local img = new("ImageLabel", {
		BackgroundTransparency = 1, Image = iconId, ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 0.9),
	}, pill)
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, img)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, FontFace = F.Heavy, Text = label, TextColor3 = color,
		TextScaled = true, Size = UDim2.fromScale(0, 0.62), AutomaticSize = Enum.AutomaticSize.X,
	}, pill)
	new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 8 }, l)
	return pill
end

local badges = {
	vip = makeBadge(1, BADGE_ICON.vip, "VIP", C.Gold),
}
for i, ps in PASS do
	badges[ps.badge] = makeBadge(i + 1, BADGE_ICON[ps.badge], ps.label, C.Accent)
end

local closeBtn = button3D(panel, {
	Size = UDim2.fromScale(0.1, 0.1), Position = UDim2.fromScale(0.905, 0.1),
}, C.Red, C.RedBase, function(face)
	local x = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.42, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, face)
	for _, r in { 45, -45 } do
		local bar = new("Frame", { BackgroundColor3 = C.White, BorderSizePixel = 0,
			Size = UDim2.new(1.2, 0, 0, 3), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Rotation = r }, x)
		corner(bar, UDim.new(1, 0))
	end
end, nil, 4)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, closeBtn)

new("Frame", {
	Size = UDim2.new(0.88, 0, 0, 1), Position = UDim2.fromScale(0.06, 0.27),
	BackgroundColor3 = C.White, BackgroundTransparency = 0.9, BorderSizePixel = 0,
}, panel)

---------------------------------------------------------------------
-- 👑 FICHE VIP — mêmes effets sobres que l'entry VIP du leaderboard
--    plaque dorée, contour or, nom doré, anneau d'avatar doré,
--    couronne, reflet lent qui balaye la fiche, quelques étincelles.
--    ↩️ VIP_PROFILE_STYLE = false → fiche VIP identique aux autres.
---------------------------------------------------------------------
local VIP_PROFILE_STYLE = true
local VIP = {
	on = false,
	GOLD      = Color3.fromRGB(255, 210, 60),
	GOLD_SOFT = Color3.fromRGB(255, 236, 160),
	GOLD_DEEP = Color3.fromRGB(190, 130, 15),
	CROWN     = "rbxassetid://93460778559039",
	PERIOD = 9.0, SWEEP = 2.6,       -- reflet : un passage lent toutes les 9 s
}

-- Plaque dorée derrière le contenu (noir à gauche → or sombre à droite)
VIP.wash = new("Frame", {
	Name = "VipWash", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
	BackgroundColor3 = C.White, BackgroundTransparency = 0.3, ZIndex = 0, Visible = false,
}, panel)
corner(VIP.wash, UDim.new(0, 18))
new("UIGradient", {
	Rotation = 20,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(12, 9, 3)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(24, 18, 5)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(78, 57, 12)),
	}),
}, VIP.wash)

-- Reflet qui traverse toute la fiche (bande claire, très discrète)
VIP.sheen = new("Frame", {
	Name = "VipSheen", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
	BackgroundColor3 = Color3.fromRGB(255, 246, 214), ZIndex = 6, Visible = false,
}, panel)
corner(VIP.sheen, UDim.new(0, 18))
VIP.sheenGrad = new("UIGradient", {
	Rotation = 14, Offset = Vector2.new(1, 0),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 1),
		NumberSequenceKeypoint.new(0.12, 1),
		NumberSequenceKeypoint.new(0.30, 0.95),
		NumberSequenceKeypoint.new(0.50, 0.86),
		NumberSequenceKeypoint.new(0.70, 0.95),
		NumberSequenceKeypoint.new(0.88, 1),
		NumberSequenceKeypoint.new(1.00, 1),
	}),
}, VIP.sheen)

-- Nom doré (le dégradé multiplie la couleur → texte blanc dessous)
VIP.nameGrad = new("UIGradient", {
	Rotation = 90, Enabled = false,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 252, 170)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 220, 70)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(235, 175, 30)),
	}),
}, nameLbl)
VIP.nameStroke = new("UIStroke", {
	Color = Color3.fromRGB(90, 55, 0), Thickness = 1.2, Transparency = 1,
}, nameLbl)

-- Anneau d'avatar doré
VIP.avGrad = new("UIGradient", {
	Rotation = 45, Enabled = false,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, VIP.GOLD_SOFT),
		ColorSequenceKeypoint.new(0.5, VIP.GOLD_DEEP),
		ColorSequenceKeypoint.new(1.0, VIP.GOLD_SOFT),
	}),
}, avStroke)

-- Icône VIP collée à DROITE du nom (suit la largeur réelle du texte)
VIP.crown = new("ImageLabel", {
	Name = "VipCrown", BackgroundTransparency = 1, Image = VIP.CROWN,
	ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(0.09, 0.075),
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.5, 0.095),
	ZIndex = 4, Visible = false,
}, panel)
new("UIAspectRatioConstraint", { AspectRatio = 1.2, DominantAxis = Enum.DominantAxis.Height }, VIP.crown)

local NAME_W, NAME_W_VIP = 0.42, 0.35   -- le nom laisse la place à l'icône
local function placeCrown()
	local w = nameLbl.AbsoluteSize.X
	if w <= 0 then return end
	-- tout en « scale » : indépendant du UIScale d'ouverture de la fiche
	local textW = math.min(nameLbl.TextBounds.X / w, 1) * nameLbl.Size.X.Scale
	VIP.crown.Position = UDim2.fromScale(0.29 + textW + 0.012, 0.095)
end
nameLbl:GetPropertyChangedSignal("TextBounds"):Connect(function()
	if VIP.on then placeCrown() end
end)

-- 🟡 Badge VIP : plus gros + plaque dorée en dégradé (comme le leaderboard)
if VIP_PROFILE_STYLE then
	local pill = badges.vip
	pill.BackgroundColor3       = C.White        -- le dégradé fait la couleur
	pill.BackgroundTransparency = 0
	pill.Size                   = UDim2.fromScale(0, 1.4)
	new("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 240, 100)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 160, 20)),
			ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 220, 80)),
		}),
	}, pill)
	local ps = pill:FindFirstChildOfClass("UIStroke")
	if ps then ps.Color, ps.Transparency, ps.Thickness = VIP.GOLD_SOFT, 0.1, 1.5 end
	local pad = pill:FindFirstChildOfClass("UIPadding")
	if pad then pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 12) end
	local lbl = pill:FindFirstChildOfClass("TextLabel")
	if lbl then
		lbl.TextColor3 = Color3.fromRGB(28, 18, 0)
		lbl.Size = UDim2.fromScale(0, 0.6)
		local c = lbl:FindFirstChildOfClass("UITextSizeConstraint")
		if c then c.MaxTextSize = 22 end
	end
end

-- Étincelles discrètes qui montent autour du nom
VIP.sparks = {}
for i, x in { 0.30, 0.52, 0.74 } do
	local d = new("Frame", {
		Size = UDim2.fromOffset(3, 3), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = VIP.GOLD_SOFT, BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 5, Visible = false,
	}, panel)
	corner(d, UDim.new(1, 0))
	VIP.sparks[i] = { f = d, x = x, phase = (i - 1) / 3 }
end

-- Valeurs d'origine (pour revenir au style normal)
VIP.accentGrad = accent:FindFirstChildOfClass("UIGradient")
VIP.pStrokeGrad = pStroke:FindFirstChildOfClass("UIGradient")

local function applyVipStyle(isVip)
	isVip = VIP_PROFILE_STYLE and isVip == true
	VIP.on = isVip
	VIP.wash.Visible  = isVip
	VIP.sheen.Visible = isVip
	VIP.crown.Visible = isVip
	for _, sp in VIP.sparks do sp.f.Visible = isVip end

	-- contour de la fiche
	pStroke.Color     = isVip and VIP.GOLD or C.White
	pStroke.Thickness = isVip and 2 or 1.5
	if VIP.pStrokeGrad then
		VIP.pStrokeGrad.Transparency = isVip and NumberSequence.new(0.1, 0.55)
			or NumberSequence.new(0.72, 0.92)
	end
	-- filet d'accent du haut
	if VIP.accentGrad then
		VIP.accentGrad.Color = isVip and ColorSequence.new(VIP.GOLD_DEEP, VIP.GOLD)
			or ColorSequence.new(C.AccentDeep, C.Accent)
	end
	-- nom (+ icône VIP à sa droite)
	nameLbl.TextColor3 = C.White
	nameLbl.Size = UDim2.fromScale(isVip and NAME_W_VIP or NAME_W, nameLbl.Size.Y.Scale)
	if isVip then placeCrown(); task.defer(placeCrown) end
	VIP.nameGrad.Enabled = isVip
	VIP.nameStroke.Transparency = isVip and 0.35 or 1
	-- avatar
	if isVip then
		avStroke.Color, avStroke.Thickness = C.White, 3
	else
		avStroke.Thickness = 2
	end
	VIP.avGrad.Enabled = isVip
end

-- Animation : une seule boucle, active uniquement fiche ouverte + VIP
RunService.Heartbeat:Connect(function()
	if not VIP.on or not panel.Visible then return end
	local t = os.clock()
	local c = t % VIP.PERIOD
	VIP.sheenGrad.Offset = (c < VIP.SWEEP)
		and Vector2.new(-1 + (c / VIP.SWEEP) * 2, 0) or Vector2.new(1, 0)
	for _, sp in VIP.sparks do
		local f = ((t * 0.35) + sp.phase) % 1
		sp.f.Position = UDim2.fromScale(sp.x, 0.2 - f * 0.16)
		sp.f.BackgroundTransparency = 0.15 + 0.85 * (f ^ 1.5)
	end
end)

-- Grille de stats (2 colonnes, défile si besoin)
local grid = new("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0,
	Size = UDim2.fromScale(0.9, 0.685), Position = UDim2.fromScale(0.05, 0.29),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 3, ScrollBarImageColor3 = C.Accent, ScrollBarImageTransparency = 0.4,
}, panel)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 6),
}, grid)
-- 🆕 La fiche défile : les UGC récupérés EN PREMIER (la preuve), puis les stats
new("UIListLayout", {
	Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)
text(grid, "Stats", F.Heavy, C.White, 20, {
	Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Left,
})
local tilesBox = new("Frame", {
	Name = "Tiles", BackgroundTransparency = 1, LayoutOrder = 2,
	Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, grid)
local gridLayout = new("UIGridLayout", {
	CellSize = UDim2.new(0.5, -5, 0, 60), CellPadding = UDim2.fromOffset(10, 9),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tilesBox)
local function fitCells()
	local w = grid.AbsoluteSize.X
	if w <= 0 then return end
	gridLayout.CellSize = UDim2.new(0.5, -5, 0, math.clamp(math.floor(w * 0.15), 48, 68))
end
grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCells)
fitCells()

--[[ Tuiles
	key     = identifiant interne
	style   = clé de LB (icône + couleurs) ; emoji = repli si pas d'icône
	label   = texte du haut (peut être remplacé à chaud, ex: "Best 30d")
]]
local STATS = {
	{ key = "points",   style = "points",    label = "Points" },
	{ key = "pps",      style = "points",    label = "Boost", icon = BADGE_ICON.boost2 },
	{ key = "kills",    style = "kills",     label = "Total Kills" },
	{ key = "wins",     style = "neutral",   label = "Arena Wins", emoji = "🏆" },   -- 🏆 manches gagnées en PvP
	{ key = "rebirths", style = "rebirths",  label = "Rebirths" },
	{ key = "streak",   style = "streak",    label = "Streak" },
	{ key = "gifted",   style = "gifters",   label = "Points Gifted" },
	{ key = "donated",  style = "donations", label = "Robux Donated" },
	{ key = "friends",  style = "neutral",   label = "Friends in Game", emoji = "👥" },
}

local tiles = {}  -- key → { frame, label, value }
for i, s in STATS do
	local st = LB[s.style] or LB.neutral
	local tile = new("Frame", {
		BackgroundColor3 = C.Tile, BackgroundTransparency = 0.25, LayoutOrder = i,
	}, tilesBox)
	corner(tile, UDim.new(0, 12))
	stroke(tile, C.White, 0.88, 1)

	-- icône seule, sans fond
	local chip = new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(0.72, 0.72),
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0),
	}, tile)
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, chip)
	local icon = s.icon or st.icon
	if icon then
		new("ImageLabel", {
			BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
		}, chip)
	else
		text(chip, s.emoji or "•", F.Bold, C.White, 28, {
			Size = UDim2.fromScale(0.9, 0.9), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
	end

	-- texte : on laisse la place de la pastille (hauteur de tuile ≈ largeur pastille)
	local label = text(tile, s.label, F.Bold, Color3.fromRGB(214, 222, 236), 16, {
		Size = UDim2.new(1, -8, 0.3, 0), Position = UDim2.new(0, 0, 0.14, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local value = text(tile, "—", F.Heavy, C.White, 22, {
		Size = UDim2.new(1, -8, 0.42, 0), Position = UDim2.new(0, 0, 0.45, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- décale le texte à droite de la pastille, quelle que soit la taille de tuile
	local function place()
		local x = chip.AbsoluteSize.X + 15
		label.Position = UDim2.new(0, x, 0.14, 0); label.Size = UDim2.new(1, -x - 6, 0.3, 0)
		value.Position = UDim2.new(0, x, 0.45, 0); value.Size = UDim2.new(1, -x - 6, 0.42, 0)
	end
	chip:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()

	tiles[s.key] = { frame = tile, label = label, value = value, baseLabel = s.label }
end

local function setTile(key, val, labelOverride)
	local t = tiles[key]
	if not t then return end
	if val == nil then
		t.frame.Visible = false
		return
	end
	t.frame.Visible = true
	t.value.Text = val
	t.label.Text = labelOverride or t.baseLabel
end

-- ⚡ Boost en vert dès qu'il n'est pas x1.00 (comme le billboard)
local BOOST_GREEN = Color3.fromRGB(70, 235, 110)
local function paintBoost(mult)
	local t = tiles.pps
	if not t then return end
	local boosted = type(mult) == "number" and string.format("%.2f", mult) ~= "1.00"
	t.value.TextColor3 = boosted and BOOST_GREEN or C.White
end

---------------------------------------------------------------------
-- Lecture des stats (données publiques uniquement)
---------------------------------------------------------------------
-- PlaytimeSeconds n'est posé qu'au chargement : on ajoute le temps écoulé
-- depuis qu'on l'a vu (exact pour ceux qui rejoignent après toi).
local playSeen = {}

local function readPlaytime(p)
	local base = p:GetAttribute("PlaytimeSeconds")
	if type(base) ~= "number" then return nil end
	local s = playSeen[p.UserId]
	if not s or s.base ~= base then
		s = { base = base, at = os.clock() }
		playSeen[p.UserId] = s
	end
	return base + (os.clock() - s.at)
end

local function statValue(p, ls, name, attr)
	local v = ls and ls:FindFirstChild(name)
	if v and v:IsA("ValueBase") then return v.Value end
	return attr and p:GetAttribute(attr) or nil
end

-- 🎟️ Gamepass possédés (info publique Roblox) — cache 5 min par joueur
local passCache = {}
local function fetchPasses(p)
	local uid = p.UserId
	local c = passCache[uid]
	if c and os.clock() - c.at < 300 then return end
	c = { at = os.clock(), owned = c and c.owned or {} }
	passCache[uid] = c
	task.spawn(function()
		for _, ps in PASS do
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, uid, ps.id)
			if ok then c.owned[ps.id] = has end
		end
		local ok, vip = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, uid, VIP_PASS_ID)
		if ok then c.owned[VIP_PASS_ID] = vip end
	end)
end

-- 🎁 Top Gifters : remote DÉJÀ utilisé par ton GiftingClient (lecture seule).
--    Une requête max par minute, partagée entre toutes les fiches.
local giftRemote = nil
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("GiftingRemotes", 30)
	giftRemote = folder and folder:WaitForChild("GetTopGifters", 10) or nil
end)
local gifters = { at = -math.huge, byId = {}, busy = false }
local function fetchGifters()
	if not giftRemote or gifters.busy or os.clock() - gifters.at < 60 then return end
	gifters.busy = true
	task.spawn(function()
		local ok, list = pcall(giftRemote.InvokeServer, giftRemote)
		gifters.busy = false
		gifters.at = os.clock()
		if ok and type(list) == "table" then
			local byId = {}
			for rank, e in ipairs(list) do
				if type(e) == "table" and e.userId then
					byId[tonumber(e.userId)] = { rank = rank, gifted = tonumber(e.gifted) or 0 }
				end
			end
			gifters.byId = byId
		end
	end)
end

-- 💚 Robux Donated : ton serveur TopDonators expose DÉJÀ le top 50
--    (GetLeaderboardData + UpdateLeaderboard). Lecture seule, rien à ajouter côté serveur.
local donorFn = nil
local donors = { at = -math.huge, byId = {}, busy = false }
local function setDonors(list)
	if type(list) ~= "table" then return end
	local byId = {}
	for rank, e in ipairs(list) do
		if type(e) == "table" and tonumber(e.userId) then
			byId[tonumber(e.userId)] = { rank = rank, total = tonumber(e.total) or 0 }
		end
	end
	donors.byId, donors.at = byId, os.clock()
end
task.spawn(function()
	donorFn = ReplicatedStorage:WaitForChild("GetLeaderboardData", 30)
	local upd = ReplicatedStorage:WaitForChild("UpdateLeaderboard", 30)
	if upd then
		upd.OnClientEvent:Connect(function(payload)   -- mises à jour gratuites (0 requête)
			if type(payload) == "table" then setDonors(payload.top) end
		end)
	end
end)
local function fetchDonors()
	if not donorFn or donors.busy or os.clock() - donors.at < 60 then return end
	donors.busy = true
	task.spawn(function()
		local ok, list = pcall(donorFn.InvokeServer, donorFn)
		donors.busy = false
		if ok and type(list) == "table" and #list > 0 then setDonors(list) end
	end)
end

local function refreshStats(p)
	local ls = p:FindFirstChild("leaderstats")
	local mult = p:GetAttribute("PointsMultiplier")

	setTile("points", fmtNum(statValue(p, ls, "Points", "Points") or 0))
	-- ⚡ même affichage que le billboard au-dessus de la tête (x1.00, x2.20…)
	setTile("pps", type(mult) == "number" and string.format("x%.2f", mult) or "x1.00")
	paintBoost(mult)
	setTile("kills", fmtNum(p:GetAttribute("TotalKills") or 0))
	setTile("wins", fmtNum(p:GetAttribute("ArenaWins") or 0))   -- 🏆 posé par CombatServer

	setTile("rebirths", tostring(statValue(p, ls, "Rebirths", "RebirthCount") or 0))

	local best = p:GetAttribute("FlameHighScore") or 0
	setTile("streak", tostring(p:GetAttribute("FlameStreak") or 0) .. " days",
		"Streak · Best " .. tostring(best) .. "d")

	local g = gifters.byId[p.UserId]
	if g then
		setTile("gifted", fmtNum(g.gifted) .. " pts", "Gifted · #" .. g.rank .. " Top Gifter")
	else
		setTile("gifted", giftRemote and "—" or nil, giftRemote and "Gifted · not in Top" or nil)
	end

	local dn = donors.byId[p.UserId]
	if dn then
		setTile("donated", "R$ " .. fmtNum(dn.total), "Donated · #" .. dn.rank .. " Top Donor")
	else
		setTile("donated", donorFn and "—" or nil, donorFn and "Donated · not in Top 50" or nil)
	end

	setTile("friends", tostring(p:GetAttribute("FriendCount") or 0))

	-- Badges
	local owned = passCache[p.UserId] and passCache[p.UserId].owned or {}
	local vip = p:GetAttribute("IsVIP") == true or owned[VIP_PASS_ID] == true
	badges.vip.Visible = vip
	for _, ps in PASS do
		badges[ps.badge].Visible = owned[ps.id] == true
	end
	avStroke.Color = vip and C.Gold or C.Accent
	applyVipStyle(vip)
end

---------------------------------------------------------------------
-- 🎽 UGC RÉCUPÉRÉS — 🆕 TOUT EN HAUT de la fiche (la première chose qu'on voit)
--    Cadre doré : nombre d'UGC + bandeau de cartes qui défile de gauche à droite,
--    la plus récente à gauche, numérotée (#1 = la toute première récupérée).
--    Source : la même que ta section admin (UGCRedeemLog_Server), via
--    PublicProfile_Server → remote « GetPublicUGCs ». Que du public :
--    l'UGC et son image.
---------------------------------------------------------------------
local UGC = { token = 0, rows = {} }

UGC.box = new("Frame", {
	Name = "UGCs", BackgroundColor3 = C.Tile, BackgroundTransparency = 0.35, LayoutOrder = 0,
	Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, grid)
corner(UGC.box, UDim.new(0, 14))
stroke(UGC.box, C.Gold, 0.35, 1.5)
new("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
}, UGC.box)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, UGC.box)

UGC.title = text(UGC.box, "🎽 UGC Redeemed", F.Heavy, C.Gold, 22, {
	Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 0, TextXAlignment = Enum.TextXAlignment.Left,
})
UGC.note = text(UGC.box, "", F.Medium, C.Sub, 15, {
	Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Left,
})
UGC.strip = new("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 2, Visible = false,
	Size = UDim2.new(1, 0, 0, 128), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 3, ScrollBarImageColor3 = C.Gold, ScrollBarImageTransparency = 0.4,
}, UGC.box)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, UGC.strip)
new("UIPadding", { PaddingBottom = UDim.new(0, 6) }, UGC.strip)

local function ugcClear()
	for _, r in UGC.rows do r:Destroy() end
	table.clear(UGC.rows)
	UGC.strip.CanvasPosition = Vector2.zero
end

local function ugcRow(order, number, item)
	local card = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(20, 24, 34), BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(96, 116), LayoutOrder = order,
	}, UGC.strip)
	corner(card, UDim.new(0, 12))
	stroke(card, C.White, 0.85, 1)
	local img = new("ImageLabel", {
		BackgroundTransparency = 1, Image = item.img or "", ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(74, 74), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
	}, card)
	corner(img, UDim.new(0, 8))
	text(card, "#" .. number, F.Heavy, C.Gold, 13, {
		Size = UDim2.fromOffset(36, 16), Position = UDim2.fromOffset(5, 3),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	text(card, item.n or "UGC", F.Bold, C.White, 13, {
		Size = UDim2.new(1, -8, 0, 30), Position = UDim2.new(0, 4, 0, 82),
		TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	table.insert(UGC.rows, card)
end

local function loadUGCs(userId)
	UGC.token += 1
	local my = UGC.token
	ugcClear()
	UGC.title.Text = "🎽 UGC Redeemed"
	UGC.note.Text = "Loading…"
	UGC.note.Visible = true
	UGC.strip.Visible = false

	task.spawn(function()
		local fn = ReplicatedStorage:WaitForChild("GetPublicUGCs", 10)
		-- 🔘 section désactivée dans PublicProfile_Server (SHOW_UGC_REDEEMED)
		UGC.box.Visible = not (fn and fn:GetAttribute("Enabled") == false)
		if not UGC.box.Visible then return end
		local res
		if fn then
			for _ = 1, 6 do
				local ok, r = pcall(fn.InvokeServer, fn, userId)
				if ok and not (type(r) == "table" and r.throttled) then res = r; break end
				task.wait(0.5)
			end
		end
		if my ~= UGC.token then return end   -- une autre fiche a été ouverte entre-temps

		if type(res) == "table" and res.disabled then
			UGC.box.Visible = false
			return
		end
		if type(res) ~= "table" or not res.ok then
			UGC.note.Text = "UGC list unavailable right now."
			return
		end
		local list = res.list or {}
		local total = math.max(tonumber(res.total) or 0, #list)
		UGC.title.Text = ("🎽 UGC Redeemed · %d"):format(total)
		if #list == 0 then
			UGC.note.Text = "No UGC redeemed yet."
			return
		end
		-- numéro = ordre de récupération ; s'il manque les plus anciens,
		-- la numérotation part du bon rang quand même
		local first = total - #list + 1
		UGC.note.Visible = total > #list
		UGC.note.Text = ("Showing the last %d"):format(#list)
		for i = #list, 1, -1 do              -- plus récent à gauche
			ugcRow(#list - i, first + i - 1, list[i])
		end
		UGC.strip.Visible = true
	end)
end

---------------------------------------------------------------------
-- 🎁 BOUTON GIFT dans la fiche
--    À gauche du ✕, même taille et même enfoncement 3D que lui. Le visuel
--    vient de TON bouton (PlayerGui.UGCshop.ShopFrame.Gift, sans ses scripts)
--    et il ouvre ton panneau de gift, avec le
--    joueur de la fiche déjà sélectionné (_G.OpenGiftWizardFor, GiftingClient).
--    Caché sur ta propre fiche : on ne peut pas s'offrir un cadeau.
--    ↩️ GIFT_BUTTON_ENABLED = false → plus de bouton.
---------------------------------------------------------------------
local GIFT_BUTTON_ENABLED = true
local GIFT_BLUE = Color3.fromRGB(40, 150, 235)   -- 🔵 couleur de la face si ton bouton n'en a pas
local GIFT = { btn = nil, target = nil, close = nil }

local function findShopGift()
	local shop = playerGui:FindFirstChild("UGCshop")
	local sf = shop and shop:FindFirstChild("ShopFrame")
	if not sf then return nil end
	local g = sf:FindFirstChild("Gift")
	if g and g:IsA("GuiObject") then return g end
	g = sf:FindFirstChild("Gift", true)
	return (g and g:IsA("GuiObject")) and g or nil
end

-- 🔁 Quand le panneau de gift se ferme (✕, Cancel, ou après un gift), la
--    fiche du joueur se rouvre. S'il n'a pas pu s'ouvrir (coupure d'urgence),
--    la fiche revient tout de suite.
local function watchWizard(before, reopen)
	if not reopen then return end
	local gui
	local t0 = os.clock()
	repeat
		for _, c in playerGui:GetChildren() do
			if c.Name == "GiftWizard" and c ~= before then gui = c break end
		end
		if gui then break end
		task.wait(0.05)
	until os.clock() - t0 > 1.5
	if not gui then reopen() return end
	gui.Destroying:Connect(function()
		task.defer(reopen)
	end)
end

local function onGiftClick()
	local t = GIFT.target
	if not t then return end
	if GIFT.close then GIFT.close() end
	task.spawn(function()
		local before = playerGui:FindFirstChild("GiftWizard")
		local name = t.name
		if not name then
			local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, t.userId)
			name = ok and n or nil
		end
		if type(_G.OpenGiftWizardFor) == "function" then
			_G.OpenGiftWizardFor({ userId = t.userId, name = name, displayName = t.displayName or name })
		elseif type(_G.OpenGiftWizard) == "function" then
			warn("[Profile] _G.OpenGiftWizardFor absent → colle le patch dans GiftingClient")
			_G.OpenGiftWizard()
		end
		watchWizard(before, t.reopen)
	end)
end

local function buildGiftButton()
	if GIFT.btn then return GIFT.btn end
	local src = findShopGift()
	if not src then return nil end

	-- 🔵 Ton bouton est bleu grâce à son UIGradient (sa couleur de fond seule
	--    est blanche/rouge). On pose donc CE dégradé sur la face 3D, sur fond
	--    blanc, à la place de celui du bouton 3D : un seul dégradé, le vrai bleu.
	local srcGrad = src:FindFirstChildOfClass("UIGradient")
	local col, baseCol
	if srcGrad then
		col = C.White
		local first = srcGrad.Color.Keypoints[1].Value
		baseCol = first:Lerp(Color3.new(0, 0, 0), 0.45)
	else
		col = GIFT_BLUE
		baseCol = col:Lerp(Color3.new(0, 0, 0), 0.45)
	end

	-- Même taille, même enfoncement que le ✕, posé juste à sa gauche
	local b = button3D(panel, {
		Name = "ProfileGift",
		Size = UDim2.fromScale(0.1, 0.1), Position = UDim2.fromScale(0.775, 0.1),
	}, col, baseCol, function(face)
		-- le visuel de TON bouton (image / texte), sans ses scripts ni ses clics
		local v = src:Clone()
		for _, d in v:GetDescendants() do
			if d:IsA("LuaSourceContainer") or d:IsA("UIAspectRatioConstraint")
				or (d:IsA("UIGradient") and d.Parent == v)   -- déjà sur la face
				or d:IsA("UISizeConstraint")
				-- son contour : il restait fixe et cassait l'effet d'enfoncement
				or (d:IsA("UIStroke") and (d.Parent == v
					or d.ApplyStrokeMode == Enum.ApplyStrokeMode.Border)) then
				d:Destroy()
			end
		end
		for _, g in { v, table.unpack(v:GetDescendants()) } do
			if g:IsA("GuiObject") then
				g.Active = false
				pcall(function() g.Interactable = false end)   -- le clic va au bouton 3D
			end
		end
		v.Name = "GiftVisual"
		v.Visible = true
		v.AnchorPoint = Vector2.new(0.5, 0.5)
		v.Position = UDim2.fromScale(0.5, 0.5)
		v.Size = UDim2.fromScale(1, 1)
		v.BackgroundTransparency = 1      -- c'est la face 3D qui porte la couleur
		v.Rotation = 0
		v.Parent = face
	end, nil, 4)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, b)
	-- pas de contour non plus sur la face 3D : juste la face qui s'enfonce
	local face = b:FindFirstChild("Face")
	local fs = face and face:FindFirstChildOfClass("UIStroke")
	if fs then fs:Destroy() end
	if face and srcGrad then
		local g = face:FindFirstChildOfClass("UIGradient")
		if g then g:Destroy() end            -- le dégradé blanc→gris du bouton 3D
		srcGrad:Clone().Parent = face         -- ton dégradé bleu, seul
	end
	b.Activated:Connect(onGiftClick)

	GIFT.btn = b
	return b
end

local function setGiftTarget(userId, name, displayName, reopen)
	local show = GIFT_BUTTON_ENABLED and userId ~= nil and userId ~= player.UserId
	GIFT.target = show and { userId = userId, name = name, displayName = displayName, reopen = reopen } or nil
	local b = show and buildGiftButton() or GIFT.btn
	if b then b.Visible = show end
end

---------------------------------------------------------------------
-- Ouverture / fermeture
---------------------------------------------------------------------
local panelOpen = false
local shown = nil
local remoteView = nil   -- 🏆 fiche ouverte depuis un leaderboard (joueur absent de ce serveur)
local setTarget -- fwd

-- 🔝 La fiche passe AU-DESSUS de toutes tes autres interfaces quand elle
--    s'ouvre. Seules les fenêtres de gift restent au-dessus d'elle (panneau
--    ouvert depuis le bouton Gift, message de coupure, réception d'un cadeau).
local GIFT_GUIS = {
	GiftWizard = true, GiftDisabledNotice = true, GiftReceived = true, TopGifters = true, GiftError = true,
}
local function isOtherScreen(g)
	if g == gui or not g:IsA("ScreenGui") then return false end
	-- Ces calques restent prioritaires : ne pas monter le profil au-dessus.
	local name = g.Name
	return name ~= "CoinRewardGui" and name ~= "RobuxPromptFX"
		and name ~= "RookieGuideUI" and name ~= "RookieGuideHUD"
		and name ~= "TutorialOverlayGui" and name ~= "TutorialGui"
end
local function liftGiftGuis()
	for _, g in playerGui:GetChildren() do
		if isOtherScreen(g) and GIFT_GUIS[g.Name] and g.DisplayOrder <= gui.DisplayOrder then
			g.DisplayOrder = gui.DisplayOrder + 1
		end
	end
end
local function bringToFront()
	local top = 0
	for _, g in playerGui:GetChildren() do
		if isOtherScreen(g) and not GIFT_GUIS[g.Name] then
			top = math.max(top, g.DisplayOrder)
		end
	end
	gui.DisplayOrder = math.max(20, top + 1)
	liftGiftGuis()
end
-- Une interface qui apparaît pendant que la fiche est ouverte ne passe pas devant
playerGui.ChildAdded:Connect(function(g)
	if not panelOpen or not isOtherScreen(g) then return end
	task.defer(function()
		if not panelOpen then return end
		if GIFT_GUIS[g.Name] then liftGiftGuis() else bringToFront() end
	end)
end)

local function closeProfile()
	if not panelOpen then return end
	panelOpen = false
	shown = nil
	remoteView = nil
	tween(dim, BACK, { BackgroundTransparency = 1 })
	tween(panelScale, BACK, { Scale = 0.96 })
	tween(panel, BACK, { GroupTransparency = 1 }).Completed:Connect(function()
		if not panelOpen then panel.Visible = false; dim.Visible = false end
	end)
end

local function openProfile(p, force)
	-- force = ouvert depuis un leaderboard : pas de limite de distance
	if force then
		if not p or not p.Parent or inArena(player) then return end
	elseif not canView(p) then
		return
	end
	setTarget(nil)
	remoteView = nil
	shown = p
	nameLbl.Text = p.DisplayName
	userLbl.Text = "@" .. p.Name
	avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. p.UserId .. "&w=150&h=150"
	grid.CanvasPosition = Vector2.zero
	fetchPasses(p)
	fetchGifters()
	fetchDonors()
	refreshStats(p)
	loadUGCs(p.UserId)
	setGiftTarget(p.UserId, p.Name, p.DisplayName, function()
		if panelOpen then return end            -- une autre fiche est déjà ouverte
		if p.Parent then
			openProfile(p, true)
		elseif _G.OpenPlayerProfile then        -- parti entre-temps : fiche hors ligne
			_G.OpenPlayerProfile(p.UserId, { name = p.DisplayName })
		end
	end)

	bringToFront()
	panelOpen = true
	dim.Visible, panel.Visible = true, true
	panelScale.Scale = 0.94
	tween(dim, SOFT, { BackgroundTransparency = 0.55 })
	tween(panel, SOFT, { GroupTransparency = 0 })
	tween(panelScale, SOFT, { Scale = 1 })
end

---------------------------------------------------------------------
-- 🏆 Ouverture depuis un LEADERBOARD
--    _G.OpenPlayerProfile(userId, info) — appelé par LeaderboardCore.
--    • Joueur sur CE serveur (toi compris) → fiche live complète, sans limite
--      de distance.
--    • Joueur ailleurs / hors ligne → même fiche, remplie avec ce que les
--      leaderboards affichent déjà (points, rebirths, streak, kills) + ses
--      rangs Top Gifters / Top Donors + ses gamepass. Que du public.
---------------------------------------------------------------------
local unameCache = {}

local function refreshRemote()
	local r = remoteView
	if not r then return end
	local info, uid = r.info, r.userId
	local function num(k) return tonumber(info[k]) end
	-- « … » pendant la lecture serveur, « — » si vraiment aucune donnée
	local function orWait(v) return v or (r.loading and "…" or "—") end

	setTile("points", orWait(num("points") and fmtNum(num("points"))))
	-- ⚡ boost vu la dernière fois qu'il a joué (PublicProfile_Server)
	setTile("pps", orWait(num("boost") and string.format("x%.2f", num("boost"))),
		num("boost") and "Boost · last seen" or nil)
	paintBoost(num("boost"))
	setTile("kills", orWait(num("kills") and fmtNum(num("kills"))))
	setTile("wins", r.loading and "…" or fmtNum(num("wins") or 0))   -- 🏆 PublicProfile_Server
	setTile("rebirths", orWait(num("rebirths") and tostring(num("rebirths"))))
	setTile("streak", orWait(num("streak") and (tostring(num("streak")) .. " days")),
		num("highScore") and ("Streak · Best " .. num("highScore") .. "d") or nil)
	setTile("friends", nil)                   -- n'a de sens qu'en jeu

	local g = gifters.byId[uid]
	if g then
		setTile("gifted", fmtNum(g.gifted) .. " pts", "Gifted · #" .. g.rank .. " Top Gifter")
	else
		setTile("gifted", orWait(num("gifted") and (fmtNum(num("gifted")) .. " pts")))
	end
	local dn = donors.byId[uid]
	if dn then
		setTile("donated", "R$ " .. fmtNum(dn.total), "Donated · #" .. dn.rank .. " Top Donor")
	else
		setTile("donated", "—", "Donated · not in Top 50")
	end

	local owned = passCache[uid] and passCache[uid].owned or {}
	local vip = info.vip == true or owned[VIP_PASS_ID] == true
	badges.vip.Visible = vip
	for _, ps in PASS do
		badges[ps.badge].Visible = owned[ps.id] == true
	end
	avStroke.Color = vip and C.Gold or C.Accent
	applyVipStyle(vip)
end

_G.OpenPlayerProfile = function(userId, info)
	userId = tonumber(userId)
	if not userId or inArena(player) then return end
	info = type(info) == "table" and info or {}

	local p = Players:GetPlayerByUserId(userId)
	if p then
		openProfile(p, true)
		return
	end

	setTarget(nil)
	shown = nil
	local view = { userId = userId, info = info, loading = true }
	remoteView = view

	-- 👤 Stats publiques complètes lues côté serveur (PublicProfile_Server)
	task.spawn(function()
		local fn = ReplicatedStorage:FindFirstChild("GetPublicProfile")
		local res
		if fn then
			for _ = 1, 6 do
				local ok, r = pcall(fn.InvokeServer, fn, userId)
				if ok and not (type(r) == "table" and r.throttled) then res = r; break end
				task.wait(0.5)
			end
		end
		if type(res) == "table" then
			for k, v in pairs(res) do
				-- la valeur du board est souvent plus fraîche : on garde la plus grande
				local cur = tonumber(info[k])
				if type(v) == "number" and (not cur or v > cur) then info[k] = v end
			end
		end
		view.loading = false
		if remoteView == view then refreshRemote() end
	end)

	nameLbl.Text = tostring(info.name or ("User " .. userId))
	userLbl.Text = unameCache[userId] and ("@" .. unameCache[userId] .. "  ·  not in this server")
		or "Not in this server"
	if not unameCache[userId] then
		task.spawn(function()
			local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			if ok and n then
				unameCache[userId] = n
				if remoteView and remoteView.userId == userId then
					userLbl.Text = "@" .. n .. "  ·  not in this server"
				end
			end
		end)
	end
	avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=150&h=150"
	grid.CanvasPosition = Vector2.zero
	fetchPasses({ UserId = userId })
	fetchGifters()
	fetchDonors()
	refreshRemote()
	loadUGCs(userId)
	setGiftTarget(userId, unameCache[userId], info.name, function()
		if panelOpen then return end
		_G.OpenPlayerProfile(userId, info)
	end)

	bringToFront()
	panelOpen = true
	dim.Visible, panel.Visible = true, true
	panelScale.Scale = 0.94
	tween(dim, SOFT, { BackgroundTransparency = 0.55 })
	tween(panel, SOFT, { GroupTransparency = 0 })
	tween(panelScale, SOFT, { Scale = 1 })
end

closeBtn.Activated:Connect(closeProfile)
GIFT.close = closeProfile

-- 👤 Ouvre TA propre fiche (tes UGC récupérés + tes stats) — bouton « My Profile »
--    des Settings. Pas de bouton Gift sur ta fiche (on ne s'offre rien).
_G.OpenMyProfile = function()
	if inArena(player) then return false end
	openProfile(player, true)
	return true
end
-- ❌ plus de fermeture en cliquant à côté : seul le bouton ✕ ferme la fiche

Players.PlayerRemoving:Connect(function(p)
	playSeen[p.UserId] = nil
	passCache[p.UserId] = nil
	if p == shown then closeProfile() end
end)

-- Entrée en PVP : on ferme la fiche tout de suite
player:GetAttributeChangedSignal("InArena"):Connect(function()
	if inArena(player) then closeProfile() end
end)

-- Stats live tant que la fiche est ouverte
task.spawn(function()
	while true do
		task.wait(1)
		if panelOpen and remoteView then
			if inArena(player) then closeProfile() else refreshRemote() end
		elseif panelOpen and shown and (inArena(player) or inArena(shown)) then closeProfile()
		elseif panelOpen and shown and shown.Parent then refreshStats(shown) end
	end
end)

---------------------------------------------------------------------
-- 🎯 Survol / sélection
---------------------------------------------------------------------
local target = nil
local hideToken = 0

setTarget = function(p)
	if p == target then return end
	target = p
	local ch = p and p.Character
	if ch then
		outline.Adornee = ch
		outline.Enabled = true
		tag.Adornee = ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart
		tag.Enabled = true
		tagScale.Scale = 0.6
		tween(tagScale, POP, { Scale = 1 })
		if IS_TOUCH then
			-- Sur mobile la sélection disparaît seule après 5 s
			hideToken += 1
			local my = hideToken
			task.delay(5, function()
				if my == hideToken and target == p and not panelOpen then setTarget(nil) end
			end)
		end
	else
		target = nil
		outline.Enabled = false
		outline.Adornee = nil
		tag.Enabled = false
		tag.Adornee = nil
	end
end

tagBtn.Activated:Connect(function()
	if target then openProfile(target) end
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function playerOnRay(ray)
	rayParams.FilterDescendantsInstances = { player.Character, outline }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * MAX_DIST, rayParams)
	if not hit then return nil end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	while model do
		local p = Players:GetPlayerFromCharacter(model)
		if p then
			local hum = model:FindFirstChildOfClass("Humanoid")
			return (hum and hum.Health > 0 and canView(p)) and p or nil
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Pas de survol si la fiche est ouverte ou si on tient une arme
local function busy()
	if panelOpen or inArena(player) then return true end
	local ch = player.Character
	return ch ~= nil and ch:FindFirstChildOfClass("Tool") ~= nil
end

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	-- Cible morte / respawn / partie → on nettoie
	if target then
		local ch = target.Parent and target.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or outline.Adornee ~= ch or not canView(target) then setTarget(nil) end
	end

	if IS_TOUCH then return end
	acc += dt
	if acc < 1 / 30 then return end
	acc = 0

	if busy() then setTarget(nil) return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local m = UserInputService:GetMouseLocation()
	setTarget(playerOnRay(cam:ViewportPointToRay(m.X, m.Y)))
end)

-- PC : clic sur le joueur survolé
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or IS_TOUCH then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and target and not busy() then
		openProfile(target)
	end
end)

-- Mobile : 1er tap = sélection, 2e tap sur le même joueur = ouvre
UserInputService.TouchTapInWorld:Connect(function(pos, processedByUI)
	if processedByUI or busy() then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local p = playerOnRay(cam:ScreenPointToRay(pos.X, pos.Y))
	if p and p == target then
		openProfile(p)
	else
		setTarget(p)
	end
end)