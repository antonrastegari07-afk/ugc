-- RestockInfo — LocalScript à mettre DANS StarterGui ▸ UGCshop ▸ ShopFrame
-- Affiche « Restocked weekly! » en blanc, droit :
--   • centré horizontalement sur la colonne du MILIEU des UGC (la 1re rangée de cartes)
--   • centré verticalement entre le haut du cadre principal et le haut de la liste
-- Recalculé tout seul (taille d'écran, cartes créées après coup) : PC, mobile, tablette.
local frame = script.Parent
local title = frame:WaitForChild("TextLabel", 10)          -- le titre « UGCs » (pour la police)
local scroll = frame:WaitForChild("ScrollingFrame", 10)    -- la liste des UGC
if not scroll then return end

local TEXT = "Restocked weekly!"

local label = Instance.new("TextLabel")
label.Name = "RestockInfo"
label.BackgroundTransparency = 1
label.Text = TEXT
label.TextScaled = true
label.TextWrapped = false
label.FontFace = title and title.FontFace or Font.fromEnum(Enum.Font.FredokaOne)
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeTransparency = 1
label.TextXAlignment = Enum.TextXAlignment.Center
label.TextYAlignment = Enum.TextYAlignment.Center
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Rotation = 0
label.ZIndex = 12
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.new(0, 0, 0)
stroke.Parent = label
-- (pas de UITextSizeConstraint : ton shop a un UIScale, une taille max en pixels
--  rendait le texte minuscule. La taille vient uniquement de la case ci-dessous.)
label.Parent = frame

-- Taille du texte : proportionnelle à une carte UGC (et non à l'espace au-dessus de la
-- liste, trop petit dans ton shop → texte minuscule).
local TEXT_HEIGHT = 0.17   -- hauteur du texte = 17 % de la largeur d'une carte (augmente pour plus gros)

-- Centre X + largeur de la carte du milieu de la 1re rangée (sinon : centre de la liste)
local function middleColumnX()
	local cards = {}
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible and c.AbsoluteSize.X > 4 then table.insert(cards, c) end
	end
	if #cards == 0 then return scroll.AbsolutePosition.X + scroll.AbsoluteSize.X / 2, scroll.AbsoluteSize.X / 3.4 end
	local topY = math.huge
	for _, c in ipairs(cards) do topY = math.min(topY, c.AbsolutePosition.Y) end
	local row = {}
	for _, c in ipairs(cards) do
		if math.abs(c.AbsolutePosition.Y - topY) < 4 then table.insert(row, c) end
	end
	table.sort(row, function(a, b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
	local mid = row[math.ceil(#row / 2)]
	return mid.AbsolutePosition.X + mid.AbsoluteSize.X / 2, mid.AbsoluteSize.X
end

-- Placement en SCALE (relatif au cadre) : correct même avec un UIScale sur l'UI.
local function place()
	local fs = frame.AbsoluteSize
	if fs.X < 1 or fs.Y < 1 then return end
	local fp = frame.AbsolutePosition
	local gapTop = scroll.AbsolutePosition.Y - fp.Y            -- du haut du cadre au haut de la liste
	if gapTop < 4 then gapTop = fs.Y * 0.08 end
	local midX, cardW = middleColumnX()
	local cx = midX - fp.X
	local h = math.max(cardW * TEXT_HEIGHT, 12)
	local w = math.min(fs.X * 0.6, h * 9)
	label.Position = UDim2.fromScale(cx / fs.X, (gapTop / 2) / fs.Y)
	label.Size = UDim2.fromScale(w / fs.X, h / fs.Y)
end

for _, obj in ipairs({ frame, scroll }) do
	obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	obj:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
end
scroll.ChildAdded:Connect(function() task.defer(place) end)
scroll.ChildRemoved:Connect(function() task.defer(place) end)
frame:GetPropertyChangedSignal("Visible"):Connect(function()
	if frame.Visible then task.defer(place) end
end)
task.defer(place)
