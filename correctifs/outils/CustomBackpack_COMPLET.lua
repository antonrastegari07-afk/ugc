--[[
	🎒 CustomBackpack v2 — copie du backpack Roblox + drag & drop sauvegardé
	📍 StarterPlayer > StarterPlayerScripts  (LocalScript)

	AUCUN autre script à modifier :
	  • lit simplement player.Backpack + le Character (comme le backpack Roblox)
	  • EquipTool / UnequipTools / tools donnés ou détruits par n'importe quel script → suivi auto
	  • StarterGui:SetCoreGuiEnabled(Backpack / All, false/true) de tes scripts → cache/affiche cette hotbar
	  • les scripts qui cachent les ScreenGui du PlayerGui ne la cachent pas (comme le vrai backpack)

	PC     : Tab (ou `) ouvre l'inventaire (tools qui ne rentrent pas dans les 10 cases)
	         → glisser un tool sur une case / dans l'inventaire
	Mobile : appui long sur un tool → les tools tremblent + l'inventaire s'ouvre
	         → glisser où tu veux · toucher ailleurs pour terminer
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local GuiService        = game:GetService("GuiService")

local player = Players.LocalPlayer

local function font(name, fallback)
	local ok, f = pcall(function() return Enum.Font[name] end)
	return ok and f or fallback
end

-- ⚙️ CONFIG ==================================================================
local CONFIG = {
	-- Contrôles
	OPEN_KEYS        = { Enum.KeyCode.Tab, Enum.KeyCode.Backquote },
	HIDE_PLAYERLIST  = false,   -- Tab ouvre AUSSI la liste des joueurs Roblox → true pour la cacher
	LONG_PRESS_TIME  = 0.45,    -- mobile : durée de l'appui long
	DRAG_THRESHOLD   = 8,       -- px avant qu'un appui devienne un drag
	JIGGLE_ON_PC     = false,   -- faire trembler aussi quand l'inventaire est ouvert sur PC

	-- Disposition (valeurs du backpack Roblox)
	HOTBAR_SLOTS_FULL   = 10,    -- nb de cases hotbar, grand écran (PC / tablette)
	HOTBAR_SLOTS_MINI   = 7,     -- nb de cases hotbar, petit écran (téléphones) → 4, 5, 6… pour en montrer plus
	MINI_WIDTH_CUTOFF   = 1024,  -- largeur d'écran (px) sous laquelle on utilise les valeurs *_MINI
	FIT_TO_SCREEN       = true,  -- retire des cases si la hotbar/l'inventaire dépasse l'écran

	SLOT_SIZE           = 60,    -- taille (px) des cases de la hotbar, grand écran
	SLOT_SIZE_MINI      = 50,    -- taille (px) des cases de la hotbar, petit écran
	INVENTORY_SLOT_SIZE      = nil,  -- taille des cases de l'inventaire (Tab), nil = comme la hotbar
	INVENTORY_SLOT_SIZE_MINI = nil,  -- pareil, petit écran
	INVENTORY_COLUMNS        = nil,  -- colonnes de l'inventaire, nil = nb de cases de la hotbar
	SLOT_GAP            = 5,
	BOTTOM_OFFSET       = 5,
	INVENTORY_ROWS_FULL = 4,
	INVENTORY_ROWS_MINI = 2,
	INVENTORY_HEADER    = 40,
	SHOW_SEARCH         = true,
	SEARCH_PLACEHOLDER  = "Rechercher",
	SHOW_TOOLTIPS       = true,  -- Tool.ToolTip au survol (souris)
	SHOW_NUMBERS        = true,  -- chiffres 1-0 (seulement si clavier)
	DISPLAY_ORDER       = -10,   -- toujours DERRIÈRE toutes les autres interfaces

	-- Apparence
	FONT                   = font("BuilderSansBold", Enum.Font.GothamBold),
	TEXT_SIZE              = 14,
	TEXT_COLOR             = Color3.new(1, 1, 1),
	SLOT_COLOR             = Color3.fromRGB(31, 31, 31),
	SLOT_TRANSPARENCY      = 0.5,
	CORNER_RADIUS          = 8,
	EQUIP_COLOR            = Color3.fromRGB(0, 162, 255),
	EQUIP_THICKNESS        = 3,
	DRAG_BORDER_COLOR      = Color3.new(1, 1, 1),
	INVENTORY_COLOR        = Color3.fromRGB(31, 31, 31),
	INVENTORY_TRANSPARENCY = 0.5,
	SEARCH_COLOR           = Color3.fromRGB(94, 94, 94),
	SEARCH_TRANSPARENCY    = 0.15,
	TOOLTIP_COLOR          = Color3.fromRGB(31, 31, 31),
	TOOLTIP_TRANSPARENCY   = 0.1,

	-- Tremblement (mobile)
	JIGGLE_ANGLE = 3,     -- degrés
	JIGGLE_SPEED = 22,

	-- Sauvegarde
	MAX_SLOTS  = 100,     -- ⚠️ même valeur que InventoryLayoutServer
	SEND_DELAY = 1,
	-- Doit renvoyer "pvp" ou "obby" (les 2 modes sauvegardés par le serveur)
	GET_MODE = function(plr)
		return plr:GetAttribute("InArena") and "pvp" or "obby"
	end,
	-- "_" → "AK47_Gold" et "AK47" partagent la même case (skins). nil = nom complet
	SKIN_SEPARATOR = "_",   -- « AK47_Gold Dragon » garde la case de « AK47 » (skins)
}
-- ===========================================================================

local remote = ReplicatedStorage:WaitForChild("InventoryLayout", 15)
if not remote then
	warn("🎒 RemoteEvent InventoryLayout introuvable : pas de sauvegarde (InventoryLayoutServer manquant ?)")
end

local KEY_TO_INDEX = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}
local OPEN_KEY = {}
for _, k in ipairs(CONFIG.OPEN_KEYS) do OPEN_KEY[k] = true end

-- 📦 ÉTAT ====================================================================
local layouts     = { pvp = {}, obby = {} }   -- [mode] = { [clé] = case }
local localEdited = {}
local slotTools   = {}     -- [case] = Tool
local slotOfTool  = {}     -- [Tool] = case
local toolConns   = {}     -- [Tool] = { connexions }
local inventoryOpen, editMode = false, false
local coreWanted  = true   -- ce que les autres scripts veulent (SetCoreGuiEnabled Backpack)
local drag        = nil
local searchText  = ""

local screenGui, root, hotbarFrame, invFrame, invScroll, tooltip, tooltipOwner
local hotSlots, invSlots = {}, {}
local hotbarCount, slotSize, invRows = 10, 60, 4

local queueRefresh, refreshUI, setInventoryOpen, onPress   -- déclarées plus bas

-- 🔧 OUTILS ==================================================================
local function new(className, props, parent)
	local o = Instance.new(className)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function inside(gui, pos)
	if not gui then return false end
	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

local function getMode()
	local ok, m = pcall(CONFIG.GET_MODE, player)
	if ok and type(m) == "string" then return m end
	return "obby"
end

local currentFormat = ""
local function computeFormat()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local mini = vp.X < CONFIG.MINI_WIDTH_CUTOFF
	local gap = CONFIG.SLOT_GAP

	local count = mini and CONFIG.HOTBAR_SLOTS_MINI or CONFIG.HOTBAR_SLOTS_FULL
	count = math.min(count, CONFIG.HOTBAR_SLOTS_FULL)
	local size = mini and CONFIG.SLOT_SIZE_MINI or CONFIG.SLOT_SIZE

	local invSize
	if mini then invSize = CONFIG.INVENTORY_SLOT_SIZE_MINI else invSize = CONFIG.INVENTORY_SLOT_SIZE end
	invSize = invSize or size
	local cols = CONFIG.INVENTORY_COLUMNS or count
	local rows = mini and CONFIG.INVENTORY_ROWS_MINI or CONFIG.INVENTORY_ROWS_FULL

	if CONFIG.FIT_TO_SCREEN then
		count = math.max(1, math.min(count, math.floor((vp.X - 20 + gap) / (size + gap))))
		cols  = math.max(1, math.min(cols, math.floor((vp.X - 20 - gap) / (invSize + gap))))
	end

	local key = table.concat({ count, size, invSize, cols, rows }, ":")
	return count, size, invSize, cols, rows, key
end

local function layoutFor(mode)
	layouts[mode] = layouts[mode] or {}
	return layouts[mode]
end

local function toolKey(tool)
	--  la faux change de numéro d'un serveur à l'autre : même case partout
	if tool:GetAttribute("JackScythe") ~= nil then return "JackScythe" end
	local k = tool:GetAttribute("InvKey")
	if type(k) == "string" and k ~= "" then return k end
	local name = tool.Name
	if CONFIG.SKIN_SEPARATOR then
		local i = string.find(name, CONFIG.SKIN_SEPARATOR, 1, true)
		if i and i > 1 then return string.sub(name, 1, i - 1) end
	end
	return name
end

-- 🧮 PLACEMENT ===============================================================
local function collectTools()
	local list, seen = {}, {}
	local function add(container)
		if not container then return end
		for _, c in ipairs(container:GetChildren()) do
			if c:IsA("Tool") and not seen[c] then
				seen[c] = true
				table.insert(list, c)
			end
		end
	end
	add(player:FindFirstChildOfClass("Backpack"))
	add(player.Character)
	return list, seen
end

local function rebuildSlotOf()
	slotOfTool = {}
	for s, t in pairs(slotTools) do slotOfTool[t] = s end
end

local function computeLayout()
	local saved = layoutFor(getMode())
	local tools, seen = collectTools()
	local slots, placed, keyUsed = {}, {}, {}

	-- suivi icône / nom des tools
	for _, tool in ipairs(tools) do
		if not toolConns[tool] then
			toolConns[tool] = {
				tool:GetPropertyChangedSignal("TextureId"):Connect(function() queueRefresh() end),
				tool:GetPropertyChangedSignal("Name"):Connect(function() queueRefresh() end),
			}
		end
	end
	for tool, conns in pairs(toolConns) do
		if not seen[tool] then
			for _, c in ipairs(conns) do c:Disconnect() end
			toolConns[tool] = nil
		end
	end

	-- 1) emplacement sauvegardé
	for _, tool in ipairs(tools) do
		local key = toolKey(tool)
		local s = saved[key]
		if s and not keyUsed[key] and not slots[s] then
			slots[s] = tool
			placed[tool] = true
			keyUsed[key] = true
		end
	end
	-- 2) déjà affiché → garde sa case
	for _, tool in ipairs(tools) do
		if not placed[tool] then
			local s = slotOfTool[tool]
			if s and not slots[s] then
				slots[s] = tool
				placed[tool] = true
			end
		end
	end
	-- 3) nouveau → première case libre
	local free = 1
	for _, tool in ipairs(tools) do
		if not placed[tool] then
			while free <= CONFIG.MAX_SLOTS and slots[free] do free = free + 1 end
			if free > CONFIG.MAX_SLOTS then break end
			slots[free] = tool
			placed[tool] = true
		end
	end

	slotTools = slots
	rebuildSlotOf()
end

-- 📡 SYNC SERVEUR ============================================================
local pendingSend, sendToken = {}, 0
local function scheduleSend(mode)
	if not remote then return end
	pendingSend[mode] = true
	sendToken = sendToken + 1
	local myToken = sendToken
	task.delay(CONFIG.SEND_DELAY, function()
		if myToken ~= sendToken then return end
		local payload = {}
		for m in pairs(pendingSend) do payload[m] = layouts[m] end
		pendingSend = {}
		remote:FireServer("set", payload)
	end)
end

-- 🧰 ACTIONS =================================================================
local function toggleEquip(tool)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or not tool.Parent then return end
	if tool.Parent == char then
		hum:UnequipTools()
	else
		hum:EquipTool(tool)
	end
end

local function commitMove(tool, target)
	local from = slotOfTool[tool]
	if not from then return end
	local FULL = CONFIG.HOTBAR_SLOTS_FULL

	if target == "end" then
		local highest = FULL
		for s in pairs(slotTools) do
			if s > highest then highest = s end
		end
		if from == highest and from > FULL then return end
		slotTools[from] = nil
		slotTools[highest + 1] = tool
	else
		if from == target then return end
		slotTools[from], slotTools[target] = slotTools[target], tool
	end

	-- compacte l'inventaire (cases > 10) : 11, 12, 13…
	local invCases = {}
	local compact = {}
	for s, t in pairs(slotTools) do
		if s > FULL then table.insert(invCases, s) else compact[s] = t end
	end
	table.sort(invCases)
	for i, s in ipairs(invCases) do
		if FULL + i <= CONFIG.MAX_SLOTS then compact[FULL + i] = slotTools[s] end
	end
	slotTools = compact
	rebuildSlotOf()

	-- snapshot → layout du mode actuel
	local mode = getMode()
	local map, usedKey, usedSlot = {}, {}, {}
	for s = 1, CONFIG.MAX_SLOTS do
		local t = slotTools[s]
		if t then
			local k = toolKey(t)
			if not usedKey[k] then
				map[k] = s
				usedKey[k] = true
				usedSlot[s] = true
			end
		end
	end
	-- tools absents (arme de spin/streak pas là aujourd'hui…) : garde leur case de hotbar si libre
	for k, s in pairs(layoutFor(mode)) do
		if not usedKey[k] and s <= FULL and not usedSlot[s] then
			map[k] = s
			usedSlot[s] = true
		end
	end
	layouts[mode] = map
	localEdited[mode] = true
	scheduleSend(mode)
end

-- 🎨 UI ======================================================================
local function hideTooltip(ui)
	if tooltip and (ui == nil or tooltipOwner == ui) then
		tooltip.Visible = false
		tooltipOwner = nil
	end
end

local function showTooltip(ui)
	if not CONFIG.SHOW_TOOLTIPS or not tooltip or drag or not UserInputService.MouseEnabled then return end
	local t = ui.tool
	if not t or t.ToolTip == "" then return end
	local p, s, o = ui.button.AbsolutePosition, ui.button.AbsoluteSize, root.AbsolutePosition
	tooltip.Text = t.ToolTip
	tooltip.Position = UDim2.fromOffset(p.X - o.X + s.X / 2, p.Y - o.Y - 4)
	tooltip.Visible = true
	tooltipOwner = ui
end

local function createSlotUI(parent)
	local b = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Selectable = false,
		BackgroundColor3 = CONFIG.SLOT_COLOR,
		BackgroundTransparency = CONFIG.SLOT_TRANSPARENCY,
		Size = UDim2.fromOffset(slotSize, slotSize),
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, CONFIG.CORNER_RADIUS) }, b)
	local stroke = new("UIStroke", {
		Color = CONFIG.EQUIP_COLOR,
		Thickness = CONFIG.EQUIP_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Enabled = false,
	}, b)
	local content = new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, b)
	local icon = new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		ScaleType = Enum.ScaleType.Fit,
		Image = "",
	}, content)
	local nameLabel = new("TextLabel", {
		Name = "ToolName",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		Font = CONFIG.FONT,
		TextSize = CONFIG.TEXT_SIZE,
		TextColor3 = CONFIG.TEXT_COLOR,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, content)
	local number = new("TextLabel", {
		Name = "Number",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(5, 2),
		Size = UDim2.fromOffset(15, 15),
		Font = CONFIG.FONT,
		TextSize = CONFIG.TEXT_SIZE,
		TextColor3 = CONFIG.TEXT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.6,
		Visible = false,
		Text = "",
	}, content)

	local ui = { button = b, stroke = stroke, content = content, icon = icon, name = nameLabel, number = number, tool = nil }
	b.InputBegan:Connect(function(input) onPress(ui, input) end)
	b.MouseEnter:Connect(function() showTooltip(ui) end)
	b.MouseLeave:Connect(function() hideTooltip(ui) end)
	return ui
end

local function paintSlot(ui, tool)
	ui.tool = tool
	local dragged = tool ~= nil and drag ~= nil and drag.active and drag.tool == tool
	if tool and not dragged then
		local tex = tool.TextureId
		ui.icon.Image = tex
		ui.name.Text = (tex == "") and tool.Name or ""
		ui.stroke.Enabled = (player.Character ~= nil and tool.Parent == player.Character)
	else
		ui.icon.Image = ""
		ui.name.Text = ""
		ui.stroke.Enabled = false
	end
end

refreshUI = function()
	if not screenGui then return end
	root.Visible = coreWanted
	local gap = CONFIG.SLOT_GAP

	-- Hotbar : fermé = seulement jusqu'au dernier tool · ouvert = toutes les cases
	local lastFilled = 0
	for i = 1, hotbarCount do
		if slotTools[i] then lastFilled = i end
	end
	local shown = inventoryOpen and hotbarCount or lastFilled
	hotbarFrame.Size = UDim2.fromOffset(math.max(shown * (slotSize + gap) - gap, 0), slotSize)
	for i, ui in ipairs(hotSlots) do
		paintSlot(ui, slotTools[i])
		ui.button.Visible = i <= shown and (inventoryOpen or slotTools[i] ~= nil)
	end

	-- Inventaire : tools au-delà de la hotbar, dans l'ordre, sans trous
	invFrame.Visible = inventoryOpen
	if not inventoryOpen then return end

	local cases = {}
	for s in pairs(slotTools) do
		if s > hotbarCount then table.insert(cases, s) end
	end
	table.sort(cases)

	local filter = string.lower(searchText)
	local n = 0
	for _, s in ipairs(cases) do
		local t = slotTools[s]
		if filter == "" or string.find(string.lower(t.Name), filter, 1, true) then
			n = n + 1
			local ui = invSlots[n]
			if not ui then
				ui = createSlotUI(invScroll)
				invSlots[n] = ui
			end
			ui.button.LayoutOrder = n
			ui.button.Visible = true
			paintSlot(ui, t)
		end
	end
	for j = n + 1, #invSlots do
		invSlots[j].button.Visible = false
		invSlots[j].tool = nil
	end
end

local refreshQueued = false
queueRefresh = function()
	if refreshQueued then return end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		computeLayout()
		refreshUI()
	end)
end

local function cancelDrag()
	if drag and drag.ghost then drag.ghost:Destroy() end
	if invScroll then invScroll.ScrollingEnabled = true end
	drag = nil
end

local function buildUI()
	cancelDrag()
	local old = screenGui
	screenGui = nil
	if old then old:Destroy() end
	hotSlots, invSlots = {}, {}
	tooltipOwner = nil

	local invSize, invCols
	hotbarCount, slotSize, invSize, invCols, invRows, currentFormat = computeFormat()
	local gap = CONFIG.SLOT_GAP

	local gui = new("ScreenGui", {
		Name = "CustomBackpack",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = CONFIG.DISPLAY_ORDER,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	screenGui = gui

	root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)

	-- Hotbar
	hotbarFrame = new("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -CONFIG.BOTTOM_OFFSET),
		Size = UDim2.fromOffset(0, slotSize),
		BackgroundTransparency = 1,
	}, root)
	local keyboard = UserInputService.KeyboardEnabled and CONFIG.SHOW_NUMBERS
	for i = 1, hotbarCount do
		local ui = createSlotUI(hotbarFrame)
		ui.button.Name = "Slot" .. i
		ui.button.Position = UDim2.fromOffset((i - 1) * (slotSize + gap), 0)
		ui.number.Text = tostring(i % 10)
		ui.number.Visible = keyboard and i <= 10
		hotSlots[i] = ui
	end

	-- Inventaire
	local invW = invCols * (invSize + gap) + gap
	local invH = CONFIG.INVENTORY_HEADER + invRows * (invSize + gap)
	invFrame = new("Frame", {
		Name = "Inventory",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(CONFIG.BOTTOM_OFFSET + slotSize + gap)),
		Size = UDim2.fromOffset(invW, invH),
		BackgroundColor3 = CONFIG.INVENTORY_COLOR,
		BackgroundTransparency = CONFIG.INVENTORY_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(0, CONFIG.CORNER_RADIUS) }, invFrame)
	-- libère la souris en shift-lock / 1re personne quand l'inventaire est ouvert (comme Roblox)
	new("TextButton", { Name = "MouseUnlock", Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Modal = true }, invFrame)

	if CONFIG.SHOW_SEARCH then
		local box = new("TextBox", {
			Name = "Search",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -gap, 0, gap),
			Size = UDim2.fromOffset(math.min(200, invW - gap * 2), CONFIG.INVENTORY_HEADER - gap * 2),
			BackgroundColor3 = CONFIG.SEARCH_COLOR,
			BackgroundTransparency = CONFIG.SEARCH_TRANSPARENCY,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = CONFIG.FONT,
			TextSize = CONFIG.TEXT_SIZE + 2,
			TextColor3 = CONFIG.TEXT_COLOR,
			PlaceholderText = CONFIG.SEARCH_PLACEHOLDER,
			PlaceholderColor3 = Color3.fromRGB(200, 200, 200),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = searchText,
		}, invFrame)
		new("UICorner", { CornerRadius = UDim.new(0, CONFIG.CORNER_RADIUS) }, box)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			searchText = box.Text
			refreshUI()
		end)
	end

	invScroll = new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(gap, CONFIG.INVENTORY_HEADER),
		Size = UDim2.new(1, -gap * 2, 1, -CONFIG.INVENTORY_HEADER - gap),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
	}, invFrame)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(invSize, invSize),
		CellPadding = UDim2.fromOffset(gap, gap),
		FillDirectionMaxCells = invCols,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, invScroll)

	-- Tooltip
	if CONFIG.SHOW_TOOLTIPS then
		tooltip = new("TextLabel", {
			Name = "Tooltip",
			AnchorPoint = Vector2.new(0.5, 1),
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = CONFIG.TOOLTIP_COLOR,
			BackgroundTransparency = CONFIG.TOOLTIP_TRANSPARENCY,
			BorderSizePixel = 0,
			Font = CONFIG.FONT,
			TextSize = CONFIG.TEXT_SIZE,
			TextColor3 = CONFIG.TEXT_COLOR,
			Visible = false,
			ZIndex = 60,
			Text = "",
		}, root)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, tooltip)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3),
		}, tooltip)
	else
		tooltip = nil
	end

	-- 🛡️ Les autres scripts ne peuvent pas la cacher/détruire (comme le backpack CoreGui)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if screenGui == gui and not gui.Enabled then gui.Enabled = true end
	end)
	gui.AncestryChanged:Connect(function()
		if screenGui == gui and gui.Parent ~= player:FindFirstChildOfClass("PlayerGui") then
			task.defer(function()
				if screenGui == gui then
					buildUI()
					queueRefresh()
				end
			end)
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	refreshUI()
end

setInventoryOpen = function(open)
	if open and not coreWanted then return end
	inventoryOpen = open
	if not open then
		editMode = false
		cancelDrag()
		if searchText ~= "" then
			searchText = ""
			local box = invFrame and invFrame:FindFirstChild("Search")
			if box then box.Text = "" end
		end
	end
	hideTooltip()
	refreshUI()
end

local function setEditMode(on)
	editMode = on
	setInventoryOpen(on)
end

-- 🖱️ DRAG & DROP (souris + tactile) ==========================================
local function isDragInput(d, input, isMove)
	if d.isTouch then return input == d.input end
	if isMove then return input.UserInputType == Enum.UserInputType.MouseMovement end
	return input.UserInputType == Enum.UserInputType.MouseButton1
end

onPress = function(ui, input)
	local t = input.UserInputType
	if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
	if drag or not ui.tool or not coreWanted then return end

	local d = {
		ui = ui,
		tool = ui.tool,
		input = input,
		isTouch = (t == Enum.UserInputType.Touch),
		start = Vector2.new(input.Position.X, input.Position.Y),
		active = false,
		longPressed = false,
	}
	drag = d

	-- 📱 appui long → mode édition (tremblement)
	if d.isTouch and not editMode then
		task.delay(CONFIG.LONG_PRESS_TIME, function()
			if drag == d and not d.active then
				d.longPressed = true
				setEditMode(true)
				drag = d   -- setInventoryOpen n'annule pas ce doigt : il peut glisser direct
			end
		end)
	end
end

local function startDragVisual(d)
	d.active = true
	hideTooltip()
	if invScroll then invScroll.ScrollingEnabled = false end

	local ghost = new("Frame", {
		Name = "DragGhost",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(slotSize, slotSize),
		BackgroundColor3 = CONFIG.SLOT_COLOR,
		BackgroundTransparency = CONFIG.SLOT_TRANSPARENCY * 0.6,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(0, CONFIG.CORNER_RADIUS) }, ghost)
	new("UIStroke", { Color = CONFIG.DRAG_BORDER_COLOR, Thickness = 2 }, ghost)
	local tex = d.tool.TextureId
	new("ImageLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		ScaleType = Enum.ScaleType.Fit,
		Image = tex,
		ZIndex = 51,
	}, ghost)
	if tex == "" then
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			Font = CONFIG.FONT,
			TextSize = CONFIG.TEXT_SIZE,
			TextColor3 = CONFIG.TEXT_COLOR,
			TextWrapped = true,
			Text = d.tool.Name,
			ZIndex = 51,
		}, ghost)
	end
	d.ghost = ghost
	refreshUI()
end

local function dropAt(tool, pos)
	local target
	for i, ui in ipairs(hotSlots) do
		if inside(ui.button, pos) then
			target = i
			break
		end
	end
	if not target and inventoryOpen and inside(invFrame, pos) then
		if inside(invScroll, pos) then
			for _, ui in ipairs(invSlots) do
				if ui.button.Visible and ui.tool and inside(ui.button, pos) then
					target = slotOfTool[ui.tool]
					break
				end
			end
		end
		target = target or "end"   -- zone vide de l'inventaire → à la fin
	end
	if target then commitMove(tool, target) end
end

UserInputService.InputChanged:Connect(function(input)
	local d = drag
	if not d or not isDragInput(d, input, true) then return end
	local pos = Vector2.new(input.Position.X, input.Position.Y)

	if not d.active then
		if (pos - d.start).Magnitude < CONFIG.DRAG_THRESHOLD then return end
		if not inventoryOpen then
			if d.isTouch then drag = nil end   -- glissé avant l'appui long = pas un drag
			return
		end
		if not d.tool.Parent then
			cancelDrag()
			return
		end
		startDragVisual(d)
	end

	local o = root.AbsolutePosition
	d.ghost.Position = UDim2.fromOffset(pos.X - o.X, pos.Y - o.Y)
end)

UserInputService.InputEnded:Connect(function(input)
	local d = drag
	if not d or not isDragInput(d, input, false) then return end
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	cancelDrag()

	if d.active then
		if d.tool.Parent then dropAt(d.tool, pos) end
		refreshUI()
	elseif not d.longPressed and inside(d.ui.button, pos) and d.ui.tool == d.tool then
		toggleEquip(d.tool)   -- simple clic / tap = équiper
	end
end)

-- 📱 Tremblement ==============================================================
local jiggling = false
RunService.RenderStepped:Connect(function()
	local on = editMode or (inventoryOpen and CONFIG.JIGGLE_ON_PC)
	if not on then
		if jiggling then
			jiggling = false
			for _, list in ipairs({ hotSlots, invSlots }) do
				for _, ui in ipairs(list) do
					ui.button.Rotation = 0
					ui.content.Position = UDim2.new()
				end
			end
		end
		return
	end
	jiggling = true
	local t = os.clock() * CONFIG.JIGGLE_SPEED
	local function jiggle(ui, phase)
		if ui.tool and ui.button.Visible then
			ui.button.Rotation = math.sin(t + phase) * CONFIG.JIGGLE_ANGLE
			ui.content.Position = UDim2.fromOffset(0, math.cos(t * 1.3 + phase))
		else
			ui.button.Rotation = 0
			ui.content.Position = UDim2.new()
		end
	end
	for i, ui in ipairs(hotSlots) do jiggle(ui, i * 1.7) end
	for i, ui in ipairs(invSlots) do jiggle(ui, i * 2.3) end
end)

-- ⌨️ CLAVIER + toucher ailleurs =============================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	local ut = input.UserInputType

	if ut == Enum.UserInputType.Touch then
		if editMode and screenGui then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if not inside(hotbarFrame, pos) and not inside(invFrame, pos) then
				setInventoryOpen(false)   -- toucher ailleurs = fin du mode édition
			end
		end
		return
	end

	if ut ~= Enum.UserInputType.Keyboard then return end
	if UserInputService:GetFocusedTextBox() or not coreWanted then return end

	if OPEN_KEY[input.KeyCode] then
		setInventoryOpen(not inventoryOpen)
		return
	end

	if gameProcessed then return end
	local idx = KEY_TO_INDEX[input.KeyCode]
	if idx and idx <= hotbarCount and slotTools[idx] then
		toggleEquip(slotTools[idx])
	end
end)

GuiService.MenuOpened:Connect(function()
	setInventoryOpen(false)
end)

-- 🔌 COMPATIBILITÉ SetCoreGuiEnabled(Backpack) ================================
local pendingSelfDisables = 0

local function setCoreWanted(v)
	if coreWanted == v then return end
	coreWanted = v
	if not v then setInventoryOpen(false) else refreshUI() end
end

local function forceCoreBackpackOff()
	local ok, enabled = pcall(function()
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
	end)
	if ok and enabled then
		pendingSelfDisables = pendingSelfDisables + 1
		local ok2 = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if not ok2 then pendingSelfDisables = pendingSelfDisables - 1 end
		return true
	end
	return false
end

do
	local ok, enabled = pcall(function()
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
	end)
	if ok then coreWanted = enabled end
end

-- Signal (si accessible) : capte aussi les "false" des autres scripts
local hasCoreSignal = pcall(function()
	StarterGui.CoreGuiChangedSignal:Connect(function(coreType, enabled)
		if coreType ~= Enum.CoreGuiType.Backpack and coreType ~= Enum.CoreGuiType.All then return end
		if coreType == Enum.CoreGuiType.Backpack and not enabled and pendingSelfDisables > 0 then
			pendingSelfDisables = pendingSelfDisables - 1
			return
		end
		setCoreWanted(enabled)
		if enabled then task.defer(forceCoreBackpackOff) end
	end)
end)

if CONFIG.HIDE_PLAYERLIST then
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
end

task.spawn(function()
	while true do
		if forceCoreBackpackOff() and not hasCoreSignal then
			setCoreWanted(true)   -- un script a réactivé le backpack Roblox → on affiche le nôtre
		end
		task.wait(0.5)
	end
end)

-- API optionnelle pour tes futurs scripts (rien d'obligatoire)
_G.CustomBackpack = {
	SetEnabled = setCoreWanted,
	IsEnabled  = function() return coreWanted end,
	Open       = function() setInventoryOpen(true) end,
	Close      = function() setInventoryOpen(false) end,
}

-- 👀 SURVEILLANCE ============================================================
local containerConns = {}
local function watchContainers()
	for _, c in ipairs(containerConns) do c:Disconnect() end
	containerConns = {}
	local function watch(container)
		if not container then return end
		table.insert(containerConns, container.ChildAdded:Connect(function(c)
			if c:IsA("Tool") then queueRefresh() end
		end))
		table.insert(containerConns, container.ChildRemoved:Connect(function(c)
			if c:IsA("Tool") then queueRefresh() end
		end))
	end
	watch(player:FindFirstChildOfClass("Backpack"))
	watch(player.Character)
	queueRefresh()
end

player.CharacterAdded:Connect(watchContainers)
player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then watchContainers() end
end)
player.AttributeChanged:Connect(function()
	queueRefresh()   -- ex: InArena → change de layout (pvp/obby)
end)

-- 📐 Rebuild seulement si le format change (rotation mobile, fenêtre PC)
local function hookCamera()
	local cam = workspace.CurrentCamera
	if not cam then return end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local _, _, _, _, _, key = computeFormat()
		if key ~= currentFormat then
			buildUI()
			queueRefresh()
		end
	end)
end
hookCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)

-- 📥 Layout sauvegardé reçu du serveur
if remote then
	remote.OnClientEvent:Connect(function(action, data)
		if action ~= "data" or type(data) ~= "table" then return end
		for mode, map in pairs(data) do
			if type(map) == "table" and not localEdited[mode] then
				layouts[mode] = map
			end
		end
		queueRefresh()
	end)
end

buildUI()
watchContainers()
if remote then remote:FireServer("get") end