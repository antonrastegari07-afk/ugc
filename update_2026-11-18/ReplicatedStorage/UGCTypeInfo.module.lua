--════════════════════════════════════════════════════════════════════════════
-- 👒 UGCTypeInfo — ModuleScript dans ReplicatedStorage   (NOUVEAU)
--
--  Décide dans quelle catégorie du filtre TYPE va chaque UGC (Hat, Hair, Head…).
--  Utilisé par le SERVEUR (UGCTypeTagger, qui étiquette chaque UGC une seule fois et
--  le garde en mémoire) et par le shop du joueur (secours si le serveur n'a pas encore
--  répondu).
--
--  ✏️ Forcer une catégorie à la main : dans UGC_CONFIG, ajoute  Type = "Head"  à l'UGC.
--════════════════════════════════════════════════════════════════════════════
local MarketplaceService = game:GetService("MarketplaceService")
local AssetService       = game:GetService("AssetService")

local M = {}

-- types Roblox → catégorie affichée (un mot)
M.TYPE_NAME = {
	[8] = "Hat", [41] = "Hair", [43] = "Neck", [44] = "Shoulder",
	[45] = "Front", [46] = "Back", [47] = "Waist", [19] = "Gear",
	[17] = "Head", [79] = "Head",                                   -- tête classique / dynamique
	[18] = "Face", [42] = "Face", [76] = "Face", [77] = "Face",     -- visage, sourcils, cils
	[88] = "Makeup", [89] = "Makeup", [90] = "Makeup",
	[2] = "Clothing", [11] = "Clothing", [12] = "Clothing",
	[64] = "Clothing", [65] = "Clothing", [66] = "Clothing", [67] = "Clothing",
	[68] = "Clothing", [69] = "Clothing", [72] = "Clothing",
	[70] = "Shoes", [71] = "Shoes",
	[27] = "Body", [28] = "Body", [29] = "Body", [30] = "Body", [31] = "Body",
	[48] = "Animation", [50] = "Animation", [51] = "Animation", [52] = "Animation",
	[53] = "Animation", [54] = "Animation", [55] = "Animation", [56] = "Animation",
	[78] = "Animation", [61] = "Emote", [32] = "Bundle",
}
-- ordre des boutons dans le filtre (une catégorie inconnue va à la fin)
M.ORDER = { "Hat", "Hair", "Head", "Face", "Makeup", "Neck", "Shoulder", "Front", "Back", "Waist",
	"Clothing", "Shoes", "Body", "Animation", "Emote", "Bundle", "Gear" }
-- bundles → catégorie
M.BUNDLE_TYPE = { DynamicHead = "Head", DynamicHeadAvatar = "Head", Shoes = "Shoes",
	Animations = "Animation", BodyParts = "Body" }

local function enumName(typeId)
	for _, e in ipairs(Enum.AssetType:GetEnumItems()) do
		if e.Value == typeId then return e.Name end
	end
	return nil
end

-- objet porté par un avatar ? (accessoire, tête, corps, animation…)
function M.isWearable(typeId)
	if M.TYPE_NAME[typeId] then return true end
	local n = enumName(typeId)
	return n ~= nil and (n:find("Accessory$") ~= nil or n:find("Animation$") ~= nil
		or n:find("Head") ~= nil or n:find("Makeup$") ~= nil)
end

-- type Roblox → catégorie ; type ajouté plus tard par Roblox → son nom (« EarAccessory » → « Ear »)
function M.fromAssetType(typeId)
	if type(typeId) ~= "number" then return nil end
	if M.TYPE_NAME[typeId] then return M.TYPE_NAME[typeId] end
	local n = enumName(typeId)
	if not n then return nil end
	local short = n:gsub("Accessory$", ""):gsub("Animation$", "")
	M.TYPE_NAME[typeId] = short ~= "" and short or n
	return M.TYPE_NAME[typeId]
end

-- catégorie forcée dans UGC_CONFIG (Type = "Head")
function M.forced(ugc)
	local t = type(ugc) == "table" and ugc.Type
	if type(t) == "string" and t ~= "" and #t <= 20 then return t end
	return nil
end

-- ⏳ demande à Roblox (peut prendre 1 à 5 s) → catégorie, ou nil + raison
function M.lookup(assetId)
	local assetType, err
	for try = 1, 3 do   -- Roblox répond parfois en erreur : on réessaie
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, assetId, Enum.InfoType.Asset)
		if ok and type(info) == "table" then assetType = info.AssetTypeId ; break end
		err = info
		if try < 3 then task.wait(1.5) end
	end
	if assetType and M.isWearable(assetType) then return M.fromAssetType(assetType) end
	-- 📦 pas un objet d'avatar : c'est peut-être un BUNDLE (ex. une tête dynamique)
	local okB, b = pcall(AssetService.GetBundleDetailsAsync, AssetService, assetId)
	if okB and type(b) == "table" and b.BundleType then
		return M.BUNDLE_TYPE[tostring(b.BundleType)] or "Bundle"
	end
	if assetType then return M.fromAssetType(assetType) end
	return nil, tostring(err)
end

return M
