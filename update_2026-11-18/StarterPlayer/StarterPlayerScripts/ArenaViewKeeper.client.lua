-- ════════════════════════════════════════════════════════════════════════
-- 🎯 ArenaViewKeeper — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (v2)
--
--  En arène PvP, SANS arme en main, tout est EXACTEMENT comme avec une arme,
--  sauf que le curseur (viseur) disparaît :
--   • même caméra : on reprend LES MÊMES calculs que la caméra des armes
--     (WeaponController : distance 11, hauteur 2, épaule 3,5, rehausse 3,5,
--     tangage ±70°, recul devant les murs, roulis du slide) ;
--   • mêmes réglages de rotation : souris, glisser au doigt, stick manette,
--     et ton réglage « sensibilité arme en main » ;
--   • AUCUN relais visible : quand tu ranges l'arme, on reprend la caméra dès
--     l'image suivante, là où elle était (l'arme ne la rend à Roblox que si
--     personne ne la reprend) ; quand tu ressors une arme, elle repart d'ici ;
--   • 1re personne : sur mobile / console comme avec une arme (vue tête) ;
--     sur PC, l'arme utilise déjà la caméra normale de Roblox → rien à faire ;
--   • B (manette : croix ←) change la vue, et le panneau des contrôles reste
--     affiché au même endroit : Shift Sprint · C Slide · B Views · H Hide Controls.
--     « Hide Controls » est retenu partout (toutes les armes + sans arme).
--   Hors de l'arène : rien ne change et le script ne fait rien.
--
--  ↩️ REVENIR À AVANT : mets ENABLED = false ci-dessous (ou supprime ce script).
-- ════════════════════════════════════════════════════════════════════════
local ENABLED = true
local SHOW_CONTROLS = true   -- panneau Shift / C / B / H sans arme (PC). false = pas de panneau

if not ENABLED then return end

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")

local player = Players.LocalPlayer
local WS = ReplicatedStorage:WaitForChild("WeaponSystem")
local Shared = require(WS:WaitForChild("WeaponSharedState"))
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_MOBILE = Shared.IsMobile()
local IS_CONSOLE = GuiService:IsTenFootInterface()

-- ── mêmes valeurs que la caméra des armes (WeaponController) ──
local CAM_DISTANCE, CAM_HEIGHT = 11, 2
local CAM_SIDE, CAM_LIFT = 3.5, 3.5
local PITCH_MIN, PITCH_MAX = math.rad(-70), math.rad(70)
local MOUSE_SENS, DRAG_SENS = 0.005, 0.012     -- PCMobileSensitivity, MainDragSensitivity

local GP = { StickDeadzone = 0.15, StickCurve = 1.7, StickYawSpeed = 3.2, StickPitchSpeed = 2.2, ToggleView = Enum.KeyCode.DPadLeft }
local LOOK_ANYWHERE = true
pcall(function()
	local cs = require(WS:WaitForChild("CombatSettings", 10))
	if type(cs) == "table" then
		if type(cs.Gamepad) == "table" then for k, v in pairs(cs.Gamepad) do GP[k] = v end end
		if cs.Enabled == false or cs.MobileLookAnywhere == false then LOOK_ANYWHERE = false end
	end
end)

local function hipMult()   -- réglage « sensibilité arme en main » (même formule que les armes)
	local v = player:GetAttribute("SettingHipSensitivity")
	if type(v) ~= "number" then v = 50 end
	return math.clamp(0.3 + (v / 100) * 1.4, 0.2, 2)
end
local function inArena() return player:GetAttribute("InArena") == true end

--════════════════════════════════════════════════════════════
-- 📷 CAMÉRA
--════════════════════════════════════════════════════════════
local BIND = "ArenaViewKeeper"
local TOKEN = {}               -- notre « jeton » de propriétaire de caméra
local bound = false
local owning = false           -- on pilote la caméra en ce moment
local yaw, pitch = 0, 0
local saved = {}               -- ce qu'on a changé, pour le remettre exactement
local hiddenParts = {}         -- 1re personne : parts cachées localement
local dragInput, dragLast = nil, nil
local padStick = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function wantMode()
	if Shared.IsThirdPersonLock() then return "lock" end
	if IS_MOBILE or IS_CONSOLE then return "first" end   -- PC 1re personne : caméra normale (comme les armes)
	return nil
end

