--════════════════════════════════════════════════════════════════════════════
-- 📐 HudLayoutClient — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (NOUVEAU, v2)
--  Applique ReplicatedStorage ▸ HudLayout. Réglages et explications dans HudLayout.
--════════════════════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local HL = require(ReplicatedStorage:WaitForChild("HudLayout"))
if not HL.Enabled then return end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local REF_W, REF_H = HL.REF_W, HL.REF_H
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local applied = setmetatable({}, { __mode = "k" })   -- [frame] = { size, pos } posés par nous

local function viewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and vp.X > 1 and vp.Y > 1 then return vp.X, vp.Y end
	return nil
end

-- 📍 COORDONNÉES ÉCRAN. Roblox donne TOUS les AbsolutePosition à partir du DESSOUS de sa
--    barre du haut (même pour un ScreenGui qui couvre la barre : il est alors en Y négatif).
--    Donc, pour n'importe quel objet : position à l'écran = AbsolutePosition + GetGuiInset().
--    (v17 se trompait ici : le bloc du haut sortait par le haut de l'écran.)
local GuiService = game:GetService("GuiService")
local function inset()
	local tl = GuiService:GetGuiInset()
	return tl.X, tl.Y
end
local function origin(gui)   -- coin haut-gauche du ScreenGui, en coordonnées ÉCRAN
	local ix, iy = inset()
	local p = gui.AbsolutePosition
	return p.X + ix, p.Y + iy
end

-- 🚧 boutons du haut (coordonnées ÉCRAN) : seulement de VRAIS boutons, visibles, de taille normale
local function topButtonRects(VW, VH)
	local rects = {}
	local coreW = IS_TOUCH and HL.RobloxIconsWidth.touch or HL.RobloxIconsWidth.pc
	table.insert(rects, { x0 = 0, x1 = coreW, y0 = 0, y1 = 48 })   -- icônes Roblox (haut gauche)
	for _, name in ipairs(HL.TopButtonGuis or {}) do
		local g = playerGui:FindFirstChild(name)
		if g and g:IsA("LayerCollector") and g.Enabled then
			local ix, iy = inset()
			local gp = Vector2.new(ix, iy)   -- AbsolutePosition d'un objet = déjà absolu (sous la barre)
			for _, c in ipairs(g:GetDescendants()) do
				if c:IsA("GuiButton") and c.Visible then
					local s = c.AbsoluteSize
					-- garde-fou : un « bouton » géant (fond, voile, panneau) n'est pas un bouton du haut
					if s.X > 2 and s.Y > 2 and s.X < VW * 0.3 and s.Y < VH * 0.2 then
						local p = gp + c.AbsolutePosition
						if p.Y < VH * 0.2 then
							table.insert(rects, { x0 = p.X, x1 = p.X + s.X, y0 = p.Y, y1 = p.Y + s.Y })
						end
					end
				end
			end
		end
	end
	return rects
end

-- screen = true : (sx, sy) en coordonnées ÉCRAN (bloc du haut) ; sinon coordonnées du ScreenGui
local function apply(fr, gui, sx, sy, w, h, screen, VW)
	local gx, gy = 0, 0
	if screen then gx, gy = origin(gui) end
	local an = fr.AnchorPoint
	local size = UDim2.fromOffset(w, h)
	local pos = UDim2.fromOffset(sx - gx + an.X * w, sy - gy + an.Y * h)
	applied[fr] = { size = size, pos = pos }
	fr:SetAttribute("HudBaseSize", size)   -- lu par les animations de survol
	fr:SetAttribute("HudBasePos", pos)
	fr.Size, fr.Position = size, pos
end

local function layoutGroup(g, VW, VH, report)
	local live = {}
	for _, it in ipairs(g.items) do
		local gui = playerGui:FindFirstChild(it.gui)
		local fr = gui and gui:FindFirstChild(it.frame)
		if fr and fr:IsA("GuiObject") and gui:IsA("LayerCollector") then
			table.insert(live, { fr = fr, gui = gui, it = it })
		end
	end
	if #live == 0 then return end
	local u = VH / REF_H                         -- tout suit la HAUTEUR de l'écran
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, e in ipairs(live) do
		minX = math.min(minX, e.it.x) ; maxX = math.max(maxX, e.it.x + e.it.w)
		minY = math.min(minY, e.it.y) ; maxY = math.max(maxY, e.it.y + e.it.h)
	end

	if g.anchor == "center" then
		local eL, eR = (REF_W / 2 - minX) * u, (maxX - REF_W / 2) * u
		-- haut VISIBLE du bloc (titres qui dépassent compris)
		local visTop = math.huge
		for _, e in ipairs(live) do visTop = math.min(visTop, e.it.y - (e.it.over or 0)) end
		local margin = VW * (1 - g.maxWidth) / 2
		local function room(top, bottom)
			local a, b = margin, VW - margin
			if g.avoidTopButtons then
				for _, r in ipairs(topButtonRects(VW, VH)) do
					if r.y1 > top - 2 and r.y0 < bottom + 2 then
						if (r.x0 + r.x1) / 2 < VW / 2 then a = math.max(a, r.x1 + HL.TopGap)
						else b = math.min(b, r.x0 - HL.TopGap) end
					end
				end
			end
			return a, b
		end
		-- ⬆️ tout en haut : même hauteur que les boutons du haut (How To Play…), sinon 6 px
		local function topFor(k)
			if not g.stickToTop then return 0 end
			local want = math.huge
			for _, r in ipairs(topButtonRects(VW, VH)) do
				if r.x0 > (IS_TOUCH and HL.RobloxIconsWidth.touch or HL.RobloxIconsWidth.pc) - 1 then want = math.min(want, r.y0) end
			end
			if want == math.huge then want = 6 end
			return want - visTop * u * k
		end
		local dy = topFor(1)
		local a, b = room(minY * u + dy, maxY * u + dy)
		local k = 1
		if eL + eR > b - a then k = (b - a) / (eL + eR) ; dy = topFor(k) end
		if k < (g.minScale or 0.75) then
			-- pas assez de place à côté des boutons du haut : on passe JUSTE EN DESSOUS
			local below = 0
			for _, r in ipairs(topButtonRects(VW, VH)) do below = math.max(below, r.y1) end
			dy = below + HL.TopGap - visTop * u
			a, b = room(minY * u + dy, maxY * u + dy)
			k = math.min(1, (b - a) / (eL + eR))
			k = math.max(k, 0.5)
		end
		local cx = math.clamp(VW / 2, a + eL * k, math.max(a + eL * k, b - eR * k))
		for _, e in ipairs(live) do
			local it = e.it
			apply(e.fr, e.gui, cx + (it.x - REF_W / 2) * u * k, it.y * u * k + dy, it.w * u * k, it.h * u * k, true, VW)
		end
		if report then print(("[HudLayout] haut : écran %dx%d · place %d→%d · échelle %.2f · centre %d · décalage bas %d"):format(VW, VH, a, b, k, cx, dy)) end
	else
		local k = 1
		local right = maxX * u
		if right > VW * g.maxWidth then k = math.max(0.6, VW * g.maxWidth / right) end
		local cy = (minY + maxY) / 2
		for _, e in ipairs(live) do
			local it = e.it
			apply(e.fr, e.gui, it.x * u * k, (cy + (it.y - cy) * k) * u, it.w * u * k, it.h * u * k)
		end
		if report then print(("[HudLayout] gauche : écran %dx%d · échelle %.2f"):format(VW, VH, k)) end
	end
end

local queued = false
local function relayout()
	if queued then return end
	queued = true
	task.defer(function()
		queued = false
		local VW, VH = viewport()
		if not VW then return end
		for _, g in pairs(HL.Groups) do
			local ok, err = pcall(layoutGroup, g, VW, VH, HL.Debug)
			if not ok then warn("[HudLayout] " .. tostring(err)) end
		end
	end)
end

-- 🛡️ un autre script déplace un de ces boutons → remis à sa place (sauf pendant
--    l'animation de survol). S'il insiste (bagarre), on le laisse faire et on le signale.
local fights = setmetatable({}, { __mode = "k" })
local function guard(fr)
	if fights[fr] then return end
	fights[fr] = { n = 0, t0 = os.clock() }
	local function check()
		local a = applied[fr]
		if not a or fr.Size == a.size and fr.Position == a.pos then return end
		if (fr:GetAttribute("HudAnimUntil") or 0) > os.clock() then return end
		local f = fights[fr]
		if os.clock() - f.t0 > 3 then f.n, f.t0 = 0, os.clock() end
		f.n += 1
		if f.n > 10 then
			if f.n == 11 then warn("[HudLayout] un autre script déplace sans arrêt " .. fr:GetFullName() .. " : je le laisse faire.") end
			return
		end
		task.defer(function()
			local a2 = applied[fr]
			if a2 and (fr:GetAttribute("HudAnimUntil") or 0) <= os.clock() then fr.Size, fr.Position = a2.size, a2.pos end
		end)
	end
	fr:GetPropertyChangedSignal("Position"):Connect(check)
	fr:GetPropertyChangedSignal("Size"):Connect(check)
end

-- ce qu'il faut surveiller : la taille de l'écran, les ScreenGui (recréés au respawn)
-- et les boutons du haut (créés par script un peu après le chargement)
local watched = setmetatable({}, { __mode = "k" })
local wanted = {}
for _, g in pairs(HL.Groups) do for _, it in ipairs(g.items) do wanted[it.gui] = true end end
for _, n in ipairs(HL.TopButtonGuis or {}) do wanted[n] = true end
local function watch(gui)
	if not wanted[gui.Name] or watched[gui] or not gui:IsA("LayerCollector") then return end
	watched[gui] = true
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayout)
	gui:GetPropertyChangedSignal("Enabled"):Connect(relayout)
	gui.DescendantAdded:Connect(relayout)
	for _, g in pairs(HL.Groups) do
		for _, it in ipairs(g.items) do
			if it.gui == gui.Name then
				local fr = gui:FindFirstChild(it.frame)
				if fr and fr:IsA("GuiObject") then guard(fr) end
			end
		end
	end
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
relayout()
task.delay(2, relayout)   -- filet : boutons du haut créés par script un peu après
task.delay(6, relayout)
