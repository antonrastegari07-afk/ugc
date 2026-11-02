--════════════════════════════════════════════════════════════════════════════
-- 🚫 PANNEAU « ACCÈS UGC RESTREINT » — CLIENT
--
--  📍 OÙ ? StarterPlayer → StarterPlayerScripts (LocalScript)
--     Nom conseillé : UGCRestrictNotify
--
--  Il s'affiche, toujours à la demande du SERVEUR :
--    • UNE fois, au moment où la privation tombe (ou à la connexion suivante
--      s'il n'était pas en jeu à ce moment-là) ;
--    • puis seulement quand il clique sur Buy pour une UGC qu'il pourrait
--      normalement se payer.
--════════════════════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local notifyRemote = ReplicatedStorage:WaitForChild("UGCRestrictNotify", 30)
if not notifyRemote then
	warn("[UGCRestrict] UGCRestrictNotify introuvable — ajoute "
		.. "AntiCheat_UGCRestrict.server.lua dans ServerScriptService")
	return
end

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local FONT      = Enum.Font.FredokaOne

local RED       = Color3.fromRGB(235, 60, 65)
local RED_DEEP  = Color3.fromRGB(140, 25, 30)
local GREEN     = Color3.fromRGB(55, 195, 100)
local GREEN_D   = Color3.fromRGB(30, 130, 65)

local currentGui = nil

local function panelSize()
	local cam = workspace.CurrentCamera
	local vp  = (cam and cam.ViewportSize.Y > 1) and cam.ViewportSize or Vector2.new(1280, 720)
	local w   = math.min(vp.X * 0.90, 470)
	local h   = math.min(vp.Y * 0.84, 460)
	return w, h
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function show(payload)
	payload = (type(payload) == "table") and payload or {}

	if currentGui and currentGui.Parent then return end   -- déjà affiché

	local gui = Instance.new("ScreenGui")
	gui.Name           = "UGCRestrictedGui"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 650
	gui.Parent         = playerGui
	currentGui = gui

	--  Voile qui avale les clics : on ne ferme que par le bouton, pour être
	--  sûr que le message a été lu au moins une fois.
	local veil = Instance.new("TextButton")
	veil.Size                   = UDim2.fromScale(1, 1)
	veil.BackgroundColor3       = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 1
	veil.AutoButtonColor        = false
	veil.Text                   = ""
	veil.BorderSizePixel        = 0
	veil.ZIndex                 = 1
	veil.Parent                 = gui
	TweenService:Create(veil, TweenInfo.new(0.25), { BackgroundTransparency = 0.5 }):Play()

	local w, h = panelSize()

	local card = Instance.new("Frame")
	card.AnchorPoint      = Vector2.new(0.5, 0.5)
	card.Position         = UDim2.new(0.5, 0, 0.5, 0)
	card.Size             = UDim2.new(0, 0, 0, 0)
	card.BackgroundColor3 = Color3.fromRGB(20, 20, 27)
	card.BorderSizePixel  = 0
	card.ZIndex           = 2
	card.Parent           = gui
	corner(card, 16)

	local cs = Instance.new("UIStroke")
	cs.Color = RED ; cs.Thickness = 2.5 ; cs.Parent = card

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 16) ; pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft   = UDim.new(0, 18) ; pad.PaddingRight  = UDim.new(0, 18)
	pad.Parent = card

	local titleH = IS_MOBILE and 34 or 42
	local btnH   = IS_MOBILE and 44 or 52

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, 0, 0, titleH)
	title.Position               = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Font                   = FONT
	--  💬 Titre configurable depuis le panel admin (section MESSAGES).
	--     Le serveur envoie déjà le texte FINI : rien n'est interprété ici,
	--     donc aucun gabarit ne peut être détourné côté client.
	title.Text                   = (type(payload.title) == "string" and payload.title ~= "")
		and payload.title
		or "🚫 UGC ACCESS RESTRICTED"
	title.TextColor3             = RED
	title.TextScaled             = true
	title.ZIndex                 = 3
	title.Parent                 = card

	local ts = Instance.new("UIStroke")
	ts.Color = RED_DEEP ; ts.Thickness = 1.5 ; ts.Parent = title

	--  Le corps du message défile : sur un petit écran il reste entièrement
	--  lisible au lieu d'être rogné, ce qui est important pour un texte
	--  qui explique une sanction.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position              = UDim2.new(0, 0, 0, titleH + 10)
	scroll.Size                  = UDim2.new(1, 0, 1, -(titleH + btnH + 30))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel       = 0
	scroll.ScrollBarThickness    = 3
	scroll.ScrollBarImageColor3  = Color3.fromRGB(90, 90, 105)
	scroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
	scroll.ScrollingDirection    = Enum.ScrollingDirection.Y
	scroll.ZIndex                = 3
	scroll.Parent                = card

	local body = Instance.new("TextLabel")
	body.Size                   = UDim2.new(1, -6, 0, 0)
	body.AutomaticSize          = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.Font                   = Enum.Font.Gotham
	body.TextColor3             = Color3.fromRGB(228, 228, 235)
	body.TextSize               = IS_MOBILE and 14 or 15
	body.TextWrapped            = true
	body.TextXAlignment         = Enum.TextXAlignment.Left
	body.TextYAlignment         = Enum.TextYAlignment.Top
	body.RichText               = true
	body.ZIndex                 = 4
	body.Parent                 = scroll

	local msg = payload.message
		or ("Our anti-cheat system has flagged your account for abnormal movement "
			.. "(fly, teleport or speed).\n\n"
			.. "As a result, UGC redemptions are disabled on your account. "
			.. "Your points are untouched and you can keep playing normally.\n\n"
			.. "If you believe this is a mistake, please contact our support team "
			.. "and include evidence — a short video of your gameplay is best. "
			.. "We review every appeal by hand.")

	--  On met en vert la ligne qui rassure sur les points : c'est la première
	--  chose que le joueur cherche, et ça évite une vague de tickets paniqués.
	msg = msg:gsub("Your points are untouched",
		"<b><font color=\"#5ADC8C\">Your points are untouched</font></b>")

	local ref = payload.reference or player.UserId
	local whenTxt = ""
	if type(payload.at) == "number" and payload.at > 0 then
		whenTxt = "\n<font color=\"#8A8A98\">Flagged on "
			.. os.date("!%d/%m/%Y", payload.at) .. " (UTC)</font>"
	end

	body.Text = msg
		.. "\n\n<font color=\"#8A8A98\">Reference ID: <b>" .. tostring(ref) .. "</b></font>"
		.. whenTxt

	local okBtn = Instance.new("TextButton")
	okBtn.AnchorPoint      = Vector2.new(0.5, 1)
	okBtn.Position         = UDim2.new(0.5, 0, 1, 0)
	okBtn.Size             = UDim2.new(1, 0, 0, btnH)
	okBtn.BackgroundColor3 = GREEN
	okBtn.AutoButtonColor  = false
	okBtn.BorderSizePixel  = 0
	okBtn.Font             = FONT
	okBtn.Text             = "I UNDERSTAND"
	okBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
	okBtn.TextSize         = IS_MOBILE and 17 or 20
	okBtn.ZIndex           = 3
	okBtn.Parent           = card
	corner(okBtn, 11)

	local os_ = Instance.new("UIStroke")
	os_.Color = GREEN_D ; os_.Thickness = 2 ; os_.Parent = okBtn

	local scale = Instance.new("UIScale") ; scale.Parent = okBtn
	okBtn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.03 }):Play()
	end)
	okBtn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)

	local function close()
		if not gui.Parent then return end
		currentGui = nil
		TweenService:Create(card,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(0, 0, 0, 0) }):Play()
		TweenService:Create(veil, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		task.delay(0.25, function() if gui and gui.Parent then gui:Destroy() end end)
	end
	okBtn.MouseButton1Click:Connect(close)

	--  Suit la rotation / le redimensionnement d'écran.
	local cam = workspace.CurrentCamera
	local vpConn
	if cam then
		vpConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if not card.Parent then return end
			local nw, nh = panelSize()
			card.Size = UDim2.new(0, nw, 0, nh)
		end)
	end
	gui.Destroying:Connect(function() if vpConn then vpConn:Disconnect() end end)

	TweenService:Create(card,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, w, 0, h) }):Play()
