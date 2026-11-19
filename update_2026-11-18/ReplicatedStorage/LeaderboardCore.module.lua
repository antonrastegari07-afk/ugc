--!nonstrict
--[[
================================================================================
	LeaderboardCore  —  ModuleScript
	📍 Emplacement : ReplicatedStorage > LeaderboardCore

	Coeur partagé par TOUS les leaderboards (Kills, Rebirths, Streaks, Points,
	Donations). Les LocalScripts ne contiennent plus qu'une table de config.

	CE QUE LE MODULE APPORTE
	------------------------
	A1  Fond dégradé doré sur les entries VIP (au lieu du noir plat)
	A3  Anneau doré sur l'avatar VIP
	A4  Gestion VIP nettoyée : UN seul label de nom, plus de container inutile
	A5  Badge + icône VIP ancrés à droite (AnchorPoint), plus d'offsets figés
	B1  Shimmer lent et large : un reflet traverse toute l'entry VIP et son
	    badge en même temps (plaque dorée conservée sous le reflet)
	B4  Apparition en cascade des entries (slide + fade décalés)
	B7  Chiffre de la place progressivement plus gros dans le top 3
	B8  Halo bleu clair pulsant sur l'entry du joueur local
	B9  Sparkles discrets sur le badge VIP (top 10 uniquement, plafonné)
	C   - un seul ModuleScript au lieu de 4 scripts dupliqués
	    - rbxthumb:// partout (zéro yield, zéro pcall par avatar)
	    - refresh NON destructif : les frames sont réutilisées, plus de flash
	    - UNE seule boucle Heartbeat anime tout le jeu (pas N task.spawn)
	    - UN seul InvokeServer par cycle, partagé par tous les boards
	    - les boards détruits (swap de map) sont retirés proprement
================================================================================
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Core = {}

--==============================================================================
-- 🏆 STYLE (ReplicatedStorage ▸ LeaderboardStyle)
--   "modern"  : look Paramètres / CombatHUD + ALL / FRIENDS / FIND ME + ta ligne
--   "classic" : EXACTEMENT l'apparence d'avant (le code d'origine est inchangé)
--==============================================================================
local STYLE = { Style = "classic", Tabs = true, YourRow = false, UpdateBar = false, FriendsCacheSeconds = 600 }
do
	local m = ReplicatedStorage:FindFirstChild("LeaderboardStyle")
	if m and m:IsA("ModuleScript") then
		local ok, t = pcall(require, m)
		if ok and type(t) == "table" then
			for k, v in pairs(t) do STYLE[k] = v end
		end
	end
end
local MODERN = STYLE.Style == "modern"
local TABS = STYLE.Tabs ~= false   -- ALL / FRIENDS / FIND ME (marche avec les deux looks)
Core.Style = STYLE

-- même famille de police que les Paramètres et le CombatHUD
local MODERN_FONT = "rbxasset://fonts/families/BuilderSans.json"
local MF = {
	Heavy = Font.new(MODERN_FONT, Enum.FontWeight.ExtraBold),
	Bold  = Font.new(MODERN_FONT, Enum.FontWeight.Bold),
	Med   = Font.new(MODERN_FONT, Enum.FontWeight.Medium),
}
-- fonds neutres « verre sombre » (la couleur d'accent de chaque board est gardée)
local MODERN_PALETTE = {
	bg = Color3.fromRGB(10, 12, 18), bgA = Color3.fromRGB(16, 19, 28), bgB = Color3.fromRGB(8, 9, 14),
	panel = Color3.fromRGB(17, 20, 28), footer = Color3.fromRGB(17, 20, 28),
	entry = Color3.fromRGB(27, 30, 40), top3A = Color3.fromRGB(42, 46, 62), top3B = Color3.fromRGB(26, 29, 39),
	entryStroke = Color3.fromRGB(52, 56, 70), stroke = Color3.fromRGB(58, 62, 78),
	muted = Color3.fromRGB(165, 175, 192), white = Color3.fromRGB(240, 242, 247),
}
local ME_COLOR = Color3.fromRGB(255, 214, 92)   -- « toi » (même jaune que le CombatHUD)
local BTN = {   -- dessus, dessous, socle (même recette que les boutons des Paramètres)
	blue = { Color3.fromRGB(55, 145, 240), Color3.fromRGB(20, 85, 180), Color3.fromRGB(12, 48, 110) },
	grey = { Color3.fromRGB(88, 94, 112), Color3.fromRGB(50, 54, 68), Color3.fromRGB(28, 30, 40) },
	teal = { Color3.fromRGB(40, 190, 180), Color3.fromRGB(15, 125, 120), Color3.fromRGB(8, 70, 68) },
}

--==============================================================================
-- CONSTANTES DE STYLE VIP / HALOS
--==============================================================================
local GOLD        = Color3.fromRGB(255, 210, 60)
local GOLD_SOFT   = Color3.fromRGB(255, 236, 160)
local GOLD_DEEP   = Color3.fromRGB(190, 130, 15)
local GOLD_NAME   = Color3.fromRGB(255, 236, 175)
local SELF_BLUE   = Color3.fromRGB(120, 205, 255)

local VIP_ICON    = "rbxassetid://93460778559039"
-- L'image n'est PAS carrée : largeur / hauteur réelles. Sans ça elle est écrasée.
local VIP_ICON_RATIO = 1.20

-- B8 — halo qui entoure TOUTE l'entry : réservé au joueur local
local SELF_GLOW = { base = {0.84, 0.91, 0.955}, amp = {0.10, 0.07, 0.04}, speed = 1.8 }

-- Taille du chiffre de la place : le #1 est le plus gros, puis ça décroît
-- (multiplicateur appliqué au MaxTextSize de base)
local RANK_SIZE = { 1.62, 1.36, 1.16 }

local SHIMMER_PERIOD = 9.0   -- s entre deux reflets
local SHIMMER_SWEEP  = 2.6   -- s de balayage (lent et large)
-- Le badge VIP utilise la MÊME période, décalée d'une demi-période :
-- les deux reflets ne peuvent donc jamais passer en même temps.
local BADGE_SWEEP    = 1.1   -- balayage court et net sur le badge
local BADGE_OFFSET   = SHIMMER_PERIOD * 0.5
local SPARKLE_MAX_RANK = 10  -- B9 seulement dans le top 10 (perf)

--==============================================================================
-- 🖱️ ENTRIES INTERACTIVES
--   Survol  → l'entry grossit (les autres se poussent) + « View Profile »
--   Clic    → ouvre la fiche profil du joueur (PlayerProfileHover)
--   ↩️ false = exactement comme avant.
--==============================================================================
local INTERACTIVE  = true
local PROFILE_ICON = "rbxassetid://78515108577271"
local HOVER_GROW   = 1.22     -- hauteur de l'entry survolée (× la normale)
local HOVER_GROW_ENABLED = false   -- false = l'entry ne grossit plus au survol
-- (« View Profile » et le clic restent actifs)
local HOVER_INFO   = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Stats vues sur TOUS les boards, fusionnées par joueur : la fiche d'un joueur
-- ouverte depuis le board Kills montre aussi ses points, rebirths, streak…
local knownStats = {}
local hoveredEntry = nil

local DEFAULT_RANK_COLORS = {
	Color3.fromRGB(255, 215, 0),
	Color3.fromRGB(200, 200, 210),
	Color3.fromRGB(180, 110, 50),
}

--==============================================================================
-- ANIMATEUR CENTRAL
--   Une seule connexion Heartbeat pour tout le jeu. Chaque animation est une
--   fonction pure du temps → pas de tween à annuler, pas de thread qui fuit.
--   Une entrée dont l'objet n'a plus de Parent est retirée automatiquement.
--==============================================================================
local anims   = {}
local animConn = nil

local function registerAnim(obj, state, fn)
	table.insert(anims, { obj = obj, state = state, fn = fn })
	if not animConn then
		animConn = RunService.Heartbeat:Connect(function()
			local t = os.clock()
			for i = #anims, 1, -1 do
				local a = anims[i]
				if not a.obj or not a.obj.Parent then
					table.remove(anims, i)
				else
					a.fn(t, a.state, a.obj)
				end
			end
		end)
	end
end

--==============================================================================
-- LISTE VIP (partagée par tous les leaderboards)
--==============================================================================
local vipList = {}

--==============================================================================
--  ⏱️ ÉPOQUE — qui gagne entre une lecture complète et un delta
--
--     `fetchVip` demande la liste au serveur et attend la réponse. Pendant
--     cette attente, un delta peut arriver et modifier `vipList`. La réponse,
--     elle, décrit l'état d'AVANT : l'écraser avec, c'est ressusciter un VIP
--     qui vient d'être retiré.
--
--     Tant que le serveur renvoyait la liste entière à chaque changement, ça
--     se réparait tout seul quelques secondes plus tard. Avec les deltas, le
--     serveur n'annonce QUE les changements : un joueur écrasé par une
--     réponse périmée ne serait plus jamais mentionné, et l'erreur resterait
--     jusqu'à la fin de la session.
--
--     Ce compteur tranche : si l'époque a bougé pendant la requête, un delta
--     plus récent est passé, et c'est lui qui a raison.
--     (DonationClient rappelle Core.refreshVip toutes les 5 s tant que le
--      panneau des dons est ouvert — la fenêtre de course est permanente.)
--==============================================================================
local vipEpoch = 0

local function fetchVip()
	local f = ReplicatedStorage:FindFirstChild("GetVIPList")
	if not f then return false end
	local mark = vipEpoch
	local ok, res = pcall(function() return f:InvokeServer() end)
	if ok and typeof(res) == "table" then
		--  Un delta est passé pendant la requête → sa version est plus jeune.
		if vipEpoch ~= mark then return true end
		vipList = res
		return true
	end
	return false
end

--  🔁 La première lecture n'est plus « une chance et tant pis ». Elle est la
--     SEULE source de l'état initial : si elle échoue (remote pas encore
--     répliqué, hoquet réseau), plus aucun badge ne s'affiche de toute la
--     session, puisque les deltas ne décrivent que les changements.
task.spawn(function()
	ReplicatedStorage:WaitForChild("GetVIPList", 20)
	for attempt = 1, 5 do
		if fetchVip() then return end
		task.wait(3 * attempt)
	end
	warn("⚠️ [Leaderboard] Liste VIP introuvable après 5 tentatives — "
		.. "les couronnes n'apparaîtront qu'aux prochains changements.")
end)

function Core.refreshVip() Core.registerAnim = registerAnim return fetchVip() end
function Core.isVip(userId) return vipList[tostring(userId)] ~= nil end


-- 🖱️ Ouvre la fiche profil (PlayerProfileHover expose _G.OpenPlayerProfile)
function Core.openProfile(userId, data)
	local info = {}
	for k, v in pairs(knownStats[userId] or {}) do info[k] = v end
	if type(data) == "table" then
		for k, v in pairs(data) do
			if info[k] == nil then info[k] = v end
		end
	end
	info.vip = Core.isVip(userId)
	if type(_G.OpenPlayerProfile) == "function" then
		_G.OpenPlayerProfile(userId, info)
	else
		warn("[Leaderboard] _G.OpenPlayerProfile introuvable → mets à jour PlayerProfileHover")
	end
end

-- Toutes les ListView vivantes, pour les repeindre quand la liste VIP change.
-- (le registre se nettoie tout seul : une vue dont le scroll est détruit sort)
local liveViews = {}

-- 👑 Le serveur diffuse la liste dès qu'un admin ajoute ou retire un VIP.
-- Le badge apparaît/disparaît à la seconde, sans attendre le cycle de refresh.
--==============================================================================
--  📉 PROTOCOLE DELTA  (doit rester en phase avec VIPManager.server.lua)
--
--     Le serveur envoyait la liste VIP COMPLÈTE du jeu à chaque changement.
--     Avec un millier de VIP enregistrés, ça faisait ~17 Ko par envoi et par
--     joueur — et les filets de synchronisation multi-serveurs ont multiplié
--     la fréquence de ces envois. C'était la cause du passage de 5 à 20 KB/s.
--
--     Deux formes possibles maintenant :
--        { d = { ["123"] = true, ["456"] = false } }  → à FUSIONNER
--        { full = { ["123"] = true, … } }             → remplace tout
--
--     `false` dans un delta veut dire « retiré » : on met la clé à nil.
--
--     ⚠️ L'ancienne forme (une table nue de userId → true) est encore acceptée
--        et traitée comme un `full`. Ça évite un écran sans badges si le
--        serveur et le client sont mis à jour à quelques minutes d'écart.
--==============================================================================
task.spawn(function()
	local ev = ReplicatedStorage:WaitForChild("VIPListUpdate", 25)
	if not ev then return end

	--  🔁 Un repaint ne coûte pas rien : il refait chaque ligne de chaque vue
	--     ouverte. Un lot de changements arrivant coup sur coup ne doit
	--     provoquer qu'UN repaint, à la fin.
	local repaintQueued = false
	local function repaint()
		if repaintQueued then return end
		repaintQueued = true
		task.defer(function()
			repaintQueued = false
			for i = #liveViews, 1, -1 do
				local v = liveViews[i]
				if not (v.scroll and v.scroll.Parent) then
					table.remove(liveViews, i)
				elseif v.lastList then
					v:render(v.lastList)
				end
			end
		end)
	end

	ev.OnClientEvent:Connect(function(msg)
		if typeof(msg) ~= "table" then return end

		if typeof(msg.d) == "table" then
			local touched = false
			for key, isVip in pairs(msg.d) do
				local want = (isVip == true) and true or nil
				if vipList[key] ~= want then
					vipList[key] = want
					touched = true
				end
			end
			--  L'époque avance même si rien n'a changé pour NOUS : ce qui
			--  compte, c'est qu'un message plus récent que toute requête en
			--  vol soit arrivé.
			vipEpoch = vipEpoch + 1
			--  Aucun changement réel → aucun repaint. Un delta redondant
			--  (deux serveurs annoncent la même chose) ne coûte rien.
			if touched then repaint() end
			return
		end

		local full = (typeof(msg.full) == "table") and msg.full or msg
		vipList  = full
		vipEpoch = vipEpoch + 1
		repaint()
	end)
end)

--==============================================================================
-- HELPERS
--==============================================================================
local function rankColor(cfg, rank)
	local p = cfg.palette
	if rank <= 3 then
		return (p.rank and p.rank[rank]) or DEFAULT_RANK_COLORS[rank]
	elseif rank <= 10 then return p.purple or Color3.fromRGB(180, 100, 255)
	elseif rank <= 25 then return p.blue   or Color3.fromRGB(80, 160, 255)
	elseif rank <= 50 then return p.green  or Color3.fromRGB(80, 220, 120)
	end
	return p.muted or Color3.fromRGB(140, 140, 150)
end

-- ⚠️ Un UIGradient MULTIPLIE la BackgroundColor3. Avec un fond noir il n'a
-- aucun effet (c'est pourquoi les dégradés top-3 de l'ancien code étaient
-- invisibles). On met donc le fond en blanc et c'est le dégradé qui donne
-- la vraie couleur.
local function bgSequence(cfg, rank, isVip)
	local p = cfg.palette
	if isVip then
		-- A1 : noir à gauche → doré sombre à droite
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(12, 9, 3)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(24, 18, 5)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(78, 57, 12)),
		})
	end
	if rank <= 3 and p.top3A and p.top3B then
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, p.top3A),
			ColorSequenceKeypoint.new(1, p.top3B),
		})
	end
	local e = p.entry or Color3.fromRGB(8, 8, 10)
	return ColorSequence.new(e)
