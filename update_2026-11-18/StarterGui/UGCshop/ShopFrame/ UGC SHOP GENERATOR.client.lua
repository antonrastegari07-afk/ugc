-- ============================================================
-- UGC SHOP GENERATOR - LocalScript avec système de LIKES
-- À placer dans : UGCshop > ShopFrame
-- ============================================================
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService       = game:GetService("SoundService")

local player    = Players.LocalPlayer
local ShopFrame = script.Parent

-- ============================================================
-- CHARGEMENT DE UGC_CONFIG
-- ============================================================
local UGC_CONFIG  = require(ReplicatedStorage:WaitForChild("UGC_CONFIG"))
-- 🏷️ UGC ajoutés sans « Name » : on attend (4 s max) leur nom Roblox avant de construire le shop
if UGC_CONFIG.WaitNames then UGC_CONFIG.WaitNames(4) end
local UGC_ITEMS   = UGC_CONFIG.GetPriceTable()
ReplicatedStorage:WaitForChild("UGCShopOrder", 5)   -- ↕️ ordre choisi dans l'admin
local sortedItems = UGC_CONFIG.GetSortedItems()
-- ❤️ Nombre de likes visible ? (case à cocher dans l'admin)
local function likeCountShown()
	local f = ReplicatedStorage:FindFirstChild("UGCShopOrder")
	return f ~= nil and f:GetAttribute("ShowLikeCount") == true
end

-- ============================================================
-- RÉFÉRENCES
-- ============================================================
local ScrollingFrame = ShopFrame:WaitForChild("ScrollingFrame")
local SelectedFrame  = ShopFrame:WaitForChild("Selected")
local NoUGCSelected  = SelectedFrame:WaitForChild("NoUGCSelected")
local UGCUpdateLabel = SelectedFrame:WaitForChild("UGCupdate")

local TemplateBtn      = ScrollingFrame:WaitForChild("MagicDominusButton")
local TemplateSelected = NoUGCSelected

-- ============================================================
-- REMOTE EVENTS
-- ============================================================
local purchaseUGCEvent        = ReplicatedStorage:WaitForChild("PurchaseUGC")
local promptUGCEvent          = ReplicatedStorage:WaitForChild("PromptUGCPurchase")
local confirmUGCPurchaseEvent = ReplicatedStorage:WaitForChild("ConfirmUGCPurchase")
local UpdateStockEvent        = ReplicatedStorage:WaitForChild("UpdateStockEvent")
local GetStockFunction        = ReplicatedStorage:WaitForChild("GetStockFunction")
local UpdateButtonStateEvent  = ReplicatedStorage:WaitForChild("UpdateButtonStateEvent")

-- ✅ NOUVEAUX REMOTES LIKES
local toggleLikeEvent       = ReplicatedStorage:WaitForChild("ToggleLikeEvent")
local likeUpdateEvent       = ReplicatedStorage:WaitForChild("LikeUpdateEvent")
local requestLikesDataFunc  = ReplicatedStorage:WaitForChild("RequestLikesDataFunction")

-- ============================================================
-- CONFIGURATION GRILLE
-- ============================================================
local COLUMNS   = 3
local BTN_SCALE = 0.28
local GAP_SCALE = (1 - BTN_SCALE * COLUMNS) / (COLUMNS + 1)

-- 🔧 Rate custom du carrousel d'offres pendant que le shop UGC est ouvert
local POINTS_OFFER_DISPLAY_TIME = 5   -- s par offre "points" (séparé du DISPLAY_TIME normal)

-- ============================================================
-- ÉTAT DU SHOP
-- ============================================================
local currentOpenFrame    = nil
local currentActiveButton = nil
local originalBtnColors   = {}
local scrollButtons       = {}
local buttonFrames        = {}
-- 🩹 place ACTUELLE de chaque bouton dans la grille + son animation de survol en cours.
--    Avant, l'animation retenait la place du 1er survol : après une réorganisation (stock
--    épuisé, ordre changé), survoler ou cliquer renvoyait le bouton à son ANCIENNE place.
local gridBase            = {}   -- [outerFrame] = { pos = UDim2, size = UDim2 }
local hoverTween          = {}   -- [outerFrame] = Tween
local newBadges           = {}   -- [ButtonName] = badge NEW
local ugcStockState       = {}
local ugcGradients        = {}

-- 👁️ VISIBILITÉ DES UGC (drapeau publié par UGCSalesLock)
--
--    ⚠️ Déclarée ICI, et pas plus bas : `reorganizeGrid` s'en sert, et en Lua
--    une fonction locale définie APRÈS son utilisation est lue comme une
--    globale — donc nil, donc le shop plante à la première réorganisation.
local visFlag = ReplicatedStorage:FindFirstChild("UGCSalesLock")

local function ugcHidden(assetId)
	if not visFlag then
		visFlag = ReplicatedStorage:FindFirstChild("UGCSalesLock")
		if not visFlag then return false end   -- script serveur absent → tout visible
	end
	return visFlag:GetAttribute("Hide_" .. tostring(assetId)) == true
end

local comingSoonLabel = nil
local function placeComingSoon(sfW, btnPx, gapPx, totalRows)
	if not comingSoonLabel then return 0 end
	local labelH = btnPx * 0.09
	local labelY = gapPx + totalRows * (btnPx + gapPx)
	comingSoonLabel.Position = UDim2.new(0.1, 0, 0, labelY)
	comingSoonLabel.Size     = UDim2.new(0.8, 0, 0, labelH)
	return labelH + gapPx -- hauteur à ajouter au canvas
end

-- ============================================================
-- ÉTAT DES LIKES
-- ============================================================
local likedByPlayer    = {}   -- [assetId] = bool
local likeCounts       = {}   -- [assetId] = number
local likeButtons      = {}   -- [assetId] = TextButton (heart)
local likeCountLabels  = {}   -- [assetId] = TextLabel
local likesDataLoaded  = false
local pendingLikeToggle = {}  -- [assetId] = tick() (anti-double-click client)
local CLIENT_LIKE_COOLDOWN = 0.5

-- ============================================================
-- UTILITAIRES
-- ============================================================
local function formatNumber(num)
	if num >= 1000000 then
		return string.format("%.1fM", num / 1000000)
	elseif num >= 1000 then
		return string.format("%.1fK", num / 1000)
	else
		return tostring(num)
	end
end

-- ========================================
-- 🪙 PIÈCE DEVANT LE PRIX (bouton d'achat)
--
--   Roblox ne sait pas insérer d'image dans un texte : le RichText n'a pas de
--   balise <img>. Il faut donc un vrai ImageLabel posé à côté du nombre.
--
--   Pour que « pièce + prix » reste centré dans le bouton, on réserve la
--   largeur de la pièce à gauche avec un UIPadding : le texte se recentre
--   alors tout seul dans ce qui reste, et l'ensemble retombe pile au milieu.
--   La pièce, elle, est positionnée à partir de la largeur RÉELLE du texte
--   (TextBounds), donc ça marche à n'importe quelle taille de bouton.
-- ========================================
-- Prix en toutes lettres sur le bouton : 2000000 → « 2,000,000 ».
--
-- Volontairement séparé de `formatNumber`, qui reste en 2.0M pour les
-- notifications et le panneau de vérification : sur un bandeau qui s'affiche
-- deux secondes, la forme courte se lit d'un coup d'œil. Sur un bouton
-- d'achat, on veut au contraire voir le prix exact avant de payer.
local function formatFullPrice(n)
	local s = tostring(math.floor(tonumber(n) or 0))

	-- Une virgule tous les 3 chiffres, en partant de la droite : on retourne
	-- la chaîne, on découpe par paquets de 3, puis on la remet à l'endroit.
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end   -- ex. 100 → ",100"
	return out
end
local TextService = game:GetService("TextService")

local COIN_IMAGE  = "rbxassetid://109902708234199"   -- même pièce que le billboard
local COIN_SCALE  = 0.70   -- taille de la pièce, en fraction de la hauteur du bouton
local COIN_GAP    = 0.12   -- écart pièce ↔ prix, en fraction de la taille de la pièce
local TEXT_SCALE  = 0.52   -- taille du prix, en fraction de la hauteur du bouton
local SIDE_MARGIN = 0.06   -- marge minimale à gauche et à droite, en fraction de la largeur

-- Prix en toutes lettres : 2000000 → « 2,000,000 »
local function formatFullPrice(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return out
end

-- ========================================
-- 🪙 PIÈCE + PRIX SUR LE BOUTON D'ACHAT
--
--   Roblox n'a pas de balise image dans le RichText : il faut un vrai
--   ImageLabel. Le piège, c'est le centrage.
--
--   Plutôt que de calculer des positions — ce qui dépend de la façon dont ton
--   template place son label — on pose une rangée horizontale centrée sur le
--   BOUTON. C'est Roblox qui centre, donc c'est juste quel que soit ton
--   template.
--
--   Le label d'origine est cloné (police, couleur, contour, dégradé suivent)
--   puis masqué : ton style est conservé au pixel près.
-- ========================================
local function attachPriceCoin(priceLabel, priceText)
	local button = priceLabel.Parent
	if not button then return end

	priceLabel.Visible = false   -- gardé comme modèle de style, plus affiché

	local row = button:FindFirstChild("PriceRow")
	local coin, txt, list

	if row then
		list = row:FindFirstChildOfClass("UIListLayout")
		coin = row:FindFirstChild("Coin")
		txt  = row:FindFirstChild("Amount")
	else
		row = Instance.new("Frame")
		row.Name                   = "PriceRow"
		row.BackgroundTransparency = 1
		row.Size                   = UDim2.new(1, 0, 1, 0)
		row.Position               = UDim2.new(0, 0, 0, 0)
		row.ZIndex                 = priceLabel.ZIndex + 1
		row.Parent                 = button

		-- 🎯 C'est CETTE ligne qui centre. Aucun calcul, aucune hypothèse.
		list = Instance.new("UIListLayout")
		list.FillDirection       = Enum.FillDirection.Horizontal
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment   = Enum.VerticalAlignment.Center
		list.SortOrder           = Enum.SortOrder.LayoutOrder
		list.Parent              = row

		coin = Instance.new("ImageLabel")
		coin.Name                   = "Coin"
		coin.LayoutOrder            = 1
		coin.BackgroundTransparency = 1
		coin.Image                  = COIN_IMAGE
		coin.ScaleType              = Enum.ScaleType.Fit
		coin.Size                   = UDim2.new(0, 20, 0, 20)
		coin.ZIndex                 = row.ZIndex + 1
		coin.Parent                 = row

		-- Clone : on récupère d'un coup la police, la couleur, le UIStroke et
		-- le UIGradient de ton bouton, sans avoir à les recopier un par un.
		txt = priceLabel:Clone()
		txt.Name           = "Amount"
		txt.LayoutOrder    = 2
		txt.Visible        = true
		txt.AnchorPoint    = Vector2.new(0, 0)
		txt.Position       = UDim2.new(0, 0, 0, 0)
		txt.Size           = UDim2.new(0, 10, 1, 0)
		txt.TextScaled     = false          -- incompatible avec AutomaticSize
		txt.TextWrapped    = false
		txt.AutomaticSize  = Enum.AutomaticSize.X
		txt.TextXAlignment = Enum.TextXAlignment.Center
		txt.TextYAlignment = Enum.TextYAlignment.Center
		txt.ZIndex         = row.ZIndex + 1

		-- Une marge ou une contrainte héritée fausserait la largeur automatique
		for _, c in ipairs(txt:GetChildren()) do
			if c:IsA("UIPadding") or c:IsA("UIAspectRatioConstraint")
				or c:IsA("UISizeConstraint") then
				c:Destroy()
			end
		end
		txt.Parent = row
	end

	txt.Text = priceText

	local function refresh()
		local w, h = button.AbsoluteSize.X, button.AbsoluteSize.Y
		if w <= 1 or h <= 1 then return end

		local size = math.floor(h * COIN_SCALE)
		local gap  = math.max(2, math.floor(size * COIN_GAP))

		coin.Size    = UDim2.new(0, size, 0, size)
		list.Padding = UDim.new(0, gap)

		-- Taille du texte : on part d'une fraction de la hauteur, puis on
		-- réduit tant que « pièce + écart + prix » dépasse la place dispo.
		-- TextService donne la largeur exacte, donc ça tombe juste du premier
		-- coup dans la quasi-totalité des cas.
		local avail = w - size - gap - math.floor(w * SIDE_MARGIN * 2)
		local ts = math.max(8, math.floor(h * TEXT_SCALE))

		while ts > 8 do
			local m = TextService:GetTextSize(txt.Text, ts, txt.Font, Vector2.new(10000, 10000))
			if m.X <= avail then break end
			ts = ts - 1
		end
		txt.TextSize = ts
	end

	refresh()
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	task.defer(refresh)
end

-- ============================================================
-- ATTENDRE UNE TAILLE VALIDE DU SCROLLINGFRAME
-- ============================================================
local function waitForValidSize(timeout)
	timeout = timeout or 5
	local elapsed = 0
	while ScrollingFrame.AbsoluteSize.X <= 1 and elapsed < timeout do
		task.wait(0.05)
		elapsed += 0.05
	end
	return ScrollingFrame.AbsoluteSize.X > 1
end

-- ============================================================
-- PLAY CLICK EFFECT
-- ============================================================
local function playClickEffect(targetFrame)
	if not targetFrame then return end
	local flash = Instance.new("Frame")
	flash.Name                   = "ClickFlash"
	flash.Size                   = UDim2.new(1, 6, 1, 6)
	flash.Position               = UDim2.new(0, -3, 0, -3)
	flash.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
	flash.BackgroundTransparency = 0.25
	flash.BorderSizePixel        = 0
	flash.ZIndex                 = 20
	flash.Parent                 = targetFrame
	local existingCorner = targetFrame:FindFirstChildOfClass("UICorner")
	local co = Instance.new("UICorner")
	co.CornerRadius = existingCorner and existingCorner.CornerRadius or UDim.new(0, 8)
	co.Parent = flash
	TweenService:Create(flash,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	):Play()
	task.delay(0.4, function()
		if flash and flash.Parent then flash:Destroy() end
	end)
end

-- ============================================================
-- SÉLECTION DES FRAMES
-- ============================================================
local function closeAllFrames()
	for _, child in pairs(SelectedFrame:GetChildren()) do
		if child:IsA("Frame") then child.Visible = false end
	end
	currentOpenFrame = nil
end

-- 🎨 COULEUR DES CARTES : UNE seule fonction décide, pour TOUTES les cartes.
--    🩹 Avant, la mise à jour du stock (envoyée par le serveur de temps en temps) remettait la
--    couleur d'origine même sur la carte SÉLECTIONNÉE → le vert disparaissait tout seul ; et
--    l'ancienne carte n'était pas toujours remise (épuisée / pas épuisée mal détecté).
--    Maintenant : sélectionnée = vert, épuisée = gris, sinon couleur d'origine, et chaque
--    changement repeint toutes les cartes (il y en a peu : rien de coûteux).
local cardGray = {}   -- [imgBtn] = { stock = épuisé d'après le stock, inactive = désactivée }
local function paintCard(imgBtn)
	if not imgBtn then return end
	local g = cardGray[imgBtn]
	if imgBtn == currentActiveButton then
		imgBtn.BackgroundColor3 = Color3.fromRGB(97, 194, 81)
	elseif g and (g.stock or g.inactive) then
		imgBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	elseif originalBtnColors[imgBtn] then
		imgBtn.BackgroundColor3 = originalBtnColors[imgBtn]
	end
end
local function paintAllCards()
	for _, b in pairs(scrollButtons) do paintCard(b) end
end
local function setCardGray(imgBtn, key, on)
	if not imgBtn then return end
	local g = cardGray[imgBtn]
	if not g then g = {}; cardGray[imgBtn] = g end
	g[key] = on == true
	paintCard(imgBtn)
end

local function openFrame(frameName, imgBtn)
	closeAllFrames()
	local frameToOpen = SelectedFrame:FindFirstChild(frameName)
	if frameToOpen then
		frameToOpen.Visible     = true
		currentOpenFrame        = frameToOpen
		UGCUpdateLabel.Text     = frameName
		currentActiveButton     = imgBtn
	else
		warn("Frame '" .. frameName .. "' introuvable dans Selected!")
		NoUGCSelected.Visible = true
		UGCUpdateLabel.Text   = "No Selection"
		currentActiveButton   = nil
	end
	paintAllCards()   -- l'ancienne carte perd TOUJOURS son vert, la nouvelle le prend
end

local function resetToNoSelection()
	closeAllFrames()
	if currentActiveButton then
		currentActiveButton = nil
		paintAllCards()
	end
	NoUGCSelected.Visible = true
	UGCUpdateLabel.Text   = "No Selection"
end

-- ⭐ MOINS DE FRICTION : à l'ouverture du shop, le 1er UGC de la grille est DÉJÀ choisi
--    (sa fiche et son bouton Buy sont affichés, sa carte est en vert). Le 1er encore en
--    vente passe avant un épuisé. Rien n'est changé si le joueur a déjà choisi un UGC.
local function selectFirstUGC()
	if currentActiveButton and currentActiveButton.Parent then
		local fr = currentActiveButton.Parent
		if fr.Visible then return end   -- son choix est toujours là : on le garde
	end
	local best, bestKey
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		local fr, btn = buttonFrames[ugc.ButtonName], scrollButtons[ugc.ButtonName]
		local gb = fr and gridBase[fr]
		if btn and fr and fr.Parent and fr.Visible and gb then
			-- clé de tri : en vente d'abord, puis la ligne, puis la colonne de la grille
			local soldOut = ugcStockState[ugc.ButtonName] == false and 1 or 0
			local key = soldOut * 1e9 + gb.pos.Y.Offset * 10 + gb.pos.X.Scale
			if not bestKey or key < bestKey then best, bestKey = { ugc = ugc, btn = btn }, key end
		end
	end
	if best then openFrame(best.ugc.FrameName, best.btn) end
end

-- ============================================================
-- NOTIFICATION
-- ============================================================
local function showNotification(message, isError)
	pcall(function()
		local gui = player:WaitForChild("PlayerGui")
		local old = gui:FindFirstChild("UGCNotification")
		if old then old:Destroy() end
		local sg = Instance.new("ScreenGui")
		sg.Name = "UGCNotification" ; sg.ResetOnSpawn = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling ; sg.Parent = gui
		local fr = Instance.new("Frame")
		fr.Size = UDim2.new(0,450,0,120) ; fr.Position = UDim2.new(0.5,0,0.5,0)
		fr.AnchorPoint = Vector2.new(0.5,0.5) ; fr.BackgroundColor3 = Color3.fromRGB(20,20,20)
		fr.BackgroundTransparency = 0.3 ; fr.BorderSizePixel = 0 ; fr.Parent = sg
		local co = Instance.new("UICorner") ; co.CornerRadius = UDim.new(0,15) ; co.Parent = fr
		local st = Instance.new("UIStroke")
		st.Color = isError and Color3.fromRGB(255,85,85) or Color3.fromRGB(85,255,127)
		st.Thickness = 3 ; st.Parent = fr
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.new(1,-20,1,-20) ; tl.Position = UDim2.new(0,10,0,10)
		tl.BackgroundTransparency = 1 ; tl.Text = message
		tl.TextColor3 = isError and Color3.fromRGB(255,100,100) or Color3.fromRGB(100,255,150)
		tl.TextStrokeColor3 = Color3.new(0,0,0) ; tl.TextStrokeTransparency = 0.5
		tl.Font = Enum.Font.GothamBold ; tl.TextSize = 24
		tl.TextWrapped = true ; tl.Parent = fr
		fr.Size = UDim2.new(0,0,0,0)
		TweenService:Create(fr,
			TweenInfo.new(0.4,Enum.EasingStyle.Bounce,Enum.EasingDirection.Out),
			{Size=UDim2.new(0,450,0,120)}):Play()
		task.delay(2.5, function()
			if not sg.Parent then return end
			local fi = TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
			TweenService:Create(fr,fi,{BackgroundTransparency=1,Size=UDim2.new(0,450,0,80)}):Play()
			TweenService:Create(tl,fi,{TextTransparency=1,TextStrokeTransparency=1}):Play()
			local bf = TweenService:Create(st,fi,{Transparency=1}) ; bf:Play()
			bf.Completed:Connect(function() sg:Destroy() end)
		end)
	end)
end

-- ============================================================
-- CONFETTIS
-- ============================================================
local function createConfetti(sourceBtn)
	pcall(function()
		local sg = sourceBtn:FindFirstAncestorOfClass("ScreenGui")
		if not sg then return end
		local ap = sourceBtn.AbsolutePosition ; local as = sourceBtn.AbsoluteSize
		for _ = 1, 30 do
			local c = Instance.new("Frame")
			c.Size = UDim2.new(0,math.random(5,15),0,math.random(5,15))
			c.Position = UDim2.fromOffset(ap.X+as.X/2, ap.Y+as.Y/2)
			c.AnchorPoint = Vector2.new(0.5,0.5)
			c.BackgroundColor3 = Color3.fromHSV(math.random(),1,1)
			c.BorderSizePixel = 0 ; c.Parent = sg
			local a = math.random()*math.pi*2 ; local d = math.random(100,300)
			local t = TweenService:Create(c,
				TweenInfo.new(1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{
					Position=UDim2.fromOffset(ap.X+as.X/2+math.cos(a)*d, ap.Y+as.Y/2+math.sin(a)*d),
					Rotation=math.random(-180,180), BackgroundTransparency=1})
			t:Play()
			task.delay(1, function() c:Destroy() end)
		end
	end)
end

-- ============================================================
-- GRADIENT ANIMÉ
-- ============================================================
local function attachGradient(targetFrame, isEmpty)
	for _, child in pairs(targetFrame:GetChildren()) do
		if child:IsA("UIGradient") then child:Destroy() end
		if child:IsA("LocalScript") and child.Name == "LocalScript" then child:Destroy() end
	end
	local g = Instance.new("UIGradient")
	if isEmpty then
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(80,  80,  85)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(110, 110, 115)),
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(75,  75,  80)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(100, 100, 105)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(80,  80,  85)),
		})
		g.Rotation = 0
	else
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(78,  200, 247)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(199, 210, 255)),
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(72,  194, 247)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(188, 202, 255)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(74,  201, 247)),
		})
		g.Rotation = 0
		TweenService:Create(g,
			TweenInfo.new(17, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 0),
			{Rotation = 360}):Play()
	end
	g.Parent = targetFrame
	return g
