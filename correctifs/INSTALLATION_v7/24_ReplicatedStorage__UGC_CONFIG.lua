-- 🛍️ UGC_CONFIG — LA LISTE DES UGC DU SHOP

--[[  📋 MODÈLE À COPIER : colle-le dans la liste ci-dessous et change les chiffres

	{
		AssetId = 000000000,
		Price = 2000000,
	},

	Seuls AssetId et Price sont obligatoires. Tout le reste a une valeur par défaut :
	nom et image = ceux de l'UGC sur Roblox. À ajouter seulement si tu en as besoin :

		ImageId = 000000000          ton image à la place de la miniature Roblox
		Thumbnail = true             miniature Roblox même si ImageId est rempli
		Name = "Mon UGC"             ton nom à la place du nom Roblox
		InitialStock = 50            stock de départ (mode compteur maison)
		Order = 100                  place dans le shop (plus grand = plus haut)

	Le badge NEW se coche dans le panel admin : 📦 RÉGLAGES DU STOCK ▸ ↕️ ORDRE DU SHOP.
]]

local UGC_CONFIG = {}

UGC_CONFIG.Items = {

	{
		Name = "Black Diamond Crown",
		AssetId = 78927052775669,
		ImageId = 94179634345502,
		Price = 2000000,
		InitialStock = 50,
		Order = 82,
		IsNew = true,
	},

	{
		Name = "Cute Ghost Catcher",
		AssetId = 105487513277629,
		ImageId = 114664145698857,
		Price = 2000000,
		InitialStock = 50,
		Order = 81,
		IsNew = true,
	},

	{
		Name = "White Evil Black Head",
		AssetId = 82722796360176,
		ImageId = 92150925381054,
		Price = 2000000,
		InitialStock = 50,
		Order = 80,
		IsNew = true,
	},

	{
		Name = "Snow Leopard MeiMei Backpack Plushie",
		AssetId = 105975485890749,
		ImageId = 131864466538161,
		Price = 2000000,
		InitialStock = 50,
		Order = 79,
		IsNew = true,
	},

	{
		Name = "GLOWING Black Hole Horns w/ chains [EMISSIVE]",
		AssetId = 94397305883900,
		ImageId = 128419103132539,
		Price = 6000000,
		InitialStock = 10,
		Order = 78,
		IsNew = true,
	},

	{
		Name = "Black Cat Ears",
		AssetId = 129828530188844,
		ImageId = 78191548435026,
		Price = 2000000,
		InitialStock = 50,
		Order = 77,
		IsNew = true,
	},

	{
		Name = "crimson Jester Anime Hair w/ Mask",
		AssetId = 138491097638591,
		ImageId = 126106018929912,
		Price = 2000000,
		InitialStock = 50,
		Order = 76,
	},

	{
		Name = "Infernal Demon Horns",
		AssetId = 73599879855231,
		ImageId = 113724998839485,
		Price = 2000000,
		InitialStock = 50,
		Order = 75,
	},

	{
		Name = "Pumpkin Reaper Scythe",
		AssetId = 120398178300052,
		ImageId = 71489669207932,
		Price = 2000000,
		InitialStock = 50,
		Order = 74,
	},

	{
		Name = "Arctic Excalibur",
		AssetId = 86103466091676,
		ImageId = 137497543539564,
		Price = 2000000,
		InitialStock = 50,
		Order = 73,
	},

	{
		Name = "Royal Abyss Horns",
		AssetId = 100425681483416,
		ImageId = 100214075226334,
		Price = 2000000,
		InitialStock = 50,
		Order = 72,
	},

	{
		Name = "Ruby Queen Crown",
		AssetId = 126932792588720,
		ImageId = 88318999224692,
		Price = 2000000,
		InitialStock = 50,
		Order = 71,
	},

	{
		Name = "Dark Fallen Wings",
		AssetId = 100995727431097,
		ImageId = 109157905471044,
		Price = 2000000,
		InitialStock = 50,
		Order = 70,
	},

	{
		Name = "Obsidian Sword",
		AssetId = 95939959821335,
		ImageId = 98718566064510,
		Price = 2000000,
		InitialStock = 50,
		Order = 69,
	},

	{
		Name = "Void Eye Sniper",
		AssetId = 129433895606013,
		ImageId = 85067430287483,
		Price = 2000000,
		InitialStock = 50,
		Order = 68,
	},

	{
		Name = "Crimson Eye Sniper",
		AssetId = 92977625455050,
		ImageId = 118217363590782,
		Price = 2000000,
		InitialStock = 50,
		Order = 67,
	},

	{
		Name = "Phantom Eye Sniper",
		AssetId = 77964460810821,
		ImageId = 76268097144584,
		Price = 2000000,
		InitialStock = 50,
		Order = 66,
	},

	{
		Name = "Divine Golden Angel Wings",
		AssetId = 83234172775661,
		ImageId = 98435432694916,
		Price = 2000000,
		InitialStock = 50,
		Order = 65,
	},

	{
		Name = "GLOWING Sakura Fedora [EMISSIVE]",
		AssetId = 121269418016646,
		ImageId = 106518654784538,
		Price = 6000000,
		InitialStock = 10,
		Order = 64,
	},

	{
		Name = "GLOWING Purple Crystallite Wings [EMISSIVE]",
		AssetId = 129656374334007,
		ImageId = 112561735858618,
		Price = 6000000,
		InitialStock = 10,
		Order = 63,
	},

	{
		Name = "Cursed Pumpkin Hammer",
		AssetId = 93158506103825,
		ImageId = 103928483502037,
		Price = 2000000,
		InitialStock = 50,
		Order = 62,
	},

	{
		Name = "Cursed Pumpkin Scythe",
		AssetId = 125623060461155,
		ImageId = 127053391247324,
		Price = 2000000,
		InitialStock = 50,
		Order = 61,
	},

	{
		Name = "Black Spiky Stone Wings",
		AssetId = 85640766431733,
		ImageId = 109682677864865,
		Price = 2000000,
		InitialStock = 50,
		Order = 60,
	},

	{
		Name = "Black Ice Energy Blades",
		AssetId = 114129652988720,
		ImageId = 108567527363101,
		Price = 2000000,
		InitialStock = 50,
		Order = 59,
	},

	{
		Name = "Black Evil Halloween Head",
		AssetId = 120125465081920,
		ImageId = 108260692536136,
		Price = 2000000,
		InitialStock = 50,
		Order = 58,
	},

	{
		Name = "Halloween Pumpkin Candy Bucket",
		AssetId = 81506887350959,
		ImageId = 126974389604760,
		Price = 2000000,
		InitialStock = 30,
		Order = 57,
	},

	{
		Name = "Black Cowboy Hat w/ Face Scarf",
		AssetId = 128860989571925,
		ImageId = 76627013482708,
		Price = 2000000,
		InitialStock = 50,
		Order = 56,
	},

	{
		Name = "Black & White Graphic Skateboard",
		AssetId = 77375697226976,
		ImageId = 88725263180481,
		Price = 2000000,
		InitialStock = 50,
		Order = 55,
	},

	{
		Name = "Black Emo Berret Hat",
		AssetId = 126815380890175,
		ImageId = 97886832382067,
		Price = 2000000,
		InitialStock = 50,
		Order = 54,
	},

	{
		Name = "Enchanted Pixelated Diamond Sword",
		AssetId = 87746944518061,
		ImageId = 92668486326638,
		Price = 2000000,
		InitialStock = 50,
		Order = 53,
	},

	{
		Name = "Cute Pumpkin Teddy Bear",
		AssetId = 138946697402409,
		ImageId = 75606819504610,
		Price = 2000000,
		InitialStock = 50,
		Order = 52,
	},

	{
		Name = "Dark Cursed Knight Cape",
		AssetId = 116016010841551,
		ImageId = 107312490992377,
		Price = 2000000,
		InitialStock = 50,
		Order = 51,
	},

	{
		Name = "Flaming Dragon Sword",
		AssetId = 107922877817833,
		ImageId = 134511502334803,
		Price = 2000000,
		InitialStock = 50,
		Order = 50,
	},

	{
		Name = "[GLOWING] Korblox Crystallite Wings (EMISSIVE)",
		AssetId = 112163393611004,
		ImageId = 77191114054071,
		Price = 6000000,
		InitialStock = 10,
		Order = 49,
	},

	{
		Name = "White Angel Wings w/ Silver Stars",
		AssetId = 120004947338156,
		ImageId = 85372293554498,
		Price = 2000000,
		InitialStock = 50,
		Order = 48,
	},

	{
		Name = "Dark Cursed Knight Crown Helmet",
		AssetId = 104572317441277,
		ImageId = 125591768063447,
		Price = 2000000,
		InitialStock = 50,
		Order = 47,
	},

	{
		Name = "Black Fallen Angel Horns",
		AssetId = 130527417282784,
		ImageId = 138188724872800,
		Price = 2000000,
		InitialStock = 50,
		Order = 46,
	},

	{
		Name = "Black & White Y2K Cap",
		AssetId = 124984212464863,
		ImageId = 110517259627694,
		Price = 2000000,
		InitialStock = 30,
		Order = 45,
	},

	{
		Name = "Black Messy Anime Hair w/ Headphones",
		AssetId = 74485674437478,
		ImageId = 140320729427572,
		Price = 2000000,
		InitialStock = 30,
		Order = 44,
	},

	{
		Name = "Halloween Pumpkin Head w/ Witch Hat",
		AssetId = 116437397913826,
		ImageId = 130443092583457,
		Price = 2000000,
		InitialStock = 50,
		Order = 43,
	},

	{
		Name = "Eternal Purple Excalibur",
		AssetId = 129980525997213,
		ImageId = 127283742165082,
		Price = 2000000,
		InitialStock = 50,
		Order = 42,
	},

	{
		Name = "Korblox Obsidian Horns",
		AssetId = 107891382385520,
		ImageId = 76189905360447,
		Price = 2000000,
		InitialStock = 50,
		Order = 41,
	},

	{
		Name = "White Cat Ears",
		AssetId = 129237857703141,
		ImageId = 119693492354271,
		Price = 2000000,
		InitialStock = 25,
		Order = 40,
	},

	{
		Name = "GLOWING White Crystallite Wings [EMISSIVE]",
		AssetId = 80557034259155,
		ImageId = 121043935534083,
		Price = 6000000,
		InitialStock = 10,
		Order = 39,
	},

	{
		Name = "GLOWING Korblox Wings [EMISSIVE]",
		AssetId = 135211838422368,
		ImageId = 135440236728865,
		Price = 6000000,
		InitialStock = 10,
		Order = 38,
	},

	{
		Name = "Gojo Head Combo",
		AssetId = 114029380940261,
		ImageId = 84953912801704,
		Price = 2000000,
		InitialStock = 50,
		Order = 37,
	},

	{
		Name = "Sukuna Head Combo",
		AssetId = 102608080453412,
		ImageId = 110365245795684,
		Price = 2000000,
		InitialStock = 50,
		Order = 36,
	},

	{
		Name = "White Bandage Wolf Hair",
		AssetId = 129609410042151,
		ImageId = 94946033941133,
		Price = 2000000,
		InitialStock = 30,
		Order = 35,
	},

	{
		Name = "Cute Black Girly Hair",
		AssetId = 75936520967737,
		ImageId = 71599543671163,
		Price = 2000000,
		InitialStock = 30,
		Order = 34,
	},

	{
		Name = "Cute White Girly Hair",
		AssetId = 74158791633551,
		ImageId = 108372728612893,
		Price = 2000000,
		InitialStock = 30,
		Order = 33,
	},

	{
		Name = "Black Bandage Wolf Hair",
		AssetId = 128522021121403,
		ImageId = 117344804517998,
		Price = 2000000,
		InitialStock = 50,
		Order = 32,
	},

	{
		Name = "Frost Dragon's Sword",
		AssetId = 126437385255582,
		ImageId = 87535027588166,
		Price = 2000000,
		InitialStock = 30,
		Order = 31,
	},

	{
		Name = "Y2K Black Guitar",
		AssetId = 75204556920896,
		ImageId = 107452445654689,
		Price = 2000000,
		InitialStock = 25,
		Order = 30,
	},

	{
		Name = "Black Obsidian Horns",
		AssetId = 72924674705425,
		ImageId = 77821107565156,
		Price = 2000000,
		InitialStock = 25,
		Order = 29,
	},

	{
		Name = "Azure Axolotl",
		AssetId = 70940921280078,
		ImageId = 80069967823743,
		Price = 2000000,
		InitialStock = 50,
		Order = 28,
	},

	{
		Name = "White Demonic Wings",
		AssetId = 134902756629626,
		ImageId = 107846911293129,
		Price = 2000000,
		InitialStock = 50,
		Order = 27,
	},

	{
		Name = "Y2K Emo Bunny",
		AssetId = 134990401762053,
		ImageId = 91124939210125,
		Price = 2000000,
		InitialStock = 50,
		Order = 26,
	},

	{
		Name = "Black beanie",
		AssetId = 98961783144875,
		ImageId = 72949898261268,
		Price = 2000000,
		InitialStock = 25,
		Order = 25,
	},

	{
		Name = "Galaxy Cape /w Sword",
		AssetId = 118576198379829,
		ImageId = 118947224798671,
		Price = 2000000,
		InitialStock = 50,
		Order = 24,
	},

	{
		Name = "Galaxy Dragon Back Set",
		AssetId = 116782442433686,
		ImageId = 140225854400468,
		Price = 2000000,
		InitialStock = 50,
		Order = 23,
	},

	{
		Name = "Galaxy Dual Sword",
		AssetId = 83905317615156,
		ImageId = 96064278499204,
		Price = 2000000,
		InitialStock = 50,
		Order = 22,
	},

	{
		Name = "Purple Fallen Wings",
		AssetId = 83758875136246,
		ImageId = 79009233288162,
		Price = 2000000,
		InitialStock = 50,
		Order = 21,
	},

	{
		Name = "Black Dual Katana",
		AssetId = 132640981936329,
		ImageId = 137422621071160,
		Price = 2000000,
		InitialStock = 50,
		Order = 20,
	},

	{
		Name = "Golden Ruby Excalibur",
		AssetId = 137588523370262,
		ImageId = 138263265711697,
		Price = 2000000,
		InitialStock = 50,
		Order = 19,
	},

	{
		Name = "Black Scythe",
		AssetId = 118630631850262,
		ImageId = 97158077798493,
		Price = 2000000,
		InitialStock = 50,
		Order = 18,
	},

	{
		Name = "Golden Coins Horns",
		AssetId = 132769224860142,
		ImageId = 96123338216405,
		Price = 2000000,
		InitialStock = 30,
		Order = 17,
	},

	{
		Name = "Shadow Dragon Blade",
		AssetId = 89712486182010,
		ImageId = 91882628352805,
		Price = 2000000,
		InitialStock = 30,
		Order = 16,
	},

	{
		Name = "Black Girl Bun Hair w/ Cap",
		AssetId = 74134154958787,
		ImageId = 119715888112543,
		Price = 2000000,
		InitialStock = 50,
		Order = 15,
	},

	{
		Name = "Nightfall Sword",
		AssetId = 118624181846831,
		ImageId = 87081409501576,
		Price = 2000000,
		InitialStock = 35,
		Order = 14,
	},

	{
		Name = "Black Ice Crown",
		AssetId = 101397096532263,
		ImageId = 131876936642873,
		Price = 2000000,
		InitialStock = 35,
		Order = 13,
	},

	{
		Name = "Darkthorn Crown",
		AssetId = 87629406056335,
		ImageId = 90493370191440,
		Price = 2000000,
		InitialStock = 25,
		Order = 12,
	},

	{
		Name = "Summer Sea Mask",
		AssetId = 114616985343091,
		ImageId = 110642618245380,
		Price = 2000000,
		InitialStock = 25,
		Order = 11,
	},

	{
		Name = "Black Ice Exaclibur",
		AssetId = 116325086460718,
		ImageId = 94824484651184,
		Price = 2000000,
		InitialStock = 25,
		Order = 10,
	},

	{
		Name = "Cute White Dragon",
		AssetId = 82106729073540,
		ImageId = 91490777120920,
		Price = 2000000,
		InitialStock = 25,
		Order = 9,
	},

	{
		Name = "Crimson Fallen Wings",
		AssetId = 111943530329241,
		ImageId = 116720660398893,
		Price = 2000000,
		InitialStock = 25,
		Order = 8,
	},

	{
		Name = "Cute Black Dragon",
		AssetId = 125115499889430,
		ImageId = 115566979212713,
		Price = 2000000,
		InitialStock = 25,
		Order = 7,
	},

	{
		Name = "Abyssal Crown",
		AssetId = 85139390071438,
		ImageId = 90493370191440,
		Price = 2000000,
		InitialStock = 25,
		Order = 6,
	},

	{
		Name = "Fluffy Messy Boy Hair",
		AssetId = 115137108197255,
		ImageId = 126483205173731,
		Price = 1500000,
		InitialStock = 40,
		Order = 5,
	},

	{
		Name = "Amethyst Reaper",
		AssetId = 89168884482751,
		ImageId = 85033565667991,
		Price = 2000000,
		InitialStock = 25,
		Order = 3,
	},

	{
		Name = "Frozen Excalibur",
		AssetId = 91353218384228,
		ImageId = 94562169281497,
		Price = 2000000,
		InitialStock = 25,
		Order = 2,
	},

	{
		Name = "Blonde Messy Hair",
		AssetId = 86260249555040,
		ImageId = 117148842981608,
		Price = 1500000,
		InitialStock = 40,
		Order = 1,
	},

}

