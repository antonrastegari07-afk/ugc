-- Flou et caméra : le FOV d'origine est conservé pendant toute la session,
-- y compris si un menu se rouvre pendant l'animation de fermeture.
--
-- 🩹 FOV « normal » APPRIS, plus jamais lu au moment où le menu s'ouvre.
--    Avant : baseFOV = FOV de la caméra à l'ouverture. Si à cet instant le FOV
--    était provisoirement plus haut (coup de FOV du dash de la faux, sprint,
--    tween d'un autre script pas fini…), cette valeur devenait le « normal » :
--    à la fermeture on y revenait et ça restait jusqu'à ce que le joueur rejoigne.
--    Maintenant : le normal est le FOV de départ, mis à jour SEULEMENT quand
--    aucun menu n'est ouvert et que le FOV est resté stable 1 s.
--
-- 🎮 Phase jouable du Rookie Guide : AUCUN flou, quelle que soit sa source.
--    Les BlurEffect sous la caméra et dans Lighting sont coupés (Enabled = false)
--    pendant la phase, puis remis exactement comme avant.
local Effects = {}
Effects.__index = Effects

local STABLE_DELAY = 1.0   -- s sans changement avant d'adopter un nouveau FOV « normal »

function Effects.new(config, services)
	local self = setmetatable({
		config = config, services = services, menu = nil,
		session = nil, core = {}, destroyed = false, gameplay = false,
		normalFOV = nil, fovToken = 0, fovConnection = nil,
		muted = {}, muteConnections = {},
	}, Effects)
	self:_watchCamera()
	self.cameraConnection = services.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:_release()
		self:_watchCamera()
		if self.gameplay then self:_muteBlurs(true) end
		if self.menu then self:_animate() end
	end)
	return self
end

function Effects:_clampFOV(v)
	local z = self.config.Zoom
	local minimum = math.clamp(z.MinFOV or 20, 1, 120)
	local maximum = math.clamp(z.MaxFOV or 110, minimum, 120)
	return math.clamp(v, minimum, maximum)
end

-- Apprend le FOV « normal » : seulement au repos (aucun menu, aucune session)
-- et après STABLE_DELAY sans changement. Un coup de FOV de 0.6 s n'est jamais adopté.
function Effects:_watchCamera()
	if self.fovConnection then self.fovConnection:Disconnect() self.fovConnection = nil end
	local cam = self.services.Workspace.CurrentCamera
	if not cam then return end
	if not self.normalFOV then self.normalFOV = self:_clampFOV(cam.FieldOfView) end
	self:_publish(cam)
	self.fovConnection = cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
		if self.menu or self.session then return end
		self.fovToken += 1
		local token, value = self.fovToken, cam.FieldOfView
		task.delay(STABLE_DELAY, function()
			if self.destroyed or token ~= self.fovToken or self.menu or self.session then return end
			if self.services.Workspace.CurrentCamera ~= cam or cam.FieldOfView ~= value then return end
			-- 🩹 Un FOV resté coincé ENTRE le zoom d'un menu et le normal (ex. 62.6 au lieu
			--    de 70 : animation de fermeture coupée par un autre script) n'est pas un
			--    nouveau normal, c'est un reste de zoom → on remet le normal.
			local normal = self.normalFOV
			local offset = math.min(self.config.Zoom.FOVOffset or -10, 0)
			if normal and value < normal - 0.3 and value >= normal + offset - 0.5 then
				self.services.TweenService:Create(cam, TweenInfo.new(0.35, Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out), { FieldOfView = normal }):Play()
				return
			end
			self.normalFOV = self:_clampFOV(value)
			self:_publish(cam)
		end)
	end)
end

-- Le FOV normal est publié sur la caméra (attribut UIFocusNormalFOV) : les autres
-- scripts qui touchent au FOV (coup de FOV du dash) reviennent à CETTE valeur.
function Effects:_publish(cam)
	cam = cam or self.services.Workspace.CurrentCamera
	if cam and self.normalFOV then pcall(function() cam:SetAttribute("UIFocusNormalFOV", self.normalFOV) end) end
end

