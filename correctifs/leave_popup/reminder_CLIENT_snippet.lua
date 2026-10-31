-- ============================================================
-- 🔴 RAPPEL (quand le Fusion Coil a déjà été proposé) : texte rouge en haut de l'écran
-- ============================================================
-- 🎁 la vraie prochaine récompense Daily du joueur (le script Daily donne le jour à PlayerGui)
local DAILY_REWARDS = {
	[1] = "a Speed Coil", [2] = "5,000 points", [3] = "a Gravity Coil", [4] = "a Fusion Coil",
	[5] = "5,000 points", [6] = "a Speed Coil", [7] = "a Jetpack",
}
local function reminderText()
	local day = playerGui:GetAttribute("DailyDay")
	local reward = type(day) == "number" and DAILY_REWARDS[day]
	if reward and playerGui:GetAttribute("DailyReadyNow") == true then
		-- la récompense du jour n'est pas encore prise : on le lui rappelle tout de suite
		return ("Don't leave yet! Your Day %d reward is ready: %s 🎁"):format(day, reward)
	end
	local options = { "Don't lose your streak! See you tomorrow 🔥" }
	if reward then
		table.insert(options, ("Come back tomorrow for Day %d: %s! 🎁"):format(day, reward))
		table.insert(options, ("Don't lose your streak! Day %d brings %s tomorrow 🔥"):format(day, reward))
	end
	return options[math.random(1, #options)]
end
local REMINDER_DIM  = 0.55     -- assombrissement du fond (0 = noir, 1 = rien)
local REMINDER_BLUR = 10       -- flou du fond (0 = aucun)
local reminderGui, reminderBlur
local function hideReminder()
	if reminderGui then reminderGui:Destroy() reminderGui = nil end
	if reminderBlur then reminderBlur:Destroy() reminderBlur = nil end
end
local function showReminder()
	hideReminder()
	if not GuiService.MenuIsOpen then return end   -- menu Roblox déjà refermé : rien à afficher
	local g = Instance.new("ScreenGui")
	g.Name = "LeaveReminderGui"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 999
	g.Parent = playerGui
	reminderGui = g
	-- fond assombri
	local dark = Instance.new("Frame")
	dark.BackgroundColor3 = Color3.new(0, 0, 0)
	dark.BackgroundTransparency = 1
	dark.BorderSizePixel = 0
	dark.Size = UDim2.fromScale(1, 1)
	dark.Parent = g
	-- fond flou
	if REMINDER_BLUR > 0 then
		local b = Instance.new("BlurEffect")
		b.Name = "LeaveReminderBlur"
		b.Size = 0
		b.Parent = Lighting
		reminderBlur = b
		TweenService:Create(b, TweenInfo.new(0.3), { Size = REMINDER_BLUR }):Play()
	end
	TweenService:Create(dark, TweenInfo.new(0.3), { BackgroundTransparency = REMINDER_DIM }):Play()
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.fromScale(0.5, 0.07)
	t.Size = UDim2.fromScale(IS_MOBILE and 0.9 or 0.7, IS_MOBILE and 0.09 or 0.07)
	t.Font = Enum.Font.FredokaOne
	t.Text = reminderText()
	t.TextColor3 = Color3.fromRGB(255, 60, 60)
	t.TextScaled = true
	t.TextTransparency = 1
	t.ZIndex = 2
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 46
	c.Parent = t
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.fromRGB(40, 0, 0)
	st.Transparency = 1
	st.Parent = t
	local sc = Instance.new("UIScale")
	sc.Scale = 0.6
	sc.Parent = t
	t.Parent = g
	local inInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(sc, inInfo, { Scale = 1 }):Play()
	TweenService:Create(t, inInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(st, inInfo, { Transparency = 0 }):Play()
	-- puis reste stable et pivote lentement de gauche à droite (tant que le menu Roblox est ouvert)
	t.Rotation = -2
	TweenService:Create(t, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Rotation = 2 }):Play()
end

-- le joueur quitte le menu Roblox → le rappel disparaît immédiatement
GuiService.MenuClosed:Connect(hideReminder)

showLeavePopup.OnClientEvent:Connect(function(kind)
	if kind == "reminder" then showReminder() else openOverlay() end
end)
