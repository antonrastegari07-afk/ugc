-- ============================================================
-- VISUAL EFFECTS (LocalScript) — StarterPlayer ▸ StarterPlayerScripts
-- ============================================================
-- Effets PUREMENT VISUELS qui tournaient sur le serveur : chaque changement était envoyé à
-- tous les joueurs en continu. Ici la même animation tourne chez chaque joueur : rien n'est
-- envoyé par le réseau, et le gameplay ne change pas (aucune collision ni dégât touché).
--
--  • Spots (Tag "WSM_BlinkLight") — remplace les 32 « SpotLight.Script » (By Itswibee) :
--    luminosité 1 → 12 puis 11 → 1, une étape toutes les 0,1 s, en boucle.
--  • Flashing Brick (Tag "WSM_FlashingBrick") — remplace les 4 « Flashing Brick.Script » :
--    transparence 0,1 → 1 puis 0,9 → 0, une étape toutes les 0,1 s, en boucle.
--    (seule la transparence change, comme avant : la collision reste la même)
-- Les Tags sont posés par le convertisseur.
-- ============================================================
local CollectionService = game:GetService("CollectionService")

local function setAll(tag, property, value, class)
	-- GetTagged ne renvoie que ce qui est chargé chez ce joueur (streaming)
	for _, obj in ipairs(CollectionService:GetTagged(tag)) do
		if obj:IsA(class) and obj:IsDescendantOf(workspace) then
			obj[property] = value
		end
	end
end

-- Spots : même boucle que l'ancien script serveur
task.spawn(function()
	while task.wait() do
		for i = 1, 12 do
			setAll("WSM_BlinkLight", "Brightness", i, "Light")
			task.wait(0.1)
		end
		for i = 11, 1, -1 do
			setAll("WSM_BlinkLight", "Brightness", i, "Light")
			task.wait(0.1)
		end
	end
end)

-- Flashing Brick : même séquence que l'ancien script serveur (attente 0,1 s AVANT chaque valeur)
local FLASH_SEQUENCE = { 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1,
	0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1, 0 }
task.spawn(function()
	while true do
		for _, value in ipairs(FLASH_SEQUENCE) do
			task.wait(0.1)
			setAll("WSM_FlashingBrick", "Transparency", value, "BasePart")
		end
	end
end)
