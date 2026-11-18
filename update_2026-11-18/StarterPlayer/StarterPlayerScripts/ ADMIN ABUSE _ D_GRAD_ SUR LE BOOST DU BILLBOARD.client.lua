--════════════════════════════════════════════════════════════════════════════
--
--   🌈  ADMIN ABUSE — DÉGRADÉ SUR LE BOOST DU BILLBOARD
--   📍  StarterPlayer ▸ StarterPlayerScripts ▸ LocalScript
--
--   ┌──────────────────────────────────────────────────────────────────────┐
--   │  POURQUOI UN SCRIPT À PART PLUTÔT QU'UNE MODIFICATION DE            │
--   │  HeadBillboardsClient ?                                              │
--   │                                                                      │
--   │  Parce que ce fichier-là marche, qu'il est gros, et qu'il gère déjà  │
--   │  un cycle de vie délicat (le serveur DÉTRUIT et recrée TempsGui à    │
--   │  chaque respawn). Y greffer une deuxième logique, c'est risquer de   │
--   │  casser un effet qui fonctionne pour en ajouter un temporaire.       │
--   │                                                                      │
--   │  Ce script-ci se pose à côté, écoute UNE seule chose — l'attribut    │
--   │  AAEventBoost posé par le serveur d'événement — et se retire tout    │
--   │  seul. Si tu supprimes ce fichier, tout le reste continue comme      │
--   │  avant, à l'octet près.                                              │
--   └──────────────────────────────────────────────────────────────────────┘
--
--   L'effet : un dégradé multicolore qui GLISSE sur le texte du boost, pour
--   que le joueur voie d'un coup d'œil que son multiplicateur est dopé par
--   l'admin — et pas seulement plus grand.
--
--   ⚠️ Une instance ne peut porter qu'UN SEUL UIGradient. Le label de boost
--      en a peut-être déjà un (style VIP). On ne le remplace donc PAS : on
--      pose un TextLabel JUMEAU par-dessus, transparent, qui affiche le même
--      texte et porte notre dégradé. Sur un TextLabel, un UIGradient ne
--      colore que les GLYPHES — pas de rectangle, pas de débordement.
--
--════════════════════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local LAYER_NAME = "AABoostRainbow"
local SPEED      = 1.45      -- tours par seconde du dégradé
local ATTR       = "AAEventBoost"

