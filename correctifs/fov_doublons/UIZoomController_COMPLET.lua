-- ModuleScript enfant de ReplicatedStorage > RobuxPromptFX.
-- Une instance par client, partagée par les menus et les prompts d'achat.
-- Un seul Tween de FOV. Aucun Heartbeat / RenderStepped / polling.
--
-- 🩹 Base = FOV NORMAL publié par UIFocus (attribut UIFocusNormalFOV), plus le FOV de
--    l'instant. Avant : si le prompt s'ouvrait pendant un menu (FOV 60) ou pendant un
--    boost, cette valeur devenait la base et le FOV y restait à la fermeture.
-- 🏷️ Attribut UIZoomActive sur la caméra pendant le zoom : UIFocus ne le « corrige »
--    plus au bout d'1 s (avant : zoom, puis dézoom alors que le prompt était encore ouvert).
local Controller = {}
Controller.__index = Controller
local singleton

local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Controller.new(services)
	local self = setmetatable({ services = services, owners = {}, blockers = {},
		camera = nil, baseFOV = nil, tween = nil, completed = nil,
		generation = 0, destroyed = false, lastDuration = 0 }, Controller)
	self.cameraConnection = services.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:_restore()
		self:_apply(self.lastDuration)
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

function Controller:_restore()
	self:_cancel()
	local camera, value = self.camera, self.baseFOV
	self.camera, self.baseFOV = nil, nil
	setActive(camera, false)
	if camera and value then pcall(function() camera.FieldOfView = value end) end
end

function Controller:_apply(duration)
	if self.destroyed then return end
	if next(self.blockers) then self:_restore() return end
	local camera = self.services.Workspace.CurrentCamera
	if self.camera and self.camera ~= camera then self:_restore() end
	if not camera then return end
	local hasOwners = next(self.owners) ~= nil
	if not self.camera then
		if not hasOwners then return end
		local normal = camera:GetAttribute("UIFocusNormalFOV")
		self.camera, self.baseFOV = camera, (type(normal) == "number" and normal) or camera.FieldOfView
	end
	setActive(camera, hasOwners)
	local offset, minimum, maximum = 0, 1, 120
	for _, request in pairs(self.owners) do
		offset = offset + request.offset
		minimum = math.max(minimum, request.minimum)
		maximum = math.min(maximum, request.maximum)
	end
	local goal = self.baseFOV
	if hasOwners then goal = math.clamp(goal + offset, minimum, math.max(minimum, maximum)) end
	self:_cancel()
	local generation = self.generation
	local function finish()
		if self.destroyed or self.generation ~= generation or self.camera ~= camera then return end
		if self.completed then self.completed:Disconnect() self.completed = nil end
		self.tween = nil
		-- Une fin interrompue ne doit pas conserver une session de retour bloquée.
		-- Nos propres interruptions sont déjà déconnectées et invalidées.
		camera.FieldOfView = goal
		if not hasOwners then self.camera, self.baseFOV = nil, nil end
	end
	if duration <= 0 or math.abs(camera.FieldOfView - goal) < 0.0001 then finish() return end
	local tween = self.services.TweenService:Create(camera,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = goal })
	self.tween = tween
	self.completed = tween.Completed:Connect(finish)
	tween:Play()
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

-- À appeler par un contrôleur de sprint/visée qui change le FOV normal
-- pendant un zoom. Au repos, les modifications normales de la caméra sont
-- automatiquement capturées à la prochaine ouverture.
function Controller:SetBaseFOV(value, duration)
	if self.destroyed or not finite(value) then return end
	value = math.clamp(value, 1, 120)
	if self.camera then
		self.baseFOV = value
		self:_apply(finite(duration) and math.max(0, duration) or 0)
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
end

function Controller.Get()
	assert(game:GetService("RunService"):IsClient(), "UIZoomController est réservé au client")
	if not singleton or singleton.destroyed then
		singleton = Controller.new({ Workspace = workspace, TweenService = game:GetService("TweenService") })
	end
	return singleton
end

return Controller
