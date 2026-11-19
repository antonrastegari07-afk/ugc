--════════════════════════════════════════════════════════════════════════════
-- 📐 HudLayout — ModuleScript dans ReplicatedStorage   (NOUVEAU, v2)
--
--  Les boutons de l'écran (les 8 à gauche + Skip Obby / Current Stage / Skip Level +
--  la roulette) gardent EXACTEMENT ta disposition sur tous les formats d'écran, et le
--  bloc du haut ne touche jamais les boutons du haut (Roblox, ⚙️, How To Play, série).
--
--  POURQUOI ILS SE DÉCOLLAIENT : position en % de la LARGEUR de l'écran mais taille
--  (UIAspectRatioConstraint) qui suivait la HAUTEUR, et des animations de survol qui
--  re-forçaient leur propre position (une valeur PC, une autre mobile).
--
--  v2 — FIABLE :
--   • ta disposition est écrite ICI (calculée depuis tes valeurs Studio, écran 16:9 de
--     1920×1080) : le script ne relit plus rien en jeu, donc aucun autre script, aucun
--     chargement, aucun état caché ne peut fausser le calcul ;
--   • TOUT (tailles ET écarts) suit la hauteur de l'écran → même disposition partout ;
--   • le bloc du haut évite les boutons du haut MESURÉS (seulement de vrais boutons,
--     de taille normale) + les icônes Roblox ; s'il manque de place il se décale, puis
--     rétrécit (jamais sous 75 %), puis passe juste EN DESSOUS de ces boutons ;
--   • si un autre script déplace un de ces boutons, il est remis à sa place.
--
--  ✏️ Tu déplaces un bouton dans Studio ? Mets sa nouvelle place ici (x, y = coin haut-
--     gauche, w, h = taille, en pixels d'un écran 1920×1080).
--  ↩️ REVENIR À AVANT : Enabled = false.
--════════════════════════════════════════════════════════════════════════════
local TweenService = game:GetService("TweenService")

local M = {}

M.Enabled = true
M.Debug   = false   -- true = écrit dans l'Output la place calculée de chaque bouton

M.REF_W, M.REF_H = 1920, 1080

M.Groups = {
	left = {
		anchor = "left",
		maxWidth = 0.42,   -- jamais plus de 42 % de la largeur de l'écran
		items = {
			{ gui = "Bouton hide", frame = "Frame",       x = 131,  y = 193, w = 90,  h = 41  },  -- Hide Gui
			{ gui = "UGCshop",     frame = "Frame",       x = 38,   y = 260, w = 271, h = 146 },  -- UGC Shop
			{ gui = "Shop",        frame = "Frame",       x = 48,   y = 419, w = 121, h = 120 },
			{ gui = "PointsShop",  frame = "Frame",       x = 182,  y = 419, w = 121, h = 120 },
			{ gui = "Rebirth",     frame = "Frame",       x = 48,   y = 548, w = 121, h = 120 },
			{ gui = "Quest",       frame = "Frame",       x = 182,  y = 548, w = 121, h = 120 },
			{ gui = "Daily tool",  frame = "open button", x = 115,  y = 673, w = 120, h = 120 },  -- Rewards
			{ gui = "invites",     frame = "Frame",       x = 102,  y = 930, w = 152, h = 74  },  -- Invite
		},
	},
	top = {
		anchor = "center",
		maxWidth = 0.92,
		avoidTopButtons = true,
		minScale = 0.75,   -- jamais plus petit ; sinon le bloc passe sous les boutons du haut
		items = {
			{ gui = "Skip Obby",  frame = "Frameskiplevel", x = 659,  y = 54, w = 138, h = 67  },
			{ gui = "# Stage",    frame = "Frame",          x = 818,  y = 37, w = 276, h = 101 },  -- Current Stage
			{ gui = "Skip Level", frame = "Frameskiplevel", x = 1110, y = 53, w = 148, h = 71  },
			{ gui = "dailyspin",  frame = "Frame",          x = 1340, y = 26, w = 168, h = 166 },  -- 🎡 roulette
		},
		-- (pas « # Stage ▸ Frame2 » : ArenaHUD la cache hors de l'écran et la remplace)
	},
}

-- 🚧 boutons du haut à éviter (en plus des icônes Roblox) : ScreenGui créés par tes scripts
M.TopButtonGuis = { "TopBarGui" }   -- ⚙️ + How To Play + série de jours
M.RobloxIconsWidth = { pc = 170, touch = 120 }   -- place des icônes Roblox en haut à gauche (px)
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
		frame:SetAttribute("HudAnimUntil", os.clock() + 0.35)   -- la mise en page laisse l'animation jouer
		TweenService:Create(frame, HOVER_INFO, { Size = ns, Position = np }):Play()
	end
	button.MouseEnter:Connect(function() to(0.9) end)
	button.MouseLeave:Connect(function() to(1) end)
	button.MouseButton1Down:Connect(function() to(0.85) end)
	button.MouseButton1Up:Connect(function() to(0.9) end)
end

return M
