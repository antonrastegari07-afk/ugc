-- ============================================================
-- GLOW ENGINE (ModuleScript) — à mettre dans ReplicatedStorage, nom : GlowEngine
-- ============================================================
-- Remplace le moteur des 27 scripts Glow de tes UI, avec le MÊME rendu :
--   • ImageGlow  = l'ancien "IMAGE GLOW - VERSION POLISHED + LED ROTATIF" (Shop, PointsShop, VIP…)
--   • FrameGlow  = l'ancien "Script pour créer un effet glow autour d'un Frame" (UGCshop, Daily, Rebirth)
--
-- MÊME RENDU : mêmes couleurs, mêmes tailles, même forme, même LED (24 segments par côté,
-- recolorés de la même façon), même shimmer, mêmes étincelles. Tous tes réglages CONFIG restent.
--
-- Pourquoi c'est beaucoup plus léger :
--   1. Les COINS étaient dessinés pixel par pixel : des centaines de Frames par coin
--      (≈ 36 000 Frames créées d'un coup au démarrage pour les 27 glows sur PC).
--      Maintenant : 12 bandes par coin, avec la même formule de dégradé et de couleur.
--      Les côtés restent les mêmes segments qu'avant.
--   2. Plus de CanvasGroup (une texture hors-écran en mémoire vidéo, redessinée 30×/s).
--      Le shimmer s'applique directement sur la transparence : résultat identique.
--   3. Les étincelles réutilisent les mêmes objets au lieu d'en créer/détruire en boucle.
--   4. Tout s'arrête quand le glow n'est pas à l'écran (shop fermé, ScreenGui désactivé…),
--      et le LED ne recolore pas un glow sorti de la zone visible d'une liste qui défile.
--
-- Aucune image à uploader : tout est fait avec des Frames.
-- ============================================================

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local GlowEngine = {}


-- ============================================================
-- VISIBILITÉ RÉELLE : l'élément et TOUS ses parents sont visibles + ScreenGui activé
-- ============================================================
local function isReallyShown(gui)
	local node = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then return false end
		elseif node:IsA("LayerCollector") then
			return node.Enabled and node:FindFirstAncestorOfClass("PlayerGui") ~= nil
		end
		node = node.Parent
	end
	return false
end

-- Appelle onChange(shown) à chaque changement de visibilité réelle
local function watchVisibility(gui, onChange)
	local conns = {}
	local last = nil
	local pending = false
	local destroyed = false

	local function clear()
		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)
	end
	local function evaluate()
		pending = false
		if destroyed then return end
		local shown = isReallyShown(gui)
		if shown ~= last then
			last = shown
			onChange(shown)
		end
	end
	local function schedule()
		if not pending then
			pending = true
			task.defer(evaluate)
		end
	end
	local function hook()
		clear()
		local node = gui
		while node do
			if node:IsA("GuiObject") then
				table.insert(conns, node:GetPropertyChangedSignal("Visible"):Connect(schedule))
			elseif node:IsA("LayerCollector") then
				table.insert(conns, node:GetPropertyChangedSignal("Enabled"):Connect(schedule))
			end
			if node ~= gui then
				table.insert(conns, node.AncestryChanged:Connect(function()
					hook()
					schedule()
				end))
			end
			node = node.Parent
		end
	end

	hook()
	local ancestryConn = gui.AncestryChanged:Connect(function()
		hook()
		schedule()
	end)
	schedule()

	return function()
		destroyed = true
		clear()
		ancestryConn:Disconnect()
	end
end

local function computeScale(cfg)
	if not cfg.responsive then return 1 end
	local cam = workspace.CurrentCamera
	local screenSize = cam and cam.ViewportSize or Vector2.new(800, 800)
	local baseDimension = math.min(screenSize.X, screenSize.Y)
	return math.clamp(baseDimension / cfg.referenceSize, cfg.minScale, cfg.maxScale)
end

