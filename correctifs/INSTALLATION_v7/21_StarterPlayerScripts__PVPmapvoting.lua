--[[
	MapVoteClient — vote réservé aux joueurs en 1v1
	Résultat: les perdantes disparaissent, la gagnante glisse au centre (léger zoom sobre)
	🎨 Style des UI de l'arène (ArenaHUD / death screen) : panneaux bleus brillants, bord épais foncé dessous,
	   liseré clair, textes Fredoka One à gros contour foncé.
	🏷️ Vote = la photo du joueur se pose sur la map votée comme un BADGE (pop), à un endroit et une inclinaison
	   différents ; tout le monde voit les mêmes (calculés à partir du joueur, de la map et du tour de vote).
	🏆 Gagnant de la manche : colonne dorée à gauche, son perso entier en pose de conquérant sur un podium
	   (ViewportFrame) : il tient l'arme avec laquelle il a fait le plus de kills comme en arène, vu de face sur
	   sa droite, avec un zoom lent vers son visage (la caméra reste loin), puis plan fixe. Dessous : stats de la manche (kills, série, headshots), puis sa carte profil (photo, nom, @,
	   total kills, total wins).
]]
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local isMobile  = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local MapConfig      = require(ReplicatedStorage:WaitForChild("MapConfig"))
local voteStateEvent = ReplicatedStorage:WaitForChild("MapVoteState")
local voteCastEvent  = ReplicatedStorage:WaitForChild("MapVoteCast")
local hideUIEvent    = ReplicatedStorage:WaitForChild("HideUIEvent")

local EDGE_SPACING = 0.007
-- ⚙️ CONFIG position de la pill "Next Map in" sur MOBILE
local MOBILE_PILL_Y_SCALE  = 0.55  -- position verticale (0 = haut, 1 = bas de l'écran)
local MOBILE_PILL_Y_OFFSET = 0    -- décalage en pixels (augmente = descend)

-- 🎨 STYLE (même palette que les UI de l'arène)
local FREDOKA   = Font.fromEnum(Enum.Font.FredokaOne)
local WHITE     = Color3.new(1, 1, 1)
local BLUE_HI   = Color3.fromRGB(92, 196, 255)
local BLUE_LO   = Color3.fromRGB(30, 108, 236)
local BLUE_EDGE = Color3.fromRGB(16, 58, 150)
local BLUE_RIM  = Color3.fromRGB(190, 236, 255)
local OUTLINE   = Color3.fromRGB(10, 30, 80)
local YELLOW    = Color3.fromRGB(255, 214, 70)
local GREEN     = Color3.fromRGB(95, 230, 115)
local RED       = Color3.fromRGB(255, 95, 80)

local function fmt(sec)
	sec = math.max(0, math.floor(sec + 0.5))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- texte blanc Fredoka One à gros contour foncé
local function outline(label, thick)
	local st = Instance.new("UIStroke")
	st.Color = OUTLINE
	st.Thickness = thick or (isMobile and 1.5 or 2.5)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.LineJoinMode = Enum.LineJoinMode.Round
	st.Parent = label
	return st
end
-- habille une Frame en panneau de jeu : dessous foncé épais (Edge) + dessus en dégradé bleu brillant (Face) avec
-- reflet et liseré clair, contour foncé. La Frame devient un simple conteneur : tout ce que tu y mets avec
-- ZIndex >= 2 passe par-dessus. Renvoie le dégradé du dessus (pour changer sa couleur) et la Face.
local function stylePanel(f, radius, depth, hi, lo, edgeCol)
	f.BackgroundTransparency = 1
	local edge = Instance.new("Frame")
	edge.Name = "Edge"; edge.BorderSizePixel = 0; edge.BackgroundColor3 = edgeCol or BLUE_EDGE
	edge.Size = UDim2.fromScale(1, 1); edge.ZIndex = 0
	edge.Parent = f
	Instance.new("UICorner", edge).CornerRadius = UDim.new(0, radius)
	local es = Instance.new("UIStroke", edge); es.Color = OUTLINE; es.Thickness = isMobile and 1.5 or 2
	es.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local face = Instance.new("Frame")
	face.Name = "Face"; face.BorderSizePixel = 0; face.BackgroundColor3 = WHITE
	face.Size = UDim2.new(1, 0, 1, -depth); face.ZIndex = 1
	face.Parent = f
	Instance.new("UICorner", face).CornerRadius = UDim.new(0, radius)
	local g = Instance.new("UIGradient", face)
	g.Name = "Fill"; g.Rotation = 90
	g.Color = ColorSequence.new(hi or BLUE_HI, lo or BLUE_LO)
	local inset = math.max(2, math.floor(depth * 0.6))
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"; gloss.BorderSizePixel = 0; gloss.BackgroundColor3 = WHITE
	gloss.Position = UDim2.fromOffset(inset, inset); gloss.Size = UDim2.new(1, -2 * inset, 0.42, 0)
	gloss.Parent = face
	Instance.new("UICorner", gloss).CornerRadius = UDim.new(0, math.max(2, radius - inset))
	local gg = Instance.new("UIGradient", gloss); gg.Rotation = 90
	gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.62), NumberSequenceKeypoint.new(1, 0.95) })
	local rim = Instance.new("Frame")
	rim.Name = "Rim"; rim.BackgroundTransparency = 1; rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5); rim.Size = UDim2.new(1, -inset, 1, -inset); rim.Parent = face
	Instance.new("UICorner", rim).CornerRadius = UDim.new(0, math.max(2, radius - 1))
	local rs = Instance.new("UIStroke", rim); rs.Color = BLUE_RIM; rs.Thickness = isMobile and 1 or 1.6; rs.Transparency = 0.25
	return g, face
end

-- État
local phase    = "countdown"
local endsAt   = 0
local inArena  = false
local lastVote = nil

-- 🆕 transition de map
local resultMapName = nil    -- nom de la gagnante (affiché au résultat)
local loadingActive = false  -- true pendant le swap réel
local updateIntermission     -- forward declaration

--========================================================
-- 1) PILL "Next Map in :"
--========================================================
local pillGui = Instance.new("ScreenGui")
pillGui.Name = "MapCountdownGui"; pillGui.ResetOnSpawn = false; pillGui.IgnoreGuiInset = true
pillGui.Parent = playerGui

local pill = Instance.new("Frame")
pill.Name = "Pill"; pill.AnchorPoint = Vector2.new(1, 1)
pill.BorderSizePixel = 0; pill.Visible = false
if isMobile then
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Size = UDim2.new(0, 70, 0, 30)
	pill.Position = UDim2.new(1 - EDGE_SPACING, 0, MOBILE_PILL_Y_SCALE, MOBILE_PILL_Y_OFFSET)
else
	pill.Size = UDim2.new(0, 170, 0, 42); pill.Position = UDim2.new(1 - EDGE_SPACING, 0, 0.5, -45)
end
pill.Parent = pillGui
local pillFill = stylePanel(pill, isMobile and 8 or 10, isMobile and 3 or 4)

local pillLabel = Instance.new("TextLabel")
pillLabel.BackgroundTransparency = 1; pillLabel.Size = UDim2.new(1, 0, 1, -(isMobile and 3 or 4))
pillLabel.FontFace = FREDOKA; pillLabel.TextColor3 = WHITE
pillLabel.TextScaled = true; pillLabel.Text = "Next Map in : --:--"; pillLabel.ZIndex = 2; pillLabel.Parent = pill
local plPad = Instance.new("UIPadding", pillLabel)
plPad.PaddingLeft = UDim.new(0,10); plPad.PaddingRight = UDim.new(0,10); plPad.PaddingTop = UDim.new(0,4); plPad.PaddingBottom = UDim.new(0,4)
outline(pillLabel, isMobile and 1.2 or 2)

