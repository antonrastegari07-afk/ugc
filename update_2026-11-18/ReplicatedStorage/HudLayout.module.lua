--════════════════════════════════════════════════════════════════════════════
-- 📐 HudLayout — ModuleScript dans ReplicatedStorage   (NOUVEAU)
--
--  Les boutons de l'écran (les 8 à gauche + Skip Obby / Current Stage / Skip Level + la roulette)
--  gardent EXACTEMENT leur disposition, quel que soit le format de l'écran
--  (PC large, 16:9, 16:10, tablette 4:3, téléphone…).
--
--  POURQUOI ILS SE DÉCOLLAIENT : leur position était en % de la LARGEUR de l'écran
--  alors que leur taille (bloquée par UIAspectRatioConstraint) suivait la HAUTEUR.
--  Sur un écran plus large, les écarts grandissaient ; plus étroit, ils se
--  rapprochaient. En plus, chaque animation de survol re-forçait sa propre
--  position (une valeur PC, une autre mobile).
--
--  COMMENT : ta disposition actuelle (comme sur un écran 16:9) est relue au
--  démarrage, puis TOUT (tailles ET écarts) est recalculé à partir de la hauteur
--  de l'écran. Le bloc de gauche reste collé au bord gauche, le trio du haut
--  reste centré. Si un bloc ne tient plus en largeur, il rétrécit en entier
--  (jamais de chevauchement). Recalcul seulement quand la taille de l'écran
--  change : aucun coût en jeu. Les animations de survol partent de la bonne place.
--
--  ↩️ REVENIR À AVANT : Enabled = false.
--════════════════════════════════════════════════════════════════════════════
local TweenService = game:GetService("TweenService")

local M = {}

M.Enabled = true

-- 🧱 Les blocs. x = position horizontale « PC » de ta disposition (en % d'un écran 16:9).
--    nil = on garde celle de Studio. Tailles et hauteurs : celles de Studio.
M.Groups = {
	left = {
		anchor = "left",
		maxWidth = 0.42,   -- jamais plus de 42 % de la largeur de l'écran
		items = {
			{ gui = "Bouton hide", frame = "Frame",       x = 0.068 },  -- Hide Gui
			{ gui = "UGCshop",     frame = "Frame",       x = 0.020 },  -- UGC Shop
			{ gui = "Shop",        frame = "Frame",       x = 0.025 },
			{ gui = "PointsShop",  frame = "Frame",       x = 0.095 },
			{ gui = "Rebirth",     frame = "Frame",       x = 0.025 },
			{ gui = "Quest",       frame = "Frame",       x = 0.095 },
			{ gui = "Daily tool",  frame = "open button", x = 0.060 },  -- Rewards
			{ gui = "invites",     frame = "Frame" },                    -- Invite
		},
	},
	top = {
		anchor = "center",
		maxWidth = 0.92,
		-- 🚧 le bloc du haut ne touche JAMAIS les boutons du haut de l'écran : ceux de Roblox et
		--    tes boutons How To Play / série de jours (à gauche sur PC, à droite sur mobile).
		--    Leur place est MESURÉE en direct : il s'écarte ou rétrécit selon l'appareil.
		avoidTopButtons = true,
		items = {
			{ gui = "Skip Obby",  frame = "Frameskiplevel" },
			{ gui = "# Stage",    frame = "Frame" },    -- Current Stage
			-- (pas « # Stage ▸ Frame2 » : ArenaHUD la cache hors de l'écran et la remplace)
			{ gui = "Skip Level", frame = "Frameskiplevel" },
			{ gui = "dailyspin",  frame = "Frame" },    -- 🎡 la roulette (à droite de Skip Level)
		},
	},
}

-- écran de référence de ta disposition
M.REF_W, M.REF_H = 1920, 1080

-- boutons du haut à éviter (en plus de ceux de Roblox) : ScreenGui créés par tes scripts
M.TopButtonGuis = { "TopBarGui" }   -- How To Play + série de jours
M.TopGap = 10                        -- écart minimum avec eux (px)

-- 🖱️ Animation de survol (la même qu'avant : 90 % au survol, 85 % à l'appui),
--    toujours calculée à partir de la place donnée par la mise en page.
local HOVER_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
function M.Hover(button, frame)
	local origSize, origPos = frame.Size, frame.Position
	local function base()
		local s, p = frame:GetAttribute("HudBaseSize"), frame:GetAttribute("HudBasePos")
		if typeof(s) == "UDim2" and typeof(p) == "UDim2" then return s, p end
		return origSize, origPos
	end
	local function to(k)
		local s, p = base()
		local ns = UDim2.new(s.X.Scale * k, s.X.Offset * k, s.Y.Scale * k, s.Y.Offset * k)
		local a = frame.AnchorPoint
		local np = UDim2.new(
			p.X.Scale + s.X.Scale * (1 - k) * (0.5 - a.X), p.X.Offset + s.X.Offset * (1 - k) * (0.5 - a.X),
			p.Y.Scale + s.Y.Scale * (1 - k) * (0.5 - a.Y), p.Y.Offset + s.Y.Offset * (1 - k) * (0.5 - a.Y))
		TweenService:Create(frame, HOVER_INFO, { Size = ns, Position = np }):Play()
	end
	button.MouseEnter:Connect(function() to(0.9) end)
	button.MouseLeave:Connect(function() to(1) end)
	button.MouseButton1Down:Connect(function() to(0.85) end)
	button.MouseButton1Up:Connect(function() to(0.9) end)
end

return M