end

local function thumbUrl(userId)
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

local function fmtDefault(n) return tostring(n) end

--==============================================================================
-- ANIMATIONS (fonctions du temps)
--==============================================================================

-- B1 — reflet qui balaye le badge VIP
local function shimmerStep(t, s, grad)
	if not s.on then return end
	local sweep = s.sweep or SHIMMER_SWEEP
	local c = (t + s.phase) % SHIMMER_PERIOD
	if c < sweep then
		grad.Offset = Vector2.new(-1 + (c / sweep) * 2, 0)
	else
		grad.Offset = Vector2.new(1, 0)   -- garé hors champ entre deux passages
	end
end

-- B7 / B8 — halo pulsant
local function glowStep(t, s, holder)
	local preset = s.preset
	if not preset then
		if s.lit then
			for _, g in ipairs(s.layers) do g.BackgroundTransparency = 1 end
			s.lit = false
		end
		return
	end
	s.lit = true
	local k = 0.5 + 0.5 * math.sin((t + s.phase) * preset.speed)
	for i, g in ipairs(s.layers) do
		g.BackgroundColor3      = s.color
		g.BackgroundTransparency = preset.base[i] - preset.amp[i] * k
	end
end

-- B9 — sparkles qui montent le long du badge VIP
local function sparkleStep(t, s, holder)
	if not s.on then
		if s.lit then
			for _, p in ipairs(s.parts) do p.BackgroundTransparency = 1 end
			s.lit = false
		end
		return
	end
	s.lit = true
	local n = #s.parts
	for i, p in ipairs(s.parts) do
		local f = ((t * 0.5) + s.phase + (i - 1) / n) % 1
		p.Position               = UDim2.new(s.bx[i], 0, 0.95 - f * 0.8, 0)
		p.BackgroundTransparency = 0.1 + 0.9 * (f ^ 1.5)
	end
end