-- ════════════════════════════════════════════════════════════════════════════
-- ⚙️ REMPLISSAGE AUTOMATIQUE + VÉRIFICATION (ne rien modifier ici)
-- ════════════════════════════════════════════════════════════════════════════
do
	local function id(v) return string.format("%.0f", tonumber(v) or 0) end
	local seenA, seenB = {}, {}
	local pendingNames = {}
	local function bad(i, msg) warn(("⚠️ [UGC_CONFIG] UGC n°%d : %s"):format(i, msg)) end
	for i, it in ipairs(UGC_CONFIG.Items) do
		if type(it.AssetId) ~= "number" or it.AssetId <= 0 then bad(i, "AssetId manquant ou invalide") end
		if type(it.Price) ~= "number" or it.Price < 0 then bad(i, "Price manquant ou invalide (" .. tostring(it.Name or it.AssetId) .. ")") end
		local k = id(it.AssetId)
		if seenA[k] then bad(i, "AssetId " .. k .. " déjà utilisé par « " .. tostring(seenA[k]) .. " »") end
		seenA[k] = it.Name or k
		-- noms internes : générés à partir de l'AssetId s'ils manquent
		it.ButtonName = it.ButtonName or ("UGC_" .. k)
		it.ButtonPath = it.ButtonPath or ("UGC_" .. k .. "_Button")
		if seenB[it.ButtonName] then bad(i, "ButtonName « " .. it.ButtonName .. " » en double") end
		seenB[it.ButtonName] = true
		-- nom : celui de Roblox s'il manque (rempli juste après, en tâche de fond)
		if it.Name == nil then
			it.Name = "UGC " .. k
			it._autoName = true
			table.insert(pendingNames, it)
		end
		if it.FrameName == nil then it.FrameName = it.Name; it._autoFrame = true end
		-- image : miniature Roblox si demandée (Thumbnail = true) ou si aucune ImageId
		if it.Thumbnail == true or it.ImageId == nil or it.ImageId == 0 then
			it.ImageId = "rbxthumb://type=Asset&id=" .. k .. "&w=420&h=420"
		end
		it.InitialStock = tonumber(it.InitialStock) or 0
		it.Order = tonumber(it.Order) or 0
		it.IsNew = it.IsNew == true
	end

	-- 🏷️ noms Roblox des UGC sans Name (une seule fois, côté serveur ET joueur)
	local namesLeft = #pendingNames
	if namesLeft > 0 then
		task.spawn(function()
			local MPS = game:GetService("MarketplaceService")
			for _, it in ipairs(pendingNames) do
				local ok, info = pcall(function() return MPS:GetProductInfo(it.AssetId, Enum.InfoType.Asset) end)
				if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
					it.Name = info.Name
					if it._autoFrame then it.FrameName = info.Name end
				end
				namesLeft -= 1
			end
		end)
	end
	-- attend (au plus `timeout` s) que les noms automatiques soient arrivés
	function UGC_CONFIG.WaitNames(timeout)
		local t0 = os.clock()
		while namesLeft > 0 and os.clock() - t0 < (timeout or 4) do task.wait(0.1) end
		return namesLeft == 0
	end
