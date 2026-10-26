-- ============================================================
-- PATCH FOV : StarterGui ▸ UIFocusSystem ▸ SceneEffects (ModuleScript)
-- ============================================================
-- Problème : avec Zoom.Enabled = true, SceneEffects "apprend" le FOV normal à partir de
-- N'IMPORTE QUEL FOV resté stable 1 s hors d'un menu UIFocus, puis "corrige" le FOV vers
-- ce normal avec un Tween. En PvP, l'arme (WeaponController) écrit le FOV à CHAQUE image
-- (visée 65, sprint, élan, zipline…). Les deux se battent :
--   • UIFocus tire le FOV vers son "normal" (Tween 0.35 s)
--   • l'arme le remet aussitôt à sa valeur
--   • 1 s plus tard UIFocus recommence → zoom / dézoom en boucle.
-- Si UIFocus a appris un mauvais "normal" (ex. pendant que la frame cross server 1v1
-- est ouverte, qui n'est PAS un menu UIFocus : le joueur reste immobile > 1 s avec un
-- FOV de gameplay), ce mauvais normal reste jusqu'au rejoin → le bug ne part jamais.
--
-- Correctif : quand le FOV appartient au gameplay (arme en main, arène PvP, zipline),
-- UIFocus ne l'apprend plus et ne le corrige plus. Les menus gardent leur zoom.
--
-- INSTALLATION : dans SceneEffects, remplace TOUTE la fonction
--     function Effects:_watchCamera() ... end
-- (de "function Effects:_watchCamera()" jusqu'au "end" juste avant le commentaire
--  "-- Le FOV normal est publié sur la caméra") par le bloc ci-dessous.
-- ============================================================

-- 🎮 Le FOV appartient au gameplay : arme en main, arène PvP ou zipline.
--    Dans ces cas, l'arme / la zipline écrivent le FOV à chaque image : UIFocus ne doit
--    ni l'apprendre comme "normal", ni le corriger (sinon zoom / dézoom en boucle).
local weaponShared -- module WeaponSharedState, cherché une seule fois quand il existe
local function getWeaponShared()
	if weaponShared then return weaponShared end
	local ws = game:GetService("ReplicatedStorage"):FindFirstChild("WeaponSystem")
	local mod = ws and ws:FindFirstChild("WeaponSharedState")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then weaponShared = res end
	end
	return weaponShared
end
local function gameplayOwnsFOV()
	local lp = game:GetService("Players").LocalPlayer
	if lp and lp:GetAttribute("InArena") == true then return true end
	if lp and (lp:GetAttribute("ZiplineFOVAdd") or 0) ~= 0 then return true end
	local shared = getWeaponShared()
	if shared and type(shared.AnyEquipped) == "function" then
		local ok, equipped = pcall(shared.AnyEquipped)
		if ok and equipped then return true end
	end
	return false
end

-- Apprend le FOV « normal » : seulement au repos (aucun menu, aucune session, pas de
-- FOV de gameplay) et après STABLE_DELAY sans changement.
function Effects:_watchCamera()
	if self.fovConnection then self.fovConnection:Disconnect() self.fovConnection = nil end
	local cam = self.services.Workspace.CurrentCamera
	if not cam then return end
	if not self.normalFOV then self.normalFOV = self:_clampFOV(cam.FieldOfView) end
	self:_publish(cam)
	self.fovConnection = cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
		if self.menu or self.session then return end
		self.fovToken += 1
		-- 🎮 FOV piloté par l'arme / l'arène : on ne l'apprend pas et on n'y touche pas
		if gameplayOwnsFOV() then return end
		local token, value = self.fovToken, cam.FieldOfView
		task.delay(STABLE_DELAY, function()
			if self.destroyed or token ~= self.fovToken or self.menu or self.session then return end
			if self.services.Workspace.CurrentCamera ~= cam or cam.FieldOfView ~= value then return end
			if gameplayOwnsFOV() then return end
			-- 🩹 Un FOV resté coincé ENTRE le zoom d'un menu et le normal (ex. 62.6 au lieu
			--    de 70 : animation de fermeture coupée par un autre script) n'est pas un
			--    nouveau normal, c'est un reste de zoom → on remet le normal.
			local normal = self.normalFOV
			local offset = math.min(self.config.Zoom.FOVOffset or -10, 0)
			-- Zoom.Enabled = false → UIFocus ne touche JAMAIS au FOV (même pas pour corriger)
			if normal and self.config.Zoom.Enabled ~= false and value < normal - 0.3 and value >= normal + offset - 0.5 then
				self.services.TweenService:Create(cam, TweenInfo.new(0.35, Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out), { FieldOfView = normal }):Play()
				return
			end
			self.normalFOV = self:_clampFOV(value)
			self:_publish(cam)
		end)
	end)
end
