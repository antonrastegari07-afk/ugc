-- RestockInfo — LocalScript à mettre DANS StarterGui ▸ UGCshop ▸ ShopFrame
-- Affiche « UGCs restocked weekly! » en haut du shop, à droite du titre « UGCs »,
-- entre le titre et le bouton X. La position est recalculée à partir du titre et
-- du X : ça reste bien placé sur PC, téléphone et tablette.
local frame = script.Parent
local title = frame:WaitForChild("TextLabel", 10)      -- le titre « UGCs »
local closeBtn = frame:FindFirstChild("ShopToggle")     -- le bouton X
if not title then return end

local TEXT = "🔄 UGCs restocked weekly!"
local COLOR = Color3.fromRGB(255, 215, 90)

local label = Instance.new("TextLabel")
label.Name = "RestockInfo"
label.BackgroundTransparency = 1
label.Text = TEXT
label.TextScaled = true
label.TextWrapped = true
label.FontFace = title.FontFace
label.TextColor3 = COLOR
label.TextStrokeTransparency = 1
label.TextXAlignment = Enum.TextXAlignment.Center
label.AnchorPoint = Vector2.new(0, 0.5)
label.Rotation = title.Rotation
label.ZIndex = title.ZIndex
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(60, 35, 0)
stroke.Parent = label
local maxText = Instance.new("UITextSizeConstraint")
maxText.MaxTextSize = 28
maxText.Parent = label
label.Parent = frame

-- Placement en SCALE (relatif au cadre) : correct même avec un UIScale sur l'UI.
local function place()
	local fs = frame.AbsoluteSize
	if fs.X < 1 or fs.Y < 1 then return end
	local fp = frame.AbsolutePosition
	local tp, ts = title.AbsolutePosition - fp, title.AbsoluteSize
	local gap = fs.X * 0.02
	local left = tp.X + ts.X + gap
	local right = fs.X * 0.62                            -- sans bouton X : on s'arrête là
	if closeBtn then
		local cx = closeBtn.AbsolutePosition.X - fp.X
		if cx > left then right = cx - gap end
	end
	local width = math.max(right - left, fs.X * 0.18)
	local height = math.clamp(ts.Y * 0.5, fs.Y * 0.035, fs.Y * 0.09)
	label.Position = UDim2.fromScale(left / fs.X, (tp.Y + ts.Y / 2) / fs.Y)
	label.Size = UDim2.fromScale(width / fs.X, height / fs.Y)
end

for _, obj in ipairs({ frame, title, closeBtn }) do
	if obj then
		obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		obj:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
	end
end
frame:GetPropertyChangedSignal("Visible"):Connect(function()
	if frame.Visible then task.defer(place) end
end)
task.defer(place)
