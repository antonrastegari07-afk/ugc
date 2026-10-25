-- RookieGuide : LocalScript dans StarterPlayer > StarterPlayerScripts.
-- Ses ModuleScripts doivent rester enfants de ce LocalScript.
-- Nécessite UIFocusSystem v4 dans StarterGui. Un seul propriétaire de visibilité.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local GS = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local C = require(script:WaitForChild("RookieConfig"))
local Flow = require(script:WaitForChild("GuideFlow"))
local Geometry = require(script:WaitForChild("SpotlightGeometry"))
if _G.__RookieGuideLoaded then return end
_G.__RookieGuideLoaded = true

-- 📝 Textes de la fin du guide (boutique ouverte). Courts et EXACTS :
--    ce sont de vrais objets d'avatar Roblox, obtenus avec des points gagnés
--    en jouant, confirmés par la fenêtre officielle de Roblox, rangés dans
--    l'inventaire Roblox. Aucune promesse de gratuité, de Robux ou de gain garanti.
--    (modifiables dans RookieConfig.Text : InfoTitle / InfoBody / InfoNote / InfoClose)
local INFO_TEXT = {
	InfoTitle = "UGC ITEMS FOR YOUR AVATAR",
	InfoBody  = "Earn points by playing, then spend them here on Roblox avatar items.",
	InfoNote  = "Confirm the Roblox prompt and the item goes to your Roblox inventory. Limited stock.",
	InfoClose = "Close the shop with the X to keep playing.",
}
local function infoText(key) return (C.Text and C.Text[key]) or INFO_TEXT[key] end
local INFO_AUTO_FINISH = 25   -- s : sans action, le guide se termine tout seul (boutique laissée ouverte)

local generation, current, disposed = 0, nil, false
local start, finish, refresh, nextCheckpoint, resolveShop, setSpotlight
local SKIP_ACTION = "RookieGuideSkip"
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function connect(s, signal, callback)
	local c = signal:Connect(callback)
	table.insert(s.connections, c)
	return c
end
local function disconnect(list)
	for _, c in ipairs(list) do c:Disconnect() end
	table.clear(list)
end
local function alive(s) return current == s and not s.finished and not disposed end
local function padActive() return UIS:GetLastInputType().Name:find("Gamepad", 1, true) ~= nil end
local function findPath(root, path)
	for _, name in ipairs(path) do root = root and root:FindFirstChild(name) end
	return root
