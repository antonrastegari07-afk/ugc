-- ============================================================
-- LikeBoardBubbles (LocalScript) — StarterPlayer ▸ StarterPlayerScripts
-- ============================================================
-- Les petites bulles qui montent dans la barre verte des 2 tableaux de likes (Like1 / Like2).
-- Avant : le SERVEUR créait une bulle toutes les 0,3 à 0,8 s sur chaque tableau et l'animait
-- (position + transparence) : chaque image de chaque bulle était envoyée à TOUS les joueurs.
-- Maintenant : exactement la même animation, mais créée chez chaque joueur → rien par le réseau.
-- Le texte, les likes et la barre restent gérés par le serveur (game like billboard in server).
-- ============================================================
local TweenService = game:GetService("TweenService")

-- même bulle que l'ancien spawnBubble du serveur
local function spawnBubble(progressFill)
	if progressFill.AbsoluteSize.X < 15 then return end -- barre vide (likes pas encore chargés)
	local bubble = Instance.new("Frame")
	local size = math.random(4, 10)
	bubble.Size = UDim2.new(0, size, 0, size)
	bubble.Position = UDim2.new(math.random(5, 95) / 100, 0, 1, math.random(0, 5))
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bubble.BackgroundTransparency = math.random(30, 60) / 100
	bubble.BorderSizePixel = 0
	bubble.ZIndex = 3
	bubble.Parent = progressFill

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(1, 0)
	bCorner.Parent = bubble

	local glow = Instance.new("UIStroke")
	glow.Color = Color3.fromRGB(255, 255, 255)
	glow.Transparency = 0.7
	glow.Thickness = 1
	glow.Parent = bubble

	local duration = math.random(18, 32) / 10
	local drift    = math.random(-8, 8) / 100
	local startX   = bubble.Position.X.Scale

	local riseTween = TweenService:Create(
		bubble,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Position = UDim2.new(startX + drift, 0, -0.1, 0), BackgroundTransparency = 1 }
	)
	riseTween:Play()
	riseTween.Completed:Connect(function() bubble:Destroy() end)
end

-- un tableau : on retrouve sa barre (le tableau peut se charger / décharger avec le streaming)
local function runBoard(modelName, partName)
	task.spawn(function()
		local fill
		while true do
			task.wait(math.random(3, 8) / 10)
			if not (fill and fill.Parent) then
				local model = workspace:FindFirstChild(modelName)
				local part = model and model:FindFirstChild(partName)
				local gui = part and part:FindFirstChild("SurfaceGui")
				fill = gui and gui:FindFirstChild("ProgressFill", true)
			end
			if fill and fill.Parent then
				spawnBubble(fill)
			end
		end
	end)
end

runBoard("Like1", "likepart1")
runBoard("Like2", "likepart2")
