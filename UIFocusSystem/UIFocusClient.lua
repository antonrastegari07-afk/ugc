-- LocalScript : StarterGui > UIFocusSystem > UIFocusClient
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local container = script.Parent
local C = require(container:WaitForChild("UI_FOCUS_CONFIG"))
if C.Enabled == false then return end

-- Ne pas lancer deux contrôleurs si le modèle a été importé deux fois.
-- Le premier ScreenGui homonyme dans PlayerGui est l'unique propriétaire.
for _, gui in ipairs(playerGui:GetChildren()) do
	if gui.Name == container.Name and gui:IsA("ScreenGui") then
		if gui ~= container then
			warn("[UIFocus] Copie ignorée : garde un seul UIFocusSystem dans StarterGui.")
			return
		end
		break
	end
end

local Effects = require(container:WaitForChild("SceneEffects"))
local Engine = require(container:WaitForChild("FocusEngine"))
local effects = Effects.new(C, {
	Workspace = workspace,
	TweenService = game:GetService("TweenService"),
	StarterGui = game:GetService("StarterGui"),
	Lighting = game:GetService("Lighting"),
})
-- Verrou de caméra séparé du choix du menu : un menu ouvert par script
-- ne peut pas réintroduire le flou/zoom pendant les checkpoints du guide.
local function syncGameplay()
	effects:SetGameplay(playerGui:GetAttribute("RookieGuidePhase") == "play")
end
local phaseConnection = playerGui:GetAttributeChangedSignal("RookieGuidePhase"):Connect(syncGameplay)
syncGameplay()
local engine = Engine.new(playerGui, container, C, function(menu, effectMenu)
	-- effectMenu = la fenêtre dont on applique le flou / zoom (voir CameraEffectsFrom)
	effects:Set(effectMenu or menu)
	if C.Debug then
		print("[UIFocus]", menu and menu.Id or "aucune fenêtre ouverte",
			(effectMenu and effectMenu ~= menu) and ("| effets de " .. effectMenu.Id) or "")
	end
end)
local stopped = false
local renderConnection
local destroyConnection
local ancestryConnection
local function stop()
	if stopped then return end
	stopped = true
	container:SetAttribute("RookieGuideSupport", nil)
	if renderConnection then renderConnection:Disconnect() end
	if destroyConnection then destroyConnection:Disconnect() end
	if ancestryConnection then ancestryConnection:Disconnect() end
	phaseConnection:Disconnect()
	engine:Destroy()
	effects:Destroy()
end

-- Pas de réaction en chaîne dans les signaux Enabled/Visible.
-- Avant le rendu : traite seulement les changements et un contrôle léger
-- périodique. Step retourne immédiatement entre deux changements.
renderConnection = RunService.PreRender:Connect(function()
	local ok, err = pcall(function() engine:Step(os.clock()) end)
	if not ok then
		stop()
		warn("[UIFocus] Arrêt et restauration des interfaces : " .. tostring(err))
	end
end)
destroyConnection = container.Destroying:Connect(stop)
ancestryConnection = container.AncestryChanged:Connect(function()
	if not container:IsDescendantOf(playerGui) then stop() end
end)
container:SetAttribute("RookieGuideSupport", 4)

-- Diagnostic utile sans modifier la configuration de l'événement à ta place.
task.defer(function()
	local config = ReplicatedStorage:FindFirstChild("HALLOWEEN_EVENT_CONFIG")
	if not config or not config:IsA("ModuleScript") then return end
	local ok, halloween = pcall(require, config)
	if not ok or type(halloween) ~= "table" then return end
	local ui = halloween.UI or {}
	if ui.HideOtherUI ~= false or (ui.BlurSize or 18) > 0 then
		warn("[UIFocus] Dans HALLOWEEN_EVENT_CONFIG, avant return C, ajoute : C.UI.HideOtherUI = false ; C.UI.BlurSize = 0. Le focus Halloween sera géré ici.")
	end
end)
