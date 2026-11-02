# Script « time » — 5 petits remplacements (dans purchaseUGCEvent.OnServerEvent)

Ou remplace tout par `time_COMPLET.lua`.

## 1. Cherche
```lua
		if _G.UGCRestrict then
			--  🆕 3ᵉ valeur : `rec`, la fiche de la sanction.
```
Remplace par
```lua
		-- 🆕 V4 : vérification rangée dans une fonction, appelée APRÈS le contrôle des points
		local revealLate = (_G.ACConfig ~= nil and _G.ACConfig.RevealOnlyWhenAffordable ~= nil
			and _G.ACConfig.RevealOnlyWhenAffordable() == true)
		local function refuseIfRestricted()
		if _G.UGCRestrict then
			--  🆕 3ᵉ valeur : `rec`, la fiche de la sanction.
```

## 2. Cherche
```lua
				return
			end
		else
			-- Le module n'est pas chargé
```
Remplace par
```lua
				return true
			end
		else
			-- Le module n'est pas chargé
```

## 3. Cherche
```lua
					"ugc_unverified", assetId, ugcData.name)
			end)
			return
		end
```
Remplace par
```lua
					"ugc_unverified", assetId, ugcData.name)
			end)
			return true
		end
		return false
		end
		if not revealLate and refuseIfRestricted() then return end
```

## 4. Cherche
```lua
		if actualPoints < ugcData.price then
			local pointsNeeded = ugcData.price - actualPoints
```
Remplace par
```lua
		if actualPoints < ugcData.price then
			-- 🤫 V4 : joueur privé d'UGC → pas de proposition Robux, juste « pas assez de points »
			if revealLate and _G.UGCRestrict and _G.UGCRestrict.IsRestricted(userId) then return end
			local pointsNeeded = ugcData.price - actualPoints
```

## 5. Cherche
```lua
			return
		end

		ugcPurchaseCooldown[globalKey] = now
```
Remplace par
```lua
			return
		end

		-- 🚫 V4 : il a assez de points → c'est maintenant qu'on lui montre la sanction
		if revealLate and refuseIfRestricted() then return end

		ugcPurchaseCooldown[globalKey] = now
```