-- ============================================================
-- PÉRIMÈTRE (identique à l'ancien script : côtés 20 %, coins 5 %, sens horaire)
-- ============================================================
local SIDE_W, CORNER_W = 0.20, 0.05
local U = {
	Top = 0.00, TopRight = 0.20, Right = 0.25, BottomRight = 0.45,
	Bottom = 0.50, BottomLeft = 0.70, Left = 0.75, TopLeft = 0.95,
}

local function paletteColor(palette, t)
	local n = #palette
	local idxFloat = (t % 1) * n
	local floorIdx = math.floor(idxFloat)
	local idxA = floorIdx % n + 1
	local idxB = (idxA % n) + 1
	return palette[idxA]:Lerp(palette[idxB], idxFloat - floorIdx)
end

-- ============================================================
-- COINS : bandes horizontales avec dégradé (aucune image, aucun cercle, aucun rognage)
-- ============================================================
-- L'ancien script dessinait chaque coin pixel par pixel. Pour un pixel à la distance d du
-- coin de l'élément : opacité = intensité × (1 - d / glowSize), et sa couleur LED dépend de
-- son angle autour du coin.
-- Ici : le coin est découpé en bandes horizontales (12 au maximum), placées au pixel près.
-- Chaque bande porte un UIGradient qui reprend EXACTEMENT ces formules (opacité + couleur)
-- le long de la bande. Une seule couche → pas de ligne à la jonction avec les côtés.
local CORNER_ROWS_MAX = 12  -- bandes par coin (12 = marches de 2 px comme l'ancien script)
local ROW_KEYPOINTS = 11    -- points du dégradé le long d'une bande (max Roblox : 20)

local function cornerSquarePos(corner, g)
	if corner == "TopLeft" then return UDim2.new(0, -g, 0, -g)
	elseif corner == "TopRight" then return UDim2.new(1, 0, 0, -g)
	elseif corner == "BottomLeft" then return UDim2.new(0, -g, 1, 0)
	else return UDim2.new(1, 0, 1, 0) end
end
-- distance au coin de l'élément pour un point (x, y) du carré du coin
local function cornerDistance(corner, g, x, y)
	if corner == "TopLeft" then return g - x, g - y
	elseif corner == "TopRight" then return x, g - y
	elseif corner == "BottomLeft" then return g - x, y
	else return x, y end
end
-- position u sur le contour (même formule que uForCornerPixel de l'ancien script)
local function cornerU(corner, g, x, y)
	local theta
	if corner == "TopRight" then theta = math.atan2(x, g - y)
	elseif corner == "BottomRight" then theta = math.atan2(y, x)
	elseif corner == "BottomLeft" then theta = math.atan2(g - x, y)
	else theta = math.atan2(g - y, g - x) end
	return U[corner] + (theta / (math.pi / 2)) * CORNER_W
end

-- Construit un coin. Renvoie le carré (Frame) et la liste des bandes (Frames).
-- colorList ~= nil → LED rotatif : chaque bande est ajoutée à colorList avec ses positions u.
local function buildCornerRows(parent, corner, g, intensity, falloff, z, color, colorList)
	local square = Instance.new("Frame")
	square.Name = "GlowCorner_" .. corner
	square.BackgroundTransparency = 1
	square.BorderSizePixel = 0
	square.Active = false
	square.Size = UDim2.fromOffset(g, g)
	square.Position = cornerSquarePos(corner, g)
	square.ZIndex = z

	local rows = {}
	local count = math.clamp(math.ceil(g / 2), 1, CORNER_ROWS_MAX)
	for j = 1, count do
		local y0 = math.floor((j - 1) * g / count + 0.5)
		local y1 = math.floor(j * g / count + 0.5)
		if y1 > y0 then
			local cy = (y0 + y1) / 2
			local trans, times, us = {}, {}, {}
			for k = 0, ROW_KEYPOINTS - 1 do
				local t = k / (ROW_KEYPOINTS - 1)
				local x = t * g
				local dx, dy = cornerDistance(corner, g, x, cy)
				local n = math.min(math.sqrt(dx * dx + dy * dy) / g, 1)
				local opacity = intensity * ((1 - n) ^ falloff)
				if opacity < 0.01 then opacity = 0 end
				trans[k + 1] = NumberSequenceKeypoint.new(t, math.clamp(1 - opacity, 0, 1))
				times[k + 1] = t
				us[k + 1] = cornerU(corner, g, x, cy)
			end

			local row = Instance.new("Frame")
			row.Name = "Row" .. j
			row.BorderSizePixel = 0
			row.Active = false
			row.ZIndex = z
			row.Size = UDim2.fromOffset(g, y1 - y0)
			row.Position = UDim2.fromOffset(0, y0)
			row.BackgroundColor3 = colorList and Color3.new(1, 1, 1) or color
			local grad = Instance.new("UIGradient")
			grad.Transparency = NumberSequence.new(trans)
			grad.Parent = row
			if colorList then
				table.insert(colorList, { grad, times, us })
			end
			row.Parent = square
			table.insert(rows, row)
		end
	end
	square.Parent = parent
	return square, rows
end


-- ============================================================
-- IMAGE GLOW (remplace "IMAGE GLOW - VERSION POLISHED + LED ROTATIF")
-- ============================================================
local DEFAULTS = {
	glowMode = "rectangle", glowColor = Color3.fromRGB(255, 200, 80),
	rectGlowSize = 19, rectIntensity = 0.7, rectFalloff = 1.0,
	rectEnableTop = true, rectEnableBottom = true, rectEnableLeft = true,
	rectEnableRight = true, rectEnableCorners = true,
	rectColorCycleEnabled = true, rectColorCycleSpeed = 10, rectColorCycleFPS = 30,
	imageLayers = 8, imageSpread = 30, imageIntensity = 0.4, imageFalloff = 1.5,
	rayCount = 12, rayLength = 80, rayThickness = 8, rayIntensity = 0.8, rayFalloff = 1.2,
	rayRotationSpeed = 20, rayAlternate = true, rayShortFactor = 0.55,
	shimmerEnabled = true, shimmerSpeed = 3.0, shimmerMin = 0.0, shimmerMax = 0.45,
	sparkleEnabled = true, sparkleCount = 7, sparkleSize = 16, sparkleSizeVar = 0.6,
	sparkleLifetime = 1.5, sparkleDelay = 0.6, sparkleOverflow = 0, sparkleRotate = true,
	sparkleThickness = 0.1,
	responsive = true, referenceSize = 800, minScale = 0.4, maxScale = 2.5,
}

function GlowEngine.ImageGlow(imageLabel, userConfig)
	local CONFIG = setmetatable(userConfig or {}, { __index = DEFAULTS })
	local parentContainer = imageLabel.Parent
	local uid = HttpService:GenerateGUID(false):gsub("[^%w]", "")

	local glowFrame        -- remplace l'ancien CanvasGroup
	local sparkleContainer
	local segments = {}    -- { {Frame, u} } : segments des côtés (LED rotatif)
	local gradients = {}   -- { {UIGradient, temps, u} } : bandes des coins (LED rotatif)
	local fadeTargets = {} -- { {inst, prop, alpha} } : éléments affectés par le shimmer
	local shimmerTweens = {}
	local colorConn, rayConn
	local sparkleThreads = {}
	local sparklePool = {}
	local shown = false
	local raysWrapper

	-- ---------- conteneurs ----------
	local function syncContainers()
		local z = imageLabel.ZIndex
		if glowFrame then
			glowFrame.AnchorPoint = imageLabel.AnchorPoint
			glowFrame.Position = imageLabel.Position
			glowFrame.Size = imageLabel.Size
			glowFrame.ZIndex = z - 1
			for _, d in ipairs(glowFrame:GetDescendants()) do
				if d:IsA("GuiObject") then d.ZIndex = z - 1 end
			end
		end
		if sparkleContainer then
			sparkleContainer.AnchorPoint = imageLabel.AnchorPoint
			sparkleContainer.Position = imageLabel.Position
			sparkleContainer.Size = imageLabel.Size
			sparkleContainer.ZIndex = z + 1
			for _, d in ipairs(sparkleContainer:GetDescendants()) do
				if d:IsA("GuiObject") then
					d.ZIndex = (d.Name == "Core") and z + 2 or z + 1
				end
			end
		end
	end

	local function makeContainers()
		if glowFrame then glowFrame:Destroy() end
		glowFrame = Instance.new("Frame")
		glowFrame.Name = uid .. "_Glow"
		glowFrame.BackgroundTransparency = 1
		glowFrame.BorderSizePixel = 0
		glowFrame.Active = false
		glowFrame.ClipsDescendants = false
		glowFrame.Parent = parentContainer

		if CONFIG.sparkleEnabled and not sparkleContainer then
			sparkleContainer = Instance.new("Frame")
			sparkleContainer.Name = uid .. "_SparkleContainer"
			sparkleContainer.BackgroundTransparency = 1
			sparkleContainer.BorderSizePixel = 0
			sparkleContainer.ClipsDescendants = true
			sparkleContainer.Active = false
			sparkleContainer.Parent = parentContainer
		end
		syncContainers()
	end

	-- ---------- shimmer (même courbe que GroupTransparency du CanvasGroup) ----------
	local function setFade(g)
		for _, f in ipairs(fadeTargets) do
			f[1][f[2]] = 1 - f[3] * (1 - g)
		end
	end
	local function stopShimmer()
		for _, t in ipairs(shimmerTweens) do t:Cancel() end
		table.clear(shimmerTweens)
		setFade(0)
	end
	local function startShimmer()
		stopShimmer()
		if not CONFIG.shimmerEnabled or CONFIG.glowMode == "none" then return end
		setFade(CONFIG.shimmerMin)
		local info = TweenInfo.new(CONFIG.shimmerSpeed / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		for _, f in ipairs(fadeTargets) do
			local t = TweenService:Create(f[1], info, { [f[2]] = 1 - f[3] * (1 - CONFIG.shimmerMax) })
			t:Play()
			table.insert(shimmerTweens, t)
		end
	end

	-- ---------- LED rotatif ----------
	-- Côtés : chaque segment prend la couleur de la palette à SA position, exactement comme
	-- l'ancien script (24 segments par côté → mêmes blocs de couleur).
	-- Coins : dégradé entre la couleur de début et de fin du coin (le coin = 5 % du contour).
	local function paintColors(offset)
		local palette = CONFIG.rectColorCyclePalette
		for i = 1, #segments do
			local s = segments[i]
			s[1].BackgroundColor3 = paletteColor(palette, s[2] - offset)
		end
		for _, e in ipairs(gradients) do
			local times, us = e[2], e[3]
			local kps = table.create(#times)
			for k = 1, #times do
				kps[k] = ColorSequenceKeypoint.new(times[k], paletteColor(palette, us[k] - offset))
			end
			e[1].Color = ColorSequence.new(kps)
		end
	end
	local function colorCycleActive()
		local palette = CONFIG.rectColorCyclePalette
		return CONFIG.rectColorCycleEnabled and CONFIG.glowMode == "rectangle"
			and palette ~= nil and #palette >= 2
	end
	-- Dans une liste qui défile : pas la peine de recolorer un glow sorti de la zone visible
	-- (il n'est pas dessiné). Ses couleurs sont recalculées dès qu'il revient.
	local clipper = imageLabel:FindFirstAncestorWhichIsA("ScrollingFrame")
	local function inView()
		if not clipper then return true end
		local p, s = imageLabel.AbsolutePosition, imageLabel.AbsoluteSize
		local cp, cs = clipper.AbsolutePosition, clipper.AbsoluteSize
		local m = 80 -- marge : le glow dépasse de l'image
		return p.X + s.X + m >= cp.X and p.X - m <= cp.X + cs.X
			and p.Y + s.Y + m >= cp.Y and p.Y - m <= cp.Y + cs.Y
	end
	local startTime = os.clock()
	local function stopColorCycle()
		if colorConn then colorConn:Disconnect(); colorConn = nil end
	end
	local function startColorCycle()
		stopColorCycle()
		if not colorCycleActive() then return end
		local interval = 1 / math.max(CONFIG.rectColorCycleFPS or 30, 1)
		local accum = interval
		local cycleDur = math.max(CONFIG.rectColorCycleSpeed, 0.01)
		colorConn = RunService.Heartbeat:Connect(function(dt)
			accum += dt
			if accum < interval then return end
			accum %= interval
			if not inView() then return end
			paintColors((os.clock() - startTime) / cycleDur)
		end)
	end

	-- ---------- construction ----------
	-- Côtés : copie EXACTE de l'ancien script (segments + UIGradient de transparence).
	-- Coins : 1 image radiale au lieu de centaines de "pixels" Frame (même formule de dégradé).
	local function buildRectangle()
		local scale = computeScale(CONFIG)
		local glowSize = math.max(math.floor(CONFIG.rectGlowSize * scale), 6)
		local intensity = CONFIG.rectIntensity
		local segCount = math.max(CONFIG.rectColorCycleSegments or 24, 1)
		local z = imageLabel.ZIndex - 1
		local nearAlpha = math.clamp(1 - intensity, 0, 1) -- = rectAlpha(0) de l'ancien script
		local farAlpha = 1                                 -- = rectAlpha(1)

		local function createSideGlow(side)
			for i = 1, segCount do
				local t0 = (i - 1) / segCount
				local segLen = 1 / segCount
				local segCenter = t0 + segLen * 0.5

				local seg = Instance.new("Frame")
				seg.Name = "GlowSide_" .. side .. "_" .. i
				seg.BackgroundColor3 = CONFIG.glowColor
				seg.BorderSizePixel = 0
				seg.Active = false
				seg.ZIndex = z

				local gradient = Instance.new("UIGradient")
				if side == "Top" then
					seg.Size = UDim2.new(segLen, 0, 0, glowSize)
					seg.Position = UDim2.new(t0, 0, 0, -glowSize)
					gradient.Rotation = 90
					gradient.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, farAlpha),
						NumberSequenceKeypoint.new(1, nearAlpha)
					})
				elseif side == "Bottom" then
					seg.Size = UDim2.new(segLen, 0, 0, glowSize)
					seg.Position = UDim2.new(t0, 0, 1, 0)
					gradient.Rotation = 90
					gradient.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, nearAlpha),
						NumberSequenceKeypoint.new(1, farAlpha)
					})
				elseif side == "Left" then
					seg.Size = UDim2.new(0, glowSize, segLen, 0)
					seg.Position = UDim2.new(0, -glowSize, t0, 0)
					gradient.Rotation = 0
					gradient.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, farAlpha),
						NumberSequenceKeypoint.new(1, nearAlpha)
					})
				elseif side == "Right" then
					seg.Size = UDim2.new(0, glowSize, segLen, 0)
					seg.Position = UDim2.new(1, 0, t0, 0)
					gradient.Rotation = 0
					gradient.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, nearAlpha),
						NumberSequenceKeypoint.new(1, farAlpha)
					})
				end
				gradient.Parent = seg

				local u
				if side == "Top" or side == "Right" then
					u = U[side] + segCenter * SIDE_W
				else
					u = U[side] + (1 - segCenter) * SIDE_W -- sens horaire
				end
				table.insert(segments, { seg, u })
				-- shimmer : BackgroundTransparency 0 → g donne exactement GroupTransparency = g
				table.insert(fadeTargets, { seg, "BackgroundTransparency", 1 })
				seg.Parent = glowFrame
			end
		end

		if CONFIG.rectEnableTop then createSideGlow("Top") end
		if CONFIG.rectEnableBottom then createSideGlow("Bottom") end
		if CONFIG.rectEnableLeft then createSideGlow("Left") end
		if CONFIG.rectEnableRight then createSideGlow("Right") end

		local cycle = colorCycleActive()
		if CONFIG.rectEnableCorners then
			for _, corner in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight" }) do
				local _, rows = buildCornerRows(glowFrame, corner, glowSize, intensity,
					CONFIG.rectFalloff or 1, z, CONFIG.glowColor, cycle and gradients or nil)
				for _, row in ipairs(rows) do
					table.insert(fadeTargets, { row, "BackgroundTransparency", 1 })
				end
			end
		end
		if cycle then
			paintColors((os.clock() - startTime) / math.max(CONFIG.rectColorCycleSpeed, 0.01))
		end
	end

	local function buildImage()
		local spreadMax = CONFIG.imageSpread * computeScale(CONFIG)
		for i = 1, CONFIG.imageLayers do
			local t = i / CONFIG.imageLayers
			local spread = spreadMax * (t ^ (1 / CONFIG.imageFalloff))
			local layer = Instance.new("ImageLabel")
			layer.Name = "GlowLayer_" .. i
			layer.Image = imageLabel.Image
			layer.ImageColor3 = CONFIG.glowColor
			layer.ScaleType = imageLabel.ScaleType
			layer.SliceCenter = imageLabel.SliceCenter
			layer.SliceScale = imageLabel.SliceScale
			layer.ImageRectOffset = imageLabel.ImageRectOffset
			layer.ImageRectSize = imageLabel.ImageRectSize
			layer.BackgroundTransparency = 1
			layer.BorderSizePixel = 0
			layer.Active = false
			layer.Size = UDim2.new(1, math.floor(spread * 2), 1, math.floor(spread * 2))
			layer.Position = UDim2.new(0, math.floor(-spread), 0, math.floor(-spread))
			local alpha = math.clamp((CONFIG.imageIntensity * (1 - t * 0.6)) / CONFIG.imageLayers * 2.5, 0, 1)
			layer.ImageTransparency = 1 - alpha
			layer.ZIndex = imageLabel.ZIndex - 1
			layer.Parent = glowFrame
			table.insert(fadeTargets, { layer, "ImageTransparency", alpha })
		end
	end

	local function stopRays()
		if rayConn then rayConn:Disconnect(); rayConn = nil end
	end
	local function startRays()
		stopRays()
		if CONFIG.glowMode ~= "rays" or CONFIG.rayRotationSpeed == 0 or not raysWrapper then return end
		local wrapper = raysWrapper
		local currentRot = wrapper.Rotation
		rayConn = RunService.Heartbeat:Connect(function(dt)
			currentRot = (currentRot + CONFIG.rayRotationSpeed * dt) % 360
			wrapper.Rotation = currentRot
		end)
	end
	local function buildRays()
		local scale = computeScale(CONFIG)
		local rayLength = CONFIG.rayLength * scale
		local rayThickness = math.max(CONFIG.rayThickness * scale, 2)
		local absSize = imageLabel.AbsoluteSize
		if absSize.X < 1 or absSize.Y < 1 then absSize = Vector2.new(100, 100) end
		local halfW, halfH = absSize.X / 2, absSize.Y / 2

		local wrapper = Instance.new("Frame")
		wrapper.Name = "RaysWrapper"
		wrapper.AnchorPoint = Vector2.new(0.5, 0.5)
		wrapper.Position = UDim2.fromScale(0.5, 0.5)
		wrapper.Size = UDim2.fromScale(1, 1)
		wrapper.BackgroundTransparency = 1
		wrapper.BorderSizePixel = 0
		wrapper.Active = false
		wrapper.ClipsDescendants = true
		wrapper.ZIndex = imageLabel.ZIndex - 1
		wrapper.Parent = glowFrame
		raysWrapper = wrapper

		local baseAlpha = math.clamp(1 - CONFIG.rayIntensity, 0, 1)
		for i = 1, CONFIG.rayCount do
			local angle = (i - 1) * (360 / CONFIG.rayCount)
			local rad = math.rad(angle)
			local dx, dy = math.sin(rad), -math.cos(rad)
			local tx = (math.abs(dx) > 1e-6) and (halfW / math.abs(dx)) or math.huge
			local ty = (math.abs(dy) > 1e-6) and (halfH / math.abs(dy)) or math.huge
			local t = math.min(tx, ty)
			local length = rayLength
			if CONFIG.rayAlternate and (i % 2 == 0) then length = rayLength * CONFIG.rayShortFactor end

			local ray = Instance.new("Frame")
			ray.Name = "GlowRay_" .. i
			ray.AnchorPoint = Vector2.new(0.5, 1)
			ray.Position = UDim2.new(0.5, dx * t, 0.5, dy * t)
			ray.Size = UDim2.new(0, rayThickness, 0, length)
			ray.Rotation = angle
			ray.BackgroundColor3 = CONFIG.glowColor
			ray.BorderSizePixel = 0
			ray.Active = false
			ray.ZIndex = imageLabel.ZIndex - 1
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			local mid = baseAlpha + (1 - baseAlpha) * (1 - 0.5 ^ CONFIG.rayFalloff)
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, mid),
				NumberSequenceKeypoint.new(1, baseAlpha),
			})
			gradient.Parent = ray
			ray.Parent = wrapper
			table.insert(fadeTargets, { ray, "BackgroundTransparency", 1 })
		end
	end

	-- ---------- étincelles (objets réutilisés) ----------
	local function getSparkleColor()
		return CONFIG.sparkleColor or CONFIG.glowColor
	end
	local function createSparkleVisual()
		local z = imageLabel.ZIndex
		local color = getSparkleColor()
		local thickness = CONFIG.sparkleThickness
		local sparkle = Instance.new("Frame")
		sparkle.Name = "Sparkle"
		sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
		sparkle.BackgroundTransparency = 1
		sparkle.BorderSizePixel = 0
		sparkle.Active = false
		sparkle.Size = UDim2.new(0, 0, 0, 0)
		sparkle.ZIndex = z + 1

		local fade = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		local h = Instance.new("Frame")
		h.AnchorPoint = Vector2.new(0.5, 0.5)
		h.Position = UDim2.fromScale(0.5, 0.5)
		h.Size = UDim2.new(1, 0, thickness, 0)
		h.BackgroundColor3 = color
		h.BorderSizePixel = 0
		h.Active = false
		h.ZIndex = z + 1
		local hg = Instance.new("UIGradient")
		hg.Transparency = fade
		hg.Parent = h
		h.Parent = sparkle

		local v = Instance.new("Frame")
		v.AnchorPoint = Vector2.new(0.5, 0.5)
		v.Position = UDim2.fromScale(0.5, 0.5)
		v.Size = UDim2.new(thickness, 0, 1, 0)
		v.BackgroundColor3 = color
		v.BorderSizePixel = 0
		v.Active = false
		v.ZIndex = z + 1
		local vg = Instance.new("UIGradient")
		vg.Rotation = 90
		vg.Transparency = fade
		vg.Parent = v
		v.Parent = sparkle

		local core = Instance.new("Frame")
		core.Name = "Core"
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5, 0.5)
		core.Size = UDim2.new(thickness * 2, 0, thickness * 2, 0)
		core.BackgroundColor3 = color
		core.BorderSizePixel = 0
		core.Active = false
		core.ZIndex = z + 2
		local rounded = Instance.new("UICorner")
		rounded.CornerRadius = UDim.new(0.5, 0)
		rounded.Parent = core
		core.Parent = sparkle

		sparkle.Visible = false
		sparkle.Parent = sparkleContainer
		return sparkle
	end

	local function stopSparkles()
		for _, thread in ipairs(sparkleThreads) do
			pcall(task.cancel, thread)
		end
		table.clear(sparkleThreads)
		for _, s in ipairs(sparklePool) do
			s.Visible = false
			s.Size = UDim2.new(0, 0, 0, 0)
		end
	end
	local function startSparkles()
		stopSparkles()
		if not CONFIG.sparkleEnabled or not sparkleContainer then return end
		for i = 1, CONFIG.sparkleCount do
			local sparkle = sparklePool[i]
			if not sparkle or not sparkle.Parent then
				sparkle = createSparkleVisual()
				sparklePool[i] = sparkle
			end
			local thread = task.spawn(function()
				task.wait(math.random() * CONFIG.sparkleLifetime)
				while sparkle.Parent do
					local size = CONFIG.sparkleSize * computeScale(CONFIG)
						* (1 + (math.random() - 0.5) * 2 * CONFIG.sparkleSizeVar)
					size = math.max(size, 4)
					local overflow = CONFIG.sparkleOverflow
					sparkle.Size = UDim2.new(0, 0, 0, 0)
					sparkle.Position = UDim2.fromScale(
						-overflow + math.random() * (1 + 2 * overflow),
						-overflow + math.random() * (1 + 2 * overflow)
					)
					sparkle.Rotation = math.random() * 360
					sparkle.Visible = true

					local halfLife = CONFIG.sparkleLifetime / 2
					local appearGoal = { Size = UDim2.new(0, size, 0, size) }
					if CONFIG.sparkleRotate then appearGoal.Rotation = sparkle.Rotation + 90 end
					local t1 = TweenService:Create(sparkle, TweenInfo.new(halfLife, Enum.EasingStyle.Back, Enum.EasingDirection.Out), appearGoal)
					t1:Play()
					t1.Completed:Wait()

					local fadeGoal = { Size = UDim2.new(0, 0, 0, 0) }
					if CONFIG.sparkleRotate then fadeGoal.Rotation = sparkle.Rotation + 90 end
					local t2 = TweenService:Create(sparkle, TweenInfo.new(halfLife, Enum.EasingStyle.Quad, Enum.EasingDirection.In), fadeGoal)
					t2:Play()
					t2.Completed:Wait()

					sparkle.Visible = false
					task.wait(math.random() * CONFIG.sparkleDelay)
				end
			end)
			table.insert(sparkleThreads, thread)
		end
	end

	-- ---------- démarrage / arrêt selon la visibilité ----------
	local function startAnimations()
		startShimmer()
		startColorCycle()
		startRays()
		startSparkles()
	end
	local function stopAnimations()
		stopShimmer()
		stopColorCycle()
		stopRays()
		stopSparkles()
	end

	local function buildGlow()
		stopAnimations()
		table.clear(fadeTargets)
		table.clear(gradients)
		table.clear(segments)
		raysWrapper = nil
		makeContainers()
		if CONFIG.glowMode == "rectangle" then
			buildRectangle()
		elseif CONFIG.glowMode == "image" then
			buildImage()
		elseif CONFIG.glowMode == "rays" then
			buildRays()
		end
		setFade(0)
		glowFrame.Visible = shown
		if sparkleContainer then sparkleContainer.Visible = shown end
		if shown then startAnimations() end
	end

	imageLabel:GetPropertyChangedSignal("Position"):Connect(syncContainers)
	imageLabel:GetPropertyChangedSignal("Size"):Connect(syncContainers)
	imageLabel:GetPropertyChangedSignal("AnchorPoint"):Connect(syncContainers)
	imageLabel:GetPropertyChangedSignal("ZIndex"):Connect(syncContainers)
	imageLabel:GetPropertyChangedSignal("Image"):Connect(function()
		if CONFIG.glowMode == "image" then buildGlow() end
	end)
	imageLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if CONFIG.glowMode == "rays" and shown then buildGlow() end
	end)

	local stopWatching
	stopWatching = watchVisibility(imageLabel, function(isShown)
		shown = isShown
		if glowFrame then glowFrame.Visible = isShown end
		if sparkleContainer then sparkleContainer.Visible = isShown end
		if isShown then startAnimations() else stopAnimations() end
	end)

	imageLabel.Destroying:Connect(function()
		stopAnimations()
		if stopWatching then stopWatching() end
		if glowFrame then glowFrame:Destroy() end
		if sparkleContainer then sparkleContainer:Destroy() end
	end)

	buildGlow()

	if CONFIG.responsive then
		local rebuildQueued = false
		local function onViewport()
			if rebuildQueued then return end
			rebuildQueued = true
			task.delay(0.1, function()
				rebuildQueued = false
				if imageLabel.Parent then buildGlow() end
			end)
		end
		local camConn
		local function hookCamera()
			if camConn then camConn:Disconnect() end
			local cam = workspace.CurrentCamera
			if cam then camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(onViewport) end
		end
		hookCamera()
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
	end
