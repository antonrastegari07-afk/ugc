-- Un seul gestionnaire de visibilité pour toutes les fenêtres.
-- Les signaux enregistrent les demandes ; ils ne réécrivent jamais la
-- propriété. Les écritures ont lieu au plus une fois par objet par image.
-- Cela évite les boucles de signaux entre les scripts d'interface.
--
-- 🔔 NOTIFICATIONS : une fenêtre ouverte (shop, settings…) cache les autres
--    interfaces, SAUF les notifications, qui restent visibles et passent
--    au-dessus de la fenêtre :
--      1. les noms listés dans C.NotificationScreenGuis ;
--      2. les noms qui contiennent un mot de C.NotificationNamePatterns
--         (notif, toast, popup, error…) → les futures notifs sont couvertes ;
--      3. toute interface créée ou allumée PENDANT qu'une fenêtre est ouverte
--         (ce qui apparaît à ce moment est forcément une réaction : achat
--         réussi, récompense, message d'event…), sauf les fenêtres du focus.
--    Leur DisplayOrder est remonté juste au-dessus de la fenêtre ouverte, puis
--    remis comme avant à la fermeture.
local Engine = {}
Engine.__index = Engine

function Engine.new(playerGui, ownGui, config, changed)
	local self = setmetatable({
		playerGui = playerGui, ownGui = ownGui, config = config,
		changed = changed, fields = {}, screens = {}, candidates = {},
		active = nil, serial = 0, nextDiscovery = 0, structureDirty = true,
		stateDirty = true, trackedScreens = {}, screenSet = {},
		connections = {}, destroyed = false,
		late = {}, wasEnabled = {}, raised = {}, notifCache = {},
	}, Engine)
	-- ⏳ Au chargement, les interfaces du jeu (copiées de StarterGui, armes, HUD…)
	--    arrivent parfois APRÈS l'ouverture du How to Play : elles ne sont pas des
	--    notifications. La règle 3 ne s'applique donc ni pendant les premières
	--    secondes, ni aux interfaces qui existent dans StarterGui.
	self.startedAt = os.clock()
	self.starterNames = {}
	pcall(function()
		for _, g in ipairs(game:GetService("StarterGui"):GetChildren()) do
			if g:IsA("ScreenGui") then self.starterNames[g.Name] = true end
		end
	end)
	self.notifNames = {}
	for _, name in ipairs(config.NotificationScreenGuis or {}) do self.notifNames[name] = true end
	local function dirty() self.structureDirty = true end
	table.insert(self.connections, playerGui.DescendantAdded:Connect(function(object)
		self:_trackScreen(object)
		dirty()
	end))
	table.insert(self.connections, playerGui.DescendantRemoving:Connect(dirty))
	-- Un seul parcours complet à l'installation. Ensuite les ajouts/retraits
	-- mettent à jour le registre ; aucun GetDescendants périodique.
	for _, object in ipairs(playerGui:GetDescendants()) do self:_trackScreen(object) end
	return self
end

function Engine:_trackScreen(object)
	if object ~= self.ownGui and object:IsA("ScreenGui") and not self.screenSet[object] then
		self.screenSet[object] = true
		table.insert(self.trackedScreens, object)
		-- 🔔 créée pendant qu'une fenêtre est ouverte → notification (règle 3)
		if self.active and self:_lateAllowed(object) then self.late[object] = true end
	end
end

-- 🔔 Règle 3 autorisée pour cette interface ? (pas au chargement, pas une interface de StarterGui)
function Engine:_lateAllowed(gui)
	if os.clock() - self.startedAt < (self.config.LateGraceSeconds or 30) then return false end
	if self.starterNames[gui.Name] then return false end
	return true
end

-- 🔔 Notification par son nom (règles 1 et 2)
function Engine:_isNotifName(gui)
	local name = gui.Name
	local cached = self.notifCache[name]
	if cached ~= nil then return cached end
	local result = self.notifNames[name] == true
	if not result then
		local lower = string.lower(name)
		for _, word in ipairs(self.config.NotificationNamePatterns or {}) do
			if string.find(lower, string.lower(word), 1, true) then result = true break end
		end
	end
	self.notifCache[name] = result
	return result
end

-- 🔔 DisplayOrder : la notification passe au-dessus de la fenêtre ouverte, puis revient
function Engine:_raise(gui, top)
	if gui.DisplayOrder <= top then
		local r = self.raised[gui]
		if not r then r = { original = gui.DisplayOrder } self.raised[gui] = r end
		r.set = top + 1
		gui.DisplayOrder = top + 1
	end
end
function Engine:_lower(gui)
	local r = self.raised[gui]
	if not r then return end
	self.raised[gui] = nil
	-- remis seulement si personne ne l'a changé entre-temps
	if gui.Parent and gui.DisplayOrder == r.set then gui.DisplayOrder = r.original end
end

function Engine:_field(object, property)
	local fields = self.fields[object]
	if not fields then fields = {} self.fields[object] = fields end
	if fields[property] then return fields[property] end
	local initial = object[property]
	local record = { object = object, property = property, wanted = initial, applied = initial }
	fields[property] = record
	record.connection = object:GetPropertyChangedSignal(property):Connect(function()
		-- Fonctionne avec les signaux Roblox immédiats ET différés.
		local current = object[property]
		if current ~= record.applied then
			record.wanted, record.applied = current, current
			self.stateDirty = true
		end
	end)
	return record
end

function Engine:_read(object, property)
	local r = self:_field(object, property)
	local actual = object[property]
	if actual ~= r.applied then
		r.wanted, r.applied = actual, actual
		self.stateDirty = true
	end
	return r.wanted
end

function Engine:_write(r, value)
	if r.object[r.property] ~= value then
		r.applied = value
		r.object[r.property] = value
	else
		r.applied = value
	end
end

function Engine:_discover()
	local previous = self.candidates
	local candidates, screens = {}, {}
	for _, object in ipairs(self.trackedScreens) do
		if object:IsDescendantOf(self.playerGui) then
			table.insert(screens, object)
			self:_field(object, "Enabled")
			for _, definition in ipairs(self.config.Menus) do
				if definition.Enabled ~= false and definition.ScreenGui == object.Name then
					local target = object
					if definition.Trigger == "Visible" then
						for _, name in ipairs(definition.Path or {}) do
							target = target and target:FindFirstChild(name)
						end
						if target and not target:IsA("GuiObject") then target = nil end
					elseif definition.Trigger ~= "Enabled" then
						target = nil
					end
					if target then
						local candidate
						for _, old in ipairs(previous) do
							if old.definition == definition and old.target == target and old.gui == object then
								candidate = old
								break
							end
						end
						candidate = candidate or { gui = object, target = target, definition = definition, wasOpen = false, order = 0 }
						table.insert(candidates, candidate)
					end
				end
			end
		end
	end
	self.trackedScreens = screens
	self.screenSet = {}
	for _, gui in ipairs(screens) do self.screenSet[gui] = true end
	self.screens, self.candidates = screens, candidates
end

function Engine:_isOpen(candidate)
	if not self:_read(candidate.gui, "Enabled") then return false end
	local object = candidate.target
	while object and object ~= self.playerGui do
		if object:IsA("GuiObject") and not self:_read(object, "Visible") then return false end
		if object:IsA("ScreenGui") and not self:_read(object, "Enabled") then return false end
		object = object.Parent
	end
	return object == self.playerGui
end

function Engine:_maskTree(object, mask)
	if object:IsA("GuiObject") then
		mask[self:_field(object, "Visible")] = true
	elseif not object:IsA("ScreenGui") then
		for _, child in ipairs(object:GetChildren()) do self:_maskTree(child, mask) end
	end
end

function Engine:_maskBranches(candidate, mask)
	local branch = candidate.target
	while branch and branch ~= candidate.gui do
		local parent = branch.Parent
		if not parent then break end
		for _, sibling in ipairs(parent:GetChildren()) do
			if sibling ~= branch then
				-- Les Folder ne sont pas visuels : chercher leurs racines GUI.
				self:_maskTree(sibling, mask)
			end
		end
		branch = parent
	end
end

function Engine:Step(now)
	if self.destroyed then return end
	-- Au repos : un simple contrôle, sans reparcourir les états à chaque image.
	if not self.stateDirty and not self.structureDirty and now < self.nextDiscovery then return end
	self.stateDirty = false
	-- Enregistrer aussi les changements arrivés avant leurs signaux différés.
	for object, fields in pairs(self.fields) do
		if not object:IsDescendantOf(self.playerGui) then
			for _, r in pairs(fields) do
				r.connection:Disconnect()
				if object.Parent then pcall(function() self:_write(r, r.wanted) end) end
			end
			self.fields[object] = nil
		else
			for _, r in pairs(fields) do self:_read(object, r.property) end
		end
	end
	if self.structureDirty or now >= self.nextDiscovery then
		self.structureDirty = false
		self.nextDiscovery = now + math.max(0.05, self.config.RefreshInterval or 0.25)
		self:_discover()
	end

	local active
	for _, candidate in ipairs(self.candidates) do
		local opened = self.config.Enabled ~= false and self:_isOpen(candidate)
		if opened and not candidate.wasOpen then
			self.serial = self.serial + 1
			candidate.order = self.serial
		end
		candidate.wasOpen = opened
		if opened then
			local priority = candidate.definition.Priority or 0
			local other = active and (active.definition.Priority or 0) or 0
			if not active or priority > other or (priority == other and candidate.order > active.order) then
				active = candidate
			end
		end
	end

	-- 🎥 Fenêtre qui décide du flou / zoom. D'habitude la fenêtre active ; mais une
	--    fenêtre sans effets caméra (le Rookie Guide) peut les prêter à une fenêtre
	--    ouverte par-dessus, listée dans CameraEffectsFrom (ex. la boutique UGC).
	local effect = active and active.definition or nil
	if active and active.definition.CameraEffects == false and active.definition.CameraEffectsFrom then
		local allowed = {}
		for _, id in ipairs(active.definition.CameraEffectsFrom) do allowed[id] = true end
		local best
		for _, candidate in ipairs(self.candidates) do
			if candidate ~= active and candidate.wasOpen and allowed[candidate.definition.Id]
				and (not best or candidate.order > best.order) then
				best = candidate
			end
		end
		if best then
			effect = best.definition
			-- BorrowedFOVOffset : la fenêtre prêtée garde son flou mais avec CE zoom
			-- (0 = aucun changement de FOV pendant le Rookie Guide)
			local borrowedOffset = active.definition.BorrowedFOVOffset
			if borrowedOffset ~= nil then
				best.borrowed = best.borrowed or setmetatable({ FOVOffset = borrowedOffset },
				{ __index = best.definition })
				effect = best.borrowed
			end
		end
	end

	-- 🔔 règle 3 : interface allumée pendant qu'une fenêtre est ouverte
	local menuGui = {}
	for _, candidate in ipairs(self.candidates) do menuGui[candidate.gui] = true end
	for _, gui in ipairs(self.screens) do
		local wantedOn = self:_field(gui, "Enabled").wanted
		if not wantedOn then
			self.late[gui] = nil
		elseif self.wasEnabled[gui] == false and (active or self.active) and self:_lateAllowed(gui) then
			self.late[gui] = true
		end
		self.wasEnabled[gui] = wantedOn
	end
	for gui in pairs(self.late) do
		if not gui.Parent or menuGui[gui] then self.late[gui] = nil end
	end
	if not active then table.clear(self.late) end

	local mask = {}
	local notifs = {}
	if active then
		local keep = {}
		if not active.definition.ReplaceKeepScreenGuis then
			for _, name in ipairs(self.config.KeepScreenGuis or {}) do keep[name] = true end
		end
		for _, name in ipairs(active.definition.KeepScreenGuis or {}) do keep[name] = true end
		for _, name in ipairs(self.config.AlwaysKeepScreenGuis or {}) do keep[name] = true end
		local hideContents = {}
		for _, candidate in ipairs(self.candidates) do
			if candidate.definition.HideMode == "Contents" then hideContents[candidate.gui] = true end
		end
		if self.config.HideOtherScreenGuis ~= false then
			for _, gui in ipairs(self.screens) do
				local isNotif = not menuGui[gui] and (self.late[gui] or self:_isNotifName(gui))
				if isNotif then notifs[gui] = true end
				if gui ~= active.gui and not keep[gui.Name] and not isNotif then
					if hideContents[gui] then
						for _, child in ipairs(gui:GetChildren()) do self:_maskTree(child, mask) end
					else
						mask[self:_field(gui, "Enabled")] = true
					end
				end
			end
		end
		if self.config.HideLaunchersInActiveGui ~= false and not active.definition.KeepWholeGui then
			self:_maskBranches(active, mask)
		end
	end
	for _, fields in pairs(self.fields) do
		for _, r in pairs(fields) do
			local value = r.wanted
			if mask[r] then value = false end
			self:_write(r, value)
		end
	end
	-- 🔔 notifications au-dessus de la fenêtre ouverte
	if active then
		local top = active.gui.DisplayOrder
		for gui in pairs(notifs) do pcall(self._raise, self, gui, top) end
	end
	for gui in pairs(self.raised) do
		if not notifs[gui] then pcall(self._lower, self, gui) end
	end
	if self.active ~= active or self.effect ~= effect then
		self.active, self.effect = active, effect
		if self.changed then self.changed(active and active.definition or nil, effect) end
	end
end

function Engine:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	for object, fields in pairs(self.fields) do
		for _, r in pairs(fields) do
			r.connection:Disconnect()
			if object.Parent then
				local actual = object[r.property]
				if actual ~= r.applied then r.wanted = actual end
				pcall(function() self:_write(r, r.wanted) end)
			end
		end
	end
	for gui in pairs(self.raised) do pcall(self._lower, self, gui) end
	self.late, self.raised = {}, {}
	self.fields, self.candidates, self.screens = {}, {}, {}
	self.trackedScreens, self.screenSet = {}, {}
	self.active, self.effect = nil, nil
end

return Engine