--========================================================
-- 1bis) BANNIÈRE D'INTERMISSION (transition de map, visible par tous)
--========================================================
local interGui = Instance.new("ScreenGui")
interGui.Name = "MapIntermissionGui"; interGui.ResetOnSpawn = false
interGui.IgnoreGuiInset = true; interGui.DisplayOrder = 60
interGui.Parent = playerGui

local interFrame = Instance.new("Frame")
interFrame.AnchorPoint = Vector2.new(0.5, 0)
interFrame.Position = UDim2.new(0.5, 0, 0, isMobile and 10 or 18)
interFrame.Size = isMobile and UDim2.fromOffset(230, 46) or UDim2.fromOffset(360, 64)
interFrame.BackgroundTransparency = 1
interFrame.BorderSizePixel = 0; interFrame.Visible = false; interFrame.Parent = interGui
-- (groupe : tout le panneau apparaît / disparaît en fondu d'un coup)
local interGroup = Instance.new("CanvasGroup")
interGroup.Size = UDim2.fromScale(1, 1); interGroup.BackgroundTransparency = 1; interGroup.GroupTransparency = 1
interGroup.Parent = interFrame
local _, interFace = stylePanel(interGroup, 12, isMobile and 3 or 5)

local interLabel = Instance.new("TextLabel")
interLabel.BackgroundTransparency = 1; interLabel.Size = UDim2.fromScale(1, 1)
interLabel.FontFace = FREDOKA; interLabel.TextColor3 = WHITE
interLabel.TextScaled = true; interLabel.Text = ""; interLabel.ZIndex = 2
interLabel.Parent = interFace
local ilPad = Instance.new("UIPadding", interLabel)
ilPad.PaddingLeft = UDim.new(0,14); ilPad.PaddingRight = UDim.new(0,14)
ilPad.PaddingTop = UDim.new(0,6);  ilPad.PaddingBottom = UDim.new(0,6)
outline(interLabel, isMobile and 1.2 or 2)

local interVisible = false
local function showInter()
	if interVisible then return end
	interVisible = true
	interFrame.Visible = true
	TweenService:Create(interGroup, TweenInfo.new(0.22), {GroupTransparency = 0}):Play()
end
local function hideInter()
	if not interVisible then return end
	interVisible = false
	local t = TweenService:Create(interGroup, TweenInfo.new(0.2), {GroupTransparency = 1})
	t:Play()
	t.Completed:Connect(function()
		if not interVisible then interFrame.Visible = false end
	end)
end

updateIntermission = function()
	if not inArena then
		hideInter()
		return
	end
	if loadingActive then
		showInter()
		return
	end
	hideInter()
end

--========================================================
-- 2) POPUP DE VOTE
--========================================================
local REF_W, REF_H = 1100, 750
local MIN_SCALE, MAX_SCALE = 0.55, 1.0

local voteGui = Instance.new("ScreenGui")
voteGui.Name = "MapVoteGui"; voteGui.ResetOnSpawn = false; voteGui.IgnoreGuiInset = true
voteGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling  -- 🆕 sinon le fond noir de la carte passe DEVANT son image au reveal
voteGui.DisplayOrder = 50; voteGui.Enabled = false; voteGui.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Size = UDim2.fromScale(1,1); backdrop.AutoButtonColor = false; backdrop.Modal = true
backdrop.Text = ""; backdrop.BackgroundColor3 = Color3.fromRGB(0,0,0); backdrop.BackgroundTransparency = 0.5
backdrop.BorderSizePixel = 0; backdrop.Parent = voteGui

local panel = Instance.new("Frame")
panel.Name = "Panel"; panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(840, 560)
panel.BorderSizePixel = 0; panel.Parent = backdrop
stylePanel(panel, 18, 8)
local menuScale = Instance.new("UIScale", panel)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -150, 0, 50); title.Position = UDim2.new(0, 22, 0, 14)
title.FontFace = FREDOKA; title.TextColor3 = WHITE; title.TextScaled = true; title.ZIndex = 2
title.Text = "Vote for the next map"; title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = panel
outline(title, 3)

-- minuteur dans une petite pastille foncée
local timerBox = Instance.new("Frame")
timerBox.AnchorPoint = Vector2.new(1, 0); timerBox.Position = UDim2.new(1, -18, 0, 16)
timerBox.Size = UDim2.new(0, 104, 0, 46); timerBox.BackgroundColor3 = OUTLINE; timerBox.BackgroundTransparency = 0.25
timerBox.BorderSizePixel = 0; timerBox.ZIndex = 2; timerBox.Parent = panel
Instance.new("UICorner", timerBox).CornerRadius = UDim.new(1, 0)
local tbs = Instance.new("UIStroke", timerBox); tbs.Color = BLUE_RIM; tbs.Thickness = 1.6; tbs.Transparency = 0.35
local voteTimer = Instance.new("TextLabel")
voteTimer.BackgroundTransparency = 1; voteTimer.AnchorPoint = Vector2.new(0.5, 0.5)
voteTimer.Size = UDim2.new(1, -16, 1, -8); voteTimer.Position = UDim2.fromScale(0.5, 0.5)
voteTimer.FontFace = FREDOKA; voteTimer.TextColor3 = YELLOW; voteTimer.TextScaled = true; voteTimer.ZIndex = 3
voteTimer.Text = "0:20"; voteTimer.TextXAlignment = Enum.TextXAlignment.Center; voteTimer.Parent = timerBox
outline(voteTimer, 2)
voteTimer:GetPropertyChangedSignal("Visible"):Connect(function() timerBox.Visible = voteTimer.Visible end)

local grid = Instance.new("Frame")
grid.Name = "Grid"; grid.BackgroundTransparency = 1; grid.AnchorPoint = Vector2.new(0.5, 0)
grid.Position = UDim2.new(0.5, 0, 0, 78); grid.Size = UDim2.new(1, -40, 1, -98); grid.ZIndex = 2; grid.Parent = panel
local gridLayout = Instance.new("UIGridLayout", grid)
gridLayout.CellSize = UDim2.fromOffset(255, 200)
gridLayout.CellPadding = UDim2.fromOffset(16, 16)
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

--========================================================
-- 🏆 GAGNANT DE LA MANCHE : son perso entier, arme favorite levée, à gauche du vote
--    il tient son arme favorite de la manche comme en arène, zoom lent vers son visage
--    Données : MapManager (roundWinner dans le vote) + modèle publié par CombatServer
--    dans ReplicatedStorage/CombatRoundWinner/Winner. Réglages : CombatSettings.RoundWinner
--========================================================
local CS = nil
pcall(function()
	local ws = ReplicatedStorage:WaitForChild("WeaponSystem", 10)
	local m = ws and ws:WaitForChild("CombatSettings", 10)
	if m then CS = require(m) end
end)
local RW = (CS and type(CS.RoundWinner) == "table") and CS.RoundWinner or {}
local WIN_ON = (CS == nil or CS.Enabled ~= false) and RW.Enabled ~= false and RW.ShowInVote ~= false

