-- ════════════════════════════════════════════════════════════════════════
-- 🎯 ArenaViewKeeper — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (NOUVEAU)
--
--  En arène PvP, ta VUE reste la même avec ou sans arme en main.
--   AVANT : en vue « lock » (3e personne verrouillée), ranger ton arme rendait la
--           caméra libre de Roblox → la vue se « délockait ».
--   MAINTENANT : sans arme, on garde le même mode que celui des armes :
--     • mode LOCK (3e personne)  → caméra verrouillée derrière l'épaule, souris
--       bloquée au centre, perso tourné vers la caméra (même distance / décalage) ;
--     • mode 1re PERSONNE         → reste en 1re personne.
--   🆕 Touche B (manette : croix ←) : change la vue MÊME SANS ARME, et le petit panneau
--      des contrôles reste affiché au même endroit que celui des armes :
--      Shift = Sprint · C = Slide · B = Views · H = Hide Controls.
--      (Sprint et Slide marchent déjà sans arme en main tant qu'une arme est dans le
--       sac à dos — c'est le cas en arène.)
--      « Hide Controls » est retenu partout : avec n'importe quelle arme et sans arme.
--   Quand tu ressors une arme, elle reprend la caméra exactement là où tu regardais.
--   Hors de l'arène : rien ne change.
--
--  ↩️ REVENIR À AVANT : mets ENABLED = false ci-dessous (ou supprime ce script).
--  Perf : ne tourne QUE pendant que tu es en arène, et ne fait rien quand une arme
--         tient déjà la caméra.
-- ════════════════════════════════════════════════════════════════════════
local ENABLED = true

-- Réglages de la vue sans arme (mêmes valeurs que la caméra des armes, WeaponController)
local LOCK_DISTANCE = 11                       -- distance de la caméra (zoom bloqué pendant le lock)
local LOCK_OFFSET   = Vector3.new(3.5, 1, 0)   -- décalage épaule droite + un peu au-dessus

if not ENABLED then return end

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Shared = require(ReplicatedStorage:WaitForChild("WeaponSystem"):WaitForChild("WeaponSharedState"))
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
-- 1re personne sans arme : vraie 1re personne verrouillée (sinon B ne changerait rien sans arme)
local FP_LOCKED = true
local SHOW_CONTROLS = true   -- panneau B / H sans arme (PC). false = pas de panneau

-- touche manette « changer de vue » (même réglage que les armes)
local PAD_TOGGLE = Enum.KeyCode.DPadLeft
pcall(function()
	local cs = require(ReplicatedStorage.WeaponSystem:WaitForChild("CombatSettings", 10))
	if cs and cs.Gamepad and cs.Gamepad.ToggleView then PAD_TOGGLE = cs.Gamepad.ToggleView end
end)

local showPanel     -- déclarée ici, définie plus bas (step() s'en sert)
local paintControls -- idem (buildPanel s'en sert)
local BIND = "ArenaViewKeeper"
local bound = false
local active = nil   -- nil | "lock" | "first"
local saved = {}     -- ce qu'on a changé, pour le remettre EXACTEMENT comme avant
-- décalage caméra « normal » du perso. ⚠️ Une arme mémorise le décalage au moment où
-- on la sort : si c'était le nôtre, elle le remettrait en la rangeant. On garde donc
-- le VRAI décalage d'origine ici, et on le remet dès qu'on retrouve le nôtre en trop.
local baseOffset = Vector3.zero

local function clearOurOffset()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.CameraOffset == LOCK_OFFSET then hum.CameraOffset = baseOffset end
end

local function inArena() return player:GetAttribute("InArena") == true end

local function restore(touchMouse)
	if not active then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if active == "lock" then
		if hum then
			hum.AutoRotate = true
			if hum.CameraOffset == LOCK_OFFSET then hum.CameraOffset = baseOffset end
		end
		if saved.minZoom then player.CameraMinZoomDistance = saved.minZoom end
		if saved.maxZoom then player.CameraMaxZoomDistance = saved.maxZoom end
		if touchMouse and not IS_TOUCH and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	elseif active == "first" then
		if saved.camMode then player.CameraMode = saved.camMode end
	end
	saved = {}
	active = nil
	player:SetAttribute("ArenaViewKept", nil)   -- lu par le bouton lock mobile (ShiftGUI)
end

local function step()
	local camera = workspace.CurrentCamera
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	-- une arme, une cinématique, l'écran de mort ou un spectate tient la caméra → on ne touche à rien
	local blocked = not (hum and root and hum.Health > 0)
		or Shared.AnyEquipped() or Shared.CameraOwner() ~= nil
		or camera.CameraType ~= Enum.CameraType.Custom
		or camera:GetAttribute("KeepScriptable")
		or workspace:GetAttribute("AnimEditorFreeze")
	-- panneau B / H : seulement sans arme et vivant (une arme affiche le sien)
	showPanel(hum ~= nil and hum.Health > 0 and not Shared.AnyEquipped())
	if blocked then
		-- arme reprise : elle gère la souris elle-même, on ne remet donc PAS la souris
		restore(false)
		return
	end
	local want = "lock"
	if Shared.IsFirstPersonAim() then want = FP_LOCKED and "first" or nil end
	if active and active ~= want then restore(true) end
	if not want then return end

	if want == "first" then
		-- (rien à faire si déjà actif)
		if not active then
			saved.camMode = player.CameraMode
			player.CameraMode = Enum.CameraMode.LockFirstPerson
			active = "first"
			player:SetAttribute("ArenaViewKept", true)
		end
	else
		if not active then
			if hum.CameraOffset ~= LOCK_OFFSET then baseOffset = hum.CameraOffset end
			saved.minZoom, saved.maxZoom = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
			player.CameraMaxZoomDistance = math.max(LOCK_DISTANCE, saved.minZoom)
			player.CameraMinZoomDistance = LOCK_DISTANCE
			active = "lock"
			player:SetAttribute("ArenaViewKept", true)
		end
		if hum.CameraOffset ~= LOCK_OFFSET then hum.CameraOffset = LOCK_OFFSET end
		if hum.AutoRotate then hum.AutoRotate = false end
		if not IS_TOUCH and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		-- le perso regarde où regarde la caméra (pas pendant la tyrolienne : elle pilote le perso)
		if not char:GetAttribute("Ziplining") then
			local lv = camera.CFrame.LookVector
			local yaw = math.atan2(-lv.X, -lv.Z)
			local rlv = root.CFrame.LookVector
			local d = (yaw - math.atan2(-rlv.X, -rlv.Z) + math.pi) % (2 * math.pi) - math.pi
			if math.abs(d) > math.rad(1) then
				root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
			end
		end
	end
	-- 🔁 l'arme suivante reprendra la caméra EXACTEMENT ici (aucun saut de vue)
	local lv = camera.CFrame.LookVector
	Shared.SetCamera(math.atan2(-lv.X, -lv.Z), math.asin(math.clamp(lv.Y, -1, 1)))
end

--════════════════════════════════════════════════════════════
-- ⌨️ PANNEAU DES CONTRÔLES SANS ARME (même look et même place que celui des armes)
--════════════════════════════════════════════════════════════
local panel, rows = nil, {}
local function controlsHidden() return player:GetAttribute("ControlsHidden") == true end
local function buildPanel()
	if panel or IS_TOUCH or not SHOW_CONTROLS then return end
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UnarmedControlsGui"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = pg
	-- même emplacement que l'AmmoHud des armes (coin bas-droite)
	local anchor = Instance.new("Frame")
	anchor.BackgroundTransparency = 1
	anchor.Size = UDim2.new(0, 200, 0, 50)
	anchor.Position = UDim2.new(1, -265, 1, -60)
	anchor.Parent = gui
	local keys = {
		{ key = "Shift", action = "Sprint" }, { key = "C", action = "Slide" },
		{ key = "B", action = "Views" }, { key = "H", action = "Hide Controls" },
	}
	local chip, rowH = 22, 26
	local list = Instance.new("Frame")
	list.Name = "KeyInstructions"
	list.BackgroundTransparency = 1
	list.AnchorPoint = Vector2.new(0, 1)
	list.Size = UDim2.new(1, 0, 0, #keys * rowH)
	list.Position = UDim2.new(0, 0, 1, 0)
	list.Parent = anchor
	for i, k in ipairs(keys) do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. k.key
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, chip)
		row.Position = UDim2.new(0, 0, 0, (i - 1) * rowH)
		row.Parent = list
		local cw = (#k.key > 1) and (chip + (#k.key - 1) * 9) or chip   -- « Shift » plus large (comme les armes)
		local group = Instance.new("Frame")
		group.BackgroundTransparency = 1
		group.Size = UDim2.new(0, cw + 6 + 80, 1, 0)
		group.AnchorPoint = Vector2.new(0.5, 0.5)
		group.Position = UDim2.new(0.5, 0, 0.5, 0)
		group.Parent = row
		local box = Instance.new("Frame")
		box.Size = UDim2.new(0, cw, 0, chip)
		box.AnchorPoint = Vector2.new(0, 0.5)
		box.Position = UDim2.new(0, 0, 0.5, 0)
		box.BackgroundColor3 = Color3.new(0, 0, 0)
		box.BackgroundTransparency = 0.4
		box.BorderSizePixel = 0
		box.Parent = group
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
		local bs = Instance.new("UIStroke") ; bs.Color = Color3.new(0, 0, 0) ; bs.Thickness = 1 ; bs.Parent = box
		local letter = Instance.new("TextLabel")
		letter.Size = UDim2.fromScale(1, 1)
		letter.BackgroundTransparency = 1
		letter.Text = k.key
		letter.TextColor3 = Color3.new(1, 1, 1)
		letter.TextStrokeTransparency = 0.4
		letter.Font = Enum.Font.GothamBold
		letter.TextSize = 14
		letter.Parent = box
		local desc = Instance.new("TextLabel")
		desc.Name = "Desc"
		desc.Size = UDim2.new(0, 80, 1, 0)
		desc.Position = UDim2.new(0, cw + 6, 0, 0)
		desc.BackgroundTransparency = 1
		desc.Text = k.action
		desc.TextColor3 = Color3.fromRGB(220, 220, 220)
		desc.TextStrokeTransparency = 0.3
		desc.Font = Enum.Font.GothamBold
		desc.TextSize = 13
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Parent = group
		rows[k.key] = { row = row, desc = desc }
	end
	panel = gui
	paintControls()
end

paintControls = function()
	if not panel then return end
	local hidden = controlsHidden()
	for key, r in pairs(rows) do
		if key ~= "H" then r.row.Visible = not hidden end
	end
	rows.H.desc.Text = hidden and "Reveal Controls" or "Hide Controls"
end
player:GetAttributeChangedSignal("ControlsHidden"):Connect(function() paintControls() end)

showPanel = function(on)
	if on then buildPanel() end
	if panel and panel.Enabled ~= on then panel.Enabled = on end
end

-- sans arme en arène : rien d'autre n'écoute B / H → c'est nous
local function unarmedInArena()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return inArena() and hum and hum.Health > 0 and not Shared.AnyEquipped()
end
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not unarmedInArena() then return end
	if (input.KeyCode == Enum.KeyCode.B and not IS_TOUCH) or input.KeyCode == PAD_TOGGLE then
		Shared.ToggleMode()   -- même fonction que les armes (le choix est aussi sauvegardé)
	elseif input.KeyCode == Enum.KeyCode.H and not IS_TOUCH then
		player:SetAttribute("ControlsHidden", not controlsHidden())   -- même état que les armes
	end
end)

local function refresh()
	if inArena() then
		if not bound then
			bound = true
			RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, step)
		end
	elseif bound then
		bound = false
		RunService:UnbindFromRenderStep(BIND)
		restore(true)
		showPanel(false)
		-- une arme rangée en sortant de l'arène peut remettre notre décalage un peu après
		task.delay(0.5, clearOurOffset)
		task.delay(1.5, clearOurOffset)
	end
end

player:GetAttributeChangedSignal("InArena"):Connect(refresh)
player.CharacterAdded:Connect(function()
	-- nouveau perso : il repart avec son décalage normal
	baseOffset = Vector3.zero
	if active then restore(false) end
end)
refresh()
