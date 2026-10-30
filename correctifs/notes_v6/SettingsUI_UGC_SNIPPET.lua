-- 🎽 UGC REDEEMED — tes UGC récupérés, EN PREMIER dans la page « STATS & UGCS » des Settings.
--    Comme dans les fiches profil : les 4 derniers UGC + une carte « See all (N) ».
--    See all → tous les UGC dans la page (qui défile), dernière carte « Show less ».
--    Rechargée à l'ouverture de la page (au plus toutes les 30 s).
local MY_UGC_PREVIEW = 4
local MY_UGC_ICON = nil   -- 🖼️ "rbxassetid://ID" pour une icône devant le texte (nil = pas d'icône)
local myUGCCard = statCard("UGC REDEEMED", 2)
local myUGCHead = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 1 }, myUGCCard)
local myUGCIconX = 0
if MY_UGC_ICON then
	new("ImageLabel", { BackgroundTransparency = 1, Image = MY_UGC_ICON, ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) }, myUGCHead)
	myUGCIconX = 26
end
local myUGCNote = text(myUGCHead, { Text = "Loading…", TextSize = 15, TextColor3 = T.Sub, TextWrapped = false,
	Size = UDim2.new(1, -myUGCIconX, 1, 0), Position = UDim2.fromOffset(myUGCIconX, 0) })
local myUGCGrid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, myUGCCard)
local myUGCLayout = new("UIGridLayout", { CellSize = UDim2.new(0.2, -5, 0, 90), CellPadding = UDim2.fromOffset(6, 6),
	SortOrder = Enum.SortOrder.LayoutOrder }, myUGCGrid)
local function fitMyUGC()
	local w = myUGCGrid.AbsoluteSize.X
	if w > 0 then myUGCLayout.CellSize = UDim2.new(0.2, -5, 0, math.floor((w - 24) / 5 * 1.3)) end
end
myUGCGrid:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitMyUGC)

local myUGCToken, myUGCAt = 0, -math.huge
local function loadMyUGCs()
	if os.clock() - myUGCAt < 30 then return end
	myUGCAt = os.clock()
	myUGCToken += 1
	local my = myUGCToken
	task.spawn(function()
		local fn = ReplicatedStorage:WaitForChild("GetPublicUGCs", 10)
		local res
		if fn then
			for _ = 1, 6 do
				local ok, r = pcall(fn.InvokeServer, fn, player.UserId)
				if ok and not (type(r) == "table" and r.throttled) then res = r break end
				task.wait(0.5)
			end
		end
		if my ~= myUGCToken then return end
		for _, c in ipairs(myUGCGrid:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		if type(res) ~= "table" or not res.ok then
			myUGCNote.Text = (type(res) == "table" and res.disabled) and "UGC list is disabled."
				or "UGC list unavailable right now."
			myUGCAt = -math.huge   -- on réessaiera à la prochaine ouverture
			return
		end
		local list = res.list or {}
		local total = math.max(tonumber(res.total) or 0, #list)
		if total == 0 then
			myUGCNote.Text = "No UGC redeemed yet. Get your first one in the shop!"
			return
		end
		myUGCNote.Text = total == 1 and "1 UGC redeemed" or (total .. " UGCs redeemed")
		local first = total - #list + 1
		local expanded = false
		local function card(k, i)
			local item = list[i]
			local c = new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 24, 34), BackgroundTransparency = 0.15,
				LayoutOrder = k }, myUGCGrid)
			corner(c, 10)
			new("ImageLabel", { BackgroundTransparency = 1, Image = item.img or "", ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromScale(0.82, 0.62), AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.05) }, c)
			text(c, { Text = "#" .. (first + i - 1), FontFace = F.Heavy, TextSize = 12, TextColor3 = T.Sub,
				TextWrapped = false, Size = UDim2.fromScale(0.5, 0.14), Position = UDim2.fromScale(0.05, 0.02) })
			text(c, { Text = item.n or "UGC", FontFace = F.Bold, TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.fromScale(0.92, 0.26), Position = UDim2.fromScale(0.04, 0.7) })
		end
		local render
		local function toggleCard(label)
			local b = new("TextButton", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.9,
				AutoButtonColor = true, Text = "", LayoutOrder = 100000 }, myUGCGrid)
			corner(b, 10)
			new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.75, Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
			local l = text(b, { Text = label, FontFace = F.Heavy, TextSize = 16, TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(0.9, 0.6),
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
			new("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 8 }, l)
			b.Activated:Connect(function()
				expanded = not expanded
				render()
			end)
		end
		render = function()
			for _, c in ipairs(myUGCGrid:GetChildren()) do
				if c:IsA("GuiObject") then c:Destroy() end
			end
			local n = expanded and #list or math.min(MY_UGC_PREVIEW, #list)
			for k = 1, n do card(k, #list - k + 1) end          -- plus récent en premier
			if #list > MY_UGC_PREVIEW then
				toggleCard(expanded and "Show less" or ("See all\n(%d)"):format(total))
			end
			task.defer(fitMyUGC)
		end
		render()
	end)
end