end

-- ============================================================
-- 🆕 SYSTÈME DE LIKES — UI ET ANIMATION
-- ============================================================
local PINK_LIGHT    = Color3.fromRGB(255, 182, 213)
local PINK_BRIGHT   = Color3.fromRGB(255, 90,  150)
local PINK_DEEP     = Color3.fromRGB(220, 40,  100)
local PINK_OUTLINE  = Color3.fromRGB(255, 150, 190)  -- ✅ Contour rose pour cœur non liké

-- Palette stock (gradient dynamique selon disponibilité)
local STOCK_GREEN_LIGHT   = Color3.fromRGB(150, 255, 180)
local STOCK_GREEN_BRIGHT  = Color3.fromRGB(40,  220, 100)
local STOCK_GREEN_DEEP    = Color3.fromRGB(50, 196, 62)
local STOCK_ORANGE_LIGHT  = Color3.fromRGB(255, 210, 140)
local STOCK_ORANGE_BRIGHT = Color3.fromRGB(255, 165, 60)
local STOCK_ORANGE_DEEP   = Color3.fromRGB(180, 90,  20)
local STOCK_RED_LIGHT     = Color3.fromRGB(255, 140, 140)
local STOCK_RED_BRIGHT    = Color3.fromRGB(255, 50,  50)
local STOCK_RED_DEEP      = Color3.fromRGB(150, 20,  20)

-- Met à jour l'affichage du coeur + compteur pour un AssetId donné
local function refreshLikeUI(assetId)
	local heartBtn = likeButtons[assetId]
	local countLbl = likeCountLabels[assetId]
	if not heartBtn or not countLbl then return end
	local liked = likedByPlayer[assetId] == true
	local count = likeCounts[assetId] or 0
	-- ⚠️ TOUJOURS ♥ (U+2665). Le ♡ (U+2661) n'existe pas dans FredokaOne :
	--    Roblox dessine alors le rectangle "glyphe manquant" = le carré gris.
	--    L'état non-liké se rend par la transparence, pas par un autre caractère.
	heartBtn.Text = "♥"
	local hStroke = heartBtn:FindFirstChildOfClass("UIStroke")
	if liked then
		heartBtn.TextColor3       = PINK_BRIGHT
		heartBtn.TextTransparency = 0
		if hStroke then hStroke.Color = PINK_DEEP    ; hStroke.Transparency = 0    end
	else
		heartBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
		heartBtn.TextTransparency = 0.62   -- cœur "creux" : seul le contour rose ressort
		if hStroke then hStroke.Color = PINK_OUTLINE ; hStroke.Transparency = 0.15 end
	end
	countLbl.Text = formatNumber(count)
end

-- Cache des tailles d'origine (pour rebondir à la BONNE taille)
local heartOriginalSizes = {}

-- Animation bounce du coeur (style Instagram)
local function bounceHeart(heartBtn)
	if not heartBtn or not heartBtn.Parent then return end
	heartBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Capturer la taille d'origine au 1er passage
	if not heartOriginalSizes[heartBtn] then
		heartOriginalSizes[heartBtn] = heartBtn.Size
	end
	local origSize = heartOriginalSizes[heartBtn]
	-- Taille "pop" = 1.45× la taille d'origine
	local bigSize = UDim2.new(
		origSize.X.Scale  * 1.45, origSize.X.Offset * 1.45,
		origSize.Y.Scale  * 1.45, origSize.Y.Offset * 1.45
	)
	local popBig = TweenService:Create(
		heartBtn,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = bigSize}
	)
	popBig:Play()
	popBig.Completed:Connect(function()
		if not heartBtn or not heartBtn.Parent then return end
		TweenService:Create(
			heartBtn,
			TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
			{Size = origSize}   -- ✅ retour à la taille d'origine, pas 1×1
		):Play()
	end)
end

-- Petit flash heart particle (effet plaisant au like)
local function spawnHeartParticle(heartBtn)
	if not heartBtn or not heartBtn.Parent then return end
	pcall(function()
		local sg = heartBtn:FindFirstAncestorOfClass("ScreenGui")
		if not sg then return end
		local ap = heartBtn.AbsolutePosition
		local as = heartBtn.AbsoluteSize
		local p = Instance.new("TextLabel")
		p.Name                   = "HeartParticle"
		p.Size                   = UDim2.fromOffset(as.X * 0.8, as.Y * 0.8)
		p.Position               = UDim2.fromOffset(ap.X + as.X/2, ap.Y + as.Y/2)
		p.AnchorPoint            = Vector2.new(0.5, 0.5)
		p.BackgroundTransparency = 1
		p.Text                   = "♥"
		p.TextColor3             = PINK_BRIGHT
		p.Font                   = Enum.Font.SourceSansBold   -- FredokaOne n'a pas le ♥
		p.TextScaled             = true
		p.ZIndex                 = 50
		p.Parent                 = sg
		local stroke = Instance.new("UIStroke")
		stroke.Color = PINK_DEEP
		stroke.Thickness = 2
		stroke.Parent = p
		TweenService:Create(p,
			TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromOffset(ap.X + as.X/2, ap.Y + as.Y/2 - 60),
				TextTransparency = 1,
				Size = UDim2.fromOffset(as.X * 1.4, as.Y * 1.4),
			}
		):Play()
		TweenService:Create(stroke,
			TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 1}
		):Play()
		task.delay(0.7, function()
			if p and p.Parent then p:Destroy() end
		end)
	end)
end

-- Toggle d'un like (avec optimistic UI)
local function onHeartClick(assetId)
	local now = tick()
	-- Anti-double-click client
	if pendingLikeToggle[assetId] and (now - pendingLikeToggle[assetId]) < CLIENT_LIKE_COOLDOWN then
		return
	end
	pendingLikeToggle[assetId] = now
	-- Optimistic update
	local wasLiked = likedByPlayer[assetId] == true
	likedByPlayer[assetId] = not wasLiked
	likeCounts[assetId] = math.max(0, (likeCounts[assetId] or 0) + (wasLiked and -1 or 1))
	refreshLikeUI(assetId)
	local heartBtn = likeButtons[assetId]
	if heartBtn then
		bounceHeart(heartBtn)
		if not wasLiked then
			-- On vient de liker → petite particule qui s'envole
			spawnHeartParticle(heartBtn)
		end
	end
	-- Envoi serveur (le serveur a le dernier mot et nous renverra LikeUpdateEvent)
	pcall(function()
		toggleLikeEvent:FireServer(assetId)
	end)
end

-- Mises à jour serveur (autres joueurs OU rate-limit OU resync multi-serveur)
likeUpdateEvent.OnClientEvent:Connect(function(assetId, newState, newCount)
	if type(assetId) ~= "number" then return end
	if newState ~= nil then
		likedByPlayer[assetId] = newState
	end
	if type(newCount) == "number" then
		likeCounts[assetId] = newCount
	end
	refreshLikeUI(assetId)
end)

-- Récupère les données likes au 1er ouverture du shop
local function fetchLikesDataOnce()
	if likesDataLoaded then return end
	task.spawn(function()
		local ok, data = pcall(function()
			return requestLikesDataFunc:InvokeServer()
		end)
		if ok and type(data) == "table" then
			-- player likes
			for assetKey, _ in pairs(data.playerLikes or {}) do
				local id = tonumber(assetKey)
				if id then likedByPlayer[id] = true end
			end
			-- global counts
			for assetKey, count in pairs(data.globalCounts or {}) do
				local id = tonumber(assetKey)
				if id and type(count) == "number" then
					likeCounts[id] = count
				end
			end
			-- Rafraîchir toutes les UI déjà créées
			for assetId in pairs(likeButtons) do
				refreshLikeUI(assetId)
			end
			likesDataLoaded = true
		else
			warn("⚠️ [LIKES] Impossible de charger les likes : " .. tostring(data))
		end
	end)
