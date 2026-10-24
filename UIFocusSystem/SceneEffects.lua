-- Flou et caméra : le FOV d'origine est conservé pendant toute la session,
-- y compris si un menu se rouvre pendant l'animation de fermeture.
local Effects = {}
Effects.__index = Effects

function Effects.new(config, services)
	local self = setmetatable({
		config = config, services = services, menu = nil,
		session = nil, core = {}, destroyed = false, gameplay = false,
	}, Effects)
	self.cameraConnection = services.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:_release()
		if self.menu then self:_animate() end
	end)
	return self
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

function Effects:_release()
	local session = self.session
	if not session then return end
	self.session = nil
	session.version = session.version + 1
	if session.blurTween then session.blurTween:Cancel() end
	if session.fovTween then session.fovTween:Cancel() end
	if session.zoomControlled then
		pcall(function() session.camera.FieldOfView = session.baseFOV end)
	end
	if session.blur then session.blur:Destroy() end
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
		session = { camera = cam, baseFOV = cam.FieldOfView, version = 0, zoomControlled = false }
		self.session = session
	end
	session.version = session.version + 1
	local version = session.version
	if session.blurTween then session.blurTween:Cancel() end
	if session.fovTween then session.fovTween:Cancel() end
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
		local minimum = math.clamp(zoomConfig.MinFOV or 20, 1, 120)
		local maximum = math.clamp(zoomConfig.MaxFOV or 110, minimum, 120)
		fov = math.clamp(session.baseFOV + offset, minimum, maximum)
	end
	if session.zoomControlled then
		session.fovTween = animate(cam, "FieldOfView", fov,
			math.max(0, (open and zoomConfig.OpenTime or zoomConfig.CloseTime) or 0))
	else done() end
end

function Effects:SetGameplay(on)
	if self.destroyed or self.gameplay == on then return end
	self.gameplay = on
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
	self.menu = nil
	self:_core(false)
	self:_release()
end

return Effects
