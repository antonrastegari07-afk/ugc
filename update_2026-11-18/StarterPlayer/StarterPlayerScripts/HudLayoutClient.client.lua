--════════════════════════════════════════════════════════════════════════════
-- 📐 HudLayoutClient — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (NOUVEAU)
--  Applique ReplicatedStorage ▸ HudLayout : les boutons de l'écran gardent leurs
--  écarts sur TOUS les formats d'écran, et le bloc du haut évite les boutons du haut
--  (Roblox + How To Play / série de jours), où qu'ils soient selon l'appareil.
--  Réglages et explications dans HudLayout.
--════════════════════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")

local HL = require(ReplicatedStorage:WaitForChild("HudLayout"))
if not HL.Enabled then return end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local REF_W, REF_H = HL.REF_W, HL.REF_H

-- disposition de Studio relue UNE fois par cadre (un nouveau cadre au respawn = relu)
local design = setmetatable({}, { __mode = "k" })

local function designOf(frame, xOverride)
	local d = design[frame]
	if d then return d end
	local s, p = frame.Size, frame.Position
	local w = s.X.Scale * REF_W + s.X.Offset
	local h = s.Y.Scale * REF_H + s.Y.Offset
	local ar = frame:FindFirstChildOfClass("UIAspectRatioConstraint")
	if ar and ar.AspectRatio > 0 and w > 0 and h > 0 then
		local r = ar.AspectRatio
		if ar.AspectType == Enum.AspectType.ScaleWithParentSize then
			if ar.DominantAxis == Enum.DominantAxis.Width then h = w / r else w = h * r end
		elseif w / h > r then
			w = h * r
		else
			h = w / r
		end
	end
	local x = (xOverride or p.X.Scale) * REF_W + p.X.Offset
	local y = p.Y.Scale * REF_H + p.Y.Offset
	local a = frame.AnchorPoint
	d = { x = x - a.X * w, y = y - a.Y * h, w = w, h = h }   -- coin haut-gauche
	design[frame] = d
	return d
end

-- 🚧 boutons du haut de l'écran (coordonnées ÉCRAN) : ceux de Roblox + les tiens
local function topButtonRects()
	local rects = {}
	local cam = workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 0
	local ok, inset = pcall(function() return GuiService.TopbarInset end)
	if ok and typeof(inset) == "Rect" and inset.Height > 0 then
		-- TopbarInset = la place LIBRE entre les boutons Roblox de gauche et ceux de droite
		if inset.Min.X > 0 then table.insert(rects, { x0 = 0, x1 = inset.Min.X, y0 = 0, y1 = inset.Max.Y }) end
		if vw > 0 and inset.Max.X < vw then table.insert(rects, { x0 = inset.Max.X, x1 = vw, y0 = 0, y1 = inset.Max.Y }) end
	else
		local top = GuiService:GetGuiInset()
		table.insert(rects, { x0 = 0, x1 = 140, y0 = 0, y1 = math.max(top.Y, 36) })
	end
	for _, name in ipairs(HL.TopButtonGuis or {}) do
		local g = playerGui:FindFirstChild(name)
		if g and g:IsA("LayerCollector") and g.Enabled then
			local gp = g.AbsolutePosition
			for _, c in ipairs(g:GetChildren()) do
				if c:IsA("GuiObject") and c.Visible and c.AbsoluteSize.X > 1 then
					local p = gp + c.AbsolutePosition
					table.insert(rects, { x0 = p.X, x1 = p.X + c.AbsoluteSize.X, y0 = p.Y, y1 = p.Y + c.AbsoluteSize.Y })
				end
			end
		end
	end
	return rects
end

