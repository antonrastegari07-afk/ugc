# Script « time » (ServerScriptService) — 2 remplacements

Plus simple : remplace tout par `time_COMPLET.lua` (fait à partir de ta version actual_version_1.0).
Aucune nouvelle variable locale au niveau principal (la limite des 200 est respectée).

## 1. Cherche (dans `purchaseUGCEvent.OnServerEvent`) tout ce bloc
```lua
		-- 🚫 PRIVATION D'UGC — vérification serveur, avant toute déduction.
		--    Placée ici volontairement : plus haut on ne connaît pas encore
		--    l'UGC visée, plus bas les points seraient déjà engagés.
		if _G.UGCRestrict then
			--  🆕 3ᵉ valeur : `rec`, la fiche de la sanction. Elle sert à
			--     remplir {warnings} et {confidence} dans tes textes.
			local blocked, why, rec = _G.UGCRestrict.CheckPurchase(player)
			if blocked then
				warn(string.format("🚫 [UGC] Achat refusé pour %s (%s) — %s",
					player.Name, ugcData.name, tostring(why)))

				-- 💬 Titre + texte pris dans le panel admin (⚙️ Messages → 🛒 Shop).
				--    Rendus ICI, côté serveur, avec les vraies valeurs. Le client
				--    ne reçoit qu'un texte fini : il n'y a aucun gabarit à
				--    interpréter côté joueur, donc aucune surface d'injection.
				--
				--    Deux textes DIFFÉRENTS selon le cas, et c'est important :
				--      • "restricted"  = il est vraiment sanctionné
				--      • sinon         = le registre n'a pas répondu, ce n'est
				--                        PAS une sanction et ça peut arriver à
				--                        n'importe qui.
				local title, body
				if _G.ACConfig and _G.ACConfig.Msg then
					local vars = {
						player     = player.Name,
						warnings   = rec and rec.warnings or nil,
						confidence = rec and rec.confidence or nil,
					}
					local ok = pcall(function()
						if why == "restricted" then
							title = _G.ACConfig.Msg("shopBlockedTitle", vars)
							body  = _G.ACConfig.Msg("shopBlockedBody", vars)
						else
							title = _G.ACConfig.Msg("shopUnverifiedTitle", vars)
							body  = _G.ACConfig.Msg("shopUnverifiedBody", vars)
						end
					end)
					--  Si la config n'est pas encore lue, on laisse le client
					--  afficher ses textes par défaut plutôt que rien.
					if not ok then title, body = nil, nil end
				end

				pcall(function()
					confirmUGCPurchaseEvent:FireClient(player, false,
						(why == "restricted") and "ugc_restricted" or "ugc_unverified",
						-- ⚠️ `assetId` et le nom restent en 3ᵉ et 4ᵉ position :
						--    ton shop client existant continue de fonctionner
						--    sans la moindre modification. Le bloc de texte est
						--    AJOUTÉ à la fin, là où rien ne le lisait avant.
						assetId, ugcData.name,
						{ title = title, message = body })
				end)
				return
			end
		else
			-- Le module n'est pas chargé : on refuse plutôt que de laisser
			-- passer. Un joueur honnête voit un message « réessaie », un
			-- exploiteur ne gagne rien à faire tomber le module.
			warn("🚫 [UGC] _G.UGCRestrict absent — achat refusé par sécurité")
			pcall(function()
				confirmUGCPurchaseEvent:FireClient(player, false,
					"ugc_unverified", assetId, ugcData.name)
			end)
			return
		end
```
Remplace par
```lua
		-- 🚫 PRIVATION D'UGC — vérification serveur, avant toute déduction.
		--    Placée ici volontairement : plus haut on ne connaît pas encore
		--    l'UGC visée, plus bas les points seraient déjà engagés.
		--  🆕 V4 : la vérification est rangée dans une fonction. Si « ne révéler que
		--     s'il pourrait se payer l'UGC » est actif (panel → 🤫 Discrétion), elle
		--     n'est faite qu'APRÈS le contrôle des points : sans assez de points,
		--     le joueur restreint voit le message normal « pas assez de points ».
		local function refuseIfRestricted()
			if _G.UGCRestrict then
				--  🆕 3ᵉ valeur : `rec`, la fiche de la sanction. Elle sert à
				--     remplir {warnings} et {confidence} dans tes textes.
				local blocked, why, rec = _G.UGCRestrict.CheckPurchase(player)
				if blocked then
					warn(string.format("🚫 [UGC] Achat refusé pour %s (%s) — %s",
						player.Name, ugcData.name, tostring(why)))

					-- 💬 Titre + texte pris dans le panel admin (⚙️ Messages → 🛒 Shop).
					--    Rendus ICI, côté serveur, avec les vraies valeurs. Le client
					--    ne reçoit qu'un texte fini : il n'y a aucun gabarit à
					--    interpréter côté joueur, donc aucune surface d'injection.
					--
					--    Deux textes DIFFÉRENTS selon le cas, et c'est important :
					--      • "restricted"  = il est vraiment sanctionné
					--      • sinon         = le registre n'a pas répondu, ce n'est
					--                        PAS une sanction et ça peut arriver à
					--                        n'importe qui.
					local title, body
					if _G.ACConfig and _G.ACConfig.Msg then
						local vars = {
							player     = player.Name,
							warnings   = rec and rec.warnings or nil,
							confidence = rec and rec.confidence or nil,
						}
						local ok = pcall(function()
							if why == "restricted" then
								title = _G.ACConfig.Msg("shopBlockedTitle", vars)
								body  = _G.ACConfig.Msg("shopBlockedBody", vars)
							else
								title = _G.ACConfig.Msg("shopUnverifiedTitle", vars)
								body  = _G.ACConfig.Msg("shopUnverifiedBody", vars)
							end
						end)
						--  Si la config n'est pas encore lue, on laisse le client
						--  afficher ses textes par défaut plutôt que rien.
						if not ok then title, body = nil, nil end
					end

					pcall(function()
						confirmUGCPurchaseEvent:FireClient(player, false,
							(why == "restricted") and "ugc_restricted" or "ugc_unverified",
							-- ⚠️ `assetId` et le nom restent en 3ᵉ et 4ᵉ position :
							--    ton shop client existant continue de fonctionner
							--    sans la moindre modification. Le bloc de texte est
							--    AJOUTÉ à la fin, là où rien ne le lisait avant.
							assetId, ugcData.name,
							{ title = title, message = body })
					end)
					return true
				end
			else
				-- Le module n'est pas chargé : on refuse plutôt que de laisser
				-- passer. Un joueur honnête voit un message « réessaie », un
				-- exploiteur ne gagne rien à faire tomber le module.
				warn("🚫 [UGC] _G.UGCRestrict absent — achat refusé par sécurité")
				pcall(function()
					confirmUGCPurchaseEvent:FireClient(player, false,
						"ugc_unverified", assetId, ugcData.name)
				end)
				return true
			end
			return false
		end
		local revealLate = (_G.ACConfig ~= nil and _G.ACConfig.RevealOnlyWhenAffordable ~= nil
			and _G.ACConfig.RevealOnlyWhenAffordable() == true)
		if not revealLate and refuseIfRestricted() then return end
```

