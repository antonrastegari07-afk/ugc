-- ModuleScript enfant de RookieGuide. Textes anglais, comme les autres UI.
return {
	Enabled = true,
	TestMode = true, -- true : rejoue à chaque session, sans marquer le tutoriel vu
	TestUserIds = {},
	StartDelay = 1.5,
	LoadTimeout = 20,
	GuidedCheckpoints = 2,
	ReachRadius = 14,
	AllowProximityProgress = true, -- secours du signal serveur CheckpointUpdated
	MaxSaneDistance = 2000,
	CheckpointFolder = "", -- facultatif : nom d'un Folder direct de Workspace
	MarkSeenOnFinish = true, -- réutilise Remotes.TutorialSeen, y compris SKIP
	StopOnTutorial = true,
	CloseShopOnFinish = true, -- ferme la boutique ouverte pendant le guide
	UGC = { ScreenGui = "UGCshop", ButtonPath = { "Frame", "ShopToggle1" },
		PanelPath = { "ShopFrame" } },
	-- How to Play : caché pendant le guide, affiché quand le guide se termine
	-- (PLAY, SKIP ou clic). Joueurs sans guide : affichage normal inchangé.
	HowToPlay = { ScreenGui = "How to Play", Path = { "HtpButton2" },
		Panel = "HtpButton", ShowOnFinish = true },
	SkipKey = Enum.KeyCode.K,
	SkipGamepadKey = Enum.KeyCode.ButtonB,
	-- Le guidage ne modifie ni les récompenses, ni les achats, ni les données.
	Text = {
		First = "Reach the next checkpoint.",
		Next = "Keep going. One more checkpoint!",
		Waiting = "Move forward. Find the next checkpoint.",
		Shop = "Open the UGC Shop.",
		InventoryTitle = "UGC FOR YOUR ROBLOX AVATAR",
		InventoryBody = "Use points to claim an available accessory. Once Roblox confirms it, find it in your Roblox inventory.",
		InventoryNote = "Check each item's requirements and availability.",
		Finish = "PLAY", Skip = "SKIP", Marker = "NEXT CHECKPOINT",
	},
	Style = {
		-- Valeurs du tutoriel fourni : noir 65%, rayon 12, 8 marches/coin.
		Green = Color3.fromRGB(34, 197, 94),
		DimTransparency = 0.35, HolePadding = 8, HoleBorder = 3,
		HoleCornerRadius = 12, HoleCornerSteps = 8,
		TextOutline = 3, TextOutlineTransparency = 0,
		Font = Enum.Font.FredokaOne, MaxTextSize = 42,
		DisplayOrder = 10000, -- inférieur à CoinRewardGui et RobuxPromptFX
	},
	Arrows = { Enabled = true, Count = 3, UpdateHz = 15, Spacing = 7,
		Speed = 8, Width = 0.28, Length = 2.3, Transparency = 0.20 },
}