end
local function text(parent, value, size)
	local label = make("TextLabel", { BackgroundTransparency = 1, Text = value,
		Font = C.Style.Font, TextColor3 = Color3.new(1, 1, 1), TextSize = size,
		TextWrapped = true, TextStrokeTransparency = 1, ZIndex = 5 }, parent)
	make("UIStroke", { Color = Color3.new(0, 0, 0),
		Thickness = math.min(C.Style.TextOutline, size / 9),
		Transparency = C.Style.TextOutlineTransparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)
	return label
end
local function button(parent, value)
	local b = make("TextButton", { Text = value, Font = C.Style.Font, TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(24, 27, 31),
		BackgroundTransparency = 0.08, AutoButtonColor = true, Selectable = true,
		Size = UDim2.fromOffset(144, 48), ZIndex = 20 }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.35,
		Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	return b
end

-- Découpe, arrondi, halo et flèche du tutoriel ; les lettres ont leur contour.
-- Recalcul seulement quand la cible/la taille d'écran change, coalescé.
-- opts.extra = objets à inclure dans le cadre vert (ex. le X de la boutique)
-- opts.noDim = true → pas de voile noir : rien ne bloque les clics autour
setSpotlight = function(s, target, clickable, opts)
	opts = opts or {}
	disconnect(s.spotConnections)
	s.spotVersion = (s.spotVersion or 0) + 1
	local version, queued = s.spotVersion, false
	s.spotTarget = target
	local function layout()
		queued = false
		if not alive(s) or s.spotVersion ~= version then return end
		local o = s.spotTarget
		local size, origin = s.probe.AbsoluteSize, s.probe.AbsolutePosition
		local w, h = size.X, size.Y
		local valid = o and o.Parent and o.Visible and o.AbsoluteSize.X > 1 and o.AbsoluteSize.Y > 1
		local rect
		if valid then
			local p, z, margin = o.AbsolutePosition - origin, o.AbsoluteSize, C.Style.HolePadding
			-- le cadre englobe aussi les objets « extra » visibles (le X qui dépasse)
			local x0, y0, x1, y1 = p.X, p.Y, p.X + z.X, p.Y + z.Y
			for _, e in ipairs(opts.extra or {}) do
				if e and e.Parent and e.Visible and e.AbsoluteSize.X > 1 then
					local ep = e.AbsolutePosition - origin
					x0, y0 = math.min(x0, ep.X), math.min(y0, ep.Y)
					x1, y1 = math.max(x1, ep.X + e.AbsoluteSize.X), math.max(y1, ep.Y + e.AbsoluteSize.Y)
				end
			end
			rect = Geometry.layout(w, h, x0, y0, x1 - x0, y1 - y0, margin,
				C.Style.HoleCornerRadius, s.cornerSteps)
			valid = rect ~= nil
		end
		for _, block in ipairs(s.blocks) do block.Visible = valid and not opts.noDim end
		s.border.Visible, s.proxy.Visible = valid, valid and clickable == true
		s.arrowAnchor.Visible = valid and clickable == true
		if valid ~= s.spotShown then
			s.spotShown = valid
			if valid then
				for _, block in ipairs(s.blocks) do
					block.BackgroundTransparency = 1
					TweenService:Create(block, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
						{ BackgroundTransparency = C.Style.DimTransparency }):Play()
				end
				s.haloTween:Play()
			else s.haloTween:Cancel() end
		end
		if s.arrowAnchor.Visible ~= s.arrowShown then
			s.arrowShown = s.arrowAnchor.Visible
			if s.arrowShown then s.arrowTween:Play() else s.arrowTween:Cancel() end
		end
		if not valid then return end
		for i, r in ipairs(rect.pieces) do
			s.blocks[i].Position = UDim2.fromOffset(r[1], r[2])
			s.blocks[i].Size = UDim2.fromOffset(r[3], r[4])
		end
		s.border.Position, s.border.Size = UDim2.fromOffset(rect.x, rect.y), UDim2.fromOffset(rect.w, rect.h)
		s.borderCorner.CornerRadius = UDim.new(0, rect.radius)
		s.proxy.Position, s.proxy.Size = s.border.Position, s.border.Size
		-- Même flèche rouge diagonale ; retournée près d'un bord pour rester lisible.
		local flipX, flipY = rect.x + rect.w + 70 > w, rect.y + rect.h + 70 > h
		s.arrowAnchor.Position = UDim2.fromOffset(flipX and rect.x or rect.x + rect.w, flipY and rect.y or rect.y + rect.h)
		s.arrowAnchor.Rotation = flipX and (flipY and 180 or 90) or (flipY and 270 or 0)
		-- La consigne évite le bouton mis en évidence. SKIP reste en haut.
		if s.flow.phase == "shop" then
			local bottom = rect.y < h * 0.40
			s.message.AnchorPoint = Vector2.new(0.5, bottom and 1 or 0)
			s.message.Position = bottom and UDim2.new(0.5, 0, 1, -16) or UDim2.new(0.5, 0, 0, 68)
		end
	end
	local function queue()
		if queued then return end
		queued = true
		task.defer(layout)
	end
	local function watch(object, property)
		table.insert(s.spotConnections, object:GetPropertyChangedSignal(property):Connect(queue))
	end
	watch(s.probe, "AbsoluteSize")
	watch(s.probe, "AbsolutePosition")
	if target then
		watch(target, "AbsolutePosition")
		watch(target, "AbsoluteSize")
		watch(target, "Visible")
		table.insert(s.spotConnections, target.AncestryChanged:Connect(queue))
	end
	for _, e in ipairs(opts.extra or {}) do
		watch(e, "AbsolutePosition")
		watch(e, "AbsoluteSize")
		watch(e, "Visible")
	end
	layout()
end

local function buildUI(s)
	pg:SetAttribute("RookieGuidePhase", "play")
	s.overlay = make("ScreenGui", { Name = "RookieGuideUI", ResetOnSpawn = false,
		Enabled = false, IgnoreGuiInset = true, DisplayOrder = C.Style.DisplayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, pg)
	s.overlay.ScreenInsets = Enum.ScreenInsets.None
	s.overlay.ClipToDeviceSafeArea = false
	s.overlay.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	s.probe = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, s.overlay)
	s.blocks = {}
	s.cornerSteps = math.clamp(math.floor(C.Style.HoleCornerSteps), 1, 16)
	for i = 1, 4 + 4 * s.cornerSteps do
		s.blocks[i] = make("TextButton", { Text = "", BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = C.Style.DimTransparency, BorderSizePixel = 0,
			Selectable = false, AutoButtonColor = false, Visible = false, ZIndex = i <= 4 and 1 or 4 }, s.overlay)
	end
	s.border = make("Frame", { BackgroundTransparency = 1, Visible = false, Active = false, ZIndex = 5 }, s.overlay)
	s.borderCorner = make("UICorner", { CornerRadius = UDim.new(0, C.Style.HoleCornerRadius) }, s.border)
	make("UIStroke", { Color = C.Style.Green, Thickness = C.Style.HoleBorder }, s.border)
	local halo = make("Frame", { Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 10, 1, 10),
		BackgroundTransparency = 1, Active = false, ZIndex = 5 }, s.border)
	make("UICorner", { CornerRadius = UDim.new(0, C.Style.HoleCornerRadius + 5) }, halo)
	local haloStroke = make("UIStroke", { Color = C.Style.Green, Thickness = 2, Transparency = 0.85 }, halo)
	s.haloTween = TweenService:Create(haloStroke, TweenInfo.new(1.1, Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut, -1, true), { Transparency = 0.35 })
	s.arrowAnchor = make("Frame", { Name = "ArrowAnchor", Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1, Visible = false, ZIndex = 6 }, s.overlay)
	local arrow = make("Frame", { Name = "Arrow", Size = UDim2.fromOffset(60, 60),
		Position = UDim2.fromOffset(-9, -9), BackgroundTransparency = 1, ZIndex = 6 }, s.arrowAnchor)
	for _, spec in ipairs({
		{ Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), Vector2.new(58, 10), 45 },
		{ Vector2.new(0, 0.5), UDim2.fromOffset(2, 8), Vector2.new(28, 10), 0 },
		{ Vector2.new(0.5, 0), UDim2.fromOffset(8, 2), Vector2.new(10, 28), 0 },
	}) do
		local bar = make("Frame", { AnchorPoint = spec[1], Position = spec[2],
			Size = UDim2.fromOffset(spec[3].X, spec[3].Y), Rotation = spec[4], BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(255, 50, 50), ZIndex = 6 }, arrow)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, bar)
	end
	s.arrowTween = TweenService:Create(arrow, TweenInfo.new(1.12, Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(9, 9) })
	-- Le clic ouvre seulement la fenêtre ; aucun achat n'est déclenché ici.
	-- Ce bouton transparent rend le même geste accessible à la manette.
	s.proxy = make("TextButton", { Name = "OpenUGC", Text = "", BackgroundTransparency = 1,
		AutoButtonColor = false, Selectable = true, Visible = false, ZIndex = 3 }, s.overlay)
	s.hud = make("ScreenGui", { Name = "RookieGuideHUD", ResetOnSpawn = false,
		Enabled = false, DisplayOrder = C.Style.DisplayOrder + 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, pg)
	s.hud.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	s.hud.ClipToDeviceSafeArea = true
	s.hud.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	s.safe = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, s.hud)
	s.skip = button(s.safe, C.Text.Skip)
	s.skip.AnchorPoint, s.skip.Position = Vector2.new(1, 0), UDim2.new(1, -12, 0, 12)
	s.padIcon = make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(25, 25),
		Position = UDim2.new(0, 12, 0.5, -12), Visible = false, ZIndex = 21 }, s.skip)
	s.message = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 68),
		Size = UDim2.new(1, -24, 0, 100), BackgroundTransparency = 1 }, s.safe)
	make("UISizeConstraint", { MaxSize = Vector2.new(760, 260) }, s.message)
	-- Fond du texte : noir semi-transparent, arrondi, qui s'efface en dégradé
	-- sur les deux côtés (le texte ressort sans « carte » aux bords durs).
	s.backdrop = make("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = C.Style.BackdropTransparency or 0.45,
		BorderSizePixel = 0, Active = false, ZIndex = 1 }, s.message)
	make("UICorner", { CornerRadius = UDim.new(0, 18) }, s.backdrop)
	make("UIGradient", { Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 1),
		NumberSequenceKeypoint.new(0.18, 0),
		NumberSequenceKeypoint.new(0.82, 0),
		NumberSequenceKeypoint.new(1.00, 1),
	}) }, s.backdrop)
	s.title = text(s.message, "", C.Style.MaxTextSize)
	s.title.Position, s.title.Size = UDim2.fromOffset(12, 10), UDim2.new(1, -24, 0, 72)
	for _, label in ipairs({s.title}) do
		label.TextScaled = true
		make("UITextSizeConstraint", { MinTextSize = 22, MaxTextSize = C.Style.MaxTextSize }, label)
	end
	s.detail = text(s.message, infoText("InfoBody"), 24)
	s.detail.Visible = false
	s.detail.TextScaled = true
	make("UITextSizeConstraint", { MinTextSize = 17, MaxTextSize = 24 }, s.detail)
	s.note = text(s.message, infoText("InfoNote"), 20)
	s.note.TextColor3 = Color3.fromRGB(225, 228, 232)
	s.note.Visible = false
	s.note.TextScaled = true
	make("UITextSizeConstraint", { MinTextSize = 15, MaxTextSize = 20 }, s.note)
	-- consigne de sortie, en vert : fermer avec le X = continuer à jouer
	s.closeHint = text(s.message, infoText("InfoClose"), 22)
	s.closeHint.TextColor3 = C.Style.Green
	s.closeHint.Visible = false
	s.closeHint.TextScaled = true
	make("UITextSizeConstraint", { MinTextSize = 16, MaxTextSize = 22 }, s.closeHint)
	s.proxy.NextSelectionDown, s.skip.NextSelectionDown = s.skip, s.proxy
	connect(s, s.skip.Activated, function() finish(s, true) end)
	connect(s, s.proxy.Activated, function()
		if not alive(s) or s.flow.phase ~= "shop" or not s.shopPanel then return end
		s.shopPanel.Visible = true
	end)
	local function inputHint()
		if not alive(s) then return end
		local pad = padActive()
		s.padIcon.Visible = pad
		s.skip.Text = C.Text.Skip .. ((not pad and UIS.KeyboardEnabled) and (" [" .. C.SkipKey.Name .. "]") or "")
		if pad then
			pcall(function() s.padIcon.Image = UIS:GetImageForKeyCode(C.SkipGamepadKey) end)
			if s.flow.phase == "shop" and s.proxy.Visible then GS.SelectedObject = s.proxy
			elseif s.flow.phase == "info" then GS.SelectedObject = s.closeButton or s.skip end
		end
	end
	connect(s, UIS.LastInputTypeChanged, inputHint)
	connect(s, s.safe:GetPropertyChangedSignal("AbsoluteSize"), function()
		if s.started then refresh(s) end
	end)
	inputHint()
	CAS:BindActionAtPriority(SKIP_ACTION, function(_, state)
		local prompt = pg:FindFirstChild("RobuxPromptFX")
		if not alive(s) or (prompt and prompt.Enabled) or UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then finish(s, true) end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 100, C.SkipKey, C.SkipGamepadKey)
	s.overlay.Enabled, s.hud.Enabled = true, true