local GOLD_HI   = Color3.fromRGB(255, 224, 96)
local GOLD_LO   = Color3.fromRGB(242, 148, 28)
local GOLD_EDGE = Color3.fromRGB(150, 80, 10)
local GOLD_OUT  = Color3.fromRGB(84, 40, 4)
local GOLD_RIM  = Color3.fromRGB(255, 244, 200)
local CREAM     = Color3.fromRGB(255, 246, 218)

local PANEL_W, PANEL_W_WIN, PANEL_H = 840, 1100, 560
local WIN_COL_W = 240

local winCol = Instance.new("Frame")
winCol.Name = "RoundWinner"; winCol.Position = UDim2.fromOffset(20, 78); winCol.Size = UDim2.new(0, WIN_COL_W, 1, -98)
winCol.ZIndex = 2; winCol.Visible = false; winCol.Parent = panel
local winScale = Instance.new("UIScale", winCol)
local _, winFace = stylePanel(winCol, 16, 6, GOLD_HI, GOLD_LO, GOLD_EDGE)
do -- liseré et contour accordés à l'or
	local edge = winCol:FindFirstChild("Edge")
	local es = edge and edge:FindFirstChildOfClass("UIStroke")
	if es then es.Color = GOLD_OUT end
	local rim = winFace:FindFirstChild("Rim")
	local rs = rim and rim:FindFirstChildOfClass("UIStroke")
	if rs then rs.Color = GOLD_RIM; rs.Transparency = 0.15 end
end
winFace.ClipsDescendants = true

local function goldOutline(label, thick)
	local st = outline(label, thick)
	st.Color = GOLD_OUT
	return st
end

-- en-tête : trophée + ROUND WINNER
local winHead = Instance.new("TextLabel")
winHead.BackgroundTransparency = 1; winHead.Position = UDim2.fromOffset(10, 8); winHead.Size = UDim2.new(1, -20, 0, 28)
winHead.FontFace = FREDOKA; winHead.TextColor3 = WHITE; winHead.TextScaled = true; winHead.ZIndex = 3
winHead.Text = "ROUND WINNER"; winHead.Parent = winFace
goldOutline(winHead, 2.4)
local trophy
if type(RW.TrophyIcon) == "string" and RW.TrophyIcon ~= "" then
	local id = RW.TrophyIcon:find("://") and RW.TrophyIcon or ("rbxassetid://" .. RW.TrophyIcon)
	trophy = Instance.new("ImageLabel")
	trophy.BackgroundTransparency = 1; trophy.Image = id; trophy.ScaleType = Enum.ScaleType.Fit
	trophy.Size = UDim2.fromOffset(26, 26); trophy.Position = UDim2.fromOffset(10, 9); trophy.ZIndex = 4
	trophy.Parent = winFace
	winHead.Position = UDim2.fromOffset(38, 8); winHead.Size = UDim2.new(1, -48, 0, 28)
else
	winHead.Text = "🏆 ROUND WINNER"
end

-- scène : fond bleu nuit, podium doré, le gagnant en pose de conquérant (son arme favorite levée)
local stage = Instance.new("Frame")
stage.Name = "Stage"; stage.Position = UDim2.fromOffset(8, 40); stage.Size = UDim2.new(1, -16, 0, 236)
stage.BackgroundColor3 = WHITE; stage.BorderSizePixel = 0; stage.ZIndex = 3; stage.ClipsDescendants = true
stage.Parent = winFace
Instance.new("UICorner", stage).CornerRadius = UDim.new(0, 12)
local stG = Instance.new("UIGradient", stage); stG.Rotation = 90
stG.Color = ColorSequence.new(Color3.fromRGB(40, 92, 190), Color3.fromRGB(12, 26, 70))
local stS = Instance.new("UIStroke", stage); stS.Color = GOLD_OUT; stS.Thickness = 2.2
stS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- photo de l'avatar affichée le temps que le modèle 3D arrive
local winPhoto = Instance.new("ImageLabel")
winPhoto.BackgroundTransparency = 1; winPhoto.Size = UDim2.fromScale(1, 1); winPhoto.ScaleType = Enum.ScaleType.Fit
winPhoto.ZIndex = 5; winPhoto.Parent = stage

local winVP = Instance.new("ViewportFrame")
winVP.BackgroundTransparency = 1; winVP.Size = UDim2.fromScale(1, 1); winVP.ZIndex = 6; winVP.ImageTransparency = 1
winVP.Ambient = Color3.fromRGB(165, 165, 185); winVP.LightColor = Color3.fromRGB(255, 242, 214)
winVP.LightDirection = Vector3.new(-0.35, -1, 0.55)
winVP.Parent = stage
local winWorld = Instance.new("WorldModel"); winWorld.Parent = winVP
local winCam = Instance.new("Camera"); winCam.FieldOfView = 32; winCam.Parent = winVP
winVP.CurrentCamera = winCam
do -- podium doré sous ses pieds
	local top = Instance.new("Part")
	top.Shape = Enum.PartType.Cylinder; top.Anchored = true; top.Size = Vector3.new(0.5, 5.2, 5.2)
	top.CFrame = CFrame.new(0, -3.25, 0) * CFrame.Angles(0, 0, math.rad(90))
	top.Color = Color3.fromRGB(255, 200, 60); top.Material = Enum.Material.SmoothPlastic; top.Parent = winWorld
	local base = Instance.new("Part")
	base.Shape = Enum.PartType.Cylinder; base.Anchored = true; base.Size = Vector3.new(0.4, 6, 6)
	base.CFrame = CFrame.new(0, -3.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	base.Color = GOLD_EDGE; base.Material = Enum.Material.SmoothPlastic; base.Parent = winWorld
end

local function txt(parent, pos, size, color, thick, xa)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1; l.Position = pos; l.Size = size; l.FontFace = FREDOKA; l.TextColor3 = color
	l.TextScaled = true; l.ZIndex = 4; l.Text = ""; l.TextXAlignment = xa or Enum.TextXAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd; l.Parent = parent
	if thick then outline(l, thick) end
	return l
end
local function fmtN(n)
	local s = tostring(math.max(0, math.floor(tonumber(n) or 0)))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- 📊 STATS DE LA MANCHE : 3 chiffres, sans cadre (kills · meilleure série · headshots)
local roundRow = Instance.new("Frame")
roundRow.BackgroundTransparency = 1; roundRow.Position = UDim2.fromOffset(8, 284); roundRow.Size = UDim2.new(1, -16, 0, 48)
roundRow.ZIndex = 3; roundRow.Parent = winFace
local winStats = {}
for i, def in ipairs({ { "kills", "KILLS" }, { "best", "STREAK" }, { "headshots", "HEADSHOTS" } }) do
	local col = Instance.new("Frame")
	col.BackgroundTransparency = 1; col.Position = UDim2.new((i - 1) / 3, 0, 0, 0); col.Size = UDim2.new(1 / 3, 0, 1, 0)
	col.ZIndex = 3; col.Parent = roundRow
	winStats[def[1]] = txt(col, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 30), WHITE, 2, nil)
	local l = txt(col, UDim2.fromOffset(0, 31), UDim2.new(1, 0, 0, 14), CREAM, nil, nil)
	l.Text = def[2]
	goldOutline(l, 1.1)
end
winStats.kills.TextColor3 = YELLOW   -- la stat vedette

