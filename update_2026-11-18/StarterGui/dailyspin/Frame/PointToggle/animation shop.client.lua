--════════════════════════════════════════════════════════════════════════════
-- 🖱️ Animation du bouton de la roulette (survol 90 %, appui 85 %) — même effet qu'avant.
--  🩹 Avant, ce script déplaçait aussi la roulette à 25 % de la largeur sur mobile :
--  elle se décollait du reste. Sa place est maintenant donnée par
--  ReplicatedStorage ▸ HudLayout (à droite de Skip Level, en évitant les boutons du haut).
--════════════════════════════════════════════════════════════════════════════
local button = script.Parent
local frame = button.Parent
local HL = require(game:GetService("ReplicatedStorage"):WaitForChild("HudLayout"))
HL.Hover(button, frame)
