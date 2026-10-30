# ⏱️ Playtime Rewards — serveur v3 (sans cooldown entre deux claims)

**ServerScriptService ▸ Playtime reward** : remplace TOUT par `PlaytimeReward_SERVEUR.lua`.

- Plus de « 1 claim par seconde » : toutes les récompenses prêtes se récupèrent d'affilée.
- Toujours impossible de prendre une récompense deux fois (marquée prise avant de donner les points,
  sans attente entre la vérification et la marque).
- Anti-flood : 12 demandes d'un coup, puis 2/s.
- Le pays du joueur (minuit local) est lu une fois par session au lieu de 2 appels web par claim.
