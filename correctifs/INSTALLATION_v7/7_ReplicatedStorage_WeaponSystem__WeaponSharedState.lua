-- ============================================================
-- WeaponSharedState  (ModuleScript)  —  V4
-- Emplacement : ReplicatedStorage/WeaponSystem/WeaponSharedState
-- ============================================================
-- Changements V4 :
--  • Flag "caméra orpheline" : quand le propriétaire de la caméra
--    meurt/disparaît SANS l'avoir rendue, le flag se lève. Le script
--    WeaponDeathWatchdog (StarterPlayerScripts) le consomme pour
--    rendre la caméra au joueur, même si le script de l'arme est mort.
--  (V3 : ClaimCamera/ReleaseCamera/CameraOwner ; V2 : suivi par tool,
--   SetFiring, ClaimTouch, etc.)
-- ============================================================
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer      = Players.LocalPlayer

local M = {}

-- ── Plateforme ──────────────────────────────────────────────
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
function M.IsMobile() return IS_MOBILE end

-- ── Mode caméra ─────────────────────────────────────────────
-- 🎮 CONSOLE (Xbox / PlayStation) : 3e personne avec lock par défaut, comme sur mobile
local IS_CONSOLE = false
pcall(function() IS_CONSOLE = game:GetService("GuiService"):IsTenFootInterface() end)
local mode = (IS_MOBILE or IS_CONSOLE) and "ThirdPersonLock" or "FirstPersonAim"
local modeChangedBindable = Instance.new("BindableEvent")
M.ModeChanged = modeChangedBindable.Event

function M.IsThirdPersonLock() return mode == "ThirdPersonLock" end
function M.IsFirstPersonAim()  return mode == "FirstPersonAim"  end
function M.GetMode()           return mode end

function M.SetMode(newMode)
	if newMode ~= "FirstPersonAim" and newMode ~= "ThirdPersonLock" then return end
	if newMode == mode then return end
	mode = newMode
	modeChangedBindable:Fire(mode)
end

