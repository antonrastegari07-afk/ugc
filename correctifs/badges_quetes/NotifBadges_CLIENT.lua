--════════════════════════════════════════════════════════════════════════════
-- ❗ NotifBadges — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (NOUVEAU)
--
--  REMPLACE les 2 anciens LocalScripts (à SUPPRIMER) :
--    • « exclamation quests button »   (le ! des quêtes)
--    • « exclamationpoint pulsion »    (l'effet d'onde de tous les !)
--
--  1) ❗ QUÊTES : le ! du bouton Quests s'allume SEULEMENT si une quête de la liste
--     affiche « Claim! ». Plus de vérification toutes les 0,5 s : il réagit au
--     changement de texte des boutons (0 calcul quand rien ne bouge).
--     (L'ancien regardait si le bouton était « Active » : la quête Feedback cachée,
--      la chasse aux œufs, etc. le laissaient allumé pour rien.)
--  2) 🎁 RÉCOMPENSES : le bouton Daily a 2 ! (daily + playtime). On n'en montre
--     plus qu'UN, même si les deux récompenses sont prêtes.
--  3) ⬆️ AU-DESSUS : les ! des boutons du HUD (Quests, Daily, Shops…) sont dessinés
--     dans une interface à part, au-dessus des autres boutons → jamais cachés.
--     Ils suivent leur bouton (position, taille, animation de survol) et
--     disparaissent avec lui (menu ouvert, bouton caché…).
--  4) 🌊 ONDE : même effet qu'avant (onde blanche + petit « pop »), mais seulement
--     quand le ! est vraiment à l'écran (avant : il tournait aussi menus fermés).
--
--  Les scripts qui allument/éteignent les ! (daily, playtime, shops…) ne changent pas :
--  ils mettent toujours .Visible sur leur ExclamationPoint, ce script s'occupe du reste.
--════════════════════════════════════════════════════════════════════════════
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ⚙️ RÉGLAGES
local OVERLAY_DISPLAY_ORDER = 1     -- au-dessus des boutons du HUD (tous à 0)
local PULSE_DURATION = 1.2          -- durée d'une onde
local PULSE_GAP      = 0.3          -- pause entre deux ondes
local PULSE_SIZE     = 1.8          -- taille finale de l'onde (× taille du !)
local POP_SCALE      = 1.15         -- « pop » du ! à chaque onde
local POP_DURATION   = 0.2
local QUEST_GUI      = "Quest"
local QUEST_SCROLL   = { "ShopFrame", "ScrollingFrame" }
local QUEST_BADGE    = { "Frame", "ExclamationPoint2" }
local CLAIM_TEXT     = "Claim!"

local function isBadge(o)
	return o:IsA("ImageLabel") and o.Name:match("^ExclamationPoint") ~= nil
end

--════════════════════════════════════════════════════════════
-- 👁️ « vraiment à l'écran » : l'objet et TOUS ses parents visibles + ScreenGui allumée
--════════════════════════════════════════════════════════════
local function watchShown(obj, onChange)
	local conns, last = {}, nil
	local rebuild
	local function clear()
		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)
	end
	local function compute()
		local o = obj
		while o and o ~= playerGui do
			if o:IsA("ScreenGui") then
				if not o.Enabled or o.Parent ~= playerGui then return false end
				return true
			end
			if o:IsA("GuiObject") and not o.Visible then return false end
			o = o.Parent
		end
		return false
	end
	local function check()
		local s = compute()
		if s ~= last then last = s ; onChange(s) end
	end
	rebuild = function()
		clear()
		local o = obj
		while o and o ~= playerGui do
			if o:IsA("ScreenGui") then
				table.insert(conns, o:GetPropertyChangedSignal("Enabled"):Connect(check))
				break
			end
			if o:IsA("GuiObject") then
				table.insert(conns, o:GetPropertyChangedSignal("Visible"):Connect(check))
			end
			o = o.Parent
		end
		table.insert(conns, obj.AncestryChanged:Connect(function() task.defer(rebuild) end))
		check()
	end
	rebuild()
	return { stop = clear, get = function() return last end }
