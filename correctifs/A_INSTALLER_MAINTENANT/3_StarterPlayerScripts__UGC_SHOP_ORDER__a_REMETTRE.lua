--════════════════════════════════════════════════════════════════════════════
-- ↕️ UGC SHOP ORDER — CLIENT (réordonne le shop EN DIRECT)
--  📍 LocalScript dans StarterPlayer > StarterPlayerScripts. Nouveau fichier.
--
--  Optionnel : sans ce script, le nouvel ordre s'applique quand le shop est
--  reconstruit (en général : au prochain join), car GetSortedItems() le suit.
--  Avec ce script, les boutons du shop déjà affichés se replacent tout de
--  suite, et à chaque fois que le shop est recréé.
--
--  Il cherche dans le PlayerGui les objets nommés comme ButtonName / FrameName
--  de tes UGC et règle leur LayoutOrder, uniquement s'ils sont rangés par un
--  UIListLayout / UIGridLayout. Il ne touche à RIEN d'autre (ni prix, ni
--  achats, ni textes).
--
--  ↩️ Pour désactiver : LIVE_REORDER = false
--════════════════════════════════════════════════════════════════════════════
local LIVE_REORDER = true
if not LIVE_REORDER then return end

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UGC_CONFIG = require(ReplicatedStorage:WaitForChild("UGC_CONFIG"))
if not UGC_CONFIG.OnOrderChanged then
	warn("[UGCShopOrder] Patch UGC_CONFIG manquant → réordonnage en direct désactivé")
	return
end

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- nom d'objet → rang dans le shop
local rankByName = {}

local function rebuildRanks()
	rankByName = {}
	for i, it in ipairs(UGC_CONFIG.GetSortedItems()) do
		if it.ButtonName then rankByName[it.ButtonName] = i end
		if it.FrameName and rankByName[it.FrameName] == nil then rankByName[it.FrameName] = i end
	end
end

local function layoutOf(parent)
	if not parent then return nil end
	return parent:FindFirstChildWhichIsA("UIGridStyleLayout")
end

-- Remonte au plus 2 niveaux pour trouver l'objet réellement rangé par le layout
local function place(obj, rank)
	local cur = obj
	for _ = 0, 2 do
		if not cur or not cur:IsA("GuiObject") then return end
		local lay = layoutOf(cur.Parent)
		if lay then
			lay.SortOrder = Enum.SortOrder.LayoutOrder
			if cur.LayoutOrder ~= rank then cur.LayoutOrder = rank end
			return
		end
		cur = cur.Parent
	end
end

local function applyAll()
	for _, d in ipairs(playerGui:GetDescendants()) do
		local r = rankByName[d.Name]
		if r and d:IsA("GuiObject") then place(d, r) end
	end
end

-- Regroupe les ajouts (le shop crée souvent tous ses boutons d'un coup)
local pending = false
local function schedule()
	if pending then return end
	pending = true
	task.delay(0.1, function()
		pending = false
		applyAll()
	end)
end

rebuildRanks()
applyAll()

UGC_CONFIG.OnOrderChanged(function()
	rebuildRanks()
	schedule()
end)

playerGui.DescendantAdded:Connect(function(d)
	if rankByName[d.Name] then schedule() end
end)