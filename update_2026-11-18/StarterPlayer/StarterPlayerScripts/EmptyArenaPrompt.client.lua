--════════════════════════════════════════════════════════════════════════════
-- ⚔️ EmptyArenaPrompt — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (NOUVEAU)
--
--  Tu entres en PvP mais personne d'autre n'y est sur ce serveur → après un court
--  moment, une fenêtre te le dit et te propose de rejoindre un serveur où il y a des
--  joueurs en PvP. « JOIN » ouvre le panneau des serveurs (le même que le
--  panneau « 1v1 Servers » du lobby).
--
--  Quand ? Pas tout de suite à l'entrée : on attend un peu (DELAY) car
--   • d'autres joueurs entrent souvent juste après toi (même vague, même vote de map) ;
--   • l'arrivée en arène a déjà son bouclier, sa caméra et son chargement de map ;
--   • on revérifie juste avant d'afficher : si quelqu'un est arrivé, rien ne s'affiche.
--  Et seulement si un AUTRE serveur a vraiment des joueurs en PvP (sinon, inutile).
--
--  Jamais d'abus : une fois par entrée en arène, au plus MaxPerSession fois, pas pendant
--  les premières secondes après un changement de serveur, et la fenêtre se ferme toute
--  seule si quelqu'un entre dans l'arène, si tu en sors ou si tu meurs.
--
--  ↩️ Pour couper : Enabled = false.
--════════════════════════════════════════════════════════════════════════════
local CONFIG = {
	Enabled          = true,
	DELAY            = 5,     -- s après ton arrivée en arène
	MinOtherArena    = 1,     -- un autre serveur doit avoir au moins ça de joueurs en PvP
	MaxPerSession    = 3,
	Cooldown         = 150,   -- s minimum entre deux fenêtres
	AfterTeleport    = 90,    -- s sans fenêtre après être arrivé par le panneau des serveurs
	AutoClose        = 25,    -- s : la fenêtre se ferme toute seule
	-- 🧪 Studio : il n'y a pas de vrais serveurs, donc la fenêtre ne pourrait jamais s'afficher.
	--    true = en STUDIO SEULEMENT, un faux serveur à 4 joueurs est utilisé pour que tu la voies
	--    (entre en PvP seul, attends DELAY secondes). Dans le vrai jeu, ce réglage ne fait RIEN.
	StudioTest       = true,
}
if not CONFIG.Enabled then return end

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local joinedAt  = os.clock()
local cameByTeleport = false
pcall(function()
	local jd = player:GetJoinData()
	cameByTeleport = jd and type(jd.TeleportData) == "table" and jd.TeleportData.joinArena == true
end)

