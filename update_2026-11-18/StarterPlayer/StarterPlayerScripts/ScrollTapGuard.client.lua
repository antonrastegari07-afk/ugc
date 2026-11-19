--════════════════════════════════════════════════════════════════════════════
-- 📱 ScrollTapGuard — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (NOUVEAU)
--
--  Sur mobile, quand on fait glisser le doigt pour faire DÉFILER une liste (quêtes,
--  shop UGC, boutiques…), le bouton sur lequel le doigt s'était posé ne doit PAS se
--  déclencher au moment où on relâche (avant : « quest completed » ou une autre
--  notif apparaissait en scrollant).
--
--  Comment : dès que la liste a VRAIMENT défilé sous le doigt (plus de 6 px), les
--  boutons de cette liste deviennent non cliquables jusqu'à ce que le doigt se lève,
--  puis redeviennent normaux 0,1 s après. Un simple tap (sans défilement) reste
--  un clic normal. Les curseurs/sliders ne sont pas touchés : ils ne font pas
--  défiler la liste.
--
--  Valable pour TOUTES les listes du jeu, sans modifier leurs scripts.
--  PC et manette : rien ne change (le script ne fait rien sans écran tactile).
--  ↩️ Pour revenir à avant : désactive ou supprime ce script.
--════════════════════════════════════════════════════════════════════════════
local UserInputService = game:GetService("UserInputService")
local Players          = game:GetService("Players")

if not UserInputService.TouchEnabled then return end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DRAG_PX       = 6     -- défilement à partir duquel ce n'est plus un tap
local RESTORE_DELAY = 0.1   -- s après le relâché : le clic « fantôme » est déjà ignoré

local touches = {}          -- [InputObject] = { sf, start, locked, saved }

-- liste qui défile sous ce point de l'écran (la plus proche du doigt)
local function scrollerAt(pos)
	local ok, objs = pcall(function() return playerGui:GetGuiObjectsAtPosition(pos.X, pos.Y) end)
	if not ok then return nil end
	for _, o in ipairs(objs) do
		local sf = o:IsA("ScrollingFrame") and o or o:FindFirstAncestorWhichIsA("ScrollingFrame")
		if sf and sf.ScrollingEnabled and sf.Visible then return sf end
	end
	return nil
end

local function lock(t)
	t.locked = true
	for _, d in ipairs(t.sf:GetDescendants()) do
		if d:IsA("GuiButton") then
			local ok, cur = pcall(function() return d.Interactable end)
			if ok and cur then
				d.Interactable = false
				t.saved[d] = true
			end
		end
	end
end

local function unlock(t)
	for d in pairs(t.saved) do
		if d.Parent then pcall(function() d.Interactable = true end) end
	end
	table.clear(t.saved)
end

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	local sf = scrollerAt(input.Position)
	if sf then touches[input] = { sf = sf, start = sf.CanvasPosition, locked = false, saved = {} } end
end)

UserInputService.InputChanged:Connect(function(input)
	local t = touches[input]
	if not t or t.locked then return end
	if not t.sf.Parent then touches[input] = nil return end
	if (t.sf.CanvasPosition - t.start).Magnitude > DRAG_PX then lock(t) end
end)

UserInputService.InputEnded:Connect(function(input)
	local t = touches[input]
	if not t then return end
	touches[input] = nil
	if t.locked then task.delay(RESTORE_DELAY, unlock, t) end
end)