-- 👤 PROFIL + TOTAUX : photo, nom, @, total kills et total wins
local card = Instance.new("Frame")
card.Position = UDim2.fromOffset(8, 340); card.Size = UDim2.new(1, -16, 0, 104); card.BorderSizePixel = 0
card.BackgroundColor3 = OUTLINE; card.BackgroundTransparency = 0.25; card.ZIndex = 3; card.Parent = winFace
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
local cardS = Instance.new("UIStroke", card); cardS.Color = GOLD_RIM; cardS.Thickness = 1.2; cardS.Transparency = 0.5
cardS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local pfp = Instance.new("ImageLabel")
pfp.Position = UDim2.fromOffset(8, 8); pfp.Size = UDim2.fromOffset(40, 40); pfp.BackgroundColor3 = BLUE_LO
pfp.BorderSizePixel = 0; pfp.ZIndex = 4; pfp.Parent = card
Instance.new("UICorner", pfp).CornerRadius = UDim.new(1, 0)
local pfpS = Instance.new("UIStroke", pfp); pfpS.Color = GOLD_HI; pfpS.Thickness = 2
local winName = txt(card, UDim2.fromOffset(56, 9), UDim2.new(1, -64, 0, 20), WHITE, 1.8, Enum.TextXAlignment.Left)
local winUser = txt(card, UDim2.fromOffset(56, 30), UDim2.new(1, -64, 0, 14), CREAM, nil, Enum.TextXAlignment.Left)

local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(10, 55); divider.Size = UDim2.new(1, -20, 0, 1); divider.BorderSizePixel = 0
divider.BackgroundColor3 = GOLD_RIM; divider.BackgroundTransparency = 0.7; divider.ZIndex = 4; divider.Parent = card
local totals = {}
for i, def in ipairs({ { "kills", "TOTAL KILLS" }, { "wins", "TOTAL WINS" } }) do
	local col = Instance.new("Frame")
	col.BackgroundTransparency = 1; col.Position = UDim2.new((i - 1) / 2, 0, 0, 60); col.Size = UDim2.new(0.5, 0, 0, 40)
	col.ZIndex = 4; col.Parent = card
	totals[def[1]] = txt(col, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 22), WHITE, 1.6, nil)
	local l = txt(col, UDim2.fromOffset(0, 23), UDim2.new(1, 0, 0, 13), CREAM, nil, nil)
	l.Text = def[2]
end

-- reflet qui balaie le panneau doré à l'apparition
local winShine = Instance.new("Frame")
winShine.Size = UDim2.fromScale(1, 1); winShine.BackgroundColor3 = WHITE; winShine.BorderSizePixel = 0
winShine.ZIndex = 9; winShine.Parent = winFace
Instance.new("UICorner", winShine).CornerRadius = UDim.new(0, 16)
local wsG = Instance.new("UIGradient", winShine); wsG.Rotation = 24
wsG.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.44, 1), NumberSequenceKeypoint.new(0.5, 0.55),
	NumberSequenceKeypoint.new(0.56, 1), NumberSequenceKeypoint.new(1, 1),
})
wsG.Offset = Vector2.new(-1.3, 0)

local win = { round = nil, token = 0, model = nil, conn = nil, waitConn = nil, t0 = nil }

local function stopWinnerScene()
	if win.anim then win.anim:Disconnect(); win.anim = nil end
	if win.conn then win.conn:Disconnect(); win.conn = nil end
	if win.waitConn then win.waitConn:Disconnect(); win.waitConn = nil end
	if win.model then win.model:Destroy(); win.model = nil end
	win.t0 = nil
end

-- 🧍 POSE : il regarde la caméra et tient son arme comme en arène (bras droit tendu devant, prise normale)
local HOLD_POSE = {
	["Right Shoulder"] = CFrame.Angles(math.rad(90), 0, 0),   -- bras droit à l'horizontale, arme vers l'avant
}
local function applyPose(m)
	local torso = m:FindFirstChild("Torso")
	if not torso then return end

	-- bras déjà soudés à l'arme par le serveur (pose de ton système d'armes) : rien d'autre à faire
	if torso:FindFirstChild("RightArmWeld") then return end
	for name, R in pairs(HOLD_POSE) do
		local j = torso:FindFirstChild(name)
		if j and j:IsA("Motor6D") then j.C0 = CFrame.new(j.C0.Position) * R * j.C0.Rotation end
	end
end

-- 🎥 CAMÉRA : plusieurs PLANS qui s'enchaînent (coupe franche entre deux plans), chacun avec un
--    mouvement lent ; la suite tourne en boucle tant que l'écran de vote est affiché.
-- (a = angle autour de lui : 0 = de face, − = son côté gauche ; d = distance ; y = point visé ;
--  h = hauteur de l'œil PAR RAPPORT au point visé (− = vue d'en bas) ; fov ; t = durée du plan en s)
local SHOTS = {
	{ t = 5, from = { a = -0.45, h = 0.5,  d = 16,  y = 0.4, fov = 31 },   -- plan large : perso entier
	         to   = { a = -0.36, h = 0.5,  d = 14.5, y = 0.6, fov = 30 } },
	{ t = 5, from = { a = 0.50,  h = -2.2, d = 11,  y = 1.0, fov = 34 },   -- contre-plongée héroïque
	         to   = { a = 0.38,  h = -2.0, d = 10,  y = 1.2, fov = 33 } },
	{ t = 4, from = { a = -0.90, h = 0.4,  d = 7,   y = 1.8, fov = 28 },   -- gros plan visage + arme
	         to   = { a = -0.72, h = 0.5,  d = 6.3, y = 1.9, fov = 27 } },
	{ t = 6, from = { a = 0.90,  h = 1.0,  d = 15,  y = 0.6, fov = 30 },   -- travelling tournant
	         to   = { a = -0.20, h = 1.0,  d = 15,  y = 0.6, fov = 30 } },
}
local SHOTS_TOTAL = 0
for _, sh in ipairs(SHOTS) do SHOTS_TOTAL += sh.t end

local function camAt(t)
	t = t % SHOTS_TOTAL
	local sh = SHOTS[#SHOTS]
	for _, s in ipairs(SHOTS) do
		if t < s.t then sh = s; break end
		t -= s.t
	end
	local x = math.clamp(t / sh.t, 0, 1)
	local e = 0.5 - 0.5 * math.cos(x * math.pi)   -- départ et arrivée doux
	local function L(k) return sh.from[k] + (sh.to[k] - sh.from[k]) * e end
	local a, d = L("a"), L("d")
	local target = Vector3.new(0, L("y"), 0)
	winCam.FieldOfView = L("fov")
	winCam.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(a) * d, L("h"), -math.cos(a) * d), target)
end

local function sceneLoop()
	if win.conn then return end
	win.conn = RunService.RenderStepped:Connect(function()
		if not voteGui.Enabled or not winCol.Visible then
			win.conn:Disconnect(); win.conn = nil
			return
		end
		if not win.model then camAt(0) return end   -- en attente du modèle
		camAt(os.clock() - win.t0)
	end)
end