local function setHidden(char, on)
	if on then
		for _, d in ipairs(char:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Decal")) and hiddenParts[d] == nil then
				hiddenParts[d] = d.LocalTransparencyModifier
				d.LocalTransparencyModifier = 1
			end
		end
	else
		for d, v in pairs(hiddenParts) do
			if d.Parent then d.LocalTransparencyModifier = v end
		end
		table.clear(hiddenParts)
	end
end

-- On rend la caméra à Roblox (sortie d'arène, mort, PC en 1re personne…)
local function release(restoreMouse)
	if not owning then return end
	owning = false
	local camera = workspace.CurrentCamera
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	setHidden(char, false)
	if Shared.CameraOwner() == TOKEN then
		Shared.ReleaseCamera(TOKEN)
		-- personne d'autre ne la tient : retour caméra normale, en gardant la direction
		local keep = camera.CFrame
		camera.CameraType = Enum.CameraType.Custom
		if hum then camera.CameraSubject = hum ; hum.AutoRotate = true end
		task.defer(function()
			if camera.CameraType == Enum.CameraType.Custom then camera.CFrame = keep end
		end)
		if restoreMouse and not IS_TOUCH then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end
	if saved.mouseDelta then UserInputService.MouseDeltaSensitivity = saved.mouseDelta end
	saved = {}
	player:SetAttribute("ArenaViewKept", nil)   -- lu par le bouton lock mobile (ShiftGUI)
end

local function step(dt)
	local camera = workspace.CurrentCamera
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local alive = hum and root and hum.Health > 0
	local mode = wantMode()

	-- une arme (ou une cinématique, l'écran de mort, un spectate) tient la caméra : on la laisse
	local owner = Shared.CameraOwner()
	local busy = Shared.AnyEquipped() or (owner ~= nil and owner ~= TOKEN)
		or camera:GetAttribute("KeepScriptable") or workspace:GetAttribute("AnimEditorFreeze")
	if not alive or busy or not mode then
		if owning then
			if owner ~= nil and owner ~= TOKEN then
				-- une arme vient de reprendre la caméra : on ne touche à RIEN (elle repart d'ici)
				owning = false
				setHidden(char, false)
				if saved.mouseDelta then UserInputService.MouseDeltaSensitivity = saved.mouseDelta end
				saved = {}
				player:SetAttribute("ArenaViewKept", nil)
			else
				release(true)
			end
		end
		return
	end

	if not owning then
		-- on prend le relais : on repart EXACTEMENT de l'orientation actuelle
		local sy, sp = Shared.GetCamera()
		local lv = camera.CFrame.LookVector
		local cy, cp = math.atan2(-lv.X, -lv.Z), math.asin(math.clamp(lv.Y, -1, 1))
		if sy and sp then
			local d = (sy - cy + math.pi) % (2 * math.pi) - math.pi
			if math.abs(d) < math.rad(25) and math.abs(sp - cp) < math.rad(25) then cy, cp = sy, sp end
		end
		yaw, pitch = cy, math.clamp(cp, PITCH_MIN, PITCH_MAX)
		Shared.ClaimCamera(TOKEN, root)   -- root : si le perso meurt, le jeton se libère tout seul
		saved.mouseDelta = UserInputService.MouseDeltaSensitivity
		UserInputService.MouseDeltaSensitivity = 1   -- comme les armes en vue lock
		owning = true
		player:SetAttribute("ArenaViewKept", true)
	end
	Shared.ClaimCamera(TOKEN, root)

	-- 🎮 stick droit (même courbe que les armes)
	if padStick then
		local x, y = padStick.X, padStick.Y
		local m = math.sqrt(x * x + y * y)
		local dz = GP.StickDeadzone or 0.15
		if m > dz then
			local k = (math.clamp((m - dz) / (1 - dz), 0, 1) ^ (GP.StickCurve or 1.7)) / m
			local mult = hipMult()
			yaw -= x * k * (GP.StickYawSpeed or 3.2) * dt * mult
			pitch = math.clamp(pitch + y * k * (GP.StickPitchSpeed or 2.2) * dt * mult, PITCH_MIN, PITCH_MAX)
		end
	end

	if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
	if not IS_TOUCH and mode == "lock" then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		-- 🖱️ seule différence avec une arme : pas de viseur
		if UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = false end
	end
	pitch = math.clamp(pitch, PITCH_MIN, PITCH_MAX)
	local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local roll = CFrame.Angles(0, 0, Shared.GetCameraRoll())
	if mode == "first" then
		local headPos = root.Position + Vector3.new(0, 1.5, 0) + hum.CameraOffset
		camera.CFrame = CFrame.new(headPos) * rot * roll
		setHidden(char, true)
	else
		setHidden(char, false)
		local charPos = root.Position + Vector3.new(0, CAM_HEIGHT, 0)
		local lookAt = charPos + rot.RightVector * CAM_SIDE
		local desired = lookAt - rot.LookVector * CAM_DISTANCE + Vector3.new(0, CAM_LIFT, 0)
		rayParams.FilterDescendantsInstances = { char }
		local res = workspace:Raycast(lookAt, desired - lookAt, rayParams)
		local camPos = desired
		if res then camPos = res.Position + (lookAt - res.Position).Unit * 0.5 end
		camera.CFrame = CFrame.new(camPos, lookAt) * roll
	end
	-- le perso regarde où regarde la caméra (pas pendant la tyrolienne : elle pilote le perso)
	if not char:GetAttribute("Ziplining") then
		local rlv = root.CFrame.LookVector
		local d = (yaw - math.atan2(-rlv.X, -rlv.Z) + math.pi) % (2 * math.pi) - math.pi
		if math.abs(d) > math.rad(2) then
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
			root.AssemblyAngularVelocity = Vector3.zero
		end
		if hum.AutoRotate then hum.AutoRotate = false end
	end
	-- 🔁 la prochaine arme reprend la caméra EXACTEMENT ici
	Shared.SetCamera(yaw, pitch)
end

-- ── rotation : souris / doigt / manette (mêmes réglages que les armes) ──
UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then padStick = input.Position end
	if not owning then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement and not IS_TOUCH then
		local m = hipMult()
		yaw -= input.Delta.X * MOUSE_SENS * m
		pitch = math.clamp(pitch - input.Delta.Y * MOUSE_SENS * m, PITCH_MIN, PITCH_MAX)
	elseif input.UserInputType == Enum.UserInputType.Touch and input == dragInput and dragLast then
		local np = Vector2.new(input.Position.X, input.Position.Y)
		local d = np - dragLast ; dragLast = np
		local m = hipMult()
		yaw -= d.X * DRAG_SENS * m
		pitch = math.clamp(pitch - d.Y * DRAG_SENS * m, PITCH_MIN, PITCH_MAX)
	end
end)
UserInputService.InputBegan:Connect(function(input)
	if not owning or input.UserInputType ~= Enum.UserInputType.Touch or dragInput then return end
	if Shared.IsTouchClaimed and Shared.IsTouchClaimed(input) then return end
	local camera = workspace.CurrentCamera
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if not LOOK_ANYWHERE and pos.X < camera.ViewportSize.X * 0.5 then return end
	local pg = player:FindFirstChild("PlayerGui")
	if pg then
		for _, o in ipairs(pg:GetGuiObjectsAtPosition(pos.X, pos.Y)) do
			if o:IsA("GuiButton") or o:IsA("TextBox") then return end
			if LOOK_ANYWHERE and (o.Name:find("Thumbstick") or (o:FindFirstAncestor("TouchGui") and o.Name ~= "TouchControlFrame")) then return end
		end
	end
	if LOOK_ANYWHERE and not (pg and pg:FindFirstChild("TouchGui"))
		and pos.X < camera.ViewportSize.X * 0.4 and pos.Y > camera.ViewportSize.Y * 0.35 then return end
	dragInput, dragLast = input, pos
end)
UserInputService.InputEnded:Connect(function(input)
	if input == dragInput then dragInput, dragLast = nil, nil end
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then padStick = nil end
end)

--════════════════════════════════════════════════════════════
-- ⌨️ PANNEAU DES CONTRÔLES SANS ARME (même look et même place que celui des armes)
--════════════════════════════════════════════════════════════
local panel, rows = nil, {}
local function controlsHidden() return player:GetAttribute("ControlsHidden") == true end
local function paintControls()
	if not panel then return end
	local hidden = controlsHidden()
	for key, r in pairs(rows) do
		if key ~= "H" then r.row.Visible = not hidden end
	end
	rows.H.desc.Text = hidden and "Reveal Controls" or "Hide Controls"
end
local function buildPanel()
	if panel or IS_TOUCH or not SHOW_CONTROLS then return end
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UnarmedControlsGui"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = pg
	local anchor = Instance.new("Frame")   -- même emplacement que l'AmmoHud des armes
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
		local cw = (#k.key > 1) and (chip + (#k.key - 1) * 9) or chip
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
player:GetAttributeChangedSignal("ControlsHidden"):Connect(paintControls)

local function unarmedInArena()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return inArena() and hum ~= nil and hum.Health > 0 and not Shared.AnyEquipped()
end
local function updatePanel()
	local on = unarmedInArena()
	if on then buildPanel() end
	if panel and panel.Enabled ~= on then panel.Enabled = on end
end

-- sans arme en arène : rien d'autre n'écoute B / H → c'est nous
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not unarmedInArena() then return end
	if (input.KeyCode == Enum.KeyCode.B and not IS_TOUCH) or input.KeyCode == GP.ToggleView then
		Shared.ToggleMode()   -- même fonction que les armes (le choix est aussi sauvegardé)
	elseif input.KeyCode == Enum.KeyCode.H and not IS_TOUCH then
		player:SetAttribute("ControlsHidden", not controlsHidden())   -- même état que les armes
	end
end)

--════════════════════════════════════════════════════════════
-- 🔌 ON / OFF selon l'arène
--════════════════════════════════════════════════════════════
local function frame(dt)
	updatePanel()
	step(dt)
end
local function refresh()
	if inArena() then
		if not bound then
			bound = true
			-- même priorité que la caméra des armes : la vue bouge avant le reste
			RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value, frame)
		end
	elseif bound then
		bound = false
		RunService:UnbindFromRenderStep(BIND)
		release(true)
		updatePanel()
	end
end
player:GetAttributeChangedSignal("InArena"):Connect(refresh)
player.CharacterAdded:Connect(function()
	if owning then release(false) end
	table.clear(hiddenParts)
end)
refresh()