end

-- 🟢 FLÈCHES : une file de chevrons qui coule du joueur vers le checkpoint.
--    Avant : 3 chevrons collés au joueur, recalculés 15 fois/s → saccadé.
--    Maintenant : position recalculée à CHAQUE image (BulkMoveTo, 1 seul appel
--    moteur pour tous les morceaux), départ lissé (plus d'effet « aimanté »),
--    apparition / disparition en fondu aux deux bouts de la file.
local ARROW_SLOTS = 12   -- plafond de chevrons visibles (la file s'adapte à la distance)
local function clearWorld(s)
	if s.arrowConn then s.arrowConn:Disconnect() s.arrowConn = nil end
	if s.marker then s.marker:Destroy() s.marker = nil end
	if s.world then s.world:Destroy() s.world = nil end
	s.arrows, s.arrowParts, s.arrowFrom = nil, nil, nil
end
local function makeWorld(s)
	clearWorld(s)
	if not s.target then return end
	s.marker = make("BillboardGui", { Name = "RookieCheckpoint", Adornee = s.target,
		Size = UDim2.fromOffset(210, 55), StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
		AlwaysOnTop = true, MaxDistance = 500 }, pg)
	local l = text(s.marker, C.Text.Marker, 24)
	l.Size, l.TextColor3 = UDim2.fromScale(1, 1), C.Style.Green
	if not C.Arrows.Enabled then return end
	s.world = make("Folder", { Name = "RookieDirections_Local" }, workspace)
	s.arrows, s.arrowParts = {}, {}
	local count = math.clamp(math.max(C.Arrows.Count or 0, 6), 1, ARROW_SLOTS)
	for i = 1, count do
		local pair = {}
		for j = 1, 2 do
			pair[j] = make("Part", { Anchored = true, CanCollide = false, CanTouch = false,
				CanQuery = false, CastShadow = false, Material = Enum.Material.Neon,
				Color = C.Style.Green, Transparency = 1, Locked = true,
				Size = Vector3.new(C.Arrows.Width, C.Arrows.Width, C.Arrows.Length) }, s.world)
			table.insert(s.arrowParts, pair[j])
		end
		s.arrows[i] = pair
	end
	local cframes = table.create(#s.arrowParts)
	s.arrowConn = RunService.RenderStepped:Connect(function(dt)
		local root = s.arrowRoot
		if not s.arrows or not root or not root.Parent or not s.target or not s.target.Parent then
			for _, p in ipairs(s.arrowParts) do if p.Transparency ~= 1 then p.Transparency = 1 end end
			return
		end
		local feet = root.Position - Vector3.new(0, 2.1, 0)
		-- départ lissé : la file suit le joueur en douceur au lieu d'être vissée dessus
		local k = 1 - math.exp(-math.min(dt, 0.1) * 10)
		s.arrowFrom = s.arrowFrom and s.arrowFrom:Lerp(feet, k) or feet
		local from = s.arrowFrom
		local to = s.target.Position + Vector3.new(0, 1.2, 0)
		local delta = to - from
		local distance = delta.Magnitude
		local direction = distance > 0.01 and delta.Unit or Vector3.new(0, 0, -1)
		local side = direction:Cross(Vector3.new(0, 1, 0))
		side = side.Magnitude < 0.01 and Vector3.new(1, 0, 0) or side.Unit
		local spacing, len = C.Arrows.Spacing, C.Arrows.Length
		local show = distance > C.ReachRadius * 0.55 and distance < C.MaxSaneDistance
		local first = 3
		local last = math.min(distance - 1.5, first + #s.arrows * spacing)
		local flow = (os.clock() * C.Arrows.Speed) % spacing
		local base = C.Arrows.Transparency
		local n = 0
		for i, pair in ipairs(s.arrows) do
			local offset = first + (i - 1) * spacing + flow
			-- fondu : entre en douceur près du joueur, sort en douceur au bout de la file
			local fade = math.min((offset - first) / spacing, (last - offset) / spacing, 1)
			local tr = (show and fade > 0) and (1 - (1 - base) * fade) or 1
			local tip = from + direction * math.min(offset, distance)
			for j, part in ipairs(pair) do
				local t = math.floor(tr * 20 + 0.5) / 20         -- évite d'écrire à chaque image
				if part.Transparency ~= t then part.Transparency = t end
				local tail = tip - direction * (len * 0.72) + side * ((j == 1 and 1 or -1) * len * 0.70)
				n += 1
				cframes[n] = CFrame.lookAt((tip + tail) / 2, tip)
			end
		end
		workspace:BulkMoveTo(s.arrowParts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end
local function updateWorld(s, root)
	if not s.target or not s.target.Parent then return end
	s.arrowRoot = root
	local distance = (s.target.Position - root.Position).Magnitude
	if s.marker then s.marker.Enabled = distance < C.MaxSaneDistance end
end

refresh = function(s)
	if not alive(s) then return end
	local phase = s.flow.phase
	pg:SetAttribute("RookieGuidePhase", phase)
	local message = phase == "info" and infoText("InfoTitle") or phase == "shop" and C.Text.Shop
		or (not s.target and C.Text.Waiting) or (s.flow.reached == 0 and C.Text.First or C.Text.Next)
	s.title.Text = message
	local info = phase == "info"
	s.detail.Visible, s.note.Visible, s.closeHint.Visible = info, info, info
	local compact = s.safe.AbsoluteSize.Y < 360 and s.safe.AbsoluteSize.X > 480
	local height = info and (compact and 170 or 236) or 100
	s.message.Size = UDim2.new(1, -24, 0, height)
	local titleHeight = info and (compact and 36 or 46) or 72
	s.title.Size = UDim2.new(1, -24, 0, titleHeight)
	if info then
		clearWorld(s)
		s.detail.Position, s.detail.Size = UDim2.fromOffset(14, compact and 40 or 58), UDim2.new(1, -28, 0, compact and 50 or 66)
		s.note.Position, s.note.Size = UDim2.fromOffset(14, compact and 92 or 128), UDim2.new(1, -28, 0, compact and 34 or 52)
		s.closeHint.Position, s.closeHint.Size = UDim2.fromOffset(14, compact and 130 or 186), UDim2.new(1, -28, 0, compact and 30 or 38)
		s.message.AnchorPoint, s.message.Position = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -12)
		-- cadre vert autour de la boutique ET de son X ; aucun voile : tout reste cliquable
		setSpotlight(s, s.shopPanel, false, { extra = { s.closeButton }, noDim = true })
		if padActive() then GS.SelectedObject = s.closeButton or s.skip end
		-- ⏱️ se termine tout seul si le joueur ne fait rien (la boutique reste ouverte)
		if not s.infoTimer then
			s.infoTimer = true
			task.delay(INFO_AUTO_FINISH, function()
				if alive(s) and s.flow.phase == "info" then finish(s, true, true) end
			end)
		end
	elseif phase == "shop" then
		clearWorld(s)
		setSpotlight(s, s.shopButton, true)
		if padActive() and s.proxy.Visible then GS.SelectedObject = s.proxy end
	else setSpotlight(s, nil, false) end
end

resolveShop = function(s)
	if not alive(s) then return end
	local gui = pg:FindFirstChild(C.UGC.ScreenGui)
	local panel = gui and findPath(gui, C.UGC.PanelPath)
	local opener = gui and findPath(gui, C.UGC.ButtonPath)
	if panel and not panel:IsA("GuiObject") then panel = nil end
	if opener and not opener:IsA("GuiObject") then opener = nil end
	local changed = panel ~= s.shopPanel or opener ~= s.shopButton
	if not changed then return end
	disconnect(s.shopConnections)
	s.shopGui, s.shopPanel, s.shopButton = gui, panel, opener
	-- le X rouge de la boutique (UGCshop ▸ ShopFrame ▸ ShopToggle), inclus dans le cadre vert
	local close = gui and findPath(gui, (C.UGC and C.UGC.ClosePath) or { "ShopFrame", "ShopToggle" })
	s.closeButton = (close and close:IsA("GuiObject")) and close or nil
	if panel then
		local function opened()
			if not alive(s) then return end
			if panel.Visible then
				s.openedShop = true
				-- Le joueur peut choisir la boutique avant la fin des checkpoints.
				if s.flow.phase == "play" then s.flow:ShowShop() end
				if s.flow:ShopOpened() then refresh(s) end
			elseif s.flow.phase == "info" then finish(s, true) end
		end
		table.insert(s.shopConnections, panel:GetPropertyChangedSignal("Visible"):Connect(opened))
		opened()
	end
	if s.overlay then refresh(s) end
end

-- Stage enregistré du joueur (leaderstats.Stage). Le guide ne vise JAMAIS un
-- checkpoint égal ou inférieur : seulement le suivant au-dessus.
local function savedStage()
	local ls = player:FindFirstChild("leaderstats")
	local stage = ls and ls:FindFirstChild("Stage")
	return stage and tonumber(stage.Value) or 0
end

nextCheckpoint = function(s, minimum)
	minimum = math.max(minimum or 1, savedStage() + 1)
	local index, target
	for n, part in pairs(s.checkpoints) do
		if n >= minimum and part:IsDescendantOf(workspace) and not s.flow.seen[n] and (not index or n < index) then
			index, target = n, part
		end
	end
	s.target = target
	if index then
		s.flow:SetTarget(index)
		s.missingSince = nil
		makeWorld(s)
	else
		s.flow:SetTarget(nil)
		s.minimum = minimum
		s.missingSince = s.missingSince or os.clock()
		clearWorld(s)
	end
	refresh(s)
end
local function reached(s, index)
	if not alive(s) or not s.flow:Reach(index) then return end
	if s.flow.phase == "shop" then
		refresh(s)
		if s.shopPanel and s.shopPanel.Visible and s.flow:ShopOpened() then refresh(s) end
	else nextCheckpoint(s, index + 1) end
end

-- keepShop = true → la boutique reste ouverte (fin automatique, ou SKIP pendant la boutique)
finish = function(s, mark, keepShop)
	if not alive(s) then return end
	s.finished = true
	-- SKIP pendant la boutique : on ne referme pas ce que le joueur regarde
	if s.flow.phase == "info" then keepShop = true end
	s.flow:Finish()
	generation = generation + 1
	CAS:UnbindAction(SKIP_ACTION)
	disconnect(s.connections)
	disconnect(s.spotConnections)
	disconnect(s.shopConnections)
	if s.haloTween then s.haloTween:Cancel() end
	if s.arrowTween then s.arrowTween:Cancel() end
	clearWorld(s)
	if not keepShop and C.CloseShopOnFinish and s.openedShop and s.shopPanel and s.shopPanel.Parent then s.shopPanel.Visible = false end
	local selected = GS.SelectedObject
	if selected and ((s.overlay and selected:IsDescendantOf(s.overlay)) or (s.hud and selected:IsDescendantOf(s.hud))) then
		GS.SelectedObject = s.previousSelection and s.previousSelection.Parent and s.previousSelection or nil
	end
	if s.overlay then s.overlay:Destroy() end
	if s.hud then s.hud:Destroy() end
	pg:SetAttribute("RookieGuidePhase", nil)
	if mark and s.started then
		_G.RookieGuideCompletedSession = true
		if C.MarkSeenOnFinish and not s.testing then
			local remotes = RS:FindFirstChild("Remotes")
			local seen = remotes and remotes:FindFirstChild("TutorialSeen")
			if seen and seen:IsA("RemoteEvent") then seen:FireServer() end
		end
	end
	_G.RookieGuideActive = false
	current = nil
end

start = function(replay)
	if disposed or not C.Enabled or (not replay and _G.RookieGuideCompletedSession) then return end
	if current then finish(current, false) end
	generation = generation + 1
	local token = generation
	local s = { flow = Flow.new(C.GuidedCheckpoints), connections = {}, spotConnections = {},
		shopConnections = {}, checkpoints = {}, testing = replay or C.TestMode or table.find(C.TestUserIds, player.UserId) ~= nil,
		previousSelection = GS.SelectedObject }
	current = s
	-- Empêche la popup de l'ancien tutoriel de partir pendant le contrôle serveur.
	_G.RookieGuideActive = true
	task.delay(C.LoadTimeout, function()
		if alive(s) and not s.started then
			warn("[RookieGuide] Chargement incomplet : guide annulé, interfaces conservées.")
			finish(s, false)
		end
	end)
	task.spawn(function()
		local focus = pg:WaitForChild("UIFocusSystem", C.LoadTimeout)
		while alive(s) and focus and (tonumber(focus:GetAttribute("RookieGuideSupport")) or 0) < 4 do task.wait(0.1) end
		if not alive(s) or token ~= generation then return end
		if not focus then finish(s, false) return end
		if not s.testing then
			local remotes = RS:WaitForChild("Remotes", C.LoadTimeout)
			local check = remotes and remotes:WaitForChild("TutorialCheckFirstJoin", C.LoadTimeout)
			if not alive(s) then return end
			local ok, first = false, false
			if check and check:IsA("RemoteFunction") then ok, first = pcall(function() return check:InvokeServer() end) end
			if not alive(s) then return end
			if not ok or first ~= true then finish(s, false) return end
		end
		task.wait(C.StartDelay)
		if not alive(s) then return end
		if _G.TutorialActive then finish(s, false) return end
		local existing = pg:FindFirstChild(C.UGC.ScreenGui)
		local existingPanel = existing and findPath(existing, C.UGC.PanelPath)
		-- Ne pas interrompre une boutique déjà ouverte pendant le chargement.
		if existingPanel and existingPanel.Visible then finish(s, false) return end
		local scope = C.CheckpointFolder ~= "" and workspace:FindFirstChild(C.CheckpointFolder) or workspace
		if not scope then finish(s, false) return end
		local function register(part)
			if not part:IsA("BasePart") then return end
			local n = tonumber(part.Name:match("^[Cc]heckpoint(%d+)$"))
			if n then s.checkpoints[n] = part end
		end
		connect(s, scope.DescendantAdded, function(part)
			register(part)
			if s.started and not s.target and s.flow.phase == "play" then nextCheckpoint(s, s.minimum or 1) end
		end)
		for i, part in ipairs(scope:GetDescendants()) do
			register(part)
			if i % 2000 == 0 then task.wait() if not alive(s) then return end end
		end
		buildUI(s)
		s.started = true
		resolveShop(s)
		connect(s, pg.DescendantAdded, function(o)
			if (not s.shopPanel or not s.shopButton) and o.Name == (not s.shopPanel and C.UGC.PanelPath[#C.UGC.PanelPath] or C.UGC.ButtonPath[#C.UGC.ButtonPath]) then
				task.defer(resolveShop, s)
			end
		end)
		nextCheckpoint(s, savedStage() + 1)
		-- Le Stage arrive parfois après le début du guide (chargement des données),
		-- ou le joueur saute plusieurs checkpoints : on vise toujours le suivant.
		local function watchStage(stage)
			connect(s, stage:GetPropertyChangedSignal("Value"), function()
				if not alive(s) or s.flow.phase ~= "play" then return end
				local cur = tonumber(stage.Value) or 0
				if not s.flow.target or s.flow.target <= cur then
					if s.flow.target and s.flow.target <= cur then reached(s, s.flow.target) end
					if alive(s) and s.flow.phase == "play" then nextCheckpoint(s, cur + 1) end
				end
			end)
		end
		local ls = player:FindFirstChild("leaderstats")
		local stageValue = ls and ls:FindFirstChild("Stage")
		if stageValue then
			watchStage(stageValue)
		else
			task.spawn(function()
				local l = player:WaitForChild("leaderstats", C.LoadTimeout)
				local st = l and l:WaitForChild("Stage", C.LoadTimeout)
				if st and alive(s) then
					watchStage(st)
					if s.flow.phase == "play" and (not s.flow.target or s.flow.target <= (tonumber(st.Value) or 0)) then
						nextCheckpoint(s, (tonumber(st.Value) or 0) + 1)
					end
				end
			end)
		end
		local bound = false
		local function bindCheckpoint(ev)
			if not bound and ev.Name == "CheckpointUpdated" and ev:IsA("RemoteEvent") then
				bound = true
				connect(s, ev.OnClientEvent, function(name)
					local n = tonumber(tostring(name):match("(%d+)"))
					reached(s, n)
				end)
			end
		end
		for _, child in ipairs(RS:GetChildren()) do bindCheckpoint(child) end
		connect(s, RS.ChildAdded, bindCheckpoint)
		local elapsed = 0
		connect(s, RunService.Heartbeat, function(dt)
			elapsed = elapsed + dt
			if elapsed < 1 / math.clamp(C.Arrows.UpdateHz, 5, 30) then return end
			elapsed = 0
			if not alive(s) then return end
			if C.StopOnTutorial and _G.TutorialActive then finish(s, false) return end
			if not focus:IsDescendantOf(pg) or not focus:GetAttribute("RookieGuideSupport") then finish(s, false) return end
			if s.flow.phase ~= "play" then return end
			if not s.target or not s.target:IsDescendantOf(workspace) then
				if s.target then nextCheckpoint(s, s.flow.target or 1) end
				if s.missingSince and os.clock() - s.missingSince > C.LoadTimeout then
					-- Streaming ou aucun checkpoint disponible : accès direct à la boutique.
					s.flow:ShowShop() refresh(s)
				end
				return
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not hum or hum.Health <= 0 then
				s.arrowRoot = nil       -- mort / respawn : la file se cache
				if s.marker then s.marker.Enabled = false end
				if s.arrows then for _, pair in ipairs(s.arrows) do for _, p in ipairs(pair) do p.Transparency = 1 end end end
				return
			end
			updateWorld(s, root)
			if C.AllowProximityProgress and (root.Position - s.target.Position).Magnitude <= C.ReachRadius then reached(s, s.flow.target) end
		end)
	end)
end

local disableAPI = function() C.Enabled = false if current then finish(current, false) end end
local replayAPI = function() start(true) end
_G.DisableRookieGuide, _G.RookieGuideReplay = disableAPI, replayAPI
script.Destroying:Connect(function()
	if current then finish(current, false) end
	disposed = true
	_G.__RookieGuideLoaded = nil
	if _G.DisableRookieGuide == disableAPI then _G.DisableRookieGuide = nil end
	if _G.RookieGuideReplay == replayAPI then _G.RookieGuideReplay = nil end
end)
start(false)
