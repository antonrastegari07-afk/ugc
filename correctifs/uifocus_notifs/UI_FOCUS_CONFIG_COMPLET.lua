-- ModuleScript : StarterGui > UIFocusSystem > UI_FOCUS_CONFIG
-- Les modifications dans Studio s'appliquent au prochain lancement du jeu.
local C = {}

C.Enabled = true
C.HideOtherScreenGuis = true
C.HideLaunchersInActiveGui = true

-- Exceptions normales. Noms exacts, espaces compris.
-- Une interface déjà désactivée n'est pas rallumée par cette liste.
C.KeepScreenGuis = { "Offers" }

-- Toujours autorisées, y compris pendant le Rookie Guide.
-- On respecte Enabled : une animation arrêtée ne sera jamais rallumée.
-- Leur DisplayOrder d'origine les place déjà au-dessus des menus.
-- LoadingScreen = l'écran noir du loader : le How to Play s'ouvre DESSOUS pendant
-- qu'il est encore noir (anti-flash), il ne doit donc jamais être caché par le focus.
C.AlwaysKeepScreenGuis = { "CoinRewardGui", "RobuxPromptFX", "LoadingScreen" }

-- 🔔 NOTIFICATIONS : jamais cachées quand une fenêtre est ouverte, et affichées
--    AU-DESSUS d'elle (achat réussi, UGC, récompenses, messages d'event…).
--    En plus de ces deux listes, toute interface créée ou allumée PENDANT
--    qu'une fenêtre est ouverte est traitée comme une notification.
-- 1) Noms exacts (ceux que les mots-clés ci-dessous ne couvrent pas)
C.NotificationScreenGuis = {
	"CoinRewardGui", "ReferralRewardGui", "AdminAbuseGui", "RebirthCooldownGui",
	"AntiFlyTPGui", "ServerBrowserOverlay", "DamagePopupContainer",
}
-- 2) Mots-clés : une interface dont le nom CONTIENT un de ces mots (majuscules
--    ignorées) est une notification. Couvre aussi les futures notifs.
C.NotificationNamePatterns = {
	"notif", "toast", "popup", "error", "result", "confirm", "warning", "notice",
	"message", "alert", "banner", "announce", "verifying", "frozen", "restricted",
	"collected", "countdown", "intermission", "vote", "subtitle", "flash", "fade",
	"tutorial", "dialog", "deathcam", "killfx", "headshot", "hitdirection", "killfeed",
}

C.Blur = {
	Enabled = true,
	Size = 18,          -- même intensité que ton UI Halloween (0 à 56)
	OpenTime = 0.30,
	CloseTime = 0.20,
}

C.Zoom = {
	Enabled = true,
	FOVOffset = -10,    -- négatif = rapproche le décor ; 0 = aucun zoom
	MinFOV = 20,
	MaxFOV = 110,
	OpenTime = 0.30,
	CloseTime = 0.20,
}

-- Comme Halloween : cache aussi ces éléments Roblox, puis les restaure.
-- Le menu système Roblox n'est pas désactivé.
C.CoreGui = {
	Enabled = true,
	Types = { "Backpack", "PlayerList", "EmotesMenu", "Health" },
}

C.RefreshInterval = 0.25 -- contrôle léger des chemins dans les ScreenGui connus
C.Debug = false         -- écrit les changements de fenêtre dans Output

-- Trigger = "Enabled" : le ScreenGui entier est la fenêtre.
-- Trigger = "Visible" : Path désigne LA fenêtre, pas le bouton qui l'ouvre.
-- Path est relatif au ScreenGui. Exemple : { "Container", "MainFrame" }.
-- KeepWholeGui garde le fond noir / overlay frère de la fenêtre.
-- Sinon, les autres branches du même ScreenGui sont masquées.
-- Enabled = false permet de retirer un menu de la détection.
-- Réglages optionnels par menu : BlurSize = 8, FOVOffset = -5.
-- HideMode = "Contents" : quand un autre menu prend le focus, masque les
-- racines visuelles sans changer Enabled (utile aux scripts qui le lisent).
C.Menus = {
	-- Le guide reste propriétaire lorsque la boutique s'ouvre. Les commandes
	-- tactiles restent utilisables. Aucune modification de caméra en jeu.
	{ Id = "RookieGuide", ScreenGui = "RookieGuideUI", Trigger = "Enabled",
		KeepWholeGui = true, Priority = 100, CameraEffects = false,
		ReplaceKeepScreenGuis = true,
		KeepScreenGuis = { "RookieGuideHUD", "UGCshop", "TouchGui" } },
	{ Id = "Settings", ScreenGui = "SettingsUI", Trigger = "Enabled", KeepWholeGui = true },
	{ Id = "HowToPlay", ScreenGui = "How to Play", Trigger = "Visible", Path = { "HtpButton2" } },
	{ Id = "Streak", ScreenGui = "StreakGui", Trigger = "Visible", Path = { "Frame" }, KeepWholeGui = true },
	{ Id = "UGCshop", ScreenGui = "UGCshop", Trigger = "Visible", Path = { "ShopFrame" } },
	{ Id = "PointsShop", ScreenGui = "PointsShop", Trigger = "Visible", Path = { "PointFrame" } },
	{ Id = "Shop", ScreenGui = "Shop", Trigger = "Visible", Path = { "PointFrame" } },
	{ Id = "Rebirth", ScreenGui = "Rebirth", Trigger = "Visible", Path = { "ShopFrame" } },
	{ Id = "Quest", ScreenGui = "Quest", Trigger = "Visible", Path = { "ShopFrame" } },
	{ Id = "Donation", ScreenGui = "DonationSystemUI", Trigger = "Visible", Path = { "MainFrame" },
		KeepWholeGui = true, KeepScreenGuis = { "DonationNotification" } },
	{ Id = "Gifting", ScreenGui = "GiftWizard", Trigger = "Enabled", KeepWholeGui = true,
		KeepScreenGuis = { "GiftError" } },
	{ Id = "Profile", ScreenGui = "PlayerProfileUI", Trigger = "Visible", Path = { "Profile" }, KeepWholeGui = true },
	-- Fenêtres annexes créées/détruites par le client Gifting fourni.
	{ Id = "TopGifters", ScreenGui = "TopGifters", Trigger = "Enabled", KeepWholeGui = true },
	{ Id = "GiftReceived", ScreenGui = "GiftReceived", Trigger = "Enabled", KeepWholeGui = true },
	{ Id = "GiftDisabled", ScreenGui = "GiftDisabledNotice", Trigger = "Enabled", KeepWholeGui = true },
	{ Id = "DailyTool", ScreenGui = "Daily tool", Trigger = "Visible", Path = { "DailyTool" } },
	-- "dailyspin" = bouton d'ouverture ; la vraie fenêtre est DailySpinGui.
	-- Contents évite que son contrôle de respawn confonde masquage et fermeture.
	{ Id = "DailySpin", ScreenGui = "DailySpinGui", Trigger = "Enabled", KeepWholeGui = true, HideMode = "Contents" },
	-- Sous-fenêtre TRY de la boutique UGC présente dans le fichier fourni.
	{ Id = "UGCTry", ScreenGui = "UGCShopGui", Trigger = "Visible", Path = { "ShopFrame" } },

	-- IMPORTANT : voir INSTALLATION pour désactiver l'ancien focus Halloween.
	{ Id = "Halloween", ScreenGui = "HalloweenEventUI", Trigger = "Enabled", KeepWholeGui = true },
}

return C