-- 🎨 même look que ton panneau des serveurs (panneau blanc, bandeau bleu, titre blanc
--    contouré) + boutons 3D enfonçables de tes Paramètres
local FONT      = Enum.Font.FredokaOne
local WHITE     = Color3.new(1, 1, 1)
local PANEL_HI  = Color3.fromRGB(255, 255, 255)
local PANEL_LO  = Color3.fromRGB(226, 236, 250)
local HEAD_HI   = Color3.fromRGB(117, 179, 249)   -- = bandeau « Servers »
local HEAD_LO   = Color3.fromRGB(70, 140, 235)
local INK       = Color3.fromRGB(28, 40, 70)      -- texte foncé sur le panneau blanc
local OUTLINE   = Color3.new(0, 0, 0)
local COL = {
	green = { Color3.fromRGB(40, 185, 80), Color3.fromRGB(12, 115, 42), Color3.fromRGB(8, 65, 25) },
	grey  = { Color3.fromRGB(88, 94, 112), Color3.fromRGB(50, 54, 68), Color3.fromRGB(28, 30, 40) },
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function outlined(lbl, t)
	new("UIStroke", { Color = OUTLINE, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, lbl)
end
-- bouton 3D des Paramètres (dégradé + socle)
local function button3D(parent, text, col, pos)
	-- 🔒 forme verrouillée : ratio fixe (jamais écrasé) et coins proportionnels (jamais rond)
	local slot = new("Frame", { Size = UDim2.new(0.5, -10, 1, 0), Position = pos, BackgroundTransparency = 1 }, parent)
	new("UIAspectRatioConstraint", { AspectRatio = 3.4 }, slot)
	local CORNER = UDim.new(0.22, 0)
	local edge = new("Frame", { Size = UDim2.new(1, 0, 1, -4), Position = UDim2.fromOffset(0, 4),
		BackgroundColor3 = col[3], BorderSizePixel = 0 }, slot)
	new("UICorner", { CornerRadius = CORNER }, edge)
	local btn = new("TextButton", { Size = UDim2.new(1, 0, 1, -4), BackgroundColor3 = WHITE, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "", ZIndex = 2 }, slot)
	new("UICorner", { CornerRadius = CORNER }, btn)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(col[1], col[2]) }, btn)
	local l = new("TextLabel", { Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), BackgroundTransparency = 1,
		Text = text, Font = FONT, TextScaled = true, TextColor3 = WHITE, ZIndex = 3 }, btn)
	new("UITextSizeConstraint", { MaxTextSize = 24 }, l)
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, l)
	outlined(l, 1.6)
	new("UIStroke", { Color = OUTLINE, Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
	btn.MouseButton1Down:Connect(function() btn.Position = UDim2.fromOffset(0, 3) end)
	btn.MouseButton1Up:Connect(function() btn.Position = UDim2.fromOffset(0, 0) end)
	btn.MouseLeave:Connect(function() btn.Position = UDim2.fromOffset(0, 0) end)
	return btn
end

local function inArena(p) return p:GetAttribute("InArena") == true end
local function othersInArena()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and inArena(p) then n += 1 end
	end
	return n
end
local function alive()
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

-- meilleur autre serveur (le plus de joueurs en PvP), via le même remote que le panneau
local function bestOtherServer()
	if CONFIG.StudioTest and game:GetService("RunService"):IsStudio() then return { arena = 4 } end
	local fn = ReplicatedStorage:FindFirstChild("GetArenaServers")
	if not fn then return nil end
	local ok, list = pcall(function() return fn:InvokeServer() end)
	if not ok or type(list) ~= "table" then return nil end
	local best
	for _, s in ipairs(list) do
		local a = type(s) == "table" and tonumber(s.arena) or 0
		if a >= CONFIG.MinOtherArena and (not best or a > best.arena) then best = { arena = a } end
	end
	return best
end

local function openServerBrowser()
	local ctrl = playerGui:FindFirstChild("ServerBrowserController")
	local ev = ctrl and ctrl:FindFirstChild("Open")
	if ev and ev:IsA("BindableEvent") then ev:Fire() return true end
	warn("[EmptyArenaPrompt] panneau des serveurs introuvable (1v1 cross server local à jour ?)")
	return false
end

--════════════════════════════════════════════════════════════
-- 🪟 LA FENÊTRE
--════════════════════════════════════════════════════════════
local gui, card, closeToken = nil, nil, 0
local shownCount, lastShownAt = 0, -math.huge
local PAD_ACTION = "EmptyArenaPromptPad"

local function close()
	closeToken += 1
	ContextActionService:UnbindAction(PAD_ACTION)
	if not gui then return end
	local g, c = gui, card
	gui, card = nil, nil
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(g) then GuiService.SelectedObject = nil end
	if c then
		local sc = c:FindFirstChildOfClass("UIScale")
		if sc then TweenService:Create(sc, TweenInfo.new(0.15), { Scale = sc.Scale * 0.9 }):Play() end
	end
	task.delay(0.15, function() g:Destroy() end)
end

local function show(best)
	if gui then return end
	shownCount += 1
	lastShownAt = os.clock()
	closeToken += 1
	local my = closeToken

	gui = new("ScreenGui", { Name = "EmptyArenaPrompt", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 60, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	-- fond assombri ; Modal = la souris est libérée même avec une arme en main
	new("TextButton", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55, Text = "", AutoButtonColor = false, Modal = true, Selectable = false }, gui)

	card = new("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 210), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2 }, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 18) }, card)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(PANEL_HI, PANEL_LO) }, card)
	new("UIStroke", { Color = OUTLINE, Thickness = 2, Transparency = 0.15 }, card)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local scale = math.clamp(math.min(vp.X / 480, vp.Y / 290), 0.55, 1.25)
	local uiScale = new("UIScale", { Scale = scale * 0.85 }, card)

	-- bandeau bleu + titre blanc contouré (comme « Servers »)
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, card)
	new("UICorner", { CornerRadius = UDim.new(0, 18) }, head)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(HEAD_HI, HEAD_LO) }, head)
	local flat = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 18),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, head)   -- coins bas carrés
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(HEAD_LO:Lerp(HEAD_HI, 0.3), HEAD_LO) }, flat)
	local title = new("TextLabel", { Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6), BackgroundTransparency = 1,
		Text = "NO PLAYERS HERE", Font = FONT, TextScaled = true, TextColor3 = WHITE, ZIndex = 4 }, head)
	new("UITextSizeConstraint", { MaxTextSize = 34 }, title)
	outlined(title, 2)

	-- l'essentiel : personne ici → rejoins un serveur pour jouer
	local line = new("TextLabel", { Position = UDim2.fromOffset(20, 68), Size = UDim2.new(1, -40, 0, 50), BackgroundTransparency = 1,
		Text = string.format("Want to play PvP?\nJoin a server with %d player%s! 🔥", best.arena, best.arena > 1 and "s" or ""),
		Font = FONT, TextScaled = true, TextColor3 = INK, ZIndex = 3 }, card)
	new("UITextSizeConstraint", { MaxTextSize = 22 }, line)

	local row = new("Frame", { Position = UDim2.new(0, 20, 1, -70), Size = UDim2.new(1, -40, 0, 52), BackgroundTransparency = 1, ZIndex = 3 }, card)
	local goBtn = button3D(row, "JOIN", COL.green, UDim2.new(0, 0, 0, 0))
	local stayBtn = button3D(row, "STAY", COL.grey, UDim2.new(0.5, 10, 0, 0))

	goBtn.Activated:Connect(function() close() ; openServerBrowser() end)
	stayBtn.Activated:Connect(close)

	-- apparition
	TweenService:Create(uiScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = scale }):Play()

	-- 🎮 manette : A = choisir (JOIN sélectionné), B = rester
	if UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad" then GuiService.SelectedObject = goBtn end
	ContextActionService:BindActionAtPriority(PAD_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then close() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)

	-- fermeture automatique : quelqu'un entre en PvP, tu sors, tu meurs, ou le temps est écoulé
	task.spawn(function()
		local t0 = os.clock()
		while my == closeToken and gui do
			local left = CONFIG.AutoClose - (os.clock() - t0)
			if left <= 0 or othersInArena() > 0 or not inArena(player) or not alive() then close() break end
			task.wait(0.5)
		end
	end)
end

--════════════════════════════════════════════════════════════
-- ⏱️ QUAND ?
--════════════════════════════════════════════════════════════
local entryToken = 0
local function onArenaChanged()
	entryToken += 1
	local my = entryToken
	if not inArena(player) then close() return end
	task.delay(CONFIG.DELAY, function()
		if my ~= entryToken or not inArena(player) or not alive() then return end
		if shownCount >= CONFIG.MaxPerSession then return end
		if os.clock() - lastShownAt < CONFIG.Cooldown then return end
		if cameByTeleport and os.clock() - joinedAt < CONFIG.AfterTeleport then return end
		if othersInArena() > 0 then return end
		local best = bestOtherServer()
		-- on revérifie APRÈS la question au serveur (quelqu'un a pu entrer entre-temps)
		if not best or my ~= entryToken or not inArena(player) or othersInArena() > 0 then return end
		show(best)
	end)
end
player:GetAttributeChangedSignal("InArena"):Connect(onArenaChanged)
if inArena(player) then onArenaChanged() end