end

-- ============================================================
-- 🔎 FILTRE / TRI DU SHOP (bouton FILTER en haut à droite de la grille)
--   Tout se passe chez le joueur : aucun appel serveur, aucun DataStore.
--   Déclaré ICI : reorganizeGrid (juste en dessous) s'en sert.
-- ============================================================
local SF = {
	f = { avail = false, sold = false, low = false, owned = false, notOwned = false, new = false, types = {} },
	sort = "default",   -- default · price_desc · price_asc · left_desc · left_asc (stock RESTANT)
	cur = {},           -- [assetId] = stock restant (rempli par la logique de stock)
	total = {},         -- [assetId] = stock total
	ownedMap = {},      -- [assetId] = true/false (lu une fois sur Roblox)
	typeOf = {},        -- [assetId] = "Hat" / "Hair"… (lu une fois sur Roblox)
	LOW_RATIO = 0.3,    -- « Few left » = 30 % du total ou moins (même seuil que la pastille orange)
}
function SF.isNew(ugc)
	if UGC_CONFIG.IsNew then return UGC_CONFIG.IsNew(ugc) == true end
	return ugc.IsNew == true
end
function SF.count()
	local f, n = SF.f, 0
	for _, k in ipairs({ "avail", "sold", "low", "owned", "notOwned", "new" }) do if f[k] then n += 1 end end
	for _ in pairs(f.types) do n += 1 end
	if SF.sort ~= "default" then n += 1 end
	return n
end
function SF.pass(ugc)
	local f, id = SF.f, ugc.AssetId
	local active = ugcStockState[ugc.ButtonName] ~= false
	if f.avail or f.sold or f.low then
		local cur, tot = SF.cur[id], SF.total[id]
		local low = active and cur and tot and tot > 0 and cur > 0 and cur <= tot * SF.LOW_RATIO
		if not ((f.avail and active) or (f.sold and not active) or (f.low and low)) then return false end
	end
	if f.owned or f.notOwned then
		local o = SF.ownedMap[id]   -- nil = pas encore vérifié : caché le temps de la vérification
		if not ((f.owned and o == true) or (f.notOwned and o == false)) then return false end
	end
	if next(f.types) and not f.types[SF.typeOf[id] or "Other"] then return false end
	if f.new and not SF.isNew(ugc) then return false end
	return true
end
-- stock RESTANT (ce qu'on peut encore acheter) ; épuisé = 0 ; inconnu = nil (rangé à la fin)
local function leftStockOf(ugc)
	if ugcStockState[ugc.ButtonName] == false then return 0 end
	return SF.cur[ugc.AssetId]
end
-- Filtre + tri de la liste prête à afficher (les UGC filtrés sont cachés)
function SF.apply(list)
	local out, rank = {}, {}
	for i, ugc in ipairs(list) do
		if SF.pass(ugc) then
			table.insert(out, ugc)
			rank[ugc] = i
		else
			local fr = buttonFrames[ugc.ButtonName]
			if fr then fr.Visible = false end
		end
	end
	local s = SF.sort
	if s ~= "default" then
		table.sort(out, function(a, b)
			local ka, kb
			if s == "price_desc" or s == "price_asc" then ka, kb = a.Price or 0, b.Price or 0
			else
				ka, kb = leftStockOf(a), leftStockOf(b)
				-- « Low stock » : les ÉPUISÉS (0) vont à la fin → en premier, ceux où il en reste le moins
				if s == "left_asc" then
					if ka == 0 then ka = math.huge end
					if kb == 0 then kb = math.huge end
				end
			end
			if ka == nil or kb == nil then   -- stock pas encore connu : à la fin, dans l'ordre du shop
				if (ka == nil) ~= (kb == nil) then return kb == nil end
				return rank[a] < rank[b]
			end
			if ka ~= kb then
				if s == "price_desc" or s == "left_desc" then return ka > kb end
				return ka < kb
			end
			return rank[a] < rank[b]   -- à égalité : l'ordre du shop
		end)
	end
	if SF.onRender then task.defer(SF.onRender, #out) end
	return out
end

-- ============================================================
-- RÉORGANISATION DE LA GRILLE
-- ============================================================
local function reorganizeGrid()
	task.spawn(function()
		task.wait()
		local elapsed = 0
		while ScrollingFrame.AbsoluteSize.X <= 1 and elapsed < 3 do
			task.wait(0.05)
			elapsed += 0.05
		end
		local sfW = ScrollingFrame.AbsoluteSize.X
		if sfW <= 1 then
			warn("[UGCShopGenerator] reorganizeGrid: AbsoluteSize invalide, abandon.")
			return
		end
		local btnPx = sfW * BTN_SCALE
		local gapPx = sfW * GAP_SCALE
		local available = {}
		local exhausted = {}

		for _, ugc in ipairs(sortedItems) do
			local frame = buttonFrames[ugc.ButtonName]

			if ugcHidden(ugc.AssetId) then
				-- 👁️ Masqué : on ne le détruit pas, on le sort de la grille.
				--    Il retrouvera sa place exacte dès que tu le réactives,
				--    sans que le joueur ait à recharger quoi que ce soit.
				if frame then frame.Visible = false end
			elseif ugcStockState[ugc.ButtonName] == false then
				if frame then frame.Visible = true end
				table.insert(exhausted, ugc)
			else
				if frame then frame.Visible = true end
				table.insert(available, ugc)
			end
		end
		local finalOrder = {}
		for _, ugc in ipairs(available) do table.insert(finalOrder, ugc) end
		for _, ugc in ipairs(exhausted) do table.insert(finalOrder, ugc) end
		finalOrder = SF.apply(finalOrder)   -- 🔎 filtre / tri choisis par le joueur
		local totalRows = math.ceil(#finalOrder / COLUMNS)
		local totalHeight = gapPx + totalRows * (btnPx + gapPx)
		totalHeight += placeComingSoon(sfW, btnPx, gapPx, totalRows)
		ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
		local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for gridIdx, ugc in ipairs(finalOrder) do
			local idx = gridIdx - 1
			local col = idx % COLUMNS
			local row = math.floor(idx / COLUMNS)
			local posX = GAP_SCALE + col * (BTN_SCALE + GAP_SCALE)
			local posY = gapPx + row * (btnPx + gapPx)
			local btn = buttonFrames[ugc.ButtonName]
			if btn then
				local pos, size = UDim2.new(posX, 0, 0, posY), UDim2.new(BTN_SCALE, 0, 0, btnPx)
				gridBase[btn] = { pos = pos, size = size }   -- 🩹 nouvelle place retenue pour le survol
				if hoverTween[btn] then hoverTween[btn]:Cancel(); hoverTween[btn] = nil end
				TweenService:Create(btn, tweenInfo, { Position = pos, Size = size }):Play()
			end
		end
	end)
end

-- ============================================================
-- METTRE À JOUR L'ÉTAT D'UN BOUTON
-- ============================================================
local function setButtonStockState(buttonName, isActive, skipReorganize)
	local wasActive = ugcStockState[buttonName]
	ugcStockState[buttonName] = isActive
	setCardGray(scrollButtons[buttonName], "inactive", isActive == false)
	local outerFrame = buttonFrames[buttonName]
	if not outerFrame then return end
	attachGradient(outerFrame, not isActive)
	if not skipReorganize and wasActive ~= isActive then
		reorganizeGrid()
	end
end

-- ============================================================
-- ANIMATION BOUTON
-- ============================================================
local function attachButtonAnimation(imgBtn, outerFrame)
	for _, child in pairs(imgBtn:GetChildren()) do
		if child:IsA("LocalScript") and child.Name == "button animation" then
			child:Destroy()
		end
	end
	local origSize, origPos
	local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function capture()
		-- 🩹 la place est relue à CHAQUE fois : celle que la grille vient de donner
		local b = gridBase[outerFrame]
		if b then
			origSize, origPos = b.size, b.pos
		elseif not origSize then
			origSize = outerFrame.Size
			origPos  = outerFrame.Position
		end
	end
	local function scaleTo(s)
		capture()
		local anchor = outerFrame.AnchorPoint
		local ns = UDim2.new(
			origSize.X.Scale*s,  origSize.X.Offset*s,
			origSize.Y.Scale*s,  origSize.Y.Offset*s)
		local np
		if anchor.X == 0.5 and anchor.Y == 0.5 then
			np = origPos
		else
			np = UDim2.new(
				origPos.X.Scale  + origSize.X.Scale  *(1-s)/2,
				origPos.X.Offset + origSize.X.Offset *(1-s)/2,
				origPos.Y.Scale  + origSize.Y.Scale  *(1-s)/2,
				origPos.Y.Offset + origSize.Y.Offset *(1-s)/2)
		end
		if hoverTween[outerFrame] then hoverTween[outerFrame]:Cancel() end
		local tw = TweenService:Create(outerFrame, info, {Size=ns, Position=np})
		hoverTween[outerFrame] = tw
		tw:Play()
	end
	outerFrame.Destroying:Connect(function() gridBase[outerFrame], hoverTween[outerFrame] = nil, nil end)
	imgBtn.MouseEnter:Connect(function()       scaleTo(0.9)  end)
	imgBtn.MouseLeave:Connect(function()       scaleTo(1.0)  end)
	imgBtn.MouseButton1Down:Connect(function() scaleTo(0.85) end)
	imgBtn.MouseButton1Up:Connect(function()   scaleTo(0.9)  end)
end

-- ============================================================
-- LOGIQUE D'ACHAT
-- ============================================================
local isProcessing = {}
local confirmedPurchases = {}

-- ⏳ ÉTAT DE VÉRIFICATION
--    Le serveur refuse de toute façon tout nouvel achat pendant ce temps.
--    Le verrou client sert uniquement à expliquer au joueur, jamais à
--    sécuriser : un exploiteur qui le contourne se fait refuser côté serveur.
local verifying = { active = false, endsAt = 0, token = 0, amount = 0, gui = nil }

local function verifyPanelSize()
	local cam = workspace.CurrentCamera
	local vp  = (cam and cam.ViewportSize.Y > 1) and cam.ViewportSize or Vector2.new(1280, 720)
	local w   = math.min(vp.X * 0.92, 430)
	local h   = math.clamp(vp.Y * 0.155, 84, 116)
	return w, h
end

local function closeVerifyPanel()
	verifying.active = false
	verifying.amount = 0
	verifying.token  = verifying.token + 1

	local g = verifying.gui
	verifying.gui = nil
	if not g then return end

	pcall(function()
		local fr = g:FindFirstChildOfClass("Frame")
		if fr then
			TweenService:Create(fr,
				TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.new(0, 0, 0, 0) }):Play()
		end
	end)
	task.delay(0.3, function() if g and g.Parent then g:Destroy() end end)
end

local function openVerifyPanel(seconds, amount)
	closeVerifyPanel()

	seconds = math.clamp(tonumber(seconds) or 30, 3, 300)
	amount  = tonumber(amount) or 0

	verifying.token  = verifying.token + 1
	local myToken    = verifying.token
	verifying.active = true
	verifying.endsAt = tick() + seconds
	verifying.amount = amount

	local gui = Instance.new("ScreenGui")
	gui.Name           = "UGCVerifyingGui"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = false     -- reste sous la barre Roblox, sur tous les appareils
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 500
	gui.Parent         = player:WaitForChild("PlayerGui")
	verifying.gui = gui

	local w, h = verifyPanelSize()

	local fr = Instance.new("Frame")
	fr.AnchorPoint            = Vector2.new(0.5, 0)
	fr.Position               = UDim2.new(0.5, 0, 0, 10)
	fr.Size                   = UDim2.new(0, 0, 0, 0)
	fr.BackgroundColor3       = Color3.fromRGB(18, 18, 24)
	fr.BackgroundTransparency = 0.05
	fr.BorderSizePixel        = 0
	fr.Parent                 = gui
	local co = Instance.new("UICorner") ; co.CornerRadius = UDim.new(0, 14) ; co.Parent = fr
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 175, 60) ; st.Thickness = 2 ; st.Parent = fr

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8) ; pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 12) ; pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = fr

	-- Ligne 1 : intitulé à gauche, compte à rebours à droite
	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(0.72, 0, 0.27, 0)
	title.Position               = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Font                   = Enum.Font.Gotham
	title.Text                   = "Verifying your purchase..."
	title.TextColor3             = Color3.fromRGB(235, 200, 150)
	title.TextScaled             = true
	title.TextXAlignment         = Enum.TextXAlignment.Left
	title.Parent                 = fr

	local timer = Instance.new("TextLabel")
	timer.AnchorPoint            = Vector2.new(1, 0)
	timer.Size                   = UDim2.new(0.24, 0, 0.27, 0)
	timer.Position               = UDim2.new(1, 0, 0, 0)
	timer.BackgroundTransparency = 1
	timer.Font                   = Enum.Font.FredokaOne
	timer.Text                   = tostring(math.ceil(seconds)) .. "s"
	timer.TextColor3             = Color3.fromRGB(255, 190, 80)
	timer.TextScaled             = true
	timer.TextXAlignment         = Enum.TextXAlignment.Right
	timer.Parent                 = fr

	-- Ligne 2 : LE message, en gros, avec le montant gelé dedans
	local big = Instance.new("TextLabel")
	big.Size                   = UDim2.new(1, 0, 0.42, 0)
	big.Position               = UDim2.new(0, 0, 0.31, 0)
	big.BackgroundTransparency = 1
	big.Font                   = Enum.Font.FredokaOne
	big.Text                   = (amount > 0)
		and (formatNumber(amount) .. " POINTS ARE SAFE")
		or  "YOUR POINTS ARE SAFE"
	big.TextColor3             = Color3.fromRGB(255, 255, 255)
	big.TextScaled             = true
	big.TextXAlignment         = Enum.TextXAlignment.Center
	big.Parent                 = fr
	local bigStroke = Instance.new("UIStroke")
	bigStroke.Color = Color3.fromRGB(120, 75, 0) ; bigStroke.Thickness = 1.5
	bigStroke.Parent = big

	-- Ligne 3 : barre de progression
	local track = Instance.new("Frame")
	track.AnchorPoint     = Vector2.new(0, 1)
	track.Size            = UDim2.new(1, 0, 0.11, 0)
	track.Position        = UDim2.new(0, 0, 1, 0)
	track.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	track.BorderSizePixel = 0
	track.Parent          = fr
	local tco = Instance.new("UICorner") ; tco.CornerRadius = UDim.new(1, 0) ; tco.Parent = track

	local fill = Instance.new("Frame")
	fill.Size             = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 175, 60)
	fill.BorderSizePixel  = 0
	fill.Parent           = track
	local fco = Instance.new("UICorner") ; fco.CornerRadius = UDim.new(1, 0) ; fco.Parent = fill

	TweenService:Create(fr,
		TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, w, 0, h) }):Play()

	TweenService:Create(fill,
		TweenInfo.new(seconds, Enum.EasingStyle.Linear),
		{ Size = UDim2.new(0, 0, 1, 0) }):Play()

	-- 📱 Suit les changements de taille d'écran (rotation, redimensionnement)
	local cam = workspace.CurrentCamera
	local vpConn
	if cam then
		vpConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if not fr.Parent then return end
			local nw, nh = verifyPanelSize()
			fr.Size = UDim2.new(0, nw, 0, nh)
		end)
	end
	gui.Destroying:Connect(function()
		if vpConn then vpConn:Disconnect() end
	end)

	-- Compte à rebours. Le token empêche un ancien panneau de continuer à
	-- écrire dans l'interface après qu'un nouveau a été ouvert.
	task.spawn(function()
		while verifying.token == myToken and gui.Parent do
			local left = math.max(0, verifying.endsAt - tick())
			if timer.Parent then timer.Text = tostring(math.ceil(left)) .. "s" end
			if left <= 0 then
				if timer.Parent then timer.Text = "" end
				if title.Parent then title.Text = "Almost done..." end
				break
			end
			task.wait(0.25)
		end
	end)

	-- 🛟 Filet : si aucune réponse du serveur n'arrive, on déverrouille quand
	--    même. Le serveur, lui, a déjà libéré le joueur au bout du délai.
	task.delay(seconds + 12, function()
		if verifying.token == myToken and verifying.active then
			closeVerifyPanel()
		end
	end)