--==============================================================================
-- CONSTRUCTION D'UNE ENTRY
--   Structure :
--     Entry (holder, transparent, géré par l'UIListLayout)
--       ├─ Glow1..3   (halos, ZIndex 0 → derrière)
--       └─ Body       (tout le visuel, ZIndex 2 → animable en slide)
--   Le holder reste immobile pour le layout, seul le Body bouge (B4).
--==============================================================================
local function buildEntry(cfg, parent, index)
	local H     = cfg.entryHeight
	local avS   = math.floor(H * 0.62)
	local badgeH = math.floor(H * 0.44)
	local badgeW = math.floor(badgeH * 2.1)
	local iconH = math.floor(H * 0.72)
	local iconW = math.floor(iconH * VIP_ICON_RATIO)
	local E     = { cfg = cfg }

	local holder = Instance.new("Frame")
	holder.Name                   = "Entry"
	holder.Size                   = UDim2.new(1, 0, 0, H)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel        = 0
	holder.ClipsDescendants       = false
	holder.LayoutOrder            = index
	holder.ZIndex                 = 1
	holder.Parent                 = parent
	E.holder = holder

	------------------------------------------------------------------
	-- B8 — halo autour de TOUTE l'entry, réservé au joueur local
	--      3 couches concentriques, aucun asset externe
	------------------------------------------------------------------
	local layers = {}
	for i = 1, 3 do
		local pad = i * 5
		local g = Instance.new("Frame")
		g.Name                   = "Glow" .. i
		g.AnchorPoint            = Vector2.new(0.5, 0.5)
		g.Position               = UDim2.fromScale(0.5, 0.5)
		g.Size                   = UDim2.new(1, pad * 2, 1, pad * 2)
		g.BackgroundColor3       = Color3.new(1, 1, 1)
		g.BackgroundTransparency = 1
		g.BorderSizePixel        = 0
		g.ZIndex                 = 0
		g.Parent                 = holder
		Instance.new("UICorner", g).CornerRadius = UDim.new(0, 8 + pad)
		layers[i] = g
	end
	E.glowState = { layers = layers, preset = nil, color = SELF_BLUE, phase = math.random() * 6, lit = false }
	registerAnim(holder, E.glowState, glowStep)

	------------------------------------------------------------------
	-- BODY
	------------------------------------------------------------------
	local body = Instance.new("Frame")
	body.Name             = "Body"
	body.Size             = UDim2.new(1, 0, 1, 0)
	body.BackgroundColor3 = Color3.new(1, 1, 1)   -- cf. bgSequence()
	body.BorderSizePixel  = 0
	body.ZIndex           = 2
	body.Parent           = holder
	E.body = body
	Instance.new("UICorner", body).CornerRadius = UDim.new(0, 8)

	local bg = Instance.new("UIGradient")
	bg.Name   = "BgGradient"
	bg.Parent = body
	E.bg = bg

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Parent    = body
	E.stroke = stroke

	-- barre de rang
	local bar = Instance.new("Frame")
	bar.Name            = "RankBar"
	bar.Size            = UDim2.new(0, 4, 1, 0)
	bar.BorderSizePixel = 0
	bar.ZIndex          = 3
	bar.Parent          = body
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
	E.bar = bar

	-- #rang
	local rankLbl = Instance.new("TextLabel")
	rankLbl.Name                   = "Rank"
	rankLbl.Size                   = UDim2.new(0.10, 0, 1, 0)
	rankLbl.Position               = UDim2.new(0.005, 0, 0, 0)
	rankLbl.BackgroundTransparency = 1
	rankLbl.TextScaled             = true
	rankLbl.Font                   = Enum.Font.FredokaOne
	rankLbl.TextXAlignment         = Enum.TextXAlignment.Center
	rankLbl.ZIndex                 = 3
	rankLbl.Parent                 = body
	local rankConstraint = Instance.new("UITextSizeConstraint", rankLbl)
	rankConstraint.MinTextSize = 8
	rankConstraint.MaxTextSize = math.floor(H * 0.26)
	E.rankLbl        = rankLbl
	E.rankConstraint = rankConstraint
	E.rankBaseSize   = H * 0.26

	-- avatar
	local avatar = Instance.new("ImageLabel")
	avatar.Name                   = "Avatar"
	avatar.Size                   = UDim2.new(0, avS, 0, avS)
	avatar.Position               = UDim2.new(0.11, 0, 0.5, -avS / 2)
	avatar.BackgroundColor3       = cfg.palette.panel or Color3.fromRGB(30, 30, 35)
	avatar.BorderSizePixel        = 0
	avatar.ZIndex                 = 5
	avatar.Parent                 = body
	Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)
	E.avatar = avatar

	local avStroke = Instance.new("UIStroke")
	avStroke.Thickness    = 2
	avStroke.Transparency = 1
	avStroke.Parent       = avatar
	E.avStroke = avStroke

	-- A3 : dégradé doré sur l'anneau, activé seulement pour les VIP
	local avGrad = Instance.new("UIGradient")
	avGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, GOLD_SOFT),
		ColorSequenceKeypoint.new(0.5, GOLD_DEEP),
		ColorSequenceKeypoint.new(1.0, GOLD_SOFT),
	})
	avGrad.Rotation = 45
	avGrad.Enabled  = false
	avGrad.Parent   = avStroke
	E.avGrad = avGrad

	-- A4 : UN SEUL label de nom (fini le doublon + le container inutile)
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name                   = "PlayerName"
	nameLbl.Position               = UDim2.new(0.24, 0, 0.06, 0)
	nameLbl.Size                   = UDim2.new(0.76, -10, 0.40, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.TextScaled             = true
	nameLbl.Font                   = Enum.Font.FredokaOne
	nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
	nameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
	nameLbl.ZIndex                 = 3
	nameLbl.Parent                 = body
	local nc = Instance.new("UITextSizeConstraint", nameLbl)
	nc.MaxTextSize = math.floor(H * 0.24); nc.MinTextSize = 7
	E.nameLbl = nameLbl
	E.nameFullW = UDim2.new(0.76, -10, 0.40, 0)
	E.nameVipW  = UDim2.new(0.76, -(badgeW + iconW + 30), 0.40, 0)

	-- valeur (icône optionnelle + nombre)
	local valBox = Instance.new("Frame")
	valBox.Name                   = "Value"
	valBox.Position               = UDim2.new(0.24, 0, 0.52, 0)
	valBox.Size                   = UDim2.new(0.60, 0, 0.42, 0)
	valBox.BackgroundTransparency = 1
	valBox.ZIndex                 = 5
	valBox.Parent                 = body
	local vLayout = Instance.new("UIListLayout")
	vLayout.FillDirection     = Enum.FillDirection.Horizontal
	vLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	vLayout.SortOrder         = Enum.SortOrder.LayoutOrder
	vLayout.Padding           = UDim.new(0, 5)
	vLayout.Parent            = valBox

	local valIcon = Instance.new("ImageLabel")
	valIcon.Name                   = "Icon"
	valIcon.LayoutOrder            = 1
	valIcon.Size                   = UDim2.new(0, math.floor(H * 0.32), 0, math.floor(H * 0.32))
	valIcon.BackgroundTransparency = 1
	valIcon.ScaleType              = Enum.ScaleType.Fit
	valIcon.Visible                = false
	valIcon.ZIndex                 = 5
	valIcon.Parent                 = valBox
	if cfg.valueIcon then
		valIcon.Image   = cfg.valueIcon
		valIcon.Visible = true
		if cfg.valueIconColor then valIcon.ImageColor3 = cfg.valueIconColor end
	end
	E.valIcon = valIcon

	local valLbl = Instance.new("TextLabel")
	valLbl.Name                   = "Amount"
	valLbl.LayoutOrder            = 2
	valLbl.AutomaticSize          = Enum.AutomaticSize.X
	valLbl.Size                   = UDim2.new(0, 0, 1, 0)
	valLbl.BackgroundTransparency = 1
	valLbl.TextSize               = cfg.valueTextSize or math.floor(H * 0.30)
	valLbl.Font                   = Enum.Font.FredokaOne
	valLbl.TextXAlignment         = Enum.TextXAlignment.Left
	valLbl.TextColor3             = cfg.valueColor or cfg.palette.accent1 or Color3.new(1, 1, 1)
	valLbl.ZIndex                 = 5
	valLbl.Parent                 = valBox
	E.valLbl = valLbl

	------------------------------------------------------------------
	-- BLOC VIP  (créé une fois, simplement masqué quand non-VIP)
	-- A5 : ancré à DROITE par AnchorPoint → aligné quel que soit le board
	------------------------------------------------------------------
	local vipIcon = Instance.new("ImageLabel")
	vipIcon.Name                   = "VipIcon"
	vipIcon.AnchorPoint            = Vector2.new(1, 0.5)
	vipIcon.Size                   = UDim2.new(0, iconW, 0, iconH)
	vipIcon.Position               = UDim2.new(1, -(badgeW + 18), 0.5, 0)
	vipIcon.BackgroundTransparency = 1
	vipIcon.Image                  = VIP_ICON
	vipIcon.ImageColor3            = Color3.new(1, 1, 1)  -- neutre : couleurs d'origine
	vipIcon.ScaleType              = Enum.ScaleType.Fit
	vipIcon.Visible                = false
	vipIcon.ZIndex                 = 12          -- AU-DESSUS du reflet d'entry (4)
	vipIcon.Parent                 = body
	-- 🔒 verrouille le ratio réel de l'image : plus aucun écrasement.
	local vipRatio = Instance.new("UIAspectRatioConstraint")
	vipRatio.AspectRatio  = VIP_ICON_RATIO
	vipRatio.DominantAxis = Enum.DominantAxis.Height
	vipRatio.Parent       = vipIcon
	E.vipIcon = vipIcon

	-- ❌ AUCUN dégradé sur l'icône : l'image garde ses propres couleurs.

	local badge = Instance.new("TextLabel")
	badge.Name             = "VipBadge"
	badge.AnchorPoint      = Vector2.new(1, 0.5)
	badge.Size             = UDim2.new(0, badgeW, 0, badgeH)
	badge.Position         = UDim2.new(1, -12, 0.5, 0)
	badge.BackgroundColor3 = Color3.new(1, 1, 1)   -- le dégradé fait la couleur
	badge.BorderSizePixel  = 0
	badge.Text             = "VIP"
	badge.TextColor3       = Color3.fromRGB(28, 18, 0)
	badge.TextSize         = math.floor(badgeH * 0.58)
	badge.Font             = Enum.Font.FredokaOne
	badge.TextXAlignment   = Enum.TextXAlignment.Center
	badge.Visible          = false
	badge.ZIndex           = 12         -- AU-DESSUS du reflet d'entry (4)
	badge.Parent           = body
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	E.badge = badge

	-- 🟡 LA PLAQUE DORÉE : dégradé diagonal fixe, comme dans ton code d'origine
	local plate = Instance.new("UIGradient")
	plate.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 240, 100)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 160, 20)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 220, 80)),
	})
	plate.Rotation = 45
	plate.Parent   = badge

	-- B1 : le shimmer est un calque SÉPARÉ posé sur la plaque.
	-- (une instance ne peut porter qu'UN seul UIGradient : plaque + reflet
	--  ne pouvaient donc pas cohabiter sur le badge lui-même)
	local badgeShine = Instance.new("Frame")
	badgeShine.Name                   = "Shine"
	badgeShine.Size                   = UDim2.new(1, 0, 1, 0)
	badgeShine.BackgroundColor3       = Color3.fromRGB(255, 252, 235)
	badgeShine.BackgroundTransparency = 0
	badgeShine.BorderSizePixel        = 0
	badgeShine.ZIndex                 = 13
	badgeShine.Parent                 = badge
	Instance.new("UICorner", badgeShine).CornerRadius = UDim.new(1, 0)

	local shim = Instance.new("UIGradient")
	shim.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 1),
		NumberSequenceKeypoint.new(0.22, 1),
		NumberSequenceKeypoint.new(0.38, 0.88),
		NumberSequenceKeypoint.new(0.50, 0.62),
		NumberSequenceKeypoint.new(0.62, 0.88),
		NumberSequenceKeypoint.new(0.78, 1),
		NumberSequenceKeypoint.new(1.00, 1),
	})
	shim.Rotation = 14
	shim.Offset   = Vector2.new(1, 0)
	shim.Parent   = badgeShine

	-- ⏱️ DEUX états distincts, décalés d'une demi-période : le reflet du badge
	--    et celui de l'entry ne passent JAMAIS en même temps.
	E.shimState  = { on = false, phase = math.random() * SHIMMER_PERIOD,
		sweep = SHIMMER_SWEEP }
	E.badgeShim  = { on = false, sweep = BADGE_SWEEP,
		phase = (E.shimState.phase + BADGE_OFFSET) % SHIMMER_PERIOD }
	registerAnim(shim, E.badgeShim, shimmerStep)

	------------------------------------------------------------------
	-- B1 (étendu) — le même reflet balaye TOUTE l'entry
	--   Un calque quasi invisible posé sur le body : son dégradé est
	--   opaque partout SAUF une bande claire, et c'est cette bande qui
	--   se déplace. ZIndex 4 → passe au-dessus du nom et du score, en
	--   dessous du badge VIP (qui a déjà son propre reflet).
	--   Même table d'état que le badge → les deux reflets sont synchro.
	------------------------------------------------------------------
	local sheen = Instance.new("Frame")
	sheen.Name                   = "Sheen"
	sheen.Size                   = UDim2.new(1, 0, 1, 0)
	sheen.BackgroundColor3       = Color3.fromRGB(255, 246, 214)
	sheen.BackgroundTransparency = 0     -- c'est le dégradé qui gère l'opacité
	sheen.BorderSizePixel        = 0
	sheen.Visible                = false
	sheen.ZIndex                 = 4
	sheen.Parent                 = body
	Instance.new("UICorner", sheen).CornerRadius = UDim.new(0, 8)
	E.sheen = sheen

	local sheenGrad = Instance.new("UIGradient")
	sheenGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 1),
		NumberSequenceKeypoint.new(0.12, 1),
		NumberSequenceKeypoint.new(0.28, 0.94),
		NumberSequenceKeypoint.new(0.42, 0.86),
		NumberSequenceKeypoint.new(0.50, 0.82),   -- coeur de la bande, large
		NumberSequenceKeypoint.new(0.58, 0.86),
		NumberSequenceKeypoint.new(0.72, 0.94),
		NumberSequenceKeypoint.new(0.88, 1),
		NumberSequenceKeypoint.new(1.00, 1),
	})
	sheenGrad.Rotation = 14              -- légère inclinaison, plus naturel
	sheenGrad.Offset   = Vector2.new(1, 0)
	sheenGrad.Parent   = sheen
	registerAnim(sheenGrad, E.shimState, shimmerStep)

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color        = GOLD_SOFT
	badgeStroke.Thickness    = 1.5
	badgeStroke.Transparency = 0.1
	badgeStroke.Parent       = badge

	-- B9 : sparkles
	local spBox = Instance.new("Frame")
	spBox.Name                   = "Sparkles"
	spBox.AnchorPoint            = Vector2.new(1, 0.5)
	spBox.Size                   = UDim2.new(0, badgeW + iconW + 16, 1, 0)
	spBox.Position               = UDim2.new(1, -8, 0.5, 0)
	spBox.BackgroundTransparency = 1
	spBox.ClipsDescendants       = false
	spBox.Visible                = false
	spBox.ZIndex                 = 15
	spBox.Parent                 = body
	E.spBox = spBox

	local parts, bx = {}, { 0.22, 0.55, 0.82 }
	for i = 1, 3 do
		local p = Instance.new("Frame")
		p.Name                   = "Spark" .. i
		p.AnchorPoint            = Vector2.new(0.5, 1)
		p.Size                   = UDim2.new(0, 3, 0, 3)
		p.BackgroundColor3       = GOLD_SOFT
		p.BackgroundTransparency = 1
		p.BorderSizePixel        = 0
		p.ZIndex                 = 15
		p.Parent                 = spBox
		Instance.new("UICorner", p).CornerRadius = UDim.new(1, 0)
		parts[i] = p
	end
	E.sparkState = { on = false, parts = parts, bx = bx, phase = math.random(), lit = false }
	registerAnim(spBox, E.sparkState, sparkleStep)

	------------------------------------------------------------------
	-- 🖱️ SURVOL + CLIC → fiche profil
	------------------------------------------------------------------
	if INTERACTIVE then
		local hintH = math.floor(H * 0.26)
		local hint = Instance.new("Frame")
		hint.Name                   = "ProfileHint"
		hint.AnchorPoint            = Vector2.new(0, 0.5)
		hint.AutomaticSize          = Enum.AutomaticSize.X
		hint.Size                   = UDim2.new(0, 0, 0, hintH)
		hint.BackgroundColor3       = Color3.fromRGB(22, 30, 44)
		hint.BackgroundTransparency = 1
		hint.BorderSizePixel        = 0
		hint.Visible                = false
		hint.ZIndex                 = 16
		hint.Parent                 = body
		Instance.new("UICorner", hint).CornerRadius = UDim.new(1, 0)
		local hStroke = Instance.new("UIStroke")
		hStroke.Color        = SELF_BLUE
		hStroke.Transparency = 1
		hStroke.Parent       = hint
		local hPad = Instance.new("UIPadding")
		hPad.PaddingLeft  = UDim.new(0, math.floor(hintH * 0.35))
		hPad.PaddingRight = UDim.new(0, math.floor(hintH * 0.45))
		hPad.Parent       = hint
		local hList = Instance.new("UIListLayout")
		hList.FillDirection     = Enum.FillDirection.Horizontal
		hList.VerticalAlignment = Enum.VerticalAlignment.Center
		hList.SortOrder         = Enum.SortOrder.LayoutOrder
		hList.Padding           = UDim.new(0, math.floor(hintH * 0.2))
		hList.Parent            = hint

		local hIcon = Instance.new("ImageLabel")
		hIcon.LayoutOrder            = 1
		hIcon.Size                   = UDim2.new(0, math.floor(hintH * 0.8), 0, math.floor(hintH * 0.8))
		hIcon.BackgroundTransparency = 1
		hIcon.Image                  = PROFILE_ICON
		hIcon.ScaleType              = Enum.ScaleType.Fit
		hIcon.ImageTransparency      = 1
		hIcon.ZIndex                 = 17
		hIcon.Parent                 = hint

		local hText = Instance.new("TextLabel")
		hText.LayoutOrder            = 2
		hText.AutomaticSize          = Enum.AutomaticSize.X
		hText.Size                   = UDim2.new(0, 0, 1, 0)
		hText.BackgroundTransparency = 1
		hText.Text                   = "View Profile"
		hText.Font                   = Enum.Font.FredokaOne
		hText.TextSize               = math.floor(hintH * 0.62)
		hText.TextColor3             = Color3.new(1, 1, 1)
		hText.TextTransparency       = 1
		hText.ZIndex                 = 17
		hText.Parent                 = hint

		-- Zone de clic invisible, par-dessus tout le reste de l'entry
		local hit = Instance.new("TextButton")
		hit.Name                   = "Hit"
		hit.Size                   = UDim2.new(1, 0, 1, 0)
		hit.BackgroundTransparency = 1
		hit.Text                   = ""
		hit.AutoButtonColor        = false
		hit.Selectable             = false
		hit.ZIndex                 = 30
		hit.Parent                 = body

		-- Collé juste après le nom (largeur RÉELLE du texte), sans mordre
		-- sur le badge VIP à droite.
		local function placeHint()
			local nb   = nameLbl.TextBounds.X
			local x    = nameLbl.AbsolutePosition.X - body.AbsolutePosition.X + nb + math.floor(H * 0.1)
			local y    = nameLbl.AbsolutePosition.Y - body.AbsolutePosition.Y + nameLbl.AbsoluteSize.Y / 2
			local right = E.badge.Visible and (badgeW + iconW + 30) or 12
			local maxX = body.AbsoluteSize.X - right - hint.AbsoluteSize.X
			hint.Position = UDim2.fromOffset(math.max(0, math.min(x, maxX)), y)
		end

		local avBig = math.floor(avS * 1.12)
		function E.setHover(on)
			if E.hovered == on then return end
			E.hovered = on
			if on then
				if hoveredEntry and hoveredEntry ~= E and hoveredEntry.setHover then
					hoveredEntry.setHover(false)
				end
				hoveredEntry = E
			elseif hoveredEntry == E then
				hoveredEntry = nil
			end

			if HOVER_GROW_ENABLED then
				local h = on and math.floor(H * HOVER_GROW) or H
				TweenService:Create(holder, HOVER_INFO, { Size = UDim2.new(1, 0, 0, h) }):Play()
				local a = on and avBig or avS
				TweenService:Create(avatar, HOVER_INFO, {
					Size = UDim2.new(0, a, 0, a), Position = UDim2.new(0.11, 0, 0.5, -a / 2),
				}):Play()
			end

			if on then
				hint.Visible = true
				placeHint()
				task.defer(placeHint)   -- une fois la nouvelle hauteur appliquée
			end
			local tr = on and 0 or 1
			TweenService:Create(hint,    HOVER_INFO, { BackgroundTransparency = on and 0.15 or 1 }):Play()
			TweenService:Create(hStroke, HOVER_INFO, { Transparency = on and 0.35 or 1 }):Play()
			TweenService:Create(hIcon,   HOVER_INFO, { ImageTransparency = tr }):Play()
			local tw = TweenService:Create(hText, HOVER_INFO, { TextTransparency = tr })
			tw:Play()
			if not on then
				tw.Completed:Connect(function()
					if not E.hovered then hint.Visible = false end
				end)
			end
		end

		hit.MouseEnter:Connect(function() E.setHover(true) end)
		hit.MouseLeave:Connect(function() E.setHover(false) end)
		holder.Destroying:Connect(function()
			if hoveredEntry == E then hoveredEntry = nil end
		end)
		nameLbl:GetPropertyChangedSignal("TextBounds"):Connect(function()
			if E.hovered then placeHint() end
		end)

		hit.Activated:Connect(function()
			local uid = E.avatarId
			if uid then Core.openProfile(uid, E.data) end
		end)
	end

	-- 🏆 style moderne : police BuilderSans (comme les Paramètres / CombatHUD).
	--    Fait UNE fois à la création : les entries sont ensuite réutilisées.
	if cfg._modern then
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("TextLabel") then
				d.FontFace = (d == E.rankLbl or d == E.valLbl) and MF.Heavy or MF.Bold
			end
		end
		for _, c in ipairs(body:GetChildren()) do
			if c:IsA("UICorner") then c.CornerRadius = UDim.new(0, 12) end
		end
	end

	return E
