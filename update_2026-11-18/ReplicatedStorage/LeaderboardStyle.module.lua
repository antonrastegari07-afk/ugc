--════════════════════════════════════════════════════════════════════════════
-- 🏆 LeaderboardStyle — ModuleScript dans ReplicatedStorage   (NOUVEAU)
--
--  Réglages des leaderboards physiques (Points, Kills, Rebirths, Streak, Dons).
--
--   Style = "classic" → l'apparence d'AVANT (par défaut).
--   Style = "modern"  → look Paramètres / CombatHUD (essai précédent), avec en plus
--                       ta ligne et la barre « next update » en bas (YourRow / UpdateBar).
--
--   Tabs = true  → dans l'en-tête : ALL / FRIENDS à gauche, petite loupe 🔍 (FIND ME)
--                  à droite. FRIENDS montre TOUS tes amis : ceux du top avec leur
--                  place, les autres en dessous avec « -- ».
--   Tabs = false → EXACTEMENT les boards d'avant, sans aucun bouton.
--════════════════════════════════════════════════════════════════════════════
return {
	Style = "classic",     -- "classic" | "modern"
	Tabs  = true,          -- ALL / FRIENDS / 🔍 FIND ME

	-- seulement pour Style = "modern"
	YourRow   = false,
	UpdateBar = false,

	-- 👥 la liste d'amis est lue UNE fois, puis gardée en mémoire ce temps-là (s)
	FriendsCacheSeconds = 600,
}