function Effects:_core(on)
	local starterGui = self.services.StarterGui
	if on then
		if not self.config.CoreGui.Enabled then return end
		for _, name in ipairs(self.config.CoreGui.Types) do
			local kind = Enum.CoreGuiType[name]
			if kind and self.core[name] == nil then
				local ok, was = pcall(function() return starterGui:GetCoreGuiEnabled(kind) end)
				if ok then
					local applied = pcall(function() starterGui:SetCoreGuiEnabled(kind, false) end)
					if applied then self.core[name] = was end
				end
			end
		end
	else
		for name, was in pairs(self.core) do
			pcall(function() starterGui:SetCoreGuiEnabled(Enum.CoreGuiType[name], was) end)
		end
		self.core = {}
	end
end

-- 🎮 Coupe / remet TOUS les BlurEffect (caméra + Lighting), y compris ceux des
--    anciens scripts, pendant la phase jouable du guide.
function Effects:_muteOne(object)
	if not object:IsA("BlurEffect") or self.muted[object] ~= nil then return end
	self.muted[object] = object.Enabled
	object.Enabled = false
	-- un script qui rallume son flou pendant la phase est recoupé
	table.insert(self.muteConnections, object:GetPropertyChangedSignal("Enabled"):Connect(function()
		if self.gameplay and object.Enabled then object.Enabled = false end
	end))
end

function Effects:_muteBlurs(on)
	for _, c in ipairs(self.muteConnections) do c:Disconnect() end
	self.muteConnections = {}
	if on then
		local roots = { self.services.Lighting, self.services.Workspace.CurrentCamera }
		for _, root in ipairs(roots) do
			if root then
				for _, d in ipairs(root:GetDescendants()) do self:_muteOne(d) end
				table.insert(self.muteConnections, root.DescendantAdded:Connect(function(d)
					self:_muteOne(d)
				end))
			end
		end
	else
		for object, was in pairs(self.muted) do
			if object.Parent then pcall(function() object.Enabled = was end) end
		end
		self.muted = {}
	end
end

function Effects:_release()
	local session = self.session
	if not session then return end
	self.session = nil
	session.version = session.version + 1
	if session.blurTween then session.blurTween:Cancel() end
	if session.fovBound then
		session.fovBound = false
		pcall(function() self.services.RunService:UnbindFromRenderStep(session.fovBindName) end)
	end
	if session.zoomControlled then
		pcall(function() session.camera.FieldOfView = session.baseFOV end)
	end
	if session.blur then session.blur:Destroy() end
end

-- 🎥 Le FOV n'est plus animé par un Tween : un autre script (dash de la faux,
--    cinématique…) pouvait l'annuler en plein milieu, et le FOV restait coincé
--    (62.6 au lieu de 70) puis se remettait d'un coup après la fermeture.
--    UIFocus écrit lui-même le FOV à CHAQUE image, juste avant le rendu, tant que
--    le menu est ouvert et pendant la fermeture : personne ne peut le couper,
--    l'animation est toujours fluide et finit exactement sur la bonne valeur.
local fovBindSerial = 0
function Effects:_driveFOV(session, to, duration, onDone)
	local cam = session.camera
	session.fovFrom = session.fovLast or cam.FieldOfView
	session.fovTo = to
	session.fovT0 = os.clock()
	session.fovDur = math.max(0, duration)
	session.fovOnDone = onDone
	session.fovFired = false
	if session.fovBound then return end
	fovBindSerial += 1
	session.fovBindName = "UIFocusFOV_" .. fovBindSerial
	session.fovBound = true
	self.services.RunService:BindToRenderStep(session.fovBindName, Enum.RenderPriority.Camera.Value + 5, function()
		if not cam.Parent then return end
		local a = session.fovDur > 0 and math.clamp((os.clock() - session.fovT0) / session.fovDur, 0, 1) or 1
		local e = 1 - (1 - a) * (1 - a)                        -- Quad Out, comme avant
		local v = session.fovFrom + (session.fovTo - session.fovFrom) * e
		if cam.FieldOfView ~= v then cam.FieldOfView = v end
		session.fovLast = v
		if a >= 1 and not session.fovFired then
			session.fovFired = true
			if session.fovOnDone then session.fovOnDone() end
		end
	end)
