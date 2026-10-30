-- EngageTrack — LocalScript dans StarterPlayer ▸ StarterPlayerScripts   (v2, remplace la v1)
-- Sert UNIQUEMENT aux stats (📊 STATS de l'admin panel). Ne change rien au jeu.
--   • 📨 chaque fermeture d'un prompt d'invitation Roblox
--   • 🖱️ le dernier bouton cliqué AVANT une fenêtre d'achat Roblox (d'où vient l'achat)
--     → envoyé seulement quand une fenêtre d'achat se ferme (1 message par achat, pas par clic)
--   • 🔔 l'affichage des popups (popup VIP, bouton pub, popup de départ)
local Players       = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local MPS           = game:GetService("MarketplaceService")
local RS            = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local track = RS:WaitForChild("EngageTrack", 60)
if not track then return end

local function send(...)
	local args = table.pack(...)
	pcall(function() track:FireServer(table.unpack(args, 1, args.n)) end)
end

-- 📨 invitations
SocialService.GameInvitePromptClosed:Connect(function(plr)
	if plr == player then send("invite") end
end)

-- 🖱️ dernier bouton cliqué (chemin dans le PlayerGui, sans le pseudo)
local lastClick, lastClickAt = nil, 0
local function pathOf(obj)
	local parts = {}
	while obj and obj ~= playerGui and #parts < 8 do
		table.insert(parts, 1, obj.Name)
		obj = obj.Parent
	end
	return table.concat(parts, ".")
end
local hooked = setmetatable({}, { __mode = "k" })
local function hook(obj)
	if hooked[obj] or not obj:IsA("GuiButton") then return end
	hooked[obj] = true
	obj.Activated:Connect(function()
		lastClick, lastClickAt = pathOf(obj), os.clock()
	end)
end
for _, d in ipairs(playerGui:GetDescendants()) do hook(d) end
playerGui.DescendantAdded:Connect(hook)

local function reportClick()
	-- le clic qui a ouvert la fenêtre (2 min max avant sa fermeture)
	if lastClick and os.clock() - lastClickAt <= 120 then send("click", lastClick) end
end
MPS.PromptGamePassPurchaseFinished:Connect(function(plr) if plr == player then reportClick() end end)
pcall(function()
	MPS.PromptProductPurchaseFinished:Connect(function(userId) if userId == player.UserId then reportClick() end end)
end)

-- 🔔 popups (affichage = passe de caché à visible)
local POPUPS = {
	{ id = "vip_offer", gui = "VIP offer", path = { "PopupFrame" } },
	{ id = "ad_button", gui = "Reward_ads", path = { "Frame" } },
	{ id = "ad_button", gui = "Reward_ads", path = { "Frame1" } },
}
local lastPop = {}
local function popShown(id)
	local now = os.clock()
	if lastPop[id] and now - lastPop[id] < 20 then return end   -- même popup ré-affiché : 1 fois / 20 s
	lastPop[id] = now
	send("pop", id)
end
local watched = setmetatable({}, { __mode = "k" })
local function watchPopup(def, obj)
	if watched[obj] then return end
	watched[obj] = true
	local was = obj.Visible
	obj:GetPropertyChangedSignal("Visible"):Connect(function()
		if obj.Visible and not was then popShown(def.id) end
		was = obj.Visible
	end)
	if was then popShown(def.id) end
end
local function scan()
	for _, def in ipairs(POPUPS) do
		local obj = playerGui:FindFirstChild(def.gui)
		for _, name in ipairs(def.path) do obj = obj and obj:FindFirstChild(name) end
		if obj and obj:IsA("GuiObject") then watchPopup(def, obj) end
	end
end
scan()
playerGui.ChildAdded:Connect(function(g)
	if g.Name == "LeavePopupGui" then popShown("leave_popup") end
	task.defer(scan)
end)