-- 🏆 ANIMATION DE VICTOIRE (locale, aucun effet en plus) :
--    0 → 0,4 s : il tombe sur le podium (petit amorti à l'atterrissage)
--    0,4 → 1,2 s : il lève son arme vers le ciel (bras droit), poing gauche levé
--    ensuite : pose tenue, IMMOBILE (plus aucun calcul)
--    Les angles se règlent ici (degrés, autour de l'épaule ; + = vers le haut).
local VICTORY = {
	DropHeight = 3,   DropTime = 0.4,
	RaiseStart = 0.4, RaiseTime = 0.8,
	RightUp = 80,     -- bras droit (arme) levé vers le ciel
	LeftUp = 150, LeftOut = 25,   -- poing gauche levé, un peu écarté
}
local function outBack(x)
	local c = 1.4; local u = x - 1
	return 1 + (c + 1) * u * u * u + c * u * u
end
local function startVictory(m)
	if win.anim then win.anim:Disconnect(); win.anim = nil end
	local torso = m:FindFirstChild("Torso")
	local rw = torso and torso:FindFirstChild("RightArmWeld")
	local lw = torso and torso:FindFirstChild("LeftArmWeld")
	local rC0, lC0 = rw and rw.C0, lw and lw.C0
	-- pivot = épaule, dans le repère du torse (R6)
	local function around(pivot, rot) return CFrame.new(pivot) * rot * CFrame.new(-pivot) end
	local rPiv, lPiv = Vector3.new(1, 0.5, 0), Vector3.new(-1, 0.5, 0)
	local t0 = os.clock()
	local function step()
		if not m.Parent then if win.anim then win.anim:Disconnect(); win.anim = nil end return end
		local t = os.clock() - t0
		-- chute + amorti
		local y = 0
		if t < VICTORY.DropTime then
			local x = t / VICTORY.DropTime
			y = VICTORY.DropHeight * (1 - x * x)
		elseif t < VICTORY.DropTime + 0.25 then
			local x = (t - VICTORY.DropTime) / 0.25
			y = -0.25 * math.sin(x * math.pi)
		end
		-- bras levés
		local r = math.clamp((t - VICTORY.RaiseStart) / VICTORY.RaiseTime, 0, 1)
		local k = r > 0 and outBack(r) or 0
		if rw and rw.Parent and rC0 then
			rw.C0 = around(rPiv, CFrame.Angles(math.rad(VICTORY.RightUp * k), 0, 0)) * rC0
		end
		if lw and lw.Parent and lC0 then
			lw.C0 = around(lPiv, CFrame.Angles(math.rad(VICTORY.LeftUp * k), 0, math.rad(-VICTORY.LeftOut * k))) * lC0
		end
		m:PivotTo(CFrame.new(0, y, 0))
		-- geste fini : pose figée, on arrête de calculer
		if t >= math.max(VICTORY.DropTime + 0.25, VICTORY.RaiseStart + VICTORY.RaiseTime)
			and win.anim then
			win.anim:Disconnect(); win.anim = nil
		end
	end
	step()
	win.anim = RunService.RenderStepped:Connect(function()
		if not voteGui.Enabled or not winCol.Visible then return end   -- écran caché : on ne calcule rien
		step()
	end)
end

local function mountModel(src, token)
	if token ~= win.token or win.model then return end
	local ok, m = pcall(function() return src:Clone() end)
	if not ok or not m then return end
	local root = m:FindFirstChild("HumanoidRootPart")
	if root then m.PrimaryPart = root; root.Anchored = true end
	m:PivotTo(CFrame.new())   -- regarde vers la caméra (côté -Z)
	m.Parent = winWorld
	applyPose(m)
	startVictory(m)
	win.model = m
	win.t0 = os.clock()
	TweenService:Create(winPhoto, TweenInfo.new(0.25), { ImageTransparency = 1 }):Play()
	TweenService:Create(winVP, TweenInfo.new(0.3), { ImageTransparency = 0 }):Play()
	if win.conn then win.conn:Disconnect(); win.conn = nil end
	sceneLoop()
end

local function waitModel(info, token)
	local folder = ReplicatedStorage:FindFirstChild("CombatRoundWinner")
	local function check(m)
		if token ~= win.token then return true end
		if m and m.Name == "Winner" and m:GetAttribute("Round") == info.round then
			mountModel(m, token)
			return true
		end
		return false
	end
	if folder and check(folder:FindFirstChild("Winner")) then return end
	if folder then
		win.waitConn = folder.ChildAdded:Connect(function(m)
			if check(m) and win.waitConn then win.waitConn:Disconnect(); win.waitConn = nil end
		end)
	end
end

local function countUp(lbl, target, delay, token)
	target = math.max(0, math.floor(tonumber(target) or 0))
	lbl.Text = "0"
	task.delay(delay, function()
		local t0, dur = os.clock(), 0.6
		while token == win.token and os.clock() - t0 < dur do
			local a = (os.clock() - t0) / dur
			a = 1 - (1 - a) ^ 3
			lbl.Text = fmtN(target * a + 0.5)
			RunService.Heartbeat:Wait()
		end
		if token == win.token then lbl.Text = fmtN(target) end
	end)
end

-- largeur du panneau : colonne du gagnant ou pas
local function layoutWinner(show)
	winCol.Visible = show
	if show then
		panel.Size = UDim2.fromOffset(PANEL_W_WIN, PANEL_H)
		grid.Position = UDim2.new(0.5, (WIN_COL_W + 20) / 2, 0, 78)
		grid.Size = UDim2.new(1, -40 - WIN_COL_W - 20, 1, -98)
	else
		panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
		grid.Position = UDim2.new(0.5, 0, 0, 78)
		grid.Size = UDim2.new(1, -40, 1, -98)
	end
end

local function showWinner(info)
	if not WIN_ON or type(info) ~= "table" or not tonumber(info.userId) or info.userId == 0 then
		win.token += 1
		win.round = nil
		stopWinnerScene()
		layoutWinner(false)
		return
	end
	layoutWinner(true)
	if win.round == info.round and win.model then sceneLoop(); return end   -- même manche : on garde la scène
	win.token += 1
	local token = win.token
	stopWinnerScene()
	win.round = info.round

	pfp.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(info.userId) .. "&w=150&h=150"
	winName.Text = tostring(info.displayName or info.name or "?")
	winUser.Text = "@" .. tostring(info.name or "")
	winPhoto.Image = "rbxthumb://type=Avatar&id=" .. tostring(info.userId) .. "&w=420&h=420"
	winPhoto.ImageTransparency = 0
	winVP.ImageTransparency = 1

	-- apparition : pop + reflet + compteurs qui montent
	winScale.Scale = 0.86
	TweenService:Create(winScale, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	wsG.Offset = Vector2.new(-1.3, 0)
	TweenService:Create(wsG, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.2),
		{ Offset = Vector2.new(1.3, 0) }):Play()
	countUp(winStats.kills, info.kills, 0.15, token)
	countUp(winStats.best, info.best, 0.25, token)
	countUp(winStats.headshots, info.headshots, 0.35, token)
	totals.kills.Text = fmtN(info.totalKills)
	totals.wins.Text = fmtN(info.wins)

	camAt(0)
	waitModel(info, token)
	sceneLoop()
end

-- Responsive
local function computeFactor()
	local cam = Workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize.Y > 1) and cam.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min(vp.X / REF_W, vp.Y / REF_H), MIN_SCALE, MAX_SCALE)
end
local function applyScale() menuScale.Scale = computeFactor() end

local camConn
local function hookCamera()
	local cam = Workspace.CurrentCamera
	if cam then
		if camConn then camConn:Disconnect() end
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end
end
hookCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() hookCamera(); applyScale() end)

