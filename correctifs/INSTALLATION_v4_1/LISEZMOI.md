# 🔫 Correctif v4.1 : plus de coils / jetpack qui « flashent » à la mort en PvP

À installer sur ta version 4.0 (3 scripts serveur, tout remplacer) :

| # | Où | Quoi faire | Fichier |
|---|---|---|---|
| 1 | ServerScriptService ▸ tp1v1_new_gestion | Remplacer tout | `tp1v1_new_gestion_COMPLET.lua` |
| 2 | ServerScriptService ▸ SessionToolCarry | Remplacer tout | `SessionToolCarry_COMPLET.lua` |
| 3 | ServerScriptService ▸ GamepassTools | Remplacer tout | `GamepassTools_SERVEUR.lua` |
| 4 | Page du jeu | Publier, puis **Shut down all servers** | — |

**Ce qui change :**
- Pendant l'arène, le StarterGear du joueur ne contient **que ses armes PvP**.
  Les outils de l'obby y sont mis de côté.
- À la mort, Roblox redonne donc directement les armes : plus de coils pendant une demi-seconde.
- À la sortie, tout revient comme avant, sans doublon.
