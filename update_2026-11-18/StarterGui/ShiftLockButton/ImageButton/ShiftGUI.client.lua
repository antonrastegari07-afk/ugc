-- ════════════════════════════════════════════════════════════════════════
-- 🔒 LOCK MOBILE (ton bouton) — v2 : l'état est GARDÉ après la mort
--   📍 StarterGui ▸ ShiftLockButton ▸ ImageButton ▸ ShiftGUI (remplace tout le script)
--
--   AVANT : le ScreenGui avait ResetOnSpawn = true → à chaque mort le script
--           redémarrait et le lock repassait sur OFF.
--   MAINTENANT :
--     • le ScreenGui est passé en ResetOnSpawn = false au lancement (rien à
--       changer dans Studio) et le script suit chaque nouveau personnage ;
--     • ton choix ON/OFF est gardé toute la session (mort, respawn, reload de perso) ;
--     • en ARÈNE PvP le lock est mis en pause (la caméra des armes gère tout),
--       puis remis tout seul à la sortie si tu l'avais activé ;
--     • tu peux quand même l'allumer / l'éteindre à la main pendant l'arène.
--   Même bouton, mêmes images, même décalage de caméra qu'avant.
--   Perf : UNE seule connexion RenderStepped, et seulement quand le lock est actif.
-- ════════════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local button = script.Parent

-- 🔁 plus de reset à la mort : ce script tourne une seule fois par session
local screenGui = button:FindFirstAncestorOfClass("ScreenGui")
if screenGui then screenGui.ResetOnSpawn = false end

button.Visible = UserInputService.TouchEnabled

local IMAGES = {
	OFF = "rbxasset://textures/ui/mouseLock_off@2x.png",
	ON = "rbxasset://textures/ui/mouseLock_on@2x.png",
}
local MAX_LENGTH = 900000
local ENABLED_OFFSET = CFrame.new(1.7, 0, 0)
local DISABLED_OFFSET = CFrame.new(-1.7, 0, 0)

local wanted = false        -- choix du joueur (gardé toute la session)
local arenaManual = nil     -- choix fait À LA MAIN pendant l'arène (oublié à la sortie)
local renderConn = nil      -- RenderStepped actif uniquement quand le lock tourne
local character, humanoid, root

local function inArena()
	return player:GetAttribute("InArena") == true
end

local function setImage(on)
	button.Image = on and IMAGES.ON or IMAGES.OFF
end

local function stopLock(moveCamera)
	if not renderConn then return end
	renderConn:Disconnect()
	renderConn = nil
	if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
	if moveCamera then camera = workspace.CurrentCamera ; camera.CFrame = camera.CFrame * DISABLED_OFFSET end
end

local function startLock()
	if renderConn then return end
	renderConn = RunService.RenderStepped:Connect(function()
		if not (root and root.Parent and humanoid and humanoid.Parent and humanoid.Health > 0) then return end
		camera = workspace.CurrentCamera
		humanoid.AutoRotate = false
		local look = camera.CFrame.LookVector
		root.CFrame = CFrame.new(root.Position,
			Vector3.new(look.X * MAX_LENGTH, root.Position.Y, look.Z * MAX_LENGTH))
		camera.CFrame = camera.CFrame * ENABLED_OFFSET
	end)
end

-- Applique l'état voulu (choix du joueur, pause en arène)
local function apply(moveCamera)
	local on
	if inArena() then
		on = arenaManual == true          -- en arène : OFF sauf si allumé à la main
		-- ArenaViewKeeper garde déjà la vue lock sans arme : on ne double pas le décalage
		if player:GetAttribute("ArenaViewKept") == true then on = false end
	else
		on = wanted
	end
	setImage(on)
	if on and root and humanoid and humanoid.Health > 0 then
		startLock()
	else
		stopLock(moveCamera)
	end
end

local function toggle()
	if inArena() then
		local cur = arenaManual == true
		arenaManual = not cur
	else
		wanted = not wanted
	end
	apply(true)
end

local function bindCharacter(char)
	stopLock(false)
	character = char
	humanoid = char:WaitForChild("Humanoid", 10)
	root = char:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and root) or character ~= char then return end
	humanoid.Died:Connect(function()
		if character == char then stopLock(false) end
	end)
	task.defer(apply, false)   -- remet le lock si le joueur l'avait activé
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then task.spawn(bindCharacter, player.Character) end

player:GetAttributeChangedSignal("InArena"):Connect(function()
	arenaManual = nil
	apply(false)
end)
player:GetAttributeChangedSignal("ArenaViewKept"):Connect(function() apply(false) end)

-- (même liaison qu'avant, protégée : elle ne doit jamais casser le bouton)
pcall(function()
	CAS:BindAction("ShiftLOCK", function(_, state)
		if state == Enum.UserInputState.Begin then toggle() end
	end, false, "On")
	CAS:SetPosition("ShiftLOCK", UDim2.new(0.8, 0, 0.8, 0))
end)

button.MouseButton1Click:Connect(toggle)
setImage(false)