end

notifyRemote.OnClientEvent:Connect(function(payload)
	local ok, err = pcall(show, payload)
	if not ok then warn("[UGCRestrict] " .. tostring(err)) end
end)

--════════════════════════════════════════════════════════════════════════════
-- 🔗 BRANCHEMENT SUR LE SHOP
--    Quand le serveur refuse un achat parce que le joueur est restreint, il
--    renvoie la raison par ConfirmUGCPurchase. On rouvre le panneau : le
--    joueur comprend immédiatement, et on n'a pas eu à toucher au script du
--    shop (il ignorait juste cette raison, sans planter).
--════════════════════════════════════════════════════════════════════════════
task.spawn(function()
	local confirm = ReplicatedStorage:WaitForChild("ConfirmUGCPurchase", 30)
	if not confirm then return end
	confirm.OnClientEvent:Connect(function(success, reason, ...)
		if success then return end
		--  💬 Le serveur peut joindre son propre titre + corps, réglés dans
		--     le panel (⚙️ Messages → 🛒 Achat refusé / ⏳ Vérification).
		--     `info` est le 3ᵉ argument, optionnel : si ton script de points
		--     ne l'envoie pas encore, on retombe sur les textes ci-dessous.
		--  On ne suppose AUCUNE position : on prend la première table qui
		--  passe dans les arguments supplémentaires. Comme ça, que ton script
		--  de points envoie (assetId, nom, texte) ou juste (texte), ça marche,
		--  et si tu n'as pas encore appliqué le patch, `info` reste vide et on
		--  retombe sur les textes par défaut.
		--  ⚠️ `select("#", ...)` et PAS ipairs : ipairs s'arrête au premier
		--     trou, or un argument nil au milieu (par exemple si ton script
		--     de points n'envoie pas le nom de l'UGC) ferait rater la table
		--     et le joueur retomberait sur le texte par défaut sans qu'on
		--     comprenne pourquoi.
		local info
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "table" then info = v break end
		end
		info = (type(info) == "table") and info or {}

		if reason == "ugc_restricted" then
			show({
				reference = player.UserId,
				title     = info.title,
				message   = info.message,
			})
		elseif reason == "ugc_unverified" then
			--  Registre illisible côté serveur : ce n'est PAS une sanction.
			--  On le dit clairement, sinon un joueur honnête croit être puni.
			show({
				reference = player.UserId,
				title     = info.title or "⏳ PLEASE TRY AGAIN",
				message   = info.message
					or ("We could not verify your account status right now "
						.. "(temporary server issue).\n\n"
						.. "Your points are untouched. Please try again in a few seconds — "
						.. "this usually resolves on its own.\n\n"
						.. "If it keeps happening, let our support team know."),
			})
		end
	end)
end)

--  🤫 V4 : on ne grise PLUS le bouton Buy. Ça révélait la sanction au joueur
--     avant même qu'il essaie d'acheter. Le refus réel vient du serveur, et
--     le panneau s'affiche au bon moment (quand il pourrait se payer l'UGC).
