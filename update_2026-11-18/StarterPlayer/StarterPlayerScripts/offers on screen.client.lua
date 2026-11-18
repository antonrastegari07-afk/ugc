-- ========================================
-- 🎁 OFFERS DISPLAY + REFERRAL — Tout-en-un
-- LocalScript · StarterPlayerScripts
-- (Remplace l'ancien REFERRAL CLIENT)
--
-- UI pré-construite :
--   ScreenGui "Offers" > Bouton "Offers"
--       ├─ WhiteRays (ImageLabel, fond rotatif)
--       └─ Image     (ImageLabel, image de l'offre)
--             ├─ Price     (TextLabel RichText : "<robux> 199" OU "GRATUIT")
--             └─ OfferText (TextLabel : description perso)
-- ========================================

local Players            = game:GetService("Players")
local MarketplaceService = require(game.ReplicatedStorage.MarketplaceServiceFX)
local SocialService      = game:GetService("SocialService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local GuiService         = game:GetService("GuiService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local SoundService       = game:GetService("SoundService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ========================================
-- ⚙️ CONFIG — LISTE DES OFFRES
-- ========================================
-- TYPES :
--   kind = "invite"   → Offre d'amis GRATUITE (ouvre le prompt d'invitation)
--   passId    = <id>  → Game Pass (achat unique, masqué si déjà possédé)
--   productId = <id>  → Developer Product (répétable : points, boost…)
--
-- CHAMPS :
--   image     = "rbxassetid://..."  → image (ImageLabel "Image")
--   price     = <nombre>            → chiffre dans "Price" (ignoré si kind="invite")
--   offerText = "..."               → description (TextLabel "OfferText", \n ok)
--   requiresPass = <passId>         → (option) n'apparaît que si ce pass est possédé
-- ========================================
local OFFERS = {
	{
		kind      = "invite",
		category  = "invite",
		image     = "rbxassetid://86772519223919",
		offerText = "Invite friend",
	},
	
	
	
	
	{
		passId    = 1889633102,
		category  = "pack",
		image     = "rbxassetid://75116114456987",
		price     = 7,
		offerText = "Starter Pack\n+10,000 pts + 1 spin",
	},
	{
		passId    = 1890203086,
		category  = "pack",
		image     = "rbxassetid://120761036868465",
		price     = 25,
		offerText = "Expert Pack\n+30,000 pts + 3 spin",
	},
	
	
	
	
	{
		passId    = 1891019055,
		category  = "Gun",
		image     = "rbxassetid://102811377007208",
		price     = 15,
		offerText = "AK47 \nPVP gun" ,
	},
	
	{
		passId    = 1889765109,
		category  = "Gun",
		image     = "rbxassetid://83159459903636",
		price     = 9,
		offerText = "Shotgun \nPVP gun" ,
	},
	{
		passId    = 1890101132,
		category  = "Gun",
		image     = "rbxassetid://132199729083079",
		price     = 25,
		offerText = "Minigun \nPVP gun" ,
	},
	{
		passId    = 1889945094,
		category  = "Gun",
		image     = "rbxassetid://86392492361829",
		price     = 49,
		offerText = "RPG \nPVP gun" ,
	},
	
	
	
	
	
	{
		passId    = 1889735131,
		category  = "Pack",
		image     = "rbxassetid://114100906523192",
		price     = 49,
		offerText = "Slap Hand" ,
	},
	
	
	
	
	{
		productId = 3606598188,
		category  = "points",
		image     = "rbxassetid://98293332133608",
		price     = 2,
		offerText = "+1,000 Points!",
		aspect    = 1.3,   -- largeur/hauteur de l'image (ex: 300x200 → 1.5)
		imageScale = 1.5,   -- (option) grossit l'image uniformément, centré. Rien = 1 = inchangé
	},
	{
		productId = 3606598763,
		category  = "points",
		image     = "rbxassetid://98293332133608",
		price     = 4,
		offerText = "+2,500 Point!",
		aspect    = 1.3,   -- largeur/hauteur de l'image (ex: 300x200 → 1.5)
		imageScale = 1.5,   -- (option) grossit l'image uniformément, centré. Rien = 1 = inchangé
	},
	{
		productId = 3606598849,
		category  = "points",
		image     = "rbxassetid://90346834918088",
		price     = 29,
		offerText = "+100,000 Points!",
		aspect    = 1.3,   -- largeur/hauteur de l'image (ex: 300x200 → 1.5)
		imageScale = 1.5,   -- (option) grossit l'image uniformément, centré. Rien = 1 = inchangé
	},
	{
		productId = 3606598712,
		category  = "points",
		image     = "rbxassetid://124304939790204",
		price     = 149,
		offerText = "+500,000 Points!",
		aspect    = 1.3,   -- largeur/hauteur de l'image (ex: 300x200 → 1.5)
		imageScale = 1.5,   -- (option) grossit l'image uniformément, centré. Rien = 1 = inchangé
	},
	{
		productId = 3606598746,
		category  = "points",
		image     = "rbxassetid://82911536609121",
		price     = 499,
		offerText = "+2,000,000 Points!",
		aspect    = 1.3,   -- largeur/hauteur de l'image (ex: 300x200 → 1.5)
		imageScale = 1.5,   -- (option) grossit l'image uniformément, centré. Rien = 1 = inchangé
	},
	
	
	
	{
		productId = 3606596221,   -- ⚠️ ton vrai productId boost
		category  = "boost",
		image     = "rbxassetid://123961835925963",
		price     = 29,
		offerText = "x25 Point Boost\nfor 30 min",
	},
	{
		productId = 3606596018,   -- ⚠️ ton vrai productId boost
		category  = "boost",
		image     = "rbxassetid://120321194799825",
		price     = 15,
		offerText = "x10 Point Boost\nfor 30 min",
	},
	{
		productId = 3606595906,   -- ⚠️ ton vrai productId boost
		category  = "boost",
		image     = "rbxassetid://123564260314375",
		price     = 9,
		offerText = "x5 Point Boost\nfor 30 min",
	},
	{
		productId = 3606595683,   -- ⚠️ ton vrai productId boost
		category  = "boost",
		image     = "rbxassetid://121093024056816",
		price     = 5,
		offerText = "x2 Point Boost\nfor 30 min",
	},
}

-- ========================================
-- ⚙️ CONFIG — TIMINGS & FEEL
-- ========================================
local FIRST_DELAY    = 5      -- délai avant la 1ère offre (s)
local DISPLAY_TIME   = 12     -- durée d'affichage de chaque offre (s)
local GAP_TIME       = 0.20   -- pause entre l'outro et le pop suivant (s)
local ROTATION_SPEED = 25     -- 🔧 vitesse des rayons (°/s)

local HOVER_SCALE    = 1.06   -- grossissement au survol
local CLICK_PUNCH    = 0.90   -- creux du punch au clic

local FREE_COLOR     = Color3.fromRGB(50, 220, 80)  -- vert "GRATUIT"
local FREE_TEXT      = "Free"

-- ⚠️ COLLE ICI ton icône Robux telle qu'elle apparaît dans le texte Price.
--    Exemples possibles :  '<img src="rbxassetid://XXXX"/> '   ou   un glyphe.
--    Le chiffre du prix sera ajouté juste après.
local ROBUX_RICH     = ""   -- ex: '<img src="rbxasset://textures/ui/common/robux.png"/> '

local INVITE_MESSAGE = "🎁 Join me and we'll both get 3,000 Points!"

-- ========================================
-- SONS
-- ========================================
local buySound  = SoundService:FindFirstChild("POP")
local POP_SOUND = buySound

-- ========================================
-- REMOTE EVENTS (referral)
-- ========================================
local referralRewardEvent   = ReplicatedStorage:WaitForChild("ReferralRewardNotify",  15)
local referralReceivedEvent = ReplicatedStorage:WaitForChild("ReferralReceivedEvent", 15)
local promptInviteEvent     = ReplicatedStorage:WaitForChild("PromptInvite",          15)

-- ========================================
-- UTILITAIRES
-- ========================================
local function isMobile()
	return UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled
		and not UserInputService.MouseEnabled
end

local function getTopInset()
	return GuiService:GetGuiInset().Y
end

local function formatPoints(n)
	if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
	if n >= 1000    then return string.format("%dk",   math.floor(n / 1000)) end
	return tostring(n)
end

local function playPop()
	if POP_SOUND then pcall(function() POP_SOUND:Play() end) end
end

-- ========================================
-- 💎 PRIX PREMIUM (-10%, arrondi vers le haut)
-- ⚠️ Affichage SEULEMENT. Le débit Roblox réel reste le prix du produit/pass.
-- ========================================
local function hasPremium()
	return player.MembershipType == Enum.MembershipType.Premium
end

-- 1.1 → 2, 9.0 → 9 (math.ceil après -10%)
local function displayPrice(basePrice)
	if not basePrice then return "" end
	if hasPremium() then
		return tostring(math.ceil(basePrice * 0.9))
	end
	return tostring(basePrice)
end

-- Pre-check CanSendGameInvite
local canInviteCache   = false
local canInviteChecked = false
task.spawn(function()
	local ok, result = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	canInviteCache   = ok and result or false
	canInviteChecked = true
end)

-- ========================================
-- ░░ CARROUSEL D'OFFRES ░░
-- ========================================
local screenGui = playerGui:WaitForChild("Offers")
local button    = screenGui:WaitForChild("Offers")
local whiteRays = button:WaitForChild("WhiteRays")
local imageNode = button:WaitForChild("Image")
local priceLbl  = imageNode:WaitForChild("Price")
local offerLbl  = imageNode:WaitForChild("OfferText")

-- 📐 Image INTERNE dédiée : grossit SANS jamais toucher Price / OfferText
local imgInner = imageNode:FindFirstChild("ImageInner")
if not imgInner then
	imgInner = Instance.new("ImageLabel")
	imgInner.Name = "ImageInner"
	imgInner.BackgroundTransparency = 1
	imgInner.AnchorPoint = Vector2.new(0.5, 0.5)
	imgInner.Position    = UDim2.fromScale(0.5, 0.5)
	imgInner.Size        = UDim2.fromScale(1, 1)
	imgInner.ScaleType   = Enum.ScaleType.Fit
	imgInner.ZIndex      = imageNode.ZIndex
	imgInner.Parent      = imageNode
end
imageNode.ImageTransparency = 1                  -- le cadre ne dessine plus l'image lui-même
priceLbl.ZIndex = imageNode.ZIndex + 1           -- textes au-dessus de l'image interne
offerLbl.ZIndex = imageNode.ZIndex + 1
-- 💡 Pour un pop bien centré, AnchorPoint du bouton = (0.5, 0.5).

local PRICE_BASE_COLOR = priceLbl.TextColor3

local uiScale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
uiScale.Parent = button
uiScale.Scale  = 0
button.Visible = false

local showing      = false
local busy         = false
local currentOffer = nil
local ownsCache    = {}   -- [passId] = true/false (résultat connu, jamais re-query dans la boucle)
-- 🎯 Engagement par catégorie (session) : pondère le tirage aléatoire
local categoryEngagement = {}     -- [catégorie] = score d'intérêt du joueur
local CLICK_WEIGHT       = 1      -- + poids quand le joueur CLIQUE une offre
local PURCHASE_WEIGHT    = 5      -- + poids quand le joueur ACHÈTE (plus fort qu'un clic)
local addEngagementCat            -- défini plus bas (après offerCategory)

-- ⚡ Lecture cache-only : NE YIELD JAMAIS → la boucle du carrousel ne peut plus freeze
local function ownsPass(id)
	return ownsCache[id] == true
end

-- 🔄 Toutes les vérifs UserOwnsGamePassAsync se font ICI, thread séparé + throttlé.
--    => zéro appel web dans pickNextOffer / isShowable (c'était la cause du gel).
task.spawn(function()
	local passList, seen = {}, {}
	local function add(pid)
		if pid and not seen[pid] then seen[pid] = true; passList[#passList + 1] = pid end
	end
	for _, o in ipairs(OFFERS) do add(o.passId); add(o.requiresPass) end

	while true do
		for _, pid in ipairs(passList) do
			if ownsCache[pid] ~= true then          -- inutile de re-checker ceux déjà possédés
				local owns = false
				local ok = pcall(function()
					owns = MarketplaceService:UserOwnsGamePassAsync(player.UserId, pid)
				end)
				if ok then ownsCache[pid] = owns end
				task.wait(0.5)                       -- throttle anti rate-limit
			end
		end
		task.wait(30)                                -- re-scan léger toutes les 30 s
	end
end)

-- Rotation des rayons
RunService.Heartbeat:Connect(function(dt)
	if button.Visible then
		whiteRays.Rotation = (whiteRays.Rotation + ROTATION_SPEED * dt) % 360
	end
end)

local function popIn()
	button.Visible = true
	uiScale.Scale  = 0
	playPop()
	local t = TweenService:Create(uiScale,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 })
	t:Play()
	t.Completed:Wait()
end

local function popOut()
	showing = false
	local t = TweenService:Create(uiScale,
		TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Scale = 0 })
	t:Play()
	t.Completed:Wait()
	button.Visible = false
end

local function applyOffer(offer)
	-- 📐 Aspect + grossissement appliqués SEULEMENT à l'image interne (centrée)
	local imgAspect = imgInner:FindFirstChildOfClass("UIAspectRatioConstraint")
		or Instance.new("UIAspectRatioConstraint", imgInner)
	imgAspect.AspectType   = Enum.AspectType.FitWithinMaxSize
	imgAspect.DominantAxis = Enum.DominantAxis.Width
	imgAspect.AspectRatio  = offer.aspect or 1

	imgInner.Image = offer.image or ""
	local f = offer.imageScale or 1
	imgInner.Size  = UDim2.fromScale(f, f)        -- grossit autour du centre (anchor 0.5,0.5)

	offerLbl.Text  = offer.offerText or ""

	if offer.kind == "invite" then
		-- Gratuit : "GRATUIT" en vert, pas d'icône Robux
		priceLbl.Text       = FREE_TEXT
		priceLbl.TextColor3 = FREE_COLOR
	else
		-- Payant : icône Robux + chiffre (réduit -10% si Premium, arrondi haut)
		priceLbl.Text       = ROBUX_RICH .. displayPrice(offer.price)
		priceLbl.TextColor3 = PRICE_BASE_COLOR
	end
end

-- Hover
button.MouseEnter:Connect(function()
	if not showing or busy then return end
	TweenService:Create(uiScale,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad), { Scale = HOVER_SCALE }):Play()
end)
button.MouseLeave:Connect(function()
	if not showing then return end
	TweenService:Create(uiScale,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
end)

-- Invitation (déclaré ici, défini plus bas après les notifs)
local doInvite

local function activateCurrentOffer()
	if busy or not currentOffer then return end
	busy = true
	local offer = currentOffer
	addEngagementCat(offer.category, CLICK_WEIGHT)   -- 🎯 intérêt pour cette catégorie
	task.spawn(function()
		local ok = pcall(function()
			if offer.kind == "invite" then
				doInvite()
			elseif offer.productId then
				MarketplaceService:PromptProductPurchase(player, offer.productId)
			elseif offer.passId then
				MarketplaceService:PromptGamePassPurchase(player, offer.passId)
			end
		end)
		if not ok then warn("⚠️ [OFFERS] échec ouverture de l'offre") end
		task.wait(0.5)
		busy = false
	end)
end

button.MouseButton1Click:Connect(function()
	if not showing then return end
	playPop()
	local down = TweenService:Create(uiScale,
		TweenInfo.new(0.07, Enum.EasingStyle.Quad), { Scale = CLICK_PUNCH })
	down:Play()
	down.Completed:Once(function()
		TweenService:Create(uiScale,
			TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
	end)
	activateCurrentOffer()
end)

-- Catégorie d'une offre (fallback si non précisée)
local function offerCategory(o)
	if o.category then return o.category end
	if o.kind == "invite" then return "invite" end
	if o.passId then return "pass" end
	if o.productId then return "product" end
	return "misc"
end

-- Lookups productId/passId → catégorie (pour les events d'achat)
local categoryByProduct = {}
local categoryByPass    = {}
for _, o in ipairs(OFFERS) do
	if o.productId then categoryByProduct[o.productId] = offerCategory(o) end
	if o.passId    then categoryByPass[o.passId]       = offerCategory(o) end
end
-- 🎯 Enregistre l'intérêt du joueur pour une catégorie (clic / achat)
function addEngagementCat(cat, amount)
	if not cat then return end
	categoryEngagement[cat] = (categoryEngagement[cat] or 0) + (amount or 1)
end

local forcedCategory   = nil    -- catégorie à proposer en priorité après un achat
local interruptDisplay = false  -- coupe l'affichage courant pour enchaîner

-- 🔒 Verrou de catégorie (ex: UGC shop ouvert → points only, rate custom)
local lockedCategory    = nil   -- si non-nil : SEULE cette catégorie tourne
local lockedDisplayTime = nil   -- durée d'affichage custom pendant le verrou

local function isShowable(cand)
	if cand.requiresPass and not ownsPass(cand.requiresPass) then return false end
	if cand.passId and ownsPass(cand.passId) then return false end  -- pass déjà possédé
	return true
end

-- 🎲 Sac de tirage : montre TOUTES les offres affichables avant d'en répéter une.
--    Vide → on repart (nouveau cycle). Le tirage DANS le sac est pondéré par
--    l'engagement : catégories cliquées/achetées sortent plus tôt → vues + souvent.
local lastShownOffer = nil
local offerBag       = {}

local function refillBag()
	offerBag = {}
	for _, cand in ipairs(OFFERS) do
		if isShowable(cand) then offerBag[#offerBag + 1] = cand end
	end
end

local function categoryWeight(cat)
	return 1 + (categoryEngagement[cat] or 0)   -- base 1 + intérêt accumulé
end

local function pickRandomShowable()
	-- purge ce qui est devenu non-affichable (ex: pass acheté entre-temps)
	for i = #offerBag, 1, -1 do
		if not isShowable(offerBag[i]) then table.remove(offerBag, i) end
	end
	if #offerBag == 0 then refillBag() end       -- cycle terminé → on recommence
	if #offerBag == 0 then return nil end

	-- tirage pondéré sans remise
	local total = 0
	for _, cand in ipairs(offerBag) do
		total += categoryWeight(offerCategory(cand))
	end
	local r, acc, chosenIdx = math.random() * total, 0, #offerBag
	for i, cand in ipairs(offerBag) do
		acc += categoryWeight(offerCategory(cand))
		if r <= acc then chosenIdx = i; break end
	end

	local pick = table.remove(offerBag, chosenIdx)   -- retiré → plus re-montré ce cycle
	-- garde-fou : pas deux fois de suite la même au passage de cycle
	if pick == lastShownOffer and #offerBag > 0 then
		local alt = table.remove(offerBag, math.random(1, #offerBag))
		offerBag[#offerBag + 1] = pick
		pick = alt
	end
	return pick
end

local offerIndex = 1
local function pickNextOffer(preferCategory, strict)
	local n = #OFFERS
	if n == 0 then return nil end

	-- 🎯 Priorité : prochaine offre showable de la catégorie demandée
	if preferCategory then
		for i = 0, n - 1 do
			local idx  = ((offerIndex - 1 + i) % n) + 1
			local cand = OFFERS[idx]
			if offerCategory(cand) == preferCategory and isShowable(cand) then
				offerIndex = (idx % n) + 1
				return cand
			end
		end
		if strict then return nil end   -- 🔒 verrou : aucun fallback hors catégorie
	end

	-- Rotation normale → ALÉATOIRE
	return pickRandomShowable()
end

-- Attente interruptible (pour couper net après un achat)
local function interruptibleWait(duration)
	local elapsed = 0
	while elapsed < duration do
		if interruptDisplay then return end
		task.wait(0.1)
		elapsed += 0.1
	end
end

-- Déclenché par un achat confirmé : enchaîner la même catégorie
local function triggerSameCategory(cat)
	if not cat then return end
	forcedCategory = cat
	if showing then interruptDisplay = true end
end

-- ========================================
-- ░░ VERROU DE CATÉGORIE (API _G) ░░
-- Le UGC shop l'appelle : tant que sa frame est ouverte,
-- le carrousel ne montre QUE cette catégorie, à une rate custom.
-- ========================================
_G.OffersLockCategory = function(category, displayTime)
	lockedCategory    = category
	lockedDisplayTime = displayTime          -- nil → DISPLAY_TIME par défaut
	forcedCategory    = nil
	interruptDisplay  = true                 -- coupe l'offre courante → switch immédiat
end

_G.OffersUnlockCategory = function()
	lockedCategory    = nil
	lockedDisplayTime = nil
	interruptDisplay  = true                 -- coupe l'offre courante → retour rotation normale
end

-- 🔔 Réglages en direct : ADMIN PANEL ▸ 🔔 POPUPS ▸ « 🎠 Carrousel d'offres »
--    (activé, 1re offre après X s, durée d'une offre). FIRST_DELAY / DISPLAY_TIME
--    ci-dessus ne servent plus que de secours.
local Gate = require(ReplicatedStorage:WaitForChild("PopupGate"))
local CAROUSEL_ID = "offers_carousel"

task.spawn(function()
	task.wait(tonumber(Gate.Get(CAROUSEL_ID, "FirstDelaySec")) or FIRST_DELAY)
	while true do
		local lockCat = lockedCategory          -- snapshot (peut changer à tout moment)
		local offer, displayTime
		local normalTime = tonumber(Gate.Get(CAROUSEL_ID, "DisplaySec")) or DISPLAY_TIME

		-- ⛔ désactivé par l'admin, ou mode « seulement si inactif » pas encore atteint
		--    (le shop UGC ouvert = le joueur regarde : seul l'interrupteur compte)
		if not Gate.Enabled(CAROUSEL_ID) or (not lockCat and not Gate.Allowed(CAROUSEL_ID)) then
			interruptDisplay = false
			interruptibleWait(2)
			continue
		end

		if lockCat then
			-- 🔒 Verrou actif : UNIQUEMENT cette catégorie, rate custom, zéro fallback
			offer       = pickNextOffer(lockCat, true)
			displayTime = lockedDisplayTime or normalTime
		else
			-- Rotation normale (+ enchaînement post-achat éventuel)
			offer          = pickNextOffer(forcedCategory, false)
			forcedCategory = nil
			displayTime    = normalTime
		end

		if offer then
			currentOffer     = offer
			lastShownOffer   = offer
			interruptDisplay = false
			applyOffer(offer)
			popIn()
			Gate.Shown(CAROUSEL_ID)   -- 📊 stats (1 fois / 20 s max)
			showing = true
			interruptibleWait(displayTime)   -- coupé net si achat OU (dé)verrouillage
			popOut()
			currentOffer     = nil
			interruptDisplay = false
			task.wait(GAP_TIME)
		else
			-- Rien à montrer : on réessaie vite, interruptible (réagit au déverrou)
			interruptDisplay = false
			interruptibleWait(1)
		end
	end
end)

-- ========================================
-- ░░ ACHAT CONFIRMÉ → ENCHAÎNER LE MÊME TYPE ░░
-- ========================================
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
	if userId ~= player.UserId or not wasPurchased then return end
	addEngagementCat(categoryByProduct[productId], PURCHASE_WEIGHT)   -- 🎯 achat = très intéressé
	triggerSameCategory(categoryByProduct[productId])
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, wasPurchased)
	if plr ~= player or not wasPurchased then return end
	ownsCache[passId] = true
	addEngagementCat(categoryByPass[passId], PURCHASE_WEIGHT)         -- 🎯 achat = très intéressé
	triggerSameCategory(categoryByPass[passId])
end)
-- ========================================
-- ░░ NOTIFICATION RÉCOMPENSE (bounce, centre) ░░
-- ========================================
local function showRewardNotification(title, subtitle, extraLine)
	local g = Instance.new("ScreenGui")
	g.Name = "ReferralRewardGui"; g.ResetOnSpawn = false
	g.DisplayOrder = 1000; g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = playerGui

	local mobile = isMobile()
	local W = mobile and 340 or 430
	local H = extraLine and 140 or 120

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.38, 0)
	frame.Size = UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = g
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 16); corner.Parent = frame
	local border = Instance.new("UIStroke")
	border.Color = Color3.fromRGB(85, 255, 127); border.Thickness = 2.5; border.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -24, 0, 42)
	titleLabel.Position = UDim2.new(0, 12, 0, 14)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
	titleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	titleLabel.TextStrokeTransparency = 0.4
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = mobile and 20 or 24
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextWrapped = true
	titleLabel.Parent = frame

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -24, 0, 30)
	subLabel.Position = UDim2.new(0, 12, 0, 58)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = subtitle
	subLabel.TextColor3 = Color3.fromRGB(200, 255, 215)
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextSize = mobile and 13 or 15
	subLabel.TextXAlignment = Enum.TextXAlignment.Center
	subLabel.TextWrapped = true
	subLabel.Parent = frame

	if extraLine then
		local extraLabel = Instance.new("TextLabel")
		extraLabel.Size = UDim2.new(1, -24, 0, 26)
		extraLabel.Position = UDim2.new(0, 12, 0, 100)
		extraLabel.BackgroundTransparency = 1
		extraLabel.Text = extraLine
		extraLabel.TextColor3 = Color3.fromRGB(160, 255, 185)
		extraLabel.Font = Enum.Font.GothamBold
		extraLabel.TextSize = mobile and 12 or 13
		extraLabel.TextXAlignment = Enum.TextXAlignment.Center
		extraLabel.TextWrapped = true
		extraLabel.Parent = frame
	end

	TweenService:Create(frame,
		TweenInfo.new(0.42, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{Size = UDim2.new(0, W, 0, H)}):Play()

	if buySound then pcall(function() buySound:Play() end) end

	task.delay(4.2, function()
		if not frame or not frame.Parent then return end
		local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(frame, fadeInfo, {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, W, 0, H - 30)
		}):Play()
		TweenService:Create(titleLabel, fadeInfo, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		TweenService:Create(subLabel,   fadeInfo, {TextTransparency = 1}):Play()
		TweenService:Create(border,     fadeInfo, {Transparency = 1}):Play()
		task.delay(0.35, function()
			if g and g.Parent then g:Destroy() end
		end)
	end)
end

-- ========================================
-- ░░ NOTIFICATIONS LÉGÈRES (coin haut, stack) ░░
-- ========================================
local notifGui     = nil
local activeNotifs = {}
local NOTIF_H      = 80
local NOTIF_GAP    = 8
local DISP_TIME    = 5.2
local ANIM_IN      = 0.38
local ANIM_OUT     = 0.25
local NOTIF_ICON   = "rbxassetid://91680937854802"

local function getNotifGui()
	if notifGui and notifGui.Parent then return notifGui end
	local g = Instance.new("ScreenGui")
	g.Name = "ReferralNotifGui"; g.ResetOnSpawn = false
	g.DisplayOrder = 999; g.IgnoreGuiInset = false; g.Parent = playerGui
	notifGui = g; return g
end

local function buildNotif(gui, title, subtitle, strokeColor)
	local mobile = isMobile()
	strokeColor  = strokeColor or Color3.fromRGB(255, 215, 0)

	local w = mobile and UDim2.new(0, 340, 0, NOTIF_H) or UDim2.new(0, 370, 0, NOTIF_H)
	local frame = Instance.new("Frame")
	frame.Name = "NotifFrame"; frame.Size = w
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, -NOTIF_H - 20)
	frame.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel = 0; frame.Parent = gui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor; stroke.Thickness = 1.8; stroke.Transparency = 0.25; stroke.Parent = frame

	local ICON_SIZE = 48
	local iconImg = Instance.new("ImageLabel")
	iconImg.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
	iconImg.Position = UDim2.new(0, 14, 0.5, -ICON_SIZE / 2)
	iconImg.BackgroundColor3 = Color3.fromRGB(89, 90, 105)
	iconImg.Image = NOTIF_ICON
	iconImg.ScaleType = Enum.ScaleType.Fit
	iconImg.Parent = frame
	local iconCorner = Instance.new("UICorner"); iconCorner.CornerRadius = UDim.new(0, 11); iconCorner.Parent = iconImg

	local TX = 14 + ICON_SIZE + 12
	local titleL = Instance.new("TextLabel")
	titleL.Size = UDim2.new(1, -(TX + 12), 0, 24)
	titleL.Position = UDim2.new(0, TX, 0, 10)
	titleL.BackgroundTransparency = 1
	titleL.Text = title
	titleL.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleL.Font = Enum.Font.GothamBold
	titleL.TextSize = mobile and 13 or 15
	titleL.TextXAlignment = Enum.TextXAlignment.Left
	titleL.TextTruncate = Enum.TextTruncate.AtEnd
	titleL.Parent = frame

	local subL = Instance.new("TextLabel")
	subL.Size = UDim2.new(1, -(TX + 12), 0, 28)
	subL.Position = UDim2.new(0, TX, 0, 34)
	subL.BackgroundTransparency = 1
	subL.Text = subtitle
	subL.TextColor3 = Color3.fromRGB(210, 210, 225)
	subL.Font = Enum.Font.Gotham
	subL.TextSize = mobile and 11 or 13
	subL.TextXAlignment = Enum.TextXAlignment.Left
	subL.TextWrapped = true
	subL.Parent = frame

	local pbBg = Instance.new("Frame")
	pbBg.Size = UDim2.new(1, -24, 0, 2)
	pbBg.Position = UDim2.new(0, 12, 1, -6)
	pbBg.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
	pbBg.BackgroundTransparency = 0.3
	pbBg.BorderSizePixel = 0; pbBg.Parent = frame
	local pbc = Instance.new("UICorner"); pbc.CornerRadius = UDim.new(1, 0); pbc.Parent = pbBg
	local pb = Instance.new("Frame")
	pb.Size = UDim2.new(1, 0, 1, 0)
	pb.BackgroundColor3 = strokeColor; pb.BorderSizePixel = 0; pb.Parent = pbBg
	local pbb = Instance.new("UICorner"); pbb.CornerRadius = UDim.new(1, 0); pbb.Parent = pb

	return frame, pb
end

local function showNotif(title, subtitle, strokeColor)
	local gui = getNotifGui()
	local stackY = getTopInset() + 12
	for _, e in ipairs(activeNotifs) do
		if e.frame and e.frame.Parent then stackY = stackY + NOTIF_H + NOTIF_GAP end
	end

	local frame, pb = buildNotif(gui, title, subtitle, strokeColor)
	local targetPos = UDim2.new(0.5, 0, 0, stackY)
	local entry = {frame = frame}
	table.insert(activeNotifs, entry)

	TweenService:Create(frame, TweenInfo.new(ANIM_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = targetPos}):Play()
	task.delay(ANIM_IN, function()
		TweenService:Create(pb, TweenInfo.new(DISP_TIME, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 1, 0)}):Play()
	end)

	task.delay(ANIM_IN + DISP_TIME, function()
		if not frame or not frame.Parent then return end
		local out = TweenService:Create(frame, TweenInfo.new(ANIM_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Position = UDim2.new(0.5, 0, 0, -NOTIF_H - 30), BackgroundTransparency = 1})
		out:Play()
		out.Completed:Connect(function()
			frame:Destroy()
			for i, e in ipairs(activeNotifs) do
				if e == entry then table.remove(activeNotifs, i); break end
			end
			local y = getTopInset() + 12
			for _, e in ipairs(activeNotifs) do
				if e.frame and e.frame.Parent then
					TweenService:Create(e.frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Position = UDim2.new(0.5, 0, 0, y)}):Play()
					y = y + NOTIF_H + NOTIF_GAP
				end
			end
		end)
	end)
end

-- ========================================
-- ░░ INVITATION (depuis le clic carrousel) ░░
-- ========================================
function doInvite()
	local waited = 0
	while not canInviteChecked and waited < 50 do task.wait(0.1); waited += 1 end

	if not canInviteCache then
		showNotif("Invites unavailable", "Game invites aren't supported on your platform.", Color3.fromRGB(220, 75, 75))
		return
	end

	local opts = Instance.new("ExperienceInviteOptions")
	opts.PromptMessage = INVITE_MESSAGE

	local ok = pcall(SocialService.PromptGameInvite, SocialService, player, opts)
	if not ok then
		showNotif("Couldn't send invite", "Please try again in a moment.", Color3.fromRGB(220, 75, 75))
	end

	-- Track serveur (comme l'ancien referral)
	pcall(function() promptInviteEvent:FireServer() end)
end

-- ========================================
-- ░░ ÉCOUTE DES RÉCOMPENSES SERVEUR ░░
-- ========================================
if referralRewardEvent then
	referralRewardEvent.OnClientEvent:Connect(function(amount, source)
		local pts = string.format("+%s pts", formatPoints(amount))

		if source == "Referral_Invitee" then
			showRewardNotification(
				pts .. "  —  You joined your friend! 🎁",
				"Welcome bonus added to your balance.",
				"🎉 Invite more friends to earn even more!")

		elseif source == "Referral_Inviter" then
			showRewardNotification(
				pts .. "  —  Your friend joined! 🎁",
				"Your invite was accepted.",
				"🎉 Invite more friends to earn even more!")

		elseif source == "Referral_Pending" then
			showRewardNotification(
				pts .. "  —  Stored invite bonus! 🎁",
				"Pending reward added to your balance.",
				"🎉 Invite more friends to earn even more!")

		elseif source == "Referral_NotNew" then
			showNotif("Friend Already Played",
				"Invite rewards only count for friends who are NEW to the game.",
				Color3.fromRGB(180, 180, 180))

		elseif source == "Referral_CapReached" then
			showNotif("Invite Limit Reached",
				"You've reached the maximum number of invite rewards.",
				Color3.fromRGB(180, 180, 180))

		else
			showRewardNotification(
				pts .. "  —  Bonus received! 🎁",
				"Points added to your balance.",
				"🎉 Invite more friends to earn even more!")
		end
	end)
end

if referralReceivedEvent then
	referralReceivedEvent.OnClientEvent:Connect(function(_)
		task.delay(2, function()
			showNotif("Invited by a friend 👋", "Your bonus points are on their way...", Color3.fromRGB(115, 115, 148))
		end)
	end)
end

print("✅ OffersDisplay + Referral chargé —", #OFFERS, "offre(s)")