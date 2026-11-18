--════════════════════════════════════════════════════════════════════════════
-- 🏆 LeaderboardStyle — ModuleScript dans ReplicatedStorage   (NOUVEAU)
--
--  Apparence des leaderboards physiques (Points, Kills, Rebirths, Streak, Dons).
--
--   Style = "modern"  → nouveau look (même style que les Paramètres et le CombatHUD :
--                       panneau sombre, police BuilderSans, boutons 3D) + onglets
--                       ALL / FRIENDS / FIND ME, ta ligne en bas, barre « next update ».
--   Style = "classic" → EXACTEMENT l'apparence d'avant (rien d'autre ne change).
--
--  Les options ci-dessous ne servent qu'en mode "modern".
--════════════════════════════════════════════════════════════════════════════
return {
	Style = "modern",      -- "modern" | "classic"

	Tabs      = true,      -- onglets ALL / FRIENDS + bouton FIND ME
	YourRow   = true,      -- ta place (et ton score) toujours visible en bas du board
	UpdateBar = true,      -- fine barre qui se remplit jusqu'à la prochaine mise à jour

	-- 👥 la liste d'amis est lue UNE fois, puis gardée en mémoire ce temps-là (s)
	FriendsCacheSeconds = 600,
}