end

-- 🔑 LE PANNEAU EST PILOTÉ PAR L'ATTRIBUT, PAS PAR UN REMOTE.
--    Même mécanisme que la pastille au-dessus de la tête, qui marche déjà.
--    Un attribut se réplique tout seul : plus aucun risque qu'un RemoteEvent
--    resté nil au démarrage du serveur fasse disparaître le panneau en silence.
local function syncVerifyPanel()
	local amount = player:GetAttribute("UGCPending")

	if type(amount) == "number" and amount > 0 then
		if verifying.active then return end   -- déjà ouvert, on ne rouvre pas

		local endsAt = tonumber(player:GetAttribute("UGCPendingUntil")) or 0
		local left   = endsAt - os.time()
		if left < 3 then left = 3 end          -- attribut arrivé en retard
		openVerifyPanel(left, amount)
	else
		closeVerifyPanel()
	end
end

player:GetAttributeChangedSignal("UGCPending"):Connect(syncVerifyPanel)
syncVerifyPanel()   -- au cas où une vérif serait déjà en cours au chargement

--════════════════════════════════════════════════════════════
-- 🛑 VENTES COUPÉES PAR UN ADMIN
--
--   L'état arrive par un objet à attributs répliqué, pas par un RemoteEvent :
--   un joueur qui rejoint APRÈS le gel doit le savoir aussi, et un attribut
--   est déjà là quand son interface se construit.
--   Ce test n'est que du confort : le serveur refuse de toute façon.
--════════════════════════════════════════════════════════════
local salesLock = ReplicatedStorage:WaitForChild("UGCSalesLock", 20)

local function salesBlocked()
	if not salesLock then return false end   -- script serveur absent → on ne gêne pas
	return salesLock:GetAttribute("Blocked") == true
end

local frozenGui = nil

local function frozenPanelSize()
	local cam = workspace.CurrentCamera
	local vp  = (cam and cam.ViewportSize.Y > 1) and cam.ViewportSize or Vector2.new(1280, 720)
	local w   = math.min(vp.X * 0.90, 460)
	local h   = math.min(vp.Y * 0.82, 430)
	return w, h
end

local function openFrozenPanel(notReady)
	if frozenGui and frozenGui.Parent then return end   -- déjà affiché

	local gui = Instance.new("ScreenGui")
	gui.Name           = "UGCSalesFrozenGui"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 600
	gui.Parent         = player:WaitForChild("PlayerGui")
	frozenGui = gui

	-- Voile qui avale les clics : on ne ferme QUE par le bouton vert, pour être
	-- sûr que le message a été vu.
	local veil = Instance.new("TextButton")
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 1
	veil.AutoButtonColor = false
	veil.Text = ""
	veil.BorderSizePixel = 0
	veil.ZIndex = 1
	veil.Parent = gui
	TweenService:Create(veil, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()

	local w, h = frozenPanelSize()

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position    = UDim2.new(0.5, 0, 0.5, 0)
	card.Size        = UDim2.new(0, 0, 0, 0)
	card.BackgroundColor3 = Color3.fromRGB(20, 20, 27)
	card.BorderSizePixel  = 0
	card.ZIndex = 2
	card.Parent = gui
	local cc = Instance.new("UICorner") ; cc.CornerRadius = UDim.new(0, 16) ; cc.Parent = card
	local cs = Instance.new("UIStroke")
	cs.Color = Color3.fromRGB(235, 60, 65) ; cs.Thickness = 2.5 ; cs.Parent = card
	local cp = Instance.new("UIPadding")
	cp.PaddingTop = UDim.new(0, 14) ; cp.PaddingBottom = UDim.new(0, 14)
	cp.PaddingLeft = UDim.new(0, 16) ; cp.PaddingRight = UDim.new(0, 16)
	cp.Parent = card

	local titleH = 40
	local btnH   = 50

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, titleH)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = notReady and "⏳ ONE MOMENT" or "🛑 UGC PURCHASES ARE PAUSED"
	title.TextColor3 = Color3.fromRGB(255, 90, 95)
	title.TextScaled = true
	title.ZIndex = 3
	title.Parent = card

	-- Le texte est dans une zone défilante : sur un petit écran il reste
	-- entièrement lisible au lieu d'être rogné.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.new(0, 0, 0, titleH + 8)
	scroll.Size = UDim2.new(1, 0, 1, -(titleH + btnH + 24))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 105)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ZIndex = 3
	scroll.Parent = card

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -6, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextColor3 = Color3.fromRGB(228, 228, 235)
	body.TextSize = 15
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.RichText = true
	body.ZIndex = 4
	body.Parent = scroll

	if notReady then
		body.Text = "The shop is still checking in with the server.\n\n"
			.. "<b><font color=\"#5ADC8C\">YOUR POINTS ARE SAFE.</font></b>\n\n"
			.. "This usually takes a few seconds. Please try again in a moment."
	else
		body.Text =
			"An administrator has temporarily turned off all UGC purchases.\n\n"
			.. "We found an exploit that could damage the economy, and we closed the "
			.. "shop to protect everyone's items.\n\n"
			.. "<b><font color=\"#5ADC8C\">YOUR POINTS ARE SAFE.</font></b>\n"
			.. "Nothing has been taken from your account, and nothing will be.\n\n"
			.. "Please check the <b>community support messages</b> for updates. "
			.. "We're working hard to fix this and reopen the shop as soon as possible.\n\n"
			.. "Thank you for your patience."

		local extra = salesLock and salesLock:GetAttribute("Note")
		if type(extra) == "string" and extra ~= "" then
			body.Text = body.Text
				.. "\n\n<font color=\"#FFC24A\">" .. extra .. "</font>"
		end
	end

	local okBtn = Instance.new("TextButton")
	okBtn.AnchorPoint = Vector2.new(0.5, 1)
	okBtn.Position = UDim2.new(0.5, 0, 1, 0)
	okBtn.Size = UDim2.new(1, 0, 0, btnH)
	okBtn.BackgroundColor3 = Color3.fromRGB(55, 195, 100)
	okBtn.AutoButtonColor = false
	okBtn.BorderSizePixel = 0
	okBtn.Font = Enum.Font.FredokaOne
	okBtn.Text = "I UNDERSTAND"
	okBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	okBtn.TextSize = 20
	okBtn.ZIndex = 3
	okBtn.Parent = card
	local oc = Instance.new("UICorner") ; oc.CornerRadius = UDim.new(0, 11) ; oc.Parent = okBtn
	local os_ = Instance.new("UIStroke")
	os_.Color = Color3.fromRGB(30, 130, 65) ; os_.Thickness = 2 ; os_.Parent = okBtn

	local scale = Instance.new("UIScale") ; scale.Parent = okBtn
	okBtn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.03 }):Play()
	end)
	okBtn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)

	local function closePanel()
		if not gui.Parent then return end
		frozenGui = nil
		TweenService:Create(card,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(0, 0, 0, 0) }):Play()
		TweenService:Create(veil, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		task.delay(0.25, function() if gui and gui.Parent then gui:Destroy() end end)
	end

	okBtn.MouseButton1Click:Connect(closePanel)

	-- 📱 Suit la rotation et le redimensionnement d'écran
	local cam = workspace.CurrentCamera
	local vpConn
	if cam then
		vpConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if not card.Parent then return end
			local nw, nh = frozenPanelSize()
			card.Size = UDim2.new(0, nw, 0, nh)
		end)
	end
	gui.Destroying:Connect(function() if vpConn then vpConn:Disconnect() end end)

	TweenService:Create(card,
		TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, w, 0, h) }):Play()
end

MarketplaceService.PromptPurchaseFinished:Connect(function(who, boughtId, bought)
	if who ~= player then return end
	isProcessing[boughtId] = false
	if bought then
		SF.ownedMap[boughtId] = true   -- 🔎 « Owned » à jour tout de suite
		pcall(function()
			local s = SoundService:FindFirstChild("Buysound")
			if s then s:Play() end
		end)
		showNotification("✅ Purchase successful!", false)
	end
end)

confirmUGCPurchaseEvent.OnClientEvent:Connect(function(success, reason, assetId, itemName, waitSeconds, pendingAmount)
	if assetId then
		isProcessing[assetId] = false
	end

	-- ⏳ Le panneau est ouvert par l'attribut UGCPending, pas ici.
	--    On sort simplement pour ne pas le refermer par erreur.
	if reason == "verifying" then return end

	-- 🛑 Le serveur a refusé parce que les ventes sont coupées. On arrive ici
	--    si l'attribut n'était pas encore là au moment du clic, ou si quelqu'un
	--    a contourné l'interface : dans les deux cas, même explication.
	if reason == "sales_frozen" or reason == "sales_unknown" then
		openFrozenPanel(reason == "sales_unknown")
		return
	end

	-- 👁️ UGC masqué : pas la peine du panneau d'urgence, ce n'est pas une
	--    crise. Le cas n'arrive que si quelqu'un a deviné l'assetId.
	if reason == "sales_hidden" then
		showNotification("⚠️ This item is not available right now.", true)
		return
	end

	-- Toute autre réponse clôt la vérification en cours
	if verifying.active then
		closeVerifyPanel()
	end

	if success then
		if assetId then SF.ownedMap[assetId] = true end   -- 🔎 « Owned » à jour tout de suite
		if reason == "delivered_via_escrow"
			or reason == "delivered_via_bug_detection"
			or reason == "delivered_via_timeout" then
			pcall(function()
				local s = SoundService:FindFirstChild("Buysound")
				if s then s:Play() end
			end)
			showNotification(string.format("✅ %s successfully delivered!", itemName or "Item"), false)
		end
	else
		if reason == "already_owned" then
			if assetId then SF.ownedMap[assetId] = true end
			showNotification(string.format("⚠️ You already own %s!", itemName or "this item"), true)

		elseif reason == "state_changed" then
			showNotification("⚠️ Please try again in a moment.", true)

		elseif reason == "not_enough_points" then
			showNotification("❌ Not enough points anymore.", true)

		elseif reason == "timeout_refunded" then
			showNotification("↩️ Purchase cancelled.\nYour points have been refunded.", false)

		elseif reason == "refund_on_rejoin" then
			showNotification("⏳ Rejoin the game and this will be settled automatically.", true)

		elseif reason == "escrow_open" or reason == "resolving" then
			showNotification("⏳ A purchase is still being verified.\nPlease wait.", true)

		elseif reason == "debt" then
			showNotification("⚠️ Settle your pending balance before buying again.", true)

		elseif reason == "refund_pending" then
			showNotification(string.format(
				"⏳ Please wait %ds before your next purchase.", waitSeconds or 0), true)
		end
	end
end)

local function setupPurchaseLogic(purchaseBtn, assetId, itemName, itemPrice)
	purchaseBtn.MouseButton1Click:Connect(function()
		playClickEffect(purchaseBtn)

		-- 🛑 Ventes coupées par un admin : on explique, et on ne déclenche RIEN.
		--    Placé avant le test des points : dire « pas assez de points » à
		--    quelqu'un alors que la boutique est fermée serait trompeur.
		if salesBlocked() then
			openFrozenPanel(salesLock and salesLock:GetAttribute("Ready") ~= true)
			pcall(function()
				local s = SoundService:FindFirstChild("buycancel")
				if s then s:Play() end
			end)
			return
		end

		-- ⏳ Vérification en cours : le serveur refuserait de toute façon.
		if verifying.active then
			local left = math.max(0, math.ceil(verifying.endsAt - tick()))
			showNotification(string.format(
				"⏳ Please wait %ds.\n%s points are safe.",
				left,
				verifying.amount > 0 and formatNumber(verifying.amount) or "Your"), true)
			pcall(function()
				local s = SoundService:FindFirstChild("buycancel")
				if s then s:Play() end
			end)
			return
		end
		pcall(function()
			local s = SoundService:FindFirstChild("Sound4")
			if s then s:Play() end
		end)
		if isProcessing[assetId] then
			showNotification("⏳ Purchase in progress...", false)
			return
		end
		local ls  = player:FindFirstChild("leaderstats")
		local pts = ls and ls:FindFirstChild("Points")
		local pp  = pts and pts.Value or 0
		if pp < itemPrice then
			local miss = itemPrice - pp
			showNotification(string.format(
				"❌ Not enough points!\n\nRequired: %s pts\nYou have: %s pts\nMissing: %s pts",
				formatNumber(itemPrice), formatNumber(pp), formatNumber(miss)), true)
			pcall(function()
				local s = SoundService:FindFirstChild("buycancel")
				if s then s:Play() end
			end)
			purchaseUGCEvent:FireServer(assetId)
			return
		end
		isProcessing[assetId] = true
		purchaseUGCEvent:FireServer(assetId)
		task.delay(15, function() isProcessing[assetId] = false end)
	end)
end

-- ============================================================
-- LOGIQUE DE STOCK
-- ============================================================
local stockLabels  = {}
local stockConfigs = {}
-- 🌐 En mode « Stock Roblox », le total affiché est le VRAI total du
--    catalogue, pas ton InitialStock. Le serveur nous l'envoie à chaque fois ;
--    on le retient ici pour ne pas repartir sur la config au refresh suivant.
local stockTotals  = {}