end

--════════════════════════════════════════════════════════════
-- 🌊 onde + pop (un seul jeu de tweens par !, réutilisés)
--════════════════════════════════════════════════════════════
local function makePulse(host, image, zIndex)
	local wave = Instance.new("Frame")
	wave.Name = "WaveCircle"
	wave.BackgroundTransparency = 1
	wave.AnchorPoint = Vector2.new(0.5, 0.5)
	wave.Size = UDim2.fromScale(1, 1)
	wave.ZIndex = zIndex
	wave.Visible = false
	local asp = Instance.new("UIAspectRatioConstraint")
	asp.Parent = wave
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = wave
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = wave
	local waveScale = Instance.new("UIScale")
	waveScale.Parent = wave
	wave.Parent = host

	local popScale = image:FindFirstChild("BadgePop") or Instance.new("UIScale")
	popScale.Name = "BadgePop"
	popScale.Parent = image

	local info = TweenInfo.new(PULSE_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local tGrow = TweenService:Create(waveScale, info, { Scale = PULSE_SIZE })
	local tFade = TweenService:Create(stroke, info, { Transparency = 1 })
	local tPop = TweenService:Create(popScale,
		TweenInfo.new(POP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Scale = POP_SCALE })

	local running, token = false, 0
	local P = {}
	-- centre / taille en pixels écran, relatifs au coin de « host » ; converti en scale
	-- (juste même si un UIScale agrandit le menu)
	function P.place(center, size)
		local hs = host.AbsoluteSize
		if hs.X < 1 or hs.Y < 1 then return end
		wave.Position = UDim2.fromScale(center.X / hs.X, center.Y / hs.Y)
		wave.Size = UDim2.fromScale(size / hs.X, size / hs.Y)
		stroke.Thickness = math.clamp(size * 0.12, 2, 8)
	end
	function P.set(on)
		if on == running then return end
		running = on
		token += 1
		if not on then
			tGrow:Cancel() ; tFade:Cancel() ; tPop:Cancel()
			wave.Visible = false
			popScale.Scale = 1
			return
		end
		local my = token
		task.spawn(function()
			while running and token == my do
				waveScale.Scale = 0.6
				stroke.Transparency = 0
				wave.Visible = true
				tGrow:Play() ; tFade:Play() ; tPop:Play()
				task.wait(PULSE_DURATION + PULSE_GAP)
			end
		end)
	end
	function P.destroy()
		P.set(false)
		wave:Destroy()
	end
	return P
end

--════════════════════════════════════════════════════════════
-- ⬆️ INTERFACE DES ! DU HUD (au-dessus des autres boutons)
--════════════════════════════════════════════════════════════
local overlay = Instance.new("ScreenGui")
overlay.Name = "HudBadges"
overlay.ResetOnSpawn = false
overlay.DisplayOrder = OVERLAY_DISPLAY_ORDER
overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
overlay.IgnoreGuiInset = true
overlay.Parent = playerGui
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = overlay

-- Un bouton du HUD = un objet posé directement dans une ScreenGui, qui contient des !
-- → UN seul ! affiché pour lui (le bouton Daily en a 2 : daily + playtime).
local launchers = {}   -- [frame] = état

local function setupLauncher(frame)
	if launchers[frame] then return launchers[frame] end
	local L = { icons = {}, conns = {} }
	launchers[frame] = L

	local img = Instance.new("ImageLabel")
	img.Name = "Badge_" .. frame.Parent.Name
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.ZIndex = 3
	img.Visible = false
	img.Parent = root
	local pulse = makePulse(root, img, 2)
	L.img, L.pulse = img, pulse

	local current, shown = nil, false
	local posConns = {}
	local function place()
		if not current then return end
		local s = current.AbsoluteSize
		local c = current.AbsolutePosition + s / 2 - root.AbsolutePosition
		img.Position = UDim2.fromOffset(c.X, c.Y)
		img.Size = UDim2.fromOffset(s.X, s.Y)
		img.Rotation = current.Rotation
		pulse.place(c, math.max(s.X, s.Y))
	end
	local function follow(icon)
		for _, c in ipairs(posConns) do c:Disconnect() end
		table.clear(posConns)
		current = icon
		if not icon then return end
		img.Image = icon.Image
		img.ImageColor3 = icon.ImageColor3
		img.ScaleType = icon.ScaleType
		img.ImageRectOffset, img.ImageRectSize = icon.ImageRectOffset, icon.ImageRectSize
		for _, p in ipairs({ "AbsolutePosition", "AbsoluteSize", "Rotation" }) do
			table.insert(posConns, icon:GetPropertyChangedSignal(p):Connect(place))
		end
		place()
	end
	table.insert(L.conns, root:GetPropertyChangedSignal("AbsolutePosition"):Connect(place))
	table.insert(L.conns, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))

	local function refresh()
		local pick
		for _, icon in ipairs(L.icons) do
			if icon.Parent == frame and icon.Visible and (not pick or icon.Name < pick.Name) then pick = icon end
		end
		if pick ~= current then follow(pick) end
		local on = pick ~= nil and shown
		img.Visible = on
		pulse.set(on)
	end
	L.refresh = refresh

	L.watch = watchShown(frame, function(s) shown = s ; refresh() end)

	function L.add(icon)
		if table.find(L.icons, icon) then return end
		table.insert(L.icons, icon)
		icon.ImageTransparency = 1          -- l'original reste le « signal » (Visible), on dessine la copie
		local c1 = icon:GetPropertyChangedSignal("Visible"):Connect(refresh)
		local c2
		c2 = icon.AncestryChanged:Connect(function()
			if icon.Parent ~= frame then
				c1:Disconnect() ; c2:Disconnect()
				local i = table.find(L.icons, icon)
				if i then table.remove(L.icons, i) end
				refresh()
			end
		end)
		refresh()
	end

	table.insert(L.conns, frame.AncestryChanged:Connect(function()
		if frame:IsDescendantOf(playerGui) then return end
		L.watch.stop()
		for _, c in ipairs(L.conns) do c:Disconnect() end
		for _, c in ipairs(posConns) do c:Disconnect() end
		pulse.destroy()
		img:Destroy()
		launchers[frame] = nil
	end))
	return L