end

--==============================================================================
-- APPLIQUER LES DONNÉES À UNE ENTRY (réutilisation → zéro flash au refresh)
--==============================================================================
local function applyEntry(E, rank, data)
	E.data = data
	local cfg    = E.cfg
	local userId = data.userId
	local isVip  = Core.isVip(userId)
	local isSelf = (LocalPlayer and userId == LocalPlayer.UserId)
	local rc     = rankColor(cfg, rank)

	E.holder.LayoutOrder = rank
	E.holder.Name        = "Entry_" .. rank

	E.bg.Color     = bgSequence(cfg, rank, isVip)
	E.bg.Rotation  = isVip and 0 or ((rank <= 3) and 90 or 0)

	E.bar.BackgroundColor3 = isVip and GOLD or rc

	E.rankLbl.Text       = "#" .. rank
	E.rankLbl.TextColor3 = isVip and GOLD or rc
	-- le #1 est le plus gros, puis ça redescend jusqu'à la taille normale
	E.rankConstraint.MaxTextSize =
		math.floor(E.rankBaseSize * (RANK_SIZE[rank] or 1))

	if E.avatarId ~= userId then
		E.avatarId    = userId
		E.avatar.Image = thumbUrl(userId)   -- C : rbxthumb, aucun yield
	end

	-- anneau de l'avatar : doré pour VIP (A3), couleur de rang pour le top 3
	if isVip then
		-- ⚠️ le UIGradient multiplie Color : il faut du blanc dessous
		E.avStroke.Color        = Color3.new(1, 1, 1)
		E.avStroke.Transparency = 0
		E.avStroke.Thickness    = 3
		E.avGrad.Enabled        = true
	elseif rank <= 3 then
		E.avGrad.Enabled        = false
		E.avStroke.Color        = rc
		E.avStroke.Thickness    = 2
		E.avStroke.Transparency = 0
	else
		E.avGrad.Enabled        = false
		E.avStroke.Transparency = 1
	end

	E.nameLbl.Text      = data.name or ("User " .. tostring(userId))
	E.nameLbl.TextColor3 = isVip and GOLD_NAME or (cfg.palette.white or Color3.new(1, 1, 1))
	E.nameLbl.Size      = isVip and E.nameVipW or E.nameFullW

	local raw = data[cfg.valueKey] or 0
	E.valLbl.Text = (cfg.formatValue or fmtDefault)(raw)
	-- 👥 ami HORS du top (onglet FRIENDS) : « -- » à la place du rang, rangé après le top
	if data.noRank then
		E.rankLbl.Text = "--"
		E.holder.LayoutOrder = 100000 + (tonumber(data._ord) or 0)
		if data.pending then E.valLbl.Text = "…" end
	end

	-- contour du body : doré pour les VIP, neutre pour tout le monde d'autre
	if isVip then
		E.stroke.Color        = GOLD
		E.stroke.Thickness    = 2.5
		E.stroke.Transparency = 0
	else
		E.stroke.Color        = cfg.palette.entryStroke or Color3.fromRGB(40, 40, 50)
		E.stroke.Thickness    = 1
		E.stroke.Transparency = 0.5
	end

	-- bloc VIP
	E.vipIcon.Visible   = isVip
	E.badge.Visible     = isVip
	E.sheen.Visible     = isVip
	E.shimState.on      = isVip
	E.badgeShim.on      = isVip
	-- B9 plafonné au top 10 pour ne pas animer 50 entries
	local sparkOn       = isVip and rank <= (cfg.sparkleMaxRank or SPARKLE_MAX_RANK)
	E.spBox.Visible     = sparkOn
	E.sparkState.on     = sparkOn

	-- B8 : halo bleu clair autour de l'entry, uniquement pour toi
	E.glowState.preset = isSelf and SELF_GLOW or nil
	E.glowState.color  = SELF_BLUE
end

--==============================================================================
-- B4 — APPARITION EN CASCADE
--==============================================================================
local INTRO_INFO = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function playIntro(E, index)
	local body = E.body

	-- ⚠️ applyEntry() a déjà posé les valeurs finales : on les mémorise AVANT
	-- de tout remettre à zéro, sinon la cible du tween serait « invisible ».
	local strokeTarget = E.stroke.Transparency
	local sheenWasOn   = E.sheen.Visible
	E.sheen.Visible    = false            -- pas de reflet pendant le fade-in

	body.Position                = UDim2.new(-0.07, 0, 0, 0)
	body.BackgroundTransparency  = 1
	E.stroke.Transparency        = 1
	E.rankLbl.TextTransparency   = 1
	E.nameLbl.TextTransparency   = 1
	E.valLbl.TextTransparency    = 1
	E.avatar.ImageTransparency   = 1
	E.bar.BackgroundTransparency = 1

	local d = math.min((index - 1) * 0.035, 1.2)

	task.delay(d, function()
		if not body.Parent then return end
		TweenService:Create(body, INTRO_INFO, {
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 0,
		}):Play()
		TweenService:Create(E.stroke,  INTRO_INFO, { Transparency = strokeTarget }):Play()
		TweenService:Create(E.rankLbl, INTRO_INFO, { TextTransparency = 0 }):Play()
		TweenService:Create(E.nameLbl, INTRO_INFO, { TextTransparency = 0 }):Play()
		TweenService:Create(E.valLbl,  INTRO_INFO, { TextTransparency = 0 }):Play()
		TweenService:Create(E.avatar,  INTRO_INFO, { ImageTransparency = 0 }):Play()
		TweenService:Create(E.bar,     INTRO_INFO, { BackgroundTransparency = 0 }):Play()
		task.delay(0.4, function()
			if body.Parent then E.sheen.Visible = sheenWasOn end
		end)
	end)
end

--==============================================================================
-- LIST VIEW  —  réutilise les frames existantes (C : plus de flash au refresh)
--==============================================================================
local ListView = {}
ListView.__index = ListView

function Core.newListView(scroll, cfg)
	cfg = cfg or {}
	cfg.palette     = cfg.palette or {}
	cfg.entryHeight = cfg.entryHeight or 68
	cfg.topSize     = cfg.topSize or 25
	cfg.valueKey    = cfg.valueKey or "value"

	local self = setmetatable({}, ListView)
	self.scroll   = scroll
	self.cfg      = cfg
	self.entries  = {}
	self.msg      = nil
	self.lastList = nil
	table.insert(liveViews, self)   -- pour le rafraîchissement VIP instantané
	return self
end

function ListView:_message(text)
	if not self.msg then
		local l = Instance.new("TextLabel")
		l.Name                   = "Message"
		l.Size                   = UDim2.new(1, 0, 0, 50)
		l.BackgroundTransparency = 1
		l.TextColor3             = self.cfg.palette.muted or Color3.fromRGB(140, 140, 150)
		l.TextScaled             = true
		l.Font                   = Enum.Font.Gotham
		l.LayoutOrder            = 9999
		l.Parent                 = self.scroll
		local c = Instance.new("UITextSizeConstraint", l)
		c.MaxTextSize = 20; c.MinTextSize = 10
		self.msg = l
	end
	self.msg.Text    = text or ""
	self.msg.Visible = (text ~= nil)