local function updateStockLabel(assetId, cur, total)
	local lbl = stockLabels[assetId]
	local cfg = stockConfigs[assetId]
	if not lbl or not cfg then return end

	if type(total) == "number" and total > 0 then stockTotals[assetId] = total end
	local max = stockTotals[assetId] or cfg.InitialStock or 0
	SF.cur[assetId], SF.total[assetId] = tonumber(cur), tonumber(max)   -- 🔎 pour le filtre / tri

	lbl.Text = cur .. "/" .. max
	local targetButtonName = nil
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		if ugc.AssetId == assetId then
			targetButtonName = ugc.ButtonName
			break
		end
	end
	-- Récupérer le gradient + stroke pour les colorer selon l'état
	local gradient = lbl:FindFirstChildOfClass("UIGradient")
	local stroke   = lbl:FindFirstChildOfClass("UIStroke")
	-- Texte reste blanc, c'est le gradient qui colore
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	if cur == 0 then
		-- ÉPUISÉ : gradient rouge
		if gradient then
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,   STOCK_RED_LIGHT),
				ColorSequenceKeypoint.new(0.5, STOCK_RED_BRIGHT),
				ColorSequenceKeypoint.new(1,   STOCK_RED_DEEP),
			})
		end
		if stroke then stroke.Color = STOCK_RED_DEEP end
		if targetButtonName then setCardGray(scrollButtons[targetButtonName], "stock", true) end
	elseif max > 0 and cur <= max * 0.3 then
		-- FAIBLE : gradient orange
		if gradient then
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,   STOCK_ORANGE_LIGHT),
				ColorSequenceKeypoint.new(0.5, STOCK_ORANGE_BRIGHT),
				ColorSequenceKeypoint.new(1,   STOCK_ORANGE_DEEP),
			})
		end
		if stroke then stroke.Color = STOCK_ORANGE_DEEP end
		if targetButtonName then setCardGray(scrollButtons[targetButtonName], "stock", false) end
	else
		-- OK : gradient vert
		if gradient then
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0,   STOCK_GREEN_LIGHT),
				ColorSequenceKeypoint.new(0.5, STOCK_GREEN_BRIGHT),
				ColorSequenceKeypoint.new(1,   STOCK_GREEN_DEEP),
			})
		end
		if stroke then stroke.Color = STOCK_GREEN_DEEP end
		if targetButtonName then setCardGray(scrollButtons[targetButtonName], "stock", false) end
	end
end

UpdateStockEvent.OnClientEvent:Connect(function(newStocks, meta)
	if type(newStocks) ~= "table" then return end

	-- `meta` n'existe que depuis le nouveau système. S'il manque (ancien
	-- serveur, ou message envoyé par une fonction non mise à jour), on garde
	-- simplement les totaux déjà connus : rien ne casse.
	local totals = (type(meta) == "table" and type(meta.totals) == "table")
		and meta.totals or nil

	for assetId in pairs(stockLabels) do
		local key = tostring(assetId)
		local v = newStocks[key]
		if v ~= nil then
			updateStockLabel(assetId, v, totals and totals[key] or nil)
		end
	end
end)

local function initStock(assetId)
	task.spawn(function()
		local data = GetStockFunction:InvokeServer(assetId)
		if data then
			stockConfigs[assetId] = data.Config
			updateStockLabel(assetId, data.CurrentStock, data.Total)
		else
			local lbl = stockLabels[assetId]
			if lbl then lbl.Text = "ERROR" ; lbl.TextColor3 = Color3.fromRGB(255,0,0) end
		end
	end)
end

UpdateButtonStateEvent.OnClientEvent:Connect(function(states)
	local anyChanged = false
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		local st = states[ugc.ButtonName]
		if st then
			local wasActive = ugcStockState[ugc.ButtonName]
			setButtonStockState(ugc.ButtonName, st.IsActive, true)
			if wasActive ~= st.IsActive then
				anyChanged = true
			end
		end
	end
	if anyChanged then
		reorganizeGrid()
	end
end)

-- ============================================================
-- NETTOYAGE
-- ============================================================
for _, child in pairs(ScrollingFrame:GetChildren()) do
	if child:IsA("Frame") and child.Name ~= "MagicDominusButton" then
		child:Destroy()
	end
end
TemplateBtn.Visible = false

for _, child in pairs(SelectedFrame:GetChildren()) do
	if child:IsA("Frame") and child.Name ~= "NoUGCSelected" then
		child:Destroy()
	end
end

-- ============================================================
-- GÉNÉRATION PRINCIPALE
-- ============================================================
local maxRow = 0
for gridIdx, ugc in ipairs(sortedItems) do
	local assetId   = ugc.AssetId
	-- 🖼️ ImageId peut être une miniature Roblox (rbxthumb://…) : on la garde telle quelle
	local rawImg    = ugc.ImageId or ugc.AssetId
	local imageId   = (type(rawImg) == "string" and rawImg:find("://")) and rawImg or ("rbxassetid://" .. tostring(rawImg))
	local itemName  = ugc.Name
	local itemPrice = ugc.Price
	local isNew     = (UGC_CONFIG.IsNew and UGC_CONFIG.IsNew(ugc)) or (not UGC_CONFIG.IsNew and ugc.IsNew == true)
	local idx = gridIdx - 1
	local col = idx % COLUMNS
	local row = math.floor(idx / COLUMNS)
	if row > maxRow then maxRow = row end
	local posX = GAP_SCALE + col * (BTN_SCALE + GAP_SCALE)
	ugcStockState[ugc.ButtonName] = true
	-- ─────────────────────────────────────────────
	-- BOUTON SCROLLINGFRAME
	-- ─────────────────────────────────────────────
	local outerFrame = TemplateBtn:Clone()
	outerFrame.Name     = ugc.ButtonPath
	outerFrame.Visible  = true
	outerFrame.Size     = UDim2.new(BTN_SCALE, 0, 0, 0)
	outerFrame.Position = UDim2.new(posX, 0, 0, 0)
	outerFrame.Parent   = ScrollingFrame
	attachGradient(outerFrame, false)
	local imgBtn = outerFrame:FindFirstChildOfClass("ImageButton")
	if not imgBtn then
		warn("ImageButton introuvable dans MagicDominusButton pour " .. itemName)
		outerFrame:Destroy()
		continue
	end
	imgBtn.Image = imageId
	local newBadge = imgBtn:FindFirstChild("ImageLabel")
	if newBadge then newBadge.Visible = isNew; newBadges[ugc.ButtonName] = newBadge end
	local lockBadge = imgBtn:FindFirstChild("Lock")
	if lockBadge then
		lockBadge.Image   = "rbxassetid://130535340323890"
		lockBadge.Visible = true
	end
	attachButtonAnimation(imgBtn, outerFrame)
	originalBtnColors[imgBtn]     = imgBtn.BackgroundColor3
	scrollButtons[ugc.ButtonName] = imgBtn
	buttonFrames[ugc.ButtonName]  = outerFrame
	imgBtn.MouseButton1Click:Connect(function()
		pcall(function()
			local s = SoundService:FindFirstChild("Sound4")
			if s then s:Play() end
		end)
		openFrame(ugc.FrameName, imgBtn)
	end)
	-- ─────────────────────────────────────────────
	-- FRAME SELECTED
	-- ─────────────────────────────────────────────
	local selFrame = TemplateSelected:Clone()
	selFrame.Name    = ugc.FrameName
	selFrame.Visible = false
	selFrame.Parent  = SelectedFrame
	local nameLabel = selFrame:FindFirstChild("TextLabel")
	if nameLabel then nameLabel:Destroy() end
	local mainImg = Instance.new("ImageLabel")
	mainImg.Name                   = "ItemImage"
	mainImg.Size                   = UDim2.new(0.94, 0, 0.94, 0)
	mainImg.Position               = UDim2.new(0.03, 0, 0.02, 0)
	mainImg.AnchorPoint            = Vector2.new(0, 0)
	mainImg.BackgroundTransparency = 1
	mainImg.Image                  = imageId
	mainImg.ScaleType              = Enum.ScaleType.Fit
	mainImg.ZIndex                 = 2
	mainImg.Parent                 = selFrame
	local mic = Instance.new("UICorner")
	mic.CornerRadius = UDim.new(0, 8)
	mic.Parent       = mainImg
	selFrame.ClipsDescendants = false
	-- ─────────────────────────────────────────────
	-- STOCK CONTAINER (gauche, 50%) — stylisé comme les likes
	-- ─────────────────────────────────────────────
	local stockContainer = Instance.new("Frame")
	stockContainer.Name                   = "stock"
	stockContainer.Size                   = UDim2.new(0.50, 0, 0.22, 0)
	stockContainer.Position               = UDim2.new(0.25, 0, 1.22, 0)  -- centré en X, plus bas
	stockContainer.BackgroundTransparency = 1
	stockContainer.BorderSizePixel        = 0
	stockContainer.ZIndex                 = 2
	stockContainer.Parent                 = selFrame
	-- Titre "Stock" — FredokaOne + stroke
	local stockTitle = Instance.new("TextLabel")
	stockTitle.Name                   = "StockTitle"
	stockTitle.Size                   = UDim2.new(1, 0, 0.32, 0)
	stockTitle.Position               = UDim2.new(0, 0, 0, 0)
	stockTitle.BackgroundTransparency = 1
	stockTitle.Text                   = "Stock"
	stockTitle.Font                   = Enum.Font.FredokaOne
	stockTitle.TextScaled             = true
	stockTitle.TextXAlignment         = Enum.TextXAlignment.Center
	stockTitle.TextColor3             = Color3.fromRGB(220, 255, 230)
	stockTitle.ZIndex                 = 3
	stockTitle.Parent                 = stockContainer
	local stockTitleStroke = Instance.new("UIStroke")
	stockTitleStroke.Color     = STOCK_GREEN_DEEP
	stockTitleStroke.Thickness = 0.5
	stockTitleStroke.Parent    = stockTitle
	-- Valeur "5/25" — FredokaOne + gradient dynamique + stroke
	local stockLabel = Instance.new("TextLabel")
	stockLabel.Name                   = "StockLabel"
	stockLabel.Size                   = UDim2.new(1, 0, 0.65, 0)
	stockLabel.Position               = UDim2.new(0, 0, 0.35, 0)
	stockLabel.BackgroundTransparency = 1
	stockLabel.Text                   = "..."
	stockLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
	stockLabel.Font                   = Enum.Font.FredokaOne
	stockLabel.TextScaled             = true
	stockLabel.TextXAlignment         = Enum.TextXAlignment.Center
	stockLabel.ZIndex                 = 3
	stockLabel.Parent                 = stockContainer
	-- Gradient (mis à jour dynamiquement par updateStockLabel)
	local stockGradient = Instance.new("UIGradient")
	stockGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,    STOCK_GREEN_LIGHT),
		ColorSequenceKeypoint.new(0.5,  STOCK_GREEN_BRIGHT),
		ColorSequenceKeypoint.new(1,    STOCK_GREEN_DEEP),
	})
	stockGradient.Rotation = 90
	stockGradient.Parent   = stockLabel
	local stockStroke = Instance.new("UIStroke")
	stockStroke.Color        = STOCK_GREEN_DEEP
	stockStroke.Thickness    = 0.5
	stockStroke.Transparency = 0.2
	stockStroke.Parent       = stockLabel
	stockLabels[assetId]  = stockLabel
	stockConfigs[assetId] = ugc
	initStock(assetId)
	-- ─────────────────────────────────────────────
	-- 🆕 LIKES CONTAINER (droite, 50% largeur)
	-- ─────────────────────────────────────────────
	local likeContainer = Instance.new("Frame")
	likeContainer.Name                   = "likes"
	-- 🎯 Même largeur et même X que le bloc Stock, juste en dessous.
	--    L'ancien 0.85/1.60 sortait du cadre (0.85+0.42 = 1.27 en X) : le cœur
	--    se retrouvait posé par-dessus les boutons de la ScrollingFrame, et
	--    c'est un bouton « épuisé » (dégradé gris) qu'on voyait à côté de lui.
	likeContainer.Size     = UDim2.new(0.42, 0, 0.18, 0)
	likeContainer.Position = UDim2.new(0.85, 0, 1.60, 0)
	likeContainer.BackgroundTransparency = 1
	likeContainer.BorderSizePixel        = 0
	likeContainer.ZIndex                 = 2
	likeContainer.Parent                 = selFrame
	-- Ligne du bas plus haute pour accueillir le gros coeur
	local heartRow = Instance.new("Frame")
	heartRow.Name                   = "HeartRow"
	heartRow.Size                   = UDim2.new(1, 0, 0.65, 0)   -- ✅ plus grand (0.50 → 0.65)
	heartRow.Position               = UDim2.new(0, 0, 0.35, 0)
	heartRow.BackgroundTransparency = 1
	heartRow.ClipsDescendants       = false                       -- ✅ laisse déborder le bounce
	heartRow.ZIndex                 = 3
	heartRow.Parent                 = likeContainer
	-- Cœur PLUS GROS + contour rose au lieu de gris
	-- Cœur centré, plus à droite
	local heartBtn = Instance.new("TextButton")
	heartBtn.Name                   = "HeartButton"
	heartBtn.AnchorPoint            = Vector2.new(0.5, 0.5)
	heartBtn.Position = UDim2.fromScale(0.7, 0.20)
	heartBtn.Size     = UDim2.fromScale(0.45, 1.5)
	heartBtn.BackgroundTransparency = 1
	heartBtn.BorderSizePixel        = 0
	-- 🩹 Un autre script du jeu remet ce fond à 0 après coup (couleur 163,162,165 =
	--    valeur par défaut d'Instance.new). On ne cherche pas à savoir lequel :
	--    on reprend la main dès qu'il touche à la propriété.
	heartBtn:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		if heartBtn.BackgroundTransparency ~= 1 then
			heartBtn.BackgroundTransparency = 1
		end
	end)
	heartBtn:GetPropertyChangedSignal("BorderSizePixel"):Connect(function()
		if heartBtn.BorderSizePixel ~= 0 then
			heartBtn.BorderSizePixel = 0
		end
	end)
	heartBtn.Text                   = "♥"            -- ✅ jamais ♡
	heartBtn.TextColor3             = Color3.fromRGB(255, 255, 255)
	heartBtn.TextTransparency       = 0.62
	-- SourceSansBold est une police Roblox historique : elle a une couverture
	-- Unicode large et contient le ♥. FredokaOne, non → carré gris.
	heartBtn.Font                   = Enum.Font.SourceSansBold
	heartBtn.TextScaled             = true
	heartBtn.AutoButtonColor        = false
	heartBtn.Selectable             = false          -- pas de cadre de sélection manette
	heartBtn.ZIndex                 = 4
	heartBtn.Visible                = true           -- ✅ réactivé
	heartBtn.Parent                 = likeContainer

	local heartStroke = Instance.new("UIStroke")
	heartStroke.Name         = "HeartStroke"
	heartStroke.Color        = PINK_OUTLINE
	heartStroke.Thickness    = 2
	heartStroke.Transparency = 0.15
	heartStroke.Parent       = heartBtn
	local countLabel = Instance.new("TextLabel")
	countLabel.Name                   = "LikeCount"
	countLabel.AnchorPoint            = Vector2.new(0.5, 0)
	countLabel.Position  = UDim2.fromScale(0.7, 0.68)
	countLabel.Size      = UDim2.fromScale(0.6, 0.35)
	countLabel.BackgroundTransparency = 1
	countLabel.Text                   = "..."
	countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	countLabel.Font                   = Enum.Font.FredokaOne
	countLabel.TextScaled             = true
	countLabel.Visible                     = likeCountShown()  -- ❤️ réglé depuis l'admin
	countLabel.TextTransparency            = 0
	countLabel.BackgroundTransparency      = 1
	countLabel.TextXAlignment         = Enum.TextXAlignment.Center
	countLabel.ZIndex                 = 4
	countLabel.Parent                 = likeContainer
	-- Enregistrer les refs
	likeButtons[assetId]     = heartBtn
	likeCountLabels[assetId] = countLabel
	likeCounts[assetId]      = likeCounts[assetId] or 0
	likedByPlayer[assetId]   = likedByPlayer[assetId] or false
	-- Click handler
	heartBtn.MouseButton1Click:Connect(function()
		pcall(function()
			local s = SoundService:FindFirstChild("Sound4")
			if s then s:Play() end
		end)
		onHeartClick(assetId)
	end)
	-- Rafraîchir au cas où les données sont déjà arrivées
	if likesDataLoaded then
		refreshLikeUI(assetId)
	end
	-- ─────────────────────────────────────────────
	-- BOUTON D'ACHAT
	-- ─────────────────────────────────────────────
	local purchaseBtn = selFrame:FindFirstChild("WingsButton")
	if purchaseBtn then
		purchaseBtn.Name = ugc.ButtonPath
		local priceLabel = purchaseBtn:FindFirstChildWhichIsA("TextLabel")
		if priceLabel then
			attachPriceCoin(priceLabel, formatFullPrice(itemPrice))
		end
	else
		warn("WingsButton introuvable dans NoUGCSelected pour " .. itemName)
	end
	setupPurchaseLogic(purchaseBtn, assetId, itemName, itemPrice)
