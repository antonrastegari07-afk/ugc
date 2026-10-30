--════════════════════════════════════════════════════════════════════════════
-- ✨ QuestListPolish — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (NOUVEAU)
--
--  🔘 ENABLED = false (ligne ci-dessous) → ce script ne fait RIEN : la liste des
--     quêtes redevient EXACTEMENT comme avant (aucun autre script n'a été modifié).
--
--  Ce qu'il fait (purement visuel, aucune donnée, aucune récompense) :
--   1) 🎨 Quête FINIE (« Claimed ») : même look partout, celui de « Like the game » :
--        bouton gris « Claimed » (texte gris clair + dégradé), barre grise vide.
--        (Magnum jaune « Magnum ✓ », chasses « Completed ✓ »… passent au même gris.)
--   2) 🌑 + un voile noir semi-transparent sur toute la quête, avec le check vert des
--        récompenses Playtime et « Completed » en blanc, centrés.
--   3) ↕️ ORDRE (de haut en bas) : « Claim! » → en cours → en cooldown → finies.
--        Dans chaque groupe, l'ordre de QUEST_SYSTEM_CONFIG est gardé.
--        La liste est triée à l'OUVERTURE du menu : rien ne bouge pendant qu'on lit.
--   4) 🎬 Quand le joueur récupère une quête, menu ouvert : il voit « Claimed »,
--        puis le voile apparaît en fondu, puis la quête glisse lentement à sa
--        nouvelle place pendant que les autres se décalent en douceur.
--════════════════════════════════════════════════════════════════════════════
local ENABLED = true
if not ENABLED then return end

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ⚙️ RÉGLAGES
local QUEST_GUI     = "Quest"
local MENU_PATH     = { "ShopFrame" }                    -- le menu des quêtes (visible = ouvert)
local SCROLL_PATH   = { "ShopFrame", "ScrollingFrame" }
local CHECK_IMAGE   = "rbxassetid://73934869622371"      -- le check vert des récompenses Playtime
local FILM_TRANSPARENCY = 0.45                           -- voile : 0 = noir plein, 1 = invisible
local DONE_TEXT     = "Completed"
local WAIT_BEFORE_FILM = 1.0     -- s : le joueur voit « Claimed » avant le voile
local FILM_FADE        = 0.5     -- s : apparition du voile
local WAIT_BEFORE_MOVE = 0.5     -- s : pause avant de glisser
local MOVE_TIME        = 0.9     -- s : durée du glissement (lent et doux)

-- look « Claimed » (celui de la quête Like the game)
local GREY      = Color3.fromRGB(128, 128, 128)
local TEXT_GREY = Color3.fromRGB(220, 220, 220)
local DONE_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 235, 235)),
	ColorSequenceKeypoint.new(1,   Color3.fromRGB(170, 170, 170)),
})

-- rang de chaque état dans la liste
local RANK = { claim = 1, progress = 2, cooldown = 3, done = 4 }
-- textes « de passage » (Claiming..., Loading...) : l'état d'avant est gardé
local TRANSIENT = { ["Loading..."] = true, ["Claiming..."] = true, ["Delivering..."] = true, ["..."] = true }

local function findPath(from, path)
	local o = from
	for _, n in ipairs(path) do o = o and o:FindFirstChild(n) end
	return o
end

