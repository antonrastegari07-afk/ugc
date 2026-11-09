--[[
	ServerBrowserDisplay (Client) — v5.2 (chargement tardif + restauration GUI)
	➜ À placer dans : StarterPlayer > StarterPlayerScripts  (LocalScript)
	➜ Supprime l'ancien script qui était DANS le model (sinon double prompt).
	Positions des displays : ReplicatedStorage/ServerBrowserAnchors (CFrameValue).
	  • Le script serveur doit publier ces positions ; un tag seul ne suffit pas.
	  • Les prompts locaux restent disponibles lorsque la zone se décharge.
	GUI attendu (1 seul, dans PlayerGui) :
	  ScreenGui  "Servers"
	    └ Frame "ShopFrame"
	        └ ScrollingFrame "ScrollingFrame"
	            └ Frame "Entrydemo"   (gabarit — cloné par serveur)
	NOUVEAU v5.1 : message "No other servers available" au lieu d'une page blanche.
--]]
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local Workspace         = game:GetService("Workspace")


-- Le menu et ses prompts ne dépendent pas du chargement de MapConfig.
local MapConfig = { Maps = {}, getByKey = function() return nil end }
local loadedMapModule
local function loadMapConfig(module)
	if not module or not module:IsA("ModuleScript") or loadedMapModule == module then return end
	loadedMapModule = module
	task.spawn(function()
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and loadedMapModule == module then
			MapConfig = result
		elseif not ok then warn("[ServerBrowser] MapConfig : " .. tostring(result)) end
	end)
end
ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "MapConfig" then loadMapConfig(child) end
end)
loadMapConfig(ReplicatedStorage:FindFirstChild("MapConfig"))

local localPlayer = Players.LocalPlayer
local playerGui   = localPlayer:WaitForChild("PlayerGui")
-- Une seule copie de cette version doit gérer l'interface.
local guard = playerGui:FindFirstChild("ServerBrowserController")
if guard and guard:IsA("ObjectValue") and guard.Value and guard.Value.Parent then return end
if guard then guard:Destroy() end
guard = Instance.new("ObjectValue")
guard.Name = "ServerBrowserController"
guard.Value = script
guard.Parent = playerGui