end

-- ============================================================
-- 🆕 TEXTE "COMING SOON" EN BAS DE LA SCROLLINGFRAME
-- ============================================================
comingSoonLabel = Instance.new("TextLabel")
comingSoonLabel.Name                   = "ComingSoonLabel"
comingSoonLabel.BackgroundTransparency = 1
comingSoonLabel.Text                   = "More UGCs coming soon!"
comingSoonLabel.TextColor3             = Color3.fromRGB(182, 227, 251) -- bleu ciel
comingSoonLabel.Font                   = Enum.Font.FredokaOne
comingSoonLabel.TextScaled             = true
comingSoonLabel.TextXAlignment         = Enum.TextXAlignment.Center
comingSoonLabel.ZIndex                 = 5
comingSoonLabel.Parent                 = ScrollingFrame
local csStroke = Instance.new("UIStroke")
csStroke.Color     = Color3.fromRGB(20, 80, 140)
csStroke.Thickness = 1
csStroke.Parent    = comingSoonLabel

-- ============================================================
-- CALCUL INITIAL DE LA GRILLE (FIX MOBILE)
-- ============================================================
local function applyInitialGrid()
	local sfW = ScrollingFrame.AbsoluteSize.X
	if sfW <= 1 then return false end
	local btnPx = sfW * BTN_SCALE
	local gapPx = sfW * GAP_SCALE
	local available = {}
	local exhausted = {}

	for _, ugc in ipairs(sortedItems) do
		local frame = buttonFrames[ugc.ButtonName]

		if ugcHidden(ugc.AssetId) then
			if frame then frame.Visible = false end
		elseif ugcStockState[ugc.ButtonName] == false then
			if frame then frame.Visible = true end
			table.insert(exhausted, ugc)
		else
			if frame then frame.Visible = true end
			table.insert(available, ugc)
		end
	end
	local finalOrder = {}
	for _, ugc in ipairs(available) do table.insert(finalOrder, ugc) end
	for _, ugc in ipairs(exhausted) do table.insert(finalOrder, ugc) end
	finalOrder = SF.apply(finalOrder)   -- 🔎 filtre / tri choisis par le joueur
	local totalRows   = math.ceil(#finalOrder / COLUMNS)
	local totalHeight = gapPx + totalRows * (btnPx + gapPx)
	totalHeight += placeComingSoon(sfW, btnPx, gapPx, totalRows)
	ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
	for gridIdx, ugc in ipairs(finalOrder) do
		local idx = gridIdx - 1
		local col = idx % COLUMNS
		local row = math.floor(idx / COLUMNS)
		local posX = GAP_SCALE + col * (BTN_SCALE + GAP_SCALE)
		local posY = gapPx + row * (btnPx + gapPx)
		local btn = buttonFrames[ugc.ButtonName]
		if btn then
			btn.Position = UDim2.new(posX, 0, 0, posY)
			btn.Size     = UDim2.new(BTN_SCALE, 0, 0, btnPx)
			gridBase[btn] = { pos = btn.Position, size = btn.Size }   -- 🩹 place retenue pour le survol
		end
	end
	print(string.format(
		"✅ [UGCShopGenerator] Grille appliquée: %d lignes | btnPx=%.0f | gapPx=%.0f",
		totalRows, btnPx, gapPx))
	return true
end

local gridApplied = false
ShopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if ShopFrame.Visible then
		-- 🔒 Carrousel → points uniquement, rate custom, tant que le shop UGC est ouvert
		if _G.OffersLockCategory then
			_G.OffersLockCategory("points", POINTS_OFFER_DISPLAY_TIME)
		end
		-- 🆕 Lazy-load des likes la 1ère fois que le shop s'ouvre
		fetchLikesDataOnce()
		if not gridApplied then
			task.wait()
			if applyInitialGrid() then
				gridApplied = true
			end
		end
		-- ⭐ 1er UGC déjà sélectionné (après la mise en place de la grille)
		task.delay(0.15, function() if ShopFrame.Visible then selectFirstUGC() end end)
	else
		-- 🔓 Shop fermé → retour à la rotation normale
		if _G.OffersUnlockCategory then
			_G.OffersUnlockCategory()
		end
	end
end)


--════════════════════════════════════════════════════════════
-- 👁️ Un admin vient d'afficher ou de masquer un UGC
--
--   La grille se refait toute seule : le joueur n'a pas à rouvrir le shop,
--   et surtout pas à relancer la partie. C'est ce qui permet de lancer un
--   UGC pour tout le monde en même temps.
--════════════════════════════════════════════════════════════
task.spawn(function()
	local f = ReplicatedStorage:WaitForChild("UGCSalesLock", 30)
	if not f then return end
	visFlag = f

	f.AttributeChanged:Connect(function(attr)
		if attr:sub(1, 5) ~= "Hide_" then return end

		-- S'il regardait justement la fiche de l'UGC qu'on masque, on referme
		-- la sélection : sinon son bouton Buy resterait affiché à l'écran.
		if f:GetAttribute(attr) == true then
			local id = attr:sub(6)
			for _, ugc in ipairs(UGC_CONFIG.Items) do
				if tostring(ugc.AssetId) == id and UGCUpdateLabel.Text == ugc.FrameName then
					resetToNoSelection()
					break
				end
			end
		end

		reorganizeGrid()
	end)

	-- Le drapeau arrive parfois après la génération de la grille : on repasse
	-- une fois pour cacher ce qui devait l'être dès le départ.
	reorganizeGrid()
end)
--════════════════════════════════════════════════════════════
-- ↕️ Un admin vient de changer l'ordre du shop → la grille se replace
--════════════════════════════════════════════════════════════
-- 🆕 Un admin coche / décoche le badge NEW → mis à jour en direct
if UGC_CONFIG.OnNewChanged and UGC_CONFIG.IsNew then
	UGC_CONFIG.OnNewChanged(function()
		for _, ugc in ipairs(UGC_CONFIG.Items) do
			local b = newBadges[ugc.ButtonName]
			if b and b.Parent then b.Visible = UGC_CONFIG.IsNew(ugc) end
		end
	end)
end

if UGC_CONFIG.OnOrderChanged then
	UGC_CONFIG.OnOrderChanged(function()
		sortedItems = UGC_CONFIG.GetSortedItems()
		reorganizeGrid()
	end)
end

--════════════════════════════════════════════════════════════
-- ❤️ Un admin affiche / cache le nombre de likes
--════════════════════════════════════════════════════════════
task.spawn(function()
	local f = ReplicatedStorage:WaitForChild("UGCShopOrder", 30)
	if not f then return end
	local function apply()
		local show = likeCountShown()
		for _, lbl in pairs(likeCountLabels) do
			lbl.Visible = show
		end
	end
	f:GetAttributeChangedSignal("ShowLikeCount"):Connect(apply)
	apply()
end)




--════════════════════════════════════════════════════════════
-- 🌀 FUSION COIL : messages
--════════════════════════════════════════════════════════════
local function formatDuree(s)
	s = math.max(0, math.floor(tonumber(s) or 0))
	local h   = math.floor(s / 3600)
	local m   = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then return string.format("%dh %02dm", h, m) end
	if m > 0 then return string.format("%dm %02ds", m, sec) end
	return sec .. "s"
end

-- 🔕 Petit message discret en bas de l'écran (au-dessus de la hotbar)
local function showToast(message)
	pcall(function()
		local gui = player:WaitForChild("PlayerGui")
		local old = gui:FindFirstChild("CoilToast")
		if old then old:Destroy() end

		local sg = Instance.new("ScreenGui")
		sg.Name = "CoilToast"
		sg.ResetOnSpawn = false
		sg.DisplayOrder = 400
		sg.Parent = gui

		local lbl = Instance.new("TextLabel")
		lbl.AnchorPoint = Vector2.new(0.5, 1)
		lbl.Position = UDim2.new(0.5, 0, 1, -80)
		lbl.Size = UDim2.new(0, 0, 0, 32)
		lbl.AutomaticSize = Enum.AutomaticSize.X
		lbl.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		lbl.BackgroundTransparency = 1
		lbl.BorderSizePixel = 0
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextSize = 15
		lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
		lbl.TextTransparency = 1
		lbl.Text = message
		lbl.Parent = sg
		local co = Instance.new("UICorner") ; co.CornerRadius = UDim.new(1, 0) ; co.Parent = lbl
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14) ; pad.PaddingRight = UDim.new(0, 14) ; pad.Parent = lbl

		TweenService:Create(lbl, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 1, -90),
			BackgroundTransparency = 0.35,
			TextTransparency = 0,
		}):Play()

		task.delay(3, function()
			if not sg.Parent then return end
			local t = TweenService:Create(lbl, TweenInfo.new(0.4), {
				BackgroundTransparency = 1, TextTransparency = 1 })
			t:Play()
			t.Completed:Connect(function() sg:Destroy() end)
		end)
	end)
end

task.spawn(function()
	local ev = ReplicatedStorage:WaitForChild("FusionCoilNotify", 30)
	if not ev then return end

	ev.OnClientEvent:Connect(function(kind, seconds)
		if kind == "given" then
			showNotification("🌀 You got the Fusion Coil!\nActive for " .. formatDuree(seconds) .. ".", false)

		elseif kind == "active" then
			showNotification(seconds
				and ("⚠️ You already have the Fusion Coil!\n" .. formatDuree(seconds) .. " left.")
				or  "⚠️ You already have the Fusion Coil!", true)

		elseif kind == "cooldown" then
			showNotification("⏳ Fusion Coil on cooldown!\nTry again in " .. formatDuree(seconds) .. ".", true)

		elseif kind == "busy" then
			showNotification("⏳ Please wait a moment...", true)

		elseif kind == "lost" then
			showToast("🌀 Your Fusion Coil has expired.")
		end
	end)
end)