end

-- ========================================
-- FONCTIONS UTILITAIRES
-- ========================================

-- Retourne les items triés par Order pour le générateur
-- ⚠️ ORDRE INVERSÉ : plus le Order est grand, plus l'item est en première position
function UGC_CONFIG.GetSortedItems()
	local sorted = {}
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		table.insert(sorted, ugc)
	end
	table.sort(sorted, function(a, b)
		local orderA = a.Order or 0
		local orderB = b.Order or 0
		return orderA > orderB
	end)
	return sorted
end

-- Récupérer un UGC par son AssetId
function UGC_CONFIG.GetByAssetId(assetId)
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		if ugc.AssetId == assetId then
			return ugc
		end
	end
	return nil
end

-- Récupérer un UGC par son ButtonName
function UGC_CONFIG.GetByButtonName(buttonName)
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		if ugc.ButtonName == buttonName then
			return ugc
		end
	end
	return nil
end

-- Table de prix pour le script principal (inchangé)
function UGC_CONFIG.GetPriceTable()
	local prices = {}
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		prices[ugc.AssetId] = {
			name  = ugc.Name,
			price = ugc.Price
		}
	end
	return prices
end

-- Table de stocks initiaux (inchangé)
function UGC_CONFIG.GetInitialStocks()
	local stocks = {}
	for _, ugc in ipairs(UGC_CONFIG.Items) do
		stocks[tostring(ugc.AssetId)] = ugc.InitialStock
	end
	return stocks
