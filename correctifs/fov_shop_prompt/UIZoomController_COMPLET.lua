-- ModuleScript enfant de ReplicatedStorage > RobuxPromptFX.
-- Une instance par client, partagée par les menus et les prompts d'achat.
-- Un seul Tween de FOV. Aucun Heartbeat / RenderStepped / polling.
--
-- 🩹 Base = FOV NORMAL publié par UIFocus (attribut UIFocusNormalFOV), plus le FOV de
--    l'instant. Avant : si le prompt s'ouvrait pendant un menu (FOV 60) ou pendant un
--    boost, cette valeur devenait la base et le FOV y restait à la fermeture.
-- 🏷️ Attribut UIZoomActive sur la caméra pendant le zoom : UIFocus ne le « corrige »
--    plus au bout d'1 s (avant : zoom, puis dézoom alors que le prompt était encore ouvert).
-- 🛍️ Menu UIFocus ouvert (shop…) : UIFocus écrit déjà le FOV à chaque image. Ce module
--    n'écrit alors PLUS RIEN (SetExternal) : UIFocus ajoute lui-même le zoom du prompt
--    (GetOffset) au FOV du menu. Un seul script écrit le FOV à la fois → pas de flick,
--    et à la fermeture du prompt on revient au FOV du shop, pas au FOV normal.
--    Quand le menu se ferme pendant le prompt, ce module reprend la main là où était le FOV.
local Controller = {}
Controller.__index = Controller
local singleton

local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Même courbe que le Tween (Quad Out) : l'offset calculé suit exactement le zoom affiché.
local function easeOut(a)
	return 1 - (1 - a) * (1 - a)
end

function Controller.new(services)
	local self = setmetatable({ services = services, owners = {}, blockers = {},
		camera = nil, baseFOV = nil, tween = nil, completed = nil,
		generation = 0, destroyed = false, lastDuration = 0,
		external = false, offFrom = 0, offTo = 0, offT0 = 0, offDur = 0 }, Controller)
	self.cameraConnection = services.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:_restore()
		local camera = services.Workspace.CurrentCamera
		if camera then self:_setActive(camera) end
		if not self.external then self:_drive(camera) end
	end)
	return self
end

function Controller:_cancel()
	self.generation = self.generation + 1
	-- Déconnecter avant Cancel : Completed peut être immédiat ou différé.
	if self.completed then self.completed:Disconnect() self.completed = nil end
	if self.tween then self.tween:Cancel() self.tween = nil end
end

local function setActive(camera, on)
	if camera then pcall(function() camera:SetAttribute("UIZoomActive", on or nil) end) end
end

function Controller:_hasOwners()
	return next(self.owners) ~= nil and next(self.blockers) == nil
end

function Controller:_setActive(camera)
	setActive(camera, self:_hasOwners())
end

local function normalOf(camera, currentOffset)
	local normal = camera and camera:GetAttribute("UIFocusNormalFOV")
	if type(normal) == "number" then return normal end
	return camera and (camera.FieldOfView - currentOffset) or 70
end

-- Zoom du prompt à cet instant (0 = aucun). Lu à chaque image par UIFocus quand un menu est ouvert.
function Controller:GetOffset()
	local a = self.offDur > 0 and math.clamp((os.clock() - self.offT0) / self.offDur, 0, 1) or 1
	return self.offFrom + (self.offTo - self.offFrom) * easeOut(a)
end

-- Ancienne caméra (CurrentCamera remplacée) : on la remet au normal et on l'oublie.
function Controller:_restore()
	self:_cancel()
	local camera, value = self.camera, self.baseFOV
	self.camera, self.baseFOV = nil, nil
	setActive(camera, false)
	if camera and value and not self.external then pcall(function() camera.FieldOfView = value end) end
end

-- Écrit le FOV (uniquement quand aucun menu UIFocus ne le pilote).
function Controller:_drive(camera)
	if self.destroyed or self.external then return end
	if self.camera and self.camera ~= camera then self:_restore() end
	self:_cancel()
	if not camera then return end
	if not self.camera then
		-- rien à zoomer ni à finir de dézoomer → on ne touche à rien
		if self.offTo == 0 and math.abs(self:GetOffset()) < 0.0001 then return end
		self.camera, self.baseFOV = camera, normalOf(camera, self:GetOffset())
	end
	local goal = self.baseFOV + self.offTo
	local remaining = math.max(0, self.offT0 + self.offDur - os.clock())
	local generation = self.generation
	local function finish()
		if self.destroyed or self.external or self.generation ~= generation or self.camera ~= camera then return end
		if self.completed then self.completed:Disconnect() self.completed = nil end
		self.tween = nil
		-- Une fin interrompue ne doit pas conserver une session de retour bloquée.
		-- Nos propres interruptions sont déjà déconnectées et invalidées.
		camera.FieldOfView = goal
		if self.offTo == 0 then self.camera, self.baseFOV = nil, nil end
	end
	if remaining <= 0 or math.abs(camera.FieldOfView - goal) < 0.0001 then finish() return end
	local tween = self.services.TweenService:Create(camera,
		TweenInfo.new(remaining, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = goal })
	self.tween = tween
	self.completed = tween.Completed:Connect(finish)
	tween:Play()
