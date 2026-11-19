--════════════════════════════════════════════════════════════════════════════
-- 📐 HudLayoutClient — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (NOUVEAU)
--  Applique ReplicatedStorage ▸ HudLayout : les boutons de l'écran gardent leurs
--  écarts sur TOUS les formats d'écran. Réglages et explications dans HudLayout.
--════════════════════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function layoutGroup(g)
	local live = {}
	for _, it in ipairs(g.items) do
		local gui = playerGui:FindFirstChild(it.gui)
		local fr = gui and gui:FindFirstChild(it.frame)
		if fr and fr:IsA("GuiObject") and gui:IsA("LayerCollector") then
			table.insert(live, { fr = fr, gui = gui, d = designOf(fr, it.x) })
		end
	end
	if #live == 0 then return end
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, e in ipairs(live) do
		minX = math.min(minX, e.d.x) ; maxX = math.max(maxX, e.d.x + e.d.w)
		minY = math.min(minY, e.d.y) ; maxY = math.max(maxY, e.d.y + e.d.h)
	end
	for _, e in ipairs(live) do
		local GW, GH = e.gui.AbsoluteSize.X, e.gui.AbsoluteSize.Y
		if GW > 1 and GH > 1 then
			local u = GH / REF_H                      -- tout suit la HAUTEUR de l'écran
			local k = 1                               -- rétrécit le bloc s'il ne tient plus en largeur
			local x, y
			if g.anchor == "center" then
				local span = math.max(math.abs(maxX - REF_W / 2), math.abs(minX - REF_W / 2)) * 2 * u
				if span > GW * g.maxWidth then k = GW * g.maxWidth / span end
				x = GW / 2 + (e.d.x - REF_W / 2) * u * k
				y = e.d.y * u * k
			else
				local right = maxX * u
				if right > GW * g.maxWidth then k = GW * g.maxWidth / right end
				local cy = (minY + maxY) / 2
				x = e.d.x * u * k
				y = (cy + (e.d.y - cy) * k) * u
			end
			local w, h = e.d.w * u * k, e.d.h * u * k
			local a = e.fr.AnchorPoint
			local size = UDim2.fromOffset(w, h)
			local pos = UDim2.fromOffset(x + a.X * w, y + a.Y * h)
			e.fr:SetAttribute("HudBaseSize", size)   -- lu par les animations de survol
			e.fr:SetAttribute("HudBasePos", pos)
			e.fr.Size, e.fr.Position = size, pos
		end
	end
end

local queued = false
local function relayout()
	if queued then return end
	queued = true
	task.defer(function()
		queued = false
		for _, g in pairs(HL.Groups) do pcall(layoutGroup, g) end
	end)
end

-- ce qu'il faut surveiller : la taille de l'écran et les ScreenGui (recréés au respawn)
local watched = setmetatable({}, { __mode = "k" })
local wanted = {}
for _, g in pairs(HL.Groups) do for _, it in ipairs(g.items) do wanted[it.gui] = true end end
local function watch(gui)
	if not wanted[gui.Name] or watched[gui] or not gui:IsA("LayerCollector") then return end
	watched[gui] = true
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
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