-- 💾 LA VUE CHOISIE EST MÉMORISÉE (réglage sauvegardé, un par type d'appareil) :
--    0 = vue par défaut de l'appareil · 1 = FirstPersonAim · 2 = ThirdPersonLock
local VIEW_KEY = IS_MOBILE and "SettingViewMobile" or (IS_CONSOLE and "SettingViewConsole" or "SettingViewPC")
local function saveView()
	local v = (mode == "ThirdPersonLock") and 2 or 1
	if LocalPlayer:GetAttribute(VIEW_KEY) == v then return end
	LocalPlayer:SetAttribute(VIEW_KEY, v)
	local r = game:GetService("ReplicatedStorage"):FindFirstChild("UpdateSetting")
	if r and LocalPlayer:GetAttribute("SettingsLoaded") == true then
		pcall(function() r:FireServer(VIEW_KEY, v) end)
	end
end

-- appelé UNIQUEMENT par le joueur (touche B, bouton VIEW, manette) : c'est son choix → mémorisé
function M.ToggleMode()
	M.SetMode(mode == "FirstPersonAim" and "ThirdPersonLock" or "FirstPersonAim")
	saveView()
end

-- ── Caméra (yaw/pitch préservés entre armes) ────────────────
local camYaw, camPitch
local camInit = false
function M.GetCamera()
	if not camInit then return nil, nil end
	return camYaw, camPitch
end
function M.SetCamera(yaw, pitch)
	camYaw, camPitch = yaw, pitch
	camInit = true
end
function M.IsCameraInitialized() return camInit end

-- ── 🆕 PROPRIÉTAIRE DE LA CAMÉRA (anti caméra figée) ────────
-- L'arme qui met la caméra en Scriptable la "réclame" avec un token.
-- Au déséquipe, si personne ne la possède → retour Custom garanti.
-- Si l'arme propriétaire meurt/disparaît sans libérer → auto-purge.
local cameraOwnerToken, cameraOwnerTool = nil, nil
local cameraOrphaned = false

function M.ClaimCamera(token, tool)
	cameraOwnerToken, cameraOwnerTool = token, tool
end

function M.ReleaseCamera(token)
	if cameraOwnerToken == token then
		cameraOwnerToken, cameraOwnerTool = nil, nil
	end
end

function M.CameraOwner()
	if cameraOwnerToken and cameraOwnerTool then
		local par = cameraOwnerTool.Parent
		local hum = par and par:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			-- propriétaire mort / arme détruite SANS avoir rendu la caméra
			-- → purge + flag "orpheline" (consommé par WeaponDeathWatchdog)
			cameraOwnerToken, cameraOwnerTool = nil, nil
			cameraOrphaned = true
		end
	end
	return cameraOwnerToken
end

-- true UNE fois si la caméra a été abandonnée par une arme morte
function M.ConsumeCameraOrphan()
	local v = cameraOrphaned
	cameraOrphaned = false
	return v
end

-- ── Armes équipées : suivi PAR TOOL (anti-fuite) ────────────
local equippedTools = setmetatable({}, { __mode = "k" })

local function equippedCountNow()
	local n = 0
	for t in pairs(equippedTools) do
		local par = t.Parent
		local hum = par and par:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			n += 1
		else
			equippedTools[t] = nil
		end
	end
	return n
end

-- ── Shift-lock natif Roblox (méthode BoundKeys) ─────────────
local inNoShiftLockZone = false
local CUSTOM_BOUND_KEYS = "LeftShift,LeftControl"

local function getBoundKeys()
	local ps = LocalPlayer:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	local cm = pm and pm:FindFirstChild("CameraModule")
	local ml = cm and cm:FindFirstChild("MouseLockController")
	return ml and ml:FindFirstChild("BoundKeys") or nil
end

local function setNativeShiftLock(enabled)
	if IS_MOBILE then return end
	if enabled and (inNoShiftLockZone or equippedCountNow() > 0) then return end
	local bk = getBoundKeys()
	local v = enabled and CUSTOM_BOUND_KEYS or ""
	-- n'écrit QUE si la valeur change : réécrire la même valeur fait quand même
	-- réagir le MouseLockController natif
	if bk and bk.Value ~= v then bk.Value = v end
end
local shiftLockRestoreToken = 0
function M.RegisterWeaponEquipped(tool)
	if typeof(tool) == "Instance" then equippedTools[tool] = true end
	shiftLockRestoreToken += 1   -- annule une réactivation en attente (switch en cours)
	if equippedCountNow() >= 1 then setNativeShiftLock(false) end
end
function M.RegisterWeaponUnequipped(tool)
	if typeof(tool) == "Instance" then equippedTools[tool] = nil end
	-- ⚠ FIX SAUT DE CAMÉRA AU SWITCH : ne PAS réactiver le shift-lock natif
	-- tout de suite. Pendant un switch (déséquipe → rééquipe en 1-2 frames),
	-- le toggle des BoundKeys faisait réagir le MouseLockController natif
	-- (surtout Shift tenu pour sprinter) → la caméra sursautait vers le bas.
	-- On attend 0.25 s : si une arme est rééquipée entre-temps, on n'a RIEN touché.
	shiftLockRestoreToken += 1
	local my = shiftLockRestoreToken
	task.delay(0.25, function()
		if my ~= shiftLockRestoreToken then return end
		if equippedCountNow() == 0 then setNativeShiftLock(true) end
	end)
end

function M.AnyEquipped() return equippedCountNow() > 0 end

-- ── Zone "no shift-lock" ────────────────────────────────────
local modeBeforeZone = nil
function M.SetNoShiftLockZone(active)
	if IS_MOBILE then return end
	active = active and true or false
	if inNoShiftLockZone == active then return end
	inNoShiftLockZone = active
	if active then
		modeBeforeZone = mode
		M.SetMode("FirstPersonAim")
		local bk = getBoundKeys()
		if bk then bk.Value = "" end
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChild("Humanoid")
		if hum then hum.AutoRotate = true end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	else
		setNativeShiftLock(true)
		if modeBeforeZone then
			M.SetMode(modeBeforeZone)
			modeBeforeZone = nil
		end
	end
end

-- 💾 au chargement des réglages : on remet la vue que le joueur avait choisie
task.spawn(function()
	local t0 = os.clock()
	while LocalPlayer:GetAttribute("SettingsLoaded") ~= true and os.clock() - t0 < 60 do task.wait(0.5) end
	local v = LocalPlayer:GetAttribute(VIEW_KEY)
	local want = (v == 1 and "FirstPersonAim") or (v == 2 and "ThirdPersonLock") or nil
	if not want then return end
	if inNoShiftLockZone then
		modeBeforeZone = want          -- zone qui force la 1re personne : la vue revient à la sortie
	else
		M.SetMode(want)
	end
end)

-- init shift-lock natif
task.spawn(function()
	if IS_MOBILE then return end
	local ps = LocalPlayer:WaitForChild("PlayerScripts", 30)
	if not ps then return end
	local pm = ps:WaitForChild("PlayerModule", 30)
	if not pm then return end
	for _ = 1, 60 do
		if getBoundKeys() then break end
		task.wait(0.1)
	end
	if equippedCountNow() == 0 then setNativeShiftLock(true) end
end)

-- ============================================================
-- API MÉCANIQUES (pont WeaponMechanics ↔ WeaponController)
-- ============================================================
local movePoseL, movePoseR = CFrame.new(), CFrame.new()
local moveFOV, moveRoll = 0, 0
local sprinting, sprintAlpha = false, 0
local actionsBlocked, aiming, firing = false, false, false

local cancelSprintBindable = Instance.new("BindableEvent")
M.CancelSprintRequested = cancelSprintBindable.Event

function M.PublishWeaponPose(l, r) movePoseL = l or CFrame.new(); movePoseR = r or CFrame.new() end
function M.GetWeaponPose() return movePoseL, movePoseR end

function M.PublishMoveFOV(v) moveFOV = v or 0 end
function M.GetMoveFOV() return moveFOV end

function M.PublishCameraRoll(v) moveRoll = v or 0 end
function M.GetCameraRoll() return moveRoll end

function M.SetSprinting(b) sprinting = b and true or false end
function M.IsSprinting() return sprinting end

function M.SetSprintAlpha(a) sprintAlpha = a or 0 end
function M.GetSprintAlpha() return sprintAlpha end

function M.SetActionsBlocked(b) actionsBlocked = b and true or false end
function M.AreActionsBlocked() return actionsBlocked end

function M.SetAiming(b) aiming = b and true or false end
function M.IsAiming() return aiming end

function M.SetFiring(b) firing = b and true or false end
function M.IsFiring() return firing end

function M.RequestCancelSprint() cancelSprintBindable:Fire() end

-- ============================================================
-- PROPRIÉTÉ DES TOUCHES (mobile)
-- ============================================================
local _claimedTouches = setmetatable({}, { __mode = "k" })

function M.ClaimTouch(input)
	if not input then return false end
	if _claimedTouches[input] then return false end
	_claimedTouches[input] = true
	return true
end

function M.IsTouchClaimed(input)
	return input ~= nil and _claimedTouches[input] == true
end

function M.ReleaseTouch(input)
	if input then _claimedTouches[input] = nil end
end

return M