end

-- ============================================================
-- FRAME GLOW (remplace "Script pour créer un effet glow autour d'un Frame")
-- Statique : côtés = Frame + UIGradient (comme avant), coins = 1 image radiale
-- (avant : une grille de Frames de 1 pixel → 2 000 à 4 000 Frames par glow).
-- ============================================================
function GlowEngine.FrameGlow(frame, cfg)
	cfg = cfg or {}
	local glowSizeBase = cfg.glowSizeBase or 25
	local glowColor = cfg.glowColor or Color3.fromRGB(0, 200, 255)
	local glowIntensity = cfg.glowIntensity or 0.45
	local edgeAlpha = math.clamp(1 - glowIntensity, 0, 1)

	local function computeGlowSize()
		local cam = workspace.CurrentCamera
		local screenSize = cam and cam.ViewportSize or Vector2.new(800, 800)
		local scaleFactor = math.min(screenSize.X, screenSize.Y) / 800
		return math.max(math.floor(glowSizeBase * scaleFactor), 10)
	end

	local function clear()
		for _, child in ipairs(frame:GetChildren()) do
			if child:GetAttribute("FrameGlow") or child.Name:match("^Glow_") or child.Name:match("^GlowCorner_") then
				child:Destroy()
			end
		end
	end

	local function sideGlow(side, glowSize)
		local glow = Instance.new("Frame")
		glow.Name = "Glow_" .. side
		glow.BackgroundColor3 = glowColor
		glow.BorderSizePixel = 0
		glow.ZIndex = frame.ZIndex - 1
		glow:SetAttribute("FrameGlow", true)
		local gradient = Instance.new("UIGradient")
		if side == "Top" then
			glow.Size = UDim2.new(1, 0, 0, glowSize)
			glow.Position = UDim2.new(0, 0, 0, -glowSize)
			gradient.Rotation = 90
			gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, edgeAlpha) })
		elseif side == "Bottom" then
			glow.Size = UDim2.new(1, 0, 0, glowSize)
			glow.Position = UDim2.new(0, 0, 1, 0)
			gradient.Rotation = 90
			gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, edgeAlpha), NumberSequenceKeypoint.new(1, 1) })
		elseif side == "Left" then
			glow.Size = UDim2.new(0, glowSize, 1, 0)
			glow.Position = UDim2.new(0, -glowSize, 0, 0)
			gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, edgeAlpha) })
		elseif side == "Right" then
			glow.Size = UDim2.new(0, glowSize, 1, 0)
			glow.Position = UDim2.new(1, 0, 0, 0)
			gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, edgeAlpha), NumberSequenceKeypoint.new(1, 1) })
		end
		gradient.Parent = glow
		glow.Parent = frame
	end

	local function cornerGlow(corner, glowSize)
		local square = buildCornerRows(frame, corner, glowSize, glowIntensity, 1,
			frame.ZIndex - 1, glowColor, nil)
		square:SetAttribute("FrameGlow", true)
	end

	local function build()
		clear()
		local glowSize = computeGlowSize()
		sideGlow("Top", glowSize)
		sideGlow("Bottom", glowSize)
		sideGlow("Left", glowSize)
		sideGlow("Right", glowSize)
		cornerGlow("TopLeft", glowSize)
		cornerGlow("TopRight", glowSize)
		cornerGlow("BottomLeft", glowSize)
		cornerGlow("BottomRight", glowSize)
	end

	build()

	local rebuildQueued = false
	local camConn
	local function hookCamera()
		if camConn then camConn:Disconnect() end
		local cam = workspace.CurrentCamera
		if not cam then return end
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if rebuildQueued then return end
			rebuildQueued = true
			task.delay(0.1, function()
				rebuildQueued = false
				if frame.Parent then build() end
			end)
		end)
	end
	hookCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
end

return GlowEngine