end

--════════════════════════════════════════════════════════════════════════════
-- ↕️ PATCH UGC_CONFIG — ORDRE PERSONNALISÉ DU SHOP
--
--  📍 OÙ COLLER ?
--     Dans ton ModuleScript « UGC_CONFIG » (ReplicatedStorage),
--     JUSTE AVANT la dernière ligne :   return UGC_CONFIG
--     Rien à supprimer : ton GetSortedItems actuel est gardé tel quel et
--     devient GetDefaultSortedItems (l'ordre par défaut, Order décroissant).
--
--  ↩️ Pour revenir EXACTEMENT comme avant : USE_CUSTOM_ORDER = false
--
--  Comment ça marche :
--   • L'ordre choisi dans le panneau admin est publié par le serveur
--     (UGCShopOrder_Server) sur ReplicatedStorage.UGCShopOrder, attribut
--     « Order » = "assetId,assetId,...".
--   • GetSortedItems() renvoie tes UGC dans cet ordre. Tout ce qui l'utilise
--     déjà (shop, stock, etc.) suit donc automatiquement.
--   • Un UGC qui n'est PAS dans la liste enregistrée (ex : un nouveau UGC
--     ajouté après) passe EN PREMIER, trié comme d'habitude par Order.
--════════════════════════════════════════════════════════════════════════════
UGC_CONFIG.USE_CUSTOM_ORDER = true
UGC_CONFIG.ORDER_FOLDER     = "UGCShopOrder"