--════════════════════════════════════════════════════════════
-- 🔎 BOUTON FILTER + PANNEAU DE FILTRE / TRI   (NOUVEAU, v7)
--   • Bouton FILTER PLAT, bord droit ALIGNÉ sur la carte la plus à droite.
--   • Le panneau SORT du bouton : une petite pointe le relie au bouton, il se
--     DÉROULE vers le bas ; un 2e appui sur FILTER le REMBOBINE (pas de X, pas de CANCEL :
--     refermer sans APPLY = rien n'est changé).
--   • Disposition d'avant : SHOW · TYPE (si le shop a plusieurs types) · SORT BY, en
--     boutons 3D (face en dégradé + socle) qui NE s'enfoncent PAS.
--   • Choix contraires impossibles ensemble : Available / Few left / Sold out (un seul),
--     Owned / Unowned (un seul), un seul tri. Prendre l'un retire l'autre (les
--     boutons gardent leur couleur normale).
--   • « High stock / Low stock » = tri sur le stock RESTANT.
--   • APPLY (vert, à gauche) · RESET (rouge, à droite) en bas DU panneau, sous un trait,
--     hors de la partie qui défile. Léger contour noir autour du panneau.
--   • Tous les appareils : tailles minimales pour le doigt (mobile) et la télé (console).
--   • 🎮 Manette, dans TOUT le shop : la touche Y est affichée sur FILTER (Y = ouvrir /
--     fermer), B = refermer le filtre puis le shop, la sélection reste dans le shop,
--     la 1re carte est choisie à l'ouverture, cadre jaune bien visible.
--   Aucun appel au serveur du jeu, aucun DataStore.
--   ⚠️ Écrit dans une FONCTION (pas un simple « do ») : Luau limite un script à
--      200 variables locales actives, et ce script en a déjà 118. La fonction a sa
--      propre limite.
--════════════════════════════════════════════════════════════
local function buildFilterUI()
	local UIS = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local CAS = game:GetService("ContextActionService")

	local WHITE  = Color3.new(1, 1, 1)
	local NAVY   = Color3.fromRGB(16, 30, 52)      -- fond du panneau (bleu nuit, le thème du bouton)
	local SUB    = Color3.fromRGB(150, 175, 210)   -- titres de section
	local SELC   = Color3.fromRGB(255, 214, 92)    -- cadre de sélection manette
	local COL = {   -- dessus, dessous, socle
		blue   = { Color3.fromRGB(55, 150, 240), Color3.fromRGB(25, 100, 200), Color3.fromRGB(12, 55, 120) },  -- = FILTER
		slate  = { Color3.fromRGB(62, 82, 112),  Color3.fromRGB(40, 56, 82),   Color3.fromRGB(22, 32, 50) },   -- pas choisi
		yellow = { Color3.fromRGB(255, 196, 60), Color3.fromRGB(215, 150, 30), Color3.fromRGB(120, 85, 10) },
		-- APPLY / RESET : vert et rouge, pour ne jamais les confondre avec les choix (bleu / ardoise)
		green  = { Color3.fromRGB(40, 185, 80),  Color3.fromRGB(12, 115, 42),  Color3.fromRGB(8, 65, 25) },
		red    = { Color3.fromRGB(245, 70, 65),  Color3.fromRGB(180, 25, 35),  Color3.fromRGB(105, 12, 22) },
	}
	local BLUE   = COL.blue[1]
	local YELLOW = Color3.fromRGB(240, 170, 30)
	local OFF    = Color3.fromRGB(44, 62, 92)
	local RED    = Color3.fromRGB(205, 70, 70)
	local Z = 40
	local SYM = Enum.Font.SourceSansBold   -- FredokaOne n'a pas ▼
	local IS_TOUCH = UIS.TouchEnabled and not UIS.KeyboardEnabled
	local IS_TV = GuiService:IsTenFootInterface()

	local function mk(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		if o:IsA("GuiObject") and props.ZIndex == nil then o.ZIndex = Z end
		o.Parent = parent
		return o
	end
	local function round(o, r) mk("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o) end
	local function outlined(lbl, t)
		mk("UIStroke", { Color = Color3.fromRGB(20, 20, 30), Thickness = t or 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, lbl)
	end
	local function flatButton(parent, text, color, size, textSize, props)
		local b = mk("TextButton", { Size = size, BackgroundColor3 = color, AutoButtonColor = true,
			BorderSizePixel = 0, Text = text, Font = Enum.Font.FredokaOne, TextSize = textSize,
			TextColor3 = WHITE }, parent)
		for k, v in pairs(props or {}) do b[k] = v end
		round(b, 8)
		outlined(b, 1.2)
		return b
	end
	-- 🎮 cadre de sélection manette (jaune, arrondi) pour tous les boutons du shop
	local selTemplate = Instance.new("Frame")
	selTemplate.Name = "PadSelection"
	selTemplate.BackgroundTransparency = 1
	selTemplate.Size = UDim2.new(1, 8, 1, 8)
	selTemplate.Position = UDim2.fromOffset(-4, -4)
	mk("UICorner", { CornerRadius = UDim.new(0, 12) }, selTemplate)
	mk("UIStroke", { Color = SELC, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, selTemplate)

	-- bouton 3D des Paramètres, mais FIXE : socle + face en dégradé, sans effet d'enfoncement
	local function button3D(parent, text, col, size, textSize, props)
		local depth = 3
		local slot = mk("Frame", { Size = size, BackgroundTransparency = 1 }, parent)
		for k, v in pairs(props or {}) do slot[k] = v end
		local edge = mk("Frame", { Size = UDim2.new(1, 0, 1, -depth), Position = UDim2.fromOffset(0, depth),
			BackgroundColor3 = col[3], BorderSizePixel = 0, ZIndex = Z + 3 }, slot)
		round(edge, 8)
		local btn = mk("TextButton", { Size = UDim2.new(1, 0, 1, -depth), BackgroundColor3 = WHITE,
			BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = Z + 4,
			SelectionImageObject = selTemplate }, slot)
		round(btn, 8)
		local grad = mk("UIGradient", { Rotation = 90, Color = ColorSequence.new(col[1], col[2]) }, btn)
		local lbl = mk("TextLabel", { Size = UDim2.new(1, -4, 1, 0), Position = UDim2.fromOffset(2, 0),
			BackgroundTransparency = 1, Text = text, Font = Enum.Font.FredokaOne, TextScaled = true,
			TextWrapped = false,   -- toujours sur UNE ligne : le texte rétrécit au lieu de se couper
			TextColor3 = WHITE, ZIndex = Z + 5 }, btn)
		-- MinTextSize = 1 : le mot rétrécit TOUJOURS assez pour tenir en entier (avec 8, Roblox
		-- le COUPAIT quand la place manquait, ex. « Price: Low » sur mobile)
		mk("UITextSizeConstraint", { MaxTextSize = textSize, MinTextSize = 1 }, lbl)
		mk("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, lbl)
		outlined(lbl, 1.2)
		local function recolor(c, txt)
			grad.Color = ColorSequence.new(c[1], c[2]) ; edge.BackgroundColor3 = c[3]
			lbl.TextColor3 = txt or WHITE
		end
		return btn, lbl, slot, recolor
	end

	-- 👒 types d'accessoire Roblox → nom affiché
	local TYPE_NAME = {
		[8] = "Hat", [41] = "Hair", [42] = "Face", [43] = "Neck", [44] = "Shoulder",
		[45] = "Front", [46] = "Back", [47] = "Waist", [19] = "Gear",
		[64] = "Clothing", [65] = "Clothing", [66] = "Clothing", [67] = "Clothing",
		[68] = "Clothing", [69] = "Clothing", [72] = "Clothing",
		[70] = "Shoes", [71] = "Shoes", [76] = "Face", [77] = "Face",
	}
	local TYPE_ORDER = { "Hat", "Hair", "Face", "Neck", "Shoulder", "Front", "Back", "Waist", "Clothing", "Shoes", "Gear", "Other" }
	-- SHOW : 1re ligne = le stock (un seul), 2e ligne = New + possession (un seul des deux)
	-- ⭐ les plus utiles en premier
	-- ✏️ libellés COURTS (lisibles même sur petit écran)
	local SHOW = { { "avail", "Available" }, { "notOwned", "Unowned" }, { "new", "New" },
		{ "low", "Few left" }, { "sold", "Sold out" }, { "owned", "Owned" } }
	local FLAG_LABEL = {}
	for _, x in ipairs(SHOW) do FLAG_LABEL[x[1]] = x[2] end
	local GROUP_OF = { avail = "stock", low = "stock", sold = "stock", owned = "own", notOwned = "own" }
	local GROUPS = { stock = { "avail", "low", "sold" }, own = { "owned", "notOwned" } }
	-- ⭐ les plus importants en premier : où il en reste le MOINS, puis le moins cher
	local SORTS = {
		{ id = "left_asc",   label = "Low stock" },  -- le moins de stock RESTANT (épuisés à la fin)
		{ id = "price_asc",  label = "Cheapest" },   -- prix croissant
		{ id = "price_desc", label = "Priciest" },   -- prix décroissant
		{ id = "left_desc",  label = "High stock" }, -- le plus de stock restant
		{ id = "default",    label = "Default" },
	}
	local SORT_LABEL = {}
	for _, x in ipairs(SORTS) do SORT_LABEL[x.id] = x.label end

	-- lectures Roblox (une seule fois, 4 à la fois max)
	local typesState, ownedState = "idle", "idle"
	local onTypesLoaded
	local function runPool(items, fn, done)
		local idx, left, finished = 0, #items, false
		local function check()
			if left <= 0 and not finished then finished = true ; done() end
		end
		if left == 0 then check() return end
		for _ = 1, math.min(4, #items) do
			task.spawn(function()
				while true do
					idx += 1
					local it = items[idx]
					if not it then break end
					pcall(fn, it)
					left -= 1
				end
				check()   -- done() n'est appelé qu'UNE fois, par le dernier à finir
			end)
		end
	end
	local function loadTypes()
		if typesState ~= "idle" then return end
		typesState = "loading"
		runPool(UGC_CONFIG.Items, function(ugc)
			local info = MarketplaceService:GetProductInfo(ugc.AssetId, Enum.InfoType.Asset)
			SF.typeOf[ugc.AssetId] = (type(info) == "table" and TYPE_NAME[info.AssetTypeId]) or "Other"
		end, function()
			typesState = "done"
			if onTypesLoaded then onTypesLoaded() end
		end)
	end
	local function loadOwned()
		if ownedState ~= "idle" then return end
		ownedState = "loading"
		runPool(UGC_CONFIG.Items, function(ugc)
			if SF.ownedMap[ugc.AssetId] ~= nil then return end
			local ok, owns = pcall(function() return MarketplaceService:PlayerOwnsAsset(player, ugc.AssetId) end)
			if ok then SF.ownedMap[ugc.AssetId] = owns == true end
		end, function()
			ownedState = "done"
			reorganizeGrid()
		end)
	end

	-- 📱🖥️📺 échelle : dessiné pour une fenêtre de 620 px de haut, avec un minimum
	--    lisible / touchable au doigt (mobile) et à distance (télé / console)
	-- 📏 tailles : TOUT suit la taille de la fenêtre du shop (et plus l'appareil). Avant, un
	--    minimum « mobile » rendait le bouton et le panneau trop gros sur téléphone.
	local function shopRatio()
		return math.min(ShopFrame.AbsoluteSize.Y / 620, ShopFrame.AbsoluteSize.X / 1100)
	end
	local function uiScaleValue()          -- bouton FILTER, message « aucun résultat »
		return math.clamp(shopRatio(), 0.35, 1.3)
	end
	local function panelScaleValue()       -- panneau : jamais plus large que 45 % de la fenêtre
		local s = math.clamp(shopRatio(), 0.4, 1.3)
		local maxW = ShopFrame.AbsoluteSize.X * 0.45
		if maxW > 1 and 300 * s > maxW then s = maxW / 300 end
		return s
	end
	local function padActive()
		return UIS:GetLastInputType().Name:sub(1, 7) == "Gamepad"
	end

	-- ── bouton FILTER (plat) ───────────────────────────────
	local BTN_W, BTN_H = 112, 32
	local fbtn = flatButton(ShopFrame, "", BLUE, UDim2.fromOffset(BTN_W, BTN_H), 17,
		{ Name = "FilterButton", AnchorPoint = Vector2.new(1, 0.5), SelectionImageObject = selTemplate })
	local fScale = mk("UIScale", {}, fbtn)
	local flbl = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(6, 0), Font = Enum.Font.FredokaOne, Text = "FILTER", TextSize = 17,
		TextColor3 = WHITE, ZIndex = Z + 1 }, fbtn)
	outlined(flbl, 1.2)
	local farrow = mk("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(14, 14), Font = SYM, Text = "▼",
		TextSize = 14, TextColor3 = WHITE, ZIndex = Z + 1 }, fbtn)
	-- 🎮 touche manette affichée à gauche du bouton (icône officielle Xbox / PlayStation)
	local padHint = mk("ImageLabel", { Name = "PadHint", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0), Size = UDim2.fromOffset(26, 26), Visible = false, ZIndex = Z + 1 }, fbtn)
	local padHintTxt = mk("TextLabel", { BackgroundColor3 = Color3.fromRGB(30, 30, 36), Size = UDim2.fromScale(1, 1),
		Text = "Y", Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = SELC, Visible = false, ZIndex = Z + 1 }, padHint)
	round(padHintTxt, 999)
	do
		local ok, img = pcall(function() return UIS:GetImageForKeyCode(Enum.KeyCode.ButtonY) end)
		if ok and type(img) == "string" and img ~= "" then padHint.Image = img else padHintTxt.Visible = true end
	end

	-- ── pastilles des filtres actifs (au-dessus de la grille) ───
	local sfPos, sfSize = ScrollingFrame.Position, ScrollingFrame.Size
	local CHIP_H = 0.052
	local chipsBar = mk("ScrollingFrame", { Name = "ActiveFilters", BackgroundTransparency = 1,
		Position = sfPos, Size = UDim2.new(sfSize.X.Scale, sfSize.X.Offset, CHIP_H, 0),
		ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0, BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), Visible = false, Selectable = false }, ShopFrame)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, chipsBar)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 4) }, chipsBar)

	-- ── message « aucun résultat » (posé sur la fenêtre, par-dessus la grille) ──
	local empty = mk("Frame", { Name = "NoFilterResult", BackgroundTransparency = 1,
		Size = UDim2.new(sfSize.X.Scale, sfSize.X.Offset, 0.3, 0),
		Position = UDim2.new(sfPos.X.Scale, sfPos.X.Offset, sfPos.Y.Scale + 0.2, 0), Visible = false }, ShopFrame)
	local emptyTxt = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30),
		Font = Enum.Font.FredokaOne, Text = "No UGC match your filters", TextColor3 = WHITE, TextSize = 22 }, empty)
	outlined(emptyTxt, 1.5)
	local emptyBtn = flatButton(empty, "RESET FILTERS", RED, UDim2.fromOffset(170, 36), 17,
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), SelectionImageObject = selTemplate })
	local emptyScale = mk("UIScale", {}, empty)

	-- ── le panneau ──────────────────────────────────────────
	--   holder (coupe ce qui dépasse ; sa hauteur se DÉROULE depuis le bouton)
	--     ├ notch : petite pointe sous le bouton FILTER (on voit que ça vient de lui)
	--     └ body  : le panneau, léger contour noir
	--         ├ scroll : SHOW · TYPE · SORT BY (défile sur les petits écrans)
	--         └ foot   : APPLY (vert, à gauche) · RESET (rouge, à droite), DANS le panneau,
	--                    sous un trait, hors de la partie qui défile
	local PW, NOTCH, PAD, GAPS = 300, 8, 10, 6
	local CELL_H, CELL_GAP, TITLE_H = 34, 6, 20
	local BAR_H, FOOT_PAD = 36, 8
	local FOOT_H = BAR_H + FOOT_PAD * 2 + 1
	local EDGE = 2          -- marge pour que le contour ne soit pas coupé
	local bodyH = 200       -- partie qui défile (sans le pied)
	local isOpen = false
	local holder = mk("Frame", { Name = "FilterPanel", AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(PW, 0), BackgroundTransparency = 1, ClipsDescendants = true,
		Visible = false, Active = true, SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop, SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop, SelectionBehaviorRight = Enum.SelectionBehavior.Stop }, ShopFrame)
	local pScale = mk("UIScale", {}, holder)
	-- 🛡️ bouclier invisible sous le panneau : un clic sur le panneau ne passe JAMAIS aux cartes /
	--    boutons du shop qui sont derrière (un simple Frame ne bloque pas les clics, un bouton oui).
	mk("TextButton", { Name = "ClickBlocker", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, Selectable = false, ZIndex = Z }, holder)
	local OUTLINE = { Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.45,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
	local notchX = PW - EDGE - BTN_W / 2
	local notch = mk("Frame", { Name = "Notch", AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
		Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(notchX, NOTCH + 2),
		BackgroundColor3 = NAVY, BorderSizePixel = 0, ZIndex = Z + 1 }, holder)
	round(notch, 3)
	mk("UIStroke", OUTLINE, notch)
	local body = mk("Frame", { Name = "Body", Position = UDim2.fromOffset(EDGE, NOTCH),
		Size = UDim2.fromOffset(PW - EDGE * 2, bodyH + FOOT_H),
		BackgroundColor3 = NAVY, BorderSizePixel = 0, ZIndex = Z + 2 }, holder)
	round(body, 12)
	mk("UIStroke", OUTLINE, body)
	-- raccord pointe ↔ panneau : on cache le trait du contour sous la pointe
	local notchJoin = mk("Frame", { Name = "NotchJoin", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(19, 4),
		Position = UDim2.fromOffset(notchX, NOTCH), BackgroundColor3 = NAVY, BorderSizePixel = 0, ZIndex = Z + 3 }, holder)
	local scroll = mk("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Selectable = false,
		Size = UDim2.new(1, 0, 1, -FOOT_H), AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		ScrollBarThickness = 4, ScrollBarImageColor3 = BLUE, ScrollBarImageTransparency = 0.3, ZIndex = Z + 2 }, body)
	mk("UIPadding", { PaddingTop = UDim.new(0, PAD), PaddingBottom = UDim.new(0, PAD),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, scroll)
	mk("UIListLayout", { Padding = UDim.new(0, GAPS), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	local foot = mk("Frame", { Name = "Buttons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, FOOT_H), ZIndex = Z + 2 }, body)
	mk("Frame", { Name = "Line", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6, BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 0, 1), ZIndex = Z + 3 }, foot)
	local applyB = button3D(foot, "APPLY", COL.green, UDim2.new(0.5, -16, 0, BAR_H), 16,
		{ Position = UDim2.new(0, 12, 0, 1 + FOOT_PAD) })
	local resetB = button3D(foot, "RESET", COL.red, UDim2.new(0.5, -16, 0, BAR_H), 16,
		{ Position = UDim2.new(0.5, 4, 0, 1 + FOOT_PAD) })

	-- ── contenu ─────────────────────────────────────────────
	local draft
	local function copyState()
		local t = {}
		for k, v in pairs(SF.f) do if k ~= "types" then t[k] = v end end
		t.types = table.clone(SF.f.types)
		return { f = t, sort = SF.sort }
	end
	local painters, firstBtn = {}, nil
	local function repaint() for _, fn in ipairs(painters) do fn() end end
	local order, contentH = 0, 0
	local function nextO() order += 1 return order end
	local function addH(h) contentH += (order > 1 and GAPS or 0) + h end
	local function title(text)
		mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, TITLE_H), Font = Enum.Font.FredokaOne,
			Text = text, TextColor3 = SUB, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = nextO(), ZIndex = Z + 3 }, scroll)
		addH(TITLE_H)
	end
	-- grille de boutons 3D fixes (3 par ligne) ; state(id) → "on" | "off"
	--   (les choix contraires gardent leur couleur normale : en prendre un retire simplement l'autre)
	local function grid(items, state, onClick)
		local g = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextO(), ZIndex = Z + 3 }, scroll)
		mk("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, CELL_H), CellPadding = UDim2.fromOffset(8, CELL_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder }, g)
		local rows = math.ceil(#items / 3)
		addH(rows * CELL_H + (rows - 1) * CELL_GAP)
		for k, it in ipairs(items) do
			local b, _, _, recolor = button3D(g, it.label, COL.slate, UDim2.fromOffset(0, CELL_H), 14, { LayoutOrder = k })
			if not firstBtn then firstBtn = b end
			local function p()
				if not draft then return end
				local st = state(it.id)
				recolor(st == "on" and COL.blue or COL.slate, WHITE)
			end
			table.insert(painters, p) ; p()
			b.Activated:Connect(function() if draft then onClick(it.id) ; repaint() end end)
		end
	end
	local function flagState(id)
		local f = draft.f
		return f[id] and "on" or "off"
	end
	local function build()
		for _, c in ipairs(scroll:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		table.clear(painters) ; firstBtn = nil
		order, contentH = 0, 0
		-- ⭐ ordre : SORT BY (le plus utilisé) · SHOW · TYPE
		title("SORT BY")
		grid(SORTS, function(id)
			return draft.sort == id and "on" or "off"
		end, function(id) draft.sort = (draft.sort == id and id ~= "default") and "default" or id end)
		title("SHOW")
		local showItems = {}
		for _, x in ipairs(SHOW) do table.insert(showItems, { id = x[1], label = x[2] }) end
		grid(showItems, flagState, function(id)
			local f = draft.f
			local was = f[id] == true
			local g = GROUP_OF[id]
			if g then for _, o in ipairs(GROUPS[g]) do f[o] = false end end   -- un seul par groupe
			f[id] = not was
		end)
		-- TYPE : seulement si le shop contient au moins 2 types (plusieurs choix possibles)
		if typesState == "done" then
			local present, list = {}, {}
			for _, ugc in ipairs(UGC_CONFIG.Items) do present[SF.typeOf[ugc.AssetId] or "Other"] = true end
			for _, t in ipairs(TYPE_ORDER) do if present[t] then table.insert(list, { id = t, label = t }) end end
			if #list >= 2 then
				title("TYPE")
				grid(list, function(id) return draft.f.types[id] and "on" or "off" end,
					function(id) draft.f.types[id] = (not draft.f.types[id]) or nil end)
			end
		end
		contentH += PAD * 2
	end

	-- ── placement : bord droit = bord droit de la carte la plus à droite ──
	local function fullH() return NOTCH + bodyH + FOOT_H + EDGE end
	local function layoutPanel()
		body.Size = UDim2.fromOffset(PW - EDGE * 2, bodyH + FOOT_H)
		if isOpen then holder.Size = UDim2.fromOffset(PW, fullH()) end
	end
	local room = 400
	local function place()
		local sc, psc = uiScaleValue(), panelScaleValue()
		fScale.Scale, pScale.Scale, emptyScale.Scale = sc, psc, sc
		-- la pointe reste sous le CENTRE du bouton (bouton et panneau n'ont pas la même échelle)
		local nx = PW - EDGE - (BTN_W / 2) * sc / psc
		notch.Position = UDim2.fromOffset(nx, NOTCH + 2)
		notchJoin.Position = UDim2.fromOffset(nx, NOTCH)
		local shopAbs = ShopFrame.AbsolutePosition
		local w = ScrollingFrame.AbsoluteWindowSize.X
		if w <= 1 or ShopFrame.AbsoluteSize.X <= 1 then return end
		local right = ScrollingFrame.AbsolutePosition.X - shopAbs.X + w * (1 - GAP_SCALE)
		local restocked = ShopFrame:FindFirstChild("restocked")
		local cy = restocked and (restocked.AbsolutePosition.Y - shopAbs.Y + restocked.AbsoluteSize.Y / 2)
			or (ShopFrame.AbsoluteSize.Y * 0.045)
		fbtn.Position = UDim2.fromOffset(right, cy)
		local top = cy + (BTN_H / 2) * sc
		holder.Position = UDim2.fromOffset(right, top)
		-- hauteur dispo dans la fenêtre : au-delà, le panneau défile (petits écrans)
		room = math.max(CELL_H * 3, (ShopFrame.AbsoluteSize.Y - top - 10) / psc - NOTCH - FOOT_H - EDGE)
		bodyH = math.min(contentH, room)
		layoutPanel()
	end
	for _, sig in ipairs({ ShopFrame:GetPropertyChangedSignal("AbsoluteSize"), ShopFrame:GetPropertyChangedSignal("AbsolutePosition"),
		ScrollingFrame:GetPropertyChangedSignal("AbsoluteWindowSize") }) do
		sig:Connect(place)
	end

	-- ── état actif visible : bouton + pastilles + grille décalée ──
	local renderChips
	local function paintButton()
		local n = SF.count()
		flbl.Text = n > 0 and ("FILTER (" .. n .. ")") or "FILTER"
		fbtn.BackgroundColor3 = n > 0 and YELLOW or BLUE
		farrow.Text = isOpen and "▲" or "▼"
	end
	local function commit()
		paintButton()
		renderChips()
		if SF.f.owned or SF.f.notOwned then loadOwned() end
		reorganizeGrid()
	end
	local function resetAll()
		SF.f = { avail = false, sold = false, low = false, owned = false, notOwned = false, new = false, types = {} }
		SF.sort = "default"
		commit()
	end
	local function chip(text, colr, onClick, orderN)
		-- tout suit la hauteur de la barre (= taille de la fenêtre du shop) : même look PC / mobile
		local h = chipsBar.AbsoluteSize.Y > 4 and chipsBar.AbsoluteSize.Y or 24
		local c = mk("TextButton", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, math.floor(h * 0.84)),
			BackgroundColor3 = colr, Text = "", AutoButtonColor = true, LayoutOrder = orderN,
			SelectionImageObject = selTemplate }, chipsBar)
		round(c, 999)
		local pad = math.max(3, math.floor(h * 0.4))
		mk("UIPadding", { PaddingLeft = UDim.new(0, pad), PaddingRight = UDim.new(0, pad) }, c)
		local l = mk("TextLabel", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
			Font = Enum.Font.FredokaOne, Text = text, TextColor3 = WHITE,
			TextSize = math.clamp(math.floor(h * 0.5), 6, 16) }, c)
		outlined(l, h < 20 and 0.6 or 1)
		c.Activated:Connect(onClick)
	end
	renderChips = function()
		for _, c in ipairs(chipsBar:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		local on = SF.count() > 0
		chipsBar.Visible = on
		local lay = chipsBar:FindFirstChildOfClass("UIListLayout")
		if lay then lay.Padding = UDim.new(0, math.max(3, math.floor(chipsBar.AbsoluteSize.Y * 0.2))) end
		ScrollingFrame.Position = on and UDim2.new(sfPos.X.Scale, sfPos.X.Offset, sfPos.Y.Scale + CHIP_H + 0.006, sfPos.Y.Offset) or sfPos
		ScrollingFrame.Size = on and UDim2.new(sfSize.X.Scale, sfSize.X.Offset, sfSize.Y.Scale - CHIP_H - 0.006, sfSize.Y.Offset) or sfSize
		if not on then return end
		local n = 0
		local function nx() n += 1 return n end
		chip("RESET", RED, resetAll, nx())
		for _, x in ipairs(SHOW) do
			local key = x[1]
			if SF.f[key] then chip(x[2] .. " X", OFF, function() SF.f[key] = false ; commit() end, nx()) end
		end
		for _, t in ipairs(TYPE_ORDER) do
			if SF.f.types[t] then chip(t .. " X", OFF, function() SF.f.types[t] = nil ; commit() end, nx()) end
		end
		if SF.sort ~= "default" and SORT_LABEL[SF.sort] then
			chip(SORT_LABEL[SF.sort] .. " X", BLUE, function() SF.sort = "default" ; commit() end, nx())
		end
	end
	-- 📱 la fenêtre change de taille (rotation, ouverture) → les pastilles suivent
	do
		local lastH, pending = -1, false
		chipsBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local hNow = math.floor(chipsBar.AbsoluteSize.Y)
			if hNow == lastH or pending then return end
			pending = true
			task.defer(function()
				pending = false
				lastH = math.floor(chipsBar.AbsoluteSize.Y)
				if chipsBar.Visible then renderChips() end
			end)
		end)
	end
	SF.onRender = function(shown)
		empty.Visible = shown == 0 and SF.count() > 0
			and not ((SF.f.owned or SF.f.notOwned) and ownedState ~= "done")   -- pas de faux « aucun résultat »
	end

	-- ── déroulement / rembobinage ───────────────────────────
	--   ouvrir : le panneau se DÉROULE depuis le bouton ; refermer : il remonte dedans
	local ROLL = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local token = 0
	local function roll(open)
		token += 1
		local my = token
		isOpen = open
		paintButton()
		if open then
			holder.Visible = true
			holder.Size = UDim2.fromOffset(PW, 0)
			scroll.CanvasPosition = Vector2.zero
			TweenService:Create(holder, ROLL, { Size = UDim2.fromOffset(PW, fullH()) }):Play()
		else
			local t1 = TweenService:Create(holder, ROLL, { Size = UDim2.fromOffset(PW, 0) })
			t1:Play()
			t1.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed and my == token and not isOpen then holder.Visible = false end
			end)
		end
	end
	local function openPanel()
		draft = copyState()
		loadTypes()
		build()
		place()
		roll(true)
		if padActive() and firstBtn then GuiService.SelectedObject = firstBtn end
	end
	-- refermer = annuler (rien n'est appliqué sans APPLY)
	local function closePanel()
		draft = nil
		roll(false)
		local sel = GuiService.SelectedObject
		if sel and sel:IsDescendantOf(holder) then GuiService.SelectedObject = padActive() and fbtn or nil end
	end
	local function toggle() if isOpen then closePanel() else openPanel() end end
	onTypesLoaded = function()
		-- les types arrivent pendant que le panneau est ouvert : on le reconstruit (les choix en cours sont gardés)
		if isOpen and draft then
			local wasPad = GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(holder)
			build() ; place()
			if wasPad and firstBtn then GuiService.SelectedObject = firstBtn end
		end
	end

	resetB.Activated:Connect(function() closePanel() ; resetAll() end)
	applyB.Activated:Connect(function()
		if not draft then return end
		SF.f, SF.sort = draft.f, draft.sort
		closePanel()
		commit()
	end)
	fbtn.Activated:Connect(toggle)
	emptyBtn.Activated:Connect(resetAll)

	--════════════════════════════════════════════════════════
	-- 🎮 MANETTE : tout le shop
	--════════════════════════════════════════════════════════
	ShopFrame.SelectionGroup = true   -- la sélection ne sort pas du shop
	for _, k in ipairs({ "SelectionBehaviorUp", "SelectionBehaviorDown", "SelectionBehaviorLeft", "SelectionBehaviorRight" }) do
		ShopFrame[k] = Enum.SelectionBehavior.Stop
	end
	ScrollingFrame.Selectable = false   -- on va directement sur les cartes (la grille défile toute seule)
	local function styleSel(d)
		if d:IsA("GuiButton") and d.SelectionImageObject == nil then d.SelectionImageObject = selTemplate end
	end
	for _, d in ipairs(ShopFrame:GetDescendants()) do styleSel(d) end
	ShopFrame.DescendantAdded:Connect(styleSel)

	local function firstCard()
		local best, bp
		for _, fr in pairs(buttonFrames) do
			if fr and fr.Parent and fr.Visible then
				local b = fr:FindFirstChildOfClass("ImageButton") or fr:FindFirstChildWhichIsA("GuiButton", true)
				if b then
					local pos = fr.AbsolutePosition
					if not bp or pos.Y < bp.Y - 2 or (math.abs(pos.Y - bp.Y) <= 2 and pos.X < bp.X) then best, bp = b, pos end
				end
			end
		end
		return best
	end
	local function closeButton()
		local t = ShopFrame:FindFirstChild("ShopToggle")
		return (t and t:IsA("GuiButton")) and t or nil
	end
	local ACTION = "UGCShopPad"
	local function onPad(_, state, input)
		if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		if input.KeyCode == Enum.KeyCode.ButtonY then
			toggle()
			return Enum.ContextActionResult.Sink
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			if isOpen then
				closePanel()
			else
				ShopFrame.Visible = false   -- = le bouton de fermeture du shop
			end
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
	local bound = false
	local function setPadBinding(on)
		if on == bound then return end
		bound = on
		if on then
			CAS:BindActionAtPriority(ACTION, onPad, false, Enum.ContextActionPriority.High.Value,
				Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonB)
		else
			CAS:UnbindAction(ACTION)
		end
	end
	local function paintHint()
		padHint.Visible = padActive() or (IS_TV and UIS.GamepadEnabled)
	end
	UIS.LastInputTypeChanged:Connect(function()
		paintHint()
		-- la manette reprend la main pendant que le shop est ouvert : on lui donne une sélection
		if padActive() and ShopFrame.Visible and not GuiService.SelectedObject then
			GuiService.SelectedObject = (isOpen and firstBtn) or firstCard() or fbtn
		end
	end)
	local function onShopVisible()
		if ShopFrame.Visible then
			task.defer(place)
			setPadBinding(true)
			paintHint()
			if padActive() then
				task.delay(0.1, function()
					if ShopFrame.Visible then GuiService.SelectedObject = firstCard() or fbtn or closeButton() end
				end)
			end
		else
			setPadBinding(false)
			if isOpen then
				token += 1
				draft = nil ; isOpen = false ; holder.Visible = false ; holder.Size = UDim2.fromOffset(PW, 0)
				paintButton()
			end
			local sel = GuiService.SelectedObject
			if sel and sel:IsDescendantOf(ShopFrame) then GuiService.SelectedObject = nil end
		end
	end
	ShopFrame:GetPropertyChangedSignal("Visible"):Connect(onShopVisible)
	task.defer(onShopVisible)
	paintButton()
end
buildFilterUI()