-- 🆕 Arc-en-ciel aussi pour TOUT boost de points temporaire (pas seulement l'Admin Abuse) :
--    boosts achetés, gagnés à la roue, offerts… → attribut TempBoostMult posé par le
--    serveur « boost temporaire » (répliqué à tout le monde, impossible à fausser côté client).
--    false = comportement d'avant (Admin Abuse seulement).
local ANY_TEMP_BOOST = true
local TEMP_ATTR      = "TempBoostMult"

--  Palette : celle du Config si présent, sinon une copie de secours. Ce
--  script doit pouvoir vivre même si le module n'est pas encore répliqué.
local RAINBOW
do
	local kp, src = {}, nil
	local mod = ReplicatedStorage:FindFirstChild("AdminAbuse_Config")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" and type(res.RAINBOW) == "table" then
			src = res.RAINBOW
		end
	end
	src = src or {
		{ 0.00, 255,  80,  80 }, { 0.17, 255, 190,  60 }, { 0.34, 250, 255,  90 },
		{ 0.50,  90, 255, 140 }, { 0.67,  90, 200, 255 }, { 0.84, 180, 130, 255 },
		{ 1.00, 255,  80,  80 },
	}
	for _, p in ipairs(src) do
		kp[#kp + 1] = ColorSequenceKeypoint.new(p[1], Color3.fromRGB(p[2], p[3], p[4]))
	end
	RAINBOW = ColorSequence.new(kp)
end

--══════════════════════════════════════════════════════════════════════════════
-- 🎞️ UNE SEULE BOUCLE POUR TOUS LES DÉGRADÉS
--══════════════════════════════════════════════════════════════════════════════
local live = {}   -- [UIGradient] = true

RunService.RenderStepped:Connect(function()
	local off = Vector2.new((os.clock() * SPEED) % 2 - 1, 0)
	for g in pairs(live) do
		if g:IsDescendantOf(game) then
			g.Offset = off
		else
			live[g] = nil
		end
	end
end)

--══════════════════════════════════════════════════════════════════════════════
-- 🔎 TROUVER LE LABEL DE BOOST
--    Chemin exact posé par ton script serveur de billboards :
--        Head ▸ TempsGui ▸ Frame ▸ BoostLabel
--══════════════════════════════════════════════════════════════════════════════
local function boostLabel(character)
	if not character then return nil end
	local head = character:FindFirstChild("Head")
	if not head then return nil end
	local gui = head:FindFirstChild("TempsGui")
	if not gui then return nil end
	local frame = gui:FindFirstChild("Frame")
	if not frame then return nil end
	local lbl = frame:FindFirstChild("BoostLabel")
	if lbl and lbl:IsA("TextLabel") then return lbl end
	return nil
end

local function removeLayer(lbl)
	if not lbl then return end
	local old = lbl:FindFirstChild(LAYER_NAME)
	while old do
		old:Destroy()
		old = lbl:FindFirstChild(LAYER_NAME)
	end
end

--  Les quatre garanties « le reflet ne déborde pas des lettres », reprises
--  telles quelles de ton HeadBillboardsClient :
--    1. BackgroundTransparency = 1 → aucune surface derrière le texte.
--    2. TextStrokeTransparency = 1 et aucun UIStroke → le dégradé ne bave
--       pas sur le contour, qui est plus large que le glyphe.
--    3. Font / TextScaled / TextSize / alignements recopiés → superposition
--       au pixel près, pas de texte fantôme dédoublé.
--    4. Un seul calque possible : on détruit l'ancien avant d'en poser un.
local function addLayer(lbl)
	if not lbl then return end
	if lbl:FindFirstChild(LAYER_NAME) then return end
	removeLayer(lbl)

	local twin = Instance.new("TextLabel")
	twin.Name                   = LAYER_NAME
	twin.BackgroundTransparency = 1
	twin.Size                   = UDim2.fromScale(1, 1)
	twin.Position               = UDim2.fromScale(0, 0)
	twin.Font                   = lbl.Font
	twin.TextScaled             = lbl.TextScaled
	if not lbl.TextScaled then twin.TextSize = lbl.TextSize end
	twin.TextXAlignment         = lbl.TextXAlignment
	twin.TextYAlignment         = lbl.TextYAlignment
	twin.TextColor3             = Color3.fromRGB(255, 255, 255)
	twin.TextStrokeTransparency = 1
	twin.TextTransparency       = 0
	twin.Text                   = lbl.Text
	twin.ZIndex                 = lbl.ZIndex + 2
	twin.Parent                 = lbl

	--  Le montant du boost change côté serveur : on recopie à chaque fois.
	local conn = lbl:GetPropertyChangedSignal("Text"):Connect(function()
		if twin.Parent then twin.Text = lbl.Text else return end
	end)
	twin.Destroying:Connect(function()
		if conn then conn:Disconnect() end
	end)

	local g = Instance.new("UIGradient")
	g.Color  = RAINBOW
	g.Parent = twin
	live[g]  = true
end

--══════════════════════════════════════════════════════════════════════════════
-- 👤 SUIVI D'UN JOUEUR
--    L'attribut AAEventBoost est posé par le SERVEUR sur l'objet Player : il
--    est donc répliqué à tout le monde, et tous les joueurs voient le boost
--    de celui qui l'a. Le client ne peut pas se le donner : un attribut posé
--    côté client ne part jamais vers le serveur ni vers les autres.
--══════════════════════════════════════════════════════════════════════════════
local function refresh(plr)
	local ch = plr.Character
	if not ch then return end
	local lbl = boostLabel(ch)
	if not lbl then return end
	local b = tonumber(plr:GetAttribute(ATTR)) or 0
	local t = ANY_TEMP_BOOST and (tonumber(plr:GetAttribute(TEMP_ATTR)) or 0) or 0
	if b > 0 or t > 0 then addLayer(lbl) else removeLayer(lbl) end
end

local function watchCharacter(plr, ch)
	if not ch then return end
	task.spawn(function()
		local head = ch:FindFirstChild("Head") or ch:WaitForChild("Head", 15)
		if not head then return end

		--  Ton script serveur DÉTRUIT puis recrée TempsGui (respawn, changement
		--  de style…). On ne devine pas : on écoute l'arrivée du nouveau.
		head.ChildAdded:Connect(function(child)
			if child.Name ~= "TempsGui" then return end
			task.delay(0.25, function()
				if plr.Character == ch then refresh(plr) end
			end)
		end)

		--  Première pose : on laisse au serveur le temps de construire.
		for _ = 1, 20 do
			if plr.Character ~= ch then return end
			if boostLabel(ch) then refresh(plr) return end
			task.wait(0.5)
		end
	end)
end

local function watch(plr)
	plr:GetAttributeChangedSignal(ATTR):Connect(function()
		pcall(refresh, plr)
	end)
	if ANY_TEMP_BOOST then
		plr:GetAttributeChangedSignal(TEMP_ATTR):Connect(function()
			pcall(refresh, plr)
		end)
	end
	plr.CharacterAdded:Connect(function(ch)
		watchCharacter(plr, ch)
	end)
	if plr.Character then watchCharacter(plr, plr.Character) end
end

for _, p in ipairs(Players:GetPlayers()) do
	pcall(watch, p)
end
Players.PlayerAdded:Connect(function(p)
	pcall(watch, p)
end)