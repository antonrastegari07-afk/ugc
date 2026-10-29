-- ============================================================
-- BLINKING LIGHTS (LocalScript) — StarterPlayer ▸ StarterPlayerScripts
-- ============================================================
-- Remplace les 32 scripts serveur « SpotLight.Script » (By Itswibee) qui changeaient la
-- luminosité des spots toutes les 0,1 s DEPUIS LE SERVEUR : chaque changement était envoyé
-- à tous les joueurs (≈ 320 changements par seconde en continu sur le réseau).
-- Ici, la même animation tourne chez chaque joueur : rien n'est envoyé par le réseau.
--
-- Même séquence que l'original : luminosité 1 → 12 puis 11 → 1, une étape toutes les 0,1 s,
-- en boucle. Les spots portent le Tag "WSM_BlinkLight" (posé par le convertisseur).
-- ============================================================
local CollectionService = game:GetService("CollectionService")

local TAG = "WSM_BlinkLight"

local function setAll(brightness)
	-- GetTagged ne renvoie que les spots chargés chez ce joueur (streaming)
	for _, light in ipairs(CollectionService:GetTagged(TAG)) do
		if light:IsA("Light") and light:IsDescendantOf(workspace) then
			light.Brightness = brightness
		end
	end
end

while task.wait() do
	for i = 1, 12 do
		setAll(i)
		task.wait(0.1)
	end
	for i = 11, 1, -1 do
		setAll(i)
		task.wait(0.1)
	end
end