end

function Effects:_animate()
	-- La partie jouable du guide ne doit ni flouter ni recadrer le monde.
	if self.gameplay or (self.menu and self.menu.CameraEffects == false) then
		self:_release()
		return
	end
	local cam = self.services.Workspace.CurrentCamera
	if not cam then return end
	local session = self.session
	if not session then
		if not self.menu then return end
		-- ✅ le FOV normal appris, pas le FOV de cet instant (qui peut être en plein coup de FOV)
		session = { camera = cam, baseFOV = self.normalFOV or self:_clampFOV(cam.FieldOfView),
			version = 0, zoomControlled = false }
		self.session = session
	end
	session.version = session.version + 1
	local version = session.version
	if session.blurTween then session.blurTween:Cancel() end
	local open = self.menu ~= nil
	local blurConfig, zoomConfig = self.config.Blur, self.config.Zoom
	local pending = 2
	local function done()
		if self.destroyed or self.session ~= session or session.version ~= version then return end
		pending = pending - 1
		if pending == 0 and not self.menu then self:_release() end
	end
	local function animate(object, property, value, duration)
		if duration <= 0 then object[property] = value done() return nil end
		local tw = self.services.TweenService:Create(object,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { [property] = value })
		local connection
		connection = tw.Completed:Connect(function(state)
			connection:Disconnect()
			if state == Enum.PlaybackState.Completed then done() end
		end)
		tw:Play()
		return tw
	end
	local blurSize = 0
	if open and blurConfig.Enabled then
		blurSize = math.clamp(self.menu.BlurSize or blurConfig.Size or 18, 0, 56)
	end
	if blurSize > 0 and not session.blur then
		local b = Instance.new("BlurEffect")
		b.Name = "UIFocusBlur"
		b.Size = 0
		-- Sous la caméra : Settings n'efface pas ce flou en désactivant
		-- les PostFX du décor dans Lighting.
		b.Parent = cam
		session.blur = b
	end
	if session.blur then
		session.blurTween = animate(session.blur, "Size", blurSize,
			math.max(0, (open and blurConfig.OpenTime or blurConfig.CloseTime) or 0))
	else done() end

	local fov = session.baseFOV
	if open and zoomConfig.Enabled then
		session.zoomControlled = true
		local offset = self.menu.FOVOffset
		if offset == nil then offset = zoomConfig.FOVOffset or -10 end
		fov = self:_clampFOV(session.baseFOV + offset)
	end
	if session.zoomControlled then
		self:_driveFOV(session, fov,
			math.max(0, (open and zoomConfig.OpenTime or zoomConfig.CloseTime) or 0), done)
	else done() end

	-- 🩹 Fermeture : on ne dépend plus de la fin « normale » de l'animation. Si un
	--    autre script l'a coupée (dash, cinématique…), on termine quand même :
	--    FOV normal + flou retiré, à l'heure prévue.
	if not open then
		local wait = math.max(blurConfig.CloseTime or 0, zoomConfig.CloseTime or 0) + 0.1
		task.delay(wait, function()
			if self.destroyed or self.menu or self.session ~= session or session.version ~= version then return end
			self:_release()
		end)
	end
end

function Effects:SetGameplay(on)
	if self.destroyed or self.gameplay == on then return end
	self.gameplay = on
	self:_muteBlurs(on)
	-- en entrant dans la phase jouable : FOV normal tout de suite
	if on then
		local cam = self.services.Workspace.CurrentCamera
		if cam and self.normalFOV and not self.session then
			pcall(function() cam.FieldOfView = self.normalFOV end)
		end
	end
	self:_animate()
end

function Effects:Set(menu)
	if self.destroyed then return end
	local wasOpen = self.menu ~= nil
	self.menu = menu
	if menu and not wasOpen then self:_core(true)
	elseif not menu and wasOpen then self:_core(false) end
	self:_animate()
end

function Effects:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.cameraConnection:Disconnect()
	if self.fovConnection then self.fovConnection:Disconnect() end
	self.menu = nil
	self:_core(false)
	self:_release()
	self.gameplay = false
	self:_muteBlurs(false)
end

return Effects