end

--════════════════════════════════════════════════════════════
-- 🌊 ! DANS LES MENUS (onglets, cases de récompense…) : onde sur place, comme avant
--════════════════════════════════════════════════════════════
local inPlace = {}
local function setupInPlace(icon)
	if inPlace[icon] then return end
	local parent = icon.Parent
	if not parent then return end
	local pulse = makePulse(parent, icon, math.max(icon.ZIndex - 1, 1))
	local shown = false
	local function place()
		local s = icon.AbsoluteSize
		local c = icon.AbsolutePosition + s / 2 - parent.AbsolutePosition
		pulse.place(c, math.max(s.X, s.Y))
	end
	local conns = {}
	for _, p in ipairs({ "AbsolutePosition", "AbsoluteSize" }) do
		table.insert(conns, icon:GetPropertyChangedSignal(p):Connect(place))
	end
	if parent:IsA("GuiObject") then
		table.insert(conns, parent:GetPropertyChangedSignal("AbsolutePosition"):Connect(place))
		table.insert(conns, parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	end
	local function upd() pulse.set(shown and icon.ImageTransparency < 1) end
	table.insert(conns, icon:GetPropertyChangedSignal("ImageTransparency"):Connect(upd))
	local w = watchShown(icon, function(s) shown = s ; if s then place() end ; upd() end)
	inPlace[icon] = true
	icon.Destroying:Connect(function()
		w.stop()
		for _, c in ipairs(conns) do c:Disconnect() end
		pulse.destroy()
		inPlace[icon] = nil
	end)
end

local function onBadge(icon)
	if not isBadge(icon) then return end
	local parent = icon.Parent
	if parent and parent:IsA("GuiObject") and parent.Parent and parent.Parent:IsA("ScreenGui")
		and parent.Parent.Name ~= overlay.Name then
		setupLauncher(parent).add(icon)
	else
		setupInPlace(icon)
	end
end

for _, d in ipairs(playerGui:GetDescendants()) do
	if not d:IsDescendantOf(overlay) then onBadge(d) end
end
playerGui.DescendantAdded:Connect(function(d)
	if d:IsDescendantOf(overlay) or not isBadge(d) then return end
	task.defer(onBadge, d)
end)

--════════════════════════════════════════════════════════════
-- ❗ QUÊTES : allumé seulement si une quête VISIBLE de la liste affiche « Claim! »
--════════════════════════════════════════════════════════════
local function findPath(from, path)
	local o = from
	for _, n in ipairs(path) do o = o and o:FindFirstChild(n) end
	return o
end

local function startQuestWatcher(questGui)
	local scroll, badge
	for _ = 1, 40 do
		scroll = findPath(questGui, QUEST_SCROLL)
		badge = findPath(questGui, QUEST_BADGE)
		if scroll and badge then break end
		task.wait(0.5)
	end
	if not (scroll and badge) then
		warn("[NotifBadges] liste des quêtes ou ! introuvable dans « " .. QUEST_GUI .. " »")
		return
	end

	local tracked = {}       -- [bouton] = { conns }
	local pending = false
	local function evaluate()
		pending = false
		local any = false
		for btn in pairs(tracked) do
			if btn.Text == CLAIM_TEXT then
				-- la quête doit être affichée dans la liste (Frame visible, bouton visible)
				local row = btn
				while row and row.Parent ~= scroll do row = row.Parent end
				local ok = row ~= nil
				local o = btn
				while ok and o and o ~= scroll do
					if o:IsA("GuiObject") and not o.Visible then ok = false end
					o = o.Parent
				end
				if ok then any = true break end
			end
		end
		if badge.Visible ~= any then badge.Visible = any end
	end
	local function schedule()
		if pending then return end
		pending = true
		task.defer(evaluate)
	end

	local function track(btn)
		if tracked[btn] or not btn:IsA("TextButton") then return end
		local conns = {}
		tracked[btn] = conns
		table.insert(conns, btn:GetPropertyChangedSignal("Text"):Connect(schedule))
		-- visibilité du bouton et de ses parents jusqu'à la liste
		local o = btn
		while o and o ~= scroll do
			if o:IsA("GuiObject") then
				table.insert(conns, o:GetPropertyChangedSignal("Visible"):Connect(schedule))
			end
			o = o.Parent
		end
		table.insert(conns, btn.AncestryChanged:Connect(function()
			if not btn:IsDescendantOf(scroll) then
				for _, c in ipairs(conns) do c:Disconnect() end
				tracked[btn] = nil
				schedule()
			end
		end))
		schedule()
	end

	for _, d in ipairs(scroll:GetDescendants()) do track(d) end
	scroll.DescendantAdded:Connect(function(d) task.defer(track, d) end)
	evaluate()
end

local function onGui(g)
	if g.Name == QUEST_GUI and g:IsA("ScreenGui") then task.spawn(startQuestWatcher, g) end
end
for _, g in ipairs(playerGui:GetChildren()) do onGui(g) end
playerGui.ChildAdded:Connect(onGui)

-- 🛡️ les 2 anciens scripts encore là ? (ils se battraient avec celui-ci)
task.delay(5, function()
	local ps = player:FindFirstChild("PlayerScripts")
	for _, n in ipairs({ "exclamation quests button ", "exclamation quests button", "exclamationpoint pulsion" }) do
		local s = ps and ps:FindFirstChild(n)
		if s then warn("⚠️ [NotifBadges] supprime l'ancien LocalScript « " .. n .. " » (StarterPlayerScripts)") end
	end
end)

print("✅ NotifBadges chargé")