local isMobile    = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Remotes (non-bloquant : le menu s'affiche même sans serveur)
local getServersFn    = ReplicatedStorage:FindFirstChild("GetArenaServers")
local joinServerEvent = ReplicatedStorage:FindFirstChild("JoinArenaServer")
local joinFailedEvent = ReplicatedStorage:FindFirstChild("ArenaJoinFailed")

--========================================================
-- 🔧 RÉGLAGES
--========================================================
local FORCE_FAKE      = false  -- true = TOUJOURS la démo (test pur de l'UI)
local FAKE_WHEN_EMPTY = false  -- true = démo si la vraie liste est vide (Studio / 1 seul serveur)
local UNIFORM_SCALE   = true
local REF_W, REF_H    = 1100, 750
local MIN_SCALE       = 1.00
local MAX_SCALE       = 1.00
local USE_OVERLAY     = true
local AUTO_REFRESH    = 10
local MAX_PFP         = 6
local PFP_PADDING     = 4

--========================================================
-- 🧪 DONNÉES DÉMO
--========================================================
local FAKE_IDS = { localPlayer.UserId, 1, 2, 3, 156, 261 }
local function fakePlayers(count)
	local t = {}
	for i = 1, count do
		t[i] = { id = FAKE_IDS[((i - 1) % #FAKE_IDS) + 1], name = "Player" .. i }
	end
	return t
end
local function makeFakeServers()
	local presets = { 6, 3, 8, 1, 4, 2, 5, 7, 2, 6, 3, 8, 1, 4 }
	local mapKeys = {}
	for _, m in ipairs(MapConfig.Maps or {}) do table.insert(mapKeys, m.key) end
	local servers = {}
	for i, arena in ipairs(presets) do
		servers[i] = {
			fake    = true,
			jobId   = string.format("demo%d-aaaaaaaa", i),
			total   = arena + math.random(2, 9),
			arena   = arena,
			region  = ({"US","CA","FR","DE","BR","GB"})[((i - 1) % 6) + 1],
			map     = mapKeys[((i - 1) % math.max(#mapKeys, 1)) + 1],
			players = fakePlayers(arena),
		}
	end
	return servers
end

--========================================================
-- 🌫️ BLUR (frosted glass — 1 seul par joueur)
--========================================================
local blur = Lighting:FindFirstChild("ServerBrowserBlur")
if not blur then
	blur = Instance.new("BlurEffect")
	blur.Name    = "ServerBrowserBlur"
	blur.Enabled = true
	blur.Size    = 0
	blur.Parent  = Lighting
end

--========================================================
-- OVERLAY (curseur libre + bloque le tir + clic-dehors)
--========================================================
local overlayGui, overlayBtn
if USE_OVERLAY then
	overlayGui = Instance.new("ScreenGui")
	overlayGui.Name           = "ServerBrowserOverlay"
	overlayGui.ResetOnSpawn   = false
	overlayGui.IgnoreGuiInset = true
	overlayGui.DisplayOrder    = -1
	overlayGui.Enabled         = false
	overlayGui.Parent          = playerGui

	overlayBtn = Instance.new("TextButton")
	overlayBtn.Size                   = UDim2.fromScale(1, 1)
	overlayBtn.BackgroundTransparency = 1
	overlayBtn.AutoButtonColor        = false
	overlayBtn.Modal                  = true
	overlayBtn.Text                   = ""
	overlayBtn.Parent                 = overlayGui
end

--========================================================
-- 📐 RÉFÉRENCES UI (ton GUI) + responsive
--========================================================
local activeGui, shopFrame, scrolling, template, menuScale
local isOpen, autoToken = false, 0
local uiGeneration, animationToken = 0, 0
local pendingOpen = false
local setupGui, trySetupGui, close
local guiConnections = {}
local joinResets = {}
local function resetJoins()
	for _, reset in ipairs(joinResets) do reset() end
end
local function uiReady()
	return activeGui and activeGui.Parent == playerGui
		and shopFrame and shopFrame:IsDescendantOf(activeGui)
		and scrolling and scrolling:IsDescendantOf(shopFrame)
		and template ~= nil
end
local function track(connection)
	table.insert(guiConnections, connection)
	return connection
end
local responsiveFactor, animatingScale = 1, false

local function getViewport()
	local cam = Workspace.CurrentCamera
	if cam and cam.ViewportSize.Y > 1 then return cam.ViewportSize end
	return Vector2.new(1280, 720)
end
local function computeFactor()
	if not UNIFORM_SCALE then return 1 end
	local vp = getViewport()
	local s = math.min(vp.X / REF_W, vp.Y / REF_H)
	return math.clamp(s, MIN_SCALE, MAX_SCALE)
end
local function applyScale()
	responsiveFactor = computeFactor()
	if menuScale and not animatingScale then
		menuScale.Scale = responsiveFactor
	end
end

local camConn
local function hookCamera()
	local cam = Workspace.CurrentCamera
	if cam then
		if camConn then camConn:Disconnect() end
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end
end

--========================================================
-- CARTE (clone de Entrydemo)
--========================================================
local function shortCode(jobId)
	local clean = (jobId or ""):gsub("-", "")
	return clean:sub(1, 8):upper()
end

local function trySet(entry, names, text)
	for _, n in ipairs(names) do
		local lbl = entry:FindFirstChild(n, true)
		if lbl and lbl:IsA("TextLabel") then lbl.Text = text; return true end
	end
	return false
end

local function fillAvatars(container, players, arena)
	for _, ch in ipairs(container:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end
	container.BackgroundTransparency = 1
	container.BorderSizePixel        = 0
	for _, d in ipairs(container:GetChildren()) do
		if d:IsA("UIStroke") then d.Enabled = false end
	end

	local lay = container:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
	lay.FillDirection       = Enum.FillDirection.Horizontal
	lay.Padding             = UDim.new(0, PFP_PADDING)
	lay.VerticalAlignment   = Enum.VerticalAlignment.Center
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Left
	lay.SortOrder           = Enum.SortOrder.LayoutOrder
	lay.Parent              = container

	local shown, avatarFrames = 0, {}
	for i, p in ipairs(players) do
		if shown >= MAX_PFP then break end
		shown += 1
		local af = Instance.new("Frame")
		af.Name             = "PFP"
		af.BackgroundColor3 = Color3.fromRGB(70, 75, 86)
		af.BorderSizePixel  = 0
		af.LayoutOrder      = i
		af.Size             = UDim2.fromScale(1, 1)
		af.Parent           = container
		Instance.new("UICorner", af).CornerRadius = UDim.new(1, 0)
		local ring = Instance.new("UIStroke", af)
		ring.Color = Color3.fromRGB(255,255,255); ring.Thickness = 1.5; ring.Transparency = 0.35
		local img = Instance.new("ImageLabel")
		img.Size                   = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.Image                  = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", p.id)
		img.Parent                 = af
		Instance.new("UICorner", img).CornerRadius = UDim.new(1, 0)
		avatarFrames[#avatarFrames+1] = af
	end

	local moreLabel
	if arena > shown then
		moreLabel = Instance.new("TextLabel")
		moreLabel.Name                 = "More"
		moreLabel.BackgroundTransparency = 1
		moreLabel.Text                 = "+" .. (arena - shown)
		moreLabel.Font                 = Enum.Font.GothamBold
		moreLabel.TextColor3           = Color3.fromRGB(120, 128, 142)
		moreLabel.TextScaled           = true
		moreLabel.LayoutOrder          = 999
		moreLabel.Size                 = UDim2.fromScale(1, 1)
		moreLabel.Parent               = container
	end

	local function resize()
		local h = container.AbsoluteSize.Y
		if h < 2 then return end
		local side = UDim2.fromOffset(h, h)
		for _, af in ipairs(avatarFrames) do af.Size = side end
		if moreLabel then moreLabel.Size = UDim2.fromOffset(math.floor(h * 1.4), h) end
	end

	task.spawn(function()
		local guard = 0
		while container.Parent and container.AbsoluteSize.Y < 2 and guard < 180 do
			task.wait(); guard += 1
		end
		if container.AbsoluteSize.Y < 2 then
			for _, af in ipairs(avatarFrames) do af.Size = UDim2.fromOffset(28, 28) end
			if moreLabel then moreLabel.Size = UDim2.fromOffset(40, 28) end
			warn("[ServerBrowser] 'Frameexemplepositionprofils' a une hauteur ~0 → avatars en taille fixe.")
		else
			resize()
		end
	end)
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
end

local function buildCard(data, order)
	local arena   = data.arena or 0
	local total   = data.total or 0
	local players = data.players or {}

	local entry = template:Clone()
	entry.Name = "ServerCard"
	entry:SetAttribute("_serverCard", true)
	entry.LayoutOrder = order
	entry.Visible = false

	local countLabel = entry:FindFirstChild("Count", true)
	if countLabel and countLabel:IsA("TextLabel") then
		countLabel.Text = tostring(arena)
	end

	local pfpAnchor = entry:FindFirstChild("Frameexemplepositionprofils", true)
	if not pfpAnchor then
		for _, d in ipairs(entry:GetDescendants()) do
			if d:IsA("GuiObject") then
				local n = d.Name:lower()
				if n:find("profil") or n:find("pfp") or n:find("avatar") then
					pfpAnchor = d; break
				end
			end
		end
	end
	if pfpAnchor then
		fillAvatars(pfpAnchor, players, arena)
	else
		warn("[ServerBrowser] ⚠️ Cadre des avatars introuvable dans Entrydemo.")
	end

	local idLabel = entry:FindFirstChild("ServerID", true)
	if idLabel and idLabel:IsA("TextLabel") then
		idLabel.Text = "Server " .. shortCode(data.jobId)
	end

	local regionLabel = entry:FindFirstChild("Region", true)
	if regionLabel and regionLabel:IsA("TextLabel") then
		regionLabel.Text = data.region or "…"
	end

	local mapInfo
	if data.map and type(MapConfig.getByKey) == "function" then
		local ok, result = pcall(MapConfig.getByKey, data.map)
		if ok and type(result) == "table" then mapInfo = result end
	end
	local mapImage = entry:FindFirstChild("MapImage", true)
	if mapImage and mapImage:IsA("ImageLabel") then
		mapImage.Image = (mapInfo and mapInfo.Image) or ""
	end
	local mapNameLbl = entry:FindFirstChild("MapName", true)
	if mapNameLbl and mapNameLbl:IsA("TextLabel") then
		mapNameLbl.Text = (mapInfo and mapInfo.Name) or (data.map or "?")
	end

	trySet(entry, {"TotalCount","Total","InServer","ServerCount","Totalcount"}, total .. " in server")

	local joinBtn = entry:FindFirstChild("Joinbutton", true)
	if joinBtn and joinBtn:IsA("GuiButton") then
		local press = joinBtn:FindFirstChild("PressScale")
		if not press then press = Instance.new("UIScale"); press.Name = "PressScale"; press.Parent = joinBtn end
		joinBtn.MouseButton1Down:Connect(function() TweenService:Create(press, TweenInfo.new(0.08), {Scale = 0.93}):Play() end)
		joinBtn.MouseButton1Up:Connect(function()   TweenService:Create(press, TweenInfo.new(0.12, Enum.EasingStyle.Back), {Scale = 1}):Play() end)
		joinBtn.MouseLeave:Connect(function()       TweenService:Create(press, TweenInfo.new(0.12), {Scale = 1}):Play() end)

		local joining = false
		local originalText = joinBtn:IsA("TextButton") and joinBtn.Text
		local joinAttempt = 0
		local function resetJoin()
			joining = false
			joinAttempt += 1
			if joinBtn.Parent and originalText then joinBtn.Text = originalText end
		end
		table.insert(joinResets, resetJoin)
		joinBtn.Activated:Connect(function()
			if joining then return end
			if data.fake then
				TweenService:Create(press, TweenInfo.new(0.08), {Scale = 0.9}):Play()
				task.delay(0.1, function() if press then TweenService:Create(press, TweenInfo.new(0.12, Enum.EasingStyle.Back), {Scale = 1}):Play() end end)
				return
			end
			joinServerEvent = ReplicatedStorage:FindFirstChild("JoinArenaServer")
			if not joinServerEvent or not joinServerEvent:IsA("RemoteEvent") then
				warn("[ServerBrowser] JoinArenaServer indisponible (serveur non installé ?)")
				return
			end
			joining = true
			if joinBtn:IsA("TextButton") then joinBtn.Text = "..." end
			joinAttempt += 1
			local attempt = joinAttempt
			local ok, err = pcall(function() joinServerEvent:FireServer(data.jobId) end)
			if not ok then resetJoin(); warn("[ServerBrowser] Join : " .. tostring(err)); return end
			task.delay(15, function()
				if joining and attempt == joinAttempt then resetJoin() end
			end)
		end)
	end

	return entry
end

--========================================================
-- RENDER / REFRESH  (pagination : 10 par 10 + bouton "Load More")
--========================================================
local PAGE_SIZE     = 10
local currentCards  = {}
local sortedList    = {}
local renderedCount = 0
local loadMoreBtn   = nil
local emptyLabel    = nil   -- 🆕 message quand aucun serveur

local function destroyLoadMore()
	if loadMoreBtn then loadMoreBtn:Destroy(); loadMoreBtn = nil end
end

local function destroyEmpty()   -- 🆕
	if emptyLabel then emptyLabel:Destroy(); emptyLabel = nil end
end

local function clearCards()
	resetJoins()
	table.clear(joinResets)
	sortedList = {}
	destroyEmpty()          -- 🆕
	destroyLoadMore()
	for _, c in ipairs(currentCards) do c:Destroy() end
	table.clear(currentCards)
	renderedCount = 0
	if scrolling then
		for _, ch in ipairs(scrolling:GetChildren()) do
			if ch:GetAttribute("_serverCard") or ch:GetAttribute("_loadMore") then ch:Destroy() end
		end
	end
end

local appendPage -- forward declaration

local function buildLoadMore()
	destroyLoadMore()
	local remaining = #sortedList - renderedCount
	if remaining <= 0 then return end
	local btn = Instance.new("TextButton")
	btn:SetAttribute("_loadMore", true)
	btn.Name = "LoadMoreButton"; btn.LayoutOrder = 1000000
	btn.Size = UDim2.new(1, -20, 0, 44); btn.BackgroundColor3 = Color3.fromRGB(46, 50, 64)
	btn.AutoButtonColor = false; btn.Font = Enum.Font.FredokaOne
	btn.Text = string.format("Load More  (%d)", remaining)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.TextSize = 20; btn.Parent = scrolling
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke", btn)
	st.Color = Color3.fromRGB(120, 128, 150); st.Thickness = 1.5; st.Transparency = 0.4
	btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(60, 66, 84)}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(46, 50, 64)}):Play() end)
	btn.Activated:Connect(function() appendPage(true) end)
	loadMoreBtn = btn
end

appendPage = function(animate)
	if not scrolling or not template then return end
	destroyLoadMore()
	local startIdx = renderedCount + 1
	local endIdx   = math.min(renderedCount + PAGE_SIZE, #sortedList)
	for i = startIdx, endIdx do
		local card = buildCard(sortedList[i], i)
		card.Parent = scrolling
		table.insert(currentCards, card)
		if animate then
			task.delay(0.035 * (i - startIdx), function()
				if card.Parent then card.Visible = true end
			end)
		else
			card.Visible = true
		end
	end
	renderedCount = endIdx
	buildLoadMore()
end

-- 🆕 affiche un message centré quand la liste est vide (au lieu d'une page blanche)
local function showEmptyState()
	destroyEmpty()
	emptyLabel = Instance.new("TextLabel")
	emptyLabel:SetAttribute("_serverCard", true) -- purgé par clearCards
	emptyLabel.Name                 = "EmptyState"
	emptyLabel.LayoutOrder          = 1
	emptyLabel.Size                 = UDim2.new(1, -20, 0, 90)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Font                 = Enum.Font.FredokaOne
	emptyLabel.TextColor3           = Color3.fromRGB(150, 156, 170)
	emptyLabel.TextWrapped          = true
	emptyLabel.TextScaled           = true
	emptyLabel.Text                 = "No other servers available yet"
	emptyLabel.Parent               = scrolling
	local con = Instance.new("UITextSizeConstraint", emptyLabel)
	con.MaxTextSize = 22
end

local function render(list, animate)
	if not scrolling or not template then return end
	local keepCount = renderedCount
	clearCards()
	if #list == 0 then
		showEmptyState()   -- 🆕 plus de page blanche
		return
	end
	table.sort(list, function(a, b)
		local aArena, bArena = a.arena or 0, b.arena or 0
		if aArena ~= bArena then return aArena > bArena end
		return (a.total or 0) > (b.total or 0)
	end)
	sortedList = list
	-- 🩹 l'actualisation auto (toutes les 10 s) repartait à 10 serveurs : ceux chargés avec
	--    « Load More » disparaissaient. On réaffiche autant de serveurs qu'avant, sans bouger
	--    la position de défilement.
	local keep = (not animate) and keepCount or 0
	local keepPos = scrolling.CanvasPosition
	appendPage(animate)
	while renderedCount < math.min(keep, #sortedList) do appendPage(false) end
	if not animate then scrolling.CanvasPosition = keepPos end
end

-- Une requête en cours par RemoteFunction : pas d'accumulation si le serveur ne répond pas.
local inFlight = setmetatable({}, { __mode = "k" })
local lastListSig = nil   -- dernière liste affichée (pour ne pas tout reconstruire si rien n'a changé)
local function showStatus(message)
	if not uiReady() then return end
	if #currentCards == 0 then showEmptyState(); emptyLabel.Text = message end
end
local function normalizeList(raw)
	local list = {}
	for _, data in ipairs(raw) do
		if type(data) == "table" and type(data.jobId) == "string" then
			local item = table.clone(data)
			local function count(value)
				value = tonumber(value) or 0
				if value ~= value or math.abs(value) == math.huge then return 0 end
				return math.max(0, math.floor(value))
			end
			item.arena, item.total = count(data.arena), count(data.total)
			item.region = type(data.region) == "string" and data.region or "…"
			item.map = type(data.map) == "string" and data.map or nil
			item.players = {}
			if type(data.players) == "table" then
				for _, p in ipairs(data.players) do
					if type(p) == "table" and count(p.id) > 0 then
						table.insert(item.players, { id = count(p.id) })
					end
					if #item.players >= MAX_PFP then break end
				end
			end
			table.insert(list, item)
		end
	end
	return list
end
local function refresh(animate)
	if not isOpen or not uiReady() then return end
	if FORCE_FAKE then render(makeFakeServers(), animate); return end
	getServersFn = ReplicatedStorage:FindFirstChild("GetArenaServers")
	local remote = getServersFn
	if not remote or not remote:IsA("RemoteFunction") then
		showStatus("Server list unavailable. Retrying...")
		return
	end
	if inFlight[remote] then
		showStatus("Waiting for the server list...")
		return
	end
	local request = { gui = activeGui, generation = uiGeneration, session = autoToken }
	inFlight[remote] = request
	showStatus("Loading servers...")
	local function currentRequest()
		return isOpen and uiReady() and activeGui == request.gui
			and uiGeneration == request.generation and autoToken == request.session
	end
	task.delay(8, function()
		if inFlight[remote] == request and currentRequest() then
			showStatus("The server is taking too long. You can close this menu.")
		end
	end)
	task.spawn(function()
		local ok, result = pcall(function() return remote:InvokeServer() end)
		inFlight[remote] = nil
		if not currentRequest() or remote ~= ReplicatedStorage:FindFirstChild("GetArenaServers") then return end
		if not ok or type(result) ~= "table" then
			showStatus("Unable to load servers. Please try Refresh.")
			warn("[ServerBrowser] GetArenaServers : " .. tostring(result))
			return
		end
		local list = normalizeList(result)
		if #list == 0 and FAKE_WHEN_EMPTY then list = makeFakeServers() end
		-- ⚡ PERF : actualisation auto (toutes les 10 s) sans AUCUN changement → on ne reconstruit
		--    rien (avant : toutes les cartes étaient détruites et recréées à chaque fois).
		local parts = {}
		for _, it in ipairs(list) do
			local ids = {}
			for _, pp in ipairs(it.players or {}) do ids[#ids + 1] = tostring(pp.id) end
			parts[#parts + 1] = table.concat({ it.jobId, it.arena, it.total, it.region or "",
				it.map or "", table.concat(ids, ",") }, "|")
		end
		local sig = table.concat(parts, ";")
		if not animate and sig == lastListSig and #currentCards > 0 then return end
		lastListSig = sig
		local rendered, err = pcall(render, list, animate)
		if not rendered then
			warn("[ServerBrowser] Affichage : " .. tostring(err))
			clearCards()
			showStatus("Unable to display servers. Please try Refresh.")
		end
	end)
end

--========================================================
-- OPEN / CLOSE : état synchronisé avec la visibilité réelle du GUI
--========================================================
local function open()
	if not uiReady() then
		pendingOpen = true
		if trySetupGui then trySetupGui() end
		if not uiReady() then
			warn("[ServerBrowser] Menu en attente : Servers > ShopFrame > ScrollingFrame > Entrydemo")
			return
		end
	end
	pendingOpen = false
	if isOpen and activeGui.Enabled and shopFrame.Visible then return end
	isOpen = true
	autoToken += 1
	animationToken += 1
	local myToken, myAnimation = autoToken, animationToken
	if overlayGui then
		overlayGui.DisplayOrder = activeGui.DisplayOrder - 1
		overlayGui.Enabled = true
	end
	activeGui.Enabled = true
	shopFrame.Visible = true
	applyScale()
	if menuScale then
		animatingScale = true
		menuScale.Scale = responsiveFactor * 0.92
		local t = TweenService:Create(menuScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = responsiveFactor})
		t.Completed:Once(function()
			if animationToken == myAnimation then animatingScale = false end
		end)
		t:Play()
	end
	TweenService:Create(blur, TweenInfo.new(0.25), {Size = 18}):Play()
	refresh(true)
	task.spawn(function()
		while isOpen and myToken == autoToken do
			task.wait(AUTO_REFRESH)
			if isOpen and myToken == autoToken then refresh(false) end
		end
	end)
end
close = function(immediate)
	pendingOpen = false
	isOpen = false
	autoToken += 1
	animationToken += 1
	local token = animationToken
	TweenService:Create(blur, TweenInfo.new(0.2), {Size = 0}):Play()
	-- Libérer le bouton Modal dès la fermeture, même si l'animation est interrompue.
	if overlayGui then overlayGui.Enabled = false end
	local frame, gui = shopFrame, activeGui
	local function finish()
		if token ~= animationToken or isOpen then return end
		animatingScale = false
		if frame and frame.Parent then frame.Visible = false end
		if gui and gui.Parent then gui.Enabled = false end
	end
	if menuScale and menuScale.Parent and immediate ~= true then
		animatingScale = true
		local t = TweenService:Create(menuScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = responsiveFactor * 0.92})
		t.Completed:Once(finish)
		t:Play()
	else finish() end
end

--========================================================
-- SETUP DE TON GUI (réessayé si les descendants arrivent plus tard)
--========================================================
setupGui = function(gui)
	if not gui:IsA("ScreenGui") then return false end
	local newFrame = gui:FindFirstChild("ShopFrame", true)
	local newScrolling = newFrame and newFrame:FindFirstChild("ScrollingFrame", true)
	local original = newScrolling and newScrolling:FindFirstChild("Entrydemo", true)
	if not newFrame or not newFrame:IsA("GuiObject") or not newScrolling
		or not newScrolling:IsA("ScrollingFrame") or not original or not original:IsA("GuiObject") then return false end
	local cloned = original:Clone()
	if not cloned then return false end
	local wanted = pendingOpen
	close(true)
	pendingOpen = wanted
	for _, conn in ipairs(guiConnections) do conn:Disconnect() end
	table.clear(guiConnections)
	clearCards()
	if template then template:Destroy() end
	shopFrame, scrolling, menuScale = newFrame, newScrolling, nil
	gui.ResetOnSpawn = false
	gui.Enabled = false
	shopFrame.Visible = false
	uiGeneration += 1
	template = cloned
	template.Name = "EntryTemplate"
	template.Visible = true
	original.Visible = false -- garder le gabarit pour une réinitialisation ultérieure

	local listLayout = scrolling:FindFirstChildOfClass("UIListLayout")
	local gridLayout = scrolling:FindFirstChildOfClass("UIGridLayout")
	if not listLayout and not gridLayout then
		listLayout = Instance.new("UIListLayout")
		listLayout.SortOrder           = Enum.SortOrder.LayoutOrder
		listLayout.Padding             = UDim.new(0, 10)
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.Parent              = scrolling
	end

	scrolling.AutomaticCanvasSize  = Enum.AutomaticSize.None
	scrolling.ScrollingEnabled     = true
	scrolling.ScrollingDirection   = Enum.ScrollingDirection.Y
	if scrolling.ScrollBarThickness < 4 then scrolling.ScrollBarThickness = 6 end

	local canvasLayout = listLayout or gridLayout
	local canvasScrolling = scrolling
	local function syncCanvas()
		if not canvasLayout or not canvasScrolling.Parent then return end
		canvasScrolling.CanvasSize = UDim2.new(0, 0, 0, canvasLayout.AbsoluteContentSize.Y + 12)
	end
	track(canvasLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas))
	syncCanvas()

	if not scrolling:FindFirstChildOfClass("UIPadding") then
		local p = Instance.new("UIPadding", scrolling)
		p.PaddingTop = UDim.new(0, 6); p.PaddingBottom = UDim.new(0, 10)
	end

	if UNIFORM_SCALE then
		shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		shopFrame.Position    = UDim2.fromScale(0.5, 0.5)
		menuScale = shopFrame:FindFirstChildOfClass("UIScale")
		if not menuScale then menuScale = Instance.new("UIScale"); menuScale.Parent = shopFrame end
		hookCamera()
		applyScale()
	end

	local exitBtn = shopFrame:FindFirstChild("Exit", true)
	if exitBtn and exitBtn:IsA("GuiButton") then
		local ps = exitBtn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", exitBtn)
		track(exitBtn.MouseButton1Down:Connect(function() TweenService:Create(ps, TweenInfo.new(0.08), {Scale = 0.9}):Play() end))
		track(exitBtn.MouseButton1Up:Connect(function()   TweenService:Create(ps, TweenInfo.new(0.12, Enum.EasingStyle.Back), {Scale = 1}):Play() end))
		track(exitBtn.MouseLeave:Connect(function()       TweenService:Create(ps, TweenInfo.new(0.12), {Scale = 1}):Play() end))
		track(exitBtn.Activated:Connect(function() close() end))
	else
		warn("[ServerBrowser] Bouton 'Exit' introuvable dans ShopFrame")
	end

	local refreshBtn = shopFrame:FindFirstChild("Refresh", true)
	if refreshBtn and refreshBtn:IsA("GuiButton") then
		track(refreshBtn.Activated:Connect(function()
			refreshBtn.Rotation = 0
			TweenService:Create(refreshBtn, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {Rotation = 360}):Play()
			task.delay(0.4, function() if refreshBtn.Parent then refreshBtn.Rotation = 0 end end)
			refresh(true)
		end))
	else
		warn("[ServerBrowser] Bouton 'Refresh' introuvable dans ShopFrame")
	end

	activeGui = gui
	track(gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if isOpen and not gui.Enabled then close(true) end
	end))
	track(shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if isOpen and not shopFrame.Visible then close(true) end
	end))
	return true
end

--========================================================
-- SETUP D'UN DISPLAY (par model) — billboard + prompt
--========================================================
-- 📍 Le prompt vit sur une part LOCALE (créée par ce script) posée à la
--    position publiée par le serveur. Une part locale n'est JAMAIS déchargée
--    par le streaming → le prompt survit au départ/retour et aux swaps de map.
local localAnchors = Instance.new("Folder")
localAnchors.Name   = "ServerBrowserLocalAnchors"
localAnchors.Parent = Workspace

local function createDisplayAt(cf)
	local anchorPart = Instance.new("Part")
	anchorPart.Name         = "ServerBrowserAnchor"
	anchorPart.Size         = Vector3.new(1, 1, 1)
	anchorPart.Transparency = 1
	anchorPart.Anchored     = true
	anchorPart.CanCollide   = false
	anchorPart.CanTouch     = false
	anchorPart.CanQuery     = false
	anchorPart.CastShadow   = false
	anchorPart.CFrame       = cf
	anchorPart.Parent       = localAnchors

	local billboard = Instance.new("BillboardGui")
	billboard.Name           = "ServerBrowserHeadline"
	billboard.Size           = UDim2.fromScale(10, 3)
	billboard.StudsOffset    = Vector3.new(0, 6, 0)
	billboard.MaxDistance    = 70
	billboard.LightInfluence = 0
	billboard.Parent         = anchorPart

	local headline = Instance.new("TextLabel")
	headline.Size                   = UDim2.fromScale(1, 0.6)
	headline.BackgroundTransparency = 1
	headline.Text                   = "Find servers with players"
	headline.Font                   = Enum.Font.FredokaOne
	headline.TextColor3             = Color3.fromRGB(255, 254, 242)
	headline.TextScaled             = true
	headline.Parent                 = billboard
	local hStroke = Instance.new("UIStroke", headline)
	hStroke.Color = Color3.fromRGB(0,0,0); hStroke.Thickness = 3; hStroke.Transparency = 0

	local headSub = Instance.new("TextLabel")
	headSub.Size                   = UDim2.fromScale(1, 0.3)
	headSub.Position               = UDim2.fromScale(0, 0.66)
	headSub.BackgroundTransparency = 1
	headSub.Text                   = isMobile and "Tap to browse" or "Press E to browse"
	headSub.Font                   = Enum.Font.FredokaOne
	headSub.TextColor3             = Color3.fromRGB(248, 251, 240)
	headSub.TextScaled             = true
	headSub.Parent                 = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = "ServerBrowserPrompt"
	prompt.ActionText            = "Browse Servers"
	prompt.ObjectText            = "1v1 Servers"
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = anchorPart

	prompt.Triggered:Connect(function(p)
		if p ~= localPlayer then return end
		open() -- idempotent : deux prompts ne peuvent pas ouvrir puis fermer aussitôt
	end)
	return anchorPart
end

--========================================================
-- BOOTSTRAP GUI (1 seul, par joueur) + filet anti-duplication au respawn
--========================================================
trySetupGui = function()
	if uiReady() then return end
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui.Name == "Servers" and gui:IsA("ScreenGui") then
			local ok, ready = pcall(setupGui, gui)
			if not ok then warn("[ServerBrowser] Setup : " .. tostring(ready)) end
			if ok and ready then
				if pendingOpen then open() end
				return
			end
		end
	end
end
local setupQueued = false
local function queueSetup()
	if setupQueued or uiReady() then return end
	setupQueued = true
	task.defer(function()
		setupQueued = false
		trySetupGui()
	end)
end
-- Écouter AVANT le scan ; aucune suppression d'un GUI encore incomplet.
playerGui.DescendantAdded:Connect(queueSetup)
playerGui.DescendantRemoving:Connect(function(obj)
	if obj == activeGui or obj == shopFrame or obj == scrolling then
		close(true)
		task.defer(queueSetup)
	end
end)
trySetupGui()
localPlayer.CharacterAdded:Connect(function() close(true) end)

-- Positions publiées par le serveur : écoute permanente, même après 30 secondes
-- ou si le dossier est remplacé lors d'un changement de carte.
local built = {}
local anchorFolder, folderAdded, folderRemoved
local function addAnchor(v)
	if not v:IsA("CFrameValue") or built[v] then return end
	local part = createDisplayAt(v.Value)
	built[v] = { part = part, connection = v.Changed:Connect(function(newCf)
		if part.Parent then part.CFrame = newCf end
	end) }
end
local function removeAnchor(v)
	local record = built[v]
	if record then record.connection:Disconnect(); record.part:Destroy() end
	built[v] = nil
end
local function syncAnchorFolder()
	local folder = ReplicatedStorage:FindFirstChild("ServerBrowserAnchors")
	if folder == anchorFolder then return end
	if folderAdded then folderAdded:Disconnect(); folderAdded = nil end
	if folderRemoved then folderRemoved:Disconnect(); folderRemoved = nil end
	for v in pairs(built) do removeAnchor(v) end
	anchorFolder = folder
	if not folder then return end
	folderAdded = folder.ChildAdded:Connect(addAnchor)
	folderRemoved = folder.ChildRemoved:Connect(removeAnchor)
	for _, v in ipairs(folder:GetChildren()) do addAnchor(v) end
end
ReplicatedStorage.ChildAdded:Connect(function(c)
	if c.Name == "ServerBrowserAnchors" then syncAnchorFolder() end
end)
ReplicatedStorage.ChildRemoved:Connect(function(c)
	if c == anchorFolder then syncAnchorFolder() end
end)
syncAnchorFolder()
task.delay(30, function()
	if not anchorFolder then warn("[ServerBrowser] ServerBrowserAnchors absent : vérifier le script serveur. Détection toujours active.") end
end)

--========================================================
-- CAMERA (re-hook si la caméra change)
--========================================================
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hookCamera(); applyScale()
end)

--========================================================
-- WIRING global
--========================================================
if overlayBtn then
	overlayBtn.Activated:Connect(function() close() end)
end

local failureRemote, failureConn
local function syncRemotes()
	getServersFn = ReplicatedStorage:FindFirstChild("GetArenaServers")
	joinServerEvent = ReplicatedStorage:FindFirstChild("JoinArenaServer")
	joinFailedEvent = ReplicatedStorage:FindFirstChild("ArenaJoinFailed")
	if failureRemote ~= joinFailedEvent then
		if failureConn then failureConn:Disconnect(); failureConn = nil end
		failureRemote = joinFailedEvent
		if failureRemote and failureRemote:IsA("RemoteEvent") then
			failureConn = failureRemote.OnClientEvent:Connect(function()
				resetJoins()
				if isOpen then refresh(false) end
			end)
		end
	end
end
local remoteNames = { GetArenaServers = true, JoinArenaServer = true, ArenaJoinFailed = true }
ReplicatedStorage.ChildAdded:Connect(function(c)
	if remoteNames[c.Name] then syncRemotes(); if isOpen then refresh(false) end end
end)
ReplicatedStorage.ChildRemoved:Connect(function(c)
	if remoteNames[c.Name] then syncRemotes() end
end)
syncRemotes()

print("✅ ServerBrowserDisplay v5.2 chargé (GUI récupérable + anchors persistants)")