end

function Controller:_apply(duration)
	if self.destroyed then return end
	local camera = self.services.Workspace.CurrentCamera
	local hasOwners = self:_hasOwners()
	local offset, minimum, maximum = 0, 1, 120
	if hasOwners then
		for _, request in pairs(self.owners) do
			offset = offset + request.offset
			minimum = math.max(minimum, request.minimum)
			maximum = math.min(maximum, request.maximum)
		end
	end
	local target = 0
	if hasOwners then
		local base = (self.camera == camera and self.baseFOV) or normalOf(camera, self:GetOffset())
		target = math.clamp(base + offset, minimum, math.max(minimum, maximum)) - base
	end
	-- Le nouvel offset part de sa valeur ACTUELLE : jamais de saut, même en plein zoom.
	self.offFrom, self.offTo = self:GetOffset(), target
	self.offT0, self.offDur = os.clock(), math.max(0, duration)
	if camera then setActive(camera, hasOwners) end
	self:_drive(camera)
end

function Controller:Set(owner, offset, duration, minimum, maximum)
	if self.destroyed then return end
	assert(owner ~= nil, "UIZoomController: owner requis")
	if not finite(offset) or offset == 0 then offset = nil end
	duration = finite(duration) and math.max(0, duration) or 0
	local previous = self.owners[owner]
	if offset then
		minimum = finite(minimum) and math.clamp(minimum, 1, 120) or 1
		maximum = finite(maximum) and math.clamp(maximum, minimum, 120) or 120
		if previous and previous.offset == offset and previous.minimum == minimum and previous.maximum == maximum then return end
		self.owners[owner] = { offset = offset, minimum = minimum, maximum = maximum }
	else
		if not previous then return end
		self.owners[owner] = nil
	end
	self.lastDuration = duration
	self:_apply(duration)
end

function Controller:Suspend(owner, on)
	if self.destroyed or (self.blockers[owner] == true) == (on == true) then return end
	self.blockers[owner] = on and true or nil
	self:_apply(on and 0 or self.lastDuration)
end

-- 🛍️ Appelé par UIFocus (SceneEffects) : true quand il écrit le FOV d'un menu à chaque
--    image (il ajoute alors GetOffset()), false quand il rend la main. À false, UIFocus a
--    déjà remis « normal + GetOffset() » : on continue le zoom/dézoom depuis là, sans saut.
function Controller:SetExternal(on)
	on = on == true
	if self.destroyed or self.external == on then return end
	self.external = on
	self:_cancel()
	self.camera, self.baseFOV = nil, nil   -- le menu a pu changer le FOV : base relue à la reprise
	if not on then self:_drive(self.services.Workspace.CurrentCamera) end
end

-- À appeler par un contrôleur de sprint/visée qui change le FOV normal
-- pendant un zoom. Au repos, les modifications normales de la caméra sont
-- automatiquement capturées à la prochaine ouverture.
function Controller:SetBaseFOV(value, duration)
	if self.destroyed or not finite(value) or self.external then return end
	value = math.clamp(value, 1, 120)
	if self.camera then
		self.baseFOV = value
		self:_drive(self.services.Workspace.CurrentCamera)
	else
		local camera = self.services.Workspace.CurrentCamera
		if camera then camera.FieldOfView = value end
	end
end

function Controller:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.cameraConnection:Disconnect()
	self:_restore()
	self.owners, self.blockers = {}, {}
	self.offFrom, self.offTo, self.offDur = 0, 0, 0
end

function Controller.Get()
	assert(game:GetService("RunService"):IsClient(), "UIZoomController est réservé au client")
	if not singleton or singleton.destroyed then
		singleton = Controller.new({ Workspace = workspace, TweenService = game:GetService("TweenService") })
	end
	return singleton
end

return Controller