-- état d'une quête d'après le texte de son bouton (tous les modules du QuestSystem)
local function stateFromText(t)
	if TRANSIENT[t] then return nil end
	if t == "Claim!" then return "claim" end
	if t == "Claimed" or t:sub(-#"✓") == "✓" then return "done" end
	if t == "Cooldown" or t:match("^%d+:%d%d:%d%d$") then return "cooldown" end
	return "progress"
end

local function ease(a) return a < 0.5 and 4 * a * a * a or 1 - (-2 * a + 2) ^ 3 / 2 end   -- cubic in-out

--════════════════════════════════════════════════════════════
local function start(questGui)
	local menu, scroll
	for _ = 1, 60 do
		menu, scroll = findPath(questGui, MENU_PATH), findPath(questGui, SCROLL_PATH)
		if menu and scroll and scroll:GetAttribute("QS_Board") then break end
		task.wait(0.5)
	end
	if not (menu and scroll) then return end
	local list = scroll:FindFirstChild("QS_List")
	if not list then return end

	-- zone de glissement : par-dessus la liste, mêmes limites (ce qui sort est coupé)
	local float = Instance.new("Frame")
	float.Name = "QP_Float"
	float.BackgroundTransparency = 1
	float.ClipsDescendants = true
	float.AnchorPoint = scroll.AnchorPoint
	float.Position, float.Size = scroll.Position, scroll.Size
	float.ZIndex = scroll.ZIndex
	float.Parent = scroll.Parent
	scroll:GetPropertyChangedSignal("Position"):Connect(function() float.Position = scroll.Position end)
	scroll:GetPropertyChangedSignal("Size"):Connect(function() float.Size = scroll.Size end)

	local rows = {}          -- [row] = R
	local busyMove = 0       -- glissements en cours

	local function isOpen() return menu.Visible end

	local function sortNow()
		for row, R in pairs(rows) do
			if not R.moving then
				row.LayoutOrder = (RANK[R.state] or 2) * 1000 + R.base
			end
		end
	end

	----------------------------------------------------------------
	-- 🌑 voile « Completed »
	local function makeFilm(row)
		local film = Instance.new("Frame")
		film.Name = "QP_DoneFilm"
		film.BackgroundColor3 = Color3.new(0, 0, 0)
		film.BackgroundTransparency = 1
		film.BorderSizePixel = 0
		film.Size = UDim2.fromScale(1, 1)
		film.ZIndex = 50
		film.Active = false
		film.Visible = false
		local rc = row:FindFirstChildOfClass("UICorner")
		local c = Instance.new("UICorner")
		c.CornerRadius = rc and rc.CornerRadius or UDim.new(0, 12)
		c.Parent = film

		local holder = Instance.new("Frame")
		holder.Name = "Content"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromScale(1, 0.5)
		holder.ZIndex = 51
		holder.Parent = film
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.VerticalAlignment = Enum.VerticalAlignment.Center
		lay.Padding = UDim.new(0.015, 0)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = holder

		local check = Instance.new("ImageLabel")
		check.Name = "Check"
		check.BackgroundTransparency = 1
		check.Image = CHECK_IMAGE
		check.ScaleType = Enum.ScaleType.Fit
		check.Size = UDim2.fromScale(1, 1)
		check.ImageTransparency = 1
		check.ZIndex = 52
		check.LayoutOrder = 1
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = 1
		a.DominantAxis = Enum.DominantAxis.Height
		a.Parent = check
		check.Parent = holder

		local txt = Instance.new("TextLabel")
		txt.Name = "Text"
		txt.BackgroundTransparency = 1
		txt.Text = DONE_TEXT
		txt.Font = Enum.Font.FredokaOne
		txt.TextScaled = true
		txt.TextColor3 = Color3.new(1, 1, 1)
		txt.TextTransparency = 1
		txt.Size = UDim2.fromScale(0.3, 1)
		txt.ZIndex = 52
		txt.LayoutOrder = 2
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Transparency = 1
		s.Parent = txt
		txt.Parent = holder

		film.Parent = row
		return { film = film, check = check, txt = txt, stroke = s }
	end

	local function showFilm(R, on, animated)
		local F = R.film
		if not F then
			if not on then return end
			F = makeFilm(R.row)
			R.film = F
		end
		local goalBg = on and FILM_TRANSPARENCY or 1
		local goal = on and 0 or 1
		if on then F.film.Visible = true end
		if animated then
			local info = TweenInfo.new(FILM_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(F.film, info, { BackgroundTransparency = goalBg }):Play()
			TweenService:Create(F.check, info, { ImageTransparency = goal }):Play()
			TweenService:Create(F.txt, info, { TextTransparency = goal }):Play()
			local t = TweenService:Create(F.stroke, info, { Transparency = goal })
			t:Play()
			if not on then t.Completed:Connect(function() if R.state ~= "done" then F.film.Visible = false end end) end
		else
			F.film.BackgroundTransparency = goalBg
			F.check.ImageTransparency, F.txt.TextTransparency, F.stroke.Transparency = goal, goal, goal
			F.film.Visible = on
		end
	end

	----------------------------------------------------------------
	-- 🎨 look « Claimed » identique pour toutes les quêtes finies
	local function applyDoneLook(R)
		if R.state ~= "done" then
			if R.grad then R.grad.Enabled = false end
			return
		end
		local b = R.button
		if b.Text ~= "Claimed" then b.Text = "Claimed" end
		if b.TextColor3 ~= TEXT_GREY then b.TextColor3 = TEXT_GREY end
		if b.BackgroundColor3 ~= GREY then b.BackgroundColor3 = GREY end
		local other = false
		for _, g in ipairs(b:GetChildren()) do
			if g:IsA("UIGradient") and g.Name ~= "QP_DoneGrad" and g.Enabled then other = true end
		end
		if not R.grad then
			R.grad = Instance.new("UIGradient")
			R.grad.Name = "QP_DoneGrad"
			R.grad.Color = DONE_GRADIENT
			R.grad.Rotation = 90
			R.grad.Parent = b
		end
		R.grad.Enabled = not other
		local bar = R.bar
		if bar then
			local fill = bar:FindFirstChild("FillBar")
			if fill then
				if fill.BackgroundColor3 ~= GREY then fill.BackgroundColor3 = GREY end
				local fg = fill:FindFirstChildOfClass("UIGradient")
				if fg and fg.Enabled then fg.Enabled = false end
			end
			-- pas de texte sur la barre : le voile dit déjà « Completed »
			local lbl = bar:FindFirstChild("ProgressLabel")
			if lbl and lbl.Text ~= "" then lbl.Text = "" end
		end
	end

	----------------------------------------------------------------
	-- ↕️ glissement d'UNE quête vers sa nouvelle place ; les quêtes entre l'ancienne et la
	--    nouvelle place se décalent d'un cran en douceur. Des cases vides gardent la liste
	--    exactement à la même taille pendant l'animation : rien ne saute, ni au début ni à la fin.
	local function moveRow(R, newOrder)
		local row = R.row
		if R.moving or row.LayoutOrder == newOrder or row.Parent ~= scroll then
			if not R.moving then row.LayoutOrder = newOrder end
			return
		end
		-- quêtes affichées, dans l'ordre actuel puis dans le nouvel ordre
		local oldList = {}
		for r, X in pairs(rows) do
			if r.Parent == scroll and r.Visible and not X.moving then table.insert(oldList, r) end
		end
		table.sort(oldList, function(x, y) return x.LayoutOrder < y.LayoutOrder end)
		local newList = table.clone(oldList)
		local function ord(r) return (r == row) and newOrder or r.LayoutOrder end
		table.sort(newList, function(x, y) return ord(x) < ord(y) end)
		local oi, ni = table.find(oldList, row), table.find(newList, row)
		if not oi or not ni or oi == ni then row.LayoutOrder = newOrder return end
		local lo, hi = math.min(oi, ni), math.max(oi, ni)
		local h0 = row.AbsoluteSize.Y
		for k = lo, hi do
			if math.abs(oldList[k].AbsoluteSize.Y - h0) > 2 then row.LayoutOrder = newOrder return end   -- tailles différentes : sans animation
		end

		busyMove += 1
		local scrollWas = scroll.ScrollingEnabled
		scroll.ScrollingEnabled = false
		local fs = float.AbsoluteSize
		local slot, saved, moving = {}, {}, {}
		for k = lo, hi do
			local r = oldList[k]
			-- case vide = même taille, même place
			local sp = Instance.new("Frame")
			sp.Name = "QP_Spacer"
			sp.BackgroundTransparency = 1
			sp.Size = r.Size
			sp.LayoutOrder = r.LayoutOrder
			local asp = r:FindFirstChildOfClass("UIAspectRatioConstraint")
			if asp then asp:Clone().Parent = sp end
			sp.Parent = scroll
			slot[k] = sp
			local abs, size = r.AbsolutePosition, r.AbsoluteSize
			saved[r] = { anchor = r.AnchorPoint, size = r.Size, pos = r.Position, aspect = asp }
			rows[r].moving = true
			r.Parent = float
			if asp then asp.Parent = nil end
			r.AnchorPoint = Vector2.zero
			r.Size = UDim2.fromScale(size.X / fs.X, size.Y / fs.Y)
			local fa = float.AbsolutePosition
			r.Position = UDim2.fromScale((abs.X - fa.X) / fs.X, (abs.Y - fa.Y) / fs.Y)
			moving[r] = { from = k, to = table.find(newList, r) }
		end
		row.LayoutOrder = newOrder

		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local a = math.clamp((os.clock() - t0) / MOVE_TIME, 0, 1)
			local e = ease(a)
			local fa, fs2 = float.AbsolutePosition, float.AbsoluteSize
			for r, m in pairs(moving) do
				local p = slot[m.from].AbsolutePosition:Lerp(slot[m.to].AbsolutePosition, e)
				r.Position = UDim2.fromScale((p.X - fa.X) / fs2.X, (p.Y - fa.Y) / fs2.Y)
			end
			if a < 1 then return end
			conn:Disconnect()
			for r, sv in pairs(saved) do
				r.Parent = scroll
				r.AnchorPoint, r.Size, r.Position = sv.anchor, sv.size, sv.pos
				if sv.aspect then sv.aspect.Parent = r end
				rows[r].moving = false
			end
			for _, sp in pairs(slot) do sp:Destroy() end
			scroll.ScrollingEnabled = scrollWas
			busyMove -= 1
		end)
	end

	-- quête récupérée menu ouvert : « Claimed » → voile → glissement
	local function playClaim(R)
		R.anim = (R.anim or 0) + 1
		local my = R.anim
		task.delay(WAIT_BEFORE_FILM, function()
			if R.anim ~= my or not R.row.Parent then return end
			if R.state == "done" then showFilm(R, true, true) end
			task.wait(FILM_FADE + WAIT_BEFORE_MOVE)
			if R.anim ~= my or not R.row.Parent then return end
			local order = (RANK[R.state] or 2) * 1000 + R.base
			if isOpen() then moveRow(R, order) else R.row.LayoutOrder = order end
		end)
	end

	----------------------------------------------------------------
	local function refresh(R)
		local s = stateFromText(R.button.Text)
		if s == nil or s == R.state then
			if R.state == "done" then applyDoneLook(R) end
			return
		end
		local prev = R.state
		R.state = s
		applyDoneLook(R)
		if prev == "claim" and (s == "done" or s == "cooldown") and isOpen() then
			playClaim(R)                    -- le joueur vient de la récupérer
		else
			showFilm(R, s == "done", false)
			if not isOpen() then sortNow() end
		end
	end

	local function questButton(row)
		for _, d in ipairs(row:GetDescendants()) do
			if d:IsA("TextButton") and d:FindFirstChild("CompleteQuestFrame") then return d end
		end
		local cb = row:FindFirstChild("ClaimButton", true)
		if cb and cb:IsA("TextButton") then return cb end
		for _, d in ipairs(row:GetDescendants()) do
			if d:IsA("TextButton") then return d end
		end
		return nil
	end

	local function addRow(row)
		if rows[row] or not row:IsA("GuiObject") or row:IsA("TextLabel") or row.Name:match("^QP_") then return end
		local button = questButton(row)
		if not button then return end
		local R = { row = row, button = button, base = row.LayoutOrder % 1000, state = nil }
		R.bar = button:FindFirstChild("CompleteQuestFrame") or row:FindFirstChild("CompleteQuestFrame")
		rows[row] = R
		local function upd() refresh(R) end
		for _, p in ipairs({ "Text", "TextColor3", "BackgroundColor3" }) do
			button:GetPropertyChangedSignal(p):Connect(upd)
		end
		if R.bar then
			local function hookBar(d)
				if d.Name == "ProgressLabel" and d:IsA("TextLabel") then
					d:GetPropertyChangedSignal("Text"):Connect(upd)
				elseif d.Name == "FillBar" and d:IsA("GuiObject") then
					d:GetPropertyChangedSignal("BackgroundColor3"):Connect(upd)
				end
			end
			for _, d in ipairs(R.bar:GetChildren()) do hookBar(d) end
			R.bar.ChildAdded:Connect(hookBar)
		end
		refresh(R)
	end

	for _, c in ipairs(scroll:GetChildren()) do addRow(c) end
	scroll.ChildAdded:Connect(function(c) task.delay(0.5, addRow, c) end)

	-- 📂 tri à l'ouverture du menu (rien ne bouge pendant la lecture)
	menu:GetPropertyChangedSignal("Visible"):Connect(function()
		if menu.Visible and busyMove == 0 then sortNow() end
	end)
	sortNow()
end

local function onGui(g)
	if g.Name == QUEST_GUI and g:IsA("ScreenGui") then task.spawn(start, g) end
end
for _, g in ipairs(playerGui:GetChildren()) do onGui(g) end
playerGui.ChildAdded:Connect(onGui)

print("✅ QuestListPolish chargé (tri + quêtes finies)")