-- Cartes de vote
local optionCards = {}
local myVote = nil
local voteRound = 0   -- 🏷️ tour de vote (sert à placer les badges pareil chez tout le monde)

-- 🆕 carte gagnante reparentée pendant le résultat
local resultHero = nil
local function clearResultVisuals()
	if resultHero then
		resultHero:Destroy()
		resultHero = nil
	end
end

local function clearOptions()
	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	table.clear(optionCards)
end

local STROKE_IDLE = { Color = OUTLINE, Thickness = 3, Transparency = 0 }
local function refreshHighlight()
	for k, c in pairs(optionCards) do
		local mine = (k == myVote)
		c.stroke.Color        = mine and GREEN or STROKE_IDLE.Color
		c.stroke.Thickness    = mine and 4.5 or STROKE_IDLE.Thickness
		c.stroke.Transparency = 0
		if c.check then c.check.Visible = mine end
	end
end

--========================================================
-- 🏷️ BADGE : la photo du votant se pose sur la map en « pop »
--========================================================
-- position / inclinaison données par le serveur (Script MapVoteBadges) : identiques chez TOUS les joueurs, une
-- nouvelle à chaque clic (même sur la même map), et jamais deux photos qui se touchent
local badgeState = {}       -- [tostring(uid)] = { k = map, x, y (0..1 de la carte), r = degrés, n = n° de pose }
local badgeRemote = nil
local syncBadges            -- (plus bas)
task.spawn(function()
	badgeRemote = ReplicatedStorage:WaitForChild("MapVoteBadges", 15)
	if not badgeRemote then return end
	badgeRemote.OnClientEvent:Connect(function(st)
		if type(st) ~= "table" then return end
		badgeState = st
		syncBadges()
	end)
	badgeRemote:FireServer("sync")
end)

local CARD_W, CARD_H = 255, 200
local BADGE = 46
local MIN_GAP = 52          -- px entre deux centres : jamais collés
-- repli (script serveur absent) : place libre tirée au hasard sur la carte
local function fallbackPlace(card, uid, key)
	local seed = 5381
	local s = tostring(uid) .. "|" .. tostring(key) .. "|" .. tostring(voteRound)
	for i = 1, #s do seed = (seed * 33 + string.byte(s, i)) % 2147483647 end
	local rng = Random.new(seed)
	local taken = {}
	for u, b in pairs(card.voters) do
		if u ~= uid then table.insert(taken, Vector2.new(b.x * CARD_W, b.y * CARD_H)) end
	end
	local best, bestD
	for _ = 1, 60 do
		local c = { x = rng:NextNumber(0.13, 0.87), y = rng:NextNumber(0.17, 0.68) }
		local d = math.huge
		for _, o in ipairs(taken) do d = math.min(d, (o - Vector2.new(c.x * CARD_W, c.y * CARD_H)).Magnitude) end
		if d >= MIN_GAP then best = c; break end
		if not bestD or d > bestD then best, bestD = c, d end
	end
	best.r = rng:NextNumber(-24, 24); best.n = 0
	return best
end

