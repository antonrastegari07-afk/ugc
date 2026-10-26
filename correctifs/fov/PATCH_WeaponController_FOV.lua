-- ============================================================
-- PATCH FOV : ReplicatedStorage ▸ WeaponSystem ▸ WeaponController
-- ============================================================
-- Problème : la boucle "Feel" de chaque arme écrit camera.FieldOfView à CHAQUE image.
-- À la mort, cette boucle n'est volontairement PAS coupée (HardResetVisualState ne
-- déconnecte pas FeelConnection). Si le script de l'arme survit à la mort (chute dans
-- le vide après un bounce pad / slide+saut : le vide détruit les pièces, pas le
-- LocalScript de l'arme), l'ancienne arme continue d'écrire le FOV pendant que la
-- nouvelle arme (ou WeaponMechanics) écrit le sien → le FOV fait zoom / dézoom en boucle
-- jusqu'au rejoin.
--
-- Correctif : l'arme n'écrit le FOV QUE si elle est tenue par le perso actuel et vivant.
--
-- Dans WeaponController, cherche (Ctrl+F) cette ligne (≈ ligne 3414) :
--
--     camera.FieldOfView = BaseFOV + FireFOVOffset + WeaponSharedState.GetMoveFOV() + (zipFOV or 0)
--
-- et remplace-la par ce bloc :

			-- 🩹 n'écrit le FOV que si CETTE arme est tenue par le perso actuel, vivant
			-- (sinon une arme "fantôme" d'une vie précédente se bat avec la nouvelle)
			local holder = tool.Parent
			local holderHum = holder and holder:FindFirstChildOfClass("Humanoid")
			if holder == Players.LocalPlayer.Character and holderHum and holderHum.Health > 0 then
				camera.FieldOfView = BaseFOV + FireFOVOffset + WeaponSharedState.GetMoveFOV() + (zipFOV or 0)
			end