## 2. Cherche
```lua
		-- Pas assez de points → auto-prompt Dev Product
		if actualPoints < ugcData.price then
			local pointsNeeded = ugcData.price - actualPoints
			local bestProduct = findBestDevProduct(pointsNeeded)
			if bestProduct then
				print(string.format("💰 AUTO-PROMPT: %s manque %d points → %s",
					player.Name, pointsNeeded, bestProduct.name))
				pcall(function()
					MarketplaceService:PromptProductPurchase(player, bestProduct.id)
				end)
			else
				warn(string.format("⚠️ %s manque %d points mais aucun Dev Product adapté",
					player.Name, pointsNeeded))
			end
			return
		end
```
Remplace par
```lua
		-- Pas assez de points → auto-prompt Dev Product
		if actualPoints < ugcData.price then
			-- 🤫 V4 : un joueur privé d'UGC ne se voit PAS proposer d'acheter des
			--    points en Robux pour une UGC qu'il ne pourra pas avoir. Le shop
			--    lui affiche déjà « pas assez de points » : rien d'autre.
			if revealLate and _G.UGCRestrict and _G.UGCRestrict.IsRestricted(userId) then
				return
			end
			local pointsNeeded = ugcData.price - actualPoints
			local bestProduct = findBestDevProduct(pointsNeeded)
			if bestProduct then
				print(string.format("💰 AUTO-PROMPT: %s manque %d points → %s",
					player.Name, pointsNeeded, bestProduct.name))
				pcall(function()
					MarketplaceService:PromptProductPurchase(player, bestProduct.id)
				end)
			else
				warn(string.format("⚠️ %s manque %d points mais aucun Dev Product adapté",
					player.Name, pointsNeeded))
			end
			return
		end

		-- 🚫 V4 : il a assez de points → c'est MAINTENANT qu'on lui dit qu'il est privé.
		if revealLate and refuseIfRestricted() then return end
```