-- 🏷️ BADGE : la photo du votant se pose sur la map en « pop »
local function makeVoterPfp(card, uid, pl)
	local holder = Instance.new("Frame")
	holder.Name = "pfp_" .. uid
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(pl.x, pl.y)
	holder.Size = UDim2.fromOffset(BADGE, BADGE)
	holder.Rotation = pl.r + ((pl.r >= 0) and 28 or -28)
	holder.ZIndex = 6
	holder.Parent = card.badges
	-- ombre portée
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"; shadow.BorderSizePixel = 0
	shadow.BackgroundColor3 = Color3.new(0, 0, 0); shadow.BackgroundTransparency = 1
	shadow.Position = UDim2.fromOffset(3, 4); shadow.Size = UDim2.fromScale(1, 1); shadow.ZIndex = 6
	shadow.Parent = holder
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(1, 0)
	-- badge : anneau blanc épais + contour foncé, la photo au centre
	local ring = Instance.new("Frame")
	ring.Name = "Ring"; ring.BorderSizePixel = 0; ring.BackgroundColor3 = WHITE
	ring.Size = UDim2.fromScale(1, 1); ring.ZIndex = 7; ring.Parent = holder
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	local rst = Instance.new("UIStroke", ring); rst.Color = OUTLINE; rst.Thickness = 2.2
	local pic = Instance.new("ImageLabel")
	pic.Name = "Pic"; pic.BorderSizePixel = 0; pic.BackgroundColor3 = BLUE_LO
	pic.AnchorPoint = Vector2.new(0.5, 0.5); pic.Position = UDim2.fromScale(0.5, 0.5)
	pic.Size = UDim2.new(1, -8, 1, -8); pic.ZIndex = 8
	pic.Image = "rbxthumb://type=AvatarHeadShot&id=" .. uid .. "&w=150&h=150"
	pic.Parent = ring
	Instance.new("UICorner", pic).CornerRadius = UDim.new(1, 0)
	-- POP : arrive gros et transparent, s'écrase sur la carte, rebondit, se pose penché
	local sc = Instance.new("UIScale", holder); sc.Scale = 2.4
	ring.BackgroundTransparency = 1; pic.ImageTransparency = 1; pic.BackgroundTransparency = 1; rst.Transparency = 1
	local fadeIn = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, fadeIn, {BackgroundTransparency = 0}):Play()
	TweenService:Create(pic, fadeIn, {ImageTransparency = 0, BackgroundTransparency = 0}):Play()
	TweenService:Create(rst, fadeIn, {Transparency = 0}):Play()
	TweenService:Create(holder, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = pl.r}):Play()
	local down = TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.86})
	down:Play()
	down.Completed:Connect(function()
		if not holder.Parent then return end
		TweenService:Create(sc, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		TweenService:Create(shadow, TweenInfo.new(0.2), {BackgroundTransparency = 0.6}):Play()
	end)
	return { h = holder, n = pl.n, x = pl.x, y = pl.y }
end
-- badge retiré (vote changé, ou il se repose ailleurs) : petit saut puis disparaît
local function removeVoterPfp(holder)
	local sc = holder:FindFirstChildOfClass("UIScale")
	local ti = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if sc then TweenService:Create(sc, ti, {Scale = 0.3}):Play() end
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("ImageLabel") then TweenService:Create(d, ti, {ImageTransparency = 1, BackgroundTransparency = 1}):Play()
		elseif d:IsA("Frame") then TweenService:Create(d, ti, {BackgroundTransparency = 1}):Play()
		elseif d:IsA("UIStroke") then TweenService:Create(d, ti, {Transparency = 1}):Play() end
	end
	task.delay(0.16, function() holder:Destroy() end)
end

-- affiche les badges : qui a voté quoi = TON serveur (liste des votants) ; où = MapVoteBadges
syncBadges = function()
	for key, c in pairs(optionCards) do
		local present = {}
		for _, uid in ipairs(c.list or {}) do present[uid] = true end
		for uid, b in pairs(c.voters) do
			if not present[uid] then removeVoterPfp(b.h); c.voters[uid] = nil end
		end
		for _, uid in ipairs(c.list or {}) do
			local st = badgeState[tostring(uid)]
			local pl = (type(st) == "table" and st.k == key) and st or nil
			local b = c.voters[uid]
			if not b then
				c.voters[uid] = makeVoterPfp(c, uid, pl or fallbackPlace(c, uid, key))
			elseif pl and b.n ~= pl.n then
				-- re-clic (même map) : la photo s'envole et se repose ailleurs
				removeVoterPfp(b.h)
				c.voters[uid] = makeVoterPfp(c, uid, pl)
			end
		end
	end
end

local function applyVoters(voters)
	if not voters then return end
	for key, c in pairs(optionCards) do
		local list = voters[key] or {}
		c.list = list
		local n = #list
		c.countLabel.Text = (n == 1) and "1 vote" or (tostring(n) .. " votes")
	end
	syncBadges()
end

local function buildOption(info, order)
	local card = Instance.new("TextButton")
	card.Name = "Opt_" .. info.key; card.AutoButtonColor = false
	card.BackgroundColor3 = BLUE_EDGE; card.Text = ""; card.LayoutOrder = order
	card.ClipsDescendants = true; card.Parent = grid
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	local hov = Instance.new("UIScale", card)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = STROKE_IDLE.Color; stroke.Thickness = STROKE_IDLE.Thickness; stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	-- image plein cadre
	local img = Instance.new("ImageLabel")
	img.BackgroundColor3 = Color3.fromRGB(14, 16, 20); img.BorderSizePixel = 0
	img.Size = UDim2.fromScale(1, 1)
	img.Image = info.Image or ""; img.ScaleType = Enum.ScaleType.Crop; img.Parent = card
	Instance.new("UICorner", img).CornerRadius = UDim.new(0, 14)

	-- liseré clair intérieur (comme les panneaux)
	local rim = Instance.new("Frame")
	rim.BackgroundTransparency = 1; rim.AnchorPoint = Vector2.new(0.5, 0.5); rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.new(1, -4, 1, -4); rim.ZIndex = 3; rim.Parent = card
	Instance.new("UICorner", rim).CornerRadius = UDim.new(0, 12)
	local rimS = Instance.new("UIStroke", rim); rimS.Color = BLUE_RIM; rimS.Thickness = 1.6; rimS.Transparency = 0.35

	-- dégradé bas
	local shade = Instance.new("Frame")
	shade.AnchorPoint = Vector2.new(0, 1); shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.new(1, 0, 0, 62); shade.BackgroundColor3 = OUTLINE
	shade.BorderSizePixel = 0; shade.ZIndex = 2; shade.Parent = card
	Instance.new("UICorner", shade).CornerRadius = UDim.new(0, 14)
	local grad = Instance.new("UIGradient", shade); grad.Rotation = 90
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1; nameLbl.AnchorPoint = Vector2.new(0, 1)
	nameLbl.Position = UDim2.new(0, 12, 1, -9); nameLbl.Size = UDim2.new(1, -104, 0, 26)
	nameLbl.FontFace = FREDOKA; nameLbl.TextColor3 = WHITE; nameLbl.ZIndex = 4
	nameLbl.TextScaled = true; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Text = info.Name; nameLbl.Parent = card
	outline(nameLbl, 2.2)

	-- compteur dans une petite pastille
	local countBox = Instance.new("Frame")
	countBox.AnchorPoint = Vector2.new(1, 1); countBox.Position = UDim2.new(1, -10, 1, -10)
	countBox.Size = UDim2.new(0, 82, 0, 26); countBox.BackgroundColor3 = OUTLINE; countBox.BackgroundTransparency = 0.2
	countBox.BorderSizePixel = 0; countBox.ZIndex = 4; countBox.Parent = card
	Instance.new("UICorner", countBox).CornerRadius = UDim.new(1, 0)
	local countLbl = Instance.new("TextLabel")
	countLbl.BackgroundTransparency = 1; countLbl.AnchorPoint = Vector2.new(0.5, 0.5)
	countLbl.Position = UDim2.fromScale(0.5, 0.5); countLbl.Size = UDim2.new(1, -12, 1, -6)
	countLbl.FontFace = FREDOKA; countLbl.TextColor3 = YELLOW; countLbl.ZIndex = 5
	countLbl.TextScaled = true; countLbl.TextXAlignment = Enum.TextXAlignment.Center
	countLbl.Text = "0 votes"; countLbl.Parent = countBox
	outline(countLbl, 1.6)

	-- ✓ sur la map que TU as votée
	local check = Instance.new("TextLabel")
	check.Name = "Check"; check.AnchorPoint = Vector2.new(1, 0); check.Position = UDim2.new(1, -8, 0, 8)
	check.Size = UDim2.fromOffset(34, 34); check.BackgroundColor3 = GREEN; check.BorderSizePixel = 0
	check.FontFace = FREDOKA; check.Text = "✓"; check.TextColor3 = WHITE; check.TextScaled = true
	check.ZIndex = 9; check.Visible = false; check.Parent = card
	Instance.new("UICorner", check).CornerRadius = UDim.new(1, 0)
	local cks = Instance.new("UIStroke", check); cks.Color = OUTLINE; cks.Thickness = 2
	cks.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	-- calque des badges des votants (posés sur l'image)
	local badges = Instance.new("Frame")
	badges.Name = "Badges"; badges.BackgroundTransparency = 1
	badges.Size = UDim2.fromScale(1, 1); badges.ZIndex = 6; badges.Parent = card

	-- hover réactif
	card.MouseEnter:Connect(function()
		if phase ~= "vote" then return end
		TweenService:Create(hov, TweenInfo.new(0.12), {Scale = 1.04}):Play()
		if info.key ~= myVote then
			TweenService:Create(stroke, TweenInfo.new(0.12), {Color = YELLOW}):Play()
		end
	end)
	card.MouseLeave:Connect(function()
		if phase ~= "vote" then return end -- 🆕 ne pas casser le zoom de la gagnante au résultat
		TweenService:Create(hov, TweenInfo.new(0.12), {Scale = 1}):Play()
		if info.key ~= myVote then
			TweenService:Create(stroke, TweenInfo.new(0.12), {Color = STROKE_IDLE.Color}):Play()
		end
	end)
	-- petit enfoncement au clic
	card.MouseButton1Down:Connect(function()
		if phase ~= "vote" then return end
		TweenService:Create(hov, TweenInfo.new(0.06), {Scale = 0.97}):Play()
	end)

	card.MouseButton1Click:Connect(function()
		if not voteGui.Enabled or phase ~= "vote" or not inArena then return end
		TweenService:Create(hov, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.04}):Play()
		myVote = info.key
		voteCastEvent:FireServer(info.key)
		refreshHighlight()
	end)

	optionCards[info.key] = { frame = card, hov = hov, stroke = stroke, check = check,
		countLabel = countLbl, nameLabel = nameLbl, badges = badges, pfpRow = badges, voters = {}, list = {} }
end

local function openVote(options, voters, roundWinner)
	clearOptions(); clearResultVisuals(); myVote = nil  -- 🆕 nettoie la gagnante restée du cycle précédent
	if roundWinner ~= "keep" then showWinner(roundWinner) end   -- 🏆 colonne du gagnant (ou panneau normal s'il n'y en a pas)
	voteRound = math.floor(endsAt)
	if badgeRemote then badgeRemote:FireServer("sync") end
	for i, info in ipairs(options) do buildOption(info, i) end
	applyVoters(voters); applyScale()
	voteGui.Enabled = true
	local f = computeFactor()
	menuScale.Scale = f * 0.92
	TweenService:Create(menuScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = f}):Play()
end

