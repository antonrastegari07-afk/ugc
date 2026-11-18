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
-- mobile / console : l'arme force une vraie 1re personne → on la garde sans arme.
-- PC : en 1re personne l'arme laisse la caméra normale de Roblox → rien à garder.
local FP_LOCKED = UserInputService.TouchEnabled or game:GetService("GuiService"):IsTenFootInterface()

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
