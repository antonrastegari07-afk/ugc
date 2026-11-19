--════════════════════════════════════════════════════════════════════════════
-- 🖱️ Animation du bouton (survol 90 %, appui 85 %) — même effet qu'avant.
--  🩹 Avant, ce script forçait aussi la position du bouton en % de la largeur de
--  l'écran (une valeur PC, une autre mobile) : les boutons se décollaient quand le
--  format de l'écran changeait. La place est maintenant donnée par
--  ReplicatedStorage ▸ HudLayout, et l'animation part de cette place.
--════════════════════════════════════════════════════════════════════════════
local button = script.Parent
local frame = button.Parent
local HL = require(game:GetService("ReplicatedStorage"):WaitForChild("HudLayout"))
HL.Hover(button, frame)