--========================================================
-- 🆕 RÉSULTAT : perdantes disparaissent + gagnante glisse au centre
--========================================================
local function fadeCardOut(card)
	local ti = TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("ImageLabel") or d:IsA("ImageButton") then
			TweenService:Create(d, ti, {ImageTransparency = 1, BackgroundTransparency = 1}):Play()
		elseif d:IsA("TextLabel") or d:IsA("TextButton") then
			TweenService:Create(d, ti, {TextTransparency = 1, BackgroundTransparency = 1}):Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, ti, {BackgroundTransparency = 1}):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, ti, {Transparency = 1}):Play()
		end
	end
	TweenService:Create(card, ti, {BackgroundTransparency = 1}):Play()
	local sc = card:FindFirstChildWhichIsA("UIScale")
	if sc then TweenService:Create(sc, ti, {Scale = 0.92}):Play() end
	task.delay(0.32, function()
		if card and card.Parent then card.Visible = false end
	end)
end

--========================================================
-- 🆕 Effet doré sobre sur la gagnante (bordure or + reflet qui balaie)
--========================================================
local function playGoldWin(winCard)
	local card   = winCard.frame
	local stroke = winCard.stroke

	-- bordure dorée qui se pose
	stroke.Color = Color3.fromRGB(255, 205, 90)
	TweenService:Create(stroke, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Thickness = 4.5, Transparency = 0}):Play()

	-- puis "respiration" dorée continue (très douce)
	task.delay(0.32, function()
		if not stroke or not stroke.Parent then return end
		TweenService:Create(stroke,
			TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{Thickness = 5.2, Transparency = 0.18}):Play()
	end)

	-- reflet doré qui balaie l'image (une seule passe)
	local shimmer = Instance.new("Frame")
	shimmer.Name = "GoldShimmer"
	shimmer.Size = UDim2.fromScale(1, 1)
	shimmer.BackgroundColor3 = Color3.fromRGB(255, 225, 150)
	shimmer.BackgroundTransparency = 0
	shimmer.BorderSizePixel = 0
	shimmer.ZIndex = 5
	shimmer.Parent = card
	Instance.new("UICorner", shimmer).CornerRadius = UDim.new(0, 14)
	local sgrad = Instance.new("UIGradient", shimmer)
	sgrad.Rotation = 20
	sgrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.50, 0.55), -- la bande claire
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1.00, 1),
	})
	sgrad.Offset = Vector2.new(-1.2, 0)  -- bande hors cadre au départ (pas de flash)
	task.delay(0.25, function()
		if not shimmer or not shimmer.Parent then return end
		local sweep = TweenService:Create(sgrad,
			TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Offset = Vector2.new(1.2, 0)})
		sweep:Play()
		sweep.Completed:Connect(function()
			if shimmer then shimmer:Destroy() end
		end)
	end)
end

local function playWinnerReveal(winnerKey)
	if resultHero then return end
	local winCard = optionCards[winnerKey]
	if not winCard or not winCard.frame then return end
	local card = winCard.frame

	local scale = menuScale.Scale
	if scale <= 0 then scale = 1 end

	-- centre & taille actuels en coords LOCALES (non scalées) du panel → zéro saut
	local centerAbs   = card.AbsolutePosition + card.AbsoluteSize / 2
	local localCenter = (centerAbs - panel.AbsolutePosition) / scale
	local localW      = card.AbsoluteSize.X / scale
	local localH      = card.AbsoluteSize.Y / scale

	-- les perdantes disparaissent
	for k, c in pairs(optionCards) do
		if k ~= winnerKey and c.frame then
			fadeCardOut(c.frame)
		end
	end

	-- la gagnante sort de la grille pour glisser librement
	card.Parent = panel
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Size = UDim2.fromOffset(localW, localH)
	card.Position = UDim2.fromOffset(localCenter.X, localCenter.Y)
	card.ZIndex = 5
	resultHero = card

	-- 🆕 effet de victoire doré (bordure + reflet)
	playGoldWin(winCard)

	-- cible : centre de la zone de grille (avec ou sans la colonne du gagnant)
	local gridCenter = (grid.AbsolutePosition + grid.AbsoluteSize / 2 - panel.AbsolutePosition) / scale
	local targetX = gridCenter.X
	local targetY = gridCenter.Y

	-- glisse au centre + léger zoom sobre
	TweenService:Create(card, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{Position = UDim2.fromOffset(targetX, targetY)}):Play()
	TweenService:Create(winCard.hov, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{Scale = 1.12}):Play()
end

local function setPhase(p)
	phase = p
	pill.Visible = inArena and (p == "countdown")
end

local function updateVisibility()
	pill.Visible = inArena and (phase == "countdown")
	if not inArena then
		if voteGui.Enabled then voteGui.Enabled = false end
	elseif phase == "vote" and lastVote and not voteGui.Enabled then
		openVote(lastVote.options or {}, lastVote.voters, lastVote.roundWinner)
	end
	updateIntermission()
end

-- ✅ savoir si on est en arène
hideUIEvent.OnClientEvent:Connect(function(hide)
	inArena = hide and true or false
	updateVisibility()
end)

--========================================================
-- Tick (compte à rebours + timer de vote)
--========================================================
RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	if phase == "countdown" then
		local remain = endsAt - now
		pillLabel.Text = "Next Map in : " .. fmt(remain)
		-- les 10 dernières secondes : la pastille passe au rouge
		local hot = remain <= 10
		pillFill.Color = hot and ColorSequence.new(Color3.fromRGB(255, 110, 100), Color3.fromRGB(212, 36, 44))
			or ColorSequence.new(BLUE_HI, BLUE_LO)
	elseif phase == "vote" then
		voteTimer.Text = fmt(endsAt - now)
		voteTimer.TextColor3 = (endsAt - now <= 5) and RED or YELLOW
	elseif phase == "result" then
		if now >= endsAt and not loadingActive then
			loadingActive = true
			updateIntermission()
		end
	end

	if loadingActive and interVisible then
		local n = math.floor((now % 1.5) / 0.5)
		interLabel.Text = "Chargement de la nouvelle map" .. string.rep(".", n + 1)
	end
end)

--========================================================
-- Réception de l'état serveur
--========================================================
voteStateEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	if data.endsAt then endsAt = data.endsAt end

	if data.phase == "countdown" then
		setPhase("countdown"); lastVote = nil
		loadingActive = false
		clearResultVisuals()    -- 🆕 enlève la gagnante restée au centre
		updateIntermission()
		if voteGui.Enabled then
			TweenService:Create(menuScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = computeFactor() * 0.9}):Play()
			task.delay(0.18, function() if phase == "countdown" then voteGui.Enabled = false end end)
		end
		if inArena then openVote(data.options or {}, data.voters, "keep") end   -- (se ferme : pas de saut de largeur)
		updateIntermission()

	elseif data.phase == "vote" then
		setPhase("vote"); lastVote = data
		title.Text = "Vote for the next map"; voteTimer.Visible = true
		if inArena then openVote(data.options or {}, data.voters, data.roundWinner) end

	elseif data.phase == "tally" then
		applyVoters(data.voters)

	elseif data.phase == "result" then
		setPhase("result")
		applyVoters(data.voters)
		resultMapName = data.winnerName or data.winner
		loadingActive = false
		updateIntermission()
		title.Text = "Next map: " .. (data.winnerName or data.winner or "?")
		voteTimer.Visible = false
		playWinnerReveal(data.winner)   -- 🆕 perdantes disparaissent, gagnante glisse au centre
	end
end)