do
	local RS = game:GetService("ReplicatedStorage")
	local defaultSorted = UGC_CONFIG.GetSortedItems   -- ton tri d'origine (Order ↓)

	local function key(id)
		return string.format("%.0f", tonumber(id) or 0)
	end
	UGC_CONFIG.IdKey = key

	-- L'ordre par défaut, toujours disponible
	function UGC_CONFIG.GetDefaultSortedItems()
		return defaultSorted()
	end

	-- Liste d'assetIds enregistrée par l'admin (ou nil = ordre par défaut)
	function UGC_CONFIG.GetCustomOrder()
		local f = RS:FindFirstChild(UGC_CONFIG.ORDER_FOLDER)
		local s = f and f:GetAttribute("Order")
		if type(s) ~= "string" or s == "" then return nil end
		local list = {}
		for part in s:gmatch("[^,%s]+") do
			local n = tonumber(part)
			if n then table.insert(list, n) end
		end
		return (#list > 0) and list or nil
	end

	-- Applique une liste d'ids à l'ordre par défaut
	function UGC_CONFIG.ApplyOrder(customIds)
		local base = defaultSorted()
		if not UGC_CONFIG.USE_CUSTOM_ORDER or type(customIds) ~= "table" or #customIds == 0 then
			return base
		end
		local rank = {}
		for i, id in ipairs(customIds) do
			local k = key(id)
			if not rank[k] then rank[k] = i end
		end
		local out, placed = {}, {}
		for _, it in ipairs(base) do
			if rank[key(it.AssetId)] then
				table.insert(placed, it)
			else
				table.insert(out, it)          -- pas dans la liste → en premier
			end
		end
		table.sort(placed, function(a, b)
			return rank[key(a.AssetId)] < rank[key(b.AssetId)]
		end)
		for _, it in ipairs(placed) do table.insert(out, it) end
		return out
	end

	function UGC_CONFIG.GetSortedItems()
		return UGC_CONFIG.ApplyOrder(UGC_CONFIG.GetCustomOrder())
	end

	-- cb() est appelé à chaque changement d'ordre (et quand le dossier apparaît)
	function UGC_CONFIG.OnOrderChanged(cb)
		local name = UGC_CONFIG.ORDER_FOLDER
		local function hook(f)
			f:GetAttributeChangedSignal("Order"):Connect(cb)
		end
		local f = RS:FindFirstChild(name)
		if f then
			hook(f)
		else
			local conn
			conn = RS.ChildAdded:Connect(function(ch)
				if ch.Name == name then
					conn:Disconnect()
					hook(ch)
					task.defer(cb)
				end
			end)
		end
	end
end


--════════════════════════════════════════════════════════════════════════════
-- 🆕 BADGE NEW — géré depuis le panel admin (UGCShopOrder_Server publie la liste
--    dans ReplicatedStorage.UGCShopOrder, attribut « NewIds » = "assetId,assetId,…").
--    Tant qu'aucun admin n'y a touché (attribut absent), c'est IsNew de la liste qui compte.
--════════════════════════════════════════════════════════════════════════════
do
	local RS = game:GetService("ReplicatedStorage")
	local function set()
		local f = RS:FindFirstChild(UGC_CONFIG.ORDER_FOLDER or "UGCShopOrder")
		local s = f and f:GetAttribute("NewIds")
		if type(s) ~= "string" then return nil end
		local t = {}
		for part in s:gmatch("[^,%s]+") do t[part] = true end
		return t
	end
	function UGC_CONFIG.IsNew(it)
		if type(it) ~= "table" then return false end
		local t = set()
		if t then return t[string.format("%.0f", tonumber(it.AssetId) or 0)] == true end
		return it.IsNew == true
	end
	-- cb() à chaque changement des badges NEW
	function UGC_CONFIG.OnNewChanged(cb)
		local name = UGC_CONFIG.ORDER_FOLDER or "UGCShopOrder"
		local function hook(f) f:GetAttributeChangedSignal("NewIds"):Connect(cb) end
		local f = RS:FindFirstChild(name)
		if f then hook(f) else
			local conn
			conn = RS.ChildAdded:Connect(function(ch)
				if ch.Name == name then conn:Disconnect(); hook(ch); task.defer(cb) end
			end)
		end
	end
end

return UGC_CONFIG