end

function ListView:showEmpty(text)
	for i = #self.entries, 1, -1 do
		self.entries[i].holder:Destroy()
		self.entries[i] = nil
	end
	self:_message(text or "No data yet...")
end

function ListView:render(list)
	if not self.scroll or not self.scroll.Parent then return end
	self.lastList = list
	local cfg = self.cfg
	local n   = math.min(#list, cfg.topSize + (tonumber(list.extra) or 0))   -- extra : ta ligne « -- » (FIND ME)

	if n == 0 then
		self:showEmpty(cfg.emptyText)
		return
	end
	self:_message(nil)

	for i = 1, n do
		local E = self.entries[i]
		-- vue filtrée (FRIENDS) : on garde la VRAIE place du joueur dans le classement
		local rank = (self.useDataRank and tonumber(list[i].rank)) or i
		if not E then
			E = buildEntry(cfg, self.scroll, i)
			self.entries[i] = E
			applyEntry(E, rank, list[i])
			playIntro(E, i)              -- B4 : seulement les nouvelles entries
		else
			applyEntry(E, rank, list[i]) -- refresh silencieux, aucun flash
		end
	end

	for i = #self.entries, n + 1, -1 do
		self.entries[i].holder:Destroy()
		self.entries[i] = nil
	end
end

function ListView:destroy()
	for i = #self.entries, 1, -1 do
		self.entries[i].holder:Destroy()
		self.entries[i] = nil
	end
	if self.msg then self.msg:Destroy(); self.msg = nil end
end

--==============================================================================
-- INDICATEUR DE CHARGEMENT
--==============================================================================
local function createLoader(parent, cfg)
	local frame = Instance.new("Frame")
	frame.Name                   = "LoadingIndicator"
	frame.Size                   = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.ZIndex                 = 50
	frame.Parent                 = parent

	local icon = Instance.new("TextLabel")
	icon.AnchorPoint            = Vector2.new(0.5, 0.5)
	icon.Size                   = UDim2.new(0, 60, 0, 60)
	icon.Position               = UDim2.new(0.5, 0, 0.35, 0)
	icon.BackgroundTransparency = 1
	icon.Text                   = cfg.loadingIcon or "★"
	icon.TextColor3             = cfg.palette.accent1 or Color3.new(1, 1, 1)
	icon.TextScaled             = true
	icon.Font                   = Enum.Font.FredokaOne
	icon.ZIndex                 = 51
	icon.Parent                 = frame

	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint            = Vector2.new(0.5, 0)
	lbl.Size                   = UDim2.new(0.8, 0, 0, 32)
	lbl.Position               = UDim2.new(0.5, 0, 0.55, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = "LOADING..."
	lbl.TextColor3             = cfg.palette.accent2 or cfg.palette.accent1 or Color3.new(1, 1, 1)
	lbl.TextScaled             = true
	lbl.Font                   = Enum.Font.FredokaOne
	lbl.ZIndex                 = 51
	lbl.Parent                 = frame
	local lc = Instance.new("UITextSizeConstraint", lbl)
	lc.MaxTextSize = 24; lc.MinTextSize = 12

	-- animé par la boucle centrale : rien à annuler, rien qui fuit
	registerAnim(frame, { phase = 0 }, function(t, s, f)
		local k = math.sin(t * 3)
		icon.Position       = UDim2.new(0.5, 0, 0.35 - 0.045 * k, 0)
		lbl.TextTransparency = 0.25 + 0.25 * (0.5 + 0.5 * math.sin(t * 2))
	end)

	return frame
end

Core.createLoader = createLoader

--==============================================================================
-- UI D'UN BOARD (SurfaceGui)
--==============================================================================
local function buildBoardUI(cfg, sg)
	for _, c in ipairs(sg:GetChildren()) do c:Destroy() end
	local p = cfg.palette
	local reserve = cfg.bottomReserve or 0

	local main = Instance.new("Frame")
	main.Name             = "MainFrame"
	main.Size             = UDim2.new(1, 0, 1, 0)
	main.BackgroundColor3 = p.bg      -- rendu sombre d'origine (le dégradé multiplie)
	main.BorderSizePixel  = 0
	main.Parent           = sg

	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color    = ColorSequence.new(p.bgA or p.bg, p.bgB or p.bg)
	bgGrad.Rotation = 135
	bgGrad.Parent   = main

	local header = Instance.new("Frame")
	header.Name             = "Header"
	header.Size             = UDim2.new(1, 0, 0.09, 0)
	header.BackgroundColor3 = p.headerMid or p.panel   -- sombre, comme avant
	header.BorderSizePixel  = 0
	header.Parent           = main

	local hGrad = Instance.new("UIGradient")
	hGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, p.headerEdge or p.panel),
		ColorSequenceKeypoint.new(0.5, p.headerMid  or p.panel),
		ColorSequenceKeypoint.new(1.0, p.headerEdge or p.panel),
	})
	hGrad.Parent = header

	local hStroke = Instance.new("UIStroke")
	hStroke.Color        = p.accent1
	hStroke.Thickness    = 3
	hStroke.Transparency = 0.2
	hStroke.Parent       = header

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, 0, 1, 0)
	title.BackgroundTransparency = 1
	title.Text                   = cfg.title
	title.TextColor3             = p.accent2 or p.accent1
	title.TextScaled             = true
	title.Font                   = Enum.Font.FredokaOne
	title.Parent                 = header
	local tc = Instance.new("UITextSizeConstraint", title)
	tc.MaxTextSize = 46; tc.MinTextSize = 20

	-- 👥 ALL / FRIENDS (à gauche) + 🔍 FIND ME discret (à droite), dans l'en-tête d'avant.
	--    Le titre reste centré : on lui laisse juste la place du milieu.
	local tabs = nil
	if TABS then
		title.AnchorPoint = Vector2.new(0.5, 0)
		title.Position    = UDim2.new(0.5, 0, 0, 0)
		title.Size        = UDim2.new(0.52, 0, 1, 0)
		local accent = p.accent1 or Color3.new(1, 1, 1)
		local dark   = p.panel or Color3.fromRGB(20, 20, 26)

		local seg = Instance.new("Frame")
		seg.Name = "Tabs"
		seg.AnchorPoint = Vector2.new(0, 0.5)
		seg.Position = UDim2.new(0.012, 0, 0.5, 0)
		seg.Size = UDim2.new(0.21, 0, 0.6, 0)
		seg.BackgroundColor3 = dark
		seg.BorderSizePixel = 0
		seg.Parent = header
		Instance.new("UICorner", seg).CornerRadius = UDim.new(1, 0)
		local ss = Instance.new("UIStroke") ; ss.Color = accent ; ss.Thickness = 2 ; ss.Transparency = 0.35 ; ss.Parent = seg
		local function half(text, x)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(0.5, -4, 1, -8)
			b.Position = UDim2.new(x, x == 0 and 4 or 0, 0, 4)
			b.BackgroundColor3 = accent
			b.BackgroundTransparency = 1
			b.AutoButtonColor = false
			b.Text = text
			b.Font = Enum.Font.FredokaOne
			b.TextScaled = true
			b.TextColor3 = p.muted or Color3.fromRGB(170, 170, 180)
			b.Parent = seg
			Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
			local c = Instance.new("UITextSizeConstraint", b) ; c.MaxTextSize = 24 ; c.MinTextSize = 8
			local pd = Instance.new("UIPadding", b) ; pd.PaddingTop = UDim.new(0.14, 0) ; pd.PaddingBottom = UDim.new(0.14, 0)
			return b
		end
		local allB = half("ALL", 0)
		local frB  = half("FRIENDS", 0.5)

		-- 🔍 FIND ME : loupe ronde + « FIND ME » écrit en petit dessous (toute la zone est cliquable)
		local find = Instance.new("TextButton")
		find.Name = "FindMe"
		find.AnchorPoint = Vector2.new(1, 0.5)
		find.Position = UDim2.new(0.98, 0, 0.5, 0)
		find.Size = UDim2.new(0.1, 0, 0.96, 0)
		find.BackgroundTransparency = 1
		find.AutoButtonColor = false
		find.Text = ""
		find.Parent = header
		local glass = Instance.new("TextLabel")
		glass.Name = "Loupe"
		glass.AnchorPoint = Vector2.new(0.5, 0)
		glass.Position = UDim2.new(0.5, 0, 0, 0)
		-- 🩹 largeur PLEINE : la contrainte (FitWithinMaxSize) fait un carré QUI TIENT dans cette boîte.
		--    Avec une largeur 0, le carré faisait 0 → seule la légende « FIND ME » restait visible.
		glass.Size = UDim2.new(1, 0, 0.7, 0)
		glass.BackgroundColor3 = dark
		glass.BackgroundTransparency = 0.2
		glass.Text = "🔍"
		glass.TextScaled = true
		glass.TextColor3 = Color3.new(1, 1, 1)
		glass.Parent = find
		local far = Instance.new("UIAspectRatioConstraint", glass)
		far.AspectRatio = 1
		far.AspectType = Enum.AspectType.FitWithinMaxSize
		Instance.new("UICorner", glass).CornerRadius = UDim.new(1, 0)
		local fs = Instance.new("UIStroke") ; fs.Color = accent ; fs.Thickness = 1.5 ; fs.Transparency = 0.5 ; fs.Parent = glass
		local fp = Instance.new("UIPadding", glass) ; fp.PaddingTop = UDim.new(0.12, 0) ; fp.PaddingBottom = UDim.new(0.12, 0)
		local cap = Instance.new("TextLabel")
		cap.Name = "Caption"
		cap.AnchorPoint = Vector2.new(0.5, 1)
		cap.Position = UDim2.new(0.5, 0, 1, 0)
		cap.Size = UDim2.new(1.4, 0, 0.26, 0)   -- un peu plus large que la loupe : le texte reste lisible
		cap.BackgroundTransparency = 1
		cap.Text = "FIND ME"
		cap.Font = Enum.Font.FredokaOne
		cap.TextScaled = true
		cap.TextColor3 = p.muted or Color3.fromRGB(190, 190, 200)
		cap.Parent = find
		local cc = Instance.new("UITextSizeConstraint", cap) ; cc.MaxTextSize = 18 ; cc.MinTextSize = 6
		find.MouseEnter:Connect(function() glass.BackgroundTransparency = 0 end)
		find.MouseLeave:Connect(function() glass.BackgroundTransparency = 0.2 end)

		tabs = {
			all = allB, friends = frB, findMe = find, frL = frB, friendsText = "FRIENDS",
			setSelected = function(which)
				for _, pair in ipairs({ { allB, "all" }, { frB, "friends" } }) do
					local on = pair[2] == which
					pair[1].BackgroundTransparency = on and 0 or 1
					pair[1].TextColor3 = on and Color3.fromRGB(20, 16, 8) or (p.muted or Color3.fromRGB(170, 170, 180))
				end
			end,
		}
		tabs.setSelected("all")
	end

	local divider = Instance.new("Frame")
	divider.Size             = UDim2.new(0.95, 0, 0, 2)
	divider.Position         = UDim2.new(0.025, 0, 0.09, 1)
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BorderSizePixel  = 0
	divider.Parent           = main
	local dGrad = Instance.new("UIGradient")
	dGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.new(0, 0, 0)),
		ColorSequenceKeypoint.new(0.2, p.accent1),
		ColorSequenceKeypoint.new(0.5, p.accent2 or p.accent1),
		ColorSequenceKeypoint.new(0.8, p.accent1),
		ColorSequenceKeypoint.new(1.0, Color3.new(0, 0, 0)),
	})
	dGrad.Parent = divider

	local content = Instance.new("Frame")
	content.Name             = "ContentFrame"
	content.Size             = UDim2.new(0.96, 0, 0.835 - reserve, 0)
	content.Position         = UDim2.new(0.02, 0, 0.103, 0)
	content.BackgroundColor3 = p.panel
	content.BorderSizePixel  = 0
	content.ClipsDescendants = true
	content.Parent           = main
	Instance.new("UICorner", content).CornerRadius = UDim.new(0, 12)

	local cStroke = Instance.new("UIStroke")
	cStroke.Color        = p.stroke
	cStroke.Thickness    = 1
	cStroke.Transparency = 0.5
	cStroke.Parent       = content

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                   = "ScrollingFrame"
	scroll.Size                   = UDim2.new(0.97, 0, 0.97, 0)
	scroll.Position               = UDim2.new(0.015, 0, 0.015, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel        = 0
	scroll.ScrollBarThickness     = 5
	scroll.ScrollBarImageColor3   = p.accent2 or p.accent1
	scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	scroll.ClipsDescendants       = true
	scroll.Parent                 = content

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding   = UDim.new(0, 8)   -- 8 px : laisse respirer les halos
	list.Parent    = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft   = UDim.new(0, 16)   -- marge pour le débord des halos
	pad.PaddingRight  = UDim.new(0, 16)
	pad.Parent        = scroll

	local footer = Instance.new("Frame")
	footer.Name             = "Footer"
	footer.Size             = UDim2.new(0.96, 0, 0.057, 0)
	footer.Position         = UDim2.new(0.02, 0, 0.938 - reserve, 0)
	footer.BackgroundColor3 = p.footer or p.panel
	footer.BorderSizePixel  = 0
	footer.Parent           = main
	Instance.new("UICorner", footer).CornerRadius = UDim.new(0, 8)

	local fStroke = Instance.new("UIStroke")
	fStroke.Color        = p.stroke
	fStroke.Thickness    = 1
	fStroke.Transparency = 0.5
	fStroke.Parent       = footer

	local refreshLbl = Instance.new("TextLabel")
	refreshLbl.Name                   = "RefreshLabel"
	refreshLbl.Size                   = UDim2.new(1, 0, 1, 0)
	refreshLbl.BackgroundTransparency = 1
	refreshLbl.Text                   = "Refresh in --:--"
	refreshLbl.TextColor3             = p.muted
	refreshLbl.TextScaled             = true
	refreshLbl.Font                   = Enum.Font.Gotham
	refreshLbl.Parent                 = footer
	local flc = Instance.new("UITextSizeConstraint", refreshLbl)
	flc.MaxTextSize = 16; flc.MinTextSize = 8

	return {
		main       = main,
		header     = header,
		content    = content,
		scroll     = scroll,
		footer     = footer,
		refreshLbl = refreshLbl,
		tabs       = tabs,
	}
end

--==============================================================================
-- 🏆 UI D'UN BOARD — STYLE MODERNE (Paramètres / CombatHUD)
--   Mêmes champs renvoyés que buildBoardUI (main, content, scroll, footer,
--   refreshLbl) : les hooks existants (bouton DONATE…) marchent tels quels.
--   + tabs (ALL / FRIENDS / FIND ME), youRow (ta place), barFill (next update)
--==============================================================================
local function modernButton(parent, text, col, size, pos)
	local depth, radius = 6, 14
	local slot = Instance.new("Frame")
	slot.Size = size
	slot.Position = pos
	slot.BackgroundTransparency = 1
	slot.Parent = parent
	local edge = Instance.new("Frame")
	edge.Size = UDim2.new(1, 0, 1, -depth)
	edge.Position = UDim2.fromOffset(0, depth)
	edge.BackgroundColor3 = col[3]
	edge.BorderSizePixel = 0
	edge.Parent = slot
	Instance.new("UICorner", edge).CornerRadius = UDim.new(0, radius)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, -depth)
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.ZIndex = 2
	btn.Parent = slot
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, radius)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(col[1], col[2])
	grad.Parent = btn
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.ZIndex = 4
	lbl.Parent = btn
	local tc = Instance.new("UITextSizeConstraint", lbl)
	tc.MaxTextSize = 30 ; tc.MinTextSize = 10
	local lp = Instance.new("UIPadding", lbl)
	lp.PaddingTop, lp.PaddingBottom = UDim.new(0.18, 0), UDim.new(0.18, 0)
	local function press(down) btn.Position = UDim2.fromOffset(0, down and depth or 0) end
	btn.MouseButton1Down:Connect(function() press(true) end)
	btn.MouseButton1Up:Connect(function() press(false) end)
	btn.MouseLeave:Connect(function() press(false) end)
	btn.Activated:Connect(function() task.delay(0.08, function() press(false) end) end)
	local function recolor(c) grad.Color = ColorSequence.new(c[1], c[2]) ; edge.BackgroundColor3 = c[3] end
	return btn, lbl, recolor
