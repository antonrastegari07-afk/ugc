--════════════════════════════════════════════════════════════════════════════
-- 🔔 RewardToast — ModuleScript dans ReplicatedStorage   (NOUVEAU, nom exact : RewardToast)
--
--  La petite notification « bande noire aux bords en fondu » qui descend du haut.
--  Utilisée par : Playtime Rewards, Daily Rewards, liste des Quêtes.
--  Un seul endroit pour la changer.
--
--  📱 Mobile (petit écran) : plus petite et collée en haut de l'écran.
--  🖥️ PC : comme avant.
--  Le mot « Toast » dans le nom de l'interface la garde visible au-dessus du menu ouvert (UIFocus).
--════════════════════════════════════════════════════════════════════════════
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local T = {}

-- ⚙️ RÉGLAGES
local DEFAULT_TIME   = 2.2
local SMALL_SCREEN   = 600      -- px : en dessous (côté le plus court de l'écran) = format mobile
local BIG   = { h1 = 44, h2 = 62, title = 26, sub = 19, width = 0.6,  minW = 260, maxW = 620, top = 14, inset = false }
local SMALL = { h1 = 28, h2 = 40, title = 17, sub = 13, width = 0.42, minW = 180, maxW = 420, top = 4,  inset = true }

local function sizes()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return (math.min(vp.X, vp.Y) < SMALL_SCREEN) and SMALL or BIG
end

local function getGui(S)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("RewardToastGui")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "RewardToastGui"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = playerGui
	end
	gui.IgnoreGuiInset = S.inset
	return gui
end

local function hideOld(gui)
	for _, old in ipairs(gui:GetChildren()) do
		if old:IsA("Frame") and old.Name == "Toast" then
			old.Name = "ToastOut"
			TweenService:Create(old, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -10) }):Play()
			for _, d in ipairs(old:GetDescendants()) do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, TweenInfo.new(0.2), { Transparency = 1 }):Play()
				end
			end
			task.delay(0.22, function() old:Destroy() end)
		end
	end
end

-- T.Show("Titre", "sous-titre jaune (optionnel)", durée)
function T.Show(title, sub, duration)
	local S = sizes()
	local gui = getGui(S)
	hideOld(gui)          -- une seule à la fois : la précédente remonte et disparaît
	local hasSub = sub ~= nil and sub ~= ""
	local f = Instance.new("Frame")
	f.Name = "Toast"
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 0, -10)
	f.Size = UDim2.new(S.width, 0, 0, hasSub and S.h2 or S.h1)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Active = false
	local sc = Instance.new("UISizeConstraint")
	sc.MinSize = Vector2.new(S.minW, 0)
	sc.MaxSize = Vector2.new(S.maxW, 200)
	sc.Parent = f
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.3),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	local function line(text, y, h, size, color)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, y)
		t.Size = UDim2.fromScale(0.72, h)
		t.Font = Enum.Font.FredokaOne
		t.Text = text
		t.TextScaled = true
		t.TextColor3 = color
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = size
		c.Parent = t
		local st = Instance.new("UIStroke")
		st.Thickness = 1.5
		st.Parent = t
		t.Parent = f
	end
	if hasSub then
		line(title, 0.33, 0.48, S.title, Color3.fromRGB(255, 255, 255))
		line(sub, 0.75, 0.34, S.sub, Color3.fromRGB(255, 220, 90))
	else
		line(title, 0.5, 0.7, S.title, Color3.fromRGB(255, 255, 255))
	end
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, S.top) }):Play()
	task.delay(duration or DEFAULT_TIME, function()
		if f.Parent and f.Name == "Toast" then
			f.Name = "ToastOut"
			TweenService:Create(f, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -10) }):Play()
			task.delay(0.32, function() f:Destroy() end)
		end
	end)
end

return T