local function layoutGroup(g)
	local live = {}
	for _, it in ipairs(g.items) do
		local gui = playerGui:FindFirstChild(it.gui)
		local fr = gui and gui:FindFirstChild(it.frame)
		if fr and fr:IsA("GuiObject") and gui:IsA("LayerCollector") then
			local d = designOf(fr, it.x)
			-- 🛡️ un cadre qu'un autre script a envoyé HORS de l'écran (pour le cacher) est ignoré :
			--    sinon le bloc paraissait immense et tout rétrécissait jusqu'à disparaître.
			local onScreen = d.w > 0 and d.h > 0 and d.x > -REF_W * 0.25 and d.x < REF_W * 1.25
				and d.y > -REF_H * 0.25 and d.y < REF_H * 1.25
			if onScreen then table.insert(live, { fr = fr, gui = gui, d = d }) end
		end
	end
	if #live == 0 then return end
	local gui0 = live[1].gui
	local GW, GH = gui0.AbsoluteSize.X, gui0.AbsoluteSize.Y
	if GW <= 1 or GH <= 1 then return end
	local u = GH / REF_H                         -- tout suit la HAUTEUR de l'écran
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, e in ipairs(live) do
		minX = math.min(minX, e.d.x) ; maxX = math.max(maxX, e.d.x + e.d.w)
		minY = math.min(minY, e.d.y) ; maxY = math.max(maxY, e.d.y + e.d.h)
	end

	local k, cx = 1, nil   -- k = rétrécissement du bloc, cx = centre (bloc centré)
	if g.anchor == "center" then
		local eL, eR = (REF_W / 2 - minX) * u, (maxX - REF_W / 2) * u   -- débords gauche / droite du centre
		local a, b = 0, GW                                              -- place disponible en largeur
		if g.avoidTopButtons then
			local top = gui0.AbsolutePosition.Y + minY * u
			local bottom = gui0.AbsolutePosition.Y + maxY * u
			for _, r in ipairs(topButtonRects()) do
				if r.y1 > top - 2 and r.y0 < bottom then   -- même bande de hauteur que le bloc
					if (r.x0 + r.x1) / 2 < GW / 2 then a = math.max(a, r.x1 + (HL.TopGap or 10))
					else b = math.min(b, r.x0 - (HL.TopGap or 10)) end
				end
			end
		end
		local margin = GW * (1 - g.maxWidth) / 2
		a, b = math.max(a, margin), math.min(b, GW - margin)
		if eL + eR > b - a then k = math.max(0.2, (b - a) / (eL + eR)) end
		-- centré si possible, sinon décalé juste assez pour éviter les boutons
		cx = math.clamp(GW / 2, a + eL * k, math.max(a + eL * k, b - eR * k))
	else
		local right = maxX * u
		if right > GW * g.maxWidth then k = GW * g.maxWidth / right end
	end

	for _, e in ipairs(live) do
		local x, y
		if g.anchor == "center" then
			x = cx + (e.d.x - REF_W / 2) * u * k
			y = e.d.y * u * k
		else
			local cy = (minY + maxY) / 2
			x = e.d.x * u * k
			y = (cy + (e.d.y - cy) * k) * u
		end
		local w, h = e.d.w * u * k, e.d.h * u * k
		local an = e.fr.AnchorPoint
		local size = UDim2.fromOffset(w, h)
		local pos = UDim2.fromOffset(x + an.X * w, y + an.Y * h)
		e.fr:SetAttribute("HudBaseSize", size)   -- lu par les animations de survol
		e.fr:SetAttribute("HudBasePos", pos)
		e.fr.Size, e.fr.Position = size, pos
	end
end

local queued = false
local function relayout()
	if queued then return end
	queued = true
	task.defer(function()
		queued = false
		for _, g in pairs(HL.Groups) do
			local ok, err = pcall(layoutGroup, g)
			if not ok then warn("[HudLayout] " .. tostring(err)) end
		end
	end)
end

-- ce qu'il faut surveiller : la taille de l'écran, les ScreenGui (recréés au respawn)
-- et les boutons du haut (ils apparaissent un peu après le chargement)
local watched = setmetatable({}, { __mode = "k" })
local wanted = {}
for _, g in pairs(HL.Groups) do for _, it in ipairs(g.items) do wanted[it.gui] = true end end
for _, n in ipairs(HL.TopButtonGuis or {}) do wanted[n] = true end
local function watch(gui)
	if not wanted[gui.Name] or watched[gui] or not gui:IsA("LayerCollector") then return end
	watched[gui] = true
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	gui:GetPropertyChangedSignal("Enabled"):Connect(relayout)
	gui.ChildAdded:Connect(relayout)
	relayout()
end
for _, c in ipairs(playerGui:GetChildren()) do watch(c) end
playerGui.ChildAdded:Connect(function(c) task.defer(watch, c) end)
local function watchCam()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(relayout) end
end
watchCam()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() watchCam() ; relayout() end)
pcall(function() GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(relayout) end)
relayout()
task.delay(3, relayout)   -- filet : les boutons du haut sont créés par script un peu après