end

local function buildBoardUIModern(cfg, sg)
	for _, c in ipairs(sg:GetChildren()) do c:Destroy() end
	local p = cfg.palette
	local r = cfg.bottomReserve or 0
	local accent = p.accent1 or Color3.fromRGB(70, 150, 245)

	local main = Instance.new("Frame")
	main.Name             = "MainFrame"
	main.Size             = UDim2.new(1, 0, 1, 0)
	main.BackgroundColor3 = Color3.new(1, 1, 1)
	main.BorderSizePixel  = 0
	main.Parent           = sg
	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color    = ColorSequence.new(MODERN_PALETTE.bgA, MODERN_PALETTE.bgB)
	bgGrad.Rotation = 90
	bgGrad.Parent   = main

	-- en-tête : titre blanc à gauche (comme « SETTINGS »), trait de couleur du board
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(0.96, 0, 0.075, 0)
	header.Position = UDim2.new(0.02, 0, 0.015, 0)
	header.BackgroundTransparency = 1
	header.Parent = main
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 10, 0.8, 0)
	stripe.Position = UDim2.new(0, 0, 0.1, 0)
	stripe.BackgroundColor3 = accent
	stripe.BorderSizePixel = 0
	stripe.Parent = header
	Instance.new("UICorner", stripe).CornerRadius = UDim.new(1, 0)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.75, 0, 1, 0)
	title.Position = UDim2.new(0, 26, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = cfg.title or ""
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = header
	local tc = Instance.new("UITextSizeConstraint", title)
	tc.MaxTextSize = 54 ; tc.MinTextSize = 20
	local icon = Instance.new("TextLabel")
	icon.AnchorPoint = Vector2.new(1, 0.5)
	icon.Size = UDim2.new(0.2, 0, 0.9, 0)
	icon.Position = UDim2.new(1, 0, 0.5, 0)
	icon.BackgroundTransparency = 1
	icon.Text = "TOP " .. tostring(cfg.topSize or "")
	icon.FontFace = MF.Heavy
	icon.TextScaled = true
	icon.TextXAlignment = Enum.TextXAlignment.Right
	icon.TextColor3 = accent
	icon.Parent = header
	local ic = Instance.new("UITextSizeConstraint", icon)
	ic.MaxTextSize = 34 ; ic.MinTextSize = 10

	-- onglets
	local tabs = nil
	if STYLE.Tabs then
		local row = Instance.new("Frame")
		row.Name = "Tabs"
		row.Size = UDim2.new(0.96, 0, 0.062, 0)
		row.Position = UDim2.new(0.02, 0, 0.098, 0)
		row.BackgroundTransparency = 1
		row.Parent = main
		local allB, allL, allC = modernButton(row, "ALL", BTN.blue, UDim2.new(0.2, 0, 1, 0), UDim2.new(0, 0, 0, 0))
		local frB, frL, frC = modernButton(row, "FRIENDS", BTN.grey, UDim2.new(0.24, 0, 1, 0), UDim2.new(0.215, 0, 0, 0))
		local meB = modernButton(row, "🔍 FIND ME", BTN.teal, UDim2.new(0.26, 0, 1, 0), UDim2.new(0.74, 0, 0, 0))
		tabs = { all = allB, friends = frB, findMe = meB, allColor = allC, friendsColor = frC, allL = allL, frL = frL }
	end
	local top = STYLE.Tabs and 0.172 or 0.1

	local content = Instance.new("Frame")
	content.Name             = "ContentFrame"
	content.Size             = UDim2.new(0.96, 0, (STYLE.YourRow and 0.835 or 0.9) - top - r, 0)
	content.Position         = UDim2.new(0.02, 0, top, 0)
	content.BackgroundColor3 = MODERN_PALETTE.panel
	content.BackgroundTransparency = 0.1
	content.BorderSizePixel  = 0
	content.ClipsDescendants = true
	content.Parent           = main
	Instance.new("UICorner", content).CornerRadius = UDim.new(0, 16)
	local cStroke = Instance.new("UIStroke")
	cStroke.Color = MODERN_PALETTE.stroke ; cStroke.Thickness = 1.5 ; cStroke.Transparency = 0.4
	cStroke.Parent = content

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                   = "ScrollingFrame"
	scroll.Size                   = UDim2.new(0.97, 0, 0.97, 0)
	scroll.Position               = UDim2.new(0.015, 0, 0.015, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel        = 0
	scroll.ScrollBarThickness     = 6
	scroll.ScrollBarImageColor3   = accent
	scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	scroll.ClipsDescendants       = true
	scroll.Parent                 = content
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding   = UDim.new(0, 8)
	list.Parent    = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
	pad.Parent = scroll

	-- ta ligne
	local youRow, youLbl = nil, nil
	if STYLE.YourRow then
		youRow = Instance.new("Frame")
		youRow.Name = "YouRow"
		youRow.Size = UDim2.new(0.96, 0, 0.06, 0)
		youRow.Position = UDim2.new(0.02, 0, 0.845 - r, 0)
		youRow.BackgroundColor3 = MODERN_PALETTE.entry
		youRow.BorderSizePixel = 0
		youRow.Parent = main
		Instance.new("UICorner", youRow).CornerRadius = UDim.new(0, 12)
		local ys = Instance.new("UIStroke")
		ys.Color = ME_COLOR ; ys.Thickness = 2 ; ys.Transparency = 0.25
		ys.Parent = youRow
		local av = Instance.new("ImageLabel")
		av.Size = UDim2.new(0, 46, 0, 46)
		av.AnchorPoint = Vector2.new(0, 0.5)
		av.Position = UDim2.new(0, 12, 0.5, 0)
		av.BackgroundColor3 = MODERN_PALETTE.panel
		av.Image = LocalPlayer and thumbUrl(LocalPlayer.UserId) or ""
		av.Parent = youRow
		Instance.new("UICorner", av).CornerRadius = UDim.new(1, 0)
		youLbl = Instance.new("TextLabel")
		youLbl.Size = UDim2.new(1, -80, 0.8, 0)
		youLbl.Position = UDim2.new(0, 70, 0.1, 0)
		youLbl.BackgroundTransparency = 1
		youLbl.FontFace = MF.Bold
		youLbl.TextScaled = true
		youLbl.RichText = true
		youLbl.TextXAlignment = Enum.TextXAlignment.Left
		youLbl.TextColor3 = MODERN_PALETTE.white
		youLbl.Text = "YOU · loading…"
		youLbl.Parent = youRow
		local yc = Instance.new("UITextSizeConstraint", youLbl)
		yc.MaxTextSize = 28 ; yc.MinTextSize = 10
	end

	-- pied : « NEXT UPDATE » + fine barre
	local footer = Instance.new("Frame")
	footer.Name             = "Footer"
	footer.Size             = UDim2.new(0.96, 0, 0.05, 0)
	footer.Position         = UDim2.new(0.02, 0, 0.92 - r, 0)
	footer.BackgroundTransparency = 1
	footer.Parent           = main
	local refreshLbl = Instance.new("TextLabel")
	refreshLbl.Name = "RefreshLabel"
	refreshLbl.Size = UDim2.new(1, 0, STYLE.UpdateBar and 0.62 or 1, 0)
	refreshLbl.BackgroundTransparency = 1
	refreshLbl.Text = "NEXT UPDATE --:--"
	refreshLbl.TextColor3 = MODERN_PALETTE.muted
	refreshLbl.TextScaled = true
	refreshLbl.FontFace = MF.Bold
	refreshLbl.TextXAlignment = Enum.TextXAlignment.Left
	refreshLbl.Parent = footer
	local flc = Instance.new("UITextSizeConstraint", refreshLbl)
	flc.MaxTextSize = 22 ; flc.MinTextSize = 8
	local barFill = nil
	if STYLE.UpdateBar then
		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, 0, 0.18, 0)
		track.Position = UDim2.new(0, 0, 0.78, 0)
		track.BackgroundColor3 = MODERN_PALETTE.entry
		track.BorderSizePixel = 0
		track.Parent = footer
		Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
		barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(0, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.new(1, 1, 1)
		barFill.BackgroundTransparency = 0.15
		barFill.BorderSizePixel = 0
		barFill.Parent = track
		Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)
	end

	return {
		main       = main,
		header     = header,
		content    = content,
		scroll     = scroll,
		footer     = footer,
		refreshLbl = refreshLbl,
		tabs       = tabs,
		youRow     = youRow,
		youLbl     = youLbl,
		barFill    = barFill,
	}
end

--==============================================================================
-- 👥 AMIS (lus une fois, gardés en mémoire) — pour l'onglet FRIENDS
--==============================================================================
local friendSet, friendsAt, friendsLoading = nil, -1e9, false
local friendNames = {}   -- [userId] = nom affiché (pour les amis hors du top)
local friendWaiters = {}
local function withFriends(cb)
	if friendSet and os.clock() - friendsAt < (STYLE.FriendsCacheSeconds or 600) then cb() return end
	table.insert(friendWaiters, cb)
	if friendsLoading then return end
	friendsLoading = true
	task.spawn(function()
		local set = {}
		local ok = pcall(function()
			local pages = Players:GetFriendsAsync(LocalPlayer.UserId)
			for _ = 1, 8 do   -- 8 pages max (≈ 400 amis) : largement assez
				for _, f in ipairs(pages:GetCurrentPage()) do
					set[f.Id] = true
					friendNames[f.Id] = f.DisplayName or f.Username
				end
				if pages.IsFinished then break end
				pages:AdvanceToNextPageAsync()
			end
		end)
		if ok then friendSet, friendsAt = set, os.clock()
		elseif not friendSet then friendSet = {} end   -- échec : liste vide (on réessaiera plus tard)
		friendsLoading = false
		local list = friendWaiters
		friendWaiters = {}
		for _, f in ipairs(list) do pcall(f) end
	end)
end

--==============================================================================
-- MOUNT  —  point d'entrée appelé par chaque LocalScript
--==============================================================================
function Core.mount(cfg)
	cfg.palette        = cfg.palette or {}
	cfg.entryHeight    = cfg.entryHeight or 68
	cfg.topSize        = cfg.topSize or 25
	cfg.refreshDelay   = cfg.refreshDelay or 120
	cfg.firstLoadDelay = cfg.firstLoadDelay or 3   -- C : plus de task.wait(80) !
	cfg.emptyText      = cfg.emptyText or "No data yet..."

	-- 🏆 style moderne : fonds neutres (copie : la palette d'origine n'est JAMAIS modifiée,
	--    elle peut servir ailleurs — ex. la fenêtre des dons). Les accents restent ceux du board.
	if MODERN then
		local pal = {}
		for k, v in pairs(cfg.palette) do pal[k] = v end
		for k, v in pairs(MODERN_PALETTE) do pal[k] = v end
		cfg.palette = pal
		cfg._modern = true
	end

	local ctx = {
		cfg          = cfg,
		boards       = {},
		data         = nil,
		stamp        = 0,      -- incrémenté à chaque nouveau jeu de données
		lastRefresh  = 0,
		isRefreshing = false,
	}

	local getFunc = ReplicatedStorage:WaitForChild(cfg.getFunctionName, 20)
	local updEvt  = cfg.updateEventName and ReplicatedStorage:WaitForChild(cfg.updateEventName, 20) or nil

	----------------------------------------------------------------
	-- déduplication + tri
	----------------------------------------------------------------
	local function dedupe(raw)
		local seen, out = {}, {}
		for _, e in ipairs(raw) do
			local k = tostring(e.userId)
			if e.userId and not seen[k] then
				seen[k] = true
				table.insert(out, e)
				local ks = knownStats[e.userId] or {}
				for f, v in pairs(e) do
					if f ~= "rank" then ks[f] = v end
				end
				knownStats[e.userId] = ks
			end
		end
		table.sort(out, function(a, b)
			return (a[cfg.valueKey] or 0) > (b[cfg.valueKey] or 0)
		end)
		for i, e in ipairs(out) do e.rank = i end
		return out
	end

	----------------------------------------------------------------
	-- rendu sur tous les boards
	----------------------------------------------------------------
	-- 🏆 ta ligne (style moderne)
	local function updateYou(b)
		if not (b.youLbl and b.youLbl.Parent) or not ctx.data then return end
		local me = LocalPlayer and LocalPlayer.UserId
		for _, e in ipairs(ctx.data) do
			if e.userId == me then
				b.youLbl.Text = string.format('<font color="#%s">#%d</font>   YOU   ·   %s', ME_COLOR:ToHex(),
					e.rank or 0, (cfg.formatValue or fmtDefault)(e[cfg.valueKey] or 0))
				return
			end
		end
		b.youLbl.Text = string.format('YOU   ·   <font color="#%s">not in the top %d yet — keep going!</font>',
			MODERN_PALETTE.muted:ToHex(), math.min(#ctx.data, cfg.topSize))
	end

	-- 👥 score des amis HORS du top (FriendsBoard_Server), gardé 5 min
	local BOARD_KEY = ({ GetPointsLeaderboard = "Points", GetRebirthLeaderboard = "Rebirths",
		GetStreakLeaderboard = "Streak", GetKillLeaderboard = "Kills", GetLeaderboardData = "Donations" })[cfg.getFunctionName or ""]
	local friendVals, friendValsAt, friendValsBusy = {}, -1e9, false
	local renderBoard
	local function fetchFriendValues(ids)
		if not BOARD_KEY or friendValsBusy or #ids == 0 then return end
		if os.clock() - friendValsAt < 300 then return end
		local fn = ReplicatedStorage:FindFirstChild("GetFriendsBoardValues")
		if not fn then return end
		friendValsBusy = true
		task.spawn(function()
			local res
			for _ = 1, 3 do
				local ok, r = pcall(function() return fn:InvokeServer(BOARD_KEY, ids) end)
				if ok and type(r) == "table" and not r.throttled then res = r break end
				task.wait(3.2)
			end
			friendValsBusy = false
			friendValsAt = os.clock()
			if type(res) == "table" then
				for k, v in pairs(res) do
					local id = tonumber(k)
					if id and type(v) == "number" then friendVals[id] = v end
				end
			end
			for _, bb in ipairs(ctx.boards) do
				if bb.filter == "friends" and bb.scroll and bb.scroll.Parent then renderBoard(bb) end
			end
		end)
	end

	-- 🏆 liste montrée par un board : tout le monde, ou toi + TOUS tes amis
	--    (ceux du top avec leur vraie place, les autres avec « -- » en dessous)
	renderBoard = function(b)
		if not ctx.data then return end
		if b.filter == "friends" then
			local me = LocalPlayer and LocalPlayer.UserId
			local out, inTop = {}, {}
			for _, e in ipairs(ctx.data) do
				if e.userId == me or (friendSet and friendSet[e.userId]) then
					table.insert(out, e)
					inTop[e.userId] = true
				end
			end
			-- amis (et toi) hors du top : affichés quand même, rang « -- »
			local others, missing = {}, {}
			local function addOther(id, name)
				if inTop[id] then return end
				local v = friendVals[id]
				if v == nil then table.insert(missing, id) end
				table.insert(others, { userId = id, name = name, [cfg.valueKey] = v or 0,
					noRank = true, pending = (v == nil) and BOARD_KEY ~= nil })
			end
			if me then addOther(me, LocalPlayer.DisplayName) end
			for id in pairs(friendSet or {}) do addOther(id, friendNames[id] or ("User " .. id)) end
			table.sort(others, function(a, c)
				local va, vc = a[cfg.valueKey] or 0, c[cfg.valueKey] or 0
				if va ~= vc then return va > vc end
				return tostring(a.name) < tostring(c.name)
			end)
			for i, e in ipairs(others) do e._ord = i ; e.rank = 9999 ; table.insert(out, e) end
			if #missing > 0 then
				table.sort(missing)
				local ids = {}
				for i = 1, math.min(#missing, 50) do ids[i] = missing[i] end
				fetchFriendValues(ids)
			end
			if #out == 0 then
				b.view.lastList = nil   -- sinon un repaint VIP réafficherait la liste complète ici
				b.view:showEmpty("None of your friends are in this top yet")
			else
				b.view:render(out)
			end
		else
			-- 🔍 FIND ME alors que tu n'es pas dans le top : ta ligne « -- » sous le dernier
			local me = LocalPlayer and LocalPlayer.UserId
			local inList = false
			if b.meExtra and me then
				for _, e in ipairs(ctx.data) do if e.userId == me then inList = true break end end
			end
			if b.meExtra and me and not inList then
				local out = table.clone(ctx.data)
				local v = friendVals[me]
				table.insert(out, { userId = me, name = LocalPlayer.DisplayName, [cfg.valueKey] = v or 0,
					noRank = true, pending = (v == nil) and BOARD_KEY ~= nil, _ord = 1, rank = 9999 })
				out.extra = 1
				b.view:render(out)
			else
				b.view:render(ctx.data)
			end
		end
		updateYou(b)
	end

	local function pushToBoards()
		for _, b in ipairs(ctx.boards) do
			if b.scroll and b.scroll.Parent then
				if b.loader then b.loader:Destroy(); b.loader = nil end
				if MODERN or TABS then renderBoard(b) else b.view:render(ctx.data) end
			end
		end
	end

	-- 🔍 FIND ME : fait défiler jusqu'à ta ligne et la fait clignoter.
	--    Pas dans le top ? Un message le dit, ta ligne « -- » est ajoutée SOUS le dernier avec ton
	--    score (lu dans le même classement), et on descend jusqu'à elle : tu vois l'écart avec le dernier.
	local FIND_GLOW = { base = {0.45, 0.62, 0.78}, amp = {0.35, 0.25, 0.15}, speed = 7 }
	local myValAt, myValBusy = -1e9, false
	local function fetchMine(done)
		local me = LocalPlayer and LocalPlayer.UserId
		if not BOARD_KEY or not me then return end
		if friendVals[me] ~= nil and os.clock() - myValAt < 60 then return end
		if myValBusy then return end
		local fn = ReplicatedStorage:FindFirstChild("GetFriendsBoardValues")
		if not fn then return end
		myValBusy = true
		task.spawn(function()
			for _ = 1, 2 do
				local ok, r = pcall(function() return fn:InvokeServer(BOARD_KEY, { me }) end)
				if ok and type(r) == "table" and not r.throttled then
					local v = r[tostring(me)]
					if type(v) == "number" then friendVals[me] = v ; myValAt = os.clock() end
					break
				end
				task.wait(3.2)
			end
			myValBusy = false
			done()
		end)
	end
	local function toast(b, text)
		local host = b.content or b.main
		if not (host and host.Parent) then return end
		local old = host:FindFirstChild("FindMeToast")
		if old then old:Destroy() end
		local t = Instance.new("TextLabel")
		t.Name = "FindMeToast"
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.new(0.5, 0, 0.02, 0)
		t.Size = UDim2.new(0.9, 0, 0.075, 0)
		t.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		t.BackgroundTransparency = 0.15
		t.BorderSizePixel = 0
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Text = text
		t.ZIndex = 50
		t.Parent = host
		Instance.new("UICorner", t).CornerRadius = UDim.new(1, 0)
		local c = Instance.new("UITextSizeConstraint", t) ; c.MaxTextSize = 30
		local pd = Instance.new("UIPadding", t) ; pd.PaddingTop = UDim.new(0.18, 0) ; pd.PaddingBottom = UDim.new(0.18, 0)
		local st = Instance.new("UIStroke") ; st.Color = ME_COLOR ; st.Thickness = 2 ; st.Transparency = 0.2 ; st.Parent = t
		task.delay(3.2, function()
			if not t.Parent then return end
			TweenService:Create(t, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			TweenService:Create(st, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			task.delay(0.45, function() if t.Parent then t:Destroy() end end)
		end)
	end
	local function scrollToMe(b)
		local me = LocalPlayer and LocalPlayer.UserId
		for _, E in ipairs(b.view.entries) do
			if E.data and E.data.userId == me and E.holder.Parent then
				local sc = b.scroll
				local y = E.holder.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y
				local maxY = math.max(0, sc.AbsoluteCanvasSize.Y - sc.AbsoluteWindowSize.Y)
				local target = math.clamp(y - (sc.AbsoluteWindowSize.Y - E.holder.AbsoluteSize.Y) / 2, 0, maxY)
				TweenService:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ CanvasPosition = Vector2.new(0, target) }):Play()
				E.glowState.preset, E.glowState.color = FIND_GLOW, ME_COLOR
				task.delay(2.5, function()
					if E.data and E.data.userId == me then
						E.glowState.preset, E.glowState.color = SELF_GLOW, SELF_BLUE
					end
				end)
				return true
			end
		end
		return false
	end
	local function findMe(b)
		if scrollToMe(b) then return end
		if b.filter == "all" and TABS and ctx.data and LocalPlayer then
			toast(b, string.format("You're not in the top %d yet — your score is at the bottom",
				math.min(#ctx.data, cfg.topSize)))
			b.meExtra = true
			renderBoard(b)
			fetchMine(function()
				if b.meExtra and b.filter == "all" and b.scroll.Parent then renderBoard(b) end
			end)
			task.spawn(function()
				-- deux images : le temps que la nouvelle ligne soit placée par le UIListLayout
				RunService.Heartbeat:Wait() ; RunService.Heartbeat:Wait()
				if b.scroll.Parent then scrollToMe(b) end
			end)
			return
		end
		-- pas dans la liste : ta ligne en bas clignote (elle dit où tu en es)
		if b.youRow and b.youRow.Parent then
			local base = MODERN_PALETTE.entry
			b.youRow.BackgroundColor3 = Color3.fromRGB(90, 76, 30)
			TweenService:Create(b.youRow, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ BackgroundColor3 = base }):Play()
		end
	end

	local function applyServerData(raw)
		if not raw or #raw == 0 then return end
		fetchVip()
		ctx.data        = dedupe(raw)
		ctx.stamp       = ctx.stamp + 1
		ctx.lastRefresh = os.clock()
		pushToBoards()
	end
	ctx.applyServerData = applyServerData

	----------------------------------------------------------------
	-- UN SEUL fetch pour tous les boards (C : moins de trafic remote)
	----------------------------------------------------------------
	local function refreshAll()
		if ctx.isRefreshing then return end
		ctx.isRefreshing = true
		ctx.lastRefresh  = os.clock()

		task.spawn(function()
			fetchVip()

			local data
			for _ = 1, 5 do
				if getFunc then
					local ok, res = pcall(function() return getFunc:InvokeServer() end)
					if ok and res and #res > 0 then data = res break end
				end
				task.wait(2)
			end

			ctx.isRefreshing = false

			if data then
				ctx.data        = dedupe(data)
				ctx.stamp       = ctx.stamp + 1
				ctx.lastRefresh = os.clock()
				pushToBoards()
			else
				-- pas encore de données côté serveur : nouvel essai dans 5s
				ctx.lastRefresh = os.clock() - cfg.refreshDelay + 5
				for _, b in ipairs(ctx.boards) do
					if b.loader then b.loader:Destroy(); b.loader = nil end
					if not ctx.data then b.view:showEmpty(cfg.emptyText) end
				end
			end
		end)
	end
	ctx.refreshAll = refreshAll

	----------------------------------------------------------------
	-- countdown (un seul thread pour tous les boards)
	----------------------------------------------------------------
	task.spawn(function()
		local BAR_TWEEN = TweenInfo.new(1, Enum.EasingStyle.Linear)
		while true do
			task.wait(1)
			local txt, col
			local rem = math.max(0, math.floor(ctx.lastRefresh + cfg.refreshDelay - os.clock()))
			if ctx.isRefreshing then
				txt = MODERN and "UPDATING…" or "Refreshing..."
				col = cfg.palette.accent2 or cfg.palette.accent1
			else
				if rem == 0 then
					txt = MODERN and "UPDATING SOON…" or "Refreshing soon..."
					col = cfg.palette.accent1
				else
					txt = string.format(MODERN and "NEXT UPDATE  %d:%02d" or "Refresh in %d:%02d", math.floor(rem / 60), rem % 60)
					col = (rem <= 15) and cfg.palette.accent1 or cfg.palette.muted
				end
			end
			local frac = math.clamp(1 - rem / math.max(1, cfg.refreshDelay), 0, 1)
			for _, b in ipairs(ctx.boards) do
				if b.refreshLbl and b.refreshLbl.Parent then
					b.refreshLbl.Text       = txt
					b.refreshLbl.TextColor3 = col
				end
				if b.barFill and b.barFill.Parent then
					if frac < (b.lastFrac or 0) then
						b.barFill.Size = UDim2.new(frac, 0, 1, 0)   -- nouveau cycle : repart à zéro net
					else
						TweenService:Create(b.barFill, BAR_TWEEN, { Size = UDim2.new(frac, 0, 1, 0) }):Play()
					end
					b.lastFrac = frac
				end
			end
		end
	end)

	----------------------------------------------------------------
	-- boucle d'auto-refresh + nettoyage des boards détruits
	-- (C : le bug de fuite mémoire au swap de map)
	----------------------------------------------------------------
	task.spawn(function()
		while true do
			task.wait(1)
			for i = #ctx.boards, 1, -1 do
				local b = ctx.boards[i]
				if not (b.surfaceGui and b.surfaceGui.Parent and b.scroll and b.scroll.Parent
					and b.part and b.part:IsDescendantOf(Workspace)) then
					b.view:destroy()
					-- la copie cliquable vit dans le PlayerGui : on la retire aussi
					if b.surfaceGui and b.surfaceGui ~= b.src then b.surfaceGui:Destroy() end
					table.remove(ctx.boards, i)
				end
			end
			if #ctx.boards > 0 and not ctx.isRefreshing then
				if (os.clock() - ctx.lastRefresh) >= cfg.refreshDelay then
					refreshAll()
				end
			end
		end
	end)

	----------------------------------------------------------------
	-- événement serveur
	----------------------------------------------------------------
	if updEvt then
		updEvt.OnClientEvent:Connect(function(newData)
			applyServerData(newData)
		end)
	end

	----------------------------------------------------------------
	-- détection / init des boards
	----------------------------------------------------------------
	local nameSet = {}
	for _, n in ipairs(cfg.boardNames or {}) do nameSet[n] = true end

	local function isBoard(part)
		return part:IsA("BasePart") and nameSet[part.Name] == true
	end

	local function initBoard(part)
		local src = part:FindFirstChildOfClass("SurfaceGui")
		if not src then return end
		for _, b in ipairs(ctx.boards) do
			if b.part == part then return end
		end

		local sg = src
		if INTERACTIVE then
			-- 🖱️ Une SurfaceGui posée dans le Workspace ne reçoit NI survol NI
			--    clic. On l'affiche donc depuis le PlayerGui, collée au même part
			--    (Adornee), et on éteint l'originale. Même rendu, mais cliquable.
			sg = Instance.new("SurfaceGui")
			sg.Name             = "LB_" .. part.Name
			sg.Face             = src.Face
			sg.SizingMode       = src.SizingMode
			sg.PixelsPerStud    = src.PixelsPerStud
			sg.AlwaysOnTop      = src.AlwaysOnTop
			sg.ZOffset          = src.ZOffset
			sg.MaxDistance      = src.MaxDistance
			sg.ClipsDescendants = src.ClipsDescendants
			sg.ResetOnSpawn     = false
			sg.Adornee          = part
			sg.Parent           = LocalPlayer:WaitForChild("PlayerGui")
			src.Enabled         = false
		end

		sg.CanvasSize      = Vector2.new(1920, 1080)
		sg.LightInfluence  = 0
		sg.Brightness      = 1
		sg.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling

		local ui = (MODERN and buildBoardUIModern or buildBoardUI)(cfg, sg)
		local b = {
			part       = part,
			src        = src,
			surfaceGui = sg,
			main       = ui.main,
			content    = ui.content,
			scroll     = ui.scroll,
			footer     = ui.footer,
			refreshLbl = ui.refreshLbl,
			loader     = nil,
			-- 🏆 style moderne
			filter     = "all",
			youRow     = ui.youRow,
			youLbl     = ui.youLbl,
			barFill    = ui.barFill,
		}
		b.view = Core.newListView(ui.scroll, cfg)
		b.view.useDataRank = MODERN or TABS
		table.insert(ctx.boards, b)

		if ui.tabs then
			local t = ui.tabs
			local function paint()
				if t.setSelected then t.setSelected(b.filter) return end   -- look d'avant
				t.allColor(b.filter == "all" and BTN.blue or BTN.grey)
				t.friendsColor(b.filter == "friends" and BTN.blue or BTN.grey)
			end
			t.all.Activated:Connect(function()
				if b.filter == "all" then return end
				b.filter = "all" ; b.meExtra = nil ; paint()
				b.scroll.CanvasPosition = Vector2.zero
				renderBoard(b)
			end)
			t.friends.Activated:Connect(function()
				if b.filter == "friends" then return end
				b.filter = "friends" ; b.meExtra = nil ; paint()
				b.scroll.CanvasPosition = Vector2.zero
				t.frL.Text = "…"
				withFriends(function()
					t.frL.Text = t.friendsText or "FRIENDS"
					if b.filter == "friends" and b.scroll.Parent then renderBoard(b) end
				end)
			end)
			t.findMe.Activated:Connect(function() findMe(b) end)
		end

		if cfg.onBoardBuilt then
			pcall(cfg.onBoardBuilt, b, ctx)
		end

		if ctx.data then
			if MODERN or TABS then renderBoard(b) else b.view:render(ctx.data) end   -- board ajouté en cours de partie
		else
			b.loader = createLoader(ui.content, cfg)
			task.delay(cfg.firstLoadDelay, function()
				if not b.scroll.Parent then return end
				if not ctx.data then refreshAll() end
			end)
		end
	end
	ctx.initBoard = initBoard

	task.spawn(function()
		task.wait(2)
		for _, d in ipairs(Workspace:GetDescendants()) do
			if isBoard(d) then initBoard(d) end
		end
	end)

	Workspace.DescendantAdded:Connect(function(d)
		if isBoard(d) then
			task.wait(0.3)
			initBoard(d)
		end
	end)

	return ctx
end

return Core