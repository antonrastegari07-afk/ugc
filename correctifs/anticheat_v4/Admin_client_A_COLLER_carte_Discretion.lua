		--──────────────────────────────────────────────────────────────
		-- 🤫 V4 — Discrétion et durée de vie des warnings (tous modes)
		--──────────────────────────────────────────────────────────────
		local _, dRows = card(body, 15, "🤫 DISCRÉTION ET DURÉE DES WARNINGS", VIOLET)

		toggleRow(dRows, 1, {
			title = "🤫 Le joueur ne voit rien de ses warnings",
			value = getDraft({ "silent" }, true) == true,
			onColor = VIOLET, path = { "silent" },
			desc = getDraft({ "silent" }, true) == true
				and "ACTIF — aucune carte, aucun retour en arrière, aucun kick d'avertissement. "
				.. "Le joueur ne sait pas qu'il est mesuré ; il ne l'apprend qu'au moment de "
				.. "la sanction. (Remplace les cases « carte orange » et « carte rouge » de "
				.. "l'onglet Messages.)"
				or "COUPÉ — les cartes de l'onglet Messages et la correction de position "
				.. "s'appliquent.",
			descColor = VIOLET,
		})

		stepper(dRows, 2, {
			title = "⏳ Un warning disparaît après",
			value = getDraft({ "warningExpiryDays" }, 30),
			path = { "warningExpiryDays" }, min = 0, max = 365, step = 5, color = VIOLET,
			format = function(v) return v == 0 and "jamais" or (v .. " j") end,
			desc = "Chaque warning s'efface tout seul ce nombre de jours après avoir été "
				.. "reçu. Ça protège le joueur qui a pris UN faux warning par erreur. "
				.. "Garde-le long (30 j conseillé) : un tricheur qui recommence en accumule "
				.. "bien avant.",
		})

		toggleRow(dRows, 3, {
			title = "🛒 Ne montrer la sanction qu'à l'achat",
			value = getDraft({ "modes", "ugc", "revealOnlyWhenAffordable" }, true) == true,
			onColor = VIOLET, path = { "modes", "ugc", "revealOnlyWhenAffordable" },
			desc = "Après le panneau affiché UNE fois à la sanction, le joueur ne le revoit "
				.. "que s'il essaie d'acheter une UGC qu'il pourrait se payer. Sans assez de "
				.. "points, il voit le message normal « pas assez de points », et on ne lui "
				.. "propose pas d'acheter des points en Robux.